-- The kitchen: when the only food Autopilot knows needs cooking, it cooks it
-- on a powered stove, takes it out once cooked, and turns the stove off. It
-- never leaves a burner it lit unattended: the stove and the dish are written
-- down in the survivor's modData until both are dealt with.
local Log = require "AutoMindful/Log"
local Options = require "AutoMindful/Options"
local Snap = require "AutoMindful/Snapshot"
local Grid = require "AutoMindful/Grid"
local Saved = require "AutoMindful/Saved"
local Needs = require "AutoMindful/SurvivalNeeds"
local Fluids = require "AutoMindful/Fluids"
local Diet = require "AutoMindful/Diet"
local Progress = require "AutoMindful/Progress"
local Soup = require "AutoMindful/Soup"
local Alerts = require "AutoMindful/Alerts"

local Kitchen = {policy = {radius = 10, lookMs = 30000, retryMs = 600000, attempts = 3, burnShare = 0.8, againMs = 120000,
    batch = 4, soonHours = 72, practiceMs = 60000, tired = 0.5,
    unwatchedMs = 15000, warnMs = 60000}}
local watched, warned = {}, {}
local P

-- What the kitchen will not try again for a while. Its own: the controller's
-- rejected list also keeps food from being eaten, which a failed cook must not do.
local function skip(state)
    state.kitchenSkip = state.kitchenSkip or {}
    return state.kitchenSkip
end

function Kitchen.bind(parts)
    P = parts
    Soup.bind({write = function(player, entry) Kitchen.write(player, entry) end, ledger = Kitchen.ledger, heatKind = Kitchen.heatKind,
        place = function(...) return Kitchen.place(...) end}, parts)
end

-- ------------------------------------------------------------------ the food

-- Raw now, safe to eat once cooked. Never rotten, burnt, frozen or poisoned:
-- cooking does not make those safe.
function Kitchen.cookable(item)
    if not item or not instanceof(item, "Food") or not item:isCookable() or item:isCooked() or item:isBurnt() then return false end
    if item:isFrozen() or not Fluids.harmless(item) or Grid.favorite(item) then return false end
    -- Stricter than eating: any eating effect at all, even the stock wild-food one, is left raw.
    local effect = item:getOnEat()
    if effect and effect ~= "" then return false end
    -- Bread that turns into toast becomes a new item, which could not be followed in the stove.
    local replaced = item.getReplaceOnCooked and item:getReplaceOnCooked()
    if replaced and (type(replaced) == "string" and replaced ~= "" or type(replaced) ~= "string" and replaced.size and replaced:size() > 0) then
        return false
    end
    return item:getHungerChange() < 0
end

local function relief(item) return -item:getHungerChange() end


-- ----------------------------------------------------------------- the stove

-- What can cook. Each kind says whether it is on, whether it can heat (power,
-- propane) and which of the game's actions switches it. Microwaves are left
-- out: they run on a timer and did not cook raw food in testing; coffee
-- machines and fryers are IsoStoves too.
local heats = {
    {kind = "stove", name = "stove",
        match = function(object) return instanceof(object, "IsoStove") and object:getContainer() ~= nil
            and object:getContainer():getType() == "stove" end,
        on = function(object) return object:Activated() end,
        ready = function(object) return object:getContainer():isPowered() end,
        action = function(player, object) return ISToggleStoveAction:new(player, object) end},
    {kind = "grill", name = "grill",
        match = function(object) return instanceof(object, "IsoBarbecue") and object:isPropaneBBQ() and object:getContainer() ~= nil end,
        -- Out of propane it cannot heat and cannot be switched: off, in effect.
        on = function(object) return object:isLit() and object:hasFuel() end,
        ready = function(object) return object:hasFuel() end,
        action = function(player, object) return ISBBQToggle:new(player, object) end},
}

local function heatOf(object)
    if not object then return nil end
    for _, heat in ipairs(heats) do
        local ok, matched = pcall(heat.match, object)
        if ok and matched then return heat end
    end
    return nil
end

function Kitchen.isStove(object) return heatOf(object) ~= nil end
function Kitchen.heatKind(object) local heat = heatOf(object); return heat and heat.kind or nil end
-- Gone or replaced since it was found: neither on nor able to heat.
local function isOn(object) local heat = heatOf(object); return heat ~= nil and heat.on(object) == true end
local function canHeat(object) local heat = heatOf(object); return heat ~= nil and heat.ready(object) == true end
Kitchen.heatName = function(object) local heat = heatOf(object); return heat and heat.name or "stove" end

local function stoveKey(object) return Grid.key(object:getSquare()) end
Kitchen.key = stoveKey

-- Nothing of anyone else's is cooking in it.
local function free(container)
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        if instanceof(items:get(index), "Food") then return false end
    end
    return true
end

-- One pass over the squares nearby: stoves that could cook now, raw food in the
-- containers around them, and powered fridges. fridgesOnly skips the food.
function Kitchen.scan(player, rejected, now, fridgesOnly)
    -- heats: every stove or grill seen, on or off, busy or not.
    local result = {stoves = {}, food = {}, fridges = {}, pots = {}, taps = {}, ready = 0, heats = 0}
    if not player:getSquare() then return result end
    local seen = {}
    local function take(container, carried)
        if fridgesOnly or not container or seen[container] then return end
        seen[container] = true
        local items = container:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if Kitchen.cookable(item) and not (rejected and rejected[item:getID()] and now < rejected[item:getID()]) then
                result.food[#result.food + 1] = {item = item, container = container, carried = carried}
            elseif instanceof(item, "Food") and Fluids.safeFood(item) and item:getHungerChange() <= -0.05
                    and not item:getOpeningRecipe() and not Grid.favorite(item) then
                -- Ready to eat as it is: cooked food, leftovers, tins.
                result.ready = result.ready + 1
            elseif Soup.isPot(item) then
                result.pots[#result.pots + 1] = {item = item, container = container, carried = carried}
            elseif carried and instanceof(item, "InventoryContainer") then
                take(item:getInventory(), true)
            end
        end
    end
    take(player:getInventory(), true)
    local home = player:getSquare():getBuilding()
    Grid.around(player, Kitchen.policy.radius, function(square, dx, dy)
        local distance = dx * dx + dy * dy
        -- From indoors the yard is only for a grill: food, fridges and taps stay inside.
        local yard = home ~= nil and square:getBuilding() == nil
        local objects = square:getObjects()
        for index = 0, objects:size() - 1 do
            local object = objects:get(index)
            local outside = yard and not heatOf(object)
            if not outside and not fridgesOnly and Soup.isTap(object) then
                result.taps[#result.taps + 1] = {object = object, square = square, distance = distance}
            end
            if heatOf(object) then result.heats = result.heats + 1 end
            if outside then
                -- nothing but heat out there
            elseif Kitchen.isStove(object) then
                local container = object:getContainer()
                local waiting = rejected and rejected["stove:" .. stoveKey(object)]
                if not fridgesOnly and canHeat(object) and not isOn(object) and free(container)
                        and not (waiting and now < waiting) then
                    result.stoves[#result.stoves + 1] = {object = object, square = square, distance = distance,
                        rank = heatOf(object).kind == "stove" and 0 or 1}
                end
            elseif object.getContainerCount then
                for c = 0, object:getContainerCount() - 1 do
                    local container = object:getContainerByIndex(c)
                    if container and container:getType() ~= "stove" then
                        take(container, false)
                        if container:getType() == "fridge" and container:isPowered() then
                            result.fridges[#result.fridges + 1] = {container = container, square = square, distance = distance}
                        end
                    end
                end
            end
        end
    end, true)
    -- A stove indoors before a grill outside, then the nearest.
    table.sort(result.stoves, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.distance < b.distance
    end)
    table.sort(result.fridges, function(a, b) return a.distance < b.distance end)
    table.sort(result.taps, function(a, b) return a.distance < b.distance end)
    -- A pot already carried first.
    table.sort(result.pots, function(a, b) return (a.carried and 1 or 0) > (b.carried and 1 or 0) end)
    return result
end

-- What to cook: what is already carried first, then whatever spoils soonest,
-- and enough of it to matter.
function Kitchen.choose(food, player)
    local best, score
    for _, entry in ipairs(food) do
        local item = entry.item
        local hoursLeft = math.max(0, item:getOffAge() - item:getAge()) * 24
        -- The diet goal scales the relief, so it never beats a much more filling dish.
        local value = Diet.adjust(player, relief(item) * 100, item) - math.min(hoursLeft, 240) / 10 + (entry.carried and 20 or 0)
        if not score or value > score then best, score = entry, value end
    end
    return best
end

local function hoursLeft(item) return math.max(0, item:getOffAge() - item:getAge()) * 24 end
-- Hours until it rots, not just goes stale.
local function rotHours(item) return math.max(0, item:getOffAgeMax() - item:getAge()) * 24 end

-- Cooked together with the main dish: from the same place, done at about the
-- same time, and better cooked now than left to spoil.
function Kitchen.companions(main, food, limit)
    local list = {}
    local minutes = main.item:getMinutesToCook()
    for _, entry in ipairs(food) do
        local item = entry.item
        if #list >= limit then break end
        if item ~= main.item and (entry.container == main.container or (entry.carried and main.carried))
                and item:getMinutesToCook() <= minutes * 1.5 + 5 and item:getMinutesToBurn() >= minutes
                and hoursLeft(item) <= Kitchen.policy.soonHours then
            list[#list + 1] = entry
        end
    end
    return list
end

-- ------------------------------------------------------------------- ledger

-- The stove a survivor lit and what is in it, kept across saves and Stop.
function Kitchen.ledger(player) return player:getModData().AutoMindfulKitchen end

local function write(player, entry) Saved.set(player, "AutoMindfulKitchen", entry) end
Kitchen.write = write

local function stoveAt(entry)
    local square = entry and getCell():getGridSquare(entry.x, entry.y, entry.z)
    if not square or not square.getObjects then return nil end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local heat = heatOf(object)
        -- The kind it lit, when a square holds more than one.
        if heat and (entry.heat == nil or entry.heat == heat.kind) then return object end
    end
    return nil
end
Kitchen.stoveAt = stoveAt

local function ids(entry) return entry.items or {entry.item} end

local function dishesIn(stove, entry)
    local list = {}
    if not stove or not entry then return list end
    local container = stove:getContainer()
    for _, id in ipairs(ids(entry)) do
        local item = container:getItemById(id)
        if item then list[#list + 1] = item end
    end
    return list
end

local function dishIn(stove, entry) return dishesIn(stove, entry)[1] end

-- Food in the stove that is not this survivor's.
local function others(container, entry)
    local mine = {}
    for _, id in ipairs(entry and ids(entry) or {}) do mine[id] = true end
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if instanceof(item, "Food") and not mine[item:getID()] then return true end
    end
    return false
end

local function adjacent(player, square) return Grid.adjacent(player:getSquare(), square) end

-- A toggle that only ever moves the stove the way it was meant to: someone
-- else may have switched it in the meantime.
local function toggle(player, stove, on, dish)
    local action = heatOf(stove).action(player, stove)
    local valid = action.isValid
    function action:isValid()
        local object = stove
        if not valid(self) or isOn(object) == on then return false end
        -- Lit only for our own dish, in a stove that still has power.
        return not on or (canHeat(object) and (not dish or object:getContainer():contains(dish)))
    end
    ISTimedActionQueue.add(action)
end

local function transfer(player, item, from, to)
    local action = ISInventoryTransferUtil.newInventoryTransferAction(player, item, from, to)
    ISTimedActionQueue.add(action)
    return action
end

-- ------------------------------------------------------------------ cooking

local function progress(dish)
    local cook = dish:getMinutesToCook()
    return cook > 0 and math.min(1, dish:getCookingTime() / cook) or 0
end

local function nearBurning(dish)
    local burn = dish:getMinutesToBurn()
    return dish:isBurnt() or (burn > 0 and dish:getCookingTime() >= burn * Kitchen.policy.burnShare)
end

local function giveUp(player, state, entry, now, why)
    skip(state)["stove:" .. entry.x .. ":" .. entry.y .. ":" .. entry.z] = now + Kitchen.policy.retryMs
    Log.event(player, "kitchen.giveup", "why", why, "stove", entry.x .. ":" .. entry.y)
end

-- Take the dish out and switch off, from beside the stove.
local function finish(player, state, entry, stove, take, all, message)
    entry.stage, entry.taking, entry.all = "finishing", {}, all or nil
    entry.cooked = entry.cooked or {}
    for _, dish in ipairs(take) do
        entry.taking[#entry.taking + 1] = dish:getID()
        local id = dish:getID()
        local fetched = entry.fetched and entry.fetched[tostring(id)]
        local known = false
        for _, seen in ipairs(entry.cooked) do known = known or seen == id end
        -- Only what came out of a fridge or cupboard goes back cold; what was carried stays carried.
        if fetched and not known and dish:isCooked() and not dish:isBurnt() then entry.cooked[#entry.cooked + 1] = id end
    end
    write(player, entry)
    return P.ownBatch(player, state, "kitchen", message, function()
        if not adjacent(player, stove:getSquare()) and not luautils.walkAdj(player, stove:getSquare(), true) then return end
        if all and isOn(stove) then toggle(player, stove, false) end
        for _, dish in ipairs(take) do transfer(player, dish, stove:getContainer(), player:getInventory()) end
    end)
end

-- Looks after a dish already on the stove. Safe to call when nothing is.
-- walk: false while zombies are about, when only what needs no steps is done.
function Kitchen.duty(player, state, now, walk)
    local entry = Kitchen.ledger(player)
    if not entry then return false end
    local stove = stoveAt(entry)
    if not stove then
        -- Nothing lit yet and no stove any more: the plan is over.
        if not entry.lit and state and (entry.stage ~= "cooking" and entry.stage ~= "finishing") then
            if Soup.handles(entry.stage) then return Soup.abandon(player, state, now, entry, "stove-gone") end
            write(player, nil)
            return false
        end
        -- Too far to see. The stove is only ever left on beside the survivor.
        if state then state.kitchenNotice = "The stove that was cooking is out of sight." end
        return false
    end
    watched[player] = now
    if entry.stage == "fetching" then
        if state and state.pending then return false end
        Kitchen.settle(player, state, now, true)
        entry = Kitchen.ledger(player)
        if not entry then return false end
    end
    if entry.stage == "ready" then return Kitchen.place(player, state, now, entry, stove) end
    if Soup.handles(entry.stage) then
        if state and state.pending then return false end
        return Soup.step(player, state, now, entry, stove)
    end
    local present = dishesIn(stove, entry)
    local dish = present[1]
    local on = isOn(stove)
    if not dish and on and not entry.lit then
        -- Lit by someone else: theirs, not ours.
        write(player, nil)
        Alerts.clear(player, "stove")
        Log.event(player, "kitchen.released", "stove", entry.x .. ":" .. entry.y, "lit", entry.lit)
        return false
    end
    if not dish and not on then
        Alerts.clear(player, "stove")
        if entry.cooked and #entry.cooked > 0 then
            -- Added to what is still waiting for the fridge, never in its place.
            local list, seen = {}, {}
            for _, id in ipairs(player:getModData().AutoMindfulLeftovers or {}) do list[#list + 1], seen[id] = id, true end
            for _, id in ipairs(entry.cooked) do if not seen[id] then list[#list + 1] = id end end
            Saved.set(player, "AutoMindfulLeftovers", list)
        end
        write(player, nil)
        if state then state.kitchenNotice = nil end
        Log.event(player, "kitchen.done", "stove", entry.x .. ":" .. entry.y)
        return false
    end
    if not state or not state.active then return false end
    -- Each dish comes out when it is cooked, or before it burns; the stove goes
    -- off with the last one.
    local ready, burning, slowest = {}, false, nil
    for _, item in ipairs(present) do
        local hot = nearBurning(item)
        burning = burning or hot
        if item:isCooked() or hot then ready[#ready + 1] = item
        elseif not slowest or progress(item) < progress(slowest) then slowest = item end
    end
    local done = dish ~= nil and #ready == #present
    local unpowered = not canHeat(stove)
    local blocked = (entry.tries or 0) >= Kitchen.policy.attempts
    local all = not dish or done or unpowered or not on
    -- Cut short again and again (danger, the player): after a few, it counts as stuck.
    blocked = blocked or (entry.cuts or 0) >= Kitchen.policy.attempts * 2
    if all or #ready > 0 or blocked then
        if blocked then
            -- Beside it, at least the heat goes off.
            if on and adjacent(player, stove:getSquare()) and walk ~= false then
                P.ownBatch(player, state, "kitchen", "Turning the " .. Kitchen.heatName(stove) .. " off.", function() toggle(player, stove, false) end)
            end
            state.kitchenNotice = "The " .. Kitchen.heatName(stove) .. " is still on. Second Nature could not reach it."
            Alerts.raise(player, "stove", "The stove is still on and Second Nature cannot reach it.", now, true)
            entry.blockedAt = entry.blockedAt or now
            if now < entry.blockedAt or now - entry.blockedAt >= Kitchen.policy.againMs then
                entry.tries, entry.cuts, entry.blockedAt = 0, 0, nil
                write(player, entry)
            end
            return false
        end
        if walk == false and not adjacent(player, stove:getSquare()) then
            state.kitchenNotice = "The " .. Kitchen.heatName(stove) .. " is on. It will be turned off once it is safe to walk."
            return false
        end
        local take = all and present or ready
        local first = take[1]
        local name = first and (first:getDisplayName() .. (#take > 1 and (" and " .. (#take - 1) .. " more") or "")) or "the stove"
        local cooked = first ~= nil
        for _, item in ipairs(take) do cooked = cooked and item:isCooked() and not nearBurning(item) end
        burning = first and nearBurning(first)
        local heatName = Kitchen.heatName(stove)
        local message = not dish and ("Turning the " .. heatName .. " off.") or cooked and ("Taking " .. name .. " out. Cooked.")
            or burning and ("Taking " .. name .. " out before it burns.")
            or unpowered and ((heatName == "grill" and "The propane ran out. Taking " or "The power went off. Taking ") .. name .. " out.")
            or ("The " .. heatName .. " went off. Taking " .. name .. " out.")
        if (unpowered or not on) and not cooked then giveUp(player, state, entry, now, "stove-off") end
        Log.event(player, "kitchen.finish", "dish", first and Snap.item(first), "count", #take, "cooked", cooked, "burning", burning,
            "unpowered", unpowered, "on", on)
        return finish(player, state, entry, stove, take, all, message)
    end
    entry.stage, entry.tries = "cooking", 0
    local share = math.floor(progress(slowest) * 100)
    state.kitchenNotice = nil
    local name = slowest:getDisplayName() .. (#present > 1 and (" and " .. (#present - 1) .. " more") or "")
    -- Stay near the stove; the dishes need taking out on time.
    P.setPhase(state, "kitchen-watch", "Cooking " .. name .. ": " .. share .. "%. Staying near the " .. Kitchen.heatName(stove) .. ".")
    return true
end

-- A stove this survivor lit is still on, or cannot be seen to be off.
function Kitchen.lit(player)
    local entry = Kitchen.ledger(player)
    if not entry then return false end
    local stove = stoveAt(entry)
    local stage = entry.stage
    return stove ~= nil and isOn(stove) and (stage == "starting" or stage == "cooking" or stage == "finishing")
end

-- Something on the stove needs a hand now, not just watching.
function Kitchen.urgent(player)
    local entry = Kitchen.ledger(player)
    if not entry or entry.stage ~= "cooking" and entry.stage ~= "finishing" then return false end
    local stove = stoveAt(entry)
    if not stove then return false end
    local present = dishesIn(stove, entry)
    if #present == 0 or not canHeat(stove) or not isOn(stove) then return true end
    for _, dish in ipairs(present) do
        if dish:isCooked() or nearBurning(dish) then return true end
    end
    return false
end

-- Starts a meal when hunger is due and nothing ready to eat is known.
-- Hungry, but not yet badly, and not thirsty: cook what can be cooked rather
-- than eat it raw. Runs before ordinary eating; when nothing can be cooked,
-- eating goes on as usual.
function Kitchen.prefer(player, state, now)
    local entry = Kitchen.ledger(player)
    if entry then
        -- A plan under way goes on before anything is eaten, unless hunger presses:
        -- otherwise its ingredients would be eaten raw between the steps.
        if entry.stage ~= "cooking" and entry.stage ~= "finishing" and not Needs.pressing(player, "food") then
            return Kitchen.duty(player, state, now, true)
        end
        return false
    end
    if not Options.cookMeals() or not Needs.due(player, "food") or Needs.pressing(player, "food") or Needs.due(player, "water")
            or Needs.lowHealth(player) or P.stat(player, "FATIGUE") >= Kitchen.policy.tired then return false end
    -- Its own timer: a look that found nothing must not hold up the real meal.
    if state.preferNext and now < state.preferNext and state.preferNext - now <= Kitchen.policy.lookMs then return false end
    state.preferNext = now + Kitchen.policy.lookMs
    return Kitchen.meal(player, state, now, true)
end

function Kitchen.meal(player, state, now, preferring)
    if Kitchen.ledger(player) then return Kitchen.duty(player, state, now, true) end
    if not Options.cookMeals() or not Needs.due(player, "food") then return false end
    if not preferring then
        if state.kitchenNext and now < state.kitchenNext and state.kitchenNext - now <= Kitchen.policy.lookMs then return false end
        state.kitchenNext = now + Kitchen.policy.lookMs
    end
    if not preferring and P.available(player, state, "food") then return false end
    local found = Kitchen.scan(player, skip(state), now)
    -- Leftovers and ready meals are eaten before anything new is cooked.
    if preferring and found.ready > 0 then return false end
    local entry, stove = Kitchen.choose(found.food, player), found.stoves[1]
    Log.event(player, "kitchen.look", "raw", #found.food, "stoves", #found.stoves, "diet", Diet.goal(player),
        "chosen", entry and Snap.item(entry.item))
    if not entry then
        state.kitchenNotice = nil
        return false
    end
    if not stove then
        if not preferring then state.kitchenNotice = "Only raw food is left, and there is no powered stove or propane grill nearby." end
        return false
    end
    state.kitchenNotice = nil
    return Kitchen.cook(player, state, now, entry, stove, found.food, "meal", found)
end

-- Cooking practice: when nobody is hungry, raw food from the cupboards is cooked
-- for Cooking XP and put back cold. "spoiling" takes only what would spoil
-- within three days; "all" any spare raw food. What is carried stays carried.
function Kitchen.practice(player, state, now)
    local mode = Options.cookTraining()
    if mode == "off" or not Options.cookMeals() or Kitchen.ledger(player) or Needs.due(player, "food") then return false end
    -- Practice waits for a rested, watered survivor: a lit stove holds up sleep and trips for water.
    if Needs.due(player, "water") or P.stat(player, "FATIGUE") >= Kitchen.policy.tired then return false end
    -- At level 10 there is nothing left to learn.
    local skill = Progress.perk(player, Perks and Perks.Cooking)
    if skill and skill.capped then return false end
    if state.practiceNext and now < state.practiceNext and state.practiceNext - now <= Kitchen.policy.practiceMs then return false end
    state.practiceNext = now + Kitchen.policy.practiceMs
    local found = Kitchen.scan(player, skip(state), now)
    local pool = {}
    for _, entry in ipairs(found.food) do
        if not entry.carried and (mode == "all" or rotHours(entry.item) <= Kitchen.policy.soonHours) then pool[#pool + 1] = entry end
    end
    local entry, stove = Kitchen.choose(pool, player), found.stoves[1]
    -- The cooked food needs somewhere cold to go back to.
    local fridge = found.fridges[1]
    local cold = fridge and entry and fridge.container:hasRoomFor(player, entry.item)
    Log.event(player, "kitchen.practice", "mode", mode, "raw", #pool, "stoves", #found.stoves, "fridge", cold == true,
        "chosen", entry and Snap.item(entry.item))
    if not entry or not stove or not cold then return false end
    return Kitchen.cook(player, state, now, entry, stove, pool, "practice", found)
end

-- Puts the chosen dish and what goes with it on the stove: from a fridge
-- first, then to the stove from wherever that leaves the survivor.
function Kitchen.cook(player, state, now, entry, stove, pool, reason, found)
    -- With a pot, water and two ingredients from one place: a soup or a stew.
    if found and Options.makeSoup() and Soup.start(player, state, now, entry, pool, stove, found, reason) then return true end
    local item, object = entry.item, stove.object
    local inventory = player:getInventory()
    if not entry.carried and not inventory:hasRoomFor(player, item) then
        skip(state)[item:getID()] = now + Kitchen.policy.retryMs
        return false
    end
    -- What spoils soon and cooks in about the same time goes in alongside.
    local batch, weight = {entry}, item:getActualWeight()
    for _, extra in ipairs(Kitchen.companions(entry, pool, Kitchen.policy.batch - 1)) do
        local extraWeight = extra.item:getActualWeight()
        if object:getContainer():hasRoomFor(player, weight + extraWeight)
                and (extra.carried or inventory:hasRoomFor(player, weight + extraWeight)) then
            batch[#batch + 1], weight = extra, weight + extraWeight
        end
    end
    local list, fetched = {}, {}
    for _, chosen in ipairs(batch) do
        list[#list + 1] = chosen.item:getID()
        if not chosen.carried then fetched[tostring(chosen.item:getID())] = true end
    end
    local square = object:getSquare()
    local record = {x = square:getX(), y = square:getY(), z = square:getZ(), heat = heatOf(object).kind, item = item:getID(), items = list,
        name = item:getDisplayName() .. (#list > 1 and (" and " .. (#list - 1) .. " more") or ""), fetched = fetched,
        tries = 0, stage = entry.carried and "ready" or "fetching", reason = reason}
    write(player, record)
    Log.event(player, "kitchen.start", "reason", reason, "dish", Snap.item(item), "count", #list, "stove", stoveKey(object), "carried", entry.carried,
        "temperature", object.getMaxTemperature and object:getMaxTemperature() or nil)
    if entry.carried then return Kitchen.place(player, state, now, record, object) end
    -- First the fridge, then, from wherever that leaves the survivor, the stove.
    local queued = P.ownBatch(player, state, "kitchen", "Getting " .. record.name .. " to cook.", function()
        local from = Grid.containerSquare(entry.container)
        if from and not adjacent(player, from) and not luautils.walkAdj(player, from, true) then return end
        for _, chosen in ipairs(batch) do
            if not chosen.carried then transfer(player, chosen.item, chosen.container, inventory) end
        end
    end)
    if not queued then
        write(player, nil)
        skip(state)[item:getID()] = now + Kitchen.policy.retryMs
        state.pending = nil
    end
    return queued
end

-- The dish is carried: to the stove with it, in, and on.
function Kitchen.place(player, state, now, entry, object)
    local inventory = player:getInventory()
    local item = inventory:getItemById(entry.item)
    local carried, list = {}, {}
    for _, id in ipairs(ids(entry)) do
        local found = inventory:getItemById(id)
        if found and Kitchen.cookable(found) then carried[#carried + 1] = found; list[#list + 1] = id end
    end
    entry.items = list
    item = item and Kitchen.cookable(item) and item or carried[1]
    if item then entry.item = item:getID() end
    local container = object and object:getContainer()
    if not item or not container or isOn(object) or not canHeat(object)
            or others(container, entry) then
        write(player, nil)
        if item then skip(state)[item:getID()] = now + Kitchen.policy.retryMs end
        skip(state)["stove:" .. entry.x .. ":" .. entry.y .. ":" .. entry.z] = now + Kitchen.policy.lookMs
        Log.event(player, "kitchen.unplaced", "carried", item ~= nil, "stove", entry.x .. ":" .. entry.y)
        return false
    end
    entry.stage = "starting"
    write(player, entry)
    local square = object:getSquare()
    local queued = P.ownBatch(player, state, "kitchen", "Cooking " .. (entry.name or item:getDisplayName()) .. " on the " .. Kitchen.heatName(object) .. ".", function()
        if not adjacent(player, square) and not luautils.walkAdj(player, square, true) then return end
        for _, dish in ipairs(carried) do
            local into = transfer(player, dish, dish:getContainer(), container)
            local valid = into.isValid
            function into:isValid()
                -- Someone else may have started cooking here in the meantime.
                return (not valid or valid(self)) and not isOn(object) and canHeat(object) and not others(container, entry)
            end
        end
        toggle(player, object, true, item)
    end)
    if not queued then
        write(player, nil)
        skip(state)[item:getID()] = now + Kitchen.policy.retryMs
        state.pending = nil
    end
    return queued
end

-- The batch is over. The world says what happened, not how the actions ended.
-- cut: an action was stopped (danger, the player), which is no failed try.
function Kitchen.settle(player, state, now, cut)
    local entry = Kitchen.ledger(player)
    if not entry then return end
    if Soup.handles(entry.stage) then return Soup.settle(player, state, now, cut) end
    local stove = stoveAt(entry)
    local dish = dishIn(stove, entry)
    if entry.stage == "fetching" then
        local fetched = false
        for _, id in ipairs(ids(entry)) do fetched = fetched or player:getInventory():getItemById(id) ~= nil end
        if fetched then
            entry.stage = "ready"
            write(player, entry)
        else
            -- Practice is never worth a second try at the same food soon; a meal may be.
            if not cut or entry.reason == "practice" then skip(state)[entry.item] = now + Kitchen.policy.retryMs end
            write(player, nil)
        end
    elseif entry.stage == "starting" then
        local on = stove and isOn(stove)
        if dish then
            -- In the stove. Lit by us, or about to be taken out again.
            entry.stage, entry.lit = "cooking", on and true or nil
            write(player, entry)
        else
            -- Never reached the stove, or someone else lit it first: nothing of ours to clean up.
            if not cut then skip(state)[entry.item] = now + Kitchen.policy.retryMs end
            write(player, nil)
        end
    elseif entry.stage == "finishing" then
        local left = false
        local container = stove and stove:getContainer()
        -- A ledger saved before batches has no list: everything was being taken out.
        local all = entry.all or not entry.taking
        for _, id in ipairs(entry.taking or ids(entry)) do left = left or (container and container:getItemById(id) ~= nil) end
        if all and stove and isOn(stove) then left = true end
        if left and cut then entry.cuts = (entry.cuts or 0) + 1
        elseif left then entry.tries = (entry.tries or 0) + 1
        else entry.stage, entry.tries, entry.cuts = "cooking", 0, 0 end
        entry.taking, entry.all = nil, nil
        write(player, entry)
    end
end

-- Cooked food that was not eaten goes into a powered fridge nearby, where it
-- keeps, instead of spoiling in a pocket.
function Kitchen.store(player, state, now)
    local data = player:getModData()
    local list = data.AutoMindfulLeftovers
    if not list or Kitchen.ledger(player) or Needs.due(player, "food") or not Options.cookMeals() then return false end
    local inventory, items = player:getInventory(), {}
    for _, id in ipairs(list) do
        local item = inventory:getItemById(id)
        if item and instanceof(item, "Food") and item:isCooked() and not item:isRotten() and not item:isBurnt()
                and not Grid.favorite(item) then items[#items + 1] = item end
    end
    if #items == 0 then Saved.set(player, "AutoMindfulLeftovers", nil); return false end
    if state.storeNext and now < state.storeNext and state.storeNext - now <= Kitchen.policy.lookMs then return false end
    state.storeNext = now + Kitchen.policy.lookMs
    local fridge
    for _, candidate in ipairs(Kitchen.scan(player, nil, now, true).fridges) do
        if candidate.container:hasRoomFor(player, items[1]) then fridge = candidate; break end
    end
    if not fridge then return false end
    local square = fridge.square
    Log.event(player, "kitchen.store", "count", #items, "fridge", square:getX() .. ":" .. square:getY())
    local queued = P.ownBatch(player, state, "kitchen", "Putting the leftovers in the fridge.", function()
        if not adjacent(player, square) and not luautils.walkAdj(player, square, true) then return end
        for _, item in ipairs(items) do
            local into = transfer(player, item, item:getContainer(), fridge.container)
            local valid = into.isValid
            function into:isValid()
                return (not valid or valid(self)) and fridge.container:isPowered() and fridge.container:hasRoomFor(player, item)
            end
        end
    end)
    if queued then Saved.set(player, "AutoMindfulLeftovers", nil) else state.pending = nil end
    return queued
end

-- Stop, death or a switch: the stove is not left burning if it can be helped.
function Kitchen.ended(player)
    local entry = Kitchen.ledger(player)
    if not entry then return nil end
    local stove = stoveAt(entry)
    if entry.stage == "fetching" or entry.stage == "ready" or Soup.handles(entry.stage) then write(player, nil); return nil end
    if not stove or not isOn(stove) or not entry.lit then return nil end
    if adjacent(player, stove:getSquare()) and not player:isDead() then
        toggle(player, stove, false)
        for _, dish in ipairs(dishesIn(stove, entry)) do transfer(player, dish, stove:getContainer(), player:getInventory()) end
        return "Turning the " .. Kitchen.heatName(stove) .. " off."
    end
    return "The " .. Kitchen.heatName(stove) .. " is still on" .. (entry.name and (" with " .. entry.name .. " inside") or "") .. "."
end

-- Nobody minding a lit stove: Stop far away, a load without Autopilot, a
-- cancelled toggle, or the player busy elsewhere. Say so; never act unasked.
function Kitchen.watchdog(player, now)
    local entry = Kitchen.ledger(player)
    if not entry or player:isDead() then return end
    if watched[player] and now >= watched[player] and now - watched[player] < Kitchen.policy.unwatchedMs then return end
    if warned[player] and now >= warned[player] and now - warned[player] < Kitchen.policy.warnMs then return end
    if not entry.lit then return end
    local stove = stoveAt(entry)
    if stove and not isOn(stove) then return end
    local dish = dishIn(stove, entry)
    local heatName = stove and Kitchen.heatName(stove) or "stove"
    local detail = dish and nearBurning(dish) and (dish:getDisplayName() .. " is about to burn on the " .. heatName .. ".")
        or ("The " .. heatName .. " is on" .. (entry.name and (" with " .. entry.name .. " inside") or "") .. " and nothing is watching it.")
    warned[player] = now
    Log.headline(player, "kitchen.unwatched", "detail", detail)
    Alerts.notice(player, "Kitchen", detail)
end

if Events and Events.EveryOneMinute then
    Events.EveryOneMinute.Add(function()
        local now = getTimestampMs()
        for index = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(index)
            if player then pcall(Kitchen.watchdog, player, now) end
        end
    end)
end

function Kitchen.status(player, state)
    local entry = Kitchen.ledger(player)
    local notice = state and state.kitchenNotice
    if not entry then return notice and {notice = notice} or nil end
    local stove = stoveAt(entry)
    -- The slowest dish still in the stove says how long is left.
    local slowest
    local present = dishesIn(stove, entry)
    for _, dish in ipairs(present) do
        if not slowest or progress(dish) < progress(slowest) then slowest = dish end
    end
    local name = slowest and (slowest:getDisplayName() .. (#present > 1 and (" and " .. (#present - 1) .. " more") or "")) or entry.name
    return {dish = name, progress = slowest and progress(slowest) or nil, notice = notice,
        on = stove and isOn(stove) and canHeat(stove) or nil}
end

return Kitchen
