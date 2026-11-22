# Debugging RLS Career Mods — the process that cracked it

The saga that produced these skills took nine versions. What follows is the exact diagnostic
playbook, roughly in the order that pays off.

## 0. Version-stamp everything first

Before anything else: put the version in both logs. `beamng.log` lines
`RLS Auto-Restock companion v1.0.9 loaded` and
`[rls_auto_restock] UI entry point loaded (v1.0.9)` remove half the ambiguity in every
back-and-forth ("which build is actually installed?").

## 1. beamng.log is the primary console — including CEF

`%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\beamng.log` (note: **BeamNG\BeamNG.drive**, not
BeamNG.drive). The GE Lua console, the Mod Manager mounts, **and CEF JavaScript `console.warn`/
`console.error` lines all land here**, prefixed like:

```
W|CEF.MainGEUI#/ui/ui-vue/mods/rls_auto_restock/index.js:13| [rls_auto_restock] ...
```

Emit warnings (`console.warn`) from Lua *and* UI, then grep the file. `dump()` output goes to
the game console; `print()` statements land as `GELua.print` lines.

## 2. Separate the layers, prove each one

Our failure chain had six layers. Instrument each in one release, read the log, repeat:

1. **VFS mounted?** `FS:fileExists("/lua/ge/extensions/...")`, `.../manifest.json`,
   `.../Panel.vue` — wrap in `print(tostring(...))`; `dump` of booleans is unreadable.
2. **Lua extension loaded and responsive?** `extensions.isExtensionLoaded("x")` +
   a log line in the extension's load hook, plus a "first call received" log in the entry-point
   function the UI calls.
3. **Catalog accepted your manifest?** Lua side:
   `local ok, m = pcall(require, 'overhaul/lib/business/typeCatalog') if ok and m then local r = m.listForUi() ... end`
   — print entry ids and every `rejected` reason. The catalog is where manifest rejection hides.
4. **Does the UI have the same data?** Import RLS's `businessTypeCatalog.js` from your own
   entry point and `JSON.stringify` the entry.
5. **Does the resolver return a component?** Wrap it, call it with your path, log component
   object / NULL / the exact throw.
6. **Does the component mount?** `console.warn` as the first statement of `<script setup>`.
   Absent line = never mounted (loader problem). Present line but blank UI = render problem.

## 3. Known console / diagnostic quirks

- The GE `extensions` global is a magic table; `extensions.someExt ~= nil` can error with
  "attempt to perform arithmetic on field" once the extension is loaded. Use
  `dump(extensions.someExt)` or `extensions.isExtensionLoaded("someExt")`.
- The UI's Lua bridge may throw *before* reaching Lua when RLS has wrapped it (see
  ui-integration.md, Trap 3) — the absence of your Lua "first call" log is itself a diagnosis.
- `engineLua` executed from the user console reports as `GELua(Sandboxed)`.

## 4. Read RLS's code, not its docs

Everything above came from reading RLS's own shipped sources: manifest validators
(`overhaul/lib/platform/catalog.lua`), the type catalog, the extension manager, the save
pipeline, and the UI's `businessTypeCatalog.js` / `runtimeComponent.js` /
`installLuaBridgeFallbacks.js`. RLS ships readable, commented code — the fastest path to
"what's the actual contract" is `grep` through the extracted zip.

## 5. The hot-reload dance

Unpacked mod + the console reload line (`see quickstart.md`) avoids restarts, **but** every
`UiModsChanged` cycle unloads mod directories from the runtime graph: styles can vanish from
mounted screens (business computer collapsing to an unstyled bullet list), module instances
split, and caches go stale. Treat a **full game restart as the state reset button** — do it
when layout damage appears or when results become inconsistent.

## 6. When the fix needs to be robust, patch *data* and *all instances*

- Module-level shims die on instance splits — re-apply periodically by scanning
  `window.__rtModules` and patching every live instance.
- Data-level sanitation (fixing degraded fields on the live objects) is instance-proof and
  fixes RLS's own screens as a bonus.
- Never ship a VFS file override assuming unpacked-beats-zip: mount priority is not
  guaranteed, and when it *is* applied it perturbs RLS's layout.

## 7. Fail-safe the boundary

Wrap the Lua functions your UI calls in `pcall`, return the error as a payload, and log it.
A UI poll that throws shows "service unreachable" forever with **zero** log output otherwise.
