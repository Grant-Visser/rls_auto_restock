import { loadModule } from "@/services/uiMods"

const PANEL = "/ui/ui-vue/mods/rls_auto_restock/ui/AutoRestockPanel.vue"
const RLS_CATALOG = "/ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/utils/businessTypeCatalog.js"
const RLS_STORE = "/ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/stores/businessComputerStore.js"

const fail = err => (err && (err.message || err)) || String(err)
const MOD_VERSION = "1.0.3"

export async function onLoad() {
  console.warn("[rls_auto_restock] UI entry point loaded (v" + MOD_VERSION + ")")
  try {
    const mod = await loadModule(PANEL)
    console.warn("[rls_auto_restock] panel module ready: " + typeof (mod && mod.default))
  } catch (err) {
    console.warn("[rls_auto_restock] panel module FAILED: " + fail(err))
    return
  }

  setTimeout(async () => {
    try {
      const catalog = await import(RLS_CATALOG)
      const list = catalog.businessTypes.value || []
      console.warn("[rls_auto_restock] catalog entries: " + list.map(t => t.id).join(", "))
      const mine = list.find(t => t.id === "rls-auto-restock-tabs")
      if (!mine) {
        console.warn("[rls_auto_restock] PROBE: my entry is MISSING from the catalog")
      } else {
        console.warn("[rls_auto_restock] my entry keys: " + Object.keys(mine).join(", "))
        console.warn("[rls_auto_restock] my tabs json: " + JSON.stringify(mine.tabs))
      }
      for (const t of list) {
        console.warn("[rls_auto_restock] type " + t.id + " views=" + JSON.stringify(t.views ?? null)
          + " isArray=" + Array.isArray(t.views))
      }
      const comp = catalog.getBusinessTabComponent(PANEL)
      console.warn("[rls_auto_restock] resolver output: " + (comp ? "component object" : "NULL"))
    } catch (err) {
      console.warn("[rls_auto_restock] catalog probe failed: " + fail(err))
    }

    let ticks = 0
    const timer = setInterval(async () => {
      ticks++
      if (ticks > 120) { clearInterval(timer); return }
      try {
        const mod = await import(RLS_STORE)
        const store = mod.useBusinessComputerStore()
        if (!store || !store.businessId) return
        const tabs = store.registeredTabs || []
        const active = tabs.find(t => t.id === store.activeView) || null
        console.warn("[rls_auto_restock] session: businessId=" + store.businessId
          + " activeView=" + JSON.stringify(store.activeView)
          + " tabs=" + tabs.map(t => (t.id || "?") + "|" + (t.component || "?")).join(" ; ")
          + " activeTab=" + (active ? JSON.stringify({ id: active.id, component: active.component }) : "none"))
        clearInterval(timer)
      } catch (err) {
        console.warn("[rls_auto_restock] session store probe failed: " + fail(err))
        clearInterval(timer)
      }
    }, 5000)
  }, 6000)
}

export async function onUnload() {}
