<!-- Auto-Restock tab for RLS Career Overhaul passive-business computers.
      Per-store virtual driver controls: enable toggle, low-stock threshold presets,
      driver tier with fee estimate, live delivery status and a manual dispatch. -->
<template>
  <div class="rls-ar">
    <section v-if="loadFailed" class="panel warn-panel">
      <h3 class="panel-title">Auto-restock service unreachable</h3>
      <p class="hint">
        The Lua extension <b>rlsAutoRestock</b> did not respond. Check that the mod is enabled in
        the Mod Manager and restart the game. Console check:
        <code>dump(extensions.rlsAutoRestock)</code>
      </p>
    </section>

    <section v-else-if="!store" class="panel">
      <h3 class="panel-title">Connecting…</h3>
      <p class="hint">Talking to the auto-restock service.</p>
    </section>

    <template v-else-if="!store.compatible">
      <section class="panel warn-panel">
        <h3 class="panel-title">RLS Career Overhaul not detected</h3>
        <p class="hint">
          This tab is part of <b>RLS Auto-Restock</b>, a companion mod. It manages passive-business
          stores from RLS Career Overhaul. Load an RLS career save; if this persists, check that
          rls_career_overhaul v2.8+ is enabled.
        </p>
      </section>
    </template>

    <template v-else>
      <header class="page-head">
        <div class="page-copy">
          <h2 class="page-title">Virtual Driver</h2>
          <p class="hint">Autonomous restock deliveries for {{ store.businessName }}.</p>
        </div>
        <span :class="['status-badge', statusClass]">{{ statusLabel }}</span>
      </header>

      <p v-if="message" :class="['notice', messageError ? 'bad' : 'ok']">{{ message }}</p>

      <section class="panel">
        <header class="row-head">
          <span class="kicker">Stock</span>
          <span class="note">{{ store.operating ? 'One pallet per sale cycle' : 'Store closed' }}</span>
        </header>
        <div class="stock-line">
          <strong :class="['value', { warn: store.stock <= 0 }]">{{ store.stock || 0 }}<small>/ {{ store.capacity || 0 }} pallets</small></strong>
          <div class="meter grow"><span :class="barClass" :style="{ width: stockPercent + '%' }"></span></div>
        </div>
        <p class="note">
          <template v-if="store.sellsOutInSeconds != null">Sells out in {{ duration(store.sellsOutInSeconds) }} of active play.</template>
          <template v-else-if="!store.operating">Consumption is paused while the store is closed.</template>
          <template v-else>Out of stock. A dispatch will arrive in as little as {{ store.quotes && store.quotes[selectedTier] ? store.quotes[selectedTier].deliverySeconds : '—' }}s.</template>
        </p>
      </section>

      <section class="panel">
        <header class="row-head">
          <span class="kicker">Auto-restock</span>
          <span class="note">{{ store.settings.enabled ? 'On — drivers dispatch automatically' : 'Off — order and haul manually' }}</span>
        </header>
        <div class="toggle-row">
          <button
            type="button"
            :class="['ar-switch', { on: store.settings.enabled }]"
            :disabled="busy"
            @click="setEnabled(!store.settings.enabled)">
            <span class="ar-knob"></span>
            <span class="ar-switch-label">{{ store.settings.enabled ? 'Enabled' : 'Disabled' }}</span>
          </button>
        </div>
        <div class="preset-row" :class="{ disabled: !store.settings.enabled }">
          <span class="note label">Order when stock below</span>
          <div class="seg">
            <button
              v-for="preset in presets"
              :key="preset.value"
              type="button"
              class="seg-btn"
              :class="{ active: isPresetActive(preset.value) }"
              :disabled="busy"
              @click="setThreshold(preset.value)">
              {{ Math.round(preset.value * 100) }}%
            </button>
          </div>
          <span class="note">≤ {{ thresholdPallets }} pallets</span>
        </div>
      </section>

      <section class="panel">
        <header class="row-head">
          <span class="kicker">Driver tier</span>
          <span class="note">Refills to {{ Math.round((store.settings.targetFillPercent || 1) * 100) }}% of capacity</span>
        </header>
        <div class="tier-grid">
          <button
            v-for="tier in tiers"
            :key="tier.id"
            type="button"
            class="tier-card"
            :class="{ active: store.settings.driverTier === tier.id }"
            :disabled="busy"
            @click="setTier(tier.id)">
            <span class="tier-name">{{ tier.name }}</span>
            <span class="tier-meta">{{ tier.deliverySeconds }}s transit</span>
            <span v-if="quote(tier.id)" class="tier-fee">
              <BngIcon class="cur" :type="icons.beamCurrency" />{{ money(quote(tier.id).driverFee.total) }} fee / run
            </span>
          </button>
        </div>

        <div v-if="quote(selectedTier)" class="breakdown">
          <div class="line"><span>{{ quote(selectedTier).units }} pallets @ <BngIcon class="cur" :type="icons.beamCurrency" />{{ money(quote(selectedTier).unitCost) }} <small>{{ store.wholesaleOwned ? 'wholesale' : 'standard' }}</small></span><strong>{{ money(quote(selectedTier).supplyCost) }}</strong></div>
          <div class="line"><span>Base dispatch fee</span><strong>{{ money(quote(selectedTier).driverFee.base) }}</strong></div>
          <div class="line"><span>Cargo surcharge <small>{{ cargoPercent }}</small></span><strong>{{ money(quote(selectedTier).driverFee.cargo) }}</strong></div>
          <div class="line"><span>Distance surcharge <small>{{ quote(selectedTier).distance ? (quote(selectedTier).distance / 1000).toFixed(1) + ' km' : 'n/a' }}</small></span><strong>{{ money(quote(selectedTier).driverFee.distance) }}</strong></div>
          <div class="line total"><span>Dispatch total <small>ETA {{ quote(selectedTier).deliverySeconds }}s</small></span><strong class="money"><BngIcon class="cur" :type="icons.beamCurrency" />{{ money(quote(selectedTier).totalOrderCost) }}</strong></div>
          <p v-if="quote(selectedTier).affordable === false" class="note bad">This dispatch exceeds the current wallet balance.</p>
        </div>

        <div class="actions">
          <button
            type="button"
            class="ar-btn primary"
            :disabled="busy || !quote(selectedTier) || quote(selectedTier).units < 1 || hasDelivery"
            @click="dispatchNow">
            Dispatch driver now
          </button>
          <button
            v-if="hasDelivery"
            type="button"
            class="ar-btn quiet"
            :disabled="busy"
            @click="cancelDelivery">
            Cancel delivery
          </button>
        </div>
      </section>

      <section v-if="hasDelivery" class="panel transit">
        <header class="row-head">
          <span class="kicker">Delivery in transit</span>
          <span class="note">{{ store.delivery.tier === 'express' ? 'Express driver' : 'Standard driver' }}</span>
        </header>
        <strong class="value">{{ Math.ceil(store.delivery.remaining) }}<small>s remaining</small></strong>
        <div class="meter"><span class="transit" :style="{ width: transitPercent + '%' }"></span></div>
        <p class="note">+{{ store.delivery.units }} pallets for {{ money(store.delivery.totalCost) }} (driver fee {{ money(store.delivery.driverFee) }}). Arrives well before the current stock runs out.</p>
      </section>
    </template>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { lua } from '@/bridge'
import { useEvents } from '@/services/events'
import { BngIcon, icons } from '@/common/components/base'

console.warn("[rls_auto_restock] panel setup running (v1.0.9)")

const props = defineProps({ data: Object })

const store = ref(null)
const busy = ref(false)
const message = ref('')
const messageError = ref(false)
const loadFailed = ref(false)
const unmounted = ref(false)
let poll = null

const events = useEvents()

const presets = [
  { value: 0.25 },
  { value: 0.5 },
  { value: 0.75 },
]
const tiers = [
  { id: 'standard', name: 'Standard', deliverySeconds: 45 },
  { id: 'express', name: 'Express', deliverySeconds: 20 },
]

const selectedTier = computed(() => (store.value?.settings?.driverTier) || 'standard')
const quote = tier => (store.value?.quotes && store.value.quotes[tier]) || null
const hasDelivery = computed(() => !!store.value?.delivery)
const cargoPercent = computed(() => (selectedTier.value === 'express' ? '22% of supply cost' : '12% of supply cost'))
const stockPercent = computed(() => {
  const capacity = Number(store.value?.capacity) || 0
  const stock = Number(store.value?.stock) || 0
  return capacity > 0 ? Math.min(100, Math.max(0, (stock / capacity) * 100)) : 0
})
const barClass = computed(() => {
  if (!store.value?.settings?.enabled) return ''
  const threshold = (Number(store.value?.capacity) || 0) * (Number(store.value?.settings?.thresholdPercent) || 0.3)
  return (Number(store.value?.stock) || 0) <= threshold ? 'low' : 'ok'
})
const transitPercent = computed(() => {
  const delivery = store.value?.delivery
  if (!delivery || !(delivery.duration > 0)) return 100
  return Math.min(100, Math.max(0, (1 - delivery.remaining / delivery.duration) * 100))
})
const thresholdPallets = computed(() => {
  const capacity = Number(store.value?.capacity) || 0
  const threshold = Number(store.value?.settings?.thresholdPercent) || 0.3
  return capacity > 0 ? Math.floor(capacity * threshold) : 0
})

const STATUS = {
  off: { label: 'Off', cls: 'idle' },
  idle: { label: 'Idle — stock healthy', cls: 'idle' },
  waiting: { label: 'Low stock — dispatching', cls: 'warn' },
  enroute: { label: 'Driver en route', cls: 'active' },
  blocked: { label: 'Insufficient funds', cls: 'bad' },
  otherMap: { label: "Travel to this store's map", cls: 'warn' },
  pending: { label: 'Waiting for career data', cls: 'idle' },
  notOwned: { label: 'Not owned', cls: 'idle' },
  unsupported: { label: 'No supply chain', cls: 'idle' },
}
const statusInfo = computed(() => STATUS[store.value?.status] || STATUS.pending)
const statusLabel = computed(() => {
  if (hasDelivery.value) return `Driver En Route (${Math.ceil(store.value.delivery.remaining)}s)`
  return statusInfo.value.label
})
const statusClass = computed(() => (hasDelivery.value ? 'active' : statusInfo.value.cls))

const money = value => (Math.max(0, Math.round(Number(value) || 0))).toLocaleString()
function duration(value) {
  const total = Math.max(0, Math.ceil(Number(value) || 0))
  if (total >= 3600) return `${Math.floor(total / 3600)}h ${Math.floor((total % 3600) / 60)}m`
  if (total >= 60) return `${Math.floor(total / 60)}m ${String(total % 60).padStart(2, '0')}s`
  return `${total}s`
}
const isPresetActive = value => Math.abs((Number(store.value?.settings?.thresholdPercent) || 0.3) - value) < 0.001

async function call(method, ...args) {
  if (busy.value) return null
  busy.value = true
  message.value = ''
  try {
    return await lua.rlsAutoRestock[method](...args)
  } catch (error) {
    messageError.value = true
    message.value = 'The auto-restock service did not respond. Is the mod enabled?'
    return null
  } finally {
    busy.value = false
  }
}

async function refresh() {
  if (unmounted.value) return
  const businessId = props.data?.businessId
  if (businessId === undefined || businessId === null) return
  try {
    const result = await lua.rlsAutoRestock.getStoreData(businessId)
    if (unmounted.value || businessId !== props.data?.businessId) return
    if (result && typeof result === 'object') {
      store.value = result
      loadFailed.value = false
    }
  } catch (error) {
    loadFailed.value = true
  }
}

async function setEnabled(value) {
  const result = await call('setStoreAutoRestock', props.data?.businessId, value)
  if (result) {
    store.value = result
    message.value = value ? 'Auto-restock enabled. Virtual drivers will keep this store stocked.' : 'Auto-restock disabled.'
    messageError.value = false
  }
}

async function setThreshold(value) {
  const result = await call('setStoreThreshold', props.data?.businessId, value)
  if (result) store.value = result
}

async function setTier(tier) {
  const result = await call('setStoreDriverTier', props.data?.businessId, tier)
  if (result) store.value = result
}

async function dispatchNow() {
  const result = await call('dispatchNow', props.data?.businessId)
  if (result) {
    messageError.value = result.success === false
    message.value = result.message || ''
    if (result.store) store.value = result.store
  }
}

async function cancelDelivery() {
  const result = await call('cancelDelivery', props.data?.businessId)
  if (result) {
    message.value = result.message || ''
    messageError.value = result.success === false
  }
}

function onStorePush(payload) {
  if (payload && payload.businessId === props.data?.businessId) store.value = payload
}

onMounted(async () => {
  events.on('RlsAutoRestockStore', onStorePush)
  await refresh()
  poll = window.setInterval(refresh, 1000)
})

onUnmounted(() => {
  unmounted.value = true
  window.clearInterval(poll)
  if (events.off) events.off('RlsAutoRestockStore', onStorePush)
})
</script>

<style scoped>
.rls-ar {
  display: flex;
  flex-direction: column;
  gap: var(--rls-ar-space-3, 0.9rem);
  min-width: 0;
  min-height: 100%;
  color: #fff;
  font-variant-numeric: tabular-nums;
  --rls-ar-accent: #ff6600;
  --rls-ar-panel: rgba(24, 24, 28, 0.92);
  --rls-ar-line: rgba(255, 255, 255, 0.12);
  --rls-ar-muted: #a0a0aa;
  --rls-ar-ok: #4fbf6b;
  --rls-ar-warn: #f2a33c;
  --rls-ar-bad: #e05555;
  --rls-ar-money: #f5c451;
}
.rls-ar .panel {
  display: flex;
  flex-direction: column;
  gap: 0.55em;
  padding: 0.9em 1em;
  border-radius: 0.9em;
  background: var(--rls-ar-panel);
  border: 1px solid var(--rls-ar-line);
}
.rls-ar .warn-panel { border-color: var(--rls-ar-warn); }
.rls-ar .page-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1em;
  flex-wrap: wrap;
}
.rls-ar .page-title { margin: 0; font-size: 1.35em; font-weight: 800; line-height: 1.15; }
.rls-ar .page-copy { display: grid; gap: 0.25em; }
.rls-ar .panel-title { margin: 0 0 0.2em; font-size: 1.05em; font-weight: 800; }
.rls-ar .hint { margin: 0; font-size: 0.85em; color: var(--rls-ar-muted); line-height: 1.45; }
.rls-ar .note { color: var(--rls-ar-muted); font-size: 0.8em; font-weight: 600; line-height: 1.35; }
.rls-ar .note.bad { color: var(--rls-ar-bad); }
.rls-ar .kicker {
  display: block;
  font-size: 0.72em;
  font-weight: 800;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--rls-ar-muted);
}
.rls-ar .row-head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 0.8em;
}
.rls-ar .value { font-size: 1.35em; font-weight: 800; line-height: 1.2; white-space: nowrap; }
.rls-ar .value.warn { color: var(--rls-ar-warn); }
.rls-ar .value small { margin-left: 0.3em; color: var(--rls-ar-muted); font-size: 0.6em; font-weight: 700; }
.rls-ar .money, .rls-ar .cur { color: var(--rls-ar-money); }
.rls-ar .cur { --bng-icon-size: 1em; margin-right: 0.15em; transform: translateY(0.08em); }
.rls-ar .grow { flex: 1 1 auto; }

.rls-ar .status-badge {
  padding: 0.35em 0.75em;
  border-radius: 1em;
  font-size: 0.78em;
  font-weight: 800;
  white-space: nowrap;
  border: 1px solid var(--rls-ar-line);
  color: var(--rls-ar-muted);
  background: rgba(255, 255, 255, 0.05);
}
.rls-ar .status-badge.active { color: #7fd0ff; border-color: rgba(127, 208, 255, 0.45); background: rgba(127, 208, 255, 0.1); }
.rls-ar .status-badge.warn { color: var(--rls-ar-warn); border-color: rgba(242, 163, 60, 0.45); background: rgba(242, 163, 60, 0.1); }
.rls-ar .status-badge.bad { color: var(--rls-ar-bad); border-color: rgba(224, 85, 85, 0.45); background: rgba(224, 85, 85, 0.12); }

.rls-ar .notice {
  margin: 0;
  padding: 0.55em 0.8em;
  border-radius: 0.6em;
  font-size: 0.85em;
  font-weight: 600;
}
.rls-ar .notice.ok { background: rgba(79, 191, 107, 0.12); color: var(--rls-ar-ok); }
.rls-ar .notice.bad { background: rgba(224, 85, 85, 0.14); color: var(--rls-ar-bad); }

.rls-ar .stock-line { display: flex; align-items: center; gap: 0.9em; }
.rls-ar .meter {
  height: 0.45em;
  border-radius: 1em;
  background: rgba(255, 255, 255, 0.1);
  overflow: hidden;
}
.rls-ar .meter > span { display: block; height: 100%; border-radius: 1em; }
.rls-ar .meter > span.ok { background: var(--rls-ar-ok); }
.rls-ar .meter > span.low { background: var(--rls-ar-warn); }
.rls-ar .meter > span.transit { background: #7fd0ff; transition: width 1s linear; }

.rls-ar .toggle-row { display: flex; align-items: center; gap: 0.8em; }
.rls-ar .ar-switch {
  display: inline-flex;
  align-items: center;
  gap: 0.65em;
  padding: 0.3em 0.75em 0.3em 0.3em;
  border-radius: 2em;
  border: 1px solid var(--rls-ar-line);
  background: rgba(255, 255, 255, 0.06);
  color: #fff;
  cursor: pointer;
  font: inherit;
  font-weight: 700;
}
.rls-ar .ar-switch:disabled { opacity: 0.55; cursor: default; }
.rls-ar .ar-knob {
  width: 1.5em;
  height: 1.5em;
  border-radius: 50%;
  background: #6d6d76;
  transition: background 0.15s ease, transform 0.15s ease;
}
.rls-ar .ar-switch.on { border-color: rgba(79, 191, 107, 0.5); background: rgba(79, 191, 107, 0.14); }
.rls-ar .ar-switch.on .ar-knob { background: var(--rls-ar-ok); transform: translateX(0.35em); }

.rls-ar .preset-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.9em;
  flex-wrap: wrap;
  padding-top: 0.4em;
  border-top: 1px solid var(--rls-ar-line);
}
.rls-ar .preset-row.disabled { opacity: 0.5; }
.rls-ar .preset-row .label { flex: 1 1 auto; }
.rls-ar .seg { display: inline-flex; border: 1px solid var(--rls-ar-line); border-radius: 0.6em; overflow: hidden; }
.rls-ar .seg-btn {
  padding: 0.4em 0.9em;
  border: 0;
  background: transparent;
  color: #fff;
  font: inherit;
  font-weight: 700;
  cursor: pointer;
}
.rls-ar .seg-btn + .seg-btn { border-left: 1px solid var(--rls-ar-line); }
.rls-ar .seg-btn.active { background: var(--rls-ar-accent); color: #fff; }
.rls-ar .seg-btn:disabled { opacity: 0.55; cursor: default; }

.rls-ar .tier-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0.6em;
}
.rls-ar .tier-card {
  display: grid;
  gap: 0.2em;
  justify-items: start;
  padding: 0.7em 0.85em;
  border-radius: 0.8em;
  border: 1px solid var(--rls-ar-line);
  background: rgba(255, 255, 255, 0.04);
  color: #fff;
  text-align: left;
  font: inherit;
  cursor: pointer;
}
.rls-ar .tier-card.active { border-color: var(--rls-ar-accent); background: rgba(255, 102, 0, 0.12); box-shadow: 0 0 0 1px var(--rls-ar-accent) inset; }
.rls-ar .tier-card:disabled { opacity: 0.55; cursor: default; }
.rls-ar .tier-name { font-weight: 800; }
.rls-ar .tier-meta { font-size: 0.75em; color: var(--rls-ar-muted); font-weight: 700; }
.rls-ar .tier-fee { font-size: 0.8em; font-weight: 700; color: var(--rls-ar-money); }

.rls-ar .breakdown {
  display: grid;
  gap: 0.3em;
  padding-top: 0.5em;
  border-top: 1px solid var(--rls-ar-line);
}
.rls-ar .line {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 1em;
  font-size: 0.85em;
  font-weight: 600;
}
.rls-ar .line small { margin-left: 0.35em; color: var(--rls-ar-muted); font-size: 0.85em; font-weight: 700; }
.rls-ar .line strong { font-weight: 800; white-space: nowrap; }
.rls-ar .line.total { padding-top: 0.3em; border-top: 1px solid var(--rls-ar-line); font-weight: 800; }

.rls-ar .actions { display: flex; gap: 0.6em; flex-wrap: wrap; }
.rls-ar .ar-btn {
  padding: 0.55em 1.1em;
  border-radius: 0.6em;
  border: 1px solid var(--rls-ar-line);
  font: inherit;
  font-weight: 800;
  cursor: pointer;
  color: #fff;
  background: rgba(255, 255, 255, 0.07);
}
.rls-ar .ar-btn.primary { background: var(--rls-ar-accent); border-color: transparent; }
.rls-ar .ar-btn.primary:hover:not(:disabled) { filter: brightness(1.08); }
.rls-ar .ar-btn.quiet { background: transparent; }
.rls-ar .ar-btn:disabled { opacity: 0.5; cursor: default; }

.rls-ar .transit { border-color: rgba(127, 208, 255, 0.35); }
</style>
