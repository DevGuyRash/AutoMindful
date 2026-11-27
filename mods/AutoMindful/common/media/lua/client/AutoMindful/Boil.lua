-- Sterilizing dressings in water hot off a heat source: the game's
-- DisinfectBandage takes a bandage or rag and 0.5 l of water in a container
-- hotter than 1.6 (RecipeCodeOnTest.hotFluidContainer). The largest pot
-- around is filled at a clean tap and heated on whatever heat the kitchen
-- drives (an unlit fire is laid and lit as for a dish; a microwave never takes
-- metal). Water cools within moments of leaving the heat, so each dressing is
-- sterilized with the pot still on it; the pot is topped up and heated again
-- while dressings are left. Its steps live in the kitchen's ledger, which is
-- only ever cleared once the pot is off the heat and our heat is off; the pot
-- is borrowed and goes back where it was.
local Fetch = require "AutoMindful/Fetch"
local Fire = require "AutoMindful/Fire"
local Grid = require "AutoMindful/Grid"
local Log = require "AutoMindful/Log"
local Snap = require "AutoMindful/Snapshot"
local Supplies = require "AutoMindful/Supplies"
local Dressings = require "AutoMindful/Dressings"
local Alerts = require "AutoMindful/Alerts"
local FirstAid = require "AutoMindful/FirstAid"

-- hot: the game's own threshold; heatMs: how long water may take to heat;
-- tries: steps that change nothing before it gives up; steps and cuts bound a
-- whole plan, so it never holds the kitchen's only ledger for ever.
local Boil = {policy = {liters = 0.5, hot = 1.6, heatMs = 900000, tries = 3, retryMs = 600000, steps = 200, cuts = 6,
    fireMinutes = 40}}
local K, P
local sources = {}

function Boil.bind(kitchen, parts) K, P = kitchen, parts end

local stages = {["boil-fetch"] = true, ["boil-fill"] = true, ["boil-place"] = true, ["boil-heat"] = true, ["boil-make"] = true,
    ["boil-off"] = true}
function Boil.handles(stage) return stages[stage] == true end
-- With the pot on the heat: what the kitchen counts as lit.
function Boil.hot(stage) return stage == "boil-heat" or stage == "boil-make" or stage == "boil-off" end

local function read(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then return value end
    return fallback
end

local function fluidOf(item)
    local world = read(function() return item:getWorldItem() end)
    return world and world:getFluidContainer() or read(function() return item:getFluidContainer() end)
end

-- A pot for water: cookware holding nothing but water, with room for one
-- dressing's worth at least. The largest wherever it is nearby; it is only
-- filled as far as the dressings left need.
Boil.roles = {pot = {anywhere = true, match = function(item)
    if instanceof(item, "Food") then return false end
    local fluid = fluidOf(item)
    return fluid ~= nil and read(function()
        -- Not a petrol can or a paint bucket, whatever the game lets go on a heat.
        return item:hasTag(ItemTag.COOKABLE) and not item:hasTag(ItemTag.PETROL) and not string.find(item:getType(), "Paint", 1, true)
            and fluid:getCapacity() >= Boil.policy.liters
            and (fluid:isEmpty() or fluid:isPureFluid(Fluid.Water)) and not fluid:isInputLocked()
    end, false) == true
end, grade = function(item) return -fluidOf(item):getCapacity() end}}
FirstAid.addRoles(Boil.roles)

-- Enough water for one more dressing, give or take the game's rounding.
local function enough(amount, liters) return amount + 0.005 >= (liters or Boil.policy.liters) end

local function plain(player)
    local inventory = player:getInventory()
    return inventory:getFirstTypeRecurse("RippedSheets") or inventory:getFirstTypeRecurse("Bandage")
end

local function adjacent(player, square) return Grid.reachable(player:getSquare(), square) end

-- The pot's way home: an ordinary loan, held (not returned, not dropped as
-- done, even through a yield) while the boiling goes on, and let go after.
local function homeward(player)
    local source = sources[player]
    local loan = source and source.loan
    if type(loan) == "table" then loan.defer, loan.held, loan.aidReturn = nil, nil, true end
    sources[player] = nil
end

local function close(player, state, now, entry, why)
    Log.event(player, why == "done" and "boil.done" or "boil.ended", "why", why, "made", entry.made or 0, "count", entry.count)
    if why ~= "done" and state then
        state.kitchenSkip = state.kitchenSkip or {}
        state.kitchenSkip["boil"] = now + Boil.policy.retryMs
    end
    homeward(player)
    K.write(player, nil)
    return false
end

function Boil.forget(player) homeward(player) end

-- Ours on the heat: the pot in the heat's container, or a heat we lit still
-- on. Out of sight, a heat we lit counts as on.
local function onHeat(entry, stove)
    if not stove then return (entry.lit or entry.litHere) == true end
    local inside = stove:getContainer():getItemById(entry.item)
    return inside ~= nil or ((entry.lit or entry.litHere) and K.isOn(stove)) == true
end

-- Gives up: straight away when nothing of ours is on the heat, otherwise only
-- once the heat is off and the pot away.
local function fail(player, state, now, entry, stove, why, later)
    if onHeat(entry, stove) then
        entry.stage, entry.after, entry.tries = "boil-off", why, 0
        K.write(player, entry)
        -- From a settle: the next step takes it off, so no batch is queued unowned.
        if later then return false end
        return Boil.step(player, state, now, entry, stove)
    end
    return close(player, state, now, entry, why)
end

-- Starts a plan for count dressings with the pots FirstAid's picker found
-- (best first): the first heat that takes one of them. False when there is no
-- heat for any, no clean water, or no light for an unlit fire.
function Boil.start(player, state, now, count, pots)
    if K.ledger(player) then return false end
    local skip = state.kitchenSkip and state.kitchenSkip["boil"]
    if skip and now < skip then return false end
    local found = K.scan(player, state.kitchenSkip, now)
    local heat, pot, plan
    for _, stove in ipairs(found.stoves) do
        for _, candidate in ipairs(pots) do
            if not heat and K.accepts(stove.object, candidate.item) then
                local fire = K.fueled(stove.object) and not K.isOn(stove.object)
                plan = fire and Fire.plan(stove.object, Boil.policy.fireMinutes, found) or nil
                if not fire or plan then heat, pot = stove, candidate end
            end
        end
    end
    -- The others this heat takes, best first: one out of reach makes way for the next.
    local spares = {}
    for _, candidate in ipairs(pots) do
        if heat and candidate ~= pot and not candidate.carried and K.accepts(heat.object, candidate.item) then spares[#spares + 1] = candidate end
    end
    local fluid = pot and fluidOf(pot.item)
    -- Taps, sinks and barrels, nearest first: never a bottle or pot of water lying on the floor.
    local taps = {}
    for _, candidate in ipairs(found.taps) do
        if not instanceof(candidate.object, "IsoWorldInventoryObject") then
            taps[#taps + 1] = {x = candidate.square:getX(), y = candidate.square:getY(), z = candidate.square:getZ()}
        end
    end
    local tap = found.taps[1] and #taps > 0
    if not heat or not ((fluid and enough(fluid:getAmount())) or tap) then
        state.kitchenSkip = state.kitchenSkip or {}
        state.kitchenSkip["boil"] = now + Boil.policy.retryMs
        Log.event(player, "boil.cannot", "heat", heat ~= nil, "tap", tap ~= nil, "pots", #pots)
        return false
    end
    local square = heat.object:getSquare()
    local entry = {stage = "boil-fetch", kind = "boil", name = "water", item = pot.item:getID(), count = count, made = 0,
        x = square:getX(), y = square:getY(), z = square:getZ(), heat = K.heatKind(heat.object)}
    -- What it takes into the hands: the pot (borrowed), and for an unlit fire its fuel, tinder and light.
    local fetch = {}
    if not pot.carried then fetch[#fetch + 1] = pot.entry end
    if plan then
        entry.fire = {fuel = {}, tinder = plan.tinder and plan.tinder.item:getID(), starter = plan.starter and plan.starter.item:getID()}
        for _, fuel in ipairs(plan.fuel) do entry.fire.fuel[#entry.fire.fuel + 1] = fuel.item:getID(); fetch[#fetch + 1] = fuel end
        if plan.tinder then fetch[#fetch + 1] = plan.tinder end
        if plan.starter then fetch[#fetch + 1] = plan.starter end
    end
    sources[player] = {fetch = fetch, loan = not pot.carried or nil, pot = pot.item, spares = spares,
        taps = taps}
    K.write(player, entry)
    Log.event(player, "boil.start", "pot", Snap.item(pot.item), "heat", Snap.object(heat.object), "taps", #taps,
        "count", count, "fire", plan ~= nil)
    return true
end

local function tapAt(source)
    local square = source and getCell():getGridSquare(source.x, source.y, source.z)
    if not square then return nil end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if K.isTap(object) and not instanceof(object, "IsoWorldInventoryObject") then return object, square end
    end
    return nil
end

local function batch(player, state, entry, message, add)
    entry.steps = (entry.steps or 0) + 1
    K.write(player, entry)
    return P.ownBatch(player, state, "kitchen", message, add)
end

local function walkTo(player, state, now, entry, stove, square, message)
    entry.walks = (entry.walks or 0) + 1
    if entry.walks > Boil.policy.tries then return fail(player, state, now, entry, stove, "unreachable") end
    return batch(player, state, entry, message, function() luautils.walkAdj(player, square, true) end)
end

-- One batch for the stage the plan is at.
function Boil.step(player, state, now, entry, stove)
    local inventory = player:getInventory()
    local source = sources[player]
    if (entry.steps or 0) > Boil.policy.steps or (entry.cuts or 0) > Boil.policy.cuts then
        if entry.stage ~= "boil-off" then return fail(player, state, now, entry, stove, "stuck") end
    end
    local container = stove and stove:getContainer()
    local inside = container and container:getItemById(entry.item)
    local pot = inventory:getItemById(entry.item)
    local remaining = entry.count - (entry.made or 0)

    -- Off the heat: our heat off and the pot in the hands, whatever came before.
    local function off(message, after)
        entry.stage, entry.after = "boil-off", after or entry.after
        return batch(player, state, entry, message, function()
            if not adjacent(player, stove:getSquare()) and not luautils.walkAdj(player, stove:getSquare(), true) then return end
            -- A fire is left burning while the pot is topped up: lighting it again
            -- would take tinder it no longer has. Anything else goes off.
            local keep = entry.after == "fill" and K.fueled(stove)
            if not keep and (entry.lit or entry.litHere) and K.isOn(stove) then K.toggle(player, stove, false) end
            if inside then ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player, inside, container, inventory)) end
        end)
    end

    if entry.stage == "boil-off" then
        if not stove then
            -- Out of sight: the kitchen's watchdog keeps saying so while the ledger stands.
            if state then state.kitchenNotice = "The heat with the pot of water is out of sight." end
            return false
        end
        local fire = entry.after == "fill" and K.fueled(stove)
        if container:getItemById(entry.item) or (not fire and onHeat(entry, stove)) then
            if entry.waitUntil and now < entry.waitUntil and entry.waitUntil - now <= 120000 then return false end
            if (entry.tries or 0) >= Boil.policy.tries then
                Alerts.raise(player, "stove", "A pot of water is still on the " .. K.heatName(stove) .. " and Second Nature cannot take it off.", now, true)
                if state then state.kitchenNotice = "The " .. K.heatName(stove) .. " is still on with a pot of water." end
                entry.tries, entry.waitUntil = 0, now + 120000
                K.write(player, entry)
                return false
            end
            return off("Taking the pot off the " .. K.heatName(stove) .. ".")
        end
        if entry.after == "fill" then
            -- A fire left burning stays ours to put out.
            if not fire then entry.lit, entry.litHere = nil, nil end
            entry.stage, entry.walks, entry.after, entry.tries = "boil-fill", 0, nil, 0
            K.write(player, entry)
            return Boil.step(player, state, now, entry, stove)
        end
        return close(player, state, now, entry, entry.after or "done")
    end

    if entry.stage == "boil-fetch" then
        local missing = {}
        for _, wanted in ipairs(source and source.fetch or {}) do
            if not inventory:getItemById(wanted.item:getID()) then missing[#missing + 1] = wanted end
        end
        if not source then
            if not pot then return fail(player, state, now, entry, stove, "reloaded") end
        elseif #missing == 0 then
            entry.stage, entry.walks = "boil-fill", 0
            K.write(player, entry)
            return Boil.step(player, state, now, entry, stove)
        end
        local first = missing[1]
        if not first then entry.stage = "boil-fill"; K.write(player, entry); return Boil.step(player, state, now, entry, stove) end
        if not Fetch.present(first) then return fail(player, state, now, entry, stove, "gone") end
        local square = Fetch.square(first)
        -- The pot out of reach: the next largest, if there is one.
        if square and not adjacent(player, square) and first.item == source.pot and (entry.walks or 0) >= Boil.policy.tries
                and source.spares and #source.spares > 0 then
            local spare = table.remove(source.spares, 1)
            for index, wanted in ipairs(source.fetch) do if wanted == first then source.fetch[index] = spare.entry end end
            source.pot, entry.item, entry.walks = spare.item, spare.item:getID(), 0
            K.write(player, entry)
            return Boil.step(player, state, now, entry, stove)
        end
        if square and not adjacent(player, square) then
            return walkTo(player, state, now, entry, stove, square, "Going for " .. first.item:getDisplayName() .. " to boil water.")
        end
        entry.fetched = #source.fetch - #missing
        return batch(player, state, entry, "Getting what it takes to boil water.", function()
            for _, wanted in ipairs(missing) do
                if wanted.from == first.from then
                    if source.loan and wanted.item == source.pot and not source.registered then
                        local loan = P.loanFor(player, state, wanted.item)
                        if loan then loan.defer, loan.held, source.loan, source.registered = true, true, loan, true end
                    end
                    if wanted.world then Fetch.queue(player, wanted) else Supplies.transfer(player, wanted.item) end
                end
            end
        end)
    end

    if entry.stage == "boil-fill" then
        if not pot then return fail(player, state, now, entry, stove, "pot-lost") end
        local fluid = fluidOf(pot)
        if not fluid or not (fluid:isEmpty() or fluid:isPureFluid(Fluid.Water)) then return fail(player, state, now, entry, stove, "not-water") end
        -- A little over what is left to sterilize, so the last one still has its half litre.
        local need = math.min(fluid:getCapacity(), Boil.policy.liters * remaining + 0.1)
        local tap, square = tapAt(source and source.taps and source.taps[1])
        if enough(fluid:getAmount(), need) or (enough(fluid:getAmount()) and not tap) then
            entry.stage, entry.walks = "boil-place", 0
            K.write(player, entry)
            return Boil.step(player, state, now, entry, stove)
        end
        if not tap then
            -- Gone dry or gone: the next one.
            if source and source.taps and #source.taps > 1 then table.remove(source.taps, 1); return Boil.step(player, state, now, entry, stove) end
            return fail(player, state, now, entry, stove, "no-tap")
        end
        if not adjacent(player, square) then
            -- Walled off or locked away: the next tap before giving up.
            if (entry.walks or 0) >= Boil.policy.tries and #source.taps > 1 then
                table.remove(source.taps, 1)
                entry.walks = 0
                return Boil.step(player, state, now, entry, stove)
            end
            return walkTo(player, state, now, entry, stove, square, "Going to the water to fill " .. pot:getDisplayName() .. ".")
        end
        entry.before = fluid:getAmount()
        return batch(player, state, entry, "Filling " .. pot:getDisplayName() .. " to sterilize dressings.", function()
            local fill = ISTakeWaterAction:new(player, pot, tap, false)
            -- As far as the dressings left need, not to the brim.
            if fill.waterUnit then
                fill.waterUnit = math.min(fill.waterUnit, math.max(0, need - fluid:getAmount()))
                fill.maxTime = fill:getDuration()
            end
            ISTimedActionQueue.add(fill)
        end)
    end

    if not stove then return fail(player, state, now, entry, stove, "heat-gone") end

    if entry.stage == "boil-place" then
        if not pot then return fail(player, state, now, entry, stove, "pot-lost") end
        if not K.accepts(stove, pot) or (K.isOn(stove) and not K.shared(stove) and not entry.lit) or not K.canHeat(stove) then
            return fail(player, state, now, entry, stove, "heat-busy")
        end
        if not adjacent(player, stove:getSquare()) then
            return walkTo(player, state, now, entry, stove, stove:getSquare(), "Taking the water to the " .. K.heatName(stove) .. ".")
        end
        entry.placedAt = now
        -- A heat we switch on is ours to switch off, from the moment it is asked;
        -- a fire is ours only once our own light caught; one already burning is borrowed.
        if not K.fueled(stove) and not K.isOn(stove) then entry.lit = true end
        return batch(player, state, entry, "Heating water on the " .. K.heatName(stove) .. " to sterilize dressings.", function()
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player, pot, pot:getContainer(), container))
            K.toggle(player, stove, true, pot, Boil.policy.fireMinutes, entry, function()
                local current = K.ledger(player)
                if current then current.litHere = true; K.write(player, current) end
            end)
        end)
    end

    if entry.stage == "boil-heat" or entry.stage == "boil-make" then
        if not inside then return fail(player, state, now, entry, stove, "pot-lost") end
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
            -- Watching water is no reason to skip a drink: other care goes on meanwhile.
            return false
        end
        if not adjacent(player, stove:getSquare()) then return walkTo(player, state, now, entry, stove, stove:getSquare(), "Back to the hot water.") end
        local logic = Dressings.logic(player, Dressings.recipes.boil, anchor, {container})
        if not logic then return off("The water would not sterilize: the heat off, the pot away.", "cannot") end
        entry.stage, entry.anchor = "boil-make", anchor:getID()
        return batch(player, state, entry, "Sterilizing " .. anchor:getDisplayName() .. " in the hot water.", function()
            Dressings.craft(player, logic)
        end)
    end
    return false
end

-- After each batch: what the world says happened.
function Boil.settle(player, state, now, cut)
    local entry = K.ledger(player)
    if not entry then return end
    local inventory = player:getInventory()
    local stove = K.stoveAt(entry)
    -- Cut short at the heat counts; a walk the game could not path has its own count.
    if cut and Boil.hot(entry.stage) or cut and entry.stage == "boil-place" then entry.cuts = (entry.cuts or 0) + 1 end
    if entry.stage == "boil-place" then
        local inside = stove and stove:getContainer():getItemById(entry.item)
        if inside then
            local on = K.isOn(stove)
            if K.fueled(stove) then entry.lit = entry.litHere or nil
            elseif not on then entry.grace = now + 5000 end
            entry.stage, entry.tries = "boil-heat", 0
        elseif not cut then
            entry.tries = (entry.tries or 0) + 1
            if entry.tries > Boil.policy.tries then K.write(player, entry); return fail(player, state, now, entry, stove, "not-placed", true) end
        end
    elseif entry.stage == "boil-make" and entry.anchor then
        if not inventory:getItemById(entry.anchor) then entry.made = (entry.made or 0) + 1; entry.tries = 0
        elseif not cut then
            entry.tries = (entry.tries or 0) + 1
            if entry.tries > Boil.policy.tries then entry.anchor = nil; K.write(player, entry); return fail(player, state, now, entry, stove, "nothing-made", true) end
        end
        entry.anchor = nil
    elseif entry.stage == "boil-fill" and entry.before then
        local pot = inventory:getItemById(entry.item)
        local fluid = pot and fluidOf(pot)
        if not (fluid and fluid:getAmount() > entry.before) and not cut then
            entry.tries = (entry.tries or 0) + 1
            if entry.tries > Boil.policy.tries then entry.before = nil; K.write(player, entry); return fail(player, state, now, entry, stove, "not-filled", true) end
        end
        entry.before = nil
    elseif entry.stage == "boil-fetch" and entry.fetched then
        local source = sources[player]
        local count = 0
        for _, wanted in ipairs(source and source.fetch or {}) do if inventory:getItemById(wanted.item:getID()) then count = count + 1 end end
        -- Each place things were taken from is a walk of its own.
        if count > entry.fetched then entry.walks = 0 end
        if count <= entry.fetched and not cut then
            entry.tries = (entry.tries or 0) + 1
            if entry.tries > Boil.policy.tries then entry.fetched = nil; K.write(player, entry); return fail(player, state, now, entry, stove, "not-fetched", true) end
        end
        entry.fetched = nil
    elseif entry.stage == "boil-off" then
        if onHeat(entry, stove) and not cut then entry.tries = (entry.tries or 0) + 1 end
    end
    K.write(player, entry)
end

-- Autopilot stopped: the heat off and the pot away if the survivor is beside
-- it, else the ledger stays (and the kitchen's watchdog keeps saying so) until
-- the next start finishes the job. Returns what was done, for the card.
function Boil.ended(player, entry, stove)
    if not onHeat(entry, stove) then
        homeward(player)
        K.write(player, nil)
        return nil
    end
    if not stove then return "A heat with a pot of water may still be on, out of sight." end
    entry.stage, entry.after = "boil-off", "stopped"
    K.write(player, entry)
    if not adjacent(player, stove:getSquare()) or player:isDead() then
        return "The " .. K.heatName(stove) .. " is still on with a pot of water."
    end
    local container = stove:getContainer()
    local inside = container:getItemById(entry.item)
    if (entry.lit or entry.litHere) and K.isOn(stove) then K.toggle(player, stove, false) end
    if inside then ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player, inside, container, player:getInventory())) end
    -- Off the heat now: the pot goes home with the other borrowed things.
    homeward(player)
    return "Turning the " .. K.heatName(stove) .. " off and taking the water off it."
end

return Boil
