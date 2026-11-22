# RLS Companion Mod — Pitfalls & Revelations

Everything that cost us a debugging session, distilled. Versions: RLS v2.8.0, BeamNG 0.40.x.

## Lua / engine side

- **RLS is not `career/modules`** — it is the `overhaul` namespace with its own manifest-driven
  loader. Don't build against the folder layout the wiki suggests.
- **`luaPathToExtName` doubles underscores**: prefer camelCase Lua file names so your extension
  global stays clean.
- **`extensions` is a magic table**: `extensions.someExt ~= nil` can throw
  "attempt to perform arithmetic on field" once loaded. Use `isExtensionLoaded` / `dump`.
- **Manual unload mode** (`setExtensionUnloadMode(name, "manual")`) is required for extensions
  that must survive map travel; RLS's own manager sets it for the same reason.
- **Module-locals are the API**: RLS state lives in closure tables. Use a
  `debug.getupvalue` anchor (function + index), not a cached table reference — RLS reassigns
  its state table on every career load.
- **`onOverhaulSaveCurrentProfile`** is RLS's save hook (fires on every autosave rotation);
  `onCareerActivated` and `onOverhaulActive(true/false)` bracket the career lifecycle.
- **Money is pallets**: store stock is consumed one pallet per `cycleSeconds`; "units" in UI
  copy should say pallets or users will misread profits.
- **The global economy index** (`getGlobalIndex`) scales all RLS prices — index every cost or
  your fees drift from the game's.
- **`jsonWriteFileSafe` joins the save pipeline** — never `jsonWriteFile` into a save slot.
- **Empty Lua tables serializing to the UI become `{}`** — there is no array marker. Never rely
  on an empty JSON array surviving a Lua round-trip.

## UI side

- **The `lua` bridge namespace list is RLS-curated.** Companion extensions are `undefined` on
  the wrapped bridge. Use RLS's `rawget(_G, ...)` + `engineLua` fallback pattern directly.
- **The business-type catalog validation is silent-fatal**: a rejected manifest logs one
  warning and your tab simply doesn't exist. The namespace-prefixed id rule
  (`id` must start with `namespace + "-"` and match the file name) bit us once.
- **`views: []` in RLS's tuningShop manifest round-trips to `{}`** and breaks
  `getBusinessTabComponent` with `(type.views || []).find is not a function` for every tab that
  resolves after that entry. Fix by sanitizing live instances, not by shipping a VFS override.
- **`entry: true` tabs are the only manifest tabs that reach the sidebar**; they must be
  namespaced. Non-entry tabs are just component aliases.
- **`businessId` is injected into tab data** by BusinessComputerMain — your component reads
  `props.data.businessId`, no plumbing needed.
- **A failed async component leaves a blank tab with no UI error.** Always render visible
  connection states and log in `<script setup>`.
- **There are two stores with overlapping names**: `businessComputerStore` (view mode) vs
  `businessSessionStore` (businessId, registeredTabs, activeView). Probing the wrong one
  silently returns empty state.
- **CEF console lines reach beamng.log** — `console.warn` from UI code is your free telemetry.

## Process side

- **Zip mods are not watched**: replace-with-zip while running = "mod vanished" + stale mounts.
  Unpacked installs hot-reload from the file system.
- **Every `UiModsChanged` unloads mod directories from the runtime graph** — styles vanish,
  module instances split, patches die. Patch by scanning `window.__rtModules` continuously, and
  restart the game when the UI state degrades.
- **Unpacked-vs-zip VFS priority is not guaranteed** — don't build on file overrides of RLS
  data. Sanitize at runtime instead.
- **`FS:fileExists` + `dump` of booleans is unreadable** — wrap results in `print(tostring(x))`.
- **Version-stamp both logs** (Lua + UI entry). It converts "is it the new build?" from a
  question into a grep.
- **Read RLS's shipped source**: the manifests' validators tell you the contract better than
  any wiki, and RLS's code is commented and readable.

## Revelations that felt surprising

- RLS's extension manager scans manifest folders *fresh* on every career start — companion
  modules join the career roster with nothing more than a manifest file.
- RLS's type catalog is designed for add-on tabs (`namespace`, `entry`) — the integration point
  is first-class, it's just strict.
- RLS's finance history is rendered from `state.financeHistory` rows — a companion can append
  rows that show up natively in the Finances tab.
- RLS's own business tabs worked while add-on tabs didn't because their names resolve *before*
  the poisoned catalog entry — order of iteration was the whole bug.
