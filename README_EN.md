# Tapgo AICoding

[简体中文](README.md) | **English**

Tapgo AICoding is a native macOS SwiftUI coding-agent client. It uses the [OpenAI Codex Harness](https://github.com/openai/codex) `app-server` as its runtime and manages conversations, tools, approvals, file changes, and command execution over persistent JSON-RPC. The desktop workspace is designed for multiple projects, long-running tasks, and development across several Macs.

Current version: **v0.5.56** · macOS 14+

## Current capabilities

| Area | Implemented capabilities |
| --- | --- |
| Coding workspace | Local projects, SSH projects, pinned projects, directory selection, remote browsing, and persistent workspace state |
| Agent conversations | Streaming replies, reasoning summaries, tool calls, command output, file diffs, approvals, trajectory replay, interruption, and retry |
| Concurrency and queueing | Multiple conversations run independently; messages within one conversation can be queued, reordered, removed, sent immediately, or steered into the active turn |
| Models | MiniMax M3, GLM 5.3 Flash, DeepSeek V4 Flash / Pro, plus custom OpenAI Responses-compatible models |
| Model usage | MiniMax / GLM plan limits, DeepSeek balance, context usage, and consistent remaining-capacity presentation |
| Input and content | Text, screenshots, image attachments, Markdown, code blocks, tables, task lists, links, and images |
| Search and export | In-conversation search, global conversation search, message copy, and full Markdown export |
| Computer use | Dedicated `Tapgo Computer Use.app` helper, 11 Codex-compatible primary tools, 8 legacy aliases, AX state/screenshots, semantic actions, mouse/keyboard, clipboard, and drag |
| Phone remote | QR-launched H5 controller over LAN, Tailscale, or an optional public relay; project/thread switching, messaging, image upload, and computer control |
| Memory | USER / GLOBAL / KEY durable memory layers, independent read/write controls, consolidation, size limits, and iCloud Drive sync across Macs |
| Plugins | Browse, install, enable, disable, and remove official Codex plugins and supported DeepSeek Harness plugins |
| Self-evolution | Dedicated evolution conversation, version history, build/test/commit/tag workflow, recoverable state, and rollback |
| Interface | Light/dark/system appearance, global font scale, settings center, shortcuts, command palette, and adaptive layout |

## Architecture

```text
┌─────────────────────────────────────────────────────────┐
│ Tapgo AICoding.app                                      │
│ SwiftUI Workspace · Chat · Settings · Trajectory · Phone│
└──────────────────────────┬──────────────────────────────┘
                           │ JSON-RPC over stdio
┌──────────────────────────▼──────────────────────────────┐
│ codex app-server                                        │
│ Thread / Turn · Agent Loop · Approval · Tool Events     │
└───────────────┬───────────────────────────┬─────────────┘
                │ Responses API             │ MCP
┌───────────────▼────────────────┐  ┌───────▼────────────────────┐
│ MiniMax / GLM / DeepSeek       │  │ Tapgo Computer Use.app     │
│ or a custom compatible model   │  │ Screen · UI · Mouse · Keys │
└────────────────────────────────┘  └────────────────────────────┘
```

Tapgo AICoding does not implement a second agent runtime. It uses the Codex Harness conversation, tool, sandbox, and approval protocols directly. Each conversation owns an independent runner, so switching views or conversations does not stop other active tasks.

## Requirements

- macOS 14 Sonoma or later.
- Swift 5.9. Building the full app requires a macOS SDK that includes the SwiftUI macro plugin. The build script defaults to `macosx26.5`; override it with `TAPGO_SDK` when needed.
- Codex CLI 0.149.1 or later.
- At least one supported model and API key.
- Computer use requires Accessibility and Screen Recording permission for the dedicated helper in macOS Privacy & Security settings.

## Quick start

### 1. Clone

```bash
git clone https://github.com/chenlaiyi/TapgoAICoding.git
cd TapgoAICoding
```

### 2. Initialize the isolated Codex home

```bash
./scripts/init-tapgo.sh
```

The initializer:

1. Checks the Codex CLI version.
2. Reads a MiniMax key from hidden input, an environment variable, or an explicit `--from-file` path.
3. Creates an isolated `config.toml`, `auth.json`, and model catalog.
4. Launches `codex app-server` and verifies that the isolated home is active.

Environment-variable and explicit-file examples:

```bash
MINIMAX_API_KEY='…' ./scripts/init-tapgo.sh
./scripts/init-tapgo.sh --from-file /path/to/key-file
```

The script never scans or migrates credentials from the official `~/.codex/` directory.

### 3. Build and run

```bash
./scripts/build-app.sh
open 'Tapgo AICoding.app'
```

The build bundles:

- The `TapgoAICoding` executable.
- The `TapgoComputerUseMCP` executable.
- A dedicated `Tapgo Computer Use.app` helper with its own bundle identity.
- Plists, icons, entitlements, and ad-hoc code signatures.

If Gatekeeper warns on first launch, right-click the app in Finder and choose Open.

### 4. Sign in and configure

After launch:

1. Sign in with an authorized Tapgo administrator account.
2. Add a local project or configure an SSH host in Settings.
3. Choose a model, update built-in credentials, or add a custom model under Settings → Models.
4. Review approval and sandbox settings under Settings → General.
5. If computer use is needed, enable it under Settings → Computer Use and complete macOS authorization.

Model and execution-policy changes apply to new conversations. Existing conversations retain the model and policy with which they were created.

## Models and credentials

### Built-in models

| Display name | Provider | Endpoint type | Credential file |
| --- | --- | --- | --- |
| MiniMax M3 | `minimax` | OpenAI Responses compatible | `auth.json` |
| GLM 5.3 Flash | `glm` | BigModel Responses | `auth-glm.json` |
| DeepSeek V4 Flash | `deepseek` | DeepSeek Responses | `auth-deepseek.json` |
| DeepSeek V4 Pro | `deepseek` | DeepSeek Responses | `auth-deepseek.json` |

Custom models can define a display name, brand, API model ID, base URL, API key, and context window in Settings. Tapgo AICoding writes an isolated model registry and generates the matching provider configuration; source changes are not required.

All model configuration lives under:

```text
~/Library/Application Support/Tapgo AICoding/codex/
```

Credential and configuration files use `0600` permissions. Never copy them into the repository or expose keys in issues, logs, or screenshots.

## Computer use

Since v0.5.46, the dedicated `Tapgo Computer Use.app` helper owns the real macOS TCC identity. Computer-control permissions are no longer borrowed from the main app, Terminal, or another host process.

Since v0.5.55, the primary tools match the Codex Computer Use names and argument semantics:

```text
click   drag   get_app_state   list_apps   paste
perform_secondary_action   press_key   scroll   select_text
set_value   type_text
```

Capabilities include transparent app launching and targeting; combined AX-tree and window-screenshot state; differential state by default and full state with `disableDiff=true`; element- or window-point clicks; left/right/middle buttons and multi-click; drag; element/coordinate horizontal and vertical scrolling; xdotool-style keys; text/Markdown/HTML paste with clipboard restoration; exact text selection/cursor placement; and only the secondary AX actions explicitly exposed by an element. The legacy aliases `list_applications`, `click_element`, `set_element_value`, `screenshot`, `get_screen_size`, `left_click`, `double_click`, and `open_application` remain available.

To enable computer use:

1. Open Settings → Computer Use.
2. Turn on Enable Computer Use.
3. Open Accessibility and Screen Recording settings.
4. Follow the in-app instructions and drag the actual helper app into the relevant allow lists.
5. Return to Tapgo AICoding and re-check. Start a new conversation or restart the harness before use.

Secure text fields never expose their real contents through the Accessibility tree. Permission state, helper state, and MCP registration are read independently; one does not prove the others.

## Phone remote control

Connect Phone starts a short-lived tokenized HTTP service on the Mac and generates a QR code. Scanning it opens the H5 controller directly in the phone browser; no native mobile app is required.

The H5 controller can:

- Show projects, conversations, transcript content, and run state.
- Switch projects or conversations, create a conversation, and send messages.
- Upload images and display conversation images.
- Select a model and show the current friendly model name.
- When authorized, capture the screen, click, scroll, type, send function keys, and lock or sleep the Mac.
- Connect over the same Wi-Fi, Tailscale, or an optional deployed relay.

Treat the URL token as a temporary access credential. Stop the service or rotate the QR code when it is no longer needed. The native client under `mobile/ios/` remains experimental; the QR-launched H5 controller is the current recommended mobile path.

## Memory and cross-device sync

Memory files live under:

```text
~/Library/Application Support/Tapgo AICoding/memory/
├── user.md          # cross-project user preferences
├── memory.md        # global environment and tool facts
└── keys/            # branch-scoped project memory
```

Settings provide independent read, write, and iCloud Drive sync controls. Only memory Markdown files are synced; API keys, repositories, and full conversations are excluded. Writes are sanitized, deduplicated, and size-limited. Temporary tasks, reasoning traces, credentials, and version snapshots should not enter durable memory.

## Data and security boundaries

Tapgo AICoding and the official Codex installation use separate homes:

```text
Official Codex       ~/.codex/
Tapgo AICoding       ~/Library/Application Support/Tapgo AICoding/codex/
Application state    ~/Library/Application Support/Tapgo AICoding/state/v1/
Application logs     ~/Library/Logs/Tapgo AICoding/harness.log
```

- Official Codex configuration and authentication files are not read or rewritten.
- Conversations are persisted as per-ID files with `0600` permissions.
- Approval modes: never ask, ask on request, or ask only for untrusted actions.
- Sandbox modes: read-only, workspace-write, or full access.
- The default full-access + auto-approve configuration is convenient for trusted local development but has the largest risk surface. Tighten it for unfamiliar repositories.
- Public commits must never contain `.env`, `auth*.json`, private keys, certificates, tokens, or production deployment credentials.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘N` | New conversation |
| `⇧⌘N` | New task with directory picker |
| `⌘O` | Open local directory |
| `⌘,` | Open Settings |
| `⌘↩` | Send or steer into the active turn |
| `⌘.` | Interrupt active task |
| `⇧⌘R` | Retry the previous turn |
| `⇧⌘F` | Find in the current conversation |
| `⌘K` | Focus conversation search |
| `⇧⌘P` | Open command palette |
| `⇧⌘T` | Toggle trajectory panel |
| `⌥⌘E` | Open the self-evolution conversation |
| `⇧⌘E` | Copy the full conversation as Markdown |
| `⇧⌘D` | Cycle appearance |

## Tests and builds

### Automatic updates

Starting with v0.5.56, “Check for Updates” is available at the top of the
sidebar and in the application menu. Sparkle checks GitHub Releases once at
launch and then hourly. An archive must pass both EdDSA verification and Apple
code-signature validation before Sparkle atomically replaces the current app.

Generate the release archive and `appcast.xml` with:

```bash
./scripts/create-github-release-artifacts.sh
```

The Sparkle private key stays in the macOS login Keychain; the repository only
contains the public key, signed appcast, and SHA-256 checksums. Versions up to
v0.5.55 require one manual installation of v0.5.56 to bootstrap the updater.

Canonical test command:

```bash
TAPGO_SKIP_REMOTE_INTEGRATION=1 swift run TapgoTests
```

The latest v0.5.56 verification is **2544 passed / 0 failed**. This mode skips only integration sections that require real SSH hosts; Core, harness, model, storage, queue, phone-remote, computer-use, and automatic-update distribution tests still run.

Release products:

```bash
swift build -c release --product TapgoAICoding
swift build -c release --product TapgoComputerUseMCP
```

Or build the complete app bundle:

```bash
./scripts/build-app.sh
```

Do not use a bare `swift build -c release` as the packaging command. `TapgoTests` is an executable test target that uses `@testable import TapgoCore`; release builds should select the intended product explicitly.

## Repository layout

```text
TapgoAICoding/
├── Package.swift
├── Sources/
│   ├── TapgoCore/                 # models, protocols, storage, validation
│   ├── TapgoComputerUse/          # AppKit screenshot/input primitives
│   ├── TapgoComputerUseMCP/       # dedicated computer-use MCP server
│   ├── TapgoAICoding/             # macOS SwiftUI app
│   └── TapgoTests/                # executable regression suite
├── AppBuilder/                    # app/helper plists, icon, signing config
├── scripts/                       # initialization, build, evolution, restart
├── mobile/ios/                    # experimental native iOS pairing client
├── EVOLUTION.md                   # release history
├── AGENT_MEMORY.md                # sanitized stable project-memory snapshot
├── README.md                      # Chinese default
└── README_EN.md                   # English
```

## Releases and rollback

Release history lives in [EVOLUTION.md](EVOLUTION.md). A release should keep these states aligned:

- `AppBuilder/Info.plist`
- `AppBuilder/project.yml`
- In-app evolution history
- Git commit and `vX.Y.Z` tag
- Installed app versions on collaborating Macs

Rollback example:

```bash
git checkout v0.5.48
./scripts/build-app.sh
open 'Tapgo AICoding.app'
```

Checking out a tag creates a detached HEAD. Return to `main` and verify the remote state before continuing development.

## Current limitations

- The app is ad-hoc signed, so first launch and helper authorization require user confirmation.
- Computer use is fully available only when Accessibility, Screen Recording, and MCP registration are all valid.
- Remote SSH integration tests require real hosts and are skipped by the canonical offline command.
- The public phone relay requires separate server and reverse-proxy deployment; production credentials are not part of this repository.
- `mobile/ios/` is not yet a released App Store client, and Android is incomplete.
- The build currently depends on an SDK that provides the SwiftUI macro plugin; validate the toolchain after changing Xcode or SDK versions.

## License

This repository does not currently include a standalone open-source license. Public visibility does not automatically grant rights to copy, modify, or redistribute the code. Add an explicit `LICENSE` before presenting the project as open source.
