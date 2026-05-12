# UI Architecture

## Related docs
- [Project Architecture](./project_architecture.md)
- [Server Architecture](./server_architecture.md)
- [SOP: Adding New Zustand Store](../SOP/adding_new_store.md)

---

## Overview

The shared UI lives in `packages/ui/`. It is a React 19 application using Zustand for state management, Tailwind v4 for styling, and a custom theme/typography system. The same codebase renders in all three runtime targets (web, Electron, VS Code) with minimal branching.

---

## Bootstrap Sequence

### Step 1 — Web entrypoint (`packages/web/src/main.tsx`)
1. Calls `createWebAPIs()` and writes the result to `window.__OPENCHAMBER_RUNTIME_APIS__` — the single runtime capability surface (files API, native APIs, etc.)
2. In production, registers a PWA service worker. In dev, unregisters stale workers.
3. Dynamic `import('@openchamber/ui/main')` loads the shared UI package.

### Step 2 — Shared UI entrypoint (`packages/ui/src/main.tsx`)
1. Reads `window.__OPENCHAMBER_RUNTIME_APIS__` (throws if absent — enforces web entrypoint runs first)
2. Async initialization before first paint:
   - `initializeLocale()` — loads i18n
   - `initializeAppearancePreferences()` — restores persisted theme/font defaults
   - After that resolves: `syncDesktopSettings()`, `applyPersistedDirectoryPreferences()`
   - Background watchers: `startAppearanceAutoSave()`, `startModelPrefsAutoSave()`, `startTypographyWatcher()`
3. Mounts React tree into `#root`:

```
StrictMode
  └─ I18nProvider
       └─ ThemeSystemProvider
            └─ ThemeProvider
                 └─ SessionAuthGate
                      └─ App (receives runtimeAPIs as props)
```

### Electron variant
The Electron main process boots the Express server in-process, gets its loopback port, then loads `http://127.0.0.1:<port>`. The preload script injects `window.__TAURI__` and other globals before the UI runs.

---

## Component Structure (`packages/ui/src/components/`)

```
components/
├── chat/               Main chat UI, message list, input, auto-follow scroll, timeline search
│   └── message/        Per-message part renderers (text, tool calls, diffs, code blocks)
├── auth/               Auth/access UI
├── comments/           Inline comment drafting
├── desktop/            Desktop-specific components (SSH, window controls overlay)
├── icons/              Custom SVG icons
├── layout/             App shell, sidebar, navigation
├── mcp/                MCP configuration UI
├── mini-chat/          Mini Chat floating window (Electron)
├── multirun/           Multi-session parallel run UI
├── onboarding/         First-run setup flow
├── providers/          React context providers
├── sections/           Settings sections (appearance, behavior, git, GitHub, skills, agents, etc.)
│   └── shared/         Shared settings primitives (reuse before introducing new patterns)
├── session/            Session list, folders, multi-select, archive
├── terminal/           Ghostty-based terminal UI
├── ui/                 Shared UI primitives (Base UI wrappers: dropdown, dialog, tooltip, select, etc.)
└── views/              Top-level views
```

---

## Views (`packages/ui/src/components/views/`)

| View | Purpose |
|---|---|
| `ChatView.tsx` | Primary AI chat interface — message list, input, status bar, queued messages, permission cards |
| `SettingsView.tsx` | Full-panel settings page organized into sections |
| `SettingsWindow.tsx` | Window-level wrapper for SettingsView (desktop separate window) |
| `FilesView.tsx` | File browser panel — directory tree, git-ignored/hidden file toggles |
| `DiffView.tsx` | Side-by-side or unified diff viewer for AI-produced file changes |
| `PierreDiffViewer.tsx` | Alternative enhanced diff viewer |
| `GitView.tsx` | Git operations panel — commit, branch, PR status |
| `TerminalView.tsx` | Integrated terminal using ghostty-web PTY |
| `PlanView.tsx` | AI's current plan/task breakdown when plan detection is active |
| `MultiRunWindow.tsx` | Multi-session/multi-run parallel AI sessions |
| `agent-manager/` | Agent management UI — list, create, configure, activate AI agents |

---

## State Management (Zustand Stores)

All stores live in `packages/ui/src/stores/`. There are 40+ stores split by domain and change frequency.

### Core principle
> Treat common stores as render fanout boundaries. An unnecessary reference change in shared state can re-render large parts of the app.

**Rules:**
- Never spread all state fields in an update — only create new references for fields that actually changed
- Select leaf values, not containers
- Group state by how often it changes (streaming state ≠ user preferences)
- Cross-store reads use `.getState()` — imperative, no subscription

### Store Inventory

| Store | Purpose | Change frequency |
|---|---|---|
| `useConfigStore.ts` | Core config: providers, models, agents, model picker defaults, variant selection. Fetches from `/api/config/settings`. | Low (on settings change) |
| `useUIStore.ts` | UI layout state: sidebar, context panel tabs, main tab, right sidebar tab, typography preferences, font preferences, mobile keyboard mode, event stream status. | Medium |
| `useGlobalSessionsStore.ts` | Global session list (active + archived) across all directories, paginated, directory-indexed map. | Medium |
| `permissionStore.ts` | Per-session auto-accept permission state. Persisted via `zustand/persist`. | Low |
| `useGitStore.ts` | Git status, diffs, branches, stash, PR status for current directory. | Medium |
| `useGitHubAuthStore.ts` | GitHub OAuth token / auth state. | Low |
| `useGitHubPrStatusStore.ts` | PR status tracking per session/branch. | Low |
| `useGitIdentitiesStore.ts` | Git identity (user.name/email) management. | Low |
| `useAgentsStore.ts` | Available agents list, filtered visibility. | Low |
| `useAgentGroupsStore.ts` | Agent groups. | Low |
| `useCommandsStore.ts` | Command palette commands registry. | Low |
| `useDirectoryStore.ts` | Current working directory tracking. | Low |
| `useFeatureFlagsStore.ts` | Feature flags. | Low |
| `useFileSearchStore.ts` | File search state and results. | Medium |
| `useFilesViewTabsStore.ts` | Open file tabs in the file viewer. | Medium |
| `messageQueueStore.ts` | Queued outbound messages before sending. | High (during send) |
| `contextStore.ts` | Session context (attached files, mentions, etc.). | Medium |
| `fileStore.ts` | File content cache and editor state. | Medium |
| `useInlineCommentDraftStore.ts` | Inline comment drafting. | Low |
| `useMagicPromptsStore.ts` | Magic/generated prompt suggestions. | Low |
| `useMcpConfigStore.ts` | MCP configuration. | Low |
| `useMcpStore.ts` | Live MCP server state. | Low |
| `useMultiRunStore.ts` | Multi-run / concurrent session execution. | Medium |
| `useOpenInAppsStore.ts` | "Open in app" external app detection cache. | Low |
| `useProjectsStore.ts` | Projects list and current project. | Low |
| `useQuotaStore.ts` | Usage quota display (tokens, costs). | Low |
| `useSessionDisplayStore.ts` | Session display preferences. | Low |
| `useSessionFoldersStore.ts` | Session folder organization. | Low |
| `useSessionMultiSelectStore.ts` | Multi-select state for session list. | Low |
| `useSkillsCatalogStore.ts` | Skills catalog browse/install state. | Low |
| `useSkillsStore.ts` | Installed skills for current project. | Low |
| `useTerminalStore.ts` | Terminal instance state. | Medium |
| `useTodosPersistStore.ts` | Persisted todos/task list. | Low |
| `useUpdateStore.ts` | App update availability state. | Low |
| `useDesktopSshStore.ts` | Desktop SSH connection management. | Low |

**Zustand middleware in use:** `devtools`, `persist`, `createJSONStorage`

---

## Key Hooks (`packages/ui/src/hooks/`)

### Connection & Readiness
| Hook | Purpose |
|---|---|
| `useOpenCodeReadiness` | Reads `useConfigStore` for `isInitialized` / `connectionPhase` / `lastDisconnectReason`. Returns `{isReady, isLoading, isUnavailable}` — canonical gate before showing main UI. |
| `useEventStream` | Subscribes to `/api/event` or global event endpoint, dispatches payloads to Zustand stores. Primary SSE hook. |

### Session Lifecycle
| Hook | Purpose |
|---|---|
| `useSessionActivity(sessionId, directory?)` | Authoritative "is the AI working?" signal. Reads `session_status` from sync store (busy/retry/idle), falls back narrowly to trailing assistant message if status hasn't landed. Returns `{phase, isWorking, isBusy, isCooldown}`. |
| `useCurrentSessionActivity()` | Thin wrapper — reads current session ID then calls `useSessionActivity`. |
| `useQueuedMessageAutoSend` | Automatically sends queued messages when session is ready. |

### Input & Chat
| Hook | Purpose |
|---|---|
| `useChatAutoFollow` | Keeps message list scrolled to bottom during streaming. |
| `useChatSearchDirectory` | Manages file/directory search context within chat input. |
| `useKeyboardShortcuts` / `useMiniChatKeyboardShortcuts` | Register global and chat-specific keyboard shortcuts. |
| `useAssistantStatus` | Tracks assistant status text/indicators. |
| `useAssistantTyping` | Drives the "assistant is typing" animation. |
| `useAvailableTools` | Resolves which tools are available in the current session/agent context. |

### Appearance & Font
| Hook | Purpose |
|---|---|
| `useFontPreferences` | Reads persisted font family + size preferences. |
| `useWindowTitle` | Updates the document/window title reactively. |
| `useWindowControlsOverlayLayout` | Adjusts layout for Electron's window controls overlay (traffic lights on macOS). |

### Platform / Native
| Hook | Purpose |
|---|---|
| `useRuntimeAPIs` | Accesses `window.__OPENCHAMBER_RUNTIME_APIS__` in a typed way. |
| `usePwaDetection` / `usePwaInstallPrompt` / `usePwaManifestSync` | PWA install prompt management and manifest sync. |
| `useDrawerSwipe` / `useEdgeSwipe` | Touch gesture handling for mobile drawers. |

### Voice / TTS
| Hook | Purpose |
|---|---|
| `useVoiceContext` | Root context for voice features. |
| `useMessageTTS` / `useSayTTS` / `useServerTTS` / `useBrowserVoice` | Different TTS backends (browser Speech API, server-side TTS endpoint, system `say` on macOS). |

### Worktrees / Directory
| Hook | Purpose |
|---|---|
| `useDetectedWorktreeRoot` | Detects the Git worktree root for the active directory. |
| `useEffectiveDirectory` | Resolves the canonical working directory for the current session/context. |

---

## OpenCode Client (`packages/ui/src/lib/opencode/client.ts`)

The `OpencodeService` class wraps `@opencode-ai/sdk/v2`'s `OpencodeClient`.

**Base URL resolution:**
- Defaults to `/api` (relative)
- Can be overridden via `VITE_OPENCODE_URL`
- In Electron, reads `window.__OPENCHAMBER_DESKTOP_SERVER__.origin` to construct the absolute loopback URL

**Key behaviors:**
- **ID generation:** `ascendingId("msg")` produces hex-timestamp-prefixed IDs for optimistic updates, matching server format
- **Directory context:** tracked in `currentDirectory`. All per-directory scoped calls use a dedicated `scopedClients` map
- **List directory caching:** 400ms TTL cache with in-flight deduplication
- **Retry logic:** `provider-tracker` module tracks circuit-breaker state per provider; retryable fetch errors trigger exponential backoff
- **Desktop filesystem API:** falls back to `window.__OPENCHAMBER_RUNTIME_APIS__.files` for native file operations in Electron

---

## Theme System (`packages/ui/src/lib/theme/`)

### Theme Definitions
- ~30 named themes, each with dark and light variant, stored as JSON files in `themes/`
- Examples: Catppuccin, Tokyo Night, Dracula, Gruvbox, Nord, Rosé Pine, Vercel, Flexoki, GitHub, One Dark Pro
- Default themes: `flexoki-light` / `flexoki-dark`
- `getThemeById(id)` looks up by `metadata.id`; handles back-compat renames

### Theme JSON Structure
Each theme has structured color groups:
```
colors.primary        — base, hover, active, foreground, muted, emphasis
colors.surface        — background, foreground, muted, mutedForeground, elevated, elevatedForeground, overlay, subtle
colors.interactive    — border, borderHover, borderFocus, selection, focus, focusRing, cursor, hover, active
colors.status         — error/warning/success/info each with foreground, background, border variants
colors.syntax.base    — background, foreground, comment, keyword, string, number, function, variable, type, operator
colors.syntax.tokens  — 30+ fine-grained token overrides
colors.markdown       — (optional)
colors.chat           — (optional)
colors.tools          — (optional)
colors.charts         — (optional)
colors.pr             — (optional, PR status colors)
config.fonts          — sans, mono, heading overrides
config.transitions    — fast, normal, slow
```

### CSS Variable Generation (`CSSVariableGenerator`)
The `apply(theme)` method:
1. Generates Tailwind-compatible variables (`--background`, `--foreground`, `--primary`, `--muted`, `--sidebar-*`, etc.)
2. Generates semantic groups: primary, surface, interactive, status, pull-request, syntax, component
3. For dark themes: injects into both `:root` and `.dark {}`, adds `dark` class to `<html>`
4. For light: injects into `:root:not(.dark)`, adds `light` class
5. Sets `data-theme` attribute on `<html>`
6. All variables use `!important` on Tailwind-compat vars to override shadcn/ui defaults
7. Color utilities (`opacity`, `darken`, `lighten`, `adjustHue`, `emphasize`) derive missing token values automatically

> **Rule:** All UI colors MUST use theme tokens — never hardcoded values or Tailwind color classes.

---

## Typography System (`packages/ui/src/lib/typography.ts`)

A semantic, scale-aware, runtime-variable typography system.

### Semantic Scales (3 global sizes)
```
              small       medium (default)   large
markdown:     0.875rem    0.9375rem          1rem
code:         0.8125rem   0.8125rem          0.9375rem
uiHeader:     0.875rem    0.9375rem          1rem
uiLabel:      0.8125rem   0.875rem           0.9375rem
meta:         0.8125rem   0.875rem           0.9375rem
micro:        0.75rem     0.875rem           0.9375rem
```
VS Code gets its own tighter set (`VSCODE_TYPOGRAPHY`).

### CSS Custom Properties
All sizes injected at runtime as CSS variables:
- `--text-markdown`, `--text-code`, `--text-ui-header`, `--text-ui-label`, `--text-meta`, `--text-micro`
- Full set of line-height and letter-spacing per element type

### Usage
```ts
// Style objects for direct style={} use
import { typography } from '@/lib/typography'
<div style={typography.ui.label}>...</div>

// Utility functions
getTypographyStyle('markdown.body')   // dot-path accessor
getTypographyVariable(key)            // → CSS var name
getTypographyClass(key)               // → Tailwind utility class name
```

---

## Electron Preload Bridge (`packages/electron/preload.mjs`)

Runs in a privileged Node context before the renderer page loads. Uses Electron's `contextBridge` to safely expose a minimal API surface into `window`.

### What is exposed

| Global | Scope | Purpose |
|---|---|---|
| `window.__OPENCHAMBER_ELECTRON__` | All pages | `{ runtime: 'electron' }` — shell-identity flag |
| `window.__TAURI__` | All pages | IPC bridge object (Tauri v2 API shape shim) |
| `window.__OPENCHAMBER_HOME__` | Local pages only | OS home directory |
| `window.__OPENCHAMBER_LOCAL_ORIGIN__` | All pages | Loopback URL for DesktopHostSwitcher |
| `window.__OPENCHAMBER_MACOS_MAJOR__` | All pages | macOS major version for traffic-light offsets |

### The `__TAURI__` shim

Mimics the Tauri v2 API shape so shared renderer code works against both shells:

```js
window.__TAURI__ = {
  core: {
    invoke: (cmd, args) => ipcRenderer.invoke('openchamber:invoke', cmd, args)
  },
  dialog: {
    open: (options) => ipcRenderer.invoke('openchamber:dialog:open', options)
  },
  shell: {
    open: (url) => ipcRenderer.invoke('openchamber:invoke', 'desktop_open_external_url', { url })
  },
  event: {
    listen: async (event, handler) => addListener(event, handler)
  }
}
```

### Security boundary
- `contextBridge` prevents renderer from accessing raw Node/Electron APIs
- `ipcMain.handle('openchamber:invoke')` enforces a `COMMANDS_SAFE_FOR_REMOTE` allowlist
- Native shell operations (file access, app launch, restart) are blocked for non-local pages

### Event flow (main → renderer)
Preload listens on `ipcRenderer.on('openchamber:emit', ...)`. Events dispatched to all registered `addListener` handlers AND forwarded as DOM `CustomEvent` on `window`.

---

## UI Primitives Policy

- **Base UI** (`@base-ui/react`) is the primary source for dropdown/select/dialog/menu/tooltip/etc.
- Wrappers live in `packages/ui/src/components/ui/`
- **Radix UI** is legacy — being migrated to Base UI
- **Toasts:** use the wrapper from `@/components/ui`; do not import `sonner` directly in feature code
- **Shared settings primitives:** reuse from `components/sections/shared/` before introducing feature-local markup patterns

---

## Performance Rules (Critical)

These rules exist because violating them has caused measurable regressions:

1. **Never spread all state fields in a Zustand update** — only create new references for fields that actually changed
2. **Select leaf values, not containers** — `useStore((s) => s.permission[sessionID])` not `useStore((s) => s.permission)`
3. **Do not put high-frequency state in broadly consumed stores** — streaming state (60/sec) must not live with user preferences
4. **Gate expensive operations on the hot path** — `message.part.delta` fires ~60/sec; add cheap boolean checks first
5. **Extract high-frequency hook consumers into separate components** — wrap in `React.memo` child so parent doesn't re-render
6. **Never use `await waitForFrames()` for scroll preservation** — use `useLayoutEffect` instead
7. **Do not let text input state repaint unrelated chrome** — typing should not force unrelated controls to re-render

See `AGENTS.md` for the full performance rules and regression-prevention checklist.
