/** Outbound FRP connection that gives one Desktop Host a stable public origin. */

import { randomBytes } from 'node:crypto'
import { execFileSync, spawn, type ChildProcess } from 'node:child_process'
import { accessSync, chmodSync, constants, existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { join, resolve } from 'node:path'

const DEVICE_ID = /^[a-f0-9]{32}$/u
const DOMAIN = /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}$/u

/** Explicit server and token settings for a managed mobile relay. */
export interface RemoteRelayConfig {
  readonly domain: string
  readonly server: string
  readonly port: number
  readonly tokenFile: string
  readonly executable: string
  readonly stateDirectory: string
}

/** Validate relay settings before creating a public pairing link.
 * @param environment - Desktop Host launch environment.
 * @param stateDirectory - Owner-only local relay state directory.
 * @param packagedExecutable - FRP executable carried by the app.
 * @returns A relay configuration, or undefined when the relay is disabled.
 */
export function resolveRemoteRelay(
  environment: NodeJS.ProcessEnv, stateDirectory: string, packagedExecutable: string,
): RemoteRelayConfig | undefined {
  const domain = environment.TAPGO_RELAY_DOMAIN
  if (domain === undefined) return undefined
  const server = environment.TAPGO_RELAY_SERVER
  const tokenFile = environment.TAPGO_RELAY_TOKEN_FILE
  const port = Number(environment.TAPGO_RELAY_PORT ?? '443')
  const executable = environment.TAPGO_FRPC_PATH ?? packagedExecutable
  if (!DOMAIN.test(domain) || server === undefined || !DOMAIN.test(server)
    || tokenFile === undefined || !Number.isSafeInteger(port) || port < 1 || port > 65535) {
    throw new Error('Tapgo mobile relay requires a valid domain, server, token file, and port')
  }
  if (!existsSync(tokenFile)) throw new Error('Tapgo mobile relay token file is missing')
  if (process.platform === 'win32') {
    const result = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
      '$ErrorActionPreference = "Stop"; Import-Module ($PSHOME + "/Modules/Microsoft.PowerShell.Security/Microsoft.PowerShell.Security.psd1"); $acl = Get-Acl -LiteralPath $env:TAPGO_RELAY_ACL_PATH; '
      + '$owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value; '
      + '$current = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value; '
      + '$allowed = @($current, "S-1-5-18", "S-1-5-32-544"); '
      + 'if ($owner -notin $allowed) { throw "Unexpected relay token owner" }; '
      + '$unsafe = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]) '
      + '| Where-Object { $_.AccessControlType -eq "Allow" -and $_.IdentityReference.Value -notin $allowed }); '
      + 'if ($unsafe.Count -gt 0) { "unsafe" } else { "private" }'],
    { encoding: 'utf8', env: { ...process.env, TAPGO_RELAY_ACL_PATH: resolve(tokenFile) }, windowsHide: true }).trim()
    if (result !== 'private') throw new Error('Tapgo mobile relay token file must have a private Windows ACL')
  } else if ((statSync(tokenFile).mode & 0o077) !== 0) {
    throw new Error('Tapgo mobile relay token file must be owner-only')
  }
  if (!existsSync(executable)) throw new Error('Tapgo mobile relay client executable is missing')
  accessSync(executable, constants.X_OK)
  return { domain, server, port, tokenFile: resolve(tokenFile), executable, stateDirectory }
}

/** Read or create a stable unpredictable device ID.
 * @param directory - Local private state directory.
 * @returns Lowercase 128-bit device ID.
 */
export function relayDeviceId(directory: string): string {
  mkdirSync(directory, { recursive: true, mode: 0o700 })
  chmodSync(directory, 0o700)
  const path = join(directory, 'device-id')
  if (existsSync(path)) {
    const id = readFileSync(path, 'utf8').trim()
    if (!DEVICE_ID.test(id)) throw new Error('Tapgo mobile relay device ID is invalid')
    return id
  }
  const id = randomBytes(16).toString('hex')
  try {
    writeFileSync(path, `${id}\n`, { flag: 'wx', mode: 0o600 })
    return id
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'EEXIST') return relayDeviceId(directory)
    throw error
  }
}

/** Render a private FRP configuration for one local Host.
 * @param config - Validated relay settings.
 * @param id - Stable device ID.
 * @param localPort - Listening Host port.
 * @returns TOML consumed only by frpc.
 */
export function remoteRelayToml(config: RemoteRelayConfig, id: string, localPort: number): string {
  if (!DEVICE_ID.test(id)) throw new Error('Tapgo mobile relay device ID is invalid')
  return [
    `serverAddr = ${JSON.stringify(config.server)}`,
    `serverPort = ${String(config.port)}`,
    'loginFailExit = false',
    'auth.method = "token"',
    'auth.tokenSource.type = "file"',
    `auth.tokenSource.file.path = ${JSON.stringify(config.tokenFile)}`,
    'transport.protocol = "wss"',
    'transport.tls.enable = true',
    `transport.tls.serverName = ${JSON.stringify(config.server)}`,
    ...(process.platform === 'darwin' ? ['transport.tls.trustedCaFile = "/etc/ssl/cert.pem"'] : []),
    `clientID = ${JSON.stringify(id)}`,
    '[[proxies]]',
    `name = ${JSON.stringify(`tapgo-${id}`)}`,
    'type = "http"',
    'localIP = "127.0.0.1"',
    `localPort = ${String(localPort)}`,
    `subdomain = ${JSON.stringify(id)}`,
    '',
  ].join('\n')
}

/** Running relay child; close waits for process termination.
 * @param child - Owned frpc child process.
 * @returns An asynchronous close operation.
 */
export function relayCloser(child: ChildProcess): () => Promise<void> {
  return async () => {
    if (child.exitCode !== null || child.signalCode !== null) return
    await new Promise<void>((resolve) => {
      const timer = setTimeout(() => { child.kill('SIGKILL') }, 5_000)
      child.once('exit', () => { clearTimeout(timer); resolve() })
      child.kill('SIGTERM')
    })
  }
}

/** Start the outbound relay after the Host begins listening.
 * @param config - Validated relay settings.
 * @param id - Stable device ID.
 * @param localPort - Listening Host port.
 * @returns A close operation for Desktop shutdown.
 */
export function startRemoteRelay(config: RemoteRelayConfig, id: string, localPort: number): () => Promise<void> {
  const path = join(config.stateDirectory, 'frpc.toml')
  writeFileSync(path, remoteRelayToml(config, id, localPort), { mode: 0o600 })
  chmodSync(path, 0o600)
  const child = spawn(config.executable, ['-c', path], { stdio: ['ignore', 'ignore', 'pipe'], windowsHide: true })
  child.stderr.on('data', (chunk: Buffer) => {
    const message = chunk.toString('utf8').trim()
    if (message !== '') console.error(`Tapgo mobile relay: ${message}`)
  })
  child.on('error', (error) => { console.error('Tapgo mobile relay failed to start:', error) })
  child.on('exit', (code, signal) => {
    if (code !== 0 && signal !== 'SIGTERM') console.error(`Tapgo mobile relay exited: ${String(code ?? signal)}`)
  })
  return relayCloser(child)
}

/** Public origin for one relay device.
 * @param config - Validated relay settings.
 * @param id - Stable device ID.
 * @returns HTTPS origin for Host trust and pairing.
 */
export function remoteRelayOrigin(config: RemoteRelayConfig, id: string): string {
  if (!DEVICE_ID.test(id)) throw new Error('Tapgo mobile relay device ID is invalid')
  return `https://${id}.${config.domain}`
}
