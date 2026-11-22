import { loadModule, getComponent } from "@/services/uiMods"

const PANEL = "/ui/ui-vue/mods/rls_auto_restock/ui/AutoRestockPanel.vue"

export async function onLoad() {
  console.warn("[rls_auto_restock] UI entry point loaded")
  try {
    const mod = await loadModule(PANEL)
    console.warn("[rls_auto_restock] panel module ready: " + typeof (mod && mod.default))
  } catch (err) {
    const msg = (err && (err.message || err)) || String(err)
    console.warn("[rls_auto_restock] panel module FAILED: " + msg)
    try {
      const data = await getComponent(PANEL, false, true)
      const state = data && data.error ? ("error: " + data.error) : (data && data.compiled ? "compiled" : "lazy")
      console.warn("[rls_auto_restock] getComponent fallback: " + state)
    } catch (err2) {
      console.warn("[rls_auto_restock] getComponent fallback FAILED: " + ((err2 && (err2.message || err2)) || String(err2)))
    }
  }
}

export async function onUnload() {}
