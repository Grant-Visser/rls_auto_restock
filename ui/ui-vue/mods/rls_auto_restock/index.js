import { loadModule } from "@/services/uiMods"

const PANEL = "/ui/ui-vue/mods/rls_auto_restock/ui/AutoRestockPanel.vue"
const RLS_CATALOG = "/ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/utils/businessTypeCatalog.js"
const RLS_STORE = "/ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/stores/businessComputerStore.js"

const fail = err => (err && (err.message || err)) || String(err)

export async function onLoad() {
  console.warn("[rls_auto_restock] UI entry point loaded")
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
      const comp = catalog.getBusinessTabComponent(PANEL)
      console.warn("[rls_auto_restock] resolver output: " + (comp ? "component object" : "NULL"))
    } catch (err) {
      console.warn("[rls_auto_restock] catalog probe failed: " + fail(err))
    }

    try {
      const mod = await import(RLS_STORE)
      const store = mod.useBusinessComputerStore()
      const tabs = store.registeredTabs || []
      console.warn("[rls_auto_restock] session activeView: " + JSON.stringify(store.activeView))
      console.warn("[rls_auto_restock] session tabs: " + tabs.map(t => (t.id || "?") + "|" + (t.component || "?")).join(" ; "))
    } catch (err) {
      console.warn("[rls_auto_restock] session store probe failed: " + fail(err))
    }
  }, 6000)
}

export async function onUnload() {}
