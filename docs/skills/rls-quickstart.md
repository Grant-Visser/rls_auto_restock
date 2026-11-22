# RLS Companion Mod — Quickstart & Quick Wins

Copy-paste shortcuts for the common moves, from rls_auto_restock's actual working code.

## Skeleton that loads

1. `scripts/<name>/modScript.lua`:
   ```lua
   setExtensionUnloadMode("YourExt", "manual")
   core_jobsystem.create(function(job)
     job.sleep(0.25)
     if not extensions.isExtensionLoaded("YourExt") then extensions.load("YourExt") end
   end)
   ```
2. `lua/ge/extensions/yourExt.lua` — camelCase file name, module table `M`, hooks
   `onCareerActivated`, `onOverhaulActive(active)`, `onUpdate(_, dtSim)`,
   `onOverhaulSaveCurrentProfile(savePath)`.
3. Optional career-module manifest `gameplay/overhaul/career/modules/yourExt.json`
   (`{"id": "yourExt", "order": 900, "module": "yourExt"}`) — idempotent alongside the
   modScript load, and gives you RLS-managed unload.

## Console cheat sheet (unpacked install)

```lua
-- reload Lua extension
extensions.unload("yourExt"); extensions.load("yourExt")

-- hot-reload all UI mods (entry points + .vue)
guihooks.trigger("UiModsChanged")

-- everything (Lua + UI)
extensions.unload("yourExt"); extensions.load("yourExt"); guihooks.trigger("UiModsChanged")

-- check what the VFS can see
print(tostring(FS:fileExists("/lua/ge/extensions/yourExt.lua")))
print(tostring(FS:fileExists("/ui/ui-vue/mods/<name>/ui/YourPanel.vue")))
```

- UI-only changes usually hot-reload on save (file watcher); the trigger is the manual fallback.
- `Ctrl+L` reloads the whole UI — the sledgehammer when styles/layouts degrade.
- Layout damage (unstyled sidebar, stacked panes) = hot-reload artifact → **restart the game**.

## Quick win: a tab in RLS's business computer

1. `gameplay/overhaul/business/types/<name>-tabs.json`:
   ```json
   {
     "id": "<name>-tabs",
     "order": 0,
     "businessType": "passiveBusiness",
     "namespace": "<name>",
     "tabs": [{
       "id": "<name>-panel",
       "label": "Your Panel",
       "component": "/ui/ui-vue/mods/<name>/ui/YourPanel.vue",
       "order": 5,
       "section": "BUSINESS",
       "entry": true
     }]
   }
   ```
   `order: 0` makes your entry the first catalog entry — the resolver matches you immediately
   (matters because of the `views` bug — see pitfalls.md).
2. `ui/ui-vue/mods/<name>/index.js` with `export async function onLoad() {}` /
   `onUnload() {}`.
3. `ui/ui-vue/mods/<name>/ui/YourPanel.vue` — `props.data.businessId` is your store id.

## Quick win: call your Lua from the panel (bridge-proof)

```js
function callLua(path, ...args) {
  const api = window.bngApi || window.beamng
  const serialized = args.map(a =>
    typeof api.serializeToLua === "function" ? api.serializeToLua(a) : "nil").join(", ")
  const [root, ...rest] = path.split(".")
  const expr = `(function() local m = rawget(_G, ${JSON.stringify(root)}) ` +
    `if type(m) ~= "table" then return nil end local f = m[${JSON.stringify(rest.join("."))}] ` +
    `if type(f) ~= "function" then return nil end return f(${serialized}) end)()`
  return new Promise(resolve => api.engineLua(expr, resolve))
}

const data = await callLua("yourExt.getStoreData", businessId)
```

## Quick win: live patch every RLS catalog instance

```js
setInterval(() => {
  const cache = window.__rtModules
  if (!cache) return
  cache.forEach(mod => {
    const m = mod && (mod.exports || mod)
    if (m && typeof m.getBusinessTabComponent === "function" && m.businessTypes) {
      if (!m.__shimmed) {
        m.getBusinessTabComponent = safeWrapper(m.getBusinessTabComponent)  // try/catch + array checks
        m.__shimmed = true
      }
      const types = m.businessTypes.value || []
      for (const t of types) if (t.views !== undefined && !Array.isArray(t.views)) t.views = []
    }
  })
}, 3000)
```

## Quick win: spend money through RLS

```lua
local attrs = rawget(_G, "overhaul_career_economy_playerAttributes")
if (attrs.getAttributeValue("money") or 0) < cost then return false end
rawget(_G, "overhaul_career_economy_payment").pay(
  { money = { amount = cost, canBeNegative = false } },
  { category = "business", label = "Your service fee" })
```

## Quick win: notify + persist

```lua
guihooks.trigger("toastrMsg", { type = "info", title = "Dispatched", msg = "..." })
overhaul_career_saveSystem.jsonWriteFileSafe(savePath .. "/career/rls_career/" .. file, data, true)
```

## Release discipline

Bump the version in the Lua extension *and* the UI entry point, tag `vX.Y.Z`, and attach a zip
whose **content sits at the zip root** (`lua/`, `gameplay/`, `scripts/`, `ui/`) with forward
slash separators (`tar -a -c -f out.zip ...`, not PowerShell `Compress-Archive`, which writes
backslashes). Log lines then identify any installed build in one grep.
