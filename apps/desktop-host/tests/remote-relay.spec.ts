import { execFileSync } from 'node:child_process'
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir, userInfo } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { relayDeviceId, remoteRelayOrigin, remoteRelayToml, resolveRemoteRelay } from '../src/remote-relay.ts'

const directories: string[] = []
afterEach(() => { for (const directory of directories.splice(0)) rmSync(directory, { recursive: true, force: true }) })

function fixture() {
  const directory = mkdtempSync(join(tmpdir(), 'tapgo-relay-test-'))
  directories.push(directory)
  const tokenFile = join(directory, 'token')
  const executable = join(directory, 'frpc')
  writeFileSync(tokenFile, 'fixture-token', { mode: 0o600 })
  writeFileSync(executable, '', { mode: 0o700 })
  if (process.platform === 'win32') {
    execFileSync('icacls.exe', [tokenFile, '/inheritance:r', '/grant:r', `${userInfo().username}:F`])
  }
  return { directory, tokenFile, executable }
}

describe('managed mobile relay', () => {
  it('gives one Mac a stable, unpredictable origin without a per-Mac DNS record', () => {
    const { directory, tokenFile, executable } = fixture()
    const config = resolveRemoteRelay({ TAPGO_RELAY_DOMAIN: 'remote.itapgo.com',
      TAPGO_RELAY_SERVER: 'relay.itapgo.com', TAPGO_RELAY_TOKEN_FILE: tokenFile,
      TAPGO_FRPC_PATH: executable }, join(directory, 'state'), executable)!
    const first = relayDeviceId(config.stateDirectory)
    expect(first).toMatch(/^[a-f0-9]{32}$/u)
    expect(relayDeviceId(config.stateDirectory)).toBe(first)
    expect(readFileSync(join(config.stateDirectory, 'device-id'), 'utf8')).toBe(`${first}\n`)
    expect(remoteRelayOrigin(config, first)).toBe(`https://${first}.remote.itapgo.com`)
    expect(remoteRelayToml(config, first)).toContain(`subdomain = "${first}"`)
    expect(remoteRelayToml(config, first)).toContain('transport.protocol = "wss"')
    expect(remoteRelayToml(config, first)).toContain('loginFailExit = false')
    expect(remoteRelayToml(config, first)).not.toContain('fixture-token')
  })

  it('rejects invalid public authorities and missing enrollment credentials before pairing', () => {
    const { directory, tokenFile, executable } = fixture()
    const base = { TAPGO_RELAY_DOMAIN: 'remote.itapgo.com', TAPGO_RELAY_SERVER: 'relay.itapgo.com',
      TAPGO_RELAY_TOKEN_FILE: tokenFile, TAPGO_FRPC_PATH: executable }
    expect(() => resolveRemoteRelay({ ...base, TAPGO_RELAY_DOMAIN: 'example.com/path' }, directory, executable)).toThrow()
    expect(() => resolveRemoteRelay({ ...base, TAPGO_RELAY_SERVER: '127.0.0.1' }, directory, executable)).toThrow()
    expect(() => resolveRemoteRelay({ ...base, TAPGO_RELAY_TOKEN_FILE: join(directory, 'missing') }, directory, executable)).toThrow()
    if (process.platform === 'win32') {
      execFileSync('icacls.exe', [tokenFile, '/grant', '*S-1-1-0:R'])
      expect(() => resolveRemoteRelay(base, directory, executable)).toThrow('private Windows ACL')
      execFileSync('icacls.exe', [tokenFile, '/remove:g', '*S-1-1-0'])
    } else {
      chmodSync(tokenFile, 0o644)
      expect(() => resolveRemoteRelay(base, directory, executable)).toThrow('owner-only')
      chmodSync(tokenFile, 0o600)
    }
    expect(() => remoteRelayOrigin(resolveRemoteRelay(base, directory, executable)!, '../other')).toThrow()
  })
})
