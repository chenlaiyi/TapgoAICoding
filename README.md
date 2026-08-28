# Tapgo AICoding

A native macOS SwiftUI front-end for the [OpenAI Codex Harness](https://github.com/openai/codex), hard-pinned to **MiniMax-M3** as the only available model. Powered by the harness's `app-server` JSON-RPC protocol over stdio — no shell-out, no exec-mode hacks. v0.5.1 targets the current server-request protocol validated against [Codex 0.150.1](https://github.com/openai/codex/releases/tag/rust-v0.150.1), and borrows recovery, compaction and fail-closed approval ideas from [DeepSeek Harness dsh-v0.1.1-rc.2](https://github.com/deepseek-ai/deepseek-harness/releases/tag/dsh-v0.1.1-rc.2) without embedding its Developer Preview Node/Python runtime.

```
┌──────────────────────────────────────────┐
│  SwiftUI App (this repo)                  │
│  ─ NavigationSplitView:                   │
│     Sidebar  ·  Chat  ·  Trajectory       │
│  ─ Composer (text + image, ⌘↩ to send)    │
│  ─ Persistent threads (resume across runs)│
│  ─ Streaming assistant deltas             │
│  ─ Inline tool calls, file changes, exec  │
└─────────────────┬────────────────────────┘
                  │ JSON-RPC over stdio
                  ▼
┌──────────────────────────────────────────┐
│  `codex app-server --listen stdio://`     │
│  ─ Initialize / thread/start / turn/start │
│  ─ Agent loop, sandbox, approval policy   │
│  ─ Turn / item / delta notifications      │
└─────────────────┬────────────────────────┘
                  │ HTTPS (OpenAI-compatible Responses API)
                  ▼
┌──────────────────────────────────────────┐
│  MiniMax-M3  (固定, only model available) │
│  https://api.minimaxi.com/v1              │
│  China endpoint — pin in config.toml      │
└──────────────────────────────────────────┘
```

## Why this stack

- **Codex Harness is the runtime** — agent loop, sandboxing, approvals, trajectory logging. We don't reinvent it; we just give it a Mac-native UI.
- **OpenAI-compatible API** — the harness's `model_provider` plugin accepts `base_url` + bearer token. Pin the URL to `api.minimaxi.com` and the harness itself doesn't change.
- **App-server mode** — unlike the legacy `codex exec` mode, the persistent JSON-RPC service gives us proper streaming deltas, per-item lifecycle, server-request approvals and tool-call notifications.
- **Recoverable context** — completed/failed turns resume the same harness thread; a pruned rollout falls back to a bounded local transcript instead of silently forgetting the conversation.
- **Fail-closed approvals** — current JSON-RPC approval request IDs are preserved and answered with `accept`/`decline`; unknown server requests are rejected rather than implicitly approved or left hanging.
- **Durable agent role and memory hygiene** — coding-agent instructions are always present; only stable, sanitized user/project facts are injected as memory, while reasoning traces, transient tasks and version snapshots are rejected.
- **Swift/SwiftUI** — true Mac app, no Electron, ~5 MB binary, fast startup.

## Hard isolation from the official Codex install

Tapgo AICoding never reads or writes anything under `~/.codex/`. All its state — config, auth, model catalog, session history — lives in a **dedicated** Codex home:

```
~/Library/Application Support/Tapgo AICoding/
└── codex/
    ├── auth.json                          (0600, MiniMax-M3 bearer)
    ├── config.toml                        (0600, model=+provider pinned)
    ├── model-catalogs/
    │   └── tapgo-catalog.json             (MiniMax-M3 only)
    └── sessions/                           (harness-side thread history)
```

Logs go to `~/Library/Logs/Tapgo AICoding/harness.log`.

The official `~/.codex/config.toml` and `~/.codex/auth.json` are not touched. The official Codex desktop app and CLI keep working exactly as they did before.

`init-tapgo.sh` never reads the official Codex home or its backups；凭据只来自用户显式提供的文件、环境变量或隐藏交互输入。

## Project layout

```
mac-codex-app/
├── Package.swift                       # SwiftPM executable target
├── scripts/
│   ├── init-tapgo.sh                   # write isolated config + auth + catalog
│   ├── build-app.sh                    # wrap binary in Tapgo AICoding.app
│   └── build-icon.sh
├── AppBuilder/
│   ├── Info.plist
│   ├── PkgInfo
│   ├── TapgoAICoding.entitlements      # no-sandbox (local use)
│   └── project.yml                     # xcodegen spec (optional)
├── Sources/TapgoAICoding/
│   ├── App.swift                       # @main + bootstrap
│   ├── Models/                         # Thread, Turn, TurnItem, ToolCall
│   ├── Services/
│   │   ├── TapgoConfig.swift           # isolated CODEX_HOME + template files
│   │   ├── CodexHarnessClient.swift    # JSON-RPC client over stdio
│   │   └── SessionStore.swift          # ObservableObject state
│   ├── Views/                          # Sidebar, Chat, Terminal, Diff, Approval, Trajectory
│   └── Resources/
│       └── L10n.swift
└── README.md
```

## Setup (one-time)

```bash
cd ~/TapgoAICoding
./scripts/init-tapgo.sh
```

The script will:

1. Check that the `codex` CLI is installed (Homebrew cask, ≥ 0.149.1). Resolution order is explicit `HARNESS_BIN`, Homebrew paths, `~/.local/bin/codex`, then `PATH`.
2. Read the MiniMax-M3 bearer token only from an explicit `--from-file` path, `MINIMAX_API_KEY` / `TAPGO_API_KEY`, or a hidden interactive prompt. The script never probes `~/.codex/` backups.
3. Store the selected key with mode `0600` in
   `~/Library/Application Support/Tapgo AICoding/codex/auth.json`.
4. Write the model catalog, `config.toml`, and verify by launching the
   harness with `CODEX_HOME=…` and confirming the `initialize` response
   reports the isolated `codexHome`.

After this runs:

- The official Codex desktop app and CLI keep using `~/.codex/`.
- Tapgo AICoding uses **only** the isolated `~/Library/Application Support/Tapgo AICoding/codex/`.
- Both can coexist without interference.

## Run

```bash
./scripts/build-app.sh
open 'Tapgo AICoding.app'
```

The script:

1. Runs `swift build -c release` (executable: `TapgoAICoding`).
2. Wraps the binary in `Tapgo AICoding.app` with a proper `Info.plist`,
   `PkgInfo`, and ad-hoc codesign.
3. Bundle id: `com.tapgo.aicoding`, display name: `Tapgo AICoding`.

After the first launch, the app stays open in your Dock with the icon
already familiar from `AppIcon.icns`.

**First launch**: macOS may show a Gatekeeper warning. Right-click the
app in Finder → Open → Open. After that, double-click works normally.

## What the app does

| Feature | Where it lives |
|---|---|
| Multi-thread sidebar (persistent harness thread ids) | `SidebarView` |
| Streaming assistant deltas | `CodexHarnessClient` → `SessionStore` → `ChatView`; animated typing dots (`StreamingIndicator`) while generating |
| Reasoning trace + summary | `reasoning/textDelta` trace + `reasoningSummaryTextDelta` summary, each in a collapsed disclosure |
| Assistant markdown-lite | fenced code blocks (copyable) + inline code + bold + strikethrough + headings + bullet/numbered/task lists + auto-linked URLs + blockquotes + horizontal rules + pipe tables + images (`![alt](url)`), via `MarkdownLite` → `MarkdownMessageView` |
| Copy assistant message | `CopyIconButton` in `MessageRow` (copies the full reply to the pasteboard) |
| Export conversation as Markdown | header `square.and.arrow.up` button → `TurnMarkdown.render` (all turns joined) |
| **MiniMax-M3 only** — no model picker; reasoning uses 默认/关闭/高 | `TapgoConfig.modelName` + `TapgoConfig.reasoningEffort`; `effort` is sent only on `turn/start` |
| Multimodal input (text + image) | `ComposerView` + `CodexHarnessClient.run(images:)` |
| Inline tool calls | `MessageRow` `.toolCall` case |
| Embedded terminal output | `CommandExecutionView` |
| File change preview | `FileChangeView` |
| Approval flow | configurable `approvalPolicy` (设置 → 运行); interactive 批准/拒绝 via `ApprovalRow` when the harness asks |
| Trajectory replay | `TrajectoryView` (detail pane), with per-turn status + start time + duration + filter (全部/命令/文件/错误/工具 via `TrajectoryFilter`); turns collapse (latest expanded) |
| Interrupt running turn | `turn/interrupt` JSON-RPC method via `ChatView` toolbar |
| Parallel conversations | each conversation owns an independent runner, queue, cancellation path, approval route, and visible run state; switching chats never interrupts another chat |
| Thread persistence + resume | `ThreadStore` persists `turns` + `harnessThreadId`; `sendUserMessage` resumes via `thread/resume` |
| Token usage per turn | `Turn.usage` (`TokenUsage`, parsed from `turn/completed`); caption in `ChatView` |
| Context meter + composer quick-switch | header color-coded `context N%` progress bar (`TokenUsage.contextLevel`); `ComposerView` sandbox + approval-policy menus (persisted) |
| In-chat search (⌘⇧F) | `Turn.matches(query:)` + `TurnItem.searchableText` (TapgoCore); `ChatView` search bar shows "X/Y" position, ⏎ jumps to next match, ⇧⏎ to previous; matches user input + assistant text + reasoning + command stdout/stderr + tool args/result + file path/diff + approval reason |
| Global font scale (设置 → 外观) | `AppFontScale` enum (small 0.85× / medium 1.00× / large 1.20×) + `AppFont.scaled(_:multiplier:)` central token in `TapgoCore`; SettingsView segmented picker + live preview; ChatView ⋮ 菜单提供同一切换; 通过 `@Environment(\.tapgoFontScale)` 注入到所有视图,改字号不破坏布局 (避开 `dynamicTypeSize` 在 macOS 上的不一致和 `scaleEffect` 撕裂布局) |

## Tests

```bash
TAPGO_SKIP_REMOTE_INTEGRATION=1 swift run TapgoTests
#   685/685 — must stay green (skipping SSH-integration; they need a
#   real remote codex host at 203.0.113.10 which is RFC 5737 TEST-NET-3)

# To run the FULL suite including SSH-integration (will fail without
# a real remote host — expected):
swift run TapgoTests

swift build                 # debug build
swift build -c release      # release build
```

We deliberately do **not** use XCTest or swift-testing — the
CommandLineTools Swift toolchain on this machine ships neither
framework. The `TapgoTests` executable target (`Sources/TapgoTests/`)
runs a custom `TestRunner` with `expect` / `expectEqual` / `expectThrows`
and a non-zero exit on any failure. Tests import the same `TapgoCore`
library the app uses, so they exercise the real validators, store
logic, and SSH argv builder — not a hand-rolled copy. The current
suite covers:

- **`RemoteCommandBuilder`**: path/host/user/command allow-lists
  (rejects `;`, `&&`, `$()`, newlines, NUL, overlong, …),
  `buildSshArgv` shape (`-o` BatchMode/ConnectTimeout/StrictHostKeyChecking,
  `user@host`, single-arg command), and rejection of every kind
  of bad input. The SSH argv is a remote-code-execution surface,
  so these are the most important assertions in the suite.
- **`Project` / `RemoteHost` / `WorkspaceState`**: the "no fake cwd"
  contract — a remote project's `displayPath` must mention the
  remote target while `harnessCwd` stays on the local mirror.
  Plus Codable round-trips.
- **`WorkspaceStore`**: dedup on add, 0700 dir / 0600 file
  permissions, `ensureRemoteMirrorExists` (the fix for the
  codex 0.149.0 unified-exec ENOENT), cascade on host removal.
- **`ThreadStore`**: per-id 0600 files, v0 → v1 one-time migration
  (with rename of the legacy `threads.json` to `threads.v0.json`
  so it never re-runs), and `turns`/`items` **are** persisted and
  round-trip (including a legacy file that lacks `turns`).
| Persistent threads | `thread/resume` JSON-RPC method, `Thread.harnessThreadId` |

## What Tapgo AICoding deliberately does NOT do

- **No model picker.** Only `MiniMax-M3` is exposed in the model
  catalog. Adding another model would require editing
  `TapgoConfig.modelName` + `tapgo-catalog.json`.
- **No arbitrary reasoning levels.** 设置仅提供服务端默认、`none`、`high`；
  非默认值只在 `turn/start` 发送，旧的 `low` / `medium` 持久值会自动迁移。
- **No edits to `~/.codex/`.** The official Codex install is treated
  as an unrelated program；初始化只接受显式 `--from-file`、环境变量或隐藏交互输入，
  不扫描任何官方配置或历史备份。
- **No app-server token store.** Tokens live in
  `~/Library/Application Support/Tapgo AICoding/codex/auth.json`
  (0600), not in Keychain — keep parity with how `codex` itself stores
  them.

## Configuration knobs

All in `~/Library/Application Support/Tapgo AICoding/codex/config.toml` (written by `init-tapgo.sh`):

| Field | Value (pinned) |
|---|---|
| `model` | `MiniMax-M3` |
| `model_provider` | `minimax` |
| `[model_providers.minimax].base_url` | `https://api.minimaxi.com/v1` (China) |
| `model_catalog_json` | `…/model-catalogs/tapgo-catalog.json` |

> Approval policy and sandbox mode are **runtime** settings (not
> `config.toml`): they're persisted in `UserDefaults` and passed to
> `thread/start`. Change them in 设置 → 运行 or via the composer chips.
> The provider **endpoint (base URL)** is also editable in 设置 → 运行 —
> an override is written into `config.toml` (`TapgoConfig.applyBaseURL`)
> and takes effect on the next harness run.

To switch regions temporarily, pass `TAPGO_BASE_URL=…` to
`init-tapgo.sh` (the script will reuse whatever you set).

## Limitations / next steps

- **Thread persistence ✔** — threads and their `turns`/`items` are
  persisted under `state/v1/threads/<id>.json` and reloaded on launch,
  so the sidebar and chat history survive an app restart. The on-disk
  copy is the source of truth for the visible conversation (we don't
  re-fetch historical items from the harness).
- **Thread resume ✔** — a reopened thread keeps its `harnessThreadId`;
  sending a message resumes the harness-side session via `thread/resume`
  instead of starting a new one.
- **Reasoning trace + summary** — the raw `reasoning/textDelta` trace is
  kept (collapsed behind a "思考过程" disclosure), and the condensed
  `reasoningSummaryTextDelta` summary streams into its own collapsed
  "思考摘要" disclosure. The final `reasoning/summary` array is only used
  to fill the trace when nothing streamed.
- **Approvals are configurable, default off** — the app ships with
  `approvalPolicy: never` (auto-approve). Select **询问** (on-request) in
  设置 → 运行 to let the harness pause and ask you to 批准/拒绝 commands,
  file changes, and tool calls inline. The wire format for the request
  and response is best-effort across codex versions; if a stricter
  policy ever hangs a turn, switch back to **永不询问** (or hit 中断).

## Troubleshooting

- **App shows "首次运行" setup screen** → you haven't run
  `scripts/init-tapgo.sh` yet (or `auth.json` is missing/empty). Run
  it, then click the **重新检查** button in the setup screen.
- **Harness exits immediately** → check
  `tail -f ~/Library/Logs/Tapgo\ AICoding/harness.log`. Most often
  this is a wrong key or a 402 from the upstream API.
- **"Model provider `minimax` not found"** → your
  `~/Library/Application Support/Tapgo AICoding/codex/config.toml` is
  stale or was hand-edited. Re-run `scripts/init-tapgo.sh`.
- **App is damaged / Gatekeeper warning** → right-click in Finder →
  Open → Open. (We ad-hoc codesign for local use; a stricter
  Gatekeeper policy may still want the explicit click-through once.)
- **Build fails on macOS < 14** → `Package.swift` requires Sonoma.

---

## Self-evolution loop

Once a feature ships, the agent (this Codex instance, talking to itself
through `codex app-server`) can keep iterating on the codebase without
manual file editing. Every iteration goes through a single gated
pipeline:

```bash
./scripts/evolve.sh patch \
  "fix: sidebar crash on empty workspace" \
  "Root cause: SidebarView assumed ≥1 project; guard with empty state."
```

That one command:

1. Bumps `AppBuilder/Info.plist` (`CFBundleShortVersionString` + `CFBundleVersion`)
2. Runs `swift build -c release` — aborts on failure
3. Runs `swift run TapgoTests` — aborts on any red test
4. Appends a section to `EVOLUTION.md`
5. Commits + creates an annotated git tag `vX.Y.Z`
6. `git push origin main --tags`
7. Rebuilds `Tapgo AICoding.app` from the new binary
8. Writes `~/Library/Application Support/Tapgo AICoding/state/evolution_state.json`
9. Prints a summary block + the rollback command

If steps 2 or 3 fail, Info.plist is reverted and nothing is committed.

### Restart-and-resume across iterations

```bash
./scripts/restart-and-resume.sh
```

This gracefully kills the current `Tapgo AICoding.app` process, relaunches
the freshly-built bundle, and prints the path to the state file the
new session should read to recover context.

Because the underlying `codex app-server` persists threads (via
`thread/resume`), and the state file persists the **next-action list**
+ last commit SHA + version, an iteration that gets cut off mid-task
can be picked up in a new conversation turn after a restart.

### Hard rollback at any time

```bash
git checkout v0.3.7
./scripts/build-app.sh
./scripts/restart-and-resume.sh
```

Every shipped iteration is a git tag pushed to `origin/main`, so
GitHub itself is the backup. To go back two versions: pick the
older tag, check it out, rebuild, restart.

### What the agent must NEVER do

- Edit `~/.codex/` — Tapgo AICoding uses only the isolated
  `~/Library/Application Support/Tapgo AICoding/codex/`.
- Bump a **major** version without explicit user approval.
- Commit a tag whose tests are not green.
- Push while `git status` is dirty in untracked files.
