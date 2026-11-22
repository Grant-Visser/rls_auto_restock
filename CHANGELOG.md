# Changelog

All notable changes to rls_auto_restock are documented here. The version also appears in the
game log (`RLS Auto-Restock companion vX.Y.Z loaded`) and in the UI entry log
(`[rls_auto_restock] UI entry point loaded (vX.Y.Z)`) so an installed build can always be
identified.

## [1.2.4] - 2026-11-22

### Fixed
- **v1.2.3 shipped the same ordering bug it claimed to fix**: the `ensureLoaded`/`currentSavePath`
  forward declarations were placed after `settingsFor`, so the global-nil error continued. The
  declarations now sit before every caller.

## [1.2.3] - 2026-11-22

### Fixed
- **Hot-reload settings regression**: `ensureLoaded` was referenced before its definition, so
  every `settingsFor` call after a hot-reload threw `attempt to call global 'ensureLoaded'`
  every second and settings self-heal never ran. Forward declarations now order the loader
  correctly (`ensureLoaded` is assigned after `loadFromSave`).

## [1.2.2] - 2026-11-22

### Changed
- **Auto-collect defaults to ON** for new stores, and saves written before v1.2.0 migrate once
  (save `CONFIG_VERSION` 1 → 2) so existing stores get auto-collect without visiting them.
  Per-store opt-out from the panel still persists.

## [1.2.1] - 2026-11-22

### Fixed
- BeamNG hot-reloads GE extensions when their source file changes, which reset the companion's
  in-memory settings (auto-collect and auto-restock toggles appeared to switch themselves off).
  Settings are now lazily reloaded from the career save on first use after any reload, and
  `persist()` is guarded so empty state can never overwrite saved settings.

## [1.2.0] - 2026-11-22

### Added
- **Auto-collect earnings**: per-store toggle on the Auto-Restock panel sweeps pending earnings
  into the wallet every 30s of active career play (cross-map — RLS accrues earnings on all
  maps), plus a manual "Collect now" button. Aggregated toast per sweep, wallet label
  ("Auto-collected <store> earnings") deliberately distinct from manual collections so RLS's
  finance backfill cannot double-count, and per-store finance history rows that render natively
  in the Finances tab. New setting `autoCollect` persists in the career save.

## [1.1.0] - 2026-11-22

### Fixed
- **"Auto-restock service unreachable" - the real bridge bug.** RLS's
  `installLuaBridgeFallbacks` wraps the UI's `lua` bridge and only creates call namespaces for
  extensions known to RLS; an extension loaded by a companion mod resolves to `undefined` on the
  wrapped bridge, so `lua.rlsAutoRestock.*` calls threw before reaching Lua. The panel now calls
  Lua through RLS's own proven pattern: a `rawget(_G, ...)`-based `engineLua` expression, which
  is independent of the bridge's namespace list.

## [1.0.9] - 2026-11-22

### Fixed
- `getStoreData` is fail-safe: any Lua-side error is caught, logged with its message, and returned
  as an error payload instead of breaking the UI bridge call. The first call per session is logged
  so a silent bridge failure is distinguishable from a Lua error.

## [1.0.8] - 2026-11-22

### Changed
- Reverted the v1.0.7 `tuningShop.json` override: VFS mount priority kept RLS's zip file winning,
  so the override never applied.
- The UI entry point now scans the runtime module cache every 3 seconds and patches every live
  business-type catalog instance: `getBusinessTabComponent` gets a safe wrapper (direct hit for
  the panel path, try/original/fallback for everything else) and degraded `views` fields are
  sanitized to empty arrays in place. This is what makes the Auto-Restock panel mount.

## [1.0.7] - 2026-11-22## [1.0.7] - 2026-11-22

### Fixed
- **Root cause fixed at the data level via a VFS file override.** RLS's
  `gameplay/overhaul/business/types/tuningShop.json` ships `"views": []` - an empty JSON array,
  which the Lua-to-UI JSON round-trip delivers as an empty *object* and breaks
  `getBusinessTabComponent` (`.find` is not a function) for every tab whose component does not
  match an earlier catalog entry. The companion now ships an override copy of that manifest with
  the empty `views` key removed. Unpacked mods take priority over zips in BeamNG's virtual file
  system, so RLS's own tuning shop and every add-on tab resolve cleanly again. The previous
  resolver shim remains as a safety net for future RLS regressions.
- Note for RLS updates: if rls_career_overhaul v2.9+ fixes the manifest, delete
  `gameplay/overhaul/business/types/tuningShop.json` from this mod so RLS's newer file is used.

## [1.0.6] - 2026-11-22

### Changed
- The resolver shim now short-circuits the Auto-Restock component path directly and logs every
  click-time resolution outcome.
- Session probe reads RLS's `businessSessionStore` (correct store).

## [1.0.5] - 2026-11-22

### Fixed
- **Blank tab made structurally impossible:** the UI entry point now installs a resolver shim on
  RLS's `getBusinessTabComponent`. The original throws when it reaches a type whose `views`
  field degraded to `{}` through the Lua round-trip (tuningShop ships an empty array); the shim
  falls back to a type-safe lookup (array checks) that returns the correct component. Applied
  on the shared module exports, so RLS's own business tabs benefit from the fallback too.

## [1.0.4] - 2026-11-22

### Added
- Persistent session probe: whenever the business computer state changes, the entry point logs
  `businessId`, `activeView`, the active tab's `component` and the live resolver output
  (component object / NULL / the exact thrown error) to the game log.
- `AutoRestockPanel.vue` logs when its setup runs, distinguishing mount failures from
  render failures.

## [1.0.3] - 2026-11-22

### Added
- `rlsAutoRestock.reloadUI()` Lua helper: triggers the UI's `UiModsChanged` hot reload, so
  `.vue`/manifest changes refresh without a game restart.
- README "Fast iteration" section documenting the unpacked-mod hot-reload workflow
  (`mods\unpacked\` + `UiModsChanged` + extension unload/load).

## [1.0.2] - 2026-11-22

### Fixed
- **Auto-Restock tab rendered empty.** RLS's `getBusinessTabComponent` iterates the business-type
  catalog and calls `.find()` on every type's `views` field. `tuningShop.json` ships
  `"views": []` (empty array), which the Lua-to-UI JSON round-trip delivers as an empty *object*
  (`{}`), and `({}).find` is not a function - so component resolution throws for any tab name
  that does not match an earlier catalog entry. Companion workaround: the manifest now sorts
  first (`order: 0`), so the resolver matches the Auto-Restock component on the first catalog
  entry and returns before the degraded `views` field is ever touched.

## [1.0.1]— 2026-11-22

### Fixed
- **Business-type manifest rejected by RLS's catalog** (blank: the Auto-Restock tab never
  appeared). RLS requires the manifest `id` to start with the manifest `namespace` followed by
  `-` and to match the file name; renamed to `rls-auto-restock-tabs.json` /
  `id: rls-auto-restock-tabs`.
- **Install layout** (README): unpacked mods belong in `mods\unpacked\<mod>\`, zip mods need the
  mod content at the zip root. A folder directly in `mods\` is silently ignored.
- Added `ui/ui-vue/mods/rls_auto_restock/index.js` UI entry point.

### Added
- Visible connection states in the panel: `Connecting…`, `Service unreachable`,
  `RLS Career Overhaul not detected` — failures are never a blank tab.
- Diagnostic probes: the UI entry point pre-compiles the panel module at load and logs the
  outcome (`[rls_auto_restock] panel module ready/FAILED`), then probes the business-type catalog
  entry, the component resolver output, and the live business-computer session state.
- Version identifiers in the Lua and UI logs.

## [1.0.0] — 2026-11-22

### Added
- Initial public release: per-store Auto-Restock tab in RLS passive-business computers
  (enable toggle, 25/50/75% threshold presets, Standard/Express driver tiers with itemized
  fees), simulated delivery timers guaranteed to beat each store's consumption rate, driver
  fee structure (base dispatch + cargo surcharge + distance surcharge), per-save persistence
  of settings and in-transit deliveries, notifications on dispatch and completion.
