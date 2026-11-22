# Initial build prompt — rls_auto_restock

The verbatim instruction that produced this mod (one AI coding session, see the
[Cost to make](../README.md#cost-to-make) note in the README).

---

RLS Mod files can be found here: C:\Users\grant\Downloads\rls_career_overhaul_v2.8.0.zip

Task: Create an Autonomous Store Restocking Companion Mod for BeamNG.drive (RLS Career Overhaul) & Publish to GitHub
Context & Goal
I am playing BeamNG.drive with the RLS Career Overhaul mod installed. Currently, owned businesses/stores require me to manually order supplies and drive delivery routes to restock them. I want you to build a lightweight, standalone BeamNG companion mod (a separate mod folder) that automatically dispatches virtual delivery drivers to restock my owned businesses in the background—complete with per-store toggles/settings inside the in-game Store Management UI, a simulated delivery delay timer guaranteed to beat each store's consumption rate, a virtual driver fee structure, and publishing the completed mod to a public repository on my GitHub account.
Step 1: Codebase Discovery (Explore First)
Before writing any code, inspect the extracted RLS Career Overhaul source files. Specifically:
Backend Business Logic: Search lua/ge/extensions/career/modules/ for modules handling owned businesses, stores, inventory, stock consumption rates/timers, supply orders, pickup/warehouse locations, and business finances.
Store Management UI: Inspect the UI files (likely under ui/ or ui/modules/apps/) for the phone's Business / Store management app to see:
Which Vue/JS components render individual owned stores and their supply order buttons.
How bngApi.engineLua(...) and guihooks.trigger(...) pass store data between Lua and the UI.
How BeamNG UI file overrides work so our patched Store Management component overrides RLS cleanly without editing rls_career_overhaul.zip.
Key Data Points to Identify:
How each owned business is uniquely identified (businessId), where its current stock and max capacity live, and its stock consumption rate (units consumed per second/minute).
How career money (career_modules_playerAttributes or RLS's custom economy/bank module) is checked and deducted.
How career save/load hooks (onSaveCurrentSaveSlot / onCareerActive) serialize data so per-store settings and active deliveries persist across game restarts.
Step 2: Architecture & Mod Requirements
Build this as a standalone companion mod (rls_auto_restock) decoupled from rls_career_overhaul.zip:
1. Per-Store Configuration & Persistence
Persist a settings table inside the active career save slot directory (via onSaveCurrentSaveSlot) keyed by businessId:
autoRestockEnabled (boolean, default false so I can opt-in per store)
restockThresholdPercent (number, default 0.30 — triggers when stock drops below 30%)
targetFillPercent (number, default 1.0 — orders enough to fill to 100%)
driverTier (string, default "standard" — "standard" or "express")
Expose Lua bridge functions (getAutoRestockSettings, setStoreAutoRestock, etc.) for the UI to read and update settings.
2. Virtual Driver Fee Structure
Implement a transparent, balanced driver payroll/dispatch fee on top of the wholesale supply cost so hiring virtual drivers feels like an authentic business expense:
Formula: totalOrderCost = wholesaleSupplyCost + driverFee
Driver Fee Breakdown:
Base Dispatch Fee: Fixed flat rate per run (e.g., $150 standard / $300 express) to cover the driver's call-out.
Cargo / Volume Surcharge: Percentage or per-unit hauling fee (e.g., 12% of wholesale supply cost for Standard, 22% for Express) to scale with truck/load size.
(Bonus if coordinates are available in RLS data): Optional distance surcharge based on Euclidean distance from the supply depot to the store.
Return the estimated driverFee and totalOrderCost to the UI so I can see what a dispatch costs before enabling it.
3. Simulated Delivery Delay Timer (Guaranteed Faster Than Consumption)
When an enabled store's stock drops below restockThresholdPercent * maxStock and has no active delivery in transit:
Calculate unitsNeeded = math.floor((targetFillPercent * maxStock) - currentStock).
Calculate wholesaleSupplyCost and driverFee (totalOrderCost = wholesaleSupplyCost + driverFee).
Check player career balance (>= totalOrderCost). If affordable, deduct totalOrderCost immediately and create an in-transit delivery timer for that store.
Dynamic Delivery Time Calculation (Must Beat Consumption):
Read or calculate the store's current stock consumption rate (unitsPerSecond).
Calculate timeUntilEmpty = currentStock / unitsPerSecond.
Set base transit time (45s for Standard, 20s for Express), clamped to never exceed 50% of timeUntilEmpty (with a minimum floor of 5 seconds):
deliveryDuration = math.max(5, math.min(baseDeliverySeconds, timeUntilEmpty * 0.5))
This guarantees every delivery arrives well before the store runs empty, ensuring stock levels always trend upward.
Delivery Completion:
When deliveryTimer <= 0, add unitsNeeded to the store's inventory (clamped to maxStock), clear the in-transit state, and trigger a BeamNG notification (e.g., "[Store Name] restocked (+X units) | Driver fee: $Y").
Persist remaining transit timers on save so mid-transit deliveries finish properly on reload.
4. Store Management UI Integration
Patch the RLS Store Management UI view/component to add a compact "Virtual Driver / Auto-Restock" panel inside each store's management card:
Enable/Disable Toggle for that store.
Threshold Preset Selector (25% / 50% / 75%).
Driver Tier Selector (Standard vs. Express — showing estimated driver fee).
Live Status Badge: Shows "Idle", "Driver En Route (Xs)", or "Insufficient Funds".
5. Safety & Error Handling
Guard onUpdate(dtReal, dtSim, dtRaw) so it only executes when Career Mode is active (career_career and career_career.isActive()), unpaused (dtSim > 0), and RLS's business module is loaded.
Register the Lua extension cleanly via scripts/rls_auto_restock/modScript.lua.
Step 3: GitHub Repository Setup & Publish
Once the mod files are written and verified:
Initialize a Git repository inside the rls_auto_restock project directory (git init).
Write a clean, comprehensive README.md explaining:
What the mod does (autonomous virtual delivery drivers for RLS Career Overhaul businesses).
Features (per-store UI controls, dynamic delivery timers, driver fee structure).
Installation instructions (dropping into %LOCALAPPDATA%\BeamNG.drive\current\mods\).
Create a .gitignore (ignoring .DS_Store, Thumbs.db, temp/backup files).
