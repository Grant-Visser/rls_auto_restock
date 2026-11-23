-- RLS Auto-Restock: autonomous virtual delivery drivers for RLS Career Overhaul passive businesses.
-- Standalone companion mod for RLS Career Overhaul v2.8.x (BeamNG.drive 0.40).
-- Reads RLS store state through the passive business module, charges a transparent
-- driver fee on top of the wholesale supply cost, and runs simulated delivery
-- timers that are always faster than a store's consumption rate.
-- Also sells business-efficiency upgrades (from RLS's Upgrades tab): each level
-- multiplies the store's selling speed, halving the earnings cycle per level.

local M = {}

-- Configuration -----------------------------------------------------------------------------------

local MOD_VERSION = "1.4.1"
local CONFIG_VERSION = 3
local UPDATE_STEP_SECONDS = 1.0
local MIN_DELIVERY_SECONDS = 5
local DELIVERY_TIME_CAP = 0.5
local DISTANCE_FEE_PER_METRE = 0.03
local COLLECT_COOLDOWN_SECONDS = 30
local SUPPLY_FEE_LABEL = "Auto-restock driver order"
local ARCHETYPE_FILE = "gameplay/overhaul/business/passiveBusinessArchetypes.json"
local SAVE_FILE = "rlsAutoRestock.json"
local UI_EVENT = "RlsAutoRestockStore"
local HISTORY_LIMIT = 60

local DEFAULT_SETTINGS = {
  enabled = false,
  thresholdPercent = 0.30,
  targetFillPercent = 1.0,
  driverTier = "standard",
  autoCollect = true,
  efficiencyLevel = 0,
}

local TIERS = {
  standard = { baseDispatchFee = 150, cargoSurcharge = 0.12, deliverySeconds = 45 },
  express = { baseDispatchFee = 300, cargoSurcharge = 0.22, deliverySeconds = 20 },
}

-- Business-efficiency upgrade tiers: index = level, value = selling-speed multiplier.
-- Level 1 doubles the payout rate (half the earnings cycle), level 2 quadruples it.
-- Purchase cost is the multiplier times the current (wholesale-aware) pallet price.
local EFFICIENCY_LEVELS = { 2, 4 }
local MAX_EFFICIENCY_LEVEL = #EFFICIENCY_LEVELS

-- State -------------------------------------------------------------------------------------------

local settings = {}
local deliveries = {}
local blocked = {}
local archetypeFallback = nil
local anchor = nil
local anchorFailed = false
local lastCollect = {}
local lastSavePath = nil
local dataLoaded = false
-- True once loadFromSave has populated the tables in THIS module instance. Survives career
-- deactivation (the exit save must persist live memory), but resets on a Lua hot-reload so the
-- self-heal reload runs from disk before anything writes.
local memoryPopulated = false
local updateAccumulator = 0

-- Small helpers -----------------------------------------------------------------------------------

local function getExt(name)
  return rawget(_G, name)
end

local function moneyRounded(value)
  return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

local function notify(kind, title, message)
  guihooks.trigger("toastrMsg", {type = kind, title = title, msg = message})
end

local function economyIndex()
  local economy = getExt("overhaul_career_economy_globalEconomy")
  if economy and type(economy.getGlobalIndex) == "function" then
    local ok, index = pcall(economy.getGlobalIndex)
    if ok and tonumber(index) then return tonumber(index) end
  end
  return 1
end

local function indexed(baseValue)
  return math.floor((tonumber(baseValue) or 0) * economyIndex() + 0.0001)
end

local function getMoney()
  local attributes = getExt("overhaul_career_economy_playerAttributes")
  if attributes and type(attributes.getAttributeValue) == "function" then
    local ok, value = pcall(attributes.getAttributeValue, "money")
    if ok then return math.floor(tonumber(value) or 0) end
  end
  return nil
end

-- Settings ----------------------------------------------------------------------------------------

local function tierConfig(tier)
  return TIERS[tier] or TIERS.standard
end

local function validTier(tier)
  return TIERS[tier] and tier or DEFAULT_SETTINGS.driverTier
end

local function sanitizeSettings(raw)
  raw = type(raw) == "table" and raw or {}
  local threshold = tonumber(raw.thresholdPercent)
  local fill = tonumber(raw.targetFillPercent)
  local efficiency = math.floor(tonumber(raw.efficiencyLevel) or 0)
  return {
    enabled = raw.enabled == true,
    thresholdPercent = math.min(0.95, math.max(0.05, threshold or DEFAULT_SETTINGS.thresholdPercent)),
    targetFillPercent = math.min(1.0, math.max(0.1, fill or DEFAULT_SETTINGS.targetFillPercent)),
    driverTier = validTier(raw.driverTier),
    autoCollect = raw.autoCollect == true,
    efficiencyLevel = math.max(0, math.min(MAX_EFFICIENCY_LEVEL, efficiency)),
  }
end

local settingsFor
local currentSavePath
local ensureLoaded

function settingsFor(businessId)
  ensureLoaded()
  local id = tostring(businessId)
  if not settings[id] then
    settings[id] = sanitizeSettings(DEFAULT_SETTINGS)
  end
  return settings[id]
end

-- RLS access --------------------------------------------------------------------------------------

-- RLS keeps store state in a module-local table. We hold a live anchor (the function that closes
-- over it plus the upvalue index) because loadData() replaces the table on every career load.
local function invalidateAnchor()
  anchor, anchorFailed = nil, false
end

local function walkUpvalues(fn, visit, seen, depth)
  if depth <= 0 or type(fn) ~= "function" or seen[fn] then return end
  seen[fn] = true
  local index = 1
  while true do
    local okRead, name, value = pcall(debug.getupvalue, fn, index)
    if not okRead or name == nil then break end
    visit(fn, index, name, value)
    if type(value) == "function" then walkUpvalues(value, visit, seen, depth - 1) end
    index = index + 1
  end
end

local function resolveAnchor()
  if anchor then return anchor end
  if anchorFailed then return nil end
  local passive = getExt("overhaul_career_business_passive")
  if not passive or type(passive.getUIData) ~= "function" then return nil end
  local found = nil
  walkUpvalues(passive.getUIData, function(fn, index, name, value)
    if not found and name == "properties" and type(value) == "table" then
      found = {fn = fn, index = index}
    end
  end, {}, 8)
  if not found then
    anchorFailed = true
    log("W", "rlsAutoRestock", "RLS passive business state is unreachable; auto-restock stays idle. Check that rls_career_overhaul v2.8.x is enabled.")
    return nil
  end
  anchor = found
  return anchor
end

local function passiveProperties()
  local found = resolveAnchor()
  if not found then return nil end
  local ok, _, value = pcall(debug.getupvalue, found.fn, found.index)
  if ok and type(value) == "table" then return value end
  invalidateAnchor()
  return nil
end

local function loadArchetypeConfig()
  local read = jsonReadFile(ARCHETYPE_FILE)
  if type(read) == "table" then
    archetypeFallback = read
  end
end

local function archetypeFor(state)
  if archetypeFallback and archetypeFallback[state.archetypeId] then
    return archetypeFallback[state.archetypeId]
  end
  return nil
end

local function owned(businessId)
  local manager = getExt("overhaul_career_business_manager")
  if not manager or type(manager.isPurchasedBusiness) ~= "function" then return false end
  local ok, result = pcall(manager.isPurchasedBusiness, "passiveBusiness", tostring(businessId))
  return ok and result == true
end

local function facilityName(businessId, archetype)
  local facilities = getExt("overhaul_world_facilities")
  if facilities and type(facilities.getFacilityIfExists) == "function" then
    local ok, facility = pcall(facilities.getFacilityIfExists, "passiveBusiness", tostring(businessId))
    if ok and type(facility) == "table" and facility.name then return facility.name end
  end
  return (archetype and archetype.name) or "Business"
end

local function supplyNameFor(archetype)
  return (archetype and archetype.supplyName) or "Business Supplies"
end

local function capacityFor(state, archetype)
  local capacities = archetype and archetype.storageCapacities
  if type(capacities) ~= "table" then return nil end
  return tonumber(capacities[state.storageLevel] or capacities[#capacities])
end

local function chainHasWholesale(state)
  local properties = passiveProperties()
  if not properties then return false end
  local levelId = getCurrentLevelIdentifier()
  for _, other in pairs(properties) do
    if type(other) == "table" and other.archetypeId == state.archetypeId
      and other.mapId == levelId and other.wholesaleOwned == true then
      return true
    end
  end
  return false
end

local function unitPrice(state)
  local archetype = archetypeFor(state)
  if not archetype then return 0 end
  local base = chainHasWholesale(state) and archetype.wholesaleUnitCost or archetype.unitCost
  return indexed(base)
end

local function timeUntilEmpty(state, archetype)
  local cycleSeconds = tonumber(archetype and archetype.cycleSeconds) or 0
  if cycleSeconds <= 0 or state.operating == false or (tonumber(state.stock) or 0) <= 0 then return nil end
  return (state.stock - 1) * cycleSeconds + math.max(0, cycleSeconds - (tonumber(state.cycleProgress) or 0))
end

-- Business efficiency ------------------------------------------------------------------------------

local function efficiencyLevelFor(value)
  local level = math.floor(tonumber(value) or 0)
  return math.max(0, math.min(MAX_EFFICIENCY_LEVEL, level))
end

local function efficiencySpeed(level)
  local lvl = efficiencyLevelFor(level)
  return lvl > 0 and EFFICIENCY_LEVELS[lvl] or 1
end

-- Each level costs a multiple of the current (wholesale-aware, indexed) pallet price.
local function efficiencyCost(state, archetype, level)
  local multiplier = EFFICIENCY_LEVELS[efficiencyLevelFor(level)]
  if not multiplier then return nil end
  local palletPrice = unitPrice(state)
  if palletPrice <= 0 then return nil end
  return moneyRounded(palletPrice * multiplier)
end

local function coordinatesFor(state, role)
  local generator = getExt("overhaul_career_logistics_generator")
  if not generator or type(generator.getLocationCoordinates) ~= "function" then return nil end
  local facId = state[role .. "FacilityId"]
  local spotName = state[role .. "ParkingSpotName"]
  if not facId or not spotName then return nil end
  local ok, position = pcall(generator.getLocationCoordinates, {type = "facilityParkingspot", facId = facId, psPath = spotName})
  if ok then return position end
  return nil
end

local distanceCache = {}

local function storeDistance(state)
  local id = tostring(state.id)
  local cached = distanceCache[id]
  local now = os.time()
  if cached and now - cached.at < 30 then return cached.distance end
  local distance = nil
  local from = coordinatesFor(state, "supplier")
  local to = coordinatesFor(state, "receiving")
  if from and to then
    local ok, length = pcall(function() return (to - from):length() end)
    if ok and tonumber(length) then distance = tonumber(length) end
  end
  if not distance then
    local generator = getExt("overhaul_career_logistics_generator")
    if generator and type(generator.getFacilityById) == "function" and type(generator.getDistanceBetweenFacilities) == "function" then
      local okFrom, supplierFacility = pcall(generator.getFacilityById, state.supplierFacilityId)
      local okTo, storeFacility = pcall(generator.getFacilityById, state.receivingFacilityId)
      if okFrom and okTo and supplierFacility and storeFacility then
        local ok, route = pcall(generator.getDistanceBetweenFacilities, supplierFacility, storeFacility)
        if ok and tonumber(route) then distance = tonumber(route) end
      end
    end
  end
  distanceCache[id] = {at = now, distance = distance}
  return distance
end

-- Fees and quotes ---------------------------------------------------------------------------------

local function computeDriverFee(tier, supplyCost, distance)
  local config = tierConfig(tier)
  local cargo = moneyRounded((tonumber(supplyCost) or 0) * config.cargoSurcharge)
  local distanceFee = 0
  if distance and DISTANCE_FEE_PER_METRE > 0 then
    distanceFee = moneyRounded(distance * DISTANCE_FEE_PER_METRE)
  end
  return {
    base = config.baseDispatchFee,
    cargo = cargo,
    distance = distanceFee,
    total = config.baseDispatchFee + cargo + distanceFee,
  }
end

local function unitsNeeded(state, archetype, fillPercent)
  local capacity = capacityFor(state, archetype) or 0
  local stock = math.max(0, math.floor(tonumber(state.stock) or 0))
  local wanted = math.floor(capacity * (tonumber(fillPercent) or 1.0) + 0.5)
  return math.max(0, math.min(wanted - stock, math.max(0, capacity - stock))), capacity
end

local function deliverySecondsFor(state, archetype, tier)
  local base = tierConfig(tier).deliverySeconds
  local untilEmpty = timeUntilEmpty(state, archetype)
  if untilEmpty then
    return math.max(MIN_DELIVERY_SECONDS, math.min(base, untilEmpty * DELIVERY_TIME_CAP)), untilEmpty
  end
  return base, nil
end

local function quoteFor(state, tier)
  local archetype = archetypeFor(state)
  if not archetype or archetype.supplyType == false then return nil end
  local config = settingsFor(state.id)
  local units, capacity = unitsNeeded(state, archetype, config.targetFillPercent)
  local supplyCost = units * unitPrice(state)
  local distance = storeDistance(state)
  local fee = computeDriverFee(tier, supplyCost, distance)
  local total = supplyCost + fee.total
  local seconds, untilEmpty = deliverySecondsFor(state, archetype, tier)
  local money = getMoney()
  return {
    tier = tier,
    units = units,
    capacity = capacity,
    stock = math.max(0, math.floor(tonumber(state.stock) or 0)),
    unitCost = unitPrice(state),
    supplyCost = supplyCost,
    driverFee = fee,
    totalOrderCost = total,
    distance = distance,
    deliverySeconds = seconds,
    timeUntilEmpty = untilEmpty,
    affordable = money ~= nil and money >= total or nil,
  }
end

-- Finance records ---------------------------------------------------------------------------------

local function recordStoreFinance(state, amount, quantity, kind)
  amount = moneyRounded(amount)
  kind = kind or "order"
  state.financeHistory = type(state.financeHistory) == "table" and state.financeHistory or {}
  local row = {t = os.time(), kind = kind, amount = amount, qty = quantity}
  if kind == "order" then row.autoRestock = true end
  table.insert(state.financeHistory, row)
  while #state.financeHistory > HISTORY_LIMIT do table.remove(state.financeHistory, 1) end
  local totals = type(state.financeTotals) == "table" and state.financeTotals or {}
  -- Efficiency upgrades belong in RLS's "Upgrades" lifetime total, like its own storage/wholesale buys.
  local key = kind == "collect" and "collected" or "supplies"
  if kind == "collect" then
    key = "collected"
  elseif kind == "efficiency" then
    key = "upgrades"
  end
  totals[key] = math.max(0, math.floor((tonumber(totals[key]) or 0) + amount))
  state.financeTotals = totals
end

local function payOrder(state, amount, label, category)
  local payment = getExt("overhaul_career_economy_payment")
  if not payment or type(payment.pay) ~= "function" then return false end
  local reason = {category = category or "business", label = label}
  local ok, result = pcall(payment.pay, {money = {amount = amount, canBeNegative = false}}, reason)
  return ok and result and true or false
end

-- Persistence -------------------------------------------------------------------------------------

local function saveFilePath(savePath)
  return tostring(savePath) .. "/career/rls_career/" .. SAVE_FILE
end

local function persist()
  -- Fresh module instance (Lua hot-reload): self-heal from the saved file before writing, so an
  -- empty table can never overwrite saved settings. After a career deactivation the memory tables
  -- are still the freshest state and the exit save must write them as-is.
  if not (dataLoaded or memoryPopulated) then ensureLoaded() end
  if not lastSavePath then return end
  local payload = {version = CONFIG_VERSION, settings = {}, deliveries = {}}
  for id, config in pairs(settings) do payload.settings[id] = config end
  for id, delivery in pairs(deliveries) do payload.deliveries[id] = delivery end
  local saveSystem = getExt("overhaul_career_saveSystem")
  if saveSystem and type(saveSystem.jsonWriteFileSafe) == "function" then
    pcall(saveSystem.jsonWriteFileSafe, saveFilePath(lastSavePath), payload, true)
  elseif type(jsonWriteFile) == "function" then
    pcall(jsonWriteFile, saveFilePath(lastSavePath), payload)
  end
end

local function sanitizeDelivery(raw)
  raw = type(raw) == "table" and raw or {}
  local remaining = tonumber(raw.remaining)
  local duration = tonumber(raw.duration)
  local units = math.max(0, math.floor(tonumber(raw.units) or 0))
  if not remaining or remaining <= 0 or units <= 0 then return nil end
  return {
    units = units,
    supplyCost = moneyRounded(raw.supplyCost),
    driverFee = moneyRounded(raw.driverFee),
    totalCost = moneyRounded(raw.totalCost),
    tier = validTier(raw.tier),
    distance = tonumber(raw.distance),
    duration = math.max(MIN_DELIVERY_SECONDS, duration or tierConfig(raw.tier).deliverySeconds),
    remaining = remaining,
  }
end

local function loadFromSave(savePath)
  settings, deliveries, blocked = {}, {}, {}
  lastSavePath = savePath
  if not savePath then return end
  local data = jsonReadFile(saveFilePath(savePath))
  if type(data) ~= "table" then return end
  local fileVersion = tonumber(data.version) or 1
  for id, config in pairs(data.settings or {}) do
    local migrated = sanitizeSettings(config)
    if fileVersion < 2 then migrated.autoCollect = true end
    if fileVersion < 3 then
      migrated.enabled = true
      migrated.autoCollect = true
      migrated.thresholdPercent = 0.25
    end
    settings[tostring(id)] = migrated
  end
  for id, delivery in pairs(data.deliveries or {}) do
    local sanitized = sanitizeDelivery(delivery)
    if sanitized then deliveries[tostring(id)] = sanitized end
  end
  memoryPopulated = true
end

currentSavePath = function()
  local saveSystem = getExt("overhaul_career_saveSystem")
  if saveSystem and type(saveSystem.getCurrentProfile) == "function" then
    local ok, _, path = pcall(saveSystem.getCurrentProfile)
    if ok then return path end
  end
  return nil
end

-- BeamNG hot-reloads GE extensions when their source file changes; that resets module state.
-- Reload persisted settings the first time anything asks for them after a reload.
ensureLoaded = function()
  if dataLoaded then return end
  dataLoaded = true
  loadArchetypeConfig()
  invalidateAnchor()
  loadFromSave(currentSavePath())
  updateAccumulator = 0
end

-- Store views -------------------------------------------------------------------------------------

local function storeStatus(state, businessId)
  local delivery = deliveries[businessId]
  if delivery then return "enroute" end
  if blocked[businessId] then return "blocked" end
  local config = settingsFor(businessId)
  if not config.enabled then return "off" end
  local archetype = archetypeFor(state)
  local capacity = (archetype and capacityFor(state, archetype)) or 0
  if capacity <= 0 then return "unsupported" end
  if state.mapId ~= getCurrentLevelIdentifier() then return "otherMap" end
  local threshold = capacity * (config.thresholdPercent or 0.30)
  if (tonumber(state.stock) or 0) <= threshold then return "waiting" end
  return "idle"
end

local function buildStoreView(businessId)
  local id = tostring(businessId)
  local properties = passiveProperties()
  local state = properties and properties[id] or nil
  local config = settingsFor(id)
  local delivery = deliveries[id]
  if not owned(id) or type(state) ~= "table" or not state.archetypeId then
    return {
      businessId = id,
      success = type(state) == "table" or owned(id),
      owned = owned(id),
      compatible = not anchorFailed,
      businessName = facilityName(id, nil),
      settings = config,
      delivery = nil,
      status = (not owned(id)) and "notOwned" or (anchorFailed and "incompatible" or "pending"),
      quotes = {},
    }
  end
  local archetype = archetypeFor(state)
  local view = {
    businessId = id,
    success = true,
    owned = true,
    compatible = true,
    businessName = facilityName(id, archetype),
    businessType = "passiveBusiness",
    archetypeId = state.archetypeId,
    supplyName = supplyNameFor(archetype),
    stock = math.max(0, math.floor(tonumber(state.stock) or 0)),
    capacity = capacityFor(state, archetype) or 0,
    operating = state.operating ~= false,
    wholesaleOwned = state.wholesaleOwned == true,
    pendingEarnings = math.max(0, math.floor((tonumber(state.uncollectedEarnings) or 0) + 0.5)),
    cycleSeconds = tonumber(archetype and archetype.cycleSeconds) or 0,
    sellsOutInSeconds = timeUntilEmpty(state, archetype),
    onCurrentMap = state.mapId == getCurrentLevelIdentifier(),
    settings = config,
    delivery = nil,
    blocked = blocked[id] == true,
    status = storeStatus(state, id),
    quotes = {},
  }
  for _, tier in ipairs({"standard", "express"}) do
    view.quotes[tier] = quoteFor(state, tier)
  end
  local effLevel = efficiencyLevelFor(config.efficiencyLevel)
  local effSpeed = efficiencySpeed(effLevel)
  local baseCycle = tonumber(archetype and archetype.cycleSeconds) or 0
  local palletCost = unitPrice(state)
  local nextLevel = effLevel < MAX_EFFICIENCY_LEVEL and (effLevel + 1) or nil
  local nextCost = nextLevel and efficiencyCost(state, archetype, nextLevel) or nil
  -- Per-hour figures mirror RLS's dashboard math: net per pallet over the effective cycle.
  local netPerPallet = math.max(0, indexed(archetype and archetype.unitRevenue or 0) - unitPrice(state))
  local profitPerHour = netPerPallet > 0 and baseCycle > 0 and effSpeed > 0
    and math.floor(netPerPallet * 3600 / (baseCycle / effSpeed) + 0.5) or 0
  local nextSpeed = nextLevel and EFFICIENCY_LEVELS[nextLevel] or nil
  local nextProfitPerHour = nextSpeed and netPerPallet > 0 and baseCycle > 0
    and math.floor(netPerPallet * 3600 / (baseCycle / nextSpeed) + 0.5) or nil
  local money = getMoney()
  view.efficiency = {
    level = effLevel,
    maxLevel = MAX_EFFICIENCY_LEVEL,
    speedMultiplier = effSpeed,
    cycleSeconds = effSpeed > 0 and (baseCycle / effSpeed) or baseCycle,
    baseCycleSeconds = baseCycle,
    profitPerHour = profitPerHour,
    palletCost = palletCost,
    nextLevel = nextLevel,
    nextMultiplier = nextSpeed,
    nextCycleSeconds = nextSpeed and nextSpeed > 0 and (baseCycle / nextSpeed) or nil,
    nextProfitPerHour = nextProfitPerHour,
    nextCost = nextCost,
    affordable = (nextCost and money ~= nil and money >= nextCost) or false,
  }
  if delivery then
    view.delivery = {
      units = delivery.units,
      tier = delivery.tier,
      remaining = delivery.remaining,
      duration = delivery.duration,
      supplyCost = delivery.supplyCost,
      driverFee = delivery.driverFee,
      totalCost = delivery.totalCost,
    }
  end
  return view
end

local function pushStore(businessId)
  pcall(guihooks.trigger, UI_EVENT, buildStoreView(businessId))
end

-- Dispatching -------------------------------------------------------------------------------------

local function saveCareer()
  local saveSystem = getExt("overhaul_career_saveSystem")
  if saveSystem and type(saveSystem.saveCurrent) == "function" then
    pcall(saveSystem.saveCurrent)
  end
end

local function completeDelivery(businessId, delivery)
  local id = tostring(businessId)
  local properties = passiveProperties()
  local state = properties and properties[id] or nil
  deliveries[id] = nil
  blocked[id] = nil
  if not state or not owned(id) then
    notify("warning", "Auto-restock cancelled", "A restock delivery was cancelled because the store is no longer owned. The order was paid before the sale.")
    persist()
    return
  end
  local archetype = archetypeFor(state)
  local capacity = capacityFor(state, archetype) or 0
  state.stock = math.min(capacity, (tonumber(state.stock) or 0) + delivery.units)
  state.outOfStockNotified = false
  local name = facilityName(id, archetype)
  notify("success", name .. " restocked",
    string.format("Virtual driver delivered +%d pallets | Driver fee: $%d", delivery.units, delivery.driverFee or 0))
  recordStoreFinance(state, delivery.totalCost or 0, delivery.units)
  persist()
  saveCareer()
  pushStore(id)
end

local function dispatch(state, businessId, tierOverride)
  local id = tostring(businessId)
  local archetype = archetypeFor(state)
  local config = settingsFor(id)
  local tier = validTier(tierOverride or config.driverTier)
  local units, capacity = unitsNeeded(state, archetype, config.targetFillPercent)
  if capacity <= 0 or units <= 0 then return false end
  local supplyCost = units * unitPrice(state)
  local distance = storeDistance(state)
  local fee = computeDriverFee(tier, supplyCost, distance)
  local total = supplyCost + fee.total
  local money = getMoney()
  if money == nil or money < total then
    if not blocked[id] then
      blocked[id] = true
      notify("warning", facilityName(id, archetype) .. " needs supplies",
        string.format("Auto-restock paused: dispatch costs $%d but the wallet holds $%s.", total, tostring(money)))
      pushStore(id)
    end
    return false
  end
  local label = string.format("%s: %s (+%d pallets, %s driver)", SUPPLY_FEE_LABEL, supplyNameFor(archetype), units, tier)
  if not payOrder(state, total, label) then
    blocked[id] = true
    pushStore(id)
    return false
  end
  local seconds = deliverySecondsFor(state, archetype, tier)
  deliveries[id] = {
    units = units,
    supplyCost = supplyCost,
    driverFee = fee.total,
    totalCost = total,
    tier = tier,
    distance = distance,
    duration = seconds,
    remaining = seconds,
  }
  blocked[id] = nil
  recordStoreFinance(state, total, units)
  persist()
  saveCareer()
  notify("info", facilityName(id, archetype) .. " driver dispatched",
    string.format("+%d pallets for $%d ($%d supply + $%d driver fee), ETA %ds.", units, total, supplyCost, fee.total, seconds))
  pushStore(id)
  return true
end

-- Update loop -------------------------------------------------------------------------------------

local function collectEarningsRemote(state, businessId, amount, archetype)
  local payment = getExt("overhaul_career_economy_payment")
  if not payment or type(payment.reward) ~= "function" then return false end
  local name = facilityName(businessId, archetype)
  local ok, result = pcall(payment.reward, {money = {amount = amount}}, {category = "business", label = "Auto-collected " .. name .. " earnings"}, true)
  if not ok or result == false then
    log("W", "rlsAutoRestock", "Auto-collect payment failed for " .. tostring(businessId))
    return false
  end
  state.uncollectedEarnings = 0
  recordStoreFinance(state, amount, nil, "collect")
  return true
end

local function autoCollectTick(now)
  local properties = passiveProperties()
  if not properties then return 0, 0, {} end
  local totalCollected, storesTouched = 0, 0
  local collectedNames = {}
  for id, state in pairs(properties) do
    id = tostring(id)
    if type(state) == "table" and owned(id) then
      local config = settingsFor(id)
      if config.autoCollect then
        local pending = math.max(0, math.floor((tonumber(state.uncollectedEarnings) or 0) + 0.5))
        local last = lastCollect[id] or 0
        if pending > 0 and now - last >= COLLECT_COOLDOWN_SECONDS then
          local archetype = archetypeFor(state)
          if collectEarningsRemote(state, id, pending, archetype) then
            lastCollect[id] = now
            totalCollected = totalCollected + pending
            storesTouched = storesTouched + 1
            collectedNames[#collectedNames + 1] = facilityName(id, archetype)
            pushStore(id)
          end
        end
      end
    end
  end
  return totalCollected, storesTouched, collectedNames
end

local function updateStores(elapsed)
  local now = os.time()
  local collectedTotal, collectedStores, collectedNames = autoCollectTick(now)
  if collectedStores > 0 then
    persist()
    saveCareer()
    local nameList
    if #collectedNames == 1 then
      nameList = collectedNames[1]
    else
      nameList = table.concat(collectedNames, ", ", 1, #collectedNames - 1) .. " and " .. collectedNames[#collectedNames]
    end
    notify("success", "Earnings auto-collected",
      string.format("$%s was added to the wallet from %s.", tostring(moneyRounded(collectedTotal)), nameList))
  end
  local properties = passiveProperties()
  if not properties then return end
  for id, delivery in pairs(deliveries) do
    local remaining = (tonumber(delivery.remaining) or 0) - elapsed
    if remaining <= 0 then
      completeDelivery(id, delivery)
    else
      delivery.remaining = remaining
    end
  end
  properties = passiveProperties()
  if not properties then return end
  local levelId = getCurrentLevelIdentifier()
  for id, state in pairs(properties) do
    id = tostring(id)
    if type(state) == "table" and state.archetypeId and state.mapId == levelId then
      local archetype = archetypeFor(state)
      if archetype and archetype.supplyType ~= false and owned(id) then
        local config = settingsFor(id)
        -- Business efficiency: fast-forward the store's sale cycle. RLS's own advanceState turns the
        -- extra progress into pallets and uncollected earnings on its next update tick.
        local speed = efficiencySpeed(config.efficiencyLevel)
        if speed > 1 and state.operating ~= false and (tonumber(state.stock) or 0) > 0 then
          state.cycleProgress = (tonumber(state.cycleProgress) or 0) + (speed - 1) * elapsed
        end
        local delivery = deliveries[id]
        if config.enabled and not delivery then
          local capacity = capacityFor(state, archetype) or 0
          local stock = math.max(0, math.floor(tonumber(state.stock) or 0))
          local threshold = capacity * (config.thresholdPercent or 0.30)
          if capacity > 0 and stock < threshold then
            dispatch(state, id, nil)
          elseif blocked[id] and stock >= threshold then
            blocked[id] = nil
            pushStore(id)
          end
        end
      end
    end
  end
end

function M.onUpdate(_, dtSim)
  local career = getExt("overhaul_career_career")
  if not career or type(career.isActive) ~= "function" then return end
  local ok, active = pcall(career.isActive)
  if not ok or not active then return end
  local dt = math.max(0, tonumber(dtSim) or 0)
  if dt <= 0 then return end
  updateAccumulator = updateAccumulator + dt
  if updateAccumulator < UPDATE_STEP_SECONDS then return end
  local elapsed = updateAccumulator
  updateAccumulator = 0
  updateStores(elapsed)
end

-- Public API --------------------------------------------------------------------------------------

local loggedFirstGet = false

function M.getStoreData(businessId)
  if not loggedFirstGet then
    loggedFirstGet = true
    log("I", "rlsAutoRestock", "getStoreData first call received (Lua v" .. MOD_VERSION .. ")")
  end
  local ok, result = pcall(buildStoreView, businessId)
  if not ok then
    log("E", "rlsAutoRestock", "getStoreData failed: " .. tostring(result))
    return {success = false, compatible = not anchorFailed, error = tostring(result)}
  end
  return result
end

function M.getAllStores()
  local result = {}
  local properties = passiveProperties()
  if properties then
    for id in pairs(properties) do
      if owned(id) then result[#result + 1] = buildStoreView(id) end
    end
  end
  table.sort(result, function(a, b) return tostring(a.businessName) < tostring(b.businessName) end)
  return result
end

function M.setStoreSettings(businessId, changes)
  local id = tostring(businessId)
  local config = settingsFor(id)
  if type(changes) == "table" then
    if changes.enabled ~= nil then config.enabled = changes.enabled == true end
    if changes.autoCollect ~= nil then config.autoCollect = changes.autoCollect == true end
    if changes.thresholdPercent ~= nil then config.thresholdPercent = tonumber(changes.thresholdPercent) end
    if changes.targetFillPercent ~= nil then config.targetFillPercent = tonumber(changes.targetFillPercent) end
    if changes.driverTier ~= nil then config.driverTier = changes.driverTier end
    if changes.efficiencyLevel ~= nil then config.efficiencyLevel = tonumber(changes.efficiencyLevel) end
  end
  settings[id] = sanitizeSettings(config)
  persist()
  pushStore(id)
  return buildStoreView(id)
end

function M.setStoreAutoRestock(businessId, enabled)
  return M.setStoreSettings(businessId, {enabled = enabled == true})
end

function M.setStoreThreshold(businessId, thresholdPercent)
  return M.setStoreSettings(businessId, {thresholdPercent = tonumber(thresholdPercent)})
end

function M.setStoreDriverTier(businessId, tier)
  return M.setStoreSettings(businessId, {driverTier = tier})
end

function M.dispatchNow(businessId, tierOverride)
  local id = tostring(businessId)
  local properties = passiveProperties()
  local state = properties and properties[id] or nil
  if not state or not owned(id) then
    return {success = false, message = "This store is unavailable for auto-restock."}
  end
  if deliveries[id] then
    return {success = false, message = "A driver is already en route to this store."}
  end
  local archetype = archetypeFor(state)
  if not archetype or archetype.supplyType == false then
    return {success = false, message = "This store has no supply chain."}
  end
  local dispatched = dispatch(state, id, tierOverride)
  return {
    success = dispatched,
    message = dispatched and "Driver dispatched." or "The dispatch could not be paid for.",
    store = buildStoreView(id),
  }
end

function M.cancelDelivery(businessId)
  local id = tostring(businessId)
  if not deliveries[id] then return {success = false, message = "No delivery is in transit."} end
  deliveries[id] = nil
  persist()
  pushStore(id)
  return {success = true, message = "Delivery cancelled. Paid supply and driver fees are forfeited."}
end

function M.setAllStores(changes)
  local properties = passiveProperties()
  if not properties then return {success = false, message = "RLS store state is not accessible."} end
  local changed = 0
  for id in pairs(properties) do
    id = tostring(id)
    if owned(id) then
      M.setStoreSettings(id, changes)
      changed = changed + 1
    end
  end
  return {success = changed > 0, changed = changed, message = "Applied settings to " .. changed .. " stores."}
end

function M.collectNow(businessId)
  local id = tostring(businessId)
  local properties = passiveProperties()
  local state = properties and properties[id] or nil
  if not state or not owned(id) then
    return {success = false, message = "This store is unavailable for auto-collect."}
  end
  local pending = math.max(0, math.floor((tonumber(state.uncollectedEarnings) or 0) + 0.5))
  if pending <= 0 then
    return {success = false, message = "There are no earnings to collect.", store = buildStoreView(id)}
  end
  if not collectEarningsRemote(state, id, pending, archetypeFor(state)) then
    return {success = false, message = "The wallet deposit failed.", store = buildStoreView(id)}
  end
  lastCollect[id] = os.time()
  persist()
  saveCareer()
  local view = buildStoreView(id)
  view.message = string.format("Collected $%d from %s.", pending, view.businessName or "the store")
  pushStore(id)
  return view
end

-- Buys the next business-efficiency level for a store: each level multiplies the selling speed
-- (halving the earnings cycle). Costs a multiple of a full store of stock; charged like RLS's own
-- upgrades (category "purchase") and recorded into the store's Upgrades finance total.
function M.purchaseEfficiencyUpgrade(businessId)
  local id = tostring(businessId)
  local properties = passiveProperties()
  local state = properties and properties[id] or nil
  if not state or not owned(id) then
    return {success = false, message = "This store is unavailable for upgrades."}
  end
  local archetype = archetypeFor(state)
  if not archetype or archetype.supplyType == false then
    return {success = false, message = "This store has no retail cycle to speed up."}
  end
  local config = settingsFor(id)
  local level = efficiencyLevelFor(config.efficiencyLevel)
  if level >= MAX_EFFICIENCY_LEVEL then
    return {success = false, message = "Business efficiency is already at its maximum.", store = buildStoreView(id)}
  end
  local nextLevel = level + 1
  local cost = efficiencyCost(state, archetype, nextLevel)
  if not cost or cost <= 0 then
    return {success = false, message = "The efficiency upgrade is unavailable for this store."}
  end
  local money = getMoney()
  if money == nil or money < cost then
    return {
      success = false,
      message = string.format("The upgrade costs $%d but the wallet holds $%s.", cost, tostring(money)),
      store = buildStoreView(id),
    }
  end
  local name = facilityName(id, archetype)
  local label = string.format("%s efficiency upgrade (level %d)", name, nextLevel)
  if not payOrder(state, cost, label, "purchase") then
    return {success = false, message = "The efficiency upgrade could not be paid for.", store = buildStoreView(id)}
  end
  config.efficiencyLevel = nextLevel
  recordStoreFinance(state, cost, nil, "efficiency")
  persist()
  saveCareer()
  local speed = EFFICIENCY_LEVELS[nextLevel]
  local cycle = math.max(1, math.floor(((tonumber(archetype.cycleSeconds) or 0) / speed) + 0.5))
  notify("success", name .. " efficiency upgraded",
    string.format("Level %d: payouts arrive %dx as often - one pallet sold every %ds of active play.", nextLevel, speed, cycle))
  local view = buildStoreView(id)
  pushStore(id)
  return {success = true, message = "Business efficiency upgraded to level " .. nextLevel .. ".", store = view}
end

-- Game hooks --------------------------------------------------------------------------------------

local function onCareerReady()
  dataLoaded = true
  loadArchetypeConfig()
  invalidateAnchor()
  loadFromSave(currentSavePath())
  updateAccumulator = 0
end

function M.onCareerActivated()
  onCareerReady()
end

function M.onOverhaulActive(active)
  if active then
    onCareerReady()
  else
    -- Keep the memory tables and memoryPopulated: RLS fires the exit save after this hook and it
    -- must persist the live state. dataLoaded=false marks the career inactive; the next activation
    -- (or any read) reloads from the career save via the usual self-heal.
    dataLoaded = false
    invalidateAnchor()
  end
end

-- RLS's save pipeline rotates slots: every save is written to the OLDEST autosave slot and that
-- path is what this hook receives. Follow it on every save so our file always lands in the slot
-- the career will resume from (pinning the first-seen path left our data in a superseded slot).
function M.onOverhaulSaveCurrentProfile(currentSavePath)
  if not currentSavePath then return end
  lastSavePath = currentSavePath
  persist()
end

function M.reloadUI()
  guihooks.trigger("UiModsChanged")
  return {success = true, message = "UI mods reload triggered."}
end

function M.onExtensionLoaded()
  log("I", "rlsAutoRestock", "RLS Auto-Restock companion v" .. MOD_VERSION .. " loaded. Waiting for an RLS career session.")
end

function M.onClientEndMission()
  updateAccumulator = 0
end

M.TIERS = TIERS
M.EFFICIENCY_LEVELS = EFFICIENCY_LEVELS
M.MAX_EFFICIENCY_LEVEL = MAX_EFFICIENCY_LEVEL

return M
