# Writing an RLS Career Companion Extension (Lua)

A companion mod is a normal BeamNG mod that never edits `rls_career_overhaul.zip`.
File layout that works:

```
rls_auto_restock/
├── gameplay/overhaul/business/types/<name>.json     ← business computer tab (optional)
├── gameplay/overhaul/career/modules/<name>.json     ← career-module registration (optional)
├── lua/ge/extensions/<Name>.lua                     ← the engine extension
├── scripts/<name>/modScript.lua                     ← loads the extension at game start
└── ui/ui-vue/mods/<name>/...                        ← UI (see ui-integration.md)
```

Use **camelCase for the Lua file name** (`rlsAutoRestock.lua` → global `rlsAutoRestock`).
An underscored file name would become `rls__auto__restock` in the extension global.

## modScript.lua — the load pattern

```lua
setExtensionUnloadMode("rlsAutoRestock", "manual")
core_jobsystem.create(function(job)
  job.sleep(0.25)
  if not extensions.isExtensionLoaded("rlsAutoRestock") then
    extensions.load("rlsAutoRestock")
  end
end)
```

`manual` unload mode is what keeps your extension (and its timers) alive across map travel;
`core_jobsystem` deferral dodges BeamNG's modScript loader wrapper.

## Guards — every RLS touch is optional

```lua
local function getExt(name) return rawget(_G, name) end

function M.onUpdate(_, dtSim)
  local career = getExt("overhaul_career_career")
  if not career or not career.isActive() then return end
  if (tonumber(dtSim) or 0) <= 0 then return end   -- paused
  ...
end
```

Wrap every RLS call in `pcall`. Resolve `rawget(_G, ...)` lazily — RLS modules load at career
start, possibly after yours. If a lookup fails, retry next tick rather than erroring.

## Reading RLS module-locals — the upvalue anchor

RLS keeps store state in a local table with **no public accessor**. Reach it once:

```lua
local anchor
local function resolveAnchor()
  if anchor then return anchor end
  local passive = rawget(_G, "overhaul_career_business_passive")
  if not passive then return nil end
  -- BFS the upvalues of a public function until a closure over "properties" is found
  local found
  walkUpvalues(passive.getUIData, function(fn, index, name, value)
    if not found and name == "properties" and type(value) == "table" then
      found = { fn = fn, index = index }
    end
  end, {}, 8)
  anchor = found
  return anchor
end

local function passiveProperties()
  local a = resolveAnchor()
  if not a then return nil end
  local ok, _, value = pcall(debug.getupvalue, a.fn, a.index)
  if ok and type(value) == "table" then return value end
  anchor = nil   -- RLS may have replaced the table; re-resolve next tick
  return nil
end
```

**Critical gotcha:** RLS's `loadData()` *reassigns* `properties = {}` on every career load.
Do not cache the table itself — cache the **anchor function + upvalue index** and re-read it
each tick. `debug.getupvalue` returns the current cell contents, so the anchor survives the swap.

Stock **BeamNG 0.40 extensions only receive update ticks while a career is loaded**, so
`onUpdate` must also be guarded against `nil` RLS globals and `dtSim == 0` (paused).

## Persistence — RLS's own save slot

```lua
function M.onOverhaulSaveCurrentProfile(currentSavePath)
  local path = currentSavePath .. "/career/rls_career/" .. SAVE_FILE
  local saveSystem = rawget(_G, "overhaul_career_saveSystem")
  pcall(saveSystem.jsonWriteFileSafe, path, payload, true)   -- joins the save pipeline
end
```

Load on `onCareerActivated()`/`onOverhaulActive(true)` via
`select(2, saveSystem.getCurrentProfile())`. Sanitize everything you read back (versions change,
users hand-edit). Persist in-flight state (timers) so deliveries survive reloads.

## Money — spend through RLS's pipeline

```lua
overhaul_career_economy_payment.pay(
  { money = { amount = total, canBeNegative = false } },
  { category = "business", label = "Auto-restock driver order" }
)
```

Check affordability first with
`overhaul_career_economy_playerAttributes.getAttributeValue("money")`.
Optionally mirror RLS's per-store finance history by appending to
`state.financeHistory` / `state.financeTotals` — the Finances tab renders it verbatim.

Prices are indexed by the global economy: multiply by
`overhaul_career_economy_globalEconomy.getGlobalIndex()` and floor.

## Notifications

```lua
guihooks.trigger("toastrMsg", { type = "success", title = "Store restocked",
  msg = "Virtual driver delivered +8 pallets | Driver fee: $214" })
```

## Delivery timers that beat consumption

```lua
local base = tier == "express" and 20 or 45
local timeUntilEmpty = (stock - 1) * cycleSeconds + (cycleSeconds - cycleProgress)
local duration = math.max(5, math.min(base, timeUntilEmpty * 0.5))
```

Tick with a sim-time accumulator (1s steps are plenty — the fastest store cycle is 6 minutes),
credit `stock` clamped to capacity on completion, and re-run the trigger check per tick.
