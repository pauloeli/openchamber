# SOP: Adding a New Server Route

## Related docs
- [Server Architecture](../system/server_architecture.md)
- [Project Architecture](../system/project_architecture.md)

---

## Overview

All server routes live in `packages/web/server/`. The server uses a **dependency-injection pattern** — each subsystem is a named runtime factory that receives its dependencies explicitly. Routes are registered in `index.js` via named registrar functions.

---

## Decision: Where does my route belong?

| Scenario | Where to add |
|---|---|
| Extends an existing domain (git, fs, notifications, etc.) | Add to the existing lib module's routes file |
| New standalone feature | Create a new module in `packages/web/server/lib/<feature>/` |
| OpenCode config/settings related | Add to `packages/web/server/lib/opencode/` |
| Tiny utility endpoint | Can add directly to `index.js` if truly trivial |

---

## Step-by-step: Adding a route to an existing module

### Example: Adding a new git endpoint

**1. Find the routes file**
```
packages/web/server/lib/git/routes.js
```

**2. Add the route handler**
```js
// packages/web/server/lib/git/routes.js

export function registerGitRoutes(app, { getDirectory, requireAuth }) {
  // ... existing routes ...

  app.get('/api/git/my-new-endpoint', requireAuth, async (req, res) => {
    const directory = getDirectory(req)
    try {
      const result = await myNewGitOperation(directory)
      res.json(result)
    } catch (err) {
      res.status(500).json({ error: err.message })
    }
  })
}
```

**3. Add the business logic**
```js
// packages/web/server/lib/git/my-operation.js
import { createGit } from './index.js'

export async function myNewGitOperation(directory) {
  const git = createGit(directory)
  // ... implementation ...
  return result
}
```

**4. Export from the module index**
```js
// packages/web/server/lib/git/index.js
export { myNewGitOperation } from './my-operation.js'
```

**5. No changes needed in `index.js`** — the git routes registrar is already called there.

---

## Step-by-step: Adding a new module

### 1. Create the module directory
```
packages/web/server/lib/<feature>/
├── index.js        # Public exports
├── routes.js       # Route registration
└── <feature>.js    # Business logic
```

### 2. Write the routes registrar
```js
// packages/web/server/lib/<feature>/routes.js

export function register<Feature>Routes(app, dependencies) {
  const { requireAuth, getDirectory } = dependencies

  app.get('/api/<feature>/something', requireAuth, async (req, res) => {
    try {
      const result = await doSomething()
      res.json(result)
    } catch (err) {
      res.status(500).json({ error: err.message })
    }
  })
}
```

### 3. Export from module index
```js
// packages/web/server/lib/<feature>/index.js
export { register<Feature>Routes } from './routes.js'
export { doSomething } from './<feature>.js'
```

### 4. Wire into the main server (`packages/web/server/index.js`)

Find the `featureRoutesRuntime.registerRoutes` section and add your registrar:

```js
// In the route registration section of index.js
import { register<Feature>Routes } from './lib/<feature>/index.js'

// Inside the registerRoutes function or main():
register<Feature>Routes(app, {
  requireAuth: uiAuth.requireAuth,
  getDirectory: projectDirectoryRuntime.getDirectory,
  // ... other dependencies your module needs
})
```

---

## Dependency injection pattern

The server passes dependencies explicitly. Common dependencies available:

| Dependency | What it provides |
|---|---|
| `requireAuth` | Express middleware — gates the route behind UI auth |
| `getDirectory(req)` | Resolves the active working directory from the request |
| `openCodeAuthHeaders` | Auth headers for proxying to the opencode process |
| `settingsRuntime` | Read/write app settings |
| `notificationEmitter` | Emit notifications to connected clients |
| `globalEventBroadcaster` | Broadcast SSE events to all connected UI clients |
| `scheduledTasksRuntime` | Access scheduled task state |

---

## SSE endpoints

For routes that stream Server-Sent Events:

```js
app.get('/api/<feature>/stream', requireAuth, (req, res) => {
  // Set SSE headers
  res.setHeader('Content-Type', 'text/event-stream')
  res.setHeader('Cache-Control', 'no-cache')
  res.setHeader('Connection', 'keep-alive')
  res.flushHeaders()

  // Send events
  const sendEvent = (data) => {
    res.write(`data: ${JSON.stringify(data)}\n\n`)
  }

  // Register cleanup on disconnect
  req.on('close', () => {
    // cleanup
  })
})
```

> **Important:** SSE paths must be added to `SSE_PATH_PREFIXES` in `index.js` to skip gzip compression (compression breaks SSE streaming).

---

## WebSocket endpoints

WebSocket upgrades are handled separately from Express routes. See `packages/web/server/lib/event-stream/runtime.js` for the pattern. Add your WS path to the upgrade handler dispatch.

---

## Auth middleware

Always apply `requireAuth` to routes that access user data or perform mutations:

```js
app.get('/api/<feature>/data', requireAuth, handler)
app.post('/api/<feature>/action', requireAuth, handler)
```

Public routes (health checks, static assets) do not need `requireAuth`.

---

## Error handling conventions

```js
app.get('/api/<feature>/data', requireAuth, async (req, res) => {
  try {
    const result = await operation()
    res.json(result)
  } catch (err) {
    // Log the error
    console.error('[feature] operation failed:', err)
    // Return structured error
    res.status(500).json({ error: err.message })
  }
})
```

For 404s:
```js
res.status(404).json({ error: 'Not found' })
```

For validation errors:
```js
res.status(400).json({ error: 'Invalid parameter: ...' })
```

---

## Validation

Use `zod` for request body/query validation:

```js
import { z } from 'zod'

const schema = z.object({
  name: z.string().min(1).max(64),
  enabled: z.boolean().optional()
})

app.post('/api/<feature>/create', requireAuth, async (req, res) => {
  const parsed = schema.safeParse(req.body)
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.message })
  }
  const { name, enabled } = parsed.data
  // ...
})
```

---

## Cross-runtime parity

If you add a route that the shared UI depends on, ensure it works consistently across all runtimes:
- **Web** — standard Express route
- **Electron** — same server runs in-process, no changes needed
- **VS Code** — check if the VS Code extension needs any special handling

If the route is desktop-only (e.g., SSH management), gate it:
```js
if (process.env.OPENCHAMBER_RUNTIME === 'desktop') {
  app.get('/api/desktop/...', requireAuth, handler)
}
```

---

## Checklist

- [ ] Route added to the correct module (not dumped in `index.js`)
- [ ] `requireAuth` applied to all non-public routes
- [ ] Error handling returns structured JSON with appropriate status codes
- [ ] Input validated with `zod` for POST/PUT routes
- [ ] SSE paths added to `SSE_PATH_PREFIXES` if streaming
- [ ] Exported from module `index.js`
- [ ] Wired into `index.js` if new module
- [ ] `bun run type-check` passes
- [ ] `bun run lint` passes
