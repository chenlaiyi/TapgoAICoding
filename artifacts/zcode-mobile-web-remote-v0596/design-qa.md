# ZCode Mobile Web Remote — Design QA

## Source truth

- Reference: `/Applications/ZCode.app` → `移动端远程控制` → live Web Remote session.
- Capture: Codex Computer Use browser trace, tab 1, current run; no session URL or QR credential is persisted.
- Viewport: `393 × 852` CSS px.
- States captured: workspace/task home; expanded `TapgoAICoding` workspace; long task conversation with sticky composer.

## Implementation

- Preview source: `Sources/TapgoCore/Resources/PhoneRemote/preview.html?preview=1` (temporary QA harness; removed before release).
- Production sources: `Sources/TapgoCore/Resources/PhoneRemote/index.html`, `app.css`, `app.js`.
- Capture: Codex Computer Use browser trace, tab 4, current run.
- Viewport: `393 × 852` CSS px.
- States captured: workspace home, expanded/collapsed workspace, task conversation, model sheet, computer-control drawer, dark/light theme.

## Comparison history

### Pass 1 — blocked

- Home exposed the composer even though no task conversation was visible.
- Workspace cards lacked folder identity, project path, inline create action and a clear disclosure affordance.
- The task header compressed navigation, title and computer control into one row.
- Conversation typography was too small and left excessive unused vertical space.

### Pass 2 — passed

- Home now follows the same hierarchy as ZCode: device header → notice → workspace/task summary → expandable project cards.
- The composer is hidden by both view state and a mobile CSS invariant while on the home view.
- Expanded tasks use compact rows, relative time, selected indicator and quiet running/completed status pills.
- Task view uses a 48 px navigation row plus a 48 px task context row, matching ZCode's two-level orientation.
- Assistant output is a flat reading stream with 16 px mobile type, 1.72 line-height, restrained heading rhythm, responsive code/table blocks and no assistant card chrome.
- The composer is a compact bordered surface with attachment, control, model and send actions; safe-area padding is retained.
- All critical actions remain reachable with accessible labels; project/task names and paths still use `textContent`.

### Pass 3 — passed

- Validation against the installed App's real state exposed 22 legacy tasks with no `projectId`; the total said 34 tasks while only 12 were reachable.
- Legacy tasks now resolve to an existing workspace by longest matching `cwd`; remaining historical paths receive their own read-only workspace card, and tasks without any path enter `未分类任务`.
- Synthetic historical groups deliberately omit the new-task button, while task selection remains available.
- The visible workspace counts now reconcile with the task total instead of silently dropping legacy conversations.

### Pass 4 — passed

- The 393 × 852 comparison was repeated for the task stream, bottom composer, model sheet and computer-control drawer; the new panels preserve the same compact dark hierarchy and touch targets instead of introducing desktop settings chrome.
- The model sheet now receives the real ProviderRegistry whitelist, groups models by provider, marks the current choice, disables unconfigured providers and switches the model used by new tasks without interrupting a running task.
- The browser receives no API key or provider endpoint; it only receives stable IDs, display names and a configured boolean.
- Computer control now exposes three distinct states: the App-level remote-control switch, Screen Recording, and Accessibility. Each permission has a live readback and a focused Mac System Settings action.
- Disabling computer control takes effect immediately. Re-enabling from the phone deliberately requires an explicit confirmation dialog on the Mac, and macOS TCC consent can never be granted by the phone.
- Mobile interaction QA switched the preview from GLM-5.3 to GLM-5.3-Flash, then disabled computer control and verified that screen, keyboard, media and system actions all became unavailable.

## Functional checks

- Return to task home: passed.
- Home composer absence: passed.
- Expand/collapse all workspaces: passed.
- Task selection and conversation rendering: passed.
- Theme cycling: passed.
- Model sheet: passed.
- Real provider/model grouping, configured-state and selection transition: passed.
- Computer-control drawer and screen/keyboard/media/system controls: passed.
- Remote-control disable confirmation and disabled-action state: passed.
- macOS Screen Recording / Accessibility guidance and status UI: passed.
- JavaScript syntax: passed (`node --check`).
- Swift regression suite: passed (`2745 passed, 0 failed`) after model, permission and control-setting route assertions are included.

## Final result

passed
