-- Sterilizing dressings in water hot off a heat source: the game's
-- DisinfectBandage takes a bandage or rag and 0.5 l of water in a container
-- hotter than 1.6 (RecipeCodeOnTest.hotFluidContainer). The largest pot
-- around is filled at a clean tap, heated on whatever heat the kitchen drives
-- (a microwave never takes metal), taken off once hot, and topped up and
-- heated again while dressings are left. Its steps live in the kitchen's
-- ledger, so the heat is turned off like any dish's, even after a reload;
-- the pot is borrowed and goes back where it was.
local Fetch = require "AutoMindful/Fetch"
local Grid = require "AutoMindful/Grid"
local Log = require "AutoMindful/Log"
local Snap = require "AutoMindful/Snapshot"
local Supplies = require "AutoMindful/Supplies"
local Dressings = require "AutoMindful/Dressings"
local Alerts = require "AutoMindful/Alerts"
local FirstAid = require "AutoMindful/FirstAid"

-- hot: the game's own threshold; heatMs: how long a pot may take to heat;
-- tries: walks and steps that change nothing before it gives up.
local Boil = {policy = {liters = 0.5, hot = 1.6, heatMs = 900000, tries = 3, retryMs = 600000}}
local K, P
local sources = {}

function Boil.bind(kitchen, parts) K, P = kitchen, parts end

local stages = {["boil-fetch"] = true, ["boil-fill"] = true, ["boil-place"] = true, ["boil-heat"] = true, ["boil-make"] = true,
    ["boil-off"] = true}
function Boil.handles(stage) return stages[stage] == true end
-- On the heat: what the kitchen counts as lit.
function Boil.hot(stage) return stage == "boil-heat" or stage == "boil-make" end

local function read(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then return value end
    return fallback
end

local function fluidOf(item)
    local world = read(function() return item:getWorldItem() end)
    return world and world:getFluidContainer() or read(function() return item:getFluidContainer() end)
end

-- A pot for water: cookware holding nothing but water, room for one dressing's
-- worth at least. The largest first; past three litres only when nothing smaller
-- will do, or a whole bucket would have to come to the boil.
Boil.roles = {pot = {match = function(item)
    if instanceof(item, "Food") then return false end
    local fluid = fluidOf(item)
    return fluid ~= nil and read(function()
        return item:hasTag(ItemTag.COOKABLE) and fluid:getCapacity() >= Boil.policy.liters
            and (fluid:isEmpty() or fluid:isPureFluid(Fluid.Water)) and not fluid:isInputLocked()
    end, false) == true
end, grade = function(item)
    local capacity = fluidOf(item):getCapacity()
    return capacity <= 3 and -capacity or capacity
end}}

FirstAid.addRoles(Boil.roles)

-- Enough water for one more dressing, give or take the game's rounding.
local function enough(amount, liters) return amount + 0.005 >= (liters or Boil.policy.liters) end

local function plain(player)
    local inventory = player:getInventory()
    return inventory:getFirstTypeRecurse("RippedSheets") or inventory:getFirstTypeRecurse("Bandage")
end

local function release(state)
    local loan = state.boilLoan
    if loan then loan.defer, loan.aidReturn = nil, true end
    state.boilLoan = nil
end

local function forget(player) sources[player] = nil end
Boil.forget = forget

local function fail(player, state, now, entry, why)
    Log.event(player, "boil.ended", "why", why, "made", entry.made or 0, "count", entry.count)
    if state then
        state.kitchenSkip = state.kitchenSkip or {}
        state.kitchenSkip["boil"] = now + Boil.policy.retryMs
        release(state)
    end
    forget(player)
    K.write(player, nil)
    return false
end

-- Starts a plan for count dressings with the pot found by FirstAid's picker
-- (pot: a found entry). False when there is no heat or no clean water for it.
function Boil.start(player, state, now, count, pot)
    if K.ledger(player) then return false end
    local skip = state.kitchenSkip and state.kitchenSkip["boil"]
    if skip and now < skip then return false end
    local found = K.scan(player, state.kitchenSkip, now)
    local heat
    for _, stove in ipairs(found.stoves) do
        if not heat and K.accepts(stove.object, pot.item) then heat = stove end
    end
    local fluid = fluidOf(pot.item)
    local filled = fluid and enough(fluid:getAmount())
    local tap = found.taps[1]
    if not heat or (not filled and not tap) then
        state.kitchenSkip = state.kitchenSkip or {}
        state.kitchenSkip["boil"] = now + Boil.policy.retryMs
        Log.event(player, "boil.cannot", "heat", heat ~= nil, "tap", tap ~= nil, "pot", Snap.item(pot.item))
        return false
    end
    local square = heat.object:getSquare()
    local entry = {stage = "boil-fetch", kind = "boil", name = "water", item = pot.item:getID(), count = count, made = 0,
        x = square:getX(), y = square:getY(), z = square:getZ(), heat = K.heatKind(heat.object)}
    sources[player] = {pot = pot, tap = tap and {square = tap.square, x = tap.square:getX(), y = tap.square:getY(), z = tap.square:getZ()}}
    K.write(player, entry)
    Log.event(player, "boil.start", "pot", Snap.item(pot.item), "heat", Snap.object(heat.object), "tap", tap and Snap.object(tap.object), "count", count)
    return true
end

local function tapAt(source)
    local square = source and getCell():getGridSquare(source.x, source.y, source.z)
    if not square then return nil end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if K.isTap(object) then return object, square end
    end
    return nil
end

local function walkTo(player, state, now, entry, square, message)
    entry.walks = (entry.walks or 0) + 1
    if entry.walks > Boil.policy.tries then return fail(player, state, now, entry, "unreachable") end
    K.write(player, entry)
    return P.ownBatch(player, state, "kitchen", message, function() luautils.walkAdj(player, square, true) end)
end

local function adjacent(player, square) return Grid.reachable(player:getSquare(), square) end

-- One batch for the stage the plan is at.
function Boil.step(player, state, now, entry, stove)
    local inventory = player:getInventory()
    local pot = inventory:getItemById(entry.item)
    local source = sources[player]
    if entry.stage == "boil-fetch" then
        if pot then
            entry.stage, entry.walks = "boil-fill", 0
            K.write(player, entry)
            return Boil.step(player, state, now, entry, stove)
        end
        if not source or not Fetch.present(source.pot.entry) then return fail(player, state, now, entry, "pot-gone") end
        local square = source.pot.square
        if square and not adjacent(player, square) then return walkTo(player, state, now, entry, square, "Going for a pot to boil water in.") end
        return P.ownBatch(player, state, "kitchen", "Getting " .. source.pot.item:getDisplayName() .. " to boil water in.", function()
            local item = source.pot.item
            local loan = P.loanFor(player, state, item)
            if loan then loan.defer = true; state.boilLoan = loan end
            if source.pot.entry.world then Fetch.queue(player, source.pot.entry) else Supplies.transfer(player, item, loan) end
        end)
    end
    local onHeat = entry.stage == "boil-heat" or entry.stage == "boil-make" or entry.stage == "boil-off"
    if not pot and not onHeat then return fail(player, state, now, entry, "pot-lost") end
    local remaining = entry.count - (entry.made or 0)
    if entry.stage == "boil-fill" then
        local fluid = fluidOf(pot)
        if not fluid or not (fluid:isEmpty() or fluid:isPureFluid(Fluid.Water)) then return fail(player, state, now, entry, "not-water") end
        -- A little over what is left to sterilize, so the last one still has its half litre.
        local need = math.min(fluid:getCapacity(), Boil.policy.liters * remaining + 0.1)
        if enough(fluid:getAmount(), need) or (enough(fluid:getAmount()) and not (source and source.tap)) then
            entry.stage, entry.walks = "boil-place", 0
            K.write(player, entry)
            return Boil.step(player, state, now, entry, stove)
        end
        local tap, square = tapAt(source and source.tap)
        if not tap then
            if enough(fluid:getAmount()) then entry.stage = "boil-place"; K.write(player, entry); return Boil.step(player, state, now, entry, stove) end
            return fail(player, state, now, entry, "no-tap")
        end
        if not adjacent(player, square) then return walkTo(player, state, now, entry, square, "Going to the tap to fill " .. pot:getDisplayName() .. ".") end
        entry.before = fluid:getAmount()
        K.write(player, entry)
        return P.ownBatch(player, state, "kitchen", "Filling " .. pot:getDisplayName() .. " to sterilize dressings.", function()
            ISTimedActionQueue.add(ISTakeWaterAction:new(player, pot, tap, false))
        end)
    end
    if not stove then return fail(player, state, now, entry, "heat-gone") end
    local container = stove:getContainer()
    if entry.stage == "boil-place" then
        if not K.accepts(stove, pot) or (K.isOn(stove) and not K.shared(stove)) or not K.canHeat(stove) then return fail(player, state, now, entry, "heat-busy") end
        if not adjacent(player, stove:getSquare()) then return walkTo(player, state, now, entry, stove:getSquare(), "Taking water to the " .. K.heatName(stove) .. ".") end
        entry.placedAt = now
        K.write(player, entry)
        return P.ownBatch(player, state, "kitchen", "Heating water on the " .. K.heatName(stove) .. " to sterilize dressings.", function()
            local into = ISInventoryTransferUtil.newInventoryTransferAction(player, pot, pot:getContainer(), container)
            ISTimedActionQueue.add(into)
            K.toggle(player, stove, true, pot, 30, entry, function()
                local current = K.ledger(player)
                if current then current.litHere = true; K.write(player, current) end
            end)
        end)
    end
    -- Water cools within moments of leaving the heat, so dressings are
    -- sterilized with the pot still on it (the recipe may use what is beside
    -- the survivor); then the heat goes off and the pot comes away.
    local inside = container:getItemById(entry.item)
    local function off(message, after)
        entry.stage, entry.after = "boil-off", after
        K.write(player, entry)
        return P.ownBatch(player, state, "kitchen", message, function()
            if not adjacent(player, stove:getSquare()) and not luautils.walkAdj(player, stove:getSquare(), true) then return end
            if entry.lit and K.isOn(stove) then K.toggle(player, stove, false) end
            if inside then ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player, inside, container, inventory)) end
        end)
    end
    if entry.stage == "boil-heat" or entry.stage == "boil-make" then
        if not inside then return fail(player, state, now, entry, "pot-lost") end
        local hot = inside:getItemHeat() > Boil.policy.hot
        local on = K.isOn(stove) or (entry.grace ~= nil and now < entry.grace)
        local late = entry.placedAt and (now < entry.placedAt or now - entry.placedAt > Boil.policy.heatMs)
        local fluid = fluidOf(inside)
        local anchor = plain(player)
        if remaining <= 0 or not anchor then return off("Done sterilizing: the heat off, the pot away.", "done") end
        if not fluid or not enough(fluid:getAmount()) then return off("Taking the pot off to top it up.", "fill") end
        if not hot then
            if not on or late then return off("The water would not heat: the heat off, the pot away.", "cold") end
            entry.stage = "boil-heat"
            local share = math.floor(math.max(0, math.min(1, (inside:getItemHeat() - 1) / (Boil.policy.hot - 1))) * 100)
            P.setPhase(state, "kitchen-watch", "Heating water to sterilize dressings: " .. share .. "%. Staying near the " .. K.heatName(stove) .. ".")
            return true
        end
        if not adjacent(player, stove:getSquare()) then return walkTo(player, state, now, entry, stove:getSquare(), "Back to the hot water.") end
        local logic = Dressings.logic(player, Dressings.recipes.boil, anchor, {container})
        if not logic then return off("The water would not sterilize: the heat off, the pot away.", "cannot") end
        entry.stage, entry.anchor = "boil-make", anchor:getID()
        K.write(player, entry)
        return P.ownBatch(player, state, "kitchen", "Sterilizing " .. anchor:getDisplayName() .. " in the hot water.", function()
            Dressings.craft(player, logic)
        end)
    end
    if entry.stage == "boil-off" then
        if inside then return off("Taking the pot off the heat.", entry.after) end
        if entry.after == "fill" then
            entry.stage, entry.walks, entry.lit, entry.litHere, entry.after = "boil-fill", 0, nil, nil, nil
            K.write(player, entry)
            return Boil.step(player, state, now, entry, stove)
        end
        if entry.after ~= "done" then return fail(player, state, now, entry, entry.after or "off") end
        Log.event(player, "boil.done", "made", entry.made or 0)
        release(state)
        forget(player)
        K.write(player, nil)
        return false
    end
    return false
end

-- After each batch: what the world says happened.
function Boil.settle(player, state, now, cut)
    local entry = K.ledger(player)
    if not entry then return end
    local inventory = player:getInventory()
    local stove = K.stoveAt(entry)
    if entry.stage == "boil-place" then
        local inside = stove and stove:getContainer():getItemById(entry.item)
        if inside then
            local on = K.isOn(stove)
            if K.fueled(stove) then entry.lit = entry.litHere or nil
            else entry.lit = on and true or nil end
            if not on then entry.grace = now + 5000 end
            entry.stage = "boil-heat"
        elseif not cut then
            entry.tries = (entry.tries or 0) + 1
            if entry.tries > Boil.policy.tries then return fail(player, state, now, entry, "not-placed") end
        end
    elseif entry.stage == "boil-off" then
        local inside = stove and stove:getContainer():getItemById(entry.item)
        if inside and not cut then
            entry.tries = (entry.tries or 0) + 1
            if entry.tries > Boil.policy.tries then
                Alerts.raise(player, "stove", "A pot is still on the heat and Second Nature cannot reach it.", now, true)
                return fail(player, state, now, entry, "left-on-heat")
            end
        end
    elseif entry.stage == "boil-make" and entry.anchor then
        if not inventory:getItemById(entry.anchor) then entry.made = (entry.made or 0) + 1; entry.tries = 0
        elseif not cut then
            entry.tries = (entry.tries or 0) + 1
            if entry.tries > Boil.policy.tries then return fail(player, state, now, entry, "nothing-made") end
        end
        entry.anchor = nil
    elseif entry.stage == "boil-fill" and entry.before then
        local pot = inventory:getItemById(entry.item)
        local fluid = pot and fluidOf(pot)
        if not (fluid and fluid:getAmount() > entry.before) and not cut then
            entry.tries = (entry.tries or 0) + 1
            if entry.tries > Boil.policy.tries then return fail(player, state, now, entry, "not-filled") end
        end
        entry.before = nil
    end
    K.write(player, entry)
end

return Boil
