# RLS Career Overhaul — Mod Architecture

Verified against **RLS Career Overhaul v2.8.x** on **BeamNG.drive 0.40.x**.

> The public-facing assumption "RLS uses `lua/ge/extensions/career/modules/`" is wrong.
> RLS v2.8 runs everything under its own **`overhaul`** namespace with a manifest-driven
> extension system. Build against what is there, not what the folder layout suggests.

## The namespace

Every RLS Lua file lives at `lua/ge/extensions/overhaul/<area>/<thing>.lua` and is loaded by
RLS's own extension manager (`overhaul_shell_extensionManager`, booted from
`scripts/rls_career_overhaul/modScript.lua`). Extension globals follow the engine convention
`luaPathToExtName`: path separators become `_`, so `overhaul/career/business/passive` becomes
the global **`overhaul_career_business_passive`**. RLS file names are camelCase on purpose —
underscores inside a file name would double into `__` in the extension name.

## Manifests — the load-order backbone

Three manifest directories are scanned **fresh** (no central roster — add-on mods are
discovered just by being mounted):

| Directory | Purpose |
| --- | --- |
| `gameplay/overhaul/career/modules/*.json` | Career modules: `{id, order, module}`. `id` must equal `extensionName(module)`, the file name must match `id`, `order` must be a number. Loaded at career start in order. |
| `gameplay/overhaul/career/owners/*.json` | Owner policies: private modules, folders, shell scopes. |
| `gameplay/overhaul/business/types/*.json` | Business-type descriptors: tabs, sections, capabilities, module owner. **Add-on tab extensions** declare `businessType` + `namespace` and must not declare `module`/`capabilities`/`skillNodes`. |

Manifest validation is strict and **silently warns into the log only**:
- ids match `^[%w][%w%._%-]*$` and must equal the file name,
- a manifest with a `namespace` must have its own `id` start with `namespace .. "-"`,
- components must match `^/ui/ui%-vue/mods/[^/]+/.+%.vue$` (no `..`, no backslashes).

The type catalog (`overhaul/lib/business/typeCatalog.lua`) scans
`gameplay/overhaul/business/types/` on every fetch; the UI-side catalog merges its builtins by
`id`, Lua entries win.

## Hooks the engine dispatches

`extensions.hook` calls a named method on **every loaded extension**. RLS relies on:

- `onCareerActivated()` — fired through the stock career path,
- `onOverhaulActive(active, newSave)` — RLS's own career-active transition (true on entry,
  false on teardown) fired in `overhaul/career/career.lua` + `career/start/transitions.lua`,
- `onOverhaulSaveCurrentProfile(currentSavePath, vehiclesThumbnailUpdate, writer)` — fired by
  RLS's save pipeline for every career save (autosave rotation included),
- `onUpdate(dtReal, dtSim, dtRaw)` — every frame; guard with
  `overhaul_career_career.isActive()` and `dtSim > 0`.

If your companion defines these on its returned module table, it participates in the same
lifecycle without touching RLS.

## Where store/business state lives

`overhaul_career_business_passive` owns passive businesses (the stores: Mini Mart, Cafe,
Boutique, Supermarket, Nail Salon, Gift Shop, Jewelry Store, Dry Cleaner, Specialty Retail,
Dino Cafe). Its state is a **module-local table** — there is no public accessor for it:

- `properties[id]` — `archetypeId`, `mapId`, `stock` (pallets), `storageLevel`,
  `cycleProgress`, `uncollectedEarnings`, `wholesaleOwned`, `operating`,
  `outOfStockNotified`, `financeHistory`, `financeTotals`.
- Config comes from `gameplay/overhaul/business/passiveBusinessArchetypes.json`
  (public data — `jsonReadFile` it yourself).
- Production: one pallet per `cycleSeconds` while `operating` and `stock > 0`.
- Runtime until empty: `(stock - 1) * cycleSeconds + (cycleSeconds - cycleProgress)`.
- Ownership check: `overhaul_career_business_manager.isPurchasedBusiness("passiveBusiness", id)`.
- Money: `overhaul_career_economy_playerAttributes.getAttributeValue("money")`,
  payments via `overhaul_career_economy_payment.pay/reward` with plain reason tables.
- Facilities/logistics: `overhaul_world_facilities`, `overhaul_career_logistics_generator`
  (`getFacilityById`, `getLocationCoordinates`, `getDistanceBetweenFacilities`).

See [extension-development.md](extension-development.md) for how to read and write that state
safely from a companion mod.
