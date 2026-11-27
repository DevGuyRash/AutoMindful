-- What Recovery decides. The Controller owns the queue, the trips and the
-- receipts; this file owns judgement: who is at the controls, how dangerous it
-- is, what may be done about which need, and when to ask for help. The survival
-- parts (danger, first aid, last resort) also stand behind every training job.
local Alerts = require "AutoMindful/Alerts"
local Coexist = require "AutoMindful/Coexist"
local Kitchen = require "AutoMindful/Kitchen"
local Grid = require "AutoMindful/Grid"
local Saved = require "AutoMindful/Saved"
local Beds = require "AutoMindful/Beds"
local Danger = require "AutoMindful/Danger"
local FirstAid = require "AutoMindful/FirstAid"
local Dressings = require "AutoMindful/Dressings"
local Fetch = require "AutoMindful/Fetch"
local Fluids = require "AutoMindful/Fluids"
local IntakeGuard = require "AutoMindful/IntakeGuard"
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
local watchMs, sampleMs, outlookMs, guardMs = 5000, 15000, 300000, 1500
local setbackMs, setbackLimitMs, setbackForgetMs = 15000, 600000, 900000
local aidRetryMs, aidConfirmMs, bedRetryMs, refillRetryMs = 5000, 4000, 900000, 60000
local lastResortMs, stalledMs, boxedAfter = 60000, 120000, 4
local bedtimeTopUp = 0.05

function Recovery.bind(parts) P = parts; Kitchen.bind(parts) end

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
    local level = vital and Needs.level(player, kind) or 0
    if Recovery.backingOff(state, now, level >= 4) then return false end
    if vital then
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

-- After a setback nobody is walked anywhere for a while; a dying survivor waits
-- a minute at most, whatever the setback was about.
function Recovery.backingOff(state, now, dying)
    if not state.tripsAt or now >= state.tripsAt or state.tripsAt - now > setbackLimitMs then return false end
    return not (dying and state.setbacks and now - state.setbacks.at >= 60000)
end

function Recovery.mayExplore(player, state, kind, now)
    if not state.recovery or state.lowHealth then return true end
    if (kind == "food" or kind == "water") and Needs.level(player, kind) >= 3 then return true end
    return Recovery.permit(player, state, "explore", now)
end

-- ------------------------------------------------------------------ danger

local essential = {eating=true, drinking=true, preparing=true, transferring=true, firstaid=true, paincare=true,
    ["restoring-mask"]=true, returning=true, standing=true, kitchen=true}

-- Work that can wait until it is safe. A bite, a bandage and the way to water
-- for someone dying of thirst are not.
function Recovery.optionalWork(player, state)
    if state.practiceCare and not (state.practiceCare.lowHealthHeal or state.practiceCare.target == "hunger") then return true end
    local trip = state.excursion
    if trip and state.pending and (trip.stage == "outbound" or trip.stage == "homebound" or trip.stage == "bed") then
        return not ((trip.kind == "food" or trip.kind == "water") and trip.stage == "outbound" and Needs.critical(player, trip.kind))
    end
    if not state.pending or #state.pending == 0 then return false end
    -- Fetching food for practice can wait; taking a dish out cannot.
    if state.phase == "kitchen" then
        local entry = Kitchen.ledger(player)
        return entry ~= nil and entry.reason == "practice" and entry.stage ~= "cooking" and entry.stage ~= "finishing"
    end
    if state.phase == "collecting" then return state.supplyKind == "literature" or state.lifestylePickup ~= nil end
    return not essential[state.phase]
end

-- Saved with the survivor, so the job can go on after loading. In multiplayer
-- the server keeps the survivor, so it has to be told.
function Recovery.remember(player, on)
    Saved.set(player, "AutoMindfulRecovery", on or nil)
end

function Recovery.remembered(player) return player:getModData().AutoMindfulRecovery == true end

function Recovery.ended(player)
    Fluids.allowTainted = false
    Alerts.forget(player)
    Presence.forget(player)
end

-- After Stop has cleared its own actions, so the switch-off is not cleared with them.
function Recovery.kitchenStopped(player)
    local stove = Kitchen.ended(player)
    if stove then
        Log.headline(player, "kitchen.ended", "result", stove)
        Alerts.notice(player, "Kitchen", stove)
    end
end

function Recovery.kitchenSettled(player, state, now, cut) Kitchen.settle(player, state, now, cut) end
function Recovery.kitchenMeal(player, state, now) return state.recovery and Kitchen.meal(player, state, now) end
function Recovery.kitchen(player, state) return Kitchen.status(player, state) end

function Recovery.alerts(player) return Alerts.list(player) end

function Recovery.collectNearby(player) return Preferences.collectNearby(player) end

function Recovery.danger(player) return Danger.read(player) end

-- A trip cannot go on from here, and nothing may wait for its end. The way back
-- is kept for when it is safe again, and it is the first one that counts.
function Recovery.parkTrip(state)
    local trip = state.excursion
    if not trip then return end
    if trip.origin and not trip.egressPlan and not state.parkedTrip then state.parkedTrip = {origin=trip.origin, stage="resume-home"} end
    state.excursion = nil
end

-- Walked off by someone, or on another floor: home is wherever they are now.
function Recovery.unparkTrip(player, state)
    local parked, square = state.parkedTrip, player:getSquare()
    state.parkedTrip = nil
    if parked and square and square:getZ() == parked.origin.z then state.excursion = parked end
end

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

-- Borrowed for this wound stays borrowed until the wound is seen to; then it
-- goes back where it came from, the floor included (placed, not dropped).
-- uses: the items the next care still takes; everything else is released.
local function releaseAid(state, uses, list)
    list = list or "aidLoans"
    local kept = {}
    for _, loan in ipairs(state[list] or {}) do
        if uses and uses[loan.original] then kept[#kept + 1] = loan
        else loan.defer, loan.aidReturn = nil, true end
    end
    state[list] = #kept > 0 and kept or nil
end

-- What the last step was meant to change. A server may refuse it, or answer
-- late; neither is a reason to use up another bandage or to skip dinner.
local function aidSettled(player, state, now)
    local try = state.aidTry
    if not try then return true end
    if FirstAid.done(player, try.step) then
        state.aidTry = nil
        if try.step.kind == "bandage" and state.aidHeld then state.aidHeld[try.step.part] = nil end
        return true
    end
    try.endedAt = try.endedAt or now
    if now >= try.endedAt and now - try.endedAt < aidConfirmMs then return false end
    state.aidTry = nil
    local part = try.step.part
    local held = state.aidHeld or {}
    state.aidHeld = held
    local record = held[part] or {count=0}
    held[part] = record
    -- Cut short says nothing about the supplies. Finished without effect does.
    if try.cut then record.at = now + 10000
    else
        record.count = record.count + 1
        record.at = now + math.min(setbackLimitMs, 30000 * 2 ^ (record.count - 1))
        local step = try.step
        local list = step.entries or {step.entry or step.item or step.tool or step.thread}
        for _, entry in ipairs(list) do state.rejected[entry.item:getID()] = now + 60000 end
    end
    FirstAid.forget(player)
    Log.event(player, "firstaid.refused", "step", try.step.kind, "part", FirstAid.partName(part), "count", record.count, "cutShort", try.cut)
    return true
end

-- A borrowed thing whose shelf is out of reach: walk back to it, so the
-- ordinary return can put it there.
local function returnTrip(player, state, now)
    for _, loan in ipairs(state.loans) do
        if loan.aidReturn and not loan.defer and (loan.aidWalks or 0) < 2 then
            local square = loan.floor and loan.floor.square or loan.origin and Supplies.sourceSquare(loan.origin)
            if square and not Grid.reachable(player:getSquare(), square) then
                loan.aidWalks = (loan.aidWalks or 0) + 1
                return P.ownBatch(player, state, "firstaid", "Taking borrowed first aid supplies back.", function()
                    luautils.walkAdj(player, square, true)
                end)
            end
        end
    end
    return false
end

-- Once everything is back where it belongs, back to where first aid began:
-- the spot the survivor was training or resting on.
local function goBack(player, state)
    local origin = state.aidOrigin
    if not origin then return false end
    for _, loan in ipairs(state.loans) do if loan.aidReturn and (loan.aidWalks or 0) < 2 then return false end end
    state.aidOrigin = nil
    local square = getCell():getGridSquare(origin.x, origin.y, origin.z)
    local here = player:getSquare()
    if not square or not here or here == square or state.excursion then return false end
    return P.ownBatch(player, state, "firstaid", "Back to where first aid began.", function()
        ISTimedActionQueue.add(ISWalkToTimedAction:new(player, square))
    end)
end

-- Auto All's jobs that look after wounds and dressings themselves.
local medicalJobs = {medicine = true, sterilize = true, clean = true, wring = true}
local coexistBleedMs = 30000

local function coexisting(player, state, step, other)
    local signature = "coexist:" .. other .. ":" .. FirstAid.partName(step.part) .. ":" .. step.kind
    if state.aidWaiting == signature then return end
    state.aidWaiting = signature
    Log.event(player, "firstaid.waiting", "why", other, "part", FirstAid.partName(step.part), "next", step.kind, "chain", step.chain)
end

-- Said once per change: what waits for safety, so the log shows it.
local function waiting(player, state, step, why)
    state.aidNotice = FirstAid.describe(step):gsub("%.$", "") .. " waits until it is safe."
    local signature = why .. ":" .. FirstAid.partName(step.part) .. ":" .. step.chain
    if state.aidWaiting == signature then return end
    state.aidWaiting = signature
    Log.event(player, "firstaid.waiting", "why", why, "part", FirstAid.partName(step.part), "next", step.kind, "chain", step.chain)
end

-- Brings what a job takes into the hands, each borrowed until the job is
-- done (state[list] holds the loans). Lying on the floor: picked up as the
-- game does, which needs no loot window to have listed it. No room, or the
-- game will not move it: held back a while, so something else may serve.
local function takeAll(player, state, now, entries, message, list)
    local queued = P.ownBatch(player, state, "firstaid", message, function()
        for _, entry in ipairs(entries) do
            local loan = P.loanFor(player, state, entry.item)
            if loan then
                loan.defer = true
                state[list] = state[list] or {}
                local known = false
                for _, other in ipairs(state[list]) do if other == loan then known = true end end
                if not known then state[list][#state[list] + 1] = loan end
            end
            local taken
            if entry.entry.world and player:getInventory():hasRoomFor(player, entry.item) then
                -- Several grabs merge into one action: whether each was
                -- taken is read afterwards, from the inventory.
                Fetch.queue(player, entry.entry)
                taken = true
            else taken = Supplies.transfer(player, entry.item, loan) end
            if not taken then
                state.rejected[entry.item:getID()] = now + 60000
                if loan then loan.defer = nil end
            end
        end
    end)
    if not queued then FirstAid.forget(player) end
    return queued
end

-- Walks beside what a job takes; first aid's walk back starts from here.
local function walkFor(player, state, now, step, message)
    local from = player:getSquare()
    local queued = P.ownBatch(player, state, "firstaid", message, function() luautils.walkAdj(player, step.square, true) end)
    -- Nothing to walk: a wall between, or no free square beside it.
    if not queued then state.rejected[step.entry.item:getID()] = now + 60000; FirstAid.forget(player)
    elseif not state.aidOrigin and not state.excursion and from then state.aidOrigin = {x = from:getX(), y = from:getY(), z = from:getZ()} end
    return queued
end

function Recovery.firstAid(player, state, now)
    if not Options.firstAid() then releaseAid(state); releaseAid(state, nil, "dressLoans"); return false end
    if state.excursion and state.excursion.stage == "outbound" then return false end
    if state.aidNext and now < state.aidNext and state.aidNext - now <= 60000 then return false end
    if not player:getBodyDamage().getBodyParts then return false end
    if not aidSettled(player, state, now) then return false end
    state.aidNext = now + 1000
    local guarded = state.guard and state.guard.level ~= "bleeding"
    local step, missing = FirstAid.plan(player, {radius = reach(state) and Options.searchRadius() or 0,
        rejected = state.rejected, now = now, hurry = guarded,
        blocked = function(part)
            local held = state.aidHeld and state.aidHeld[part]
            return held ~= nil and now < held.at and held.at - now <= setbackLimitMs
        end})
    releaseAid(state, step and step.uses)
    if not step then
        state.aidBleedSince = nil
        state.aidNotice = missing == "bleeding" and "Bleeding, and there is no bandage within reach."
            or missing == "calming" and "Wounds wait until the panic passes: the sight of blood." or nil
        if missing then state.aidNext = now + aidRetryMs end
        state.aidWaiting = nil
        if state.guard or not Recovery.permit(player, state, "topUp", now) then return false end
        -- Nothing to treat now, or nothing to treat it with: borrowed things still go home.
        if missing then return returnTrip(player, state, now) end
        -- A dressing job under way walks back by itself once it is done.
        return returnTrip(player, state, now) or (not state.dressBusy and goBack(player, state))
    end
    state.aidNotice = nil
    -- Auto All in charge: its Auto Medicine, Sterilize and Clean do this very
    -- work, so nothing is started or slipped in between, except a dressing on
    -- a wound that has bled undressed too long. Its other jobs leave room for
    -- care of a bleeding wound only.
    local other = Coexist.owner(player)
    if other then
        local kind = other:match("%(([%w_]+)%)")
        if medicalJobs[kind] then
            local since = state.aidBleedSince
            if step.urgent and not since then state.aidBleedSince = now; since = now end
            if not (step.urgent and (step.kind == "bandage" or step.kind == "take" and step.chain == "bandage")
                    and now >= since and now - since >= coexistBleedMs) then
                coexisting(player, state, step, other)
                return false
            end
        elseif not step.urgent then
            coexisting(player, state, step, other)
            return false
        end
    end
    if not step.urgent then state.aidBleedSince = nil end
    -- Care for a bleeding wound goes on while someone is at the controls or
    -- something else is due; the rest waits until nobody needs the hands and
    -- no thirst or hunger is critical. Low health is no reason to wait:
    -- treating the wounds is how it comes back.
    if not step.urgent and (Needs.critical(player, "water") or Needs.critical(player, "food")
            or not Recovery.permit(player, state, "topUp", now)) then return false end
    -- With danger near only a dressing on a bleeding wound, where it stands.
    if guarded and not (step.urgent and (step.kind == "bandage" or step.kind == "take" and step.chain == "bandage")) then
        waiting(player, state, step, state.guard.reason or state.guard.level)
        return false
    end
    -- What the dressing leaves for later, said once while danger is near.
    if guarded and step.waits then waiting(player, state, {part = step.part, kind = step.waits:match("^[^>]+"), chain = step.waits}, state.guard.reason or state.guard.level)
    else state.aidWaiting = nil end
    state.aidTry = {step=step}
    local message = FirstAid.describe(step)
    local queued
    if step.kind == "take" then
        queued = takeAll(player, state, now, step.entries, message, "aidLoans")
        if not queued then state.aidNext = now + aidRetryMs end
    elseif step.kind == "walk" then
        queued = walkFor(player, state, now, step, message)
        if not queued then state.aidNext = now + aidRetryMs end
    else
        queued = P.ownBatch(player, state, "firstaid", message, function()
            local action = FirstAid.action(player, step)
            if action then ISTimedActionQueue.add(action) end
        end)
    end
    local item = step.item or step.tool or step.thread or step.plank or step.alcohol or step.rag or step.herb
    Log.event(player, "firstaid", "step", step.kind, "part", FirstAid.partName(step.part), "chain", step.chain,
        "item", item and Snap.item(item.item), "urgent", step.urgent, "queued", queued)
    if queued then return true end
    state.aidTry = nil
    state.pending = nil
    return false
end

-- ---------------------------------------------------------------- dressings

-- Between wounds, in a calm moment: a dirty dressing washed in clean water, a
-- clean one sterilized with alcohol, with the game's own crafts. A step is
-- done once the dressing it started from has turned into something else.
local function dressSettled(player, state, now)
    local try = state.dressTry
    if not try then return true end
    if not player:getInventory():getItemById(try.id) then state.dressTry = nil; return true end
    try.endedAt = try.endedAt or now
    if now >= try.endedAt and now - try.endedAt < aidConfirmMs then return false end
    state.dressTry = nil
    -- Stopped (darkness, the player): tried again later, and not for ever.
    state.dressCuts = try.cut and (state.dressCuts or 0) + 1 or 0
    if not try.cut or state.dressCuts >= 3 then state.rejected[try.id] = now + 600000; state.dressCuts = 0
    else state.dressNext = now + 30000 end
    Log.event(player, "dressing.refused", "step", try.kind, "cutShort", try.cut)
    return true
end

function Recovery.dressings(player, state, now)
    if not state.recovery or not Options.firstAid() then state.dressBusy = nil; releaseAid(state, nil, "dressLoans"); return false end
    -- Auto All in charge: its own Sterilize and Clean may be at it.
    if Coexist.owner(player) then return false end
    if state.guard or state.excursion or not player:getBodyDamage().getBodyParts then return false end
    if state.dressNext and now < state.dressNext and state.dressNext - now <= 60000 then return false end
    if not dressSettled(player, state, now) then return false end
    state.dressNext = now + 2000
    local job = Dressings.plan(player, function(radius) return FirstAid.picker(player, radius, state.rejected, now) end,
        reach(state) and Options.searchRadius() or 0)
    state.dressBusy = job ~= nil or nil
    if not job then
        releaseAid(state, nil, "dressLoans")
        state.dressNext = now + 30000
        return false
    end
    local uses, far, near = {}, nil, {}
    for _, entry in ipairs(job.uses) do
        uses[entry.item] = true
        -- In a bag: into the hands with a loan, so it goes back to its bag.
        if not entry.carried then
            if entry.reach then near[#near + 1] = entry elseif not far then far = entry end
        end
    end
    releaseAid(state, uses, "dressLoans")
    local queued, message
    if #near > 0 then
        message = "Getting " .. near[1].item:getDisplayName() .. " for the dressings."
        queued = takeAll(player, state, now, near, message, "dressLoans")
    elseif far then
        message = "Going for " .. far.item:getDisplayName() .. " for the dressings."
        queued = walkFor(player, state, now, {square = far.square, entry = far}, message)
    else
        local logic = Dressings.logic(player, job.recipe, job.anchor.item)
        if not logic then
            state.rejected[job.anchor.item:getID()] = now + 600000
            Log.event(player, "dressing.cannot", "step", job.kind, "item", Snap.item(job.anchor.item))
            return false
        end
        message = job.kind == "wash" and ("Washing " .. job.anchor.item:getDisplayName() .. ".")
            or ("Sterilizing " .. job.anchor.item:getDisplayName() .. ".")
        state.dressTry = {id = job.anchor.item:getID(), kind = job.kind}
        queued = P.ownBatch(player, state, "firstaid", message, function() Dressings.craft(player, logic) end)
        if not queued then state.dressTry = nil end
    end
    Log.event(player, "dressing", "step", job.kind, "item", Snap.item(job.anchor.item), "with", Snap.item(job.uses[1].item), "queued", queued)
    if queued then return true end
    state.pending = nil
    state.dressNext = now + 30000
    return false
end

-- --------------------------------------------------------------- last resort

-- Dying of thirst is certain; water that makes you ill is not. Only when the
-- last moodle has stood for a while and nothing clean is left.
function Recovery.prepareCare(player, state, now)
    local critical = Needs.critical(player, "water")
    if not critical then state.parchedAt = nil
    elseif not state.parchedAt or now < state.parchedAt then state.parchedAt = now end
    local allow = false
    if critical and now - state.parchedAt >= lastResortMs and Options.lastResort() then
        if state.lastResortAt and now >= state.lastResortAt and now - state.lastResortAt < 10000 then
            allow = state.lastResort == true
        else
            -- Ask with clean water only: anything clean that is left comes first.
            state.lastResortAt = now
            Fluids.allowTainted, state.travelScan = false, nil
            allow = not P.available(player, state, "water")
        end
    end
    if allow ~= (state.lastResort == true) then
        state.lastResort, state.travelScan, state.polls = allow or nil, nil, nil
        Log.headline(player, "last-resort", "taintedWater", allow)
    end
    Fluids.allowTainted = allow == true
end

-- The permission belongs to this survivor; the fluid checks are shared.
function Recovery.allowTainted(state)
    Fluids.allowTainted = state.active == true and state.lastResort == true and Needs.critical(state.player, "water")
end

-- Nobody is there to close a menu or a map, and the survivor is going under.
function Recovery.unattended(player, state, now)
    if not Presence.away(player, now) then return false end
    return Needs.level(player, "water") >= 3 or Needs.level(player, "food") >= 3 or state.guard ~= nil and state.guard.level == "bleeding"
end

-- Lifestyle is gone or still loading: nothing here works without it.
function Recovery.unready(player, state, reason, now)
    state.unreadyAt = state.unreadyAt or now
    if now - state.unreadyAt >= 60000 then Alerts.raise(player, "unready", reason, now, Presence.away(player, now)) end
end

function Recovery.errorAlert(player, now, count)
    if count >= 3 then Alerts.raise(player, "error", "Second Nature hit an error and keeps retrying. Copy report in the Log tab helps fix it.", now, true) end
end

function Recovery.ready(player, state)
    if state.unreadyAt then state.unreadyAt = nil; Alerts.clear(player, "unready") end
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
    -- Nobody goes to bed with the stove on.
    if Kitchen.ledger(player) then
        if Kitchen.duty(player, state, now, true) then return true end
        if Kitchen.lit(player) then
            P.setPhase(state, "recovery-idle", "Not going to sleep: the stove is still on.")
            return true
        end
    end
    if topUpBeforeBed(player, state) then return true end
    state.bedTry = nil
    if state.lowHealth or state.excursion or not Options.useBeds() or not Options.searchNearby() then return false end
    if state.bedsAt and now < state.bedsAt and state.bedsAt - now <= bedRetryMs then return false end
    local bed = Beds.find(player, Options.searchRadius(), state.bedsRejected, now)
    if not bed then return false end
    state.bedTry = {key=Beds.key(bed)}
    Log.event(player, "bed", "bed", Snap.object(bed), "quality", ISWorldObjectContextMenu.getBedQuality(player, bed))
    state.excursion = {origin=P.rememberOrigin(player, player:getSquare()), stage="bed", kind="sleep"}
    local queued = P.ownBatch(player, state, "bed", "Going to bed.", function()
        P.prepareWalk(state)
        if player:isSitOnGround() then
            state.bedTry = nil -- stand first; the next look finds the bed again
            ISTimedActionQueue.add(ISWaitWhileGettingUp:new(player))
            return
        end
        ISWorldObjectContextMenu.onConfirmSleep(nil, {internal="YES"}, player:getPlayerNum(), bed)
        -- The game lies the survivor down by clearing the queue on arrival. Work
        -- that joined it on the way is somebody's; then there is no lying down.
        for _, action in ipairs(P.queueFor(player)) do
            local arrive = action.onCompleteFunc
            if arrive then
                action.onCompleteFunc = function(...)
                    if #P.queueFor(player) == 0 and state.active and state.excursion and state.excursion.stage == "bed" then return arrive(...) end
                end
            end
        end
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
    Recovery.bedFailed(player, state, now)
    return false
end

function Recovery.bedFailed(player, state, now)
    local try = state.bedTry
    state.bedTry = nil
    if not try or try.slept then return end
    state.bedsRejected = state.bedsRejected or {}
    state.bedsRejected[try.key] = now + bedRetryMs
    state.bedFails = (state.bedFails or 0) + 1
    if state.bedFails % 2 == 0 then state.bedsAt = now + bedRetryMs end -- the floor, for a while
    Log.event(player, "bed.unusable", "bed", try.key, "failed", state.bedFails)
end

-- ------------------------------------------------------------------- water

local function waterVessel(player, state, item)
    local fluid = Fluids.container(item)
    if not fluid or item:isSealed() or (Grid.favorite(item) and fluid:isEmpty()) then return nil end
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
    if not source then state.refillNext = now + 15000; return false end
    local queued = P.ownBatch(player, state, "refilling", "Filling " .. item:getDisplayName() .. ".", function()
        local action = ISTakeWaterAction:new(player, item, source.object, false)
        if not action:isValid() then return end
        -- A shared barrel may have changed by the time the bottle is under it.
        IntakeGuard.bind(action, function(self)
            local live = self.waterObject == source.object and WaterSources.inspect(player, source.object, source.part)
            return live and live.directDrink and not Fluids.allowTainted and waterVessel(player, state, item) ~= nil
        end, "transferFluid")
        if player:isSitOnGround() then ISTimedActionQueue.add(ISWaitWhileGettingUp:new(player)) end
        ISTimedActionQueue.add(action)
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
    P.pause(player, state, (reason or "Something went wrong.") .. " Autopilot stays on and tries again.", "setback")
end

function Recovery.notePath(state, target, failed)
    local player = state.player
    local square = player and player:getSquare()
    if not square then return end
    local here = Grid.key(square)
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
    Interject.settle(player, state, P.queueFor(player), now)
    local function report(id, problem, text)
        if problem then Alerts.raise(player, id, text, now, away or problem == "dying") else Alerts.clear(player, id) end
    end
    local level = Danger.read(player)
    report("danger", away and level == "engaged", "Zombies have found the survivor.")
    report("bleeding", Danger.bleeding(player) and state.aidNotice ~= nil, "Bleeding, and there is no bandage within reach.")
    state.needSince = state.needSince or {}
    for _, kind in ipairs({"water", "food"}) do
        local need = Needs.level(player, kind)
        local since = need >= 3 and (state.needSince[kind] or now) or nil
        state.needSince[kind] = since
        -- On the way to it, or already at it.
        local trip = state.excursion
        local busy = trip and trip.kind == kind and state.pending ~= nil or state.supplyKind == kind and state.pending ~= nil
        local short = since and not busy and not P.available(player, state, kind)
        -- There is something, and still nothing has happened for a while: a
        -- mask, a menu, a queue that never ends. Say so all the same.
        local stalled = since and now >= since and now - since >= stalledMs
        report(kind, (short or stalled) and (need >= 4 and "dying" or "short") or nil,
            kind == "water" and (short and "Very thirsty, and nothing safe to drink is within reach." or "Very thirsty, and not getting to drink.")
            or (short and "Very hungry, and there is nothing to eat within reach." or "Very hungry, and not getting to eat."))
    end
    local errors = state.errors
    if errors and now - errors.at > 120000 then state.errors = nil; Alerts.clear(player, "error") end
    if state.pathFails and not player:isPlayerMoving() then
        local square = player:getSquare()
        if square and state.pathFails.here ~= Grid.key(square) then
            Recovery.notePath(state, nil, false)
        end
    end
    report("boxed", state.boxedIn, "Cannot walk to any supply from here: closed doors, or a stuck spot.")
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
        local worst = outlook.issues[1]
        if not (worst and worst.severity >= 3) then Alerts.clear(player, "farewell")
        elseif state.farewell then Alerts.raise(player, "farewell", "Before you go: " .. worst.text, now, true) end
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
    Recovery.parkTrip(state)
    if Recovery.firstAid(player, state, now) then return end
    if Kitchen.urgent(player) and Kitchen.duty(player, state, now, false) then return end
    if state.guardAt and now >= state.guardAt and now - state.guardAt < guardMs then return end
    state.guardAt = now
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
    -- A cooked or burning dish comes before anything else; watching it does not.
    if Kitchen.urgent(player) and Kitchen.duty(player, state, now, true) then return end
    -- While something cooks, care uses what is carried or within reach: no trips away from the stove.
    -- Cooking comes before eating raw what could be cooked.
    if Kitchen.prefer(player, state, now) or not state.active then return end
    local cooking = Kitchen.lit(player)
    if cooking then state.carriedOnly = true end
    local cared = P.care(player, state)
    if cooking then state.carriedOnly = nil end
    if cared or not state.active then return end
    if Kitchen.meal(player, state, now) or not state.active then return end
    -- Another automation owns the survivor (Auto All's exercise, for one): only
    -- what cannot wait from here on. Optional work would hold the queue it waits on.
    local other = Coexist.owner(player)
    if other then
        if state.coexisting ~= other then Log.event(player, "coexist", "owner", other); state.coexisting = other end
        -- Short and needed: the toilet, leftovers kept cold, frozen food thawed, pain, sleep.
        if P.lifestyleCare(player, state, P.lifestyleReady(player, state, now), now) then return end
        if Kitchen.store(player, state, now) or not state.active then return end
        if Kitchen.thaw(player, state, now) or not state.active then return end
        if P.painAvailable(player, state, now) and P.supply(player, state, "pain") then return end
        if P.waitForSleep(player, state) then return end
        P.setPhase(state, "recovery-idle", other .. " is running. Autopilot steps in only for urgent needs.")
        return
    end
    if state.coexisting then Log.event(player, "coexist", "owner", "none"); state.coexisting = nil end
    if Kitchen.store(player, state, now) or not state.active then return end
    if Kitchen.thaw(player, state, now) or not state.active then return end
    local away = Presence.away(player, now)
    local calm = Recovery.permit(player, state, "posture", now)
    if P.lifestyleCare(player, state, P.lifestyleReady(player, state, now), now) then return end
    local pain = P.painAvailable(player, state, now)
    if pain and P.supply(player, state, "pain") then return end
    if Recovery.permit(player, state, "topUp", now) and P.earlySupply(player, state, true) then return end
    if Recovery.permit(player, state, "topUp", now) and Recovery.dressings(player, state, now) then return end
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
    -- Practice walks to the cupboards: the same permission as any other look around.
    if Options.searchNearby() and Recovery.permit(player, state, "explore", now) and Kitchen.practice(player, state, now) then return end
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
    if not Options.refill() or not Options.searchNearby() or state.excursion or Recovery.backingOff(state, now) then return false end
    if state.fetchNext and now < state.fetchNext and state.fetchNext - now <= bedRetryMs then return false end
    local item, room, carried = Recovery.bottle(player, state)
    if not item or carried >= 0.5 or not light(player, room) then return false end
    state.fetchNext = now + bedRetryMs
    local started = P.fetchWater(player, state)
    Log.event(player, "refill.trip", "carriedLiters", carried, "started", started)
    return started
end

return Recovery
