# OpenChamber — Engineering Documentation

This is the index for all engineering documentation. Start here to understand what exists and where to find it.

---

## What is OpenChamber?

OpenChamber is an open-source, multi-runtime UI shell for the [OpenCode](https://github.com/opencode-ai/opencode) AI coding assistant. It provides polished interfaces for chat, file management, terminal, git, and more — across browser, Electron desktop, and VS Code — all sharing a single React UI codebase.

---

## Documentation Index

### System Documentation (`system/`)

Core reference for understanding how the system works. Read these to get full context before making changes.

| Document | What it covers |
|---|---|
| [project_architecture.md](./system/project_architecture.md) | **Start here.** Project goal, monorepo structure, tech stack, runtime targets, storage, environment variables, build commands. |
| [server_architecture.md](./system/server_architecture.md) | Express server structure, all route groups, SSE/WebSocket endpoints, every `lib/` module (opencode, git, terminal, notifications, tts, github, quota, skills-catalog, scheduled-tasks, fs), auth flows, OpenCode process lifecycle. |
| [ui_architecture.md](./system/ui_architecture.md) | React app bootstrap, component structure, all views, Zustand store inventory, key hooks, OpenCode client, theme system, typography system, Electron preload bridge, UI primitives policy, performance rules. |
| [integrations.md](./system/integrations.md) | Deep-dive on every external integration: OpenCode process, GitHub OAuth, Git, Cloudflare tunnels, terminal PTY, push notifications, TTS, skills catalog, scheduled tasks, preview proxy, WebAuthn, VS Code extension, Electron desktop. |

### SOPs (`SOP/`)

Step-by-step guides for common engineering tasks.

| Document | When to use |
|---|---|
| [adding_new_routes.md](./SOP/adding_new_routes.md) | Adding a new HTTP endpoint to the Express server — where to put it, dependency injection pattern, auth, error handling, SSE/WebSocket, validation, cross-runtime parity checklist. |
| [adding_new_store.md](./SOP/adding_new_store.md) | Creating a new Zustand store — when to create vs. extend, store structure, persist middleware, correct update patterns, high-frequency state rules, optimistic updates, checklist. |

### Tasks (`Tasks/`)

PRDs and implementation plans for specific features. Add a new file here when starting a significant feature.

*(No tasks documented yet — add `Tasks/<feature-name>.md` when starting a new feature.)*

---

## Quick Reference

### Where is X?

| What | Where |
|---|---|
| Express server entry | `packages/web/server/index.js` |
| All server lib modules | `packages/web/server/lib/` |
| React UI entry | `packages/ui/src/main.tsx` |
| All Zustand stores | `packages/ui/src/stores/` |
| All React components | `packages/ui/src/components/` |
| Top-level views | `packages/ui/src/components/views/` |
| Theme definitions | `packages/ui/src/lib/theme/themes/` |
| Typography system | `packages/ui/src/lib/typography.ts` |
| OpenCode client | `packages/ui/src/lib/opencode/client.ts` |
| Electron main | `packages/electron/main.mjs` |
| Electron preload | `packages/electron/preload.mjs` |
| VS Code extension | `packages/vscode/src/extension.ts` |
| CLI binary | `packages/web/bin/cli.js` |
| App settings storage | `~/.config/openchamber/settings.json` |
| Provider auth storage | `~/.local/share/opencode/auth.json` |

### Key constraints

- **Desktop work goes in `packages/electron/`** — `packages/desktop/` (Tauri) is legacy, maintenance-only
- **All UI colors must use theme tokens** — never hardcoded values or Tailwind color classes
- **Do not modify `../opencode`** — that is a separate repository
- **Run `bun run type-check` and `bun run lint` before finalizing any change**
- **Prefer the smallest correct change** — no drive-by refactors

### Runtime targets

| Target | Entry | Notes |
|---|---|---|
| Web (browser) | `packages/web/src/main.tsx` | Served as SPA by Express |
| Desktop (Electron) | `packages/electron/main.mjs` | Boots server in-process, default port 57123 |
| Desktop (Tauri, legacy) | `packages/desktop/src-tauri/src/main.rs` | Maintenance-only |
| VS Code | `packages/vscode/src/extension.ts` | Webview panels |

### Build commands

```bash
bun run dev              # Full dev mode
bun run build            # Build all packages
bun run electron:dev     # Electron dev mode
bun run electron:build   # Package Electron app
bun run vscode:build     # Build VS Code extension
bun run type-check       # Type-check all packages
bun run lint             # Lint all packages
```

---

## Module documentation

Several server lib modules have their own `DOCUMENTATION.md` files with deeper detail:

| Module | Documentation |
|---|---|
| `packages/web/server/lib/quota/` | `DOCUMENTATION.md` |
| `packages/web/server/lib/git/` | `DOCUMENTATION.md` |
| `packages/web/server/lib/github/` | `DOCUMENTATION.md` |
| `packages/web/server/lib/opencode/` | `DOCUMENTATION.md` |
| `packages/web/server/lib/notifications/` | `DOCUMENTATION.md` |
| `packages/web/server/lib/terminal/` | `DOCUMENTATION.md` |
| `packages/web/server/lib/tts/` | `DOCUMENTATION.md` |
| `packages/web/server/lib/skills-catalog/` | `DOCUMENTATION.md` |

---

## Contributing to this documentation

- **Update docs when you change behavior** — if you add a route, update `server_architecture.md`; if you add a store, update `ui_architecture.md`
- **Add a Task doc when starting a significant feature** — create `Tasks/<feature-name>.md` with the PRD and implementation plan
- **Keep this README updated** — add new docs to the index above
- **No overlap between files** — each doc owns its domain; cross-reference with links instead of duplicating content
