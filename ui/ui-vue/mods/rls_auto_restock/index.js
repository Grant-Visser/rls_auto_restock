import { loadModule } from "@/services/uiMods"

const PANEL = "/ui/ui-vue/mods/rls_auto_restock/ui/AutoRestockPanel.vue"
const RLS = "/ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/utils/"
const RLS_CATALOG = RLS + "businessTypeCatalog.js"
const RLS_RUNTIME = RLS + "runtimeComponent.js"
const RLS_SESSION = "/ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/stores/businessComputer/businessSessionStore.js"

const MOD_VERSION = "1.0.7"
const fail = err => (err && (err.message || err)) || String(err)

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
    const catalog = await import(RLS_CATALOG)
    const { runtimeComponent } = await import(RLS_RUNTIME)

    if (typeof catalog.getBusinessTabComponent !== "function") {
      console.warn("[rls_auto_restock] resolver shim skipped: RLS catalog shape unexpected")
    } else if (!catalog.__rlsAutoRestockShimmed) {
      const original = catalog.getBusinessTabComponent
      catalog.getBusinessTabComponent = name => {
        if (name === PANEL) {
          console.warn("[rls_auto_restock] direct resolution for panel")
          return runtimeComponent(PANEL)
        }
        try {
          return original(name)
        } catch (err) {
          console.warn("[rls_auto_restock] resolver shim engaged for " + JSON.stringify(name) + ": " + fail(err))
          let file = null
          for (const type of catalog.businessTypes.value || []) {
            const tabs = Array.isArray(type.tabs) ? type.tabs : []
            const tab = tabs.find(t => t.componentName === name || t.component === name)
            const views = Array.isArray(type.views) ? type.views : []
            const view = views.find(v => v.id === name || v.component === name)
            file = (tab && tab.component) || (view && view.component)
            if (file) break
          }
          return file ? runtimeComponent(file) : null
        }
      }
      catalog.__rlsAutoRestockShimmed = true
      console.warn("[rls_auto_restock] resolver shim installed")
    }

    if (typeof runtimeComponent === "function" && !catalog.__rlsAutoRestockRtLogged) {
      const rt = runtimeComponent(PANEL)
      console.warn("[rls_auto_restock] runtimeComponent(PANEL) returned: " + (rt ? "component" : "falsy"))
      catalog.__rlsAutoRestockRtLogged = true
    }
  } catch (err) {
    console.warn("[rls_auto_restock] resolver shim FAILED: " + fail(err))
  }

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
