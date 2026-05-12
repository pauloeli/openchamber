# SOP: Adding a New Zustand Store

## Related docs
- [UI Architecture](../system/ui_architecture.md)
- [Project Architecture](../system/project_architecture.md)

---

## Overview

All Zustand stores live in `packages/ui/src/stores/`. There are 40+ stores split by domain and change frequency. Before creating a new store, check if an existing store can be extended.

---

## Decision: Do I need a new store?

**Extend an existing store if:**
- The new state belongs to the same domain (e.g., adding a field to `useGitStore`)
- The new state changes at the same frequency as existing state in that store
- The same set of components already subscribes to that store

**Create a new store if:**
- The new state has a different change frequency (e.g., streaming state vs. preferences)
- The new state has a different subscriber set
- Adding to an existing store would cause unrelated components to re-render

> **Rule:** Never add unrelated state to an existing store just because it's convenient.

---

## Step-by-step: Creating a new store

### 1. Create the store file

```ts
// packages/ui/src/stores/useMyFeatureStore.ts
import { create } from 'zustand'
import { devtools } from 'zustand/middleware'

interface MyFeatureState {
  // State fields
  items: string[]
  isLoading: boolean
  error: string | null

  // Actions
  setItems: (items: string[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  reset: () => void
}

const initialState = {
  items: [],
  isLoading: false,
  error: null,
}

export const useMyFeatureStore = create<MyFeatureState>()(
  devtools(
    (set) => ({
      ...initialState,

      setItems: (items) => set({ items }),
      setLoading: (isLoading) => set({ isLoading }),
      setError: (error) => set({ error }),
      reset: () => set(initialState),
    }),
    { name: 'MyFeatureStore' }
  )
)
```

### 2. For persisted state (survives page reload)

```ts
import { create } from 'zustand'
import { devtools, persist, createJSONStorage } from 'zustand/middleware'

export const useMyPersistedStore = create<MyState>()(
  devtools(
    persist(
      (set) => ({
        // state and actions
      }),
      {
        name: 'my-feature-storage', // localStorage key
        storage: createJSONStorage(() => localStorage),
        // Only persist specific fields:
        partialize: (state) => ({ items: state.items }),
      }
    ),
    { name: 'MyPersistedStore' }
  )
)
```

### 3. Export from the stores barrel (if one exists)

Check if there's a barrel export file. If so, add your store:
```ts
// packages/ui/src/stores/index.ts (if it exists)
export { useMyFeatureStore } from './useMyFeatureStore'
```

---

## Consuming the store in components

### Basic usage (leaf selector — preferred)
```tsx
// Subscribe only to the specific field you need
const items = useMyFeatureStore((s) => s.items)
const isLoading = useMyFeatureStore((s) => s.isLoading)
```

### Multiple fields (use separate selectors)
```tsx
// Good: separate selectors, each re-renders only when its value changes
const items = useMyFeatureStore((s) => s.items)
const isLoading = useMyFeatureStore((s) => s.isLoading)

// Bad: object selector creates new reference on every state change
const { items, isLoading } = useMyFeatureStore((s) => ({ items: s.items, isLoading: s.isLoading }))
```

### Reading from another store in an action (no subscription)
```ts
// In your store's action — use .getState() not a hook
import { useOtherStore } from './useOtherStore'

const myAction = () => {
  const otherValue = useOtherStore.getState().someField
  // use otherValue...
}
```

---

## Updating state correctly

### Only update changed fields
```ts
// Good: only creates new reference for the field that changed
set({ items: newItems })

// Bad: spreads all state, creates new references for everything
set((state) => ({ ...state, items: newItems }))
```

### Preserve references for unchanged nested state
```ts
// Good: preserve existing message references, only add new ones
set((state) => {
  const existingIds = new Set(state.messages.map((m) => m.id))
  const newMessages = incoming.filter((m) => !existingIds.has(m.id))
  if (newMessages.length === 0) return state // no-op — return same reference
  return { messages: [...state.messages, ...newMessages] }
})

// Bad: always creates new array even if nothing changed
set((state) => ({ messages: [...state.messages, ...incoming] }))
```

### Skip no-op updates
```ts
set((state) => {
  if (state.status === newStatus) return state // same reference = no re-render
  return { status: newStatus }
})
```

---

## High-frequency state (streaming)

If your store receives updates at high frequency (e.g., during AI streaming, ~60/sec):

1. **Gate behind a cheap check first**
```ts
// Check the most likely no-op condition before doing any work
set((state) => {
  if (state.streamingSessionId !== sessionId) return state
  // ... expensive update
})
```

2. **Isolate hot consumers in separate components**
```tsx
// Extract the streaming indicator into its own component
const StreamingIndicator = React.memo(({ sessionId }: { sessionId: string }) => {
  const isStreaming = useMyStore((s) => s.streamingBySession[sessionId])
  return isStreaming ? <Spinner /> : null
})
```

3. **Do not put streaming state in broadly consumed stores**
   - If only 2 components need it, it belongs in a narrow store
   - Shell/layout components must not subscribe to high-frequency data

---

## Async data fetching pattern

```ts
interface MyDataState {
  data: MyData | null
  isLoading: boolean
  error: string | null
  fetchData: (id: string) => Promise<void>
}

export const useMyDataStore = create<MyDataState>()(
  devtools(
    (set) => ({
      data: null,
      isLoading: false,
      error: null,

      fetchData: async (id) => {
        set({ isLoading: true, error: null })
        try {
          const data = await api.getData(id)
          set({ data, isLoading: false })
        } catch (err) {
          set({ error: err.message, isLoading: false })
        }
      },
    }),
    { name: 'MyDataStore' }
  )
)
```

---

## Optimistic updates pattern

```ts
// Shadow Map pattern for optimistic updates
interface MyOptimisticState {
  items: Map<string, Item>
  optimisticItems: Map<string, Item> // shadow map
  addOptimistic: (item: Item) => void
  confirmOptimistic: (id: string, serverItem: Item) => void
  rollbackOptimistic: (id: string) => void
}

// In the action:
addOptimistic: (item) => set((state) => {
  const optimisticItems = new Map(state.optimisticItems)
  optimisticItems.set(item.id, item)
  return { optimisticItems }
}),

confirmOptimistic: (id, serverItem) => set((state) => {
  const items = new Map(state.items)
  const optimisticItems = new Map(state.optimisticItems)
  items.set(id, serverItem)
  optimisticItems.delete(id)
  return { items, optimisticItems }
}),

rollbackOptimistic: (id) => set((state) => {
  const optimisticItems = new Map(state.optimisticItems)
  optimisticItems.delete(id)
  return { optimisticItems }
}),
```

---

## Checklist

- [ ] Checked if an existing store can be extended instead
- [ ] Store grouped by change frequency (not by convenience)
- [ ] `devtools` middleware added with a descriptive name
- [ ] `persist` middleware added only if state should survive page reload
- [ ] Actions only update changed fields (no full state spread)
- [ ] No-op updates return the same state reference
- [ ] High-frequency state isolated from broadly consumed stores
- [ ] Cross-store reads use `.getState()` not hooks
- [ ] Components use leaf selectors not container selectors
- [ ] `bun run type-check` passes
- [ ] `bun run lint` passes
