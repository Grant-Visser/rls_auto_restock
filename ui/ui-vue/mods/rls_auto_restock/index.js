import { loadModule } from "@/services/uiMods"

const PANEL = "/ui/ui-vue/mods/rls_auto_restock/ui/AutoRestockPanel.vue"
const RLS_CATALOG = "/ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/utils/businessTypeCatalog.js"
const RLS_STORE = "/ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/stores/businessComputerStore.js"

const MOD_VERSION = "1.0.4"
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

  setTimeout(async () => {
    let catalog, storeMod
    try {
      catalog = await import(RLS_CATALOG)
      storeMod = await import(RLS_STORE)
    } catch (err) {
      console.warn("[rls_auto_restock] probe imports failed: " + fail(err))
      return
    }

    let lastSignature = ""
    setInterval(() => {
      try {
        const store = storeMod.useBusinessComputerStore()
        const tabs = store.registeredTabs || []
        const active = tabs.find(t => t.id === store.activeView) || null
        const signature = JSON.stringify([store.businessId, store.activeView, tabs.length])
        if (signature === lastSignature || !store.businessId) return
        lastSignature = signature

        let resolverResult = "skipped"
        if (active && active.component) {
          try {
            resolverResult = catalog.getBusinessTabComponent(active.component) ? "component object" : "NULL"
          } catch (err2) {
            resolverResult = "THREW: " + fail(err2)
          }
        }
        console.warn("[rls_auto_restock] session: businessId=" + store.businessId
          + " activeView=" + JSON.stringify(store.activeView)
          + " activeComponent=" + JSON.stringify(active ? active.component : null)
          + " resolver=" + resolverResult
          + " tabs=" + tabs.map(t => t.id).join("|"))
      } catch (err) {
        console.warn("[rls_auto_restock] session probe tick failed: " + fail(err))
      }
    }, 3000)
  }, 6000)
}

export async function onUnload() {}
