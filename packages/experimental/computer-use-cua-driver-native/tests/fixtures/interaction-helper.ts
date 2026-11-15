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
  const cancelPath = join(root, 'cancel')
  const beginPath = join(root, 'begin')
  const helperPath = join(root, 'observer')
  const outcome = mode === 'sequence' ? 'restored' : mode
  const report = { type: 'finished', status: outcome, focus_restored: outcome === 'restored', pointer_restored: outcome === 'restored', before_pid: 1000, before_pointer: { x: 10, y: 20 }, after_pid: outcome === 'restored' ? 1000 : 2000, after_pointer: { x: 10, y: 20 }, outside_input: outcome !== 'restored', external_source_pids: outcome === 'restored' ? [] : [3000], driver_pid: 123, source_pid: 4000, destination_pid: 2000, activated_pids: [4000, 2000], focus_requested: outcome === 'restored', input_stopped: mode === 'interrupted', monitor_lost: false, blocked_driver_events: mode === 'interrupted' ? 10 : 0, delivered_driver_events: 3, driver_release_seen: true, interruption_reason: mode === 'interrupted' ? 'outside_input' : null, interrupted_at_ms: mode === 'interrupted' ? 10 : null, first_blocked_at_ms: mode === 'interrupted' ? 11 : null, last_delivered_at_ms: 9, button_released_at_ms: mode === 'interrupted' ? 12 : null, synthetic_buttons_released: true, native_drag_seen: false, native_drag_cancelled: false, cancel_sent: mode === 'interrupted' }
  const interrupted = { ...report, status: 'interrupted', focus_restored: false, pointer_restored: false, outside_input: true, external_source_pids: [0], input_stopped: true, blocked_driver_events: 10, interruption_reason: 'outside_input', interrupted_at_ms: 10, first_blocked_at_ms: 11, button_released_at_ms: 12, cancel_sent: true }
  const sequencePath = join(root, 'sequence')
  const quote = (value: string) => "'" + value.replaceAll("'", "'\\''") + "'"
  const focus = { type: 'focus', pid: 123, requested_window_id: null, resolved_window_id: 7,
    focused_window_id: mode === 'focus-competing' ? 9 : 7, front_window_id: mode === 'focus-competing' ? 9 : 7,
    eligible_window_ids: mode === 'focus-competing' ? [7, 9] : [7], ignored_control_window_ids: [8], unmapped_window_ids: [],
    verified: mode === 'focus-verified' || mode === 'sequence', reason: mode === 'focus-modal' ? 'modal_sheet_present' : mode === 'focus-competing' ? 'different_focused_window' : 'verified_ax_window' }
  // This fixture owns only stdio; shell builtins avoid unrelated Node cold-start timing.
  await writeFile(helperPath, `#!/bin/sh
printf '%s' "$$" > ${quote(pidPath)}
if [ "$1" = '--inspect-focus' ]; then
 case "$3" in
  0) printf '%s\\n' ${quote(JSON.stringify(focus))};;
  *) printf '%s\\n' ${quote(JSON.stringify({ ...focus, requested_window_id: 7 }))};;
 esac
 exit 0
fi
while IFS= read -r line; do
case "$line" in
 *begin*)
  printf '%s' "$line" > ${quote(beginPath)}
  ${mode === 'unavailable' ? "printf '%s\\n' '{\"type\":\"unavailable\"}'; exit 0" : "printf '%s\\n' '{\"type\":\"ready\",\"protocol\":2}'"}
  printf '%s\\n' '{"type":"progress","phase":"pressed","elapsed_ms":1}'
 ;;
 *cancel*) printf '%s' '1' > ${quote(cancelPath)};;
 *) ${mode === 'hang' ? ':' : `if ${mode === 'sequence' ? `[ -f ${quote(sequencePath)} ]` : 'false'}; then printf '%s\\n' ${quote(JSON.stringify(interrupted))}; else printf '%s\\n' ${quote(JSON.stringify(report))}; printf '1' > ${quote(sequencePath)}; fi; exit 0`};;
esac
done
`)
  await chmod(helperPath, 0o700)
  return { config: { helperPath, timeoutMs: 5000, pollMs: 20, leaseMs: 30000 },
    root, pidPath, cancelPath, beginPath }
}
