<!-- Business-efficiency upgrade card for RLS passive-business computers.
      Injected into the Upgrades page by rls_auto_restock's index.js (this is not a sidebar tab).
      Shows the store's current payout speed and sells the next tier: each level halves the
      earnings cycle (2x selling speed, then 4x), costing 2x / 4x the current pallet price. -->
<template>
  <section class="panel block eff-card" data-fk="efficiency">
    <header class="block-head">
      <div class="head-copy">
        <span class="caption">Operations</span>
        <h3 class="block-title">Business efficiency</h3>
      </div>
      <span class="pill" :class="{ ok: level >= maxLevel }">
        <BngIcon class="pill-icon" :type="level >= maxLevel ? icons.checkmark : icons.timer" />Level {{ level }} / {{ maxLevel }}
      </span>
    </header>

    <template v-if="eff">
      <div class="levels" aria-hidden="true">
        <span v-for="n in maxLevel" :key="n" :class="{ on: n <= level }"></span>
      </div>

      <template v-if="level < maxLevel">
        <div class="facts">
          <div class="fact">
            <span class="fact-key">Payout cycle</span>
            <span class="fact-value">{{ duration(eff.cycleSeconds) }} → {{ duration(nextCycleSeconds) }}</span>
          </div>
          <div class="fact">
            <span class="fact-key">Selling speed</span>
            <span class="fact-value">{{ eff.speedMultiplier }}× → {{ eff.nextMultiplier }}×</span>
          </div>
          <div class="fact ok">
            <span class="fact-key">Extra earnings</span>
            <span class="fact-value">+<BngIcon class="cur" :type="icons.beamCurrency" />{{ money(eff.nextProfitPerHour - eff.profitPerHour) }} <small>/ hr</small></span>
          </div>
        </div>
        <div class="upgrade-foot">
          <span class="note">
            Costs {{ eff.nextMultiplier }}× the current pallet price
            (<BngIcon class="cur" :type="icons.beamCurrency" />{{ money(eff.palletCost) }} × {{ eff.nextMultiplier }}).
            Payouts arrive {{ eff.nextMultiplier }}× as often.
          </span>
          <HouseButton
            :disabled="busy || eff.affordable === false"
            data-fk="efficiency-upgrade"
            @click="purchase">
            Upgrade for <BngIcon class="cur" :type="icons.beamCurrency" />{{ money(eff.nextCost) }}
          </HouseButton>
        </div>
        <p v-if="eff.affordable === false" class="hint">This upgrade exceeds the current wallet balance.</p>
      </template>
      <p v-else class="hint">
        Maximum efficiency: this store sells stock and pays out {{ eff.speedMultiplier }}× faster than a standard store.
      </p>
    </template>

    <p v-else-if="loadFailed" class="hint">The auto-restock service did not respond. Is the mod enabled?</p>
    <p v-else class="hint">Loading efficiency data…</p>

    <p v-if="message" :class="['notice', messageError ? 'bad' : 'ok']">{{ message }}</p>
  </section>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { BngIcon, icons } from '@/common/components/base'
import { HouseButton } from '/ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/components/house/index.js'

console.warn("[rls_auto_restock] efficiency card setup running (v1.4.1)")

const props = defineProps({ businessId: [String, Number] })

const store = ref(null)
const busy = ref(false)
const message = ref('')
const messageError = ref(false)
const loadFailed = ref(false)
const unmounted = ref(false)
let poll = null

function getApi() {
  return (typeof window !== 'undefined' && (window.bngApi || window.beamng)) || null
}

function callLua(path, ...args) {
  return new Promise((resolve, reject) => {
    try {
      const api = getApi()
      if (!api || typeof api.engineLua !== 'function') {
        reject(new Error('Lua bridge unavailable'))
        return
      }
      const serialized = args
        .map(arg => (typeof api.serializeToLua === 'function' ? api.serializeToLua(arg) : 'nil'))
        .join(', ')
      const parts = String(path).split('.')
      const root = parts[0]
      const method = parts.slice(1).join('.')
      const expr =
        '(function() ' +
        `local m = rawget(_G, ${JSON.stringify(root)}) ` +
        'if type(m) ~= "table" then return nil end ' +
        `local f = m[${JSON.stringify(method)}] ` +
        'if type(f) ~= "function" then return nil end ' +
        `return f(${serialized}) ` +
        'end)()'
      api.engineLua(expr, resolve)
    } catch (err) {
      reject(err)
    }
  })
}

const eff = computed(() => (store.value && store.value.efficiency) || null)
const level = computed(() => (eff.value && eff.value.level) || 0)
const maxLevel = computed(() => (eff.value && eff.value.maxLevel) || 2)
const nextCycleSeconds = computed(() => (eff.value && eff.value.nextCycleSeconds) || 0)

const money = value => (Math.max(0, Math.round(Number(value) || 0))).toLocaleString()
function duration(value) {
  const total = Math.max(0, Math.ceil(Number(value) || 0))
  if (total >= 3600) return `${Math.floor(total / 3600)}h ${Math.floor((total % 3600) / 60)}m`
  if (total >= 60) return `${Math.floor(total / 60)}m ${String(total % 60).padStart(2, '0')}s`
  return `${total}s`
}

async function refresh() {
  if (unmounted.value || props.businessId === undefined || props.businessId === null) return
  try {
    const result = await callLua('rlsAutoRestock.getStoreData', props.businessId)
    if (unmounted.value) return
    if (result && typeof result === 'object') {
      store.value = result
      loadFailed.value = false
    }
  } catch (error) {
    loadFailed.value = true
  }
}

async function purchase() {
  if (busy.value) return
  busy.value = true
  try {
    const result = await callLua('rlsAutoRestock.purchaseEfficiencyUpgrade', props.businessId)
    if (unmounted.value) return
    if (result && typeof result === 'object') {
      messageError.value = result.success === false
      message.value = result.message || (result.success ? 'Business efficiency upgraded.' : '')
      if (result.store) store.value = result.store
    }
  } catch (error) {
    messageError.value = true
    message.value = 'The upgrade could not be processed. Is the mod enabled?'
  } finally {
    busy.value = false
  }
}

onMounted(() => {
  refresh()
  poll = window.setInterval(refresh, 1000)
})

onUnmounted(() => {
  unmounted.value = true
  window.clearInterval(poll)
})
</script>

<style scoped lang="scss">
@use "@/styles/rls_career_overhaul/modules/career/styles/rlsHouse.scss" as *;

/* The card is mounted inside RLS's .rls-house.passive-app, so the house variables and fonts
   inherit from the host. Only the pieces the house sheets do not provide are defined here,
   matching the dashboard's own local rules so the card reads as a native upgrade block. */
.eff-card.block {
  gap: var(--space-3);
  padding: 0.9em 1em;
}
.block-head {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-2) var(--space-4);
}
.head-copy {
  display: grid;
  gap: 0.25em;
  flex: 1 1 14em;
  min-width: 0;
}
.head-copy .block-title { font-size: 1.15em; overflow-wrap: anywhere; }
.block-head > .pill { flex: 0 0 auto; }

.pill-icon,
.key-icon {
  --bng-icon-size: 1.15em;
  flex: 0 0 auto;
  transform: translateY(-0.1em);
}

.facts {
  display: grid;
  gap: var(--space-2);
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 9.5em), 1fr));
}
.fact-value small { color: var(--faint); font-size: 0.75em; font-weight: 700; }

.cur {
  --bng-icon-size: 1.1em;
  margin-right: 0.08em;
  transform: translateY(0.06em);
}

/* one segment per efficiency level, same rhythm as the storage pips */
.levels {
  display: grid;
  grid-auto-flow: column;
  grid-auto-columns: minmax(0, 1fr);
  gap: 0.3em;
}
.levels span {
  height: 0.45em;
  border-radius: 1em;
  background: rgba(255, 255, 255, 0.12);
}
.levels span.on { background: var(--ok); }

.upgrade-foot {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2) var(--space-4);
  padding-top: var(--space-2);
  border-top: 1px solid var(--line);
}
</style>
