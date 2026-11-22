# RLS Business-Computer UI Integration

How an add-on gets a tab into RLS's business computer, and the three traps that will eat
your afternoon.

## The component resolution chain

```
gameplay/.../types/<addon>.json          (Lua catalog scan, every fetch)
  → listForUi() → UI bridge → businessTypeCatalog (createCatalog)
    → projectBusinessTabs(businessType, luaTabs, sectionIds)   ← sidebar projection
      → sessionStore.registeredTabs                            ← sidebar renders
        → BusinessComputerMain: getBusinessTabComponent(tab.component)
          → runtimeComponent(vfsPath) → loadModule(vfsPath)    ← runtime SFC compile
```

Tab data receives `businessId`/`businessType` injected automatically
(`activeTabData = {...tab.data, businessId: sessionStore.businessId, ...}`).

## Manifest — the add-on tab

```json
{
  "id": "rls-auto-restock-tabs",
  "order": 0,
  "businessType": "passiveBusiness",
  "namespace": "rls-auto-restock",
  "tabs": [{
    "id": "rls-auto-restock-panel",
    "label": "Auto-Restock",
    "icon": "<path d=\"M1 3h15v13H1z\"/>",
    "component": "/ui/ui-vue/mods/rls_auto_restock/ui/AutoRestockPanel.vue",
    "order": 5,
    "section": "BUSINESS",
    "entry": true
  }]
}
```

Rules that rejected our first attempt (warnings only — the tab just doesn't exist):
- the manifest's **own `id` must start with `namespace` + `-`** and match the file name,
- `entry: true` tab ids must be namespace-prefixed,
- component paths are regex-validated, not existence-checked.

## Trap 1 — the empty-array JSON round-trip

`tuningShop.json` ships `"views": []`. Lua's `jsonReadFile` makes that an empty table, and
the Lua→UI bridge serializes it back as an **empty object `{}`** — Lua cannot express "empty
array". RLS's resolver then calls `(type.views || []).find(...)` and `({}).find` is
"not a function": **component resolution throws for any tab whose name doesn't match an
earlier catalog entry.** RLS's own tabs survive because their names match before the poisoned
entry is reached; every add-on tab dies.

Fixes that work, in order of robustness:
1. **Sanitize live data**: on a 3s timer, walk `window.__rtModules` (the runtime graph's module
   cache), find every instance with `getBusinessTabComponent` + `businessTypes`, and set
   `type.views = []` when `!Array.isArray(type.views)`. Fixes RLS's own tabs too.
2. **Shim the resolver** per instance: try the original, on throw re-run the lookup with
   array checks. Wrap the function on the module's `exports` object — RLS views call it as a
   property access, so the patch is live — **but re-apply after every reload** (see Trap 2).
3. `order: 0` on your own manifest so the resolver matches you on the first entry — helpful,
   but not sufficient alone, because the poisoned entry is *second*.

Do **not** ship a VFS override of RLS's `tuningShop.json`: unpacked-vs-zip mount priority is
not guaranteed, and when it does apply it perturbs RLS's layout.

## Trap 2 — module instance splits after every hot-reload

Every `UiModsChanged` → `loadMods(true)` → `resetComponentCache` per mod directory **unloads
the directory from the runtime graph**. Next import = a brand-new module instance with brand-new
state. A patch installed on "the" catalog module silently applies to the wrong copy.

Pattern that survives: a periodic scanner over `window.__rtModules` (values are CJS export
objects; guard `mod.exports || mod`) that re-applies shims and re-sanitizes data on **every
instance it finds**, forever. Idempotency marker: `mod.__rlsAutoRestockPatched`.

## Trap 3 — the `lua` bridge namespace list

RLS's `installLuaBridgeFallbacks.js` wraps the UI's `lua` bridge and only creates callable
namespaces for extensions RLS knows (`MOD_NAMESPACES` is generated from their ui-owners
catalogs). **A companion extension resolves to `undefined` on the wrapped bridge**, so
`lua.yourExtension.method(...)` throws a TypeError in the browser — the call never reaches Lua,
no Lua error is logged, and your panel shows a blank tab.

Fix: call Lua the way RLS's own fallbacks do — a `rawget(_G, ...)`-based `engineLua` expression:

```js
function callLua(path, ...args) {
  const api = window.bngApi || window.beamng
  const serialized = args.map(a =>
    typeof api.serializeToLua === "function" ? api.serializeToLua(a) : "nil").join(", ")
  const [root, ...rest] = path.split(".")
  const expr = `(function() local m = rawget(_G, ${JSON.stringify(root)}) ` +
    'if type(m) ~= "table" then return nil end ' +
    `local f = m[${JSON.stringify(rest.join("."))}] ` +
    `if type(f) ~= "function" then return nil end return f(${serialized}) end)()`
  return new Promise(resolve => api.engineLua(expr, resolve))
}
```

Works regardless of the bridge's namespace list. (Keep result shapes free of empty
arrays for the same round-trip reason as Trap 1.)

## UI mod entry point

`ui/ui-vue/mods/<name>/index.js` exporting `onLoad()`/`onUnload()` registers the directory with
the runtime loader (BeamNG's `runModEntryPoints` requires it) and lets you install your
bridge/shim instrumentation exactly when RLS's is installed.

## Runtime module loading

`loadModule(vfsPath)` from `@/services/uiMods` compiles any `.vue` under `mods/<mod>/` at
runtime — cross-mod, no build step. The async wrapper caches per file; on error it rethrows
(`Could not load <file>`) and a failed record can leave the tab blank with **no UI error** —
so give the component visible connection states (`Connecting…` / unreachable / incompatible)
and a `console.warn` at the top of `setup`.

## Events UI ← Lua

`guihooks.trigger("YourEvent", payload)` → `useEvents().on("YourEvent", handler)` —
use it for state pushes on dispatch/completion; poll the bridge for countdowns.
