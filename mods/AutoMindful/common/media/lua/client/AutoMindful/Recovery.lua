-- What Recovery decides. The Controller owns the queue, the trips and the
-- receipts; this file owns judgement: who is at the controls, how dangerous it
-- is, what may be done about which need, and when to ask for help. The survival
-- parts (danger, first aid, last resort) also stand behind every training job.
local Alerts = require "AutoMindful/Alerts"
local Beds = require "AutoMindful/Beds"
local Danger = require "AutoMindful/Danger"
local FirstAid = require "AutoMindful/FirstAid"
local Fluids = require "AutoMindful/Fluids"
local Interject = require "AutoMindful/Interject"
local Log = require "AutoMindful/Log"
local Needs = require "AutoMindful/SurvivalNeeds"
local Options = require "AutoMindful/Options"
local Outlook = require "AutoMindful/Outlook"
local Preferences = require "AutoMindful/Preferences"
local Presence = require "AutoMindful/Presence"
local Snap = require "AutoMindful/Snapshot"
local Supplies = require "AutoMindful/Supplies"
local WaterSources = require "AutoMindful/WaterSources"

local Recovery = {}
local P -- the Controller's parts, bound once it has loaded
local watchMs, sampleMs, outlookMs = 5000, 15000, 300000
local setbackMs, setbackLimitMs, setbackForgetMs = 15000, 600000, 900000
local aidRetryMs, bedRetryMs, refillRetryMs = 5000, 900000, 60000
local lastResortMs, boxedAfter = 60000, 4
local bedtimeTopUp = 0.05

function Recovery.bind(parts) P = parts end

-- ---------------------------------------------------------------- presence

-- How long nobody has used the controls and nothing else has used the body.
function Recovery.aloneMs(player, state, now)
    local alone = Presence.aloneMs(player, now)
    if state.recoveryIdleAt and now >= state.recoveryIdleAt then return math.min(alone, now - state.recoveryIdleAt) end
    return 0
end

function Recovery.away(player, now) return Presence.away(player, now) end

function Recovery.setAway(player, state, away)
    Presence.pin(player, away)
    if not away then Presence.touch(player, getTimestampMs()) end
    state.watchAt = nil -- say now what would go wrong, while there is someone to tell
    Log.event(player, "presence.pin", "away", away)
end

function Recovery.permit(player, state, what, now)
    if not state.recovery then return true end
    if state.guard then return false end
    if Presence.away(player, now) then return true end
    return Recovery.aloneMs(player, state, now) >= Presence.policy[what]
end

-- Walking off with the survivor is the most intrusive thing Recovery does. How
-- long it waits depends on how badly it is needed.
function Recovery.mayTravel(player, state, kind, now)
    local vital = kind == "food" or kind == "water"
    if state.guard then return vital and state.guard.level ~= "vehicle" and Needs.critical(player, kind) end
    if not state.recovery then return true end
    if state.tripsAt and now < state.tripsAt and state.tripsAt - now <= setbackLimitMs then return false end
    if vital then
        local level = Needs.level(player, kind)
        if level >= 3 or state.lowHealth then return true end
        if level == 2 then return Recovery.permit(player, state, "pressing", now) end
        if level == 1 then return Recovery.permit(player, state, "due", now) end
        if Needs.due(player, kind) then return Recovery.permit(player, state, "early", now) end
        return Presence.away(player, now)
    end
    if kind == "restroom" then return Recovery.permit(player, state, "pressing", now) end
    if kind == "literature" then return Recovery.permit(player, state, "explore", now) end
    return Recovery.permit(player, state, "due", now)
end

function Recovery.mayExplore(player, state, kind, now)
    if not state.recovery or state.lowHealth then return true end
    if (kind == "food" or kind == "water") and Needs.level(player, kind) >= 3 then return true end
    return Recovery.permit(player, state, "explore", now)
end

-- ------------------------------------------------------------------ danger

local essential = {eating=true, drinking=true, preparing=true, transferring=true, firstaid=true, paincare=true,
    ["restoring-mask"]=true, returning=true, standing=true}

-- Work that can wait until it is safe. A bite, a bandage and the way to water
-- for someone dying of thirst are not.
function Recovery.optionalWork(player, state)
    if state.practiceCare and not (state.practiceCare.lowHealthHeal or state.practiceCare.target == "hunger") then return true end
    local trip = state.excursion
    if trip and state.pending and (trip.stage == "outbound" or trip.stage == "homebound" or trip.stage == "bed") then
        return not ((trip.kind == "food" or trip.kind == "water") and trip.stage == "outbound" and Needs.critical(player, trip.kind))
    end
    if not state.pending or #state.pending == 0 then return false end
    if state.phase == "collecting" then return state.supplyKind == "literature" or state.lifestylePickup ~= nil end
    return not essential[state.phase]
end

function Recovery.alerts(player) return Alerts.list(player) end

function Recovery.collectNearby(player) return Preferences.collectNearby(player) end

function Recovery.danger(player) return Danger.read(player) end

-- Sets state.guard: what is wrong, and therefore what is still allowed.
function Recovery.readGuard(player, state)
    local level, reason = Danger.read(player)
    state.guard = nil
    if level == "engaged" then return level, reason end
    if state.recovery and player:getVehicle() then
        state.guard = {level="vehicle", reason="the survivor is in a vehicle"}
    elseif level == "wary" then state.guard = {level="wary", reason=reason}
    elseif Danger.bleeding(player) then state.guard = {level="bleeding", reason="the survivor is bleeding"} end
    return state.guard and state.guard.level or "clear", state.guard and state.guard.reason
end

-- ----------------------------------------------------------------- first aid

local function reach(state)
    return not (state.guard and state.guard.level == "vehicle") and (state.collectNearby or Options.searchNearby())
end

function Recovery.firstAid(player, state, now)
    if state.excursion or state.aidNext and now < state.aidNext and state.aidNext - now <= 60000 then return false end
    if not player:getBodyDamage().getBodyParts then return false end
    local plan, missing = FirstAid.next(player, reach(state))
    if not plan then
        state.aidNext = now + aidRetryMs
        state.aidNotice = missing == "bleeding" and "Bleeding, and there is no bandage within reach." or nil
        return false
    end
    -- A dirty bandage or a scratch can wait until nobody needs the hands.
    if not plan.bleeding and not Recovery.permit(player, state, "topUp", now) then return false end
    state.aidNotice = nil
    if not plan.remove and plan.item:getContainer() ~= player:getInventory() then
        state.aidNext = nil
        local queued = P.ownBatch(player, state, "firstaid", "Getting a bandage.", function() Supplies.transfer(player, plan.item) end)
        if queued then return true end
        state.pending, state.aidNext = nil, now + aidRetryMs
        return false
    end
    local name = FirstAid.partName(plan.part)
    local queued = P.ownBatch(player, state, "firstaid",
        plan.remove and ("Taking a dirty bandage off: " .. name .. ".") or ("Bandaging: " .. name .. "."), function()
        local action = FirstAid.action(player, plan)
        if action then ISTimedActionQueue.add(action) end
    end)
    Log.event(player, "firstaid", "part", name, "item", Snap.item(plan.item), "remove", plan.remove, "bleeding", plan.bleeding, "queued", queued)
    state.aidNext = now + 1000
    if queued then return true end
    state.pending, state.aidNext = nil, now + aidRetryMs
    return false
end

-- --------------------------------------------------------------- last resort

-- Dying of thirst is certain; water that makes you ill is not. Only when the
-- last moodle has stood for a while and nothing clean is left.
function Recovery.prepareCare(player, state, now)
    local critical = Needs.critical(player, "water")
    if not critical then state.parchedAt = nil
    elseif not state.parchedAt or now < state.parchedAt then state.parchedAt = now end
    local allow = critical and now - state.parchedAt >= lastResortMs and Options.lastResort()
    if allow ~= (state.lastResort == true) then
        state.lastResort, state.travelScan, state.polls = allow or nil, nil, nil
        Log.headline(player, "last-resort", "taintedWater", allow)
    end
    Fluids.allowTainted = allow == true
end

-- ------------------------------------------------------------------- sleep

-- A bite and a sip before eight hours without either.
local function topUpBeforeBed(player, state)
    local full = player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) >= 3
    for _, kind in ipairs({"water", "food"}) do
        local value = P.stat(player, kind == "water" and "THIRST" or "HUNGER")
        if value >= bedtimeTopUp and (kind == "water" or not full)
                and P.supply(player, state, kind, kind == "water" and full, nil, nil, true, true) then return true end
    end
    return false
end

-- Returns true when something was started instead of lying down right here.
function Recovery.beforeSleep(player, state, now)
    if not state.recovery then return false end
    if topUpBeforeBed(player, state) then return true end
    local try = state.bedTry
    if try and not try.slept then
        state.bedsRejected = state.bedsRejected or {}
        state.bedsRejected[try.key] = now + bedRetryMs
        Log.event(player, "bed.unusable", "bed", try.key)
    end
    state.bedTry = nil
    if state.lowHealth or state.excursion or not Options.useBeds() or not Options.searchNearby() then return false end
    local bed = Beds.find(player, Options.searchRadius(), state.bedsRejected, now)
    if not bed then return false end
    state.bedTry = {key=Beds.key(bed)}
    Log.event(player, "bed", "bed", Snap.object(bed), "quality", ISWorldObjectContextMenu.getBedQuality(player, bed))
    state.excursion = {origin=P.rememberOrigin(player, player:getSquare()), stage="bed", kind="sleep"}
    local queued = P.ownBatch(player, state, "bed", "Going to bed.", function()
        if player:isSitOnGround() then ISTimedActionQueue.add(ISWaitWhileGettingUp:new(player)) end
        if #P.queueFor(player) == 0 then
            ISWorldObjectContextMenu.onConfirmSleep(nil, {internal="YES"}, player:getPlayerNum(), bed)
        else state.bedTry = nil end -- stand first; the next look finds the bed again
    end)
    if player:isAsleep() then
        state.bedTry.slept = true
        P.setPhase(state, "sleeping", "Sleeping in bed. Continues after waking.")
        return true
    end
    if queued then
        if not state.bedTry then state.excursion = nil end
        return true
    end
    state.excursion, state.pending = nil, nil
    return false
end

-- ------------------------------------------------------------------- water

local function waterVessel(player, state, item)
    local fluid = Fluids.container(item)
    if not fluid or item:isSealed() or (item.isFavorite and item:isFavorite() and fluid:isEmpty()) then return nil end
    if not Fluids.drinkable(item, fluid) or fluid:isInputLocked() then return nil end
    state.vessels = state.vessels or {}
    if fluid:isEmpty() then
        local name = item:getFullType()
        if not state.vessels[item:getID()] and not (name:find("Bottle") or name:find("Canteen") or name:find("Flask")
                or name:find("Thermos")) then return nil end
        return Fluids.emptyVessel(item) and fluid or nil
    end
    if not fluid:isPureFluid(Fluid.Water) or not Fluids.safe(fluid) then return nil end
    state.vessels[item:getID()] = true
    return fluid
end

-- The game sips from bottles in the main inventory by itself. A full one keeps
-- a survivor alive when no path works and nothing else may be done.
function Recovery.bottle(player, state)
    local items = player:getInventory():getItems()
    local best, free, carried = nil, 0, 0
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local fluid = waterVessel(player, state, item)
        if fluid then
            carried = carried + fluid:getAmount()
            local room = fluid:getCapacity() - fluid:getAmount()
            if room > fluid:getCapacity() * 0.1 and room > free then best, free = item, room end
        end
    end
    return best, free, carried
end

local function light(player, kilograms)
    local inventory = player:getInventory()
    if not inventory.getCapacityWeight or not player.getMaxWeight then return true end
    return inventory:getCapacityWeight() + kilograms <= player:getMaxWeight()
end

function Recovery.refill(player, state, now, object)
    if not state.recovery or not Options.refill() or Fluids.allowTainted then return false end
    if state.refillNext and now < state.refillNext and state.refillNext - now <= refillRetryMs then return false end
    local item, room = Recovery.bottle(player, state)
    if not item or not light(player, room) then state.refillNext = now + refillRetryMs; return false end
    local source = WaterSources.choose(player, state.rejected, object)
    if not source then return false end
    local queued = P.ownBatch(player, state, "refilling", "Filling " .. item:getDisplayName() .. ".", function()
        if player:isSitOnGround() then ISTimedActionQueue.add(ISWaitWhileGettingUp:new(player)) end
        local action = ISTakeWaterAction:new(player, item, source.object, false)
        if action:isValid() then ISTimedActionQueue.add(action) end
    end)
    Log.event(player, "refill", "item", Snap.item(item), "liters", room, "from", Snap.object(source.object), "queued", queued)
    state.refillNext = now + (queued and 5000 or refillRetryMs)
    if not queued then state.pending = nil end
    return queued
end

-- ------------------------------------------------------------------ setbacks

-- An internal failure used to end the job. For someone who left the survivor in
-- Recovery's hands overnight that is the same as giving up on them.
function Recovery.setback(player, state, reason, cause)
    local now = getTimestampMs()
    local record = state.setbacks
    if not record or now < record.at or now - record.at > setbackForgetMs then record = {count=0} end
    record.count, record.at, record.reason = record.count + 1, now, reason
    state.setbacks = record
    local limit = (Needs.critical(player, "water") or Needs.critical(player, "food")) and 60000 or setbackLimitMs
    state.tripsAt = now + math.min(limit, setbackMs * 2 ^ math.min(record.count - 1, 10))
    Log.headline(player, "recovery.setback", "reason", reason, "cause", cause, "count", record.count,
        "noTripsForS", math.floor((state.tripsAt - now) / 1000), "phase", state.phase, "trip", state.excursion and state.excursion.stage)
    state.excursion, state.travelScan, state.failures = nil, nil, 0
    state.stalledSkill, state.unknownPauses, state.lostWithoutAction, state.unconfirmedSince = nil, nil, nil, nil
    P.pause(player, state, (reason or "Something went wrong.") .. " Recovery stays on and tries again.", "setback")
end

function Recovery.notePath(state, target, failed)
    local player = state.player
    local square = player and player:getSquare()
    if not square then return end
    local here = square:getX() .. ":" .. square:getY() .. ":" .. square:getZ()
    local record = state.pathFails
    if not failed or not record or record.here ~= here then
        record = {here=here, keys={}, count=0}
        state.pathFails = record
        if state.boxedIn then Log.event(player, "boxed-in.over", "at", here) end
        state.boxedIn = nil
        if not failed then return end
    end
    local key = target and target.key or "?"
    if not record.keys[key] then record.keys[key], record.count = true, record.count + 1 end
    if record.count >= boxedAfter and not state.boxedIn then
        state.boxedIn, state.outlookRead = true, nil
        Log.headline(player, "boxed-in", "at", here, "failedTargets", record.count)
    end
end

-- -------------------------------------------------------------------- watch

-- Runs whether or not Recovery may act, so that a survivor in trouble is never
-- in trouble quietly.
function Recovery.watch(player, state, now)
    if state.sampleAt and now >= state.sampleAt and now - state.sampleAt < sampleMs then
        -- sampled recently
    else
        state.sampleAt = now
        Outlook.sample(player, now)
    end
    if state.watchAt and now >= state.watchAt and now - state.watchAt < watchMs then return end
    state.watchAt = now
    local away = Presence.away(player, now)
    if away ~= (state.wasAway == true) then
        state.wasAway = away or nil
        Log.event(player, "presence", "away", away, "aloneS", math.floor(Presence.aloneMs(player, now) / 1000), "pinned", Presence.pinned(player))
        if away then state.farewell = true end
    end
    if player:isAsleep() then return end
    local function report(id, problem, text)
        if problem then Alerts.raise(player, id, text, now, away or problem == "dying") else Alerts.clear(player, id) end
    end
    local level = Danger.read(player)
    report("danger", away and level == "engaged", "Zombies have found the survivor.")
    report("bleeding", Danger.bleeding(player) and state.aidNotice ~= nil, "Bleeding, and there is no bandage within reach.")
    for _, kind in ipairs({"water", "food"}) do
        local need = Needs.level(player, kind)
        local short = need >= 3 and not P.available(player, state, kind)
        report(kind, short and (need >= 4 and "dying" or "short") or nil,
            kind == "water" and "Very thirsty, and nothing safe to drink is within reach."
            or "Very hungry, and there is nothing to eat within reach.")
    end
    report("boxed", state.boxedIn, "Every walk from this spot fails. Move the survivor to open floor.")
    local setbacks = state.setbacks
    report("setback", setbacks and setbacks.count >= 3 and now - setbacks.at < setbackForgetMs, setbacks and setbacks.reason or "")
    if not away then state.farewell = nil end
    if state.farewell or not state.outlookAt or now < state.outlookAt or now - state.outlookAt >= outlookMs then
        state.outlookAt = now
        local outlook = Recovery.outlook(player, state, now, true)
        local names = {}
        for _, issue in ipairs(outlook.issues) do names[#names + 1] = issue.id .. ":" .. issue.severity end
        Log.event(player, "outlook", "foodH", outlook.foodHours, "waterH", outlook.waterHours, "endlessWater", outlook.endlessWater,
            "carriedFoodH", outlook.carriedFoodHours, "carriedWaterH", outlook.carriedWaterHours, "issues", table.concat(names, " "), "away", away)
        -- The moment someone leaves is the last one at which telling them helps.
        if state.farewell then
            local worst = outlook.issues[1]
            if worst and worst.severity >= 3 then Alerts.raise(player, "farewell", "Before you go: " .. worst.text, now, true) end
        end
        state.farewell = nil
    end
    if not away then Alerts.clear(player, "farewell") end
end

function Recovery.observe(player, state, now)
    Presence.observe(player, now)
    Recovery.watch(player, state, now)
end

function Recovery.between(player, state, queue, now)
    return Interject.consider(player, state, queue, now)
end

function Recovery.outlook(player, state, now, force)
    if not force and state.outlookRead and now >= state.outlookRead.at and now - state.outlookRead.at < 10000 then return state.outlookRead.value end
    local value = Outlook.read(player, Preferences.range(player), state)
    state.outlookRead = {at=now, value=value}
    return value
end

-- ------------------------------------------------------------------- advance

-- Zombies in view, bleeding, or sitting in a car: no walking, no practice, no
-- sleep. Eating, drinking, bandaging and a painkiller from where you are.
function Recovery.guarded(player, state, now)
    local guard = state.guard
    P.sampleIdle(state, now)
    if Recovery.firstAid(player, state, now) then return end
    Recovery.prepareCare(player, state, now)
    local full = player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) >= 3
    state.carriedOnly = guard.level == "vehicle" or nil
    local acted = false
    for _, kind in ipairs(Needs.critical(player, "food") and not Needs.critical(player, "water") and {"food", "water"} or {"water", "food"}) do
        if not acted and (Needs.due(player, kind) or Needs.critical(player, kind)) and (kind == "water" or not full) then
            local here = not Needs.critical(player, kind) or guard.level == "vehicle"
            acted = P.supply(player, state, kind, kind == "water" and full, nil, nil, true, here) and true or false
        end
    end
    if not acted and guard.level ~= "vehicle" and P.painReady(player, state, now) then
        acted = P.supply(player, state, "pain", false, nil, nil, true, true) and true or false
    end
    state.carriedOnly = nil
    if acted or not state.active then return end
    P.setPhase(state, "recovery-paused", guard.level == "bleeding" and (state.aidNotice or "Bleeding. Looking for a bandage.")
        or guard.level == "vehicle" and "In a vehicle. Only what you carry is used."
        or ("Keeping still: " .. guard.reason .. ". Only care that needs no walking."), "recovery-danger")
end

function Recovery.advance(player, state, now)
    local policy = P.policy
    local endurance = P.endurance(player)
    P.sampleIdle(state, now)
    if Recovery.firstAid(player, state, now) then return end
    if P.care(player, state) or not state.active then return end
    local away = Presence.away(player, now)
    local calm = Recovery.permit(player, state, "posture", now)
    if P.lifestyleCare(player, state, P.lifestyleReady(player, state, now), now) then return end
    local pain = P.painAvailable(player, state, now)
    if pain and P.supply(player, state, "pain") then return end
    if Recovery.permit(player, state, "topUp", now) and P.earlySupply(player, state, true) then return end
    local boredom = P.stat(player, "BOREDOM")
    local wantsReading = calm and boredom >= policy.readAt
    if wantsReading and P.supply(player, state, "literature", false, nil, nil, true, true) then return end
    if state.recoveryStockWaiting then
        if not P.waitForSleep(player, state) then
            P.setPhase(state, "recovery-idle", "Will collect a known supply if you stay idle.")
        end
        return
    end
    if calm then
        local med, yoga = P.levels(player)
        if P.resumeTier(player, state, now, med, yoga) then return end
        if P.practiceCare(player, state, now, P.meditationGate(player), P.yogaAdmission(player), med, yoga, nil, nil, pain) or not state.active then return end
    end
    if P.waitForSleep(player, state) then return end
    if away then
        if P.earlySupply(player, state, false) then return end
        if wantsReading and P.supply(player, state, "literature", false, nil, nil, true) then return end
    end
    if Recovery.permit(player, state, "explore", now) and P.lookInside(player, state, boredom) then return end
    if calm and Recovery.refill(player, state, now) then return end
    if away and Recovery.fetchWater(player, state, now) then return end
    if not (calm and P.restNaturally(player, state, endurance)) then
        local strict = state.recoveryTier
        P.setPhase(state, "recovery-idle", strict and strict.waiting
            or away and "Looking after the survivor while you are away."
            or calm and "Nothing needs attention." or "Watching. You can carry on with other actions.")
    end
end

-- Away, nearly dry, and a known tap within range: go and fill up before it is
-- needed rather than after.
function Recovery.fetchWater(player, state, now)
    if not Options.refill() or not Options.searchNearby() or state.excursion then return false end
    if state.fetchNext and now < state.fetchNext and state.fetchNext - now <= bedRetryMs then return false end
    local item, room, carried = Recovery.bottle(player, state)
    if not item or carried >= 0.5 or not light(player, room) then return false end
    state.fetchNext = now + bedRetryMs
    local started = P.fetchWater(player, state)
    Log.event(player, "refill.trip", "carriedLiters", carried, "started", started)
    return started
end

return Recovery
