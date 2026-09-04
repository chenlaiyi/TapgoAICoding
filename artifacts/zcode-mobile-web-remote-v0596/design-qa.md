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

## Functional checks

- Return to task home: passed.
- Home composer absence: passed.
- Expand/collapse all workspaces: passed.
- Task selection and conversation rendering: passed.
- Theme cycling: passed.
- Model sheet: passed.
- Computer-control drawer and screen/keyboard/media/system controls: passed.
- JavaScript syntax: passed (`node --check`).
- Swift regression suite: passed (`2728 passed, 0 failed`) after the final assertions are included.

## Final result

passed
