# Changelog

All notable changes to rls_auto_restock are documented here. The version also appears in the
game log (`RLS Auto-Restock companion vX.Y.Z loaded`) and in the UI entry log
(`[rls_auto_restock] UI entry point loaded (vX.Y.Z)`) so an installed build can always be
identified.

## [1.0.1] — 2026-11-22

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
