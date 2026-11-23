import { loadModule } from "@/services/uiMods"
import { createApp } from "vue"

const PANEL = "/ui/ui-vue/mods/rls_auto_restock/ui/AutoRestockPanel.vue"
const CARD = "/ui/ui-vue/mods/rls_auto_restock/ui/EfficiencyUpgradeCard.vue"
const RLS_SESSION = "/ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/stores/businessComputer/businessSessionStore.js"

// The efficiency card is injected into RLS's own Upgrades page (Storage + Wholesale blocks) rather
// than rendered as a sidebar tab. RLS's dashboard is a single component for all four sections, so
// the card rides inside its DOM: a small separate Vue app mounted on a host div appended to the
// Upgrades page container. Shared state lives on window so hot-reload split module instances
// converge on one mounted app instead of fighting each other.
const EFF_STATE = "__rlsAutoRestockEfficiency"
const DASHBOARD_SELECTOR = ".rls-house.passive-app"
// Bump when the card or its mounting changes: a reloaded entry point then replaces an
// already-mounted card instead of leaving the stale one in the DOM.
const CARD_STAMP = 2

const MOD_VERSION = "1.4.0"
const fail = err => (err && (err.message || err)) || String(err)

let shimCount = 0
let rlsRuntimeComponent = null
let cardComponent = null
let sessionMod = null

function effState() {
  if (typeof window === "undefined") return null
  if (!window[EFF_STATE]) window[EFF_STATE] = { app: null, host: null, businessId: null }
  return window[EFF_STATE]
}

function teardownEfficiencyCard() {
  const state = effState()
  if (!state) return
  if (state.app) {
    try { state.app.unmount() } catch (err) { console.warn("[rls_auto_restock] card unmount failed: " + fail(err)) }
    state.app = null
  }
  if (state.host && state.host.parentNode) state.host.parentNode.removeChild(state.host)
  state.host = null
  state.businessId = null
}

function isUpgradesPage(page) {
  if (!page) return false
  const captions = page.querySelectorAll(".caption")
  for (const caption of captions) {
    if ((caption.textContent || "").trim() === "Storage") return true
  }
  return false
}

function ensureEfficiencyCard() {
  const state = effState()
  if (!state || !cardComponent || !sessionMod) return
  if (state.stamp !== CARD_STAMP) {
    teardownEfficiencyCard()
    state.stamp = CARD_STAMP
  }
  let store = null
  try {
    store = sessionMod.useBusinessSessionStore()
  } catch (err) {
    teardownEfficiencyCard()
    return
  }
  const businessId = store && store.businessId
  const wanted = !!(businessId
    && store.businessType === "passiveBusiness"
    && store.activeView === "upgrades")
  const root = wanted ? document.querySelector(DASHBOARD_SELECTOR) : null
  const page = root ? root.querySelector(":scope > .page") : null
  if (!wanted || !isUpgradesPage(page)) {
    teardownEfficiencyCard()
    return
  }
  let host = state.host
  if (host && (!host.isConnected || host.parentNode !== page)) teardownEfficiencyCard()
  if (state.app && !state.host) teardownEfficiencyCard()
  // the computer can switch businesses without leaving the Upgrades view: rebind the card
  if (state.app && state.businessId && state.businessId !== String(businessId)) teardownEfficiencyCard()
  if (!state.host) {
    host = document.createElement("div")
    host.className = "rls-ar-efficiency-host"
    page.appendChild(host)
    state.host = host
    state.businessId = String(businessId)
  }
  if (!state.app) {
    try {
      state.app = createApp(cardComponent, { businessId: state.businessId })
      state.app.mount(state.host)
      console.warn("[rls_auto_restock] efficiency card mounted (business " + state.businessId + ", v" + MOD_VERSION + ")")
    } catch (err) {
      console.warn("[rls_auto_restock] efficiency card mount FAILED: " + fail(err))
      teardownEfficiencyCard()
    }
  }
}

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
    const card = await loadModule(CARD)
    cardComponent = card && card.default
    console.warn("[rls_auto_restock] efficiency card module ready: " + typeof cardComponent)
  } catch (err) {
    console.warn("[rls_auto_restock] efficiency card module FAILED: " + fail(err))
  }

  try {
    sessionMod = await import(RLS_SESSION)
  } catch (err) {
    console.warn("[rls_auto_restock] session store import FAILED: " + fail(err))
  }
  if (cardComponent && sessionMod) {
    ensureEfficiencyCard()
    setInterval(ensureEfficiencyCard, 1000)
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

  if (sessionMod) {
    try {
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
}

export async function onUnload() {}
