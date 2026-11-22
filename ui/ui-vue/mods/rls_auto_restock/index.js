import { loadModule } from "@/services/uiMods"

const PANEL = "/ui/ui-vue/mods/rls_auto_restock/ui/AutoRestockPanel.vue"
const RLS_SESSION = "/ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/stores/businessComputer/businessSessionStore.js"

const MOD_VERSION = "1.2.0"
const fail = err => (err && (err.message || err)) || String(err)

let shimCount = 0
let rlsRuntimeComponent = null

function safeFallbackResolve(catalogInstance, name) {
  try {
    const types = catalogInstance.businessTypes.value || []
    for (const type of types) {
      const tabs = Array.isArray(type.tabs) ? type.tabs : []
      const tab = tabs.find(t => t.componentName === name || t.component === name)
      if (tab && tab.component) return tab.component
      const views = Array.isArray(type.views) ? type.views : []
      const view = views.find(v => v.id === name || v.component === name)
      if (view && view.component) return view.component
    }
  } catch (err) {
    console.warn("[rls_auto_restock] safe fallback resolve failed: " + fail(err))
  }
  return null
}

function patchCatalogModule(mod) {
  if (!mod || mod.__rlsAutoRestockPatched) return false
  try {
    if (typeof mod.getBusinessTabComponent !== "function") return false
    const original = mod.getBusinessTabComponent
    mod.getBusinessTabComponent = name => {
      if (name === PANEL) {
        console.warn("[rls_auto_restock] direct resolution for panel")
        return rlsRuntimeComponent ? rlsRuntimeComponent(PANEL) : null
      }
      try {
        return original(name)
      } catch (err) {
        console.warn("[rls_auto_restock] resolver shim engaged for " + JSON.stringify(name) + ": " + fail(err))
        const file = safeFallbackResolve(mod, name)
        return file && rlsRuntimeComponent ? rlsRuntimeComponent(file) : null
      }
    }
    mod.__rlsAutoRestockPatched = true
    shimCount++
    console.warn("[rls_auto_restock] resolver shim #" + shimCount + " installed on a live catalog instance")
    return true
  } catch (err) {
    console.warn("[rls_auto_restock] shim install failed: " + fail(err))
    return false
  }
}

function sanitizeCatalogData(mod) {
  try {
    const value = mod.businessTypes && mod.businessTypes.value
    if (!Array.isArray(value)) return
    let fixed = 0
    for (const type of value) {
      if (type && type.views !== undefined && !Array.isArray(type.views)) {
        type.views = []
        fixed++
      }
    }
    if (fixed) console.warn("[rls_auto_restock] sanitized " + fixed + " degraded views field(s) in a live catalog instance")
  } catch (err) {
    console.warn("[rls_auto_restock] sanitize pass failed: " + fail(err))
  }
}

function collectModuleCache() {
  const cache = (typeof window !== "undefined" && window.__rtModules) || null
  if (!cache) return []
  const result = []
  if (typeof cache.forEach === "function") {
    cache.forEach(value => result.push(value))
  } else {
    for (const key of Object.keys(cache)) result.push(cache[key])
  }
  return result
}

function scanAndPatch() {
  const modules = collectModuleCache()
  for (const entry of modules) {
    const mod = entry && (entry.exports || entry)
    if (mod && typeof mod.getBusinessTabComponent === "function" && mod.businessTypes) {
      patchCatalogModule(mod)
      sanitizeCatalogData(mod)
    }
  }
}

export async function onLoad() {
  console.warn("[rls_auto_restock] UI entry point loaded (v" + MOD_VERSION + ")")
  try {
    const mod = await loadModule(PANEL)
    console.warn("[rls_auto_restock] panel module ready: " + typeof (mod && mod.default))
  } catch (err) {
    console.warn("[rls_auto_restock] panel module FAILED: " + fail(err))
    return
  }

  try {
    const catalog = await import("/ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/utils/businessTypeCatalog.js")
    const runtime = await import("/ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/utils/runtimeComponent.js")
    rlsRuntimeComponent = runtime.runtimeComponent
    patchCatalogModule(catalog)
    sanitizeCatalogData(catalog)
  } catch (err) {
    console.warn("[rls_auto_restock] catalog patch failed: " + fail(err))
  }

  setInterval(scanAndPatch, 3000)

  try {
    const sessionMod = await import(RLS_SESSION)
    let lastSignature = ""
    setInterval(() => {
      try {
        const store = sessionMod.useBusinessSessionStore()
        const tabs = store.registeredTabs || []
        const active = tabs.find(t => t.id === store.activeView) || null
        const signature = JSON.stringify([store.businessId, store.activeView, tabs.length])
        if (signature === lastSignature || !store.businessId) return
        lastSignature = signature
        console.warn("[rls_auto_restock] session: businessId=" + store.businessId
          + " activeView=" + JSON.stringify(store.activeView)
          + " activeComponent=" + JSON.stringify(active ? active.component : null)
          + " tabs=" + tabs.map(t => t.id).join("|"))
      } catch (err) {
        console.warn("[rls_auto_restock] session probe tick failed: " + fail(err))
      }
    }, 3000)
  } catch (err) {
    console.warn("[rls_auto_restock] session probe setup FAILED: " + fail(err))
  }
}

export async function onUnload() {}
