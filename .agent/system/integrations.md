# Integrations

## Related docs
- [Project Architecture](./project_architecture.md)
- [Server Architecture](./server_architecture.md)

---

## Overview

OpenChamber integrates with several external systems. This document covers each integration: what it does, how it's wired, where the code lives, and key configuration.

---

## 1. OpenCode Process

**What:** The core AI inference engine. OpenChamber is a UI shell around it.

**How it works:**
- OpenChamber auto-starts the `opencode` binary as a subprocess via `child_process.spawn`
- Port is auto-detected or configured via `OPENCODE_PORT` / `OPENCHAMBER_PORT`
- All `/api/*` requests (except OpenChamber-specific routes) are proxied to the opencode process
- OpenCode communicates back via SSE events and HTTP API

**Code location:**
- Lifecycle: `packages/web/server/lib/opencode/lifecycle.js`
- Proxy: `packages/web/server/lib/opencode/proxy.js`
- Auth: `packages/web/server/lib/opencode/auth.js`
- Watcher: `packages/web/server/lib/opencode/watcher.js`
- HMR state: `packages/web/server/lib/opencode/hmr-state-runtime.js`

**Configuration:**
| Variable | Purpose |
|---|---|
| `OPENCODE_PORT` | Port of an existing opencode server |
| `OPENCODE_HOST` | Full base URL of existing opencode server |
| `OPENCHAMBER_SKIP_OPENCODE_START` | Skip starting the subprocess (connect to existing) |
| `OPENCHAMBER_OPENCODE_WSL_DISTRO` | WSL distro for running opencode on Windows |

**Auth:** Auto-generated password stored in HMR-persistent state. Injected into all upstream proxy calls via `getOpenCodeAuthHeaders`.

**Storage:**
- Provider auth: `~/.local/share/opencode/auth.json`
- User config: `~/.config/opencode/opencode.json`
- Project config: `<workingDirectory>/.opencode/opencode.json`

---

## 2. GitHub

**What:** OAuth authentication, repository operations, PR status tracking.

**Code location:** `packages/web/server/lib/github/`

**Auth flow (OAuth Device Flow):**
1. Client calls `startDeviceFlow({ clientId, scope })` → gets `device_code` + `user_code`
2. User visits GitHub and enters the code
3. Client polls `exchangeDeviceCode({ clientId, deviceCode })` until token arrives
4. Token stored in `~/.config/openchamber/github-auth.json` (mode `0o600`)
5. Supports multi-account via `accountId`

**Key exports:**
- `getGitHubAuth()`, `setGitHubAuth(...)`, `activateGitHubAuth(accountId)`, `clearGitHubAuth()`
- `getOctokitOrNull()` — current Octokit REST client or `null`
- `parseGitHubRemoteUrl(raw)`, `resolveGitHubRepoFromDirectory(directory, remoteName)`
- `resolveGitHubPrStatus(...)` — finds PR across remotes/forks/upstreams

**PR resolution logic:**
1. Ranks remotes: explicit → tracking → origin → upstream → rest
2. Expands repos through `parent`/`source` (fork detection)
3. Skips default branch
4. Tries source-owner+branch first, falls back to broader search

**Client-side polling rules:**
- Immediate on watch start
- Retry at 2s/5s if no PR found
- 5m discovery interval
- 1m (pending checks) / 2m (no signal) / 5m (stable) refresh

---

## 3. Git (Local)

**What:** All local Git repository operations.

**Code location:** `packages/web/server/lib/git/`

**Library:** `simple-git` — instances created via `createGit(directory)`

**Routes:** Registered under `/api/git/*`

**Key operations:**
- Status, diff, file diff, range diff
- Branch create/checkout/delete/rename
- Worktree create/remove/validate
- Commit, pull, push, fetch
- Merge, rebase (with abort/continue)
- Stash push/apply/pop/drop
- Log, commit files

**Worktree naming convention:** `openchamber/<worktree-name>`

**SSH key injection:** via `core.sshCommand` git config option

---

## 4. Cloudflare Tunnels

**What:** Expose the local OpenChamber server to the internet via Cloudflare tunnels.

**Code location:** `packages/web/server/lib/tunnels/`

**Three modes:**
| Mode | Description |
|---|---|
| `quick` | Temporary URL via `cloudflared tunnel --url` |
| `managed-local` | Local `cloudflared` binary with named tunnel |
| `managed-remote` | Pre-configured hosted tunnel (token stored in config) |

**Configuration:**
- Managed remote tunnels: `~/.config/openchamber/cloudflare-managed-remote-tunnels.json`
- Named tunnels: `~/.config/openchamber/cloudflare-named-tunnels.json`

**TTLs:**
- Bootstrap TTL: 30 minutes (default)
- Session TTL: 8 hours (default)

**Auth:** `createTunnelAuth()` provides a separate JWT token for tunnel-authenticated remote access. `host.docker.internal` is treated as local (no tunnel auth required).

**Wiring:** `packages/web/server/lib/opencode/tunnel-wiring-runtime.js` wires tunnel providers into the server startup pipeline.

---

## 5. Terminal (PTY)

**What:** Full-duplex terminal sessions in the browser via WebSocket.

**Code location:** `packages/web/server/lib/terminal/`

**Libraries:** `bun-pty` (Bun runtime) / `node-pty` (Node runtime)

**Protocol:**
- WebSocket path: `/api/terminal/ws`
- Custom framing protocol (documented in `TERMINAL_WS_PROTOCOL.md`)
- Control frames for resize, heartbeat, rebind
- Output replay buffer covers startup races (shell prompt emitted before client binds)

**Rate limiting:** Max 128 rebinds per 60-second window

**Heartbeat:** 15 seconds

**UI:** `ghostty-web` terminal renderer in `packages/ui/src/components/terminal/`

---

## 6. Push Notifications (Web Push)

**What:** Browser push notifications for session completion, errors, questions, and permission requests.

**Code location:** `packages/web/server/lib/notifications/`

**Library:** `web-push` with VAPID keys

**Flow:**
1. Browser subscribes via `/api/push/subscribe`
2. Subscriptions stored in `~/.config/openchamber/push-subscriptions.json`
3. OpenCode SSE events trigger `maybeSendPushForTrigger(payload)`
4. Server sends push to all registered subscribers

**Triggers:** Session completion, error, question, permission events

**Text processing:**
- `DEFAULT_NOTIFICATION_MESSAGE_MAX_LENGTH` = 250
- `DEFAULT_NOTIFICATION_SUMMARY_THRESHOLD` = 200 (above this, summarize via zen model)
- `DEFAULT_NOTIFICATION_SUMMARY_LENGTH` = 100

**Desktop notifications:** Electron receives notifications via `onDesktopNotification` callback injected at startup — no stdout-parsing IPC.

---

## 7. Text-to-Speech (TTS)

**What:** Server-side TTS to bypass mobile Safari audio context restrictions.

**Code location:** `packages/web/server/lib/tts/`

**Backends:**
1. **OpenAI TTS** — primary, via `openai` SDK
2. **macOS `say` binary** — detected via `detectSayTtsCapability()`, used as fallback

**API key resolution order:**
1. `OPENAI_API_KEY` environment variable
2. OpenCode auth file: `auth.openai`, `auth.codex`, `auth.chatgpt`

**Routes:** `/api/voice/*`, `/api/tts/*`, `/api/stt/*`, `/api/text/summarize`

**13 voices:** alloy, ash, ballad, coral, echo, fable, nova, onyx, sage, shimmer, verse, marin, cedar

**Summarization:** `summarizeText({ text, threshold, maxLength, zenModel, mode })` — modes: `tts`, `notification`, `note`

---

## 8. Skills Catalog

**What:** Browse, install, and configure agent skill packages from GitHub or ClawdHub registry.

**Code location:** `packages/web/server/lib/skills-catalog/`

**Sources:**
1. **GitHub repositories** — sparse checkout via `git clone --filter=blob:none`
2. **ClawdHub registry** — ZIP download via `adm-zip`
3. **Curated sources** — `getCuratedSkillsSources()`, `CURATED_SKILLS_SOURCES`

**Skill discovery:** Scans for `SKILL.md` files in repository

**Skill name validation:** `/^[a-z0-9][a-z0-9-]*[a-z0-9]$/` (1-64 chars)

**Conflict policies:** configurable on install (overwrite, skip, error)

**UI:** `packages/ui/src/components/sections/skills/`

---

## 9. Scheduled Tasks

**What:** Cron-like automation that creates OpenCode sessions on schedule.

**Code location:** `packages/web/server/lib/scheduled-tasks/`

**Library:** `cron-parser`

**Flow:**
1. Tasks defined per-project in `~/.config/openchamber/projects/<id>/`
2. Runtime schedules timers based on cron expressions
3. On trigger: creates an OpenCode session via `session create + prompt_async`
4. Emits `openchamber:scheduled-task-ran` SSE event to UI

**Routes:** `/api/projects/:id/scheduled-tasks` (CRUD + manual run), `/api/openchamber/scheduled-tasks/status`

---

## 10. Preview Proxy

**What:** Authenticated reverse proxy for local dev servers (e.g., Vite/HMR apps running locally).

**Code location:** `packages/web/server/lib/preview/`

**Routes:** `/api/preview/*`

**Features:**
- URL rewriting
- Vite HMR support
- Authentication gate (same as main server auth)

---

## 11. WebAuthn (Passkeys)

**What:** Passwordless authentication for the OpenChamber UI.

**Code location:** `packages/web/server/lib/ui-auth/`

**Libraries:** `@simplewebauthn/server`, `@simplewebauthn/browser`

**Flow:**
1. `beginRegistration()` → challenge sent to browser
2. Browser creates passkey via WebAuthn API
3. `finishRegistration()` → passkey stored server-side
4. `beginAuthentication()` → challenge sent
5. Browser signs with passkey
6. `finishAuthentication()` → JWT session token issued via `jose`
7. Token stored in browser cookie

**Routes:** `/auth/passkey/*`, `/api/passkeys`

**Password fallback:** `scrypt` hashing with constant-time comparison

---

## 12. VS Code Extension Integration

**What:** Embeds the OpenChamber UI as webview panels inside VS Code.

**Code location:** `packages/vscode/src/extension.ts`

**Webview panels:**
- `ChatViewProvider` — sidebar chat panel
- `AgentManagerPanelProvider` — agent management panel
- `SessionEditorPanelProvider` — full session viewer in editor tab

**Server lifecycle:** `OpenCodeManager` manages the opencode server lifecycle for the extension

**Session watching:** `sessionActivityWatcher` — global SSE watcher for session status events

**Settings sync:** VS Code settings key `openchamber.settings` stores:
- `defaultModel`, `defaultVariant`, `defaultAgent`
- `gitmojiEnabled`, `defaultFileViewerPreview`
- `zenModel`, `messageStreamTransport`, `autoCreateWorktree`

**Commands registered:**
- `openchamber.openSidebar`
- `openchamber.focusChat`
- `openchamber.openAgentManager`
- `openchamber.setActiveSession`
- `openchamber.openActiveSessionInEditor`
- `openchamber.internal.settingsSynced`

---

## 13. Electron Desktop Integration

**What:** Native desktop shell with system integrations.

**Code location:** `packages/electron/main.mjs` (~2,656 lines)

**Key integrations:**
- **In-process web server:** `startWebUiServer()` boots the Express server directly in the Electron main process
- **Single-instance lock:** enforced at startup
- **Deep link protocol:** `openchamber://` registered as default protocol client
- **Auto-update:** `electron-updater` with GitHub releases as update source
- **SSH Manager:** `ElectronSshManager` manages SSH tunnel connections
- **Mini Chat windows:** floating always-on-top windows (520×760) for focused conversations
- **Quit confirmation:** prompts user if there are active tunnels or running scheduled tasks
- **Logging:** `electron-log` to `~/Library/Logs/OpenChamber/main.log` (7-day rotation, max 5MB per file)

**Default port:** 57123

**IPC bridge:** Preload exposes `window.__TAURI__` shim — see [UI Architecture](./ui_architecture.md#electron-preload-bridge)
