-- The kitchen: when the only food Autopilot knows needs cooking, it cooks it
-- on a powered stove, takes it out once cooked, and turns the stove off. It
-- never leaves a burner it lit unattended: the stove and the dish are written
-- down in the survivor's modData until both are dealt with.
local Log = require "AutoMindful/Log"
local Options = require "AutoMindful/Options"
local Snap = require "AutoMindful/Snapshot"
local Storage = require "AutoMindful/Storage"
local Needs = require "AutoMindful/SurvivalNeeds"
local Alerts = require "AutoMindful/Alerts"
local HUD = require "AutoMindful/CompletionHUD"

local Kitchen = {policy = {radius = 10, lookMs = 30000, retryMs = 600000, attempts = 3, burnShare = 0.8, againMs = 120000,
    unwatchedMs = 15000, warnMs = 60000}}
local watched, warned = {}, {}
local P

function Kitchen.bind(parts) P = parts end

-- ------------------------------------------------------------------ the food

-- Raw now, safe to eat once cooked. Never rotten, burnt, frozen or poisoned:
-- cooking does not make those safe.
function Kitchen.cookable(item)
    if not item or not instanceof(item, "Food") or not item:isCookable() or item:isCooked() or item:isBurnt() then return false end
    if item:isFrozen() or item:isRotten() or item:isTainted() or item:isPoison() or item:getPoisonPower() > 0 then return false end
    if item:getAge() >= item:getOffAgeMax() or item:isAlcoholic() or item:getFoodSicknessChange() > 0 then return false end
    local effect = item:getOnEat()
    if effect and effect ~= "" then return false end
    if item.isFavorite and item:isFavorite() then return false end
    return item:getHungerChange() < 0
end

local function relief(item) return -item:getHungerChange() end

local function squareOf(container)
    local square = container:getSourceGrid()
    if square then return square end
    local holder = container:getContainingItem()
    local world = holder and holder:getWorldItem()
    return world and world:getSquare()
end

-- ----------------------------------------------------------------- the stove

-- Ovens and ranges only: coffee machines, fryers and microwaves are IsoStoves
-- too, and a microwave sets fire to anything metal.
function Kitchen.isStove(object)
    if not object or not instanceof(object, "IsoStove") then return false end
    local container = object:getContainer()
    return container ~= nil and container:getType() == "stove"
end

local function stoveKey(object)
    local square = object:getSquare()
    return square:getX() .. ":" .. square:getY() .. ":" .. square:getZ()
end
Kitchen.key = stoveKey

-- Nothing of anyone else's is cooking in it.
local function free(container)
    local items = container:getItems()
    for index = 0, items:size() - 1 do
        if instanceof(items:get(index), "Food") then return false end
    end
    return true
end

local function within(here, square, radius)
    if not square or square:getZ() ~= here:getZ() then return false end
    local dx, dy = square:getX() - here:getX(), square:getY() - here:getY()
    if dx * dx + dy * dy > radius * radius then return false end
    -- Indoors, the same building: nobody crosses the street to cook.
    local building = here.getBuilding and here:getBuilding()
    return building == nil or (square.getBuilding and square:getBuilding()) == building
end

-- One pass over the squares nearby: stoves that could cook now, and raw food
-- in the containers around them.
function Kitchen.scan(player, rejected, now)
    local here = player:getSquare()
    local result = {stoves = {}, food = {}}
    if not here then return result end
    local radius = Kitchen.policy.radius
    local seen = {}
    local function take(container, carried)
        if not container or seen[container] then return end
        seen[container] = true
        local items = container:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if Kitchen.cookable(item) and not (rejected and rejected[item:getID()] and now < rejected[item:getID()]) then
                result.food[#result.food + 1] = {item = item, container = container, carried = carried}
            elseif carried and instanceof(item, "InventoryContainer") then
                take(item:getInventory(), true)
            end
        end
    end
    take(player:getInventory(), true)
    local x0, y0, z = here:getX(), here:getY(), here:getZ()
    for x = x0 - radius, x0 + radius do
        for y = y0 - radius, y0 + radius do
            local square = getCell():getGridSquare(x, y, z)
            if square and within(here, square, radius) and Storage.permitted(player, square) then
                local objects = square:getObjects()
                for index = 0, objects:size() - 1 do
                    local object = objects:get(index)
                    if Kitchen.isStove(object) then
                        local container = object:getContainer()
                        local waiting = rejected and rejected["stove:" .. stoveKey(object)]
                        if container:isPowered() and not object:Activated() and free(container)
                                and not (waiting and now < waiting) then
                            result.stoves[#result.stoves + 1] = {object = object, square = square,
                                distance = (x - x0) ^ 2 + (y - y0) ^ 2}
                        end
                    elseif object.getContainerCount then
                        for c = 0, object:getContainerCount() - 1 do
                            local container = object:getContainerByIndex(c)
                            if container and container:getType() ~= "stove" then take(container, false) end
                        end
                    end
                end
            end
        end
    end
    table.sort(result.stoves, function(a, b) return a.distance < b.distance end)
    return result
end

-- What to cook: what is already carried first, then whatever spoils soonest,
-- and enough of it to matter.
function Kitchen.choose(food)
    local best, score
    for _, entry in ipairs(food) do
        local item = entry.item
        local hoursLeft = math.max(0, item:getOffAge() - item:getAge()) * 24
        local value = relief(item) * 100 - math.min(hoursLeft, 240) / 10 + (entry.carried and 20 or 0)
        if not score or value > score then best, score = entry, value end
    end
    return best
end

-- ------------------------------------------------------------------- ledger

-- The stove a survivor lit and what is in it, kept across saves and Stop.
function Kitchen.ledger(player) return player:getModData().AutoMindfulKitchen end

local function write(player, entry)
    player:getModData().AutoMindfulKitchen = entry
    if isClient() and player.transmitModData then pcall(player.transmitModData, player) end
end

local function stoveAt(entry)
    local square = entry and getCell():getGridSquare(entry.x, entry.y, entry.z)
    if not square then return nil end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if Kitchen.isStove(object) then return object end
    end
    return nil
end
Kitchen.stoveAt = stoveAt

local function dishIn(stove, entry)
    return stove and entry and entry.item and stove:getContainer():getItemById(entry.item) or nil
end

local function adjacent(player, square)
    local here = player:getSquare()
    return here and square and here:getZ() == square:getZ() and math.abs(here:getX() - square:getX()) <= 1
        and math.abs(here:getY() - square:getY()) <= 1
end

-- A toggle that only ever moves the stove the way it was meant to: someone
-- else may have switched it in the meantime.
local function toggle(player, stove, on, dish)
    local action = ISToggleStoveAction:new(player, stove)
    local valid = action.isValid
    function action:isValid()
        if not valid(self) or self.object:Activated() == on then return false end
        -- Lit only for our own dish, in a stove that still has power.
        return not on or (self.object:getContainer():isPowered() and (not dish or self.object:getContainer():contains(dish)))
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
    state.rejected["stove:" .. entry.x .. ":" .. entry.y .. ":" .. entry.z] = now + Kitchen.policy.retryMs
    Log.event(player, "kitchen.giveup", "why", why, "stove", entry.x .. ":" .. entry.y)
end

-- Take the dish out and switch off, from beside the stove.
local function finish(player, state, entry, stove, dish, message)
    entry.stage = "finishing"
    write(player, entry)
    return P.ownBatch(player, state, "kitchen", message, function()
        if not adjacent(player, stove:getSquare()) and not luautils.walkAdj(player, stove:getSquare(), true) then return end
        if stove:Activated() then toggle(player, stove, false) end
        if dish then transfer(player, dish, stove:getContainer(), player:getInventory()) end
    end)
end

-- Looks after a dish already on the stove. Safe to call when nothing is.
-- walk: false while zombies are about, when only what needs no steps is done.
function Kitchen.duty(player, state, now, walk)
    local entry = Kitchen.ledger(player)
    if not entry then return false end
    local stove = stoveAt(entry)
    if not stove then
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
    local dish = dishIn(stove, entry)
    local on = stove:Activated()
    if not dish and on and (not entry.lit or not free(stove:getContainer())) then
        -- Lit by someone else, or holding their food now: theirs, not ours.
        write(player, nil)
        Alerts.clear(player, "stove")
        Log.event(player, "kitchen.released", "stove", entry.x .. ":" .. entry.y, "lit", entry.lit)
        return false
    end
    if not dish and not on then
        Alerts.clear(player, "stove")
        write(player, nil)
        if state then state.kitchenNotice = nil end
        Log.event(player, "kitchen.done", "stove", entry.x .. ":" .. entry.y)
        return false
    end
    if not state or not state.active then return false end
    local done = dish and dish:isCooked()
    local burning = dish and nearBurning(dish)
    local unpowered = not stove:getContainer():isPowered()
    local blocked = (entry.tries or 0) >= Kitchen.policy.attempts
    if not dish or done or burning or unpowered or blocked or (entry.stage == "cooking" and not on) then
        if blocked then
            state.kitchenNotice = "The stove is still on. Second Nature could not reach it."
            Alerts.raise(player, "stove", "The stove is still on and Second Nature cannot reach it.", now, true)
            entry.blockedAt = entry.blockedAt or now
            if now < entry.blockedAt or now - entry.blockedAt >= Kitchen.policy.againMs then
                entry.tries, entry.blockedAt = 0, nil
                write(player, entry)
            end
            return false
        end
        if walk == false and not adjacent(player, stove:getSquare()) then
            state.kitchenNotice = "The stove is on. It will be turned off once it is safe to walk."
            return false
        end
        local name = dish and dish:getDisplayName() or "the stove"
        local message = not dish and "Turning the stove off." or done and ("Taking " .. name .. " out. It is cooked.")
            or burning and ("Taking " .. name .. " out before it burns.")
            or unpowered and ("The power went off. Taking " .. name .. " out.")
            or ("The stove went off. Taking " .. name .. " out.")
        if (unpowered or (entry.stage == "cooking" and not on)) and not done then giveUp(player, state, entry, now, "stove-off") end
        Log.event(player, "kitchen.finish", "dish", dish and Snap.item(dish), "cooked", done, "burning", burning,
            "unpowered", unpowered, "on", on)
        return finish(player, state, entry, stove, dish, message)
    end
    entry.stage, entry.tries = "cooking", 0
    local share = math.floor(progress(dish) * 100)
    state.kitchenNotice = nil
    -- Stay near the stove; the dish needs taking out on time.
    P.setPhase(state, "kitchen-watch", "Cooking " .. dish:getDisplayName() .. ": " .. share .. "%. Staying near the stove.")
    return true
end

-- A stove this survivor lit is still on, or cannot be seen to be off.
function Kitchen.lit(player)
    local entry = Kitchen.ledger(player)
    if not entry then return false end
    local stove = stoveAt(entry)
    return stove ~= nil and stove:Activated() and entry.stage ~= "fetching" and entry.stage ~= "ready"
end

-- Something on the stove needs a hand now, not just watching.
function Kitchen.urgent(player)
    local entry = Kitchen.ledger(player)
    if not entry or entry.stage ~= "cooking" and entry.stage ~= "finishing" then return false end
    local stove = stoveAt(entry)
    if not stove then return false end
    local dish = dishIn(stove, entry)
    return not dish or dish:isCooked() or nearBurning(dish) or not stove:getContainer():isPowered()
        or not stove:Activated()
end

-- Starts a meal when hunger is due and nothing ready to eat is known.
function Kitchen.meal(player, state, now)
    if Kitchen.ledger(player) then return Kitchen.duty(player, state, now, true) end
    if not Options.cookMeals() or not Needs.due(player, "food") then return false end
    if state.kitchenNext and now < state.kitchenNext and state.kitchenNext - now <= Kitchen.policy.lookMs then return false end
    state.kitchenNext = now + Kitchen.policy.lookMs
    if P.available(player, state, "food") then return false end
    local found = Kitchen.scan(player, state.rejected, now)
    local entry, stove = Kitchen.choose(found.food), found.stoves[1]
    Log.event(player, "kitchen.look", "raw", #found.food, "stoves", #found.stoves, "chosen", entry and Snap.item(entry.item))
    if not entry then
        state.kitchenNotice = nil
        return false
    end
    if not stove then
        state.kitchenNotice = "Only raw food is left, and there is no powered stove nearby."
        return false
    end
    state.kitchenNotice = nil
    local item, object = entry.item, stove.object
    local inventory = player:getInventory()
    if not entry.carried and not inventory:hasRoomFor(player, item) then
        state.rejected[item:getID()] = now + Kitchen.policy.retryMs
        return false
    end
    local square = object:getSquare()
    local record = {x = square:getX(), y = square:getY(), z = square:getZ(), item = item:getID(), name = item:getDisplayName(),
        tries = 0, stage = entry.carried and "ready" or "fetching"}
    write(player, record)
    Log.event(player, "kitchen.start", "dish", Snap.item(item), "stove", stoveKey(object), "carried", entry.carried,
        "temperature", object.getMaxTemperature and object:getMaxTemperature() or nil)
    if entry.carried then return Kitchen.place(player, state, now, record, object) end
    -- First the fridge, then, from wherever that leaves the survivor, the stove.
    local queued = P.ownBatch(player, state, "kitchen", "Getting " .. item:getDisplayName() .. " to cook.", function()
        local from = squareOf(entry.container)
        if from and not adjacent(player, from) and not luautils.walkAdj(player, from, true) then return end
        transfer(player, item, entry.container, inventory)
    end)
    if not queued then
        write(player, nil)
        state.rejected[item:getID()] = now + Kitchen.policy.retryMs
        state.pending = nil
    end
    return queued
end

-- The dish is carried: to the stove with it, in, and on.
function Kitchen.place(player, state, now, entry, object)
    local item = player:getInventory():getItemById(entry.item)
    local container = object and object:getContainer()
    if not item or not Kitchen.cookable(item) or not container or object:Activated() or not container:isPowered()
            or not free(container) then
        write(player, nil)
        if item then state.rejected[item:getID()] = now + Kitchen.policy.retryMs end
        state.rejected["stove:" .. entry.x .. ":" .. entry.y .. ":" .. entry.z] = now + Kitchen.policy.lookMs
        Log.event(player, "kitchen.unplaced", "carried", item ~= nil, "stove", entry.x .. ":" .. entry.y)
        return false
    end
    entry.stage = "starting"
    write(player, entry)
    local square = object:getSquare()
    local queued = P.ownBatch(player, state, "kitchen", "Cooking " .. item:getDisplayName() .. " on the stove.", function()
        if not adjacent(player, square) and not luautils.walkAdj(player, square, true) then return end
        local into = transfer(player, item, item:getContainer(), container)
        local valid = into.isValid
        function into:isValid()
            -- Someone else may have started cooking here in the meantime.
            return (not valid or valid(self)) and not object:Activated() and container:isPowered() and free(container)
        end
        toggle(player, object, true, item)
    end)
    if not queued then
        write(player, nil)
        state.rejected[item:getID()] = now + Kitchen.policy.retryMs
        state.pending = nil
    end
    return queued
end

-- The batch is over. The world says what happened, not how the actions ended.
-- cut: an action was stopped (danger, the player), which is no failed try.
function Kitchen.settle(player, state, now, cut)
    local entry = Kitchen.ledger(player)
    if not entry then return end
    local stove = stoveAt(entry)
    local dish = dishIn(stove, entry)
    if entry.stage == "fetching" then
        if player:getInventory():getItemById(entry.item) then
            entry.stage = "ready"
            write(player, entry)
        else
            if not cut then state.rejected[entry.item] = now + Kitchen.policy.retryMs end
            write(player, nil)
        end
    elseif entry.stage == "starting" then
        local on = stove and stove:Activated()
        if dish then
            -- In the stove. Lit by us, or about to be taken out again.
            entry.stage, entry.lit = "cooking", on and true or nil
            write(player, entry)
        else
            -- Never reached the stove, or someone else lit it first: nothing of ours to clean up.
            if not cut then state.rejected[entry.item] = now + Kitchen.policy.retryMs end
            write(player, nil)
        end
    elseif entry.stage == "finishing" and not cut and (dish or (stove and stove:Activated())) then
        entry.tries = (entry.tries or 0) + 1
        write(player, entry)
    end
end

-- Stop, death or a switch: the stove is not left burning if it can be helped.
function Kitchen.ended(player)
    local entry = Kitchen.ledger(player)
    if not entry then return nil end
    local stove = stoveAt(entry)
    if entry.stage == "fetching" or entry.stage == "ready" then write(player, nil); return nil end
    if not stove or not stove:Activated() or not entry.lit then return nil end
    if adjacent(player, stove:getSquare()) and not player:isDead() then
        toggle(player, stove, false)
        local dish = dishIn(stove, entry)
        if dish then transfer(player, dish, stove:getContainer(), player:getInventory()) end
        return "Turning the stove off."
    end
    return "The stove is still on" .. (entry.name and (" with " .. entry.name .. " inside") or "") .. "."
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
    if stove and not stove:Activated() then return end
    local dish = dishIn(stove, entry)
    local detail = dish and nearBurning(dish) and (dish:getDisplayName() .. " is about to burn on the stove.")
        or ("The stove is on" .. (entry.name and (" with " .. entry.name .. " inside") or "") .. " and nothing is watching it.")
    warned[player] = now
    Log.headline(player, "kitchen.unwatched", "detail", detail)
    HUD.show(player:getPlayerNum(), {brand="Second Nature", theme="mindful", status="stopped", title="Kitchen", detail=detail})
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
    local dish = dishIn(stove, entry)
    return {dish = entry.name, progress = dish and progress(dish) or nil, on = stove and stove:Activated() or nil, notice = notice}
end

return Kitchen
