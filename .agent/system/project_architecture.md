# Project Architecture

## Related docs
- [Server Architecture](./server_architecture.md)
- [UI Architecture](./ui_architecture.md)
- [Integrations](./integrations.md)

---

## Project Goal

OpenChamber is an open-source, multi-runtime UI shell for the [OpenCode](https://github.com/opencode-ai/opencode) AI coding assistant. It does **not** implement AI inference — it wraps and communicates with an `opencode` server process (local auto-start or remote), providing polished interfaces for chat, file management, terminal, git, and more.

**Key value proposition:** Multiple runtime targets (browser, Electron desktop, VS Code extension, legacy Tauri desktop) all share a single React UI codebase (`@openchamber/ui`).

- **Version:** 1.10.4
- **License:** MIT
- **Package manager:** Bun 1.3.5
- **Node requirement:** >= 20.0.0

---

## Monorepo Structure

```
openchamber/
├── packages/
│   ├── ui/          @openchamber/ui       Shared React UI (components, stores, hooks, styles)
│   ├── web/         @openchamber/web      Web app + Express server + CLI binary
│   ├── electron/    @openchamber/electron Electron desktop shell (primary forward target)
│   ├── desktop/     (Tauri)               Legacy Tauri shell — maintenance-only, no new features
│   └── vscode/                            VS Code extension
├── .agent/                                Engineering documentation (this folder)
├── package.json                           Root workspace config
└── bun.lock
```

### Package responsibilities

| Package | Published | Purpose |
|---|---|---|
| `packages/ui` | No | All React components, Zustand stores, hooks, theme system, typography. Consumed by web, electron, vscode. |
| `packages/web` | Yes (npm) | Vite SPA build + Express server (`server/index.js`) + `openchamber` CLI binary (`bin/cli.js`). |
| `packages/electron` | No | Electron 41 desktop shell. Boots the web server **in-process** via `startWebUiServer()`, loads the SPA over loopback. Handles native integrations: tray, menus, dialogs, deep links, auto-update, SSH manager. |
| `packages/desktop` | No | Legacy Tauri v2 shell. Kept only for auto-update migration of existing Tauri installs. Do not add features here. |
| `packages/vscode` | No | VS Code extension. Registers webview panels (`ChatViewProvider`, `AgentManagerPanelProvider`, `SessionEditorPanelProvider`) and manages the OpenCode server lifecycle. |

---

## Tech Stack

### Runtime & Tooling
| Tool | Version | Role |
|---|---|---|
| Bun | 1.3.5 | Package manager + runtime |
| Node.js | >= 20.0.0 | Server runtime |
| TypeScript | ~5.8.3 | Type system |
| Vite | ^7.1.2 | Frontend build tool |
| ESLint | ^9.33.0 | Linting |

### Frontend / UI
| Library | Purpose |
|---|---|
| React 19 | UI framework |
| Tailwind CSS v4 | Styling (utility-first) |
| Zustand 5 | State management |
| Base UI (`@base-ui/react`) | Primary headless primitives (dropdowns, dialogs, menus, tooltips) |
| Radix UI | Legacy headless primitives (being migrated to Base UI) |
| HeroUI | Component library |
| Remixicon | Icon set |
| CodeMirror 6 | In-app code editor (JS, TS, Python, Rust, Go, SQL, YAML, etc.) |
| `@pierre/diffs` | Diff/patch viewing |
| `@tanstack/react-virtual` | Virtualised lists |
| `@dnd-kit` | Drag-and-drop (sortable sessions, folders) |
| `ghostty-web` | In-browser terminal renderer |
| `react-markdown` + `remark-gfm` | Markdown rendering in chat |
| `rehype-katex` + `remark-math` | LaTeX/math rendering |
| `beautiful-mermaid` | Diagram rendering |
| `motion` | Animations |
| `next-themes` | Theme switching |
| `sonner` | Toast notifications |
| `cmdk` | Command palette |
| `fuse.js` | Fuzzy search |

### Backend / Server
| Library | Purpose |
|---|---|
| Express 5 | HTTP server |
| `http-proxy-middleware` | Proxy to OpenCode process |
| `ws` | WebSocket server |
| `better-sqlite3` | SQLite (session/data persistence) |
| `jose` | JWT / JOSE for auth tokens |
| `@simplewebauthn/server` + `/browser` | WebAuthn-based UI authentication |
| `web-push` | Web Push / VAPID for push notifications |
| `simple-git` | Git operations |
| `node-pty` / `bun-pty` | Terminal PTY spawning |
| `openai` | OpenAI SDK (TTS/STT) |
| `adm-zip` | ZIP handling (skill catalog) |
| `yaml` | YAML parsing |
| `jsonc-parser` | JSONC settings files |
| `@octokit/rest` | GitHub REST API |
| `@clack/prompts` | Interactive CLI prompts |
| `zod` | Runtime schema validation |

### Desktop (Electron)
| Library | Purpose |
|---|---|
| Electron 41 | Desktop shell |
| `electron-updater` | Auto-update |
| `electron-log` | Structured logging to file |
| `electron-context-menu` | Right-click context menus |

---

## System Data Flow

```
User (Browser / Electron / VS Code Webview)
    │
    │  HTTP + SSE + WebSocket
    ▼
OpenChamber Express Server  (packages/web/server/index.js)
    ├── /api/*              → Proxied to opencode process
    ├── /api/event          → SSE relay from opencode
    ├── /api/global/event   → Internal UI event broadcast (SSE)
    ├── /api/terminal/*     → PTY WebSocket
    ├── /api/tts/*          → Text-to-speech
    ├── /api/notifications  → Push/SSE notification routes
    ├── /api/git/*          → simple-git operations
    ├── /api/fs/*           → Filesystem operations
    ├── /api/settings/*     → Settings persistence
    ├── /api/tunnels/*      → Tunnel management (Cloudflare)
    └── /static             → Vite-built React SPA
    │
    │  spawn / HTTP
    ▼
opencode process  (separate binary — AI inference engine)
    └── Communicates back via SSE events and HTTP API
```

---

## Runtime Targets

### Web (Browser)
- Entry: `packages/web/src/main.tsx` → `packages/ui/src/main.tsx`
- Served by the Express server as a static SPA
- Communicates with the server via relative `/api/*` paths

### Desktop (Electron — primary)
- Entry: `packages/electron/main.mjs`
- Boots the web server **in-process** via `startWebUiServer()`
- Loads the SPA at `http://127.0.0.1:<port>` (default 57123)
- Preload (`packages/electron/preload.mjs`) exposes `window.__TAURI__` IPC shim so shared UI is shell-agnostic
- Native integrations: tray, menus, dialogs, deep links (`openchamber://`), auto-update, SSH manager, mini-chat windows

### Desktop (Tauri — legacy, maintenance-only)
- Entry: `packages/desktop/src-tauri/src/main.rs`
- Kept only for auto-update migration of existing Tauri installs
- **Do not add features here**

### VS Code Extension
- Entry: `packages/vscode/src/extension.ts`
- Registers webview panels that embed the shared React UI
- Manages OpenCode server lifecycle via `OpenCodeManager`
- Communicates settings via `openchamber.settings` VS Code config key

---

## Storage & Persistence

| Storage | Mechanism | Contents |
|---|---|---|
| `~/.config/openchamber/settings.json` | JSON file | App settings (providers, tunnels, models, themes, projects, skills, typography) |
| `~/.config/openchamber/push-subscriptions.json` | JSON file | Web Push subscription objects |
| `~/.config/openchamber/cloudflare-managed-remote-tunnels.json` | JSON file | Cloudflare managed remote tunnel tokens/hostnames |
| `~/.config/openchamber/themes/` | Directory of JSON files | Custom theme definitions (max 512KB each) |
| `~/.config/openchamber/projects/` | Directory | Per-project config (scheduled tasks, actions, dev servers) |
| `~/.config/openchamber/github-auth.json` | JSON file (mode 0o600) | GitHub OAuth tokens, multi-account |
| `better-sqlite3` SQLite DB | Embedded SQLite | Session persistence |
| Zustand `persist` (localStorage) | Browser localStorage | UI preferences, permission auto-accept map, session display prefs |
| Electron window state | File in app data | Window geometry, position, size across restarts |
| `~/.local/share/opencode/auth.json` | JSON file | Provider API keys (managed by opencode) |
| `~/.config/opencode/opencode.json` | JSON file | OpenCode user config |

---

## Environment Variables

| Variable | Purpose | Default |
|---|---|---|
| `OPENCHAMBER_PORT` | Port for the OpenChamber web server | 3000 |
| `OPENCHAMBER_HOST` | Bind host for the server | — |
| `OPENCHAMBER_DATA_DIR` | Override data/config storage directory | `~/.config/openchamber` |
| `OPENCHAMBER_RUNTIME` | Runtime identifier (`web`, `desktop`) | — |
| `OPENCHAMBER_DESKTOP_NOTIFY` | Enable desktop notification emit mode | — |
| `OPENCHAMBER_VERBOSE_REQUEST_LOGS` | Enable verbose HTTP request logging | — |
| `OPENCHAMBER_SKIP_OPENCODE_START` | Skip starting the opencode subprocess | — |
| `OPENCHAMBER_OPENCODE_WSL_DISTRO` | WSL distro for running opencode on Windows | — |
| `OPENCODE_SKIP_START` | Alternative skip flag (opencode side) | — |
| `OPENCODE_PORT` | Port of an existing opencode server to connect to | — |
| `OPENCODE_HOST` | Full base URL of existing opencode server | — |
| `OPENCODE_EXPERIMENTAL_PLAN_MODE` | Enable experimental plan mode feature | — |
| `VITE_OPENCODE_URL` | Override OpenCode API base URL in the browser SPA | `/api` |

---

## Build Commands

| Command | What it does |
|---|---|
| `bun run dev` | Full dev mode: watch server + watch web build + UI type-check |
| `bun run build` | Build all packages |
| `bun run build:web` | Build web SPA (Vite) |
| `bun run electron:dev` | Dev mode for Electron desktop |
| `bun run electron:build` | Package Electron app |
| `bun run desktop:build` | Build Tauri app (legacy) |
| `bun run vscode:build` | Build VS Code extension |
| `bun run vscode:package` | Package VS Code .vsix |
| `bun run type-check` | Type-check all packages |
| `bun run lint` | Lint all packages |
| `bun run release:test` | Smoke test release build |
| `bun run start:web` | Run the server via CLI (`node bin/cli.js serve`) |

---

## Key Configuration Files

| File | Purpose |
|---|---|
| `package.json` | Root workspace config, all scripts |
| `packages/web/vite.config.ts` | Vite build config for the SPA |
| `packages/electron/electron-builder.yml` | Electron packaging config |
| `packages/vscode/package.json` | VS Code extension manifest (commands, settings, activation events) |
| `packages/ui/src/lib/theme/` | Theme definitions and CSS variable generator |
| `packages/ui/src/lib/typography.ts` | Typography scale system |
