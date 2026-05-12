# Server Architecture

## Related docs
- [Project Architecture](./project_architecture.md)
- [Integrations](./integrations.md)
- [SOP: Adding New Routes](../SOP/adding_new_routes.md)

---

## Overview

The server lives entirely in `packages/web/server/`. It is an **Express 5** application assembled via a dependency-injection pattern — each subsystem is a named "runtime" factory that receives its dependencies explicitly. The `main()` function in `index.js` wires them all together.

The server serves three purposes:
1. **Proxy** — forwards `/api/*` requests to the underlying `opencode` process
2. **Augmentation** — adds features the opencode binary doesn't provide: git, filesystem, terminal PTY, TTS, notifications, tunnels, GitHub auth, skills catalog, scheduled tasks
3. **Static host** — serves the Vite-built React SPA

---

## Entry Point

**`packages/web/server/index.js`** (~1,314 lines)

Key startup sequence:
1. Parse CLI options (`cli-options.js`)
2. Initialize HMR-safe state (`hmrStateRuntime`) — survives Vite dev server hot reloads to prevent zombie opencode processes
3. Create all runtime instances (settings, auth, tunnels, notifications, terminal, etc.)
4. Register middleware (CORS, compression, auth gate)
5. Register all route groups
6. Start the Express HTTP server
7. Bootstrap the opencode subprocess (unless `OPENCHAMBER_SKIP_OPENCODE_START`)
8. Start health monitoring

---

## Module Map (`packages/web/server/lib/`)

```
lib/
├── opencode/           Core OpenCode integration (51 files) — lifecycle, proxy, settings, auth, routing
├── event-stream/       WebSocket bridges for browser ↔ OpenCode SSE transport
├── ui-auth/            Browser session auth + WebAuthn passkeys
├── tunnels/            Cloudflare tunnel orchestration
├── notifications/      Push/SSE notification fan-out
├── tts/                OpenAI TTS/STT API + routes
├── terminal/           PTY WebSocket protocol utilities
├── skills-catalog/     GitHub + ClawdHub skill install/scan
├── github/             GitHub OAuth, Octokit, PR status resolution
├── git/                All local Git operations (simple-git)
├── quota/              Provider usage/quota API (13 providers)
├── fs/                 Workspace-bound filesystem API
├── text/               Shared summarization helpers
├── scheduled-tasks/    Cron-like task scheduling via OpenCode sessions
├── projects/           Per-project config + ID
├── magic-prompts/      Magic prompts feature
├── preview/            Preview proxy (local dev server reverse proxy)
└── security/           Shared request security middleware
```

---

## Route Groups

Routes are registered in this order in `index.js`:

| Registrar | Route prefix | Purpose |
|---|---|---|
| `registerServerStatusRoutes` | `/health` | Health check endpoint |
| `registerCommonRequestMiddleware` | `*` | CORS, body parsing, auth middleware |
| `registerAuthAndAccessRoutes` | `/auth/*`, `/api/passkeys` | UI session auth, WebAuthn, tunnel auth |
| `registerTtsRoutes` | `/api/voice/*`, `/api/tts/*`, `/api/stt/*`, `/api/text/*` | TTS generation, STT proxy, text summarize |
| `registerNotificationRoutes` | `/api/push/*`, `/api/session-activity`, `/api/sessions/*` | Push subscription management, session attention |
| `registerOpenChamberRoutes` | `/api/openchamber/*` | Meta/config routes for the UI |
| `featureRoutesRuntime.registerRoutes` | `/api/git/*`, `/api/fs/*`, `/api/config/*`, `/api/projects/*`, `/api/tunnels/*`, `/api/quota/*` | Git, filesystem, settings, agents, providers, skills, scheduled tasks, project config, themes |
| `previewProxyRuntime.attach` | `/api/preview/*` | Authenticated reverse proxy for local dev servers |
| `staticRoutesRuntime` | `*` | Serves built SPA (catch-all) |
| OpenCode proxy | `/api/*` | Forwards everything else to the opencode process |

---

## SSE & WebSocket Endpoints

| Path | Protocol | Purpose |
|---|---|---|
| `/api/event` | SSE | Main OpenCode event stream (proxied from opencode server) |
| `/api/event/ws` | WebSocket | WS alternative to SSE for per-directory events |
| `/api/global/event` | SSE | Global UI event broadcast (notifications, session status) |
| `/api/global/event/ws` | WebSocket | WS alternative to global SSE |
| `/api/notifications/stream` | SSE | Notification-specific SSE channel |
| `/api/openchamber/events` | SSE | OpenChamber-internal events (scheduled task ran, etc.) |
| `/api/terminal/ws` | WebSocket | Terminal PTY I/O stream |
| `/api/message-stream` | WebSocket | Message streaming WebSocket (alternative to SSE) |

---

## Core Module Details

### `opencode/` — Core Integration (51 files)

The largest module. Owns every aspect of OpenCode server integration.

**Key sub-files:**
| File | Purpose |
|---|---|
| `lifecycle.js` | `startOpenCode`, `restartOpenCode`, `waitForOpenCodeReady`, `bootstrapOpenCodeAtStartup`, `startHealthMonitoring` |
| `proxy.js` | `registerOpenCodeProxy` — SSE forwarders, session message forwarder, generic `/api/*` forwarding, readiness gate |
| `watcher.js` | `createOpenCodeWatcherRuntime` — global event watcher backed by shared upstream SSE reader |
| `auth.js` | `readAuthFile`, `writeAuthFile`, `getProviderAuth`, `listProviderAuths` |
| `settings-runtime.js` | Settings read/write, normalization, migration |
| `session-runtime.js` | `processOpenCodeSsePayload`, `getSessionActivitySnapshot`, `getSessionStateSnapshot`, `markSessionViewed` |
| `hmr-state-runtime.js` | HMR-safe state that survives Vite hot reloads |
| `tunnel-wiring-runtime.js` | Wires tunnel providers into the server startup pipeline |
| `shared.js` | `readConfig`, `writeConfig`, path constants (`AGENT_DIR`, `SKILL_DIR`), scope constants |

**Storage paths:**
- Provider auth: `~/.local/share/opencode/auth.json`
- User config: `~/.config/opencode/opencode.json`
- Project config: `<workingDirectory>/.opencode/opencode.json`

---

### `event-stream/` — WebSocket Bridge

Bridges browser clients to the upstream OpenCode SSE streams.

**Key exports:**
- `MESSAGE_STREAM_GLOBAL_WS_PATH` → `/api/global/event/ws`
- `MESSAGE_STREAM_DIRECTORY_WS_PATH` → `/api/event/ws`
- `parseSseEventEnvelope(block)` — parses SSE block into `{ eventId, directory, payload }`
- `createGlobalMessageStreamHub(...)` — shared global hub with bounded replay buffer
- `createGlobalUiEventBroadcaster(...)` — fan-out to SSE+WS clients simultaneously
- `createMessageStreamWsRuntime(...)` — mounts WS server and upgrade routing
- `createUpstreamSseReader(...)` — reusable start/stop upstream SSE reader with `Last-Event-ID`, stall recovery, reconnect

**Architecture:** One shared global hub; browser clients connect to WS endpoints; OpenCode watcher and all browser WS subscribers share one upstream `/global/event` SSE reader. Directory streams maintain one reader per browser connection.

---

### `ui-auth/` — UI Authentication

Browser password sessions, WebAuthn passkeys, trusted-device session cookies.

**Key exports:**
- `createUiAuth({ password, cookieName, sessionTtlMs, ... })` → controller with:
  - `requireAuth(req, res, next)` — Express middleware guarding all `/api/*` routes
  - `handleSessionStatus/Create` — session token management
  - Full passkey registration/authentication/revocation flow
- Password hashing uses `scrypt` with constant-time comparison
- Session tokens managed via `jose` JWT

---

### `terminal/` — PTY WebSocket

Utilities for PTY-backed terminal sessions.

**Key exports:**
- `TERMINAL_WS_PATH` → `/api/terminal/ws`
- `normalizeTerminalWsMessageToBuffer/Text(rawData)`
- `readTerminalWsControlFrame(rawData)` / `createTerminalWsControlFrame(payload)`
- `createTerminalOutputReplayBuffer()` — covers startup races (shell prompt emitted before client binds)
- `pruneRebindTimestamps(...)`, `isRebindRateLimited(...)` — max 128 rebinds per 60-second window

**Heartbeat:** 15 seconds.

---

### `git/` — Git Operations

All Git repository operations via `simple-git`.

**Key operation groups:**
- **Repository:** `isGitRepository`, `getGlobalIdentity`, `getCurrentIdentity`, `setLocalIdentity`, `getRemoteUrl`
- **Status/Diff:** `getStatus`, `getDiff`, `getRangeDiff`, `getFileDiff`, `collectDiffs`, `revertFile`
- **Branches:** `getBranches`, `createBranch`, `checkoutBranch`, `deleteBranch`, `renameBranch`
- **Worktrees:** `getWorktrees`, `validateWorktreeCreate`, `createWorktree`, `removeWorktree`, `isLinkedWorktree`
- **Commit/Remote:** `commit`, `pull`, `push`, `fetch`, `removeRemote`, `deleteRemoteBranch`
- **Log:** `getLog`, `getCommitFiles`
- **Merge/Rebase:** `merge`, `abortMerge`, `continueMerge`, `rebase`, `abortRebase`, `continueRebase`, `getConflictDetails`
- **Stash:** `listStashes`, `stashPush`, `stashApply`, `stashPop`, `stashDrop`

Worktree branches follow `openchamber/<worktree-name>` naming convention.

---

### `notifications/` — Push Notifications

System notification fan-out — web push, desktop notifications, session attention SSE.

**Key exports:**
- `registerNotificationRoutes(app, dependencies)` → 13 endpoints
- `createNotificationTriggerRuntime(dependencies)` → `maybeSendPushForTrigger(payload)`
- `createPushRuntime(dependencies)` → web push subscription management + UI visibility
- `createNotificationEmitterRuntime(dependencies)` → `writeSseEvent`, `emitDesktopNotification`, `broadcastUiNotification`
- `createNotificationTemplateRuntime(dependencies)` → template variable resolution, zen-model summarization

**Triggers:** Session completion, error, question, permission events from OpenCode SSE.

**Constants:**
- `DEFAULT_NOTIFICATION_MESSAGE_MAX_LENGTH` = 250
- `DEFAULT_NOTIFICATION_SUMMARY_THRESHOLD` = 200
- `DEFAULT_NOTIFICATION_SUMMARY_LENGTH` = 100

---

### `tts/` — Text-to-Speech

Server-side TTS via OpenAI API. Bypasses mobile Safari audio context restrictions.

**Key exports:**
- `ttsService` (singleton): `isAvailable()`, `generateSpeechStream(opts)`, `generateSpeechBuffer(opts)`
- `TTS_VOICES` — 13 voices: alloy, ash, ballad, coral, echo, fable, nova, onyx, sage, shimmer, verse, marin, cedar
- `detectSayTtsCapability(processLike)` — probes macOS `say` binary

**API key resolution order:** `OPENAI_API_KEY` env → OpenCode auth file (`auth.openai`, `auth.codex`, `auth.chatgpt`).

---

### `github/` — GitHub Integration

OAuth device flow, Octokit client factory, repository URL parsing, PR status resolution.

**Key exports:**
- `getGitHubAuth()`, `setGitHubAuth(...)`, `activateGitHubAuth(accountId)`, `clearGitHubAuth()`
- `startDeviceFlow({ clientId, scope })`, `exchangeDeviceCode({ clientId, deviceCode })`
- `getOctokitOrNull()` — current Octokit or `null`
- `parseGitHubRemoteUrl(raw)`, `resolveGitHubRepoFromDirectory(directory, remoteName)`
- `resolveGitHubPrStatus(...)` — finds PR across remotes/forks/upstreams

**Auth storage:** `~/.config/openchamber/github-auth.json` (atomic writes, mode `0o600`). Supports multi-account.

---

### `quota/` — Usage Quota

Usage/quota fetching for 13 AI provider accounts.

**Supported providers:** `claude`, `codex`, `google`, `github-copilot`, `github-copilot-addon`, `kimi-for-coding`, `nano-gpt`, `openrouter`, `zai-coding-plan`, `zhipuai-coding-plan`, `minimax-coding-plan`, `minimax-cn-coding-plan`, `ollama-cloud`

**Response contract:** `{ providerId, providerName, ok, configured, usage, fetchedAt, error? }`

---

### `skills-catalog/` — Skills Catalog

Skill discovery, scanning, and installation from GitHub repositories and the ClawdHub registry.

**Key exports:**
- `parseSkillRepoSource(source, { subpath })` — parses GitHub repo source strings
- `scanSkillsRepository({ source, subpath, identity, ... })` — clones and scans for `SKILL.md` files
- `installSkillsFromRepository({ source, selections, conflictPolicy, ... })` — sparse checkout + install
- `scanClawdHub()`, `installSkillsFromClawdHub(...)` — ClawdHub registry
- `getCuratedSkillsSources()`, `CURATED_SKILLS_SOURCES`

**Skill name validation:** `/^[a-z0-9][a-z0-9-]*[a-z0-9]$/` (1-64 chars)

---

### `scheduled-tasks/` — Scheduled Tasks

Server-side cron-like task runtime for per-project automation.

**Key exports:**
- `createScheduledTasksRuntime(dependencies)` → `{ start(), stop(), syncAllProjects(), syncProject(id), runNow(projectId, taskId) }`
- `registerScheduledTaskRoutes(app, dependencies)` → CRUD + manual run endpoints

**Behavior:** Creates OpenCode sessions on schedule via `session create + prompt_async`. Per-project task persistence owned by `projects/project-config.js`.

---

### `fs/` — Filesystem API

Workspace-bound filesystem API for browser clients.

**Endpoints registered:**
- `GET /api/fs/home` — home directory
- `POST /api/fs/mkdir` — create directory
- `GET /api/fs/read` — read file content
- `GET /api/fs/raw` — raw file bytes
- `POST /api/fs/write` — write file
- `POST /api/fs/delete` — delete file/directory
- `POST /api/fs/rename` — rename/move
- `POST /api/fs/reveal` — reveal in OS file manager
- `POST /api/fs/exec` — execute command (job queue)
- `GET /api/fs/exec/:jobId` — poll exec job result
- `GET /api/fs/list` — list directory

**Security:** Workspace boundary enforcement with active project + worktree fallback.

---

## Authentication Flow

### UI Authentication (WebAuthn + JWT)
1. Client requests `/auth/session/status`
2. If auth is enabled and no valid session token → 401
3. Client initiates WebAuthn registration or authentication via `/auth/passkey/*`
4. On success, server issues a JWT session token (via `jose`)
5. Token stored in browser cookie (`cookieName`)
6. All subsequent `/api/*` requests validated by `requireAuth` middleware

### OpenCode Process Auth
- Auto-generated password stored in HMR-persistent state (`openCodeAuthPassword`)
- Auth headers injected into all upstream proxy calls via `getOpenCodeAuthHeaders`
- Source tracked as `openCodeAuthSource` (user-provided vs. auto-generated)

### Tunnel Auth
- `createTunnelAuth()` provides a separate token for tunnel-authenticated remote access
- Tunnel sessions have configurable TTLs (bootstrap: 30 min default, session: 8h default)
- `host.docker.internal` treated as local (no tunnel auth required)

---

## OpenCode Process Lifecycle

1. **Startup:** `bootstrapOpenCodeAtStartup()` resolves the opencode binary path, spawns it as a subprocess
2. **Readiness:** `waitForOpenCodeReady()` polls the health endpoint until ready
3. **Health monitoring:** `startHealthMonitoring()` checks every 15 seconds
4. **HMR safety:** `hmrStateRuntime` persists the process handle across Vite hot reloads to prevent zombie processes
5. **Restart:** `restartOpenCode()` gracefully stops and restarts the subprocess
6. **WSL support:** Can run `opencode` inside WSL from Windows host via `OPENCHAMBER_OPENCODE_WSL_DISTRO`
