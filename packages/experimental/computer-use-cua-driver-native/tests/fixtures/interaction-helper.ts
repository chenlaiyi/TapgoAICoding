/** External native observer fixture; it never reads or changes a desktop. */
import { mkdtemp, writeFile, chmod } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

/**
 * Create an executable implementing only the observer stdio protocol.
 * @param mode - Reported outcome, or a deliberate protocol failure.
 * @returns Owned root and process configuration; remove the root only after all leases close.
 */
export async function createInteractionFixture(mode = 'restored') {
  const root = await mkdtemp(join(tmpdir(), 'dsh-interaction-test-'))
  const pidPath = join(root, 'pid')
  const helperPath = join(root, 'observer')
  const report = { type: 'finished', status: mode, focus_restored: mode === 'restored', pointer_restored: mode === 'restored', before_pid: 1000, before_pointer: { x: 10, y: 20 }, after_pid: mode === 'restored' ? 1000 : 2000, after_pointer: { x: 10, y: 20 }, outside_input: mode !== 'restored', external_source_pids: mode === 'restored' ? [] : [3000], driver_pid: 123, source_pid: 4000, destination_pid: 2000, activated_pids: [4000, 2000], focus_requested: mode === 'restored' }
  const quote = (value: string) => "'" + value.replaceAll("'", "'\\''") + "'"
  // This fixture owns only stdio; shell builtins avoid unrelated Node cold-start timing.
  await writeFile(helperPath, `#!/bin/sh
printf '%s' "$$" > ${quote(pidPath)}
while IFS= read -r line; do
case "$line" in
 *begin*)
  ${mode === 'unavailable' ? "printf '%s\\n' '{\"type\":\"unavailable\"}'; exit 0" : "printf '%s\\n' '{\"type\":\"ready\"}'"}
 ;;
 *) ${mode === 'hang' ? ':' : `printf '%s\\n' ${quote(JSON.stringify(report))}; exit 0`};;
esac
done
`)
  await chmod(helperPath, 0o700)
  return { config: { helperPath, timeoutMs: 5000, pollMs: 20, leaseMs: 30000 },
    root, pidPath }
}
