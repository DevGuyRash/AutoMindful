require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISReadABook"
require "TimedActions/ISDrinkFluidAction"
require "TimedActions/ISWaitWhileGettingUp"
require "ISUI/ISWorldObjectContextMenu"
local Supplies = require "AutoMindful/Supplies"
local Consumables = require "AutoMindful/Consumables"
local Needs = require "AutoMindful/SurvivalNeeds"
local WaterSources = require "AutoMindful/WaterSources"
local Progress = require "AutoMindful/Progress"
local TrainingCycle = require "AutoMindful/TrainingCycle"
local Decisions = require "AutoMindful/DecisionHistory"
local PracticeCare = require "AutoMindful/PracticeCare"
local WellnessInfo = require "AutoMindful/WellnessInfo"
require "AutoMindful/CompletionHUD"
local Fluids = require "AutoMindful/Fluids"
local Nearby = require "AutoMindful/Nearby"
local Storage = require "AutoMindful/Storage"
require "Vehicles/TimedActions/ISPathFindAction"
local Options = require "AutoMindful/Options"
local Tiers = require "AutoMindful/TierTargets"
local ActionYield = require "AutoMindful/ActionYield"
local MaskRestore = require "AutoMindful/MaskRestore"
local EnduranceGoal = require "AutoMindful/EnduranceGoal"
local PainCare = require "AutoMindful/PainCare"
local LifestyleCare = require "AutoMindful/LifestyleCare"
local ScoutMemory = require "AutoMindful/ScoutMemory"
local RouteOutcome = require "AutoMindful/RouteOutcome"
local SurvivalRoute = require "AutoMindful/SurvivalRoute"
local ScoutEgress = require "AutoMindful/ScoutEgress"
require "TimedActions/WalkToTimedAction"

AutoMindful = AutoMindful or {}
local Controller = {}
AutoMindful.Controller = Controller
local states = {}
local modeTitles = {both = "Training", meditation = "Meditation", yoga = "Yoga", endurance = "Endurance meditation",
    recovery = "Recovery", recoverEndurance = "Endurance recovery", meditateTo = "Meditation", yogaTo = "Yoga"}
local tierModes = {meditateTo="meditation", yogaTo="yoga"}
local tierAttempts, tierWorkMs, tierWaitingMs = 4, 480000, 480000
local recoveryTierMs = {[1]=90000, [2]=240000, [3]=420000}
local practiceClasses = {meditation="LSMeditateAction", yoga="LSYogaAction"}
local aimStopMessage = "Cancelled because you started aiming."
local homeCancel = "The return walk was cancelled. Start again when you are ready."
local homeRetryDelay, homeSettleTimeout, homeAttemptLimit = 750, 5000, 3
local unconfirmedSettleTimeout = 5000
local yogaBridgeMs, noXPGameHours, finalPracticeSampleMs = 30000, 6, 1500
local yogaEnduranceBridge = "yoga-endurance"
local minRecoveryPracticeMs = 5000
local careMenuWait = "Care is paused while the context menu is open. Close it to continue."
local careWindowWait = "Care is paused while a game window is open. Close it to continue."
local homeNoRoute = "The game found no path back to the original training spot after three attempts. Clear the route and start training again."

-- Persistent Recovery is more sensitive than a training interruption, but
-- distant care and unsolicited posture still need a useful quiet gap.
local recoveryPolicy={supplyAt=0.10,remainder=0.02,readAt=15,sitBelow=0.95,quietMs=2000,quietGapMs=1000}

local function stateFor(player)
    if not states[player] then
        states[player] = {active = false, loans = {}, phase = "idle", message = "Choose a training mode to begin."}
    end
    return states[player]
end

local function queueFor(player)
    return ISTimedActionQueue.getTimedActionQueue(player).queue
end

-- Called both by normal polling and at the native stop boundary. A real
-- Escape in the world is a stop; Escape dismissing an inspection is not.
local function sampleInspection(player, state, queue, now)
    if state.uiQueueHead ~= queue[1] or (state.paperMapOpen and player:pressedCancelAction()) then
        state.windowChecked = nil
    end
    state.uiQueueHead = queue[1]
    local wasInspecting = state.inspectingUI
    state.inspectingUI = ActionYield.inspecting(player, state, now)
    if not player:pressedCancelAction() then state.uiCancelHeld = nil
    elseif state.inspectingUI or wasInspecting then state.uiCancelHeld = true end
end

local function trainingPhase(phase)
    return phase == "meditation" or phase == "yoga"
end

local function isPractice(action, kind)
    local className = practiceClasses[kind]
    if not className or not action then return false end
    local class = _G[className]
    local expected = class and class.Type or className
    return action.Type == expected or (class and class.instanceof and class:instanceof(action, expected))
end

local function otherSkill(kind)
    return kind == "meditation" and "yoga" or "meditation"
end

local function playerRunIntent(player)
    -- Running/sprinting are engine animation flags, not evidence of player
    -- intent by themselves. Read the raw move axis even while a timed action
    -- blocks stepping, so a genuine held run is honored before displacement.
    return (player:isRunning() or player:isSprinting()) and player:pressedMovement(true)
end

local function stat(player, name)
    return player:getStats():get(CharacterStat[name])
end

local function levels(player)
    local meditation = Perks and Perks.Meditation and player:getPerkLevel(Perks.Meditation) or 0
    local yoga = HiddenSkills and HiddenSkills.getLevel and HiddenSkills.getLevel(player, "Yoga") or 0
    return meditation, yoga
end

local function atSkillGoal(player, state)
    if state.backgroundPractice or state.tierGoal then return false end
    local meditation, yoga = levels(player)
    return (state.mode == "yoga" or meditation >= 10) and (state.mode == "meditation" or yoga >= 10)
end

local function currentCyclePolicy(player)
    return TrainingCycle.normalizePolicy(Options.cyclePolicy and Options.cyclePolicy(player))
end

local function skillCounters()
    return {hoursWithoutXP=0, started=0, completed=0, positiveXPGains=0}
end

local function newCycle(player)
    local last = player:getModData().AutoMindfulLastCompleted
    if not practiceClasses[last] then last=nil end
    return {policy=currentCyclePolicy(player), lastCompleted=last, gates={},
        skills={meditation=skillCounters(), yoga=skillCounters()}}
end

local function setCycleDebt(cycle, kind)
    if kind ~= cycle.owed then
        cycle.owed, cycle.bridgeUsed = kind, nil
    end
end

local function completeTurn(player,state,kind)
    local cycle=state.cycle
    local completed,owed=TrainingCycle.complete(cycle.lastCompleted,cycle.owed,kind)
    cycle.lastCompleted=completed
    cycle.cooperativeKind,cycle.cooperativeTurns=nil,nil
    setCycleDebt(cycle,owed)
    player:getModData().AutoMindfulLastCompleted=completed
end

local function noteCycle(state, reason, preferred, selected)
    local cycle=state.cycle
    if not cycle then return end
    cycle.reason, cycle.preferred, cycle.nextKind = reason, preferred, selected
    local gate=cycle.gates.yoga
    local med=cycle.gates.meditation
    local message="mode="..state.mode.." policy="..cycle.policy.." reason="..reason
        .." due="..(cycle.owed or "none").." preferred="..(preferred or "none")
        .." next="..(selected or "none").." yogaGate="..(gate and gate.kind or "unknown")
        .." medGate="..(med and med.kind or "unknown").." bridge="..tostring(cycle.bridge == true)
    if cycle.logged ~= message then
        cycle.logged=message
        print("[AutoMindful] cycle: "..message)
    end
end

-- Only a matching owned practice (not its preparation or any foreign action)
-- can charge the no-XP clock or make a voluntary interruption productive.
local function observePractice(player, state, queue, now, final)
    local cycle, work = state.cycle, state.practiceWork
    if not cycle or not work then return end
    local head=queue[1]
    local running=head and head.autoMindfulOwner==state and isPractice(head,work.kind)
        and head:isStarted() and not head.autoMindfulStopped
    if running and not work.started then
        work.started, work.bridgeStartedAt = true, work.bridge and now or nil
        if work.bridge ~= yogaEnduranceBridge then cycle.skills[work.kind].started=cycle.skills[work.kind].started+1 end
    end
    -- A Yoga-only endurance wait is not Meditation training, even when its
    -- native action awards incidental XP. Rank 10 and zero XP are both valid.
    if work.bridge == yogaEnduranceBridge then return end
    if not running and not (final and work.started) then
        work.lastGameHours=nil
        return
    end
    local meter=cycle.skills[work.kind]
    if work.kind=="yoga" and work.settled then
        return meter.hoursWithoutXP > noXPGameHours and "yoga" or nil
    end
    local current=Progress.snapshot(player)[work.kind]
    -- A completed rank may still grant Fitness/Nimble or recovery effects,
    -- but waiting for XP in the capped target would trip a false watchdog.
    if state.backgroundPractice and current and current.capped then return end
    local gameHours=player:getHoursSurvived()
    local elapsed=0
    if work.lastGameHours and (running or (final and not head and work.lastSampleMs
            and now>=work.lastSampleMs and now-work.lastSampleMs<=finalPracticeSampleMs)) then
        -- Only a prompt final idle sample can close the last observed interval.
        elapsed=math.max(0,gameHours-work.lastGameHours)
    end
    work.lastGameHours=running and gameHours or nil
    work.lastSampleMs=running and now or nil
    if work.kind=="yoga" then
        local hours=TrainingCycle.observeYoga(meter,work,current,elapsed)
        return hours > noXPGameHours and work.kind or nil
    end
    local change=Progress.change(work.progress,current)
    if change and change.positive then
        work.productive=true
        meter.positiveXPGains=meter.positiveXPGains+1
        meter.hoursWithoutXP=0
    else
        meter.hoursWithoutXP=meter.hoursWithoutXP+elapsed
    end
    work.progress=current or work.progress
    return meter.hoursWithoutXP > noXPGameHours and work.kind or nil
end

local function stalledMessage(kind)
    if kind=="yoga" then
        return "Yoga retained no XP over six game hours of practice. Early stops can undo pose XP. Let a session finish or check Lifestyle XP settings."
    end
    return modeTitles[kind].." produced no XP for six game hours of practice. Check Lifestyle XP settings or server restrictions."
end

local function closePractice(state)
    state.practiceWork=nil
    if state.cycle then state.cycle.bridge=nil end
end

local function rotateAfterOpportunity(player,state,work)
    local cycle=state.cycle
    if cycle.policy=="alternate" and (not cycle.owed or cycle.owed==work.kind) then
        local med,yoga=levels(player)
        local nextSkill=otherSkill(work.kind)
        if state.backgroundPractice or (nextSkill=="meditation" and med<10) or (nextSkill=="yoga" and yoga<10) then
            setCycleDebt(cycle,nextSkill)
        end
    end
    cycle.cooperativeKind,cycle.cooperativeTurns=nil,nil
    state.trainingKind=nil
end

-- A real cooperative handoff can end partial practice without fabricating
-- native completion. Alternate gets one quiet same-leg retry before giving
-- the other skill a turn, even when repeated starts were too short for XP.
local function countOpportunity(player,state,work)
    local cycle=state.cycle
    if not cycle or state.mode~="both" or not work or not work.started or work.bridge then return end
    local pin=state.turnTier
    if pin and pin.kind==work.kind then
        local tier=Tiers.current(player,work.kind)
        if not tier or tier<pin.target then return end
        -- A pre-existing badge is not a completed practice. It also cannot
        -- keep an already satisfied minimum pinned forever.
        state.turnTier=nil
        if pin.addedDebt and cycle.owed==work.kind then setCycleDebt(cycle,nil) end
    end
    local exhausted=false
    if cycle.policy=="alternate" then
        cycle.cooperativeTurns=cycle.cooperativeKind==work.kind and (cycle.cooperativeTurns or 0)+1 or 1
        cycle.cooperativeKind=work.kind
        exhausted=cycle.cooperativeTurns>=2
    end
    if work.productive or exhausted then
        rotateAfterOpportunity(player,state,work)
    elseif work.kind=="yoga" and not state.backgroundPractice and not work.settled then
        -- Our release runs the early-stop penalty after this decision.
        -- One retained gain permits replanning; don't charge a second turn.
        work.recheckOpportunity=true
    end
end

local function yieldPractice(player, state, cooperative)
    local work=state.practiceWork
    if not work then return end
    if cooperative then
        observePractice(player,state,queueFor(player),getTimestampMs(),false)
        countOpportunity(player,state,work)
    end
    if work.bridge then state.trainingKind=nil end
    closePractice(state)
end

local function setPhase(state, phase, message, cause, nativeReason)
    if state.phase ~= phase or state.message ~= message then
        print("[AutoMindful] " .. phase .. ": " .. message)
    end
    state.phase, state.message = phase, message
    Decisions.transition(state, phase, cause, nativeReason)
end

local function clearOwned(player, state)
    state.pending = nil
    local done = ActionYield.release(player, state)
    state.releasePending = not done or nil
    return done
end

local function noteCareWait(state, message)
    if state.careWait ~= message then
        state.careWait = message
        print("[AutoMindful] care-wait: " .. message)
        Decisions.note(state, message==careMenuWait and "care-menu" or message==careWindowWait and "care-window" or "care-settle")
    end
end

local function breakForCare(player, state, message, reason)
    if reason then
        local course=state.practiceCare
        print("[AutoMindful] care-interrupt: mode=" .. tostring(state.mode) .. " phase=" .. tostring(state.phase)
            .. " practice=" .. tostring(course and course.kind or state.trainingKind) .. " trigger=" .. reason)
    end
    yieldPractice(player,state,true)
    state.careHandoff = true
    clearOwned(player, state)
    setPhase(state, "care", message)
end

local function showSessionEnd(player, state)
    local session = state.session
    if not session then return end
    state.session = nil
    local hud = PZActionCompletionHUD
    local detail = {hud.duration((getTimestampMs() - session.startedAt) / 1000)}
    if (state.endurance or state.recoveryFull) and state.endPhase == "complete" then detail[#detail+1] = "100% endurance" end
    if state.tierGoal and state.endPhase=="complete" then
        detail[#detail+1]=Tiers.label(state.tierGoal.kind,state.tierGoal.target) or "Requested tier"
    end
    local progress = Progress.snapshot(player)
    for _, kind in ipairs({"meditation", "yoga"}) do
        if state.mode == "both" or state.mode == kind then
            local before, after = session.progress[kind], progress[kind]
            local change = Progress.change(before, after)
            if change and change.amount then
                local sign = change.amount > 0 and "+" or ""
                table.insert(detail, sign .. Progress.number(change.amount) .. " " .. modeTitles[kind] .. " XP")
            elseif change and change.levels then
                table.insert(detail, string.format("%s level %d → %d", modeTitles[kind], before.level, after.level))
            end
        end
    end
    local stopped = state.endPhase == "stopped"
    hud.show(player:getPlayerNum(), {
        brand="AUTOMINDFUL", theme="mindful",
        title=modeTitles[state.mode] .. (stopped and " session stopped" or " session complete"),
        detail=table.concat(detail, " | "),
        status=state.endPhase, note=stopped and state.endMessage or nil,
    })
end

function Controller.stop(player, reason, cause, nativeReason)
    local state = stateFor(player)
    MaskRestore.observe(player,state.maskRestore,queueFor(player))
    state.active, state.trainingStopReason, state.trainingKind = false, nil, nil
    state.turnTier,state.recoveryTier,state.restroomDrain=nil,nil,nil
    closePractice(state)
    state.excursion, state.lifestyleCourse, state.lifestylePickup, state.practiceCare, state.mindfulnessWatch = nil, nil, nil, nil, nil
    state.yielding, state.idleSince, state.cycleUntil = nil, nil, nil
    state.careHandoff, state.careWait, state.careReleaseSince = nil, nil, nil
    if ActionYield.hasForeign(queueFor(player), state) then
        for _, loan in ipairs(state.loans) do loan.interference = true end
    end
    clearOwned(player, state)
    Supplies.finishLoan(player, state.supplyLoan)
    for _, loan in ipairs(state.loans) do loan.defer = nil end
    state.supplyItem, state.supplyKind, state.supplyLoan, state.supplySource = nil, nil, nil, nil
    state.supplyStop = nil
    state.supplyBaseline, state.preparation, state.collectingItem, state.fluidSupply = nil, nil, nil, nil
    state.endPhase, state.endMessage = "stopped", reason or "Stopped. Start again when you are ready."
    state.endCause, state.endNativeReason = cause, nativeReason
    setPhase(state, state.endPhase, state.endMessage, cause, nativeReason)
    showSessionEnd(player, state)
end

function Controller.setCollectNearby(player, enabled)
    local state = stateFor(player)
    state.collectNearby = not state.endurance and enabled == true
end

local function recordHomeStop(player, state, action)
    local trip = state.excursion
    if not state.active or not state.pending or not trip or trip.homeWalk ~= action or action.autoMindfulFinished then return false end
    if trip.homeStopRecorded == action then return true end
    trip.homeStopRecorded = action
    -- Stock movement/cancel can stop the action between controller ticks. Do
    -- not turn such a stop into another walk, even if the input was released.
    if player:isAiming() then
        trip.homeCancelled = aimStopMessage
    elseif playerRunIntent(player) then
        trip.homeCancelled = "Cancelled because you started running."
    elseif player:pressedCancelAction()
            and not (state.uiCancelHeld or state.inspectingUI or state.contextVisible) then
        trip.homeCancelled = homeCancel
    elseif player:pressedMovement(false) then
        -- A plain walk can interrupt the stock route before our next tick.
        -- Do not restart that route or turn it into a terminal cancellation.
        state.walkTakenOver = true
    elseif action.result ~= nil and action.result == BehaviorResult.Failed then
        trip.homeFailures = (trip.homeFailures or 0) + 1
        trip.homeRetrySince = getTimestampMs()
        trip.homeFailedWalk = action
        local moved = "unknown"
        if action.autoMindfulHomeStartX then
            local dx = player:getX() - action.autoMindfulHomeStartX
            local dy = player:getY() - action.autoMindfulHomeStartY
            moved = string.format("%.2f", math.sqrt(dx * dx + dy * dy))
        end
        -- Count and log here, including the final failure, before the stock
        -- stop clears the queue or the next tick disarms this session.
        print("[AutoMindful] homebound walk stopped: action=" .. tostring(action.Type)
            .. " path=Failed speed=" .. tostring(getGameSpeed())
            .. " attempt=" .. trip.homeFailures .. "/" .. homeAttemptLimit
            .. " aim=" .. (action.autoMindfulHomeAim or "stock-tile") .. " displacementTiles=" .. moved
            .. " from=" .. math.floor(player:getX()) .. ":" .. math.floor(player:getY())
            .. " to=" .. trip.origin.x .. ":" .. trip.origin.y .. ":" .. trip.origin.z)
    elseif not state.inspectingUI and not state.contextVisible then
        -- Ordinary yielding clears pending before doing its own stop. A
        -- different, unexplained native stop does not authorize another walk.
        trip.homeCancelled = homeCancel
    end
    return true
end

local function routeAction(action)
    return action and (action.Type == "ISWalkToTimedAction" or action.Type == "ISPathFindAction")
end

-- Compare ordinary-speed native walking, not sitting, care, or queue delay.
-- Start at the first native update since adding an action can start it
-- synchronously before AutoMindful can attach its per-instance observers.
local function timeScoutLeg(player,state,action)
    local trip=state.excursion
    local leg=trip and trip.stage
    if not trip or trip.indirect or not (trip.careTarget or trip.waterObject)
            or (leg~="outbound" and leg~="homebound") or not routeAction(action) then return end
    trip.walkTiming=trip.walkTiming or {}
    if trip.walkTiming[leg] then trip.walkTiming.invalid=true; return end
    local update,record=action.update,{}
    if type(update)~="function" then return end
    trip.walkTiming[leg]=record
    local function sample(a)
        if trip.walkTiming.invalid then return end
        local now=getTimestampMs()
        if state.excursion~=trip or trip.stage~=leg or queueFor(player)[1]~=a
                or state.contextVisible or state.inspectingUI or getGameSpeed()~=1
                or ActionYield.hasForeign(queueFor(player),state)
                or player:pressedMovement(false) or player:pressedCancelAction()
                or (record.last and (now<record.last or now-record.last>2000)) then
            trip.walkTiming.invalid=true
            return
        end
        record.start=record.start or now
        record.last=now
    end
    function action:update(...)
        sample(self)
        return update(self,...)
    end
    return function(method,a)
        if method=="stop" then trip.walkTiming.invalid=true
        elseif method=="perform" and record.start then
            sample(a)
            if not trip.walkTiming.invalid and record.last>record.start then
                record.ms=record.last-record.start
            end
        end
    end
end

local unsafeReason

-- Bind to the exact owned action while we still have its admission baseline.
-- Cooperative release clears state.practiceWork *before* invoking native stop.
-- Read after Lifestyle has applied its stop deduction, before the queue owner
-- hands over to a successor. Never ascribe that successor's XP/time to us.
local function yogaReceipt(player,state,work,method,original)
    return function(self,...)
        local bound=state.active and not work.settled and queueFor(player)[1]==self
            and (work.started or self:isStarted())
        if not bound then return original(self,...) end
        local meter=state.cycle.skills.yoga
        local before=Progress.yoga(player)
        local hours=player:getHoursSurvived()
        local elapsed=work.lastGameHours and math.max(0,hours-work.lastGameHours) or 0
        TrainingCycle.observeYoga(meter,work,before,elapsed)
        work.lastGameHours,work.closing=nil,true
        local result=original(self,...)
        work.closing=nil
        local head=queueFor(player)[1]
        local retained=work.terminalXP
        if retained then
            work.terminalXP=nil -- captured after Lifestyle's own award or penalty
        elseif not head or head==self then
            retained=Progress.yoga(player)
        elseif method=="perform" then
            -- Stock perform may synchronously start somebody else's action.
            -- Its pre-perform poses are now retained (no stop deduction);
            -- ignore an ambiguous bonus or change made by that successor.
            retained=before
        end
        TrainingCycle.settleYoga(meter,work,retained)
        if work.recheckOpportunity and work.productive then rotateAfterOpportunity(player,state,work) end
        if meter.hoursWithoutXP>noXPGameHours then state.stalledSkill="yoga" end
        return result
    end
end

-- The last walk (or native repair/flush) can finish just after a poll. Use
-- the first genuinely idle boundary before an idle floor-rest can interpose.
-- Never reenter over a foreign action or even our own unwinding Java handle.
function Controller.restroomBoundary(player,state,action)
    local trip,course=state.excursion,state.lifestyleCourse
    if not state.active or not ((trip and trip.kind=="restroom" and trip.stage=="outbound" and routeAction(action))
            or (course and course.before.preparation=="unclog")) or queueFor(player)[1] then return end
    state.lastUpdate=nil
    local native=player:getCharacterActions()
    if native:isEmpty() and not ActionYield.nativeBusy(player) then
        Controller.update(player) -- normal need, safety, input, access and posture gates
    elseif native:isEmpty() or (native:size()==1 and action.action and native:contains(action.action)) then
        state.restroomDrain={handle=action.action,batch=state.pending,at=getTimestampMs()}
    end
end

local function ownAction(player, state, action)
    if action.autoMindfulOwner == state then return end
    action.autoMindfulOwner = state
    state.pending[#state.pending + 1] = action
    if state.excursion and state.excursion.stage == "outbound" then RouteOutcome.observe(action) end
    local finishTiming=timeScoutLeg(player,state,action)
    local work=state.practiceWork
    local yogaAction=isPractice(action,"yoga")
    if yogaAction and action:isStarted() then action.autoMindfulYogaStartedAt=getTimestampMs() end
    local yoga=work and not state.backgroundPractice and work.kind=="yoga" and yogaAction
    if yoga then
        -- These instance-local hooks only observe Lifestyle's mutation. Stock
        -- base:perform can start another producer before perform() returns.
        for _,name in ipairs({"grantBonusXP","reduceXP"}) do
            local native=action[name]
            if native then
                action[name]=function(self,...)
                    local result=native(self,...)
                    if work.closing and queueFor(player)[1]==self then work.terminalXP=Progress.yoga(player) end
                    return result
                end
            end
        end
    end
    for _, method in ipairs({"start", "perform", "stop"}) do
        local original = action[method]
        if original then
            if yoga and method~="start" then original=yogaReceipt(player,state,work,method,original) end
            action[method] = function(self, ...)
                if method=="start" and yogaAction then
                    self.autoMindfulYogaStartedAt=getTimestampMs()
                    if yoga then work.entry=Progress.yoga(player) end
                end
                if finishTiming then finishTiming(method,self) end
                if method == "perform" then self.autoMindfulFinished = true end
                local pending, queue = state.pending, queueFor(player)
                if method == "stop" then
                    self.autoMindfulStopped = true
                    local yogaStarted=self.autoMindfulYogaStartedAt
                    if pending and state.active and queue[1]==self and yogaStarted
                            and getTimestampMs()-yogaStarted<1000 and self:isStarted()
                            and player:isSitOnGround() and not player:getVehicle()
                            and not player:pressedMovement(false) and not player:pressedCancelAction() then
                        self.autoMindfulPostureBounced=true
                        state.yogaPostureBounces=1+(state.yogaPostureBounces or 0)
                        state.standStableSince=nil
                        print("[AutoMindful] Yoga startup returned to floor sitting; bounce="..state.yogaPostureBounces)
                    end
                    if pending and state.active and state.recovery and queue[1]==self then
                        return Controller.recoveryNativeStop(player,state,queue,self,original,...)
                    end
                    -- Native cancellation can happen and the input be released
                    -- between polls. Latch real hard stops; never invent intent
                    -- for an unexpected cancellation. Even a plain stop can
                    -- append foreign work inside Lifestyle's callback, before
                    -- stock base:stop resets the entire queue. Defer handoff
                    -- until the original Java head drains in either case.
                    -- Our own Stop/care/yield clears pending before calling stop.
                    if pending and state.active and queue[1] == self and (trainingPhase(state.phase) or state.practiceCare) then
                        local stoppedAt = getTimestampMs()
                        self.autoMindfulNativeStoppedAt = stoppedAt
                        if self.Type == practiceClasses.yoga and state.actionStarted and stoppedAt-state.actionStarted < 1000 then
                            print("[AutoMindful] Yoga stopped during startup: started="..tostring(self:isStarted())
                                .." seated="..tostring(player:isSitOnGround())
                                .." gettingUp="..tostring(player.isGettingUp and player:isGettingUp() or false)
                                .." inVehicle="..tostring(player:getVehicle()~=nil))
                        end
                        sampleInspection(player, state, queue, stoppedAt)
                        if player:pressedMovement(false) then state.walkTakenOver=true end
                        state.trainingStopReason = state.trainingStopReason or unsafeReason(player, state)
                        return ActionYield.nativeStop(player, state, self, original, ...)
                    end
                    -- The stock walk invokes the base stop/reset on a native
                    -- failure. Reuse the deferred handoff only for a real
                    -- foreign successor, never start it over a draining Java head.
                    if recordHomeStop(player, state, self) and ActionYield.hasForeign(queue, state) then
                        self.autoMindfulHandoffTimeout = homeSettleTimeout
                        return ActionYield.nativeStop(player, state, self, original, ...)
                    end
                    -- Outbound pathing and masked care can stop between polls
                    -- too. A stock base stop resets its entire Lua queue.
                    -- Preserve even a successor appended within the callback.
                    local trip, mask = state.excursion, state.maskRestore
                    local outbound = state.active and state.phase=="travelling" and trip and trip.stage=="outbound"
                    if pending and queue[1]==self and (outbound or mask or state.lifestyleCourse and state.lifestyleCourse.before.preparation) then
                        local stoppedAt = getTimestampMs()
                        self.autoMindfulNativeStoppedAt = stoppedAt
                        MaskRestore.observe(player,mask,queue)
                        if outbound then
                            if routeAction(self) and RouteOutcome.failed(self)
                                    and not player:pressedMovement(false) and not player:pressedCancelAction() then
                                trip.outboundFailed=true
                            end
                        end
                        if state.active then
                            sampleInspection(player,state,queue,stoppedAt)
                            if player:pressedMovement(false) then state.walkTakenOver=true end
                            state.trainingStopReason = state.trainingStopReason or unsafeReason(player,state)
                        end
                        return ActionYield.nativeStop(player,state,self,original,...)
                    end
                end
                -- A foreign successor may begin and append its own children
                -- inside stock perform(). Those children are never ours.
                if not pending or ActionYield.hasForeign(queue, state) then return original(self, ...) end
                local before = {}
                for _, queued in ipairs(queue) do before[queued] = true end
                local result = original(self, ...)
                if state.pending == pending and method=="perform" and self.autoMindfulYogaStand then
                    local now=getTimestampMs()
                    state.yogaStandCompletedAt=now
                    state.standStableSince=not player:isSitting() and not player:isSitOnGround()
                        and not (player.isGettingUp and player:isGettingUp()) and now or nil
                end
                if state.pending == pending then
                    for _, queued in ipairs(queueFor(player)) do
                        if not before[queued] then ownAction(player, state, queued) end
                    end
                    if method=="perform" then Controller.restroomBoundary(player,state,self) end
                end
                return result
            end
        end
    end
end

function Controller.canShareMindfulnessWatch(state,phase)
    local watch=state.mindfulnessWatch
    return watch and ((watch.target=="hunger" and (trainingPhase(phase) or phase=="standing"))
        or (watch.target=="pain" and phase=="meditation"))
end

local function ownBatch(player, state, phase, message, addActions)
    local before = {}
    for _, action in ipairs(queueFor(player)) do before[action] = true end
    local mask = (phase=="drinking" or phase=="eating") and MaskRestore.capture(player) or nil
    local batch = {}
    state.pending = batch
    if not Controller.canShareMindfulnessWatch(state,phase) then
        if state.mindfulnessWatch and state.mindfulnessWatch.target=="hunger" then state.hungerAid=nil end
        state.mindfulnessWatch=nil
    end
    addActions()
    -- A synchronous callback may already have stopped or yielded this
    -- session. Never claim a replacement queue or reinstate its old phase.
    if state.pending ~= batch then return false end
    for _, action in ipairs(queueFor(player)) do
        if not before[action] then ownAction(player, state, action) end
    end
    if mask then
        local tracked = MaskRestore.track(mask,batch)
        if tracked then state.maskRestore,state.maskNotice=tracked,nil end
    end
    state.actionStarted = getTimestampMs()
    local queued=#state.pending>0
    setPhase(state, phase, message, not queued and trainingPhase(phase) and "admission-retry" or nil)
    return queued
end

function Controller.observeMaskRestore(player,state,queue)
    MaskRestore.observe(player,state.maskRestore,queue)
end

function Controller.restoreMask(player, state, now)
    if not state.maskRestore then return false end
    if player:pressedMovement(false) or #queueFor(player)>0 or ActionYield.nativeBusy(player) then return true end
    local status, action = MaskRestore.next(player,state.maskRestore,now)
    if status=="wait" then return true end
    if status=="wear" then
        if ownBatch(player,state,"restoring-mask","Putting the mask back on.",function() ISTimedActionQueue.add(action) end) then
            return true
        end
        status="manual"
    end
    state.maskRestore=nil
    if status=="manual" then state.maskNotice="AutoMindful could not safely restore the mask. Check your equipment." end
    return false
end

local function loanFor(player, state, item)
    for _, loan in ipairs(state.loans) do
        for _, candidate in ipairs(loan.items) do if candidate:getID() == item:getID() then return loan end end
    end
    local loan = Supplies.loan(player, item)
    if loan then state.loans[#state.loans + 1] = loan end
    return loan
end

local function returnBorrowed(player, state)
    state.returnNotice = nil
    for index = #state.loans, 1, -1 do
        local loan = state.loans[index]
        local action, notice, complete
        if not loan.defer then action, notice, complete = Supplies.returnAction(player, loan) end
        if complete then
            state.returnNotice = state.returnNotice or loan.notice
            table.remove(state.loans, index)
        elseif action then
            return ownBatch(player, state, "returning", "Returning borrowed supplies to their original source.", function()
                ISTimedActionQueue.add(action)
            end)
        else
            state.returnNotice = state.returnNotice or notice
        end
    end
    return false
end

local function needSleep(player)
    if isClient() and not getServerOptions():getBoolean("SleepNeeded") then return false end
    return stat(player, "FATIGUE") >= 0.6
end

-- Match the current stock floor Sleep menu, not raw panic or a presumed
-- animation state. The outer update already handles threats and foreign work.
local function sleepReadiness(player,state)
    if not needSleep(player) then return nil end
    if isClient() and not getServerOptions():getBoolean("SleepAllowed") then return "server" end
    if player:getHoursSurvived()-player:getLastHourSleeped()<=1 then return "cooldown" end
    if player:getSleepingTabletEffect()<2000 then
        local moodles=player:getMoodles()
        if moodles:getMoodleLevel(MoodleType.PAIN)>=2 and stat(player,"FATIGUE")<=0.85 then return "pain" end
        if moodles:getMoodleLevel(MoodleType.PANIC)>=1 then return "panic" end
        if MoodleType.NOXIOUS_SMELL and moodles:getMoodleLevel(MoodleType.NOXIOUS_SMELL)>=1 then return "smell" end
    end
    if player:getVariableBoolean("ExerciseStarted") or (FitnessState and player:isCurrentState(FitnessState.instance())) then
        return "exercise"
    end
    if ISWorldObjectContextMenu.sleepDialog then return "dialog" end
    if state.sleepDeclined then return "refused" end
    if player:getVariableBoolean("ExerciseEnded") then return "ready" end
    -- A fresh survivor can have no flag at all. The game's *outer* floor
    -- confirmation is its normal entry there; only stock owns initialization.
    if FitnessState and player:getVariableString("ExerciseEnded")==""
            and type(ISWorldObjectContextMenu.onConfirmSleep)=="function" then return "confirm" end
    return "exercise"
end

local function sleepAdmitted(reason)
    return reason=="ready" or reason=="confirm"
end

local function excursionMotion(player, state)
    if not state or not state.excursion then return false end
    if player:pressedMovement(false) or player:pressedCancelAction() then return false end
    local current = queueFor(player)[1]
    if current then return current.autoMindfulOwner == state and routeAction(current) end
    -- Native motion can outlive the queued walk by a frame at completion or path failure.
    if state.phase == "travelling" then
        for _, action in ipairs(state.pending or {}) do
            if routeAction(action) and (action.autoMindfulFinished or action.autoMindfulStopped) then return true end
        end
    end
    return false
end

unsafeReason = function(player, state)
    if state and state.trainingStopReason then return state.trainingStopReason end
    if player:isDead() then return "Stopped because the survivor died." end
    if player:isOnFire() then return "Stopped because the survivor is on fire." end
    if player:getVehicle() then return "Stopped because you entered a vehicle." end
    if not player:getSquare() then return "Stopped because the survivor has no loaded square." end
    if playerRunIntent(player) then return "Cancelled because you started running." end
    if player:pressedCancelAction() and not (state and state.uiCancelHeld) then return "Cancelled by your input." end
    if player:isAttacking() then return "Stopped because you started attacking." end
    if state and state.active then
        local walked=state.walkTakenOver or player:pressedMovement(false)
        local foreignMove=ActionYield.foreignMoving(player,queueFor(player),state)
        if walked or foreignMove then
            ActionYield.rememberPosition(state,player)
            if state.excursion then
                -- The player or a real foreign job took over movement. Do
                -- not pull them back to an old location after it finishes.
                state.excursion=nil
                state.walkTakenOver=true
            end
        elseif ActionYield.leftArea(state, player, excursionMotion(player, state)) then
            return "Cancelled because you moved unexpectedly or changed floor."
        end
    elseif player:isPlayerMoving() and (player:pressedMovement(false) or not ActionYield.nativeBusy(player)) then
        return "Stop moving before training."
    end
    if player:isAiming() then
        return state and aimStopMessage or "Stop aiming before starting training."
    end
    local inspecting = ActionYield.contextOpen(player)
    if state then state.contextVisible = inspecting end
    if player:pressedAim() and not inspecting and not (state and state.inspectingUI) then
        if not state then return "Stop aiming before starting training." end
        local now = getTimestampMs()
        if not state.aimStarted or now < state.aimStarted then state.aimStarted = now end
        if now - state.aimStarted >= 500 then return aimStopMessage end
    elseif state then state.aimStarted = nil end
    if player:isDraggingCorpse() then return "Stop dragging the corpse before training." end
    local stats = player:getStats()
    if stats:getNumVisibleZombies() > 0 or stats:getNumChasingZombies() > 0
            or stats:getNumVeryCloseZombies() > 0 then return "Stopped because zombies are nearby." end
    if player:getBodyDamage():getNumPartsBleeding() > 0 then return "Stopped because you are bleeding. Treat the wound first." end
end

-- Recovery is ordinarily background help, not a claim on the character.
-- Separate a real request to end it from a temporary reason not to act.
function Controller.recoveryInterruption(player,state,queue)
    if state.trainingStopReason then return state.trainingStopReason,"stop" end
    if player:isDead() then return "Stopped because the survivor died.","stop" end
    local priorContext=state.contextVisible
    state.contextVisible=ActionYield.contextOpen(player)
    if player:pressedCancelAction() then
        if priorContext or state.contextVisible then state.uiCancelHeld=true end
        if not state.uiCancelHeld then return "Cancelled by your input.","stop" end
    end

    local square=player:getSquare()
    local walking
    if square then
        local ownWalk=excursionMotion(player,state)
        walking=player:pressedMovement(true) or state.walkTakenOver or ActionYield.foreignMoving(player,queue,state)
            or (player:isPlayerMoving() and not ownWalk) or ActionYield.leftArea(state,player,ownWalk)
        if walking then
            ActionYield.rememberPosition(state,player)
            state.excursion,state.walkTakenOver=nil,nil
        end
    else
        state.motionZ=nil
    end

    local unsafe
    if not square then unsafe="the survivor's area is not loaded"
    elseif player:isOnFire() then unsafe="the survivor is on fire"
    elseif player:getVehicle() then unsafe="the survivor is in a vehicle"
    else
        local stats, body=player:getStats(),player:getBodyDamage()
        if stats:getNumVisibleZombies()>0 or stats:getNumChasingZombies()>0 or stats:getNumVeryCloseZombies()>0 then
            unsafe="zombies are nearby"
        elseif body:getNumPartsBleeding()>0 then unsafe="the survivor is bleeding" end
    end
    if unsafe then
        state.excursion=nil
        return "Recovery paused: "..unsafe..".", "recovery-danger"
    end
    if walking then return "Recovery is waiting for your movement to settle.","walking" end
    if player:isAiming() or (player:pressedAim() and not state.contextVisible and not state.inspectingUI) then
        return "Recovery is waiting for you to stop aiming.","manual-input"
    end
    if player:isAttacking() then return "Recovery is waiting for your attacks to finish.","manual-input" end
    if player:isDraggingCorpse() then return "Recovery is waiting for you to finish moving the corpse.","manual-input" end
    if state.uiCancelHeld then return "Recovery is waiting for your game window to close.","inspection-open" end
end

function Controller.recoveryNativeStop(player,state,queue,action,original,...)
    local now=getTimestampMs()
    action.autoMindfulNativeStoppedAt=now
    MaskRestore.observe(player,state.maskRestore,queue)
    sampleInspection(player,state,queue,now)
    local reason,cause=Controller.recoveryInterruption(player,state,queue)
    if cause=="stop" then state.trainingStopReason=reason
    elseif reason then state.recoveryInterrupted={reason=reason,cause=cause}
    else
        local trip=state.excursion
        if trip and state.phase=="travelling" then
            if routeAction(action) and RouteOutcome.failed(action) then
                if trip.homeWalk==action then recordHomeStop(player,state,action)
                elseif trip.stage=="outbound" then trip.outboundFailed=true end
            else
                -- No known path failure or intentional Stop. Do not restart a
                -- walk we can't account for, but keep Recovery available.
                state.excursion=nil
                state.recoveryInterrupted={reason="Recovery is waiting for the interrupted walk to settle.",cause="settling-action"}
            end
        end
    end
    -- Diet, paperwork, and posture actions can also receive native stops.
    -- Preserve other work, including a successor appended inside stock stop.
    return ActionYield.nativeStop(player,state,action,original,...)
end

local wellnessDisabled = "Lifestyle Wellness is disabled in this world."
local function available(player, mode)
    if not Tiers.wellnessEnabled() and mode ~= "recovery" and mode ~= "recoverEndurance" then
        return false, wellnessDisabled
    end
    local data = player:getModData()
    local options = ZenWellnessContextMenu and ZenWellnessContextMenu.Options
    if not options or not options.Meditation or not options.Meditation.canPerform or not options.Meditation.onAction
            or not options.Yoga or not options.Yoga.canPerform or not options.Yoga.onAction
            or not HiddenSkills or not HiddenSkills.getSkill or not Perks or not Perks.Meditation then
        return false, "Enable Lifestyle: Hobbies with yoga support before starting AutoMindful."
    end
    if not data.LSMoodles or not data.LSMoodles.Embarrassed or not data.LSMoodles.MindfulState
            or not data.LSMoodles.WasTaughtSkill or not data.LSMoodles.Zen then
        return false, "Waiting for Lifestyle to initialize this survivor. Try starting again in a moment."
    end
    return true
end

local function yogaGate(player)
    if not Tiers.wellnessEnabled() then return false, wellnessDisabled end
    local blocked, message = ZenWellnessContextMenu.Options.Yoga.canPerform(player, "", nil)
    return not blocked, message
end

local function meditationGate(player)
    if not Tiers.wellnessEnabled() then return {ready=false, kind="blocked", reason=wellnessDisabled} end
    local blocked, message = ZenWellnessContextMenu.Options.Meditation.canPerform(player, "", nil)
    if not blocked then return {ready=true, kind="ready"} end
    local bored=getText("ContextMenu_Meditate_Bored")
    return {ready=false,reason=message,kind=(message==bored or message==" <RED>"..bored) and "boredom" or "blocked"}
end

local function yogaAdmission(player)
    local ready, message=yogaGate(player)
    if ready then return {ready=true,kind="ready"} end
    local kind=message==getText("Tooltip_Action_Exhausted") and "endurance"
        or message==getText("ContextMenu_Embarrassed") and "embarrassment"
        or message==getText("Tooltip_Yoga_MissingMat") and "mat" or "blocked"
    return {ready=false,reason=message,kind=kind,temporary=kind=="endurance" or kind=="embarrassment"}
end

local function leaveFurniture(player, state)
    if player:getModData().IsSittingOnSeat then
        setPhase(state, "seated", "Waiting for your seat activity to end. Stand up normally if needed.")
        return false
    end
    if not player:isSittingOnFurniture() then return true end
    if state.furnitureAttempted then
        Controller.stop(player, "Could not get up from the furniture. Stand up normally and try again.")
    else
        state.furnitureAttempted = true
        ownBatch(player, state, "standing", "Getting up from the furniture before training.", function()
            ISTimedActionQueue.add(ISWaitWhileGettingUp:new(player))
        end)
    end
    return false
end

local function sit(player, state)
    if not leaveFurniture(player, state) then return false end
    state.furnitureAttempted = nil
    if player:isSitOnGround() then return true end
    if state.phase ~= "sitting" then
        player:reportEvent("EventSitOnGround")
        state.postureStarted = getTimestampMs()
        setPhase(state, "sitting", "Sitting down for recovery or meditation.")
    elseif getTimestampMs() - state.postureStarted > 15000 then
        Controller.stop(player, "Could not sit down here. Choose clear ground and start again.")
    end
    return false
end

local function stand(player, state, message)
    local now = getTimestampMs()
    local gettingUp = player.isGettingUp and player:isGettingUp()
    if gettingUp then
        -- The stock stand action can complete before PlayerGetUpState exits.
        -- Lifestyle's timed action must not contend with that animation.
        state.standTransitionSince = state.standTransitionSince or now
        state.standStableSince = nil
        if now - state.standTransitionSince > 15000 then
            Controller.stop(player, "Could not finish standing up. Move to clear ground and start again.")
        else
            setPhase(state, "standing", "Waiting for the game to finish standing up.")
        end
        return false
    end
    if state.standTransitionSince then
        if not player:isSitting() then
            state.standStableSince = state.standStableSince or now
            if now - state.standStableSince < 120 then return false end
        end
        state.standTransitionSince, state.standStableSince = nil, nil
    end
    if not message then
        local seated=player:isSitting() or player:isSitOnGround() or player:isSittingOnFurniture()
        local recent=state.yogaStandCompletedAt
        local repeated=(state.yogaPostureBounces or 0)>=2
        if recent or repeated then
            if seated then state.standStableSince=nil
            else state.standStableSince=state.standStableSince or now end
            local settled=state.standStableSince and now-state.standStableSince>=(repeated and 500 or 180)
            if not settled and (not seated or repeated or now-recent<750) then
                setPhase(state,repeated and "recovering" or "standing",
                    repeated and "Yoga is waiting for a stable standing posture. Stand normally when ready."
                    or "Waiting for the standing posture to settle before Yoga.")
                return false
            end
            state.yogaStandCompletedAt,state.standStableSince=nil,nil
        end
        if player:isSitOnGround() and not player:isSitting() then
            setPhase(state,"recovering","Waiting for the game's floor-sitting and standing states to agree before Yoga.")
            return false
        end
    end
    if not leaveFurniture(player, state) then return false end
    state.furnitureAttempted = nil
    if not player:isSitting() and (message or not player:isSitOnGround()) then return true end
    ownBatch(player, state, "standing", message or "Standing up for yoga.", function()
        local action=ISWaitWhileGettingUp:new(player)
        if not message then action.autoMindfulYogaStand=true end
        ISTimedActionQueue.add(action)
    end)
    return false
end

local function restForYoga(player, state, reason)
    if sit(player, state) then
        setPhase(state, "resting", "Resting until Lifestyle's endurance requirement for yoga is met.", "yoga-gate", reason)
    end
end

local function resetSupply(state)
    if state.fluidSupply then
        for _, loan in ipairs(state.fluidSupply.loans) do loan.defer = nil end
    end
    state.fluidSupply = nil
    state.supplyItem, state.supplyKind, state.supplyLoan, state.supplySource = nil, nil, nil, nil
    state.supplyStop = nil
    state.supplyBaseline, state.awaitSupplyUntil, state.preparation, state.supplyGoal = nil, nil, nil, nil
end

local function yieldToPlayer(player, state, unexplained, walking, settling, pauseReason, pauseCause)
    local cause=pauseCause or walking and "walking" or state.inspectingUI and "inspection-open"
        or unexplained and "interrupted" or settling and "settling-action" or "current-action"
    local entering = not state.yielding
    if entering then
        local tier=state.tierGoal or state.turnTier
        if tier then tier.head,tier.sampleAt,tier.waitAt=nil,nil,nil end
        local strict=state.recoveryTier
        if strict then strict.head,strict.sampleAt,strict.launchAt=nil,nil,nil end
        if not unexplained and not walking and state.cooperativePending then
            countOpportunity(player,state,state.cooperativePending.opportunity)
        end
        yieldPractice(player,state,not unexplained and not walking)
        state.yielding = true
        if state.practiceCare then state.practiceCareNext=getTimestampMs()+120000 end
        for _, loan in ipairs(state.loans) do loan.interference, loan.defer = true, nil end
        Supplies.finishLoan(player, state.supplyLoan)
        PainCare.detach(player, state, getTimestampMs())
        resetSupply(state)
        state.collectingItem, state.contextInterrupted, state.travelScan = nil, nil, nil
        state.lifestyleCourse, state.lifestylePickup, state.lifestyleScan, state.practiceCare, state.mindfulnessWatch = nil, nil, nil, nil, nil
        state.utilityTierRetry=nil
        if state.hungerAid and not state.hungerAid.failed then state.hungerAid=nil end -- discard ambiguous player-work baselines
        state.furnitureAttempted, state.cycleUntil, state.cooperativePending = nil, nil, nil
        state.standTransitionSince, state.standStableSince = nil, nil
        state.careNeeds = {}
        -- Keep the exact way home and any real failure budget, never the old
        -- care target, item or portion. A failed walk is retained as read-only
        -- evidence of the draining Java handle, not an action to replay.
        local trip = state.excursion
        if trip and trip.egressPlan then
            state.excursion=nil
        elseif trip then
            if trip.outboundFailed then
                Controller.forgetScoutStop(state,trip.target)
                if SurvivalRoute.known(trip.target,trip.kind) then
                    Controller.rejectScoutPath(state,trip,getTimestampMs(),"native-failed-before-yield")
                else state.travelRejected[trip.target.key]=(trip.careTarget or trip.waterObject) and getTimestampMs()+15000 or true end
            end
            state.excursion = {origin=trip.origin, stage="resume-home", homeFailures=trip.homeFailures,
                homeRetrySince=trip.homeRetrySince, homeFailedWalk=trip.homeFailedWalk,
                homeStopRecorded=trip.homeStopRecorded}
        end
        Nearby.invalidate(player)
        if state.active then
            if state.recovery then
                setPhase(state,cause=="recovery-danger" and "recovery-paused" or "manual",
                    pauseReason or "Waiting for your action. Recovery stays on in the background.",cause)
            else
                setPhase(state, "manual", unexplained and "Training was interrupted. Checking before resuming."
                    or "Waiting for your action. Training will resume when you are ready.", cause)
            end
        end
    elseif state.active and state.recovery and (pauseReason or state.phase=="recovery-paused" or state.pauseNotice) then
        setPhase(state,cause=="recovery-danger" and "recovery-paused" or "manual",
            pauseReason or "Waiting for your action. Recovery stays on in the background.",cause)
    elseif state.active and state.phase=="manual" then
        Decisions.transition(state,"manual",cause)
    end
    state.pauseNotice=pauseReason
    state.idleSince = nil
    if state.endurance then EnduranceGoal.observe(state.endurance, nil, getTimestampMs(), false) end
    if entering or state.pending or state.releasePending then clearOwned(player, state) end
end

function Controller.pauseRecovery(player,state,reason,cause)
    -- The normal poll's dose observation is below this early return. Apply
    -- the same foreign-pill veto before yielding can detach a dose receipt.
    local now=getTimestampMs()
    PainCare.observeForeign(player,state,queueFor(player),now)
    PainCare.observe(player,state,now)
    state.careHandoff,state.careWait,state.careReleaseSince=nil,nil,nil
    yieldToPlayer(player,state,false,cause=="walking",false,reason,cause)
end

function Controller.recoveryYields(player,state,queue)
    local reason,cause=Controller.recoveryInterruption(player,state,queue)
    local interrupted=state.recoveryInterrupted
    state.recoveryInterrupted=nil
    if not reason and interrupted then reason,cause=interrupted.reason,interrupted.cause end
    if not reason then return false end
    if cause=="stop" then Controller.stop(player,reason)
    else Controller.pauseRecovery(player,state,reason,cause) end
    return true
end

local function fluidSourceKey(source)
    return source.worldSource and source.worldSource.object or source.item:getID()
end

local function abandonFluid(state, message, rejectedKey)
    local flow = state.fluidSupply
    if flow then state.rejected[rejectedKey or fluidSourceKey(flow.source)] = getTimestampMs() + 60000 end
    state.fluidNotice = message
    state.supplyMissingReason = message
    state.pending = nil
    resetSupply(state)
    return false
end

local function currentFluidSource(player, source)
    if source.worldSource then
        local world, reason = WaterSources.inspect(player, source.worldSource.object, source.worldSource.part)
        if not world then return nil, reason or "The bulk liquid is no longer safe or reachable." end
        return {worldSource = world, item = world.item, owned = false, description = world.description}
    end
    local item = Supplies.inventoryItem(player, source.item)
    if not item or item:getContainer() ~= player:getInventory() then return nil, "The bulk liquid could not be collected." end
    return {item = item, owned = true, description = Consumables.inspect(player, item)}
end

local function queueFluidTransfer(player, state)
    local flow = state.fluidSupply
    if flow.source.worldSource and not (state.collectNearby or Options.searchNearby() or state.excursion ~= nil) then
        return abandonFluid(state, "Nearby collection was disabled before the liquid transfer.")
    end
    local source, reason = currentFluidSource(player, flow.source)
    if not source then return abandonFluid(state, reason) end
    local vessel = Supplies.inventoryItem(player, flow.vessel.item)
    if not vessel or vessel:getContainer() ~= player:getInventory() then
        return abandonFluid(state, "The drinking vessel could not be collected.", flow.vessel.item:getID())
    end
    local candidate, unavailable = Supplies.transferPlan(player, source, {item = vessel, owned = true}, flow.kind)
    if not candidate then return abandonFluid(state, unavailable or "The liquid can no longer be transferred into this vessel.") end
    local sourceFluid = source.description.fluid
    local targetFluid = Fluids.container(vessel)
    flow.source, flow.vessel.item = source, vessel
    if state.supplyStop then
        flow.sourceAmountBefore, flow.vesselAmountBefore = sourceFluid:getAmount(), targetFluid:getAmount()
    end
    flow.before = {hunger = stat(player, "HUNGER"), thirst = stat(player, "THIRST")}
    flow.phase = "transferring"
    local queued = ownBatch(player, state, "transferring", "Pouring the needed liquid into a drinking vessel.", function()
        local used, failure = Fluids.transfer(player, sourceFluid, targetFluid, candidate.transfer.amount, function()
            if source.worldSource and not (state.collectNearby or Options.searchNearby() or state.excursion ~= nil) then return false end
            local target = Supplies.inventoryItem(player, vessel)
            if not target or target:getContainer() ~= player:getInventory() or Fluids.container(target) ~= targetFluid then return false end
            local current = currentFluidSource(player, source)
            return current and current.description.fluid == sourceFluid
        end)
        if not used then reason = failure end
    end)
    if not queued then return abandonFluid(state, reason or "The native liquid transfer could not start.") end
    return true
end

local function beginFluidSupply(player, state, transfer)
    local flow = {source = transfer.source, vessel = transfer.vessel, kind = transfer.kind,
        loans = {}, phase = "collecting"}
    state.fluidSupply, state.fluidNotice = flow, nil
    state.supplyItem, state.supplyLoan, state.supplySource, state.collectingItem = nil, nil, nil, nil
    state.supplyKind, state.supplyBaseline = flow.kind, nil
    local items = {}
    if not flow.source.worldSource then items[#items + 1] = flow.source.item end
    items[#items + 1] = flow.vessel.item
    local collecting, guardedSource = {}
    for _, item in ipairs(items) do
        local loan = loanFor(player, state, item)
        if loan then
            loan.defer = true
            flow.loans[#flow.loans + 1] = loan
            if item:getID() == flow.vessel.item:getID() then flow.vesselLoan = loan end
            if state.supplyStop and item==flow.source.item then guardedSource=loan end
        end
        if item:getContainer() ~= player:getInventory() then collecting[#collecting + 1] = item end
    end
    if #collecting == 0 then return queueFluidTransfer(player, state) end
    if not ownBatch(player, state, "collecting", "Collecting the bulk liquid and empty drinking vessel as needed.", function()
        for _, item in ipairs(collecting) do
            Supplies.transfer(player,item,item==flow.source.item and guardedSource or nil)
        end
    end) then return abandonFluid(state, "Make room to collect the liquid or its drinking vessel.") end
    return true
end

local function finishFluidPreparation(player, state, failed, now)
    local flow = state.fluidSupply
    if flow.phase == "collecting" then
        if queueFluidTransfer(player, state) then return "pending" end
        return "finished"
    end
    local vessel = Supplies.inventoryItem(player, flow.vessel.item)
    if not vessel then
        abandonFluid(state, "The filled drinking vessel is no longer in your inventory.", flow.vessel.item:getID())
        return "finished"
    end
    local fluid = Fluids.container(vessel)
    local safe, reason
    if fluid then safe, reason = Fluids.safe(fluid) end
    if not safe then
        abandonFluid(state, reason or "The filled vessel is unsafe; its contents were preserved instead of consumed.", vessel:getID())
        return "finished"
    end
    local need = stat(player, flow.kind == "food" and "HUNGER" or "THIRST")
    if need <= Consumables.restoredThreshold then
        state.failures = 0
        state.pending = nil
        resetSupply(state)
        return "finished"
    end
    if fluid:isEmpty() then
        local before = flow.kind == "food" and flow.before.hunger or flow.before.thirst
        if need < before then
            state.failures = 0
            state.pending = nil
            resetSupply(state)
        elseif not failed and now < (flow.awaitUntil or now + 3000) then
            flow.awaitUntil = flow.awaitUntil or now + 3000
            return "pending"
        else abandonFluid(state, "The game did not confirm usable liquid in the drinking vessel.") end
        return state.fluidSupply and "pending" or "finished"
    end
    local description = Consumables.inspect(player, vessel)
    if not description[flow.kind] or description.needsOpening or description.needsVessel then
        abandonFluid(state, description.reason or "The filled vessel cannot restore the required need.", vessel:getID())
        return "finished"
    end
    if state.supplyStop and not failed and flow.sourceAmountBefore and flow.vesselAmountBefore then
        local donor=flow.source.description.fluid
        flow.verifiedStop=donor and donor:getAmount()<flow.sourceAmountBefore
            and fluid:getAmount()>flow.vesselAmountBefore
    end
    flow.phase, state.pending = "using", nil
    return "consume", vessel, flow.vesselLoan
end

local function wantsPainCare(player, state, now)
    local wanted, reason = PainCare.wanted(player, state, now)
    if reason then
        state.painNotice, state.painNoticeUntil = reason, nil
    elseif not wanted and (not state.painNoticeUntil or now >= state.painNoticeUntil) then
        state.painNotice = nil
    end
    return wanted
end

local function usePainkiller(player, state, item, loan)
    local now = getTimestampMs()
    local permitted = Supplies.painLoanAllowed(player, loan, state.collectNearby or Options.searchNearby())
    if not wantsPainCare(player, state, now) or not PainCare.eligible(item) or not permitted then
        if not permitted then state.painNotice = "Borrowed Painkillers are no longer permitted; returning them if possible." end
        if loan then loan.defer = nil end
        resetSupply(state)
        return false
    end
    state.supplyItem, state.supplyKind, state.supplyLoan = item, "pain", loan
    if loan then loan.defer = true end
    Supplies.watchLoan(player, loan, item)
    local started, reason
    local queued = ownBatch(player, state, "paincare", "Taking one dose of stock Painkillers.", function()
        started, reason = PainCare.queue(player, state, item, now)
    end)
    if not started then state.painNotice = reason or "The game did not start pain relief." end
    if queued then return true end
    -- No native action was added. Never claim a dose, or retry an ambiguous
    -- submission: PainCare keeps a distinct guard for each survivor.
    state.painNextScan, state.pending = now + 5000, nil
    if loan then loan.defer = nil end
    resetSupply(state)
    return false
end

local function useSupply(player, state, kind, item, loan)
    if kind == "pain" then return usePainkiller(player, state, item, loan) end
    local descriptor = Consumables.inspect(player, item, state.collectNearby or Options.searchNearby() or state.excursion ~= nil)
    if kind ~= "literature" and not descriptor[kind] then
        state.rejected[item:getID()] = getTimestampMs() + 60000
        state.supplyMissingReason = descriptor.reason or "This supply is no longer usable."
        if loan then loan.defer = nil end
        resetSupply(state)
        return false
    end
    state.supplyItem, state.supplyKind, state.supplyLoan = item, kind, loan
    if loan then loan.defer = true end
    local queued
    if kind ~= "literature" and descriptor.needsVessel and not descriptor.needsOpening then
        local candidate, reason = Supplies.chooseTransfer(player, {item = item, owned = true, description = descriptor}, kind,
            state.collectNearby or Options.searchNearby() or state.excursion ~= nil, state.rejected)
        if candidate then return beginFluidSupply(player, state, candidate.transfer) end
        state.fluidNotice = reason or "Bring a clean empty drinking vessel for the bulk liquid."
        state.rejected[item:getID()] = getTimestampMs() + 60000
        if loan then loan.defer = nil end
        resetSupply(state)
        return false
    elseif kind ~= "literature" and descriptor.needsOpening then
        local tools = {}
        for _, tool in ipairs(descriptor.returnItems) do
            local borrowed = loanFor(player, state, tool)
            if borrowed then borrowed.defer = true; tools[#tools + 1] = borrowed end
        end
        state.preparation = {item = item, descriptor = descriptor, before = Supplies.inventoryIDs(player), loan = loan, kind = kind, tools = tools}
        queued = ownBatch(player, state, "preparing", "Opening " .. item:getDisplayName() .. " with the game's available tools.", function()
            Consumables.prepare(player, item, descriptor)
        end)
    else
        state.supplyBaseline = {hunger = stat(player, "HUNGER"), calories = player:getNutrition():getCalories(),
            thirst = stat(player, "THIRST"), boredom = stat(player, "BOREDOM")}
        Supplies.watchLoan(player, loan, item)
        if kind == "literature" then
            queued = ownBatch(player, state, "reading", "Reading " .. item:getDisplayName() .. " to relieve boredom.", function()
                ISTimedActionQueue.add(ISReadABook:new(player, item))
            end)
        else
            queued = ownBatch(player, state, kind == "food" and "eating" or "drinking", "Using " .. item:getDisplayName() .. ".", function()
                local _, goal = Consumables.consume(player, item, kind)
                if type(goal) == "table" then state.supplyGoal = goal end
            end)
        end
    end
    if not queued then Controller.stop(player, "The game could not start using " .. item:getDisplayName() .. ". Check its tools and action requirements.") end
    return true
end

local function sameSquare(a, b)
    return a and b and a:getX() == b:getX() and a:getY() == b:getY() and a:getZ() == b:getZ()
end

local function atOrigin(square, origin)
    return square and origin and square:getX() == origin.x and square:getY() == origin.y and square:getZ() == origin.z
end

local function rememberOrigin(player, square)
    local origin = {x=square:getX(), y=square:getY(), z=square:getZ()}
    -- Preserve only a real foot position strictly inside this same tile.
    -- A furniture pose or stair elevation is not known walkable ground.
    if not player:isSittingOnFurniture() and not player:getModData().IsSittingOnSeat
            and player:getZ() == origin.z then
        local x, y = player:getX(), player:getY()
        if x > origin.x and x < origin.x + 1 and y > origin.y and y < origin.y + 1
                and (math.abs(x - origin.x - 0.5) > 0.001 or math.abs(y - origin.y - 0.5) > 0.001) then
            origin.pointX, origin.pointY = x, y
        end
    end
    return origin
end

local function resolveOrigin(origin)
    local cell = getCell()
    local square = origin and cell and cell:getGridSquare(origin.x, origin.y, origin.z)
    return atOrigin(square, origin) and square or nil
end

local function vehicleTargetAvailable(player, target)
    if not target.part then return true end
    local vehicle, area = Storage.vehiclePart(target.part)
    return vehicle and sameSquare(area, target.square) and Storage.permitted(player, area)
        and Storage.permitted(player, vehicle:getSquare())
end

local function prepareScoutWalk()
    -- Build 42 refuses to start a native walking action above speed 2.
    if not isClient() and getGameSpeed() > 2 then
        local controls = UIManager.getSpeedControls()
        if controls then controls:SetCurrentGameSpeed(1) end
    end
end

function Controller.scoutedStorageAllowed(player,target)
    return ScoutMemory.liveStorage(target) and Storage.permitted(player,target.square)
        and (not instanceof(target.object,"IsoThumpable") or not target.object:isLockedToCharacter(player))
end

function Controller.rejectScoutPath(state,trip,now,reason)
    local policy=SurvivalRoute.reject(state.travelRejected,trip.target,trip.kind,now)
    print("[AutoMindful] route-skip: need=" .. tostring(trip.kind) .. " source=" .. tostring(trip.target.key)
        .. " reason=" .. (reason or "native-path-failed") .. " retry=" .. policy)
end

function Controller.forgetScoutStop(state,target)
    ScoutMemory.forget(state.scoutMemory,target)
end

function Controller.abandonStalledSupply(player,state,now)
    local trip=state.excursion
    if not trip or trip.stage~="outbound" or trip.egressPlan or not SurvivalRoute.known(trip.target,trip.kind) then return false end
    Controller.forgetScoutStop(state,trip.target)
    Controller.rejectScoutPath(state,trip,now,"no-movement-progress")
    trip.stage="care" -- settle this owned walk; use the ordinary safe home/idle boundary
    state.travelScan=nil
    state.careNotice="The supply walk made no progress. Checking other care options."
    clearOwned(player,state)
    return true
end

local function learnedStop(player,state,kind,square,radius,now,onlyWorldWater)
    if not state.scoutMemory then return end
    return ScoutMemory.choose(state.scoutMemory,kind,square,radius,now,function(_,object,sourceSquare,container,suffix)
        local key=kind..":"..sourceSquare:getX()..":"..sourceSquare:getY()..":"..sourceSquare:getZ()..(suffix or "")
        local target={kind=kind,object=object,square=sourceSquare,key=key,container=container,remembered=true,storageScoped=suffix~=nil}
        if state.travelRejected[key] then
            local layout=SurvivalRoute.known(target,kind) and Nearby.routeEvidence
                and Nearby.routeEvidence(player,square,radius)
            if SurvivalRoute.blocked(state.travelRejected,key,target,layout,now) then return end
        end
        if container then
            if onlyWorldWater or not Storage.permitted(player,sourceSquare)
                    or (instanceof(object,"IsoThumpable") and object:isLockedToCharacter(player)) then return end
            local usable, obsolete=Supplies.scoutedStock(player,kind,container,state.rejected)
            if usable then return target end
            return nil,obsolete
        elseif kind=="water" then
            local sourceRejection=Needs.supplyRejected(state.rejected,object,now)
            if not sourceRejection and Nearby.waterObject(player,target)==object then return target end
        end
    end)
end

-- A confirmed local interaction is enough; for an excursion, remember the
-- facility only after a successful exact return to this training position.
local function learnFacility(state,target,now)
    if not target or not target.object then return end
    if state.excursion then
        local trip=state.excursion
        if trip.careTarget==target or trip.waterObject==target.object
                or (target.container and trip.target and trip.target.container==target.container and trip.kind==target.kind) then
            trip.verifiedFixture=target
        end
        if trip.verifiedFixture==target or trip.localErrand then trip.outing.learned[target.kind]=target end
    else ScoutMemory.remember(state.scoutMemory,target,now) end
end

-- A walk or a queued action is not success. Open the next stop only after
-- native relief; interrupted/failed attempts fall through to the way home.
function Controller.scoutRelief(state,kind,partial)
    local trip=state.excursion
    if trip and trip.stage=="care" then
        if partial then state.careNeeds[kind]=true else trip.outing.served[kind]=true end
        trip.outing.turns=trip.outing.turns+1
        trip.stage,trip.openedWindow="errands",nil
    end
end

local function arrivedHome(state,trip,now)
    if trip.outing then
        local t,origin=trip.walkTiming,trip.origin
        local sample
        if t and not t.invalid and not trip.homeFailures and t.outbound and t.outbound.ms and t.homebound and t.homebound.ms then
            sample={x=origin.x,y=origin.y,z=origin.z,ms=t.outbound.ms+t.homebound.ms}
        end
        for _,target in pairs(trip.outing.learned) do
            ScoutMemory.remember(state.scoutMemory,target,now,not trip.indirect and target==trip.verifiedFixture and sample or nil)
        end
    end
    state.excursion=nil
end

-- An empty/unreplicated MP list is a possibility, not a usable supply.
-- It may still be inspected when the requested practice is genuinely blocked.
-- Run this after looking up the target: a live gate may change during the
-- short radius cache without the actual stock changing.
function Controller.yieldUnknownScout(player,state,target,kind)
    if not target or not target.unknown or not isClient() then return false end
    if (kind=="water" or kind=="food") and Needs.level(player,kind)>=1 and Needs.due(player,kind)
            and not state.lowHealth and not Needs.critical(player,"water") and not Needs.critical(player,"food") then
        -- A first moodle permits one normal, time-bounded loot inspection
        -- ahead of optional practice. Don't displace a usable hunger fallback.
        return kind=="food" and Controller.hungerOpportunity(player,state)
            or kind=="water" and Needs.due(player,"food") and Controller.hungerOpportunity(player,state)
    end
    if state.practiceCare then return true end
    local head=queueFor(player)[1]
    if head and head.autoMindfulOwner==state and not head.autoMindfulStopped
            and (isPractice(head,"meditation") or isPractice(head,"yoga")) then return true end
    if state.tierGoal then
        return (state.tierGoal.kind=="meditation" and meditationGate(player) or yogaAdmission(player)).ready
    end
    if state.recovery then return not state.recoveryUnknown end
    -- The scheduler has just considered the selected modes, caps, pins and
    -- native gates. An admissible alternate (including a bridge) counts too.
    return state.cycle and state.cycle.nextKind~=nil
end

local function nearbyTarget(player, state, kind, onlyWorldWater, skipRemembered)
    local trip=state.excursion
    if (trip and trip.stage~="errands") or not Options.searchNearby() then return nil end
    onlyWorldWater=onlyWorldWater==true
    state.travelRejected = state.travelRejected or {}
    local now, square, radius = getTimestampMs(), player:getSquare(), Options.searchRadius()
    if trip then
        square,radius=resolveOrigin(trip.origin), math.min(radius,trip.outing.radius)
        if not square then return nil end
        skipRemembered=true -- rank confirmed stock from our feet, inside the original circle
    end
    local critical = (kind == "food" or kind == "water") and Needs.critical(player,kind)
    state.travelScan = state.travelScan or {}
    local cached = state.travelScan[kind]
    local target
    if not skipRemembered and cached and cached.square == square and cached.radius == radius
            and cached.onlyWorldWater == onlyWorldWater and cached.critical == critical
            and now>=cached.time and (now==cached.time or not cached.target and now-cached.time<1000) then
        target=cached.target
    else
        target = not skipRemembered and learnedStop(player,state,kind,square,radius,now,onlyWorldWater)
            or Nearby.find(player, kind, square, radius, state.travelRejected, onlyWorldWater,state.rejected)
        if target and target.remembered and SurvivalRoute.known(target,kind) and Nearby.routeEvidence then
            target.routeLayout,target.routeScope=Nearby.routeEvidence(player,square,radius)
        end
        state.travelScan[kind] = {square=square, radius=radius, onlyWorldWater=onlyWorldWater,
            critical=critical, time=now, target=target}
    end
    if target and target.unknown and (critical or Controller.yieldUnknownScout(player,state,target,kind)) then return nil end
    return target
end

-- A valid supply across the room may still be unreachable from the square
-- occupied by a crate. First offer a native step onto clear floor; never
-- teleport, climb an edge, or stand on that same occupied tile again.
function Controller.scoutEgress(player,state,kind,target,here)
    if state.excursion or target.unknown or (kind~="water" and kind~="food")
            or not ISPathFindAction or not ISPathFindAction.pathToNearest then return false end
    local plan=ScoutEgress.options(player,here)
    if not plan then return false end
    local signature=plan.signature
    if state.scoutEgressSignature==signature then return false end
    if not stand(player,state,"Standing up to move off the blocked training tile.") then return true end
    if player:getSquare()~=here then return false end
    state.scoutEgressSignature=signature
    local walk=ISPathFindAction:pathToNearest(player,plan.goals)
    if not walk then return false end
    local trip={origin=rememberOrigin(player,here),target=target,kind=kind,stage="outbound",egressPlan=plan,egressWalk=walk}
    state.excursion,state.travelScan=trip,nil
    if ownBatch(player,state,"travelling","Trying a clear adjacent floor tile before scouting.",function()
        prepareScoutWalk()
        ISTimedActionQueue.add(walk)
    end) then return true end
    if not state.active or state.excursion~=trip then return true end
    state.excursion=nil
    return false
end

function Controller.settleScoutEgress(player,state,trip,failedPath)
    state.excursion,state.travelScan=nil,nil
    Nearby.invalidate(player)
    if not failedPath and trip.egressWalk.autoMindfulFinished and ScoutEgress.arrived(player,resolveOrigin(trip.origin),trip.egressPlan) then
        state.scoutEgressSignature=nil
        state.careNotice="Moved off the blocked training tile. Checking supplies from clear ground."
    else
        state.careNotice="No clear path off the blocked training tile. Checking other care options."
    end
end

local function tryExcursion(player,state,kind,onlyWorldWater,selectedCare,target)
    local worldWater = kind == "water" and target.object ~= nil and not target.container
    local waterObject = worldWater and Nearby.waterObject(player, target) or nil
    local exact=target.container and (target.remembered and target
        or (not target.unknown and not target.part and ScoutMemory.storageTarget(kind,target.container)))
    if (worldWater and not waterObject) or not vehicleTargetAvailable(player, target)
            or (exact and not Controller.scoutedStorageAllowed(player,exact)) then
        state.travelScan=nil
        if target.remembered then ScoutMemory.forget(state.scoutMemory,target) end
        state.travelRejected[target.key]=getTimestampMs()+15000
        return false
    end
    local here = player:getSquare()
    if not here then return false end
    local prior=state.excursion
    if Controller.scoutEgress(player,state,kind,target,here) then return true end
    if prior then
        local origin,radius=prior.origin,math.min(prior.outing.radius,Options.searchRadius())
        local dx,dy=target.square:getX()-origin.x,target.square:getY()-origin.y
        if target.unknown or target.square:getZ()~=origin.z or dx*dx+dy*dy>radius*radius
                or not LifestyleCare.frontInRange(selectedCare,origin.x,origin.y,origin.z,radius) then return false end
    end
    state.excursion = {origin = prior and prior.origin or rememberOrigin(player, here), target = target, kind = kind,
        outing = prior and prior.outing or {served={},learned={},turns=0,radius=Options.searchRadius()}, indirect=prior~=nil,
        onlyWorldWater = onlyWorldWater, waterObject = waterObject, careTarget = selectedCare, exactStorage = exact, stage = "outbound"}
    state.travelScan = nil
    if target.unknown and ((target.part and Storage.vehicleAccessible(player, target.part))
            or (not target.part and here and here:canReachTo(target.square))) then
        state.excursion.stage, state.excursion.inspectUntil = "inspect", getTimestampMs() + 3000
        setPhase(state, "scouting", "Inspecting a nearby container through the normal loot interface.")
        return true
    end
    local route
    local message = waterObject and (target.remembered and "Walking to a known clean-water source; returning here after care."
            or "Walking to a clean-water source; returning here after care.")
        or (selectedCare and (kind == "restroom" and (target.remembered and "Walking to a known toilet; returning here after care."
            or "Walking to a nearby toilet; returning here after care.") or (target.remembered
            and "Walking to a known place to wash; returning here after care." or "Walking to a place to wash; returning here after care.")))
        or (target.remembered and "Walking to a known supply container; returning here after care."
            or "Walking to a supply container; returning here after care.")
    local queued = ownBatch(player, state, "travelling", message, function()
        prepareScoutWalk()
        if player:isSitOnGround() or (kind=="restroom" and player:isSitting()) then
            ISTimedActionQueue.add(ISWaitWhileGettingUp:new(player))
        end
        if target.part then
            local vehicle = Storage.vehiclePart(target.part)
            if vehicle then
                ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(player, vehicle, target.part:getArea()))
                route = true
            end
        elseif selectedCare then
            local front=type(selectedCare.care)=="table" and selectedCare.care.front
            if front then
                ISTimedActionQueue.add(ISWalkToTimedAction:new(player,front)); route=true
            else route=luautils.walkAdjObject(player, selectedCare.object, true, true) end
        elseif SurvivalRoute.known(target,kind) then
            route = SurvivalRoute.walk(player,target.square,waterObject)
        else
            route = luautils.walkAdj(player, target.square, true)
        end
    end)
    -- A synchronous callback may already have yielded or stopped us.
    if not state.active or not state.excursion or state.excursion.target~=target then return true end
    if not route then
        local leg=state.excursion
        clearOwned(player,state)
        if not state.active or state.excursion~=leg then return true end
        queued=false
    end
    if not queued then
        if not route then Controller.rejectScoutPath(state,{target=target,kind=kind},getTimestampMs(),"no-legal-approach")
        else state.travelRejected[target.key]=getTimestampMs()+15000 end
        state.pending,state.excursion,state.travelScan=nil,prior,nil
        if target.remembered then ScoutMemory.forget(state.scoutMemory,target) end
        if state.releasePending or #queueFor(player)>0 or ActionYield.nativeBusy(player) then return true end
    end
    return queued
end

local function beginExcursion(player,state,kind,onlyWorldWater,selectedCare,skipRemembered,confirmedOnly)
    local trip=state.excursion
    if (trip and trip.stage~="errands") or not Options.searchNearby() then return false end
    state.travelRejected=state.travelRejected or {}
    if trip then
        -- A follow-up may only use a known stop. Never start the speculative
        -- inspection/retry loop from another stop.
        local target=selectedCare or nearbyTarget(player,state,kind,onlyWorldWater,true)
        return target and not target.unknown and tryExcursion(player,state,kind,onlyWorldWater,selectedCare,target) or false
    end
    -- Bound native admissions per update. A single rejected ordinary source
    -- must not be reported as “no water” while another known source exists.
    local tried={}
    for i=1,4 do
        local target=selectedCare or nearbyTarget(player,state,kind,onlyWorldWater,skipRemembered)
        if not target or (confirmedOnly and target.unknown) then return false end
        local id=SurvivalRoute.known(target,kind) and SurvivalRoute.identity(target) or target.key
        if tried[id] then return false end
        tried[id]=true
        if tryExcursion(player,state,kind,onlyWorldWater,selectedCare,target) then return true end
        if selectedCare or target.unknown then return false end
        skipRemembered=true
    end
    local nextTarget=nearbyTarget(player,state,kind,onlyWorldWater,true)
    if nextTarget and not nextTarget.unknown and not tried[SurvivalRoute.known(nextTarget,kind) and SurvivalRoute.identity(nextTarget) or nextTarget.key] then
        setPhase(state,"scouting","Checking the remaining known supply routes.")
        return true -- more known routes at the next normal idle update
    end
    return false
end

local function homeWalk(player, square, trip)
    local action = ISWalkToTimedAction:new(player, square)
    local stockStart = action.start
    local origin = trip.origin
    local useSavedPoint = trip.homeFailures == homeAttemptLimit - 1 and origin.pointX ~= nil
    function action:start(...)
        self.autoMindfulHomeStartX, self.autoMindfulHomeStartY = player:getX(), player:getY()
        self.autoMindfulHomeAim = "stock-tile"
        local result = stockStart and stockStart(self, ...)
        local here = useSavedPoint and player:getSquare()
        if stockStart and here and here:getZ() == origin.z and queueFor(player)[1] == self
                and not player:pressedMovement(false) and not player:pressedCancelAction() then
            local path = player:getPathFindBehavior2()
            -- Stock start sets, but does not submit, the center request. Before
            -- the first update, retarget it only if that exact center remains
            -- its native target. Preserve stock start/flags and other hooks.
            if path and path.pathToLocationF and path.getTargetX and path.getTargetY and path.getTargetZ
                    and path:getTargetX() == origin.x + 0.5 and path:getTargetY() == origin.y + 0.5
                    and path:getTargetZ() == origin.z then
                path:pathToLocationF(origin.pointX, origin.pointY, origin.z)
                self.autoMindfulHomeAim = "saved-point"
            end
        end
        return result
    end
    return action
end

local function returnToOrigin(player, state, now)
    local trip = state.excursion
    if not trip then return false end
    local here = player:getSquare()
    if atOrigin(here, trip.origin) then
        arrivedHome(state,trip,now)
        return false
    end
    if trip.homeRetrySince then
        if now < trip.homeRetrySince then trip.homeRetrySince = now end
        if now - trip.homeRetrySince < homeRetryDelay then
            setPhase(state, "return-wait", "Waiting briefly before retrying the walk to the original training spot.")
            return true
        end
    end
    -- Do not retain an IsoGridSquare across an outing. The native route uses
    -- XYZ, but current loading, permissions, and floor still need validation.
    local origin = resolveOrigin(trip.origin)
    if not origin or not here or origin:getZ() ~= here:getZ() or not Storage.permitted(player, origin) then
        Controller.stop(player, "The original training spot is no longer accessible. Stopped without forcing movement.")
        return true
    end
    if ScoutEgress.obstructed(origin) then
        if here.canStand and here:canStand() and Storage.permitted(player,here) then
            state.excursion,state.travelScan=nil,nil
            state.careNotice="The original training tile is blocked. Resuming at the current clear tile."
            Nearby.invalidate(player)
            return false
        end
        Controller.stop(player, "The original training tile is blocked. Choose clear ground and start again.")
        return true
    end
    trip.stage, trip.homeRetrySince, trip.homeFailedWalk, trip.homeStopRecorded = "homebound", nil, nil, nil
    local queued = ownBatch(player, state, "travelling", "Returning to the original training spot.", function()
        prepareScoutWalk()
        if player:isSitOnGround() then ISTimedActionQueue.add(ISWaitWhileGettingUp:new(player)) end
        trip.homeWalk = homeWalk(player, origin, trip)
        ISTimedActionQueue.add(trip.homeWalk)
    end)
    if not queued then Controller.stop(player, "Could not start the walk back to the original training spot.") end
    return true
end

local function checkHomeRecovery(player, state, queue, now)
    local trip = state.excursion
    if not trip then return false end
    if trip.homeCancelled then
        Controller.stop(player, trip.homeCancelled)
        return true
    end
    if trip.homeStopRecorded and trip.homeStopRecorded.autoMindfulNativeHandoffExpired then
        Controller.stop(player, "The return walk did not settle. Stopped without forcing movement.")
        return true
    end
    if not trip.homeFailures then return false end
    if not atOrigin(player:getSquare(), trip.origin) then
        if not Options.searchNearby() then
            Controller.stop(player, "Scouting is off. Stopped without retrying the return to the training spot.")
            return true
        end
        if trip.homeFailures >= homeAttemptLimit then
            Controller.stop(player, homeNoRoute)
            return true
        end
    end
    if not trip.homeRetrySince or state.contextVisible or state.inspectingUI or player:isAsleep() then return false end
    if now < trip.homeRetrySince then trip.homeRetrySince = now end
    if now - trip.homeRetrySince < homeSettleTimeout then return false end
    -- A genuine foreign action is allowed to finish without a timer. A dead
    -- owned handle or an engine busy flag with no action is not such a pause.
    local native, failed = player:getCharacterActions(), trip.homeFailedWalk
    local staleOwned = (not queue[1] or queue[1] == failed) and failed and failed.action
        and native:size() == 1 and native:contains(failed.action)
    local staleFlag = (not queue[1] or queue[1] == failed) and native:isEmpty()
        and (queue[1] ~= nil or ActionYield.nativeBusy(player) or state.releasePending)
    if staleOwned or staleFlag then
        Controller.stop(player, "The return walk did not settle. Stopped without forcing movement.")
        return true
    end
    return false
end

local function supply(player, state, kind, onlyWorldWater, waterObject, exactContainer, confirmedOnly, localOnly)
    if kind == "pain" and not wantsPainCare(player, state, getTimestampMs()) then return false end
    if kind == "literature" and player:tooDarkToRead() then return not localOnly and beginExcursion(player,state,kind,onlyWorldWater,nil,nil,confirmedOnly) end
    state.supplyMissingReason = nil
    local collect = state.collectNearby or Options.searchNearby() or state.excursion ~= nil
    local entry
    if waterObject then
        local source = WaterSources.choose(player, state.rejected, waterObject)
        if not source then return false end
        entry = {source=source}
    else
        entry = Supplies.choose(player, kind, collect, state.rejected, onlyWorldWater, exactContainer)
    end
    while entry and entry.source do
        local source = entry.source
        state.supplyItem, state.supplyLoan, state.collectingItem = nil, nil, nil
        state.supplyKind, state.supplySource = "water", source
        state.supplyStop = nil
        state.supplyBaseline = {thirst = stat(player, "THIRST")}
        local queued = ownBatch(player, state, "drinking", "Drinking from a nearby clean-water source.", function()
            local needed = stat(player, "THIRST") * 2
            local amount = source.object:getFluidAmount()
            state.supplyGoal = {fullyCovered=amount >= needed, world=source.object, worldAmount=amount, baselineNeed=needed/2,
                expectedRemaining=math.max(0, amount-needed)}
            local used, reason = WaterSources.drink(player, source)
            if not used then state.supplyMissingReason = reason end
        end)
        if not queued then
            state.rejected[source.object] = getTimestampMs() + 60000
            state.supplyKind, state.supplySource, state.supplyBaseline = nil, nil, nil
            state.pending = nil
        end
        if queued then return true end
        if waterObject then return false end
        entry = Supplies.choose(player, kind, collect, state.rejected, onlyWorldWater)
    end
    if entry and entry.transfer then
        if entry.transfer.source.description.needsOpening then entry = entry.transfer.source
        else
            state.supplyStop=not entry.transfer.source.worldSource and ScoutMemory.supplyTarget(kind,entry.transfer.source.item) or nil
            return beginFluidSupply(player,state,entry.transfer)
        end
    end
    if not entry then
        if exactContainer or localOnly then return false end
        if beginExcursion(player, state, kind, onlyWorldWater,nil,nil,confirmedOnly) then return true end
        if (kind == "water" or kind == "food") and not state.excursion then
            local report = Supplies.report(player, state.collectNearby or Options.searchNearby())
            state.supplyMissingReason = state.supplyMissingReason
                or report.fluidReason or (kind == "water" and report.waterSourceReason or report.openingReason)
        end
        return false
    end
    local item = entry.item
    state.supplyStop=ScoutMemory.supplyTarget(kind,item)
    local loan = loanFor(player, state, item)
    if kind == "pain" and loan then loan.pain = true end
    state.supplyItem, state.supplyKind, state.supplyLoan = item, kind, loan
    if item:getContainer() ~= player:getInventory() then
        state.collectingItem = item
        return ownBatch(player, state, "collecting", "Collecting " .. item:getDisplayName() .. ".", function()
            Supplies.transfer(player, item, (kind=="pain" or state.supplyStop) and loan or nil)
        end)
    end
    state.collectingItem = nil
    return useSupply(player, state, kind, item, loan)
end

-- Optional cross-practice may not surprise the player by removing or
-- dropping equipment. Unknown equipment state is not permission.
local function careGearSafe(player,kind,rank)
    if not player.getPrimaryHandItem or not player.getSecondaryHandItem then return false end
    local function safe(item)
        return not item or (item.isForceDropHeavyItem and item:isForceDropHeavyItem()==false)
    end
    if not safe(player:getPrimaryHandItem()) or not safe(player:getSecondaryHandItem()) then return false end
    local vars=SandboxVars and SandboxVars[kind=="yoga" and "Yoga" or "Meditation"]
    if kind=="meditation" and rank>=3 or vars and vars.KeepBags==true then return true end
    if not player.getWornItems or not instanceof then return false end
    local worn=player:getWornItems()
    if not worn then return false end
    for i=0,worn:size()-1 do
        local item=worn:get(i):getItem()
        if item and instanceof(item,"InventoryContainer") then return false end
    end
    return true
end

function Controller.suspendTurnTier(state,goal,reason)
    state.tierSuppressed=state.tierSuppressed or {}
    state.tierSuppressed[goal.kind]={group=goal.group,chosen=goal.chosen}
    state.turnTier=nil
    if goal.addedDebt and state.cycle.owed==goal.kind then setCycleDebt(state.cycle,nil) end
    state.tierNotice=reason.." Continuing normal "..modeTitles[goal.kind].." without this minimum for now."
    state.tierNoticeUntil=getTimestampMs()+15000
end

local function train(player, state, kind, bridge, course)
    if not Tiers.wellnessEnabled() then return false end
    if state.cycleUntil then
        local remaining = state.cycleUntil - getTimestampMs()
        if remaining > 0 and remaining <= ActionYield.cooperativeWindowMs then
            setPhase(state, "between", "Waiting briefly before the next training action.")
            return
        end
        state.cycleUntil = nil
    end
    -- Keep the selected *leg*, not a timed-action object. Stand/sit, supplies,
    -- and foreign work may all intervene before native practice can begin.
    if not course then state.trainingKind = kind end
    if kind == "meditation" then
        if not sit(player, state) then return end
        if bridge == yogaEnduranceBridge then
            -- Sitting can span multiple updates. Sample the live native
            -- admission again; the old exhaustion reason isn't permission.
            local gate=yogaAdmission(player)
            state.cycle.gates.yoga=gate
            if gate.kind ~= "endurance" or not careGearSafe(player,kind,levels(player)) then
                state.trainingKind=nil
                noteCycle(state,"recheck","yoga",nil)
                return false
            end
        end
        local gate=meditationGate(player)
        if not gate.ready then
            if course then return false end
            if state.cycle then
                state.cycle.gates.meditation=gate
                noteCycle(state,"recheck","meditation",nil)
                Decisions.transition(state,state.phase,"meditation-gate",gate.reason)
                return
            end
            Controller.stop(player,gate.reason,"meditation-gate",gate.reason)
            return
        end
    else
        if not stand(player,state) then return end
        -- The native menu onAction doesn't repeat its tool-tip gate. A
        -- completed stand is not permission to start stale Yoga.
        local gate=yogaAdmission(player)
        if state.cycle then state.cycle.gates.yoga=gate end
        if not gate.ready then
            if not course then
                noteCycle(state,"recheck","yoga",nil)
                Decisions.transition(state,state.phase,"yoga-gate",gate.reason)
            end
            return false
        end
    end
    local option = kind == "meditation" and ZenWellnessContextMenu.Options.Meditation or ZenWellnessContextMenu.Options.Yoga
    -- Lifestyle's onAction clears the stock queue. Check at admission too,
    -- not just at the beginning of the controller tick.
    if #queueFor(player) > 0 or ActionYield.nativeBusy(player) then yieldToPlayer(player, state); return end
    local cycle=state.cycle
    local target=not course and not bridge and (state.tierGoal or state.turnTier)
    if target and target.kind==kind then
        local current=Tiers.current(player,kind)
        if current==nil then
            local reason="Could not read the current Lifestyle tier."
            if state.tierGoal then Controller.stop(player,reason); return false end
            Controller.suspendTurnTier(state,target,reason)
            target=nil
        else
            target.belowAtAdmission=current<target.target
            target.waitAt,target.waitMs=nil,nil
        end
    else target=nil end
    if course then
        if not careGearSafe(player,kind,course.rank) then return false end
        state.practiceCare=course
        if course.target=="hunger" then
            state.hungerAid={tried=true,best=state.hungerAid and state.hungerAid.best}
        end
        state.practiceCareRelieved=nil
        state.practiceCareNext=course.startedAt+120000
    elseif cycle then
        local entry=Progress.snapshot(player)[kind]
        state.practiceWork={kind=kind,bridge=bridge or nil,progress=entry,entry=entry}
        if bridge then cycle.bridge=true end
        if bridge == true then cycle.bridgeUsed=true end
        noteCycle(state,bridge and "bridge" or cycle.reason or "ready",cycle.preferred or kind,kind)
    end
    local strict=course and course.strictTier
    local queued=ownBatch(player, state, course and "practice-care" or kind,
        strict and ((kind=="yoga" and "Practicing Yoga" or "Meditating").." toward "
            ..(Tiers.label(kind,strict.target) or "the selected tier").."; other actions still take priority.")
            or course and course.target=="hunger" and ("Meditating toward "
                ..(Tiers.label(kind,course.targetTier) or "Strong Mindfulness").." for hunger relief.")
            or course and ((kind=="yoga" and "Practicing Yoga" or "Meditating").." for "..course.need..(state.recovery and "; other actions can take over." or "; training resumes afterward."))
            or target and ((kind=="yoga" and "Practicing Yoga" or "Meditating").." toward "
                ..(Tiers.label(kind,target.target) or "the selected tier")..".")
            or kind == "yoga" and "Practicing yoga. Poses may fail normally; completed sessions restart automatically."
            or state.endurance and "Meditating until endurance reaches 100%."
            or bridge == yogaEnduranceBridge and "Meditating only while Lifestyle blocks Yoga for low endurance."
            or bridge and "Meditating briefly while waiting for Yoga's native recovery requirement."
            or "Meditating. AutoMindful will take care breaks and resume.", function()
        option.onAction({}, option, player)
    end)
    if course then return queued end
    if not queued then
        -- The native menu may return without a timed action during a posture
        -- or animation transition. Its empty batch is a loss, not success.
        -- Use the same bounded recovery as a disappeared training action.
        if state.active and not state.yielding and state.pending then
            setPhase(state, kind, "Lifestyle did not queue training. Checking before retrying.", "admission-retry")
        end
    elseif cycle then
        observePractice(player,state,queueFor(player),getTimestampMs(),false)
    end
end

local criticalNeed=Needs.critical

local function comfortSupplyAvailable(player, state, kind, confirmedOnly, localOnly)
    if kind == "literature" then
        if player:tooDarkToRead() then
            if localOnly then return false end
            local target=nearbyTarget(player,state,kind,false)
            return target~=nil and not (confirmedOnly and target.unknown)
        end
    end
    local full = kind ~= "literature" and player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) >= 3
    if full and kind == "food" then return false end
    if Supplies.choose(player,kind,state.collectNearby or Options.searchNearby(),state.rejected,full) then return true end
    if localOnly then return false end
    local target=nearbyTarget(player,state,kind,full)
    return target~=nil and not (confirmedOnly and target.unknown)
end

-- Mild pain is optional care: only interrupt our own meditation for a known,
-- usable treatment. Don't disturb a Yoga action; its successful poses can
-- already ease pain and Lifestyle penalizes stopping early.
local function painAvailable(player, state, now)
    if not wantsPainCare(player, state, now) then return false end
    if state.painNextScan and now < state.painNextScan and state.painNextScan - now <= 5000 then return false end
    if Supplies.choose(player, "pain", state.collectNearby or Options.searchNearby(), state.rejected)
            or nearbyTarget(player, state, "pain", false) then
        state.painNotice = nil
        return true
    end
    state.painNextScan = now + 5000
    state.painNotice = "Pain needs attention. No usable stock Painkillers found within the permitted supply range."
    return false
end

local function lifestyleReady(player, state, now)
    return (not state.excursion and not state.endurance) and LifestyleCare.ready(player, state, now,
        state.collectNearby, Options.searchNearby() and Options.searchRadius() or nil)
end

local function queueLifestyle(player, state, target, now, useOnly)
    local name=target.kind=="restroom" and (not useOnly and target.care and target.care.plungerId
        and "Unclogging the toilet." or "Using the restroom.") or target.item and "Using a hygiene item." or "Washing yourself."
    local course
    local queued=ownBatch(player,state,target.kind,name,function()
        course=LifestyleCare.begin(player,target,state,useOnly)
    end)
    if queued and course then
        state.lifestyleCourse=course
        if target.kind=="restroom" then
            setPhase(state,target.kind,course.before.preparation and "Unclogging the toilet." or "Using the restroom.")
        end
        return true
    end
    LifestyleCare.reject(state,target,now)
    if queued then clearOwned(player,state) end
    state.pending=nil
    return false
end

local function lifestyleCare(player,state,target,now)
    if not target then return false end
    if target.object and not LifestyleCare.accessible(player,target) then
        if not target.close and LifestyleCare.validTarget(player,target)
                and beginExcursion(player,state,target.kind,false,target) then return true end
        LifestyleCare.reject(state,target,now)
        return false
    end
    if not stand(player,state,"Standing up for a care break.") then return true end
    if target.item and target.item:getContainer()~=player:getInventory() then
        local loan=loanFor(player,state,target.item)
        if not loan or not Supplies.careLoanAllowed(player,loan,state.collectNearby or Options.searchNearby()) then
            if loan then loan.defer=nil end
            LifestyleCare.reject(state,target,now)
            return false
        end
        local queued=ownBatch(player,state,"collecting","Collecting a hygiene item.",function()
            Supplies.transfer(player,target.item,loan)
        end)
        if queued then
            state.lifestylePickup={target=target,loan=loan,id=target.item:getID(),fullType=target.item:getFullType()}
            state.supplyLoan=loan
            return true
        end
        loan.defer=nil
        state.pending=nil
        LifestyleCare.reject(state,target,now)
        return false
    end
    return queueLifestyle(player,state,target,now)
end

-- Only undo a known native blocker with bounded, ordinary care. Never
-- treat Yoga or a lower boredom reading as a hunger receipt.
function Controller.hungerPrerequisite(player,state)
    if not Controller.mindfulnessEnabled() or not WellnessInfo.supported()
            or not Tiers.wellnessEnabled() or (Options.practiceCare and not Options.practiceCare()) then
        return false,"Lifestyle hunger relief is disabled or unavailable."
    end
    local med,yoga=levels(player)
    local tier=Tiers.current(player,"meditation")
    if not PracticeCare.hungerUnlocked(med) then return false,"Strong Mindfulness requires Meditation rank 6." end
    if tier==nil then return false,"Lifestyle's Mindfulness state could not be read." end
    if state.hungerAid and state.hungerAid.failed then return false,"Native Mindfulness did not confirm hunger relief." end
    if player:isSittingOnFurniture() or player:getModData().IsSittingOnSeat or not careGearSafe(player,"meditation",med) then
        return false,"Meditation for hunger is blocked by seating or carried equipment."
    end
    local gate=meditationGate(player)
    if gate.ready then return false end
    if gate.kind~="boredom" then
        return false,"Lifestyle blocked Meditation: "..(gate.reason and gate.reason:gsub("<[^>]*>",""):gsub("^%s+","") or "native requirements not met").."."
    end
    if criticalNeed(player,"water") then return false,"Critical thirst takes priority over Meditation." end
    -- A real book may unlock Meditation without the exertion of Yoga.
    if not state.prerequisiteReadAttempted and not player:tooDarkToRead()
            and comfortSupplyAvailable(player,state,"literature",true,true)
            and supply(player,state,"literature",false,nil,nil,true,true) then
        state.prerequisiteReadAttempted=true
        return true
    end
    if Needs.lowHealth(player) then
        return false,"Boredom blocks Meditation. Read eligible literature; low health rules out optional Yoga."
    end
    if state.prerequisiteYogaAttempted then
        return false,"Boredom still blocks Meditation after a bounded Yoga attempt. Read eligible literature or find safe food."
    end
    local y=yogaAdmission(player)
    if not y.ready or not careGearSafe(player,"yoga",yoga) then
        return false,"Boredom blocks Meditation. Yoga cannot start here; read eligible literature or find safe food."
    end
    local now=getTimestampMs()
    local readings={BOREDOM=stat(player,"BOREDOM")}
    local course={kind="yoga",need="boredom",rank=yoga,startedAt=now,before=readings,
        hungerPrerequisite=true,maxMs=math.min(450000,240000+math.floor(yoga/4)*90000)}
    if train(player,state,"yoga",false,course) then
        state.prerequisiteYogaAttempted=true
        return true
    end
    if state.pending and #state.pending>0 or state.phase=="standing" or state.phase=="between" and state.cycleUntil then return true end
    if state.practiceCare==course then state.practiceCare,state.pending=nil,nil end
    state.prerequisiteYogaAttempted=true
    return false,"Lifestyle did not start Yoga. Boredom still blocks Meditation; read eligible literature or find safe food."
end

-- Ask whether native relief is a real alternative *before* rummaging through
-- unreplicated MP storage. Always run the ordinary supply/known-route path first.
function Controller.hungerOpportunity(player,state)
    if state.endurance or not Controller.mindfulnessEnabled() or not WellnessInfo.supported()
            or (Options.practiceCare and not Options.practiceCare()) then return false end
    local aid,watch=state.hungerAid,state.mindfulnessWatch
    if aid and aid.failed then return false end
    if watch and watch.target=="hunger" then return true end -- a late native flush may outlive the badge
    local med=levels(player)
    local tier=Tiers.current(player,"meditation")
    local ready=PracticeCare.hungerUnlocked(med) and not (aid and aid.tried and not aid.helped) and not player:isSittingOnFurniture()
        and not player:getModData().IsSittingOnSeat and meditationGate(player).ready and careGearSafe(player,"meditation",med)
    local course,passive=PracticeCare.hungerPlan(stat(player,"HUNGER"),med,tier,ready,Needs.level(player,"food"))
    return course~=nil or passive~=nil
end

function Controller.firstHungerCourse(player,state)
    if Needs.level(player,"food")<1 or not Needs.due(player,"food") or state.mindfulnessWatch
            or (state.hungerAid and state.hungerAid.tried and not state.hungerAid.helped) then return false end
    local tier=Tiers.current(player,"meditation")
    return tier~=nil and tier<2 and Controller.hungerOpportunity(player,state)
end

local function care(player, state)
    state.careNotice,state.sleepBlock,state.noConfirmedFood,state.recoveryStockWaiting=nil,nil,nil,nil
    if not Needs.due(player,"food") then
        state.hungerAid,state.prerequisiteReadAttempted,state.prerequisiteYogaAttempted=nil,nil,nil
    elseif state.hungerAid and not criticalNeed(player,"food") then state.hungerAid.best=nil end
    local criticalFood,criticalWater=criticalNeed(player,"food"),criticalNeed(player,"water")
    local emergency=criticalFood or criticalWater
    state.noEmergencyDrink=nil
    local full=player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN)>=3
    local remainder=state.recovery and recoveryPolicy.remainder or Consumables.restoredThreshold
    local order=criticalFood and not criticalWater and {"food","water"} or {"water","food"}
    for _,kind in ipairs(order) do
        local value=stat(player,kind=="water" and "THIRST" or "HUNGER")
        if value<=remainder then state.careNeeds[kind]=nil end
        if Needs.due(player,kind) or criticalNeed(player,kind) then state.careNeeds[kind]=true end
    end
    -- A route is only a candidate. With two needs, use a suitable supply at
    -- our feet before spending either need's time on that speculative walk.
    if state.careNeeds.food and state.careNeeds.water then
        for _,kind in ipairs(order) do
            if (kind=="water" or not full) and supply(player,state,kind,kind=="water" and full,nil,nil,true,true) then
                state.mindfulnessWatch=nil
                return true
            end
        end
    end
    for _,kind in ipairs(order) do
        if state.careNeeds[kind] then
            local fallback=kind=="food" and not full and Controller.hungerOpportunity(player,state)
            local confirmedOnly=emergency or fallback or state.lowHealth
            -- First moodle authorizes the normal bounded scout now. The quiet
            -- gap still protects preventive raw-stat Recovery trips below it.
            local localOnly=state.recovery and not emergency and Needs.level(player,kind)<1 and not state.recoveryReadyToScout
            local worldOnly=kind=="water" and full
            if (kind=="water" or not full) and supply(player,state,kind,worldOnly,nil,nil,confirmedOnly,localOnly) then
                state.mindfulnessWatch=nil
                return true
            end
            local later=localOnly and (kind=="water" or not full) and nearbyTarget(player,state,kind,worldOnly)
            if later and not later.unknown then state.recoveryStockWaiting=true
            elseif kind=="food" and not full then state.noConfirmedFood=true end
            state.careNeeds[kind]=nil
            if not emergency then
                state.careNotice=state.supplyMissingReason and (state.supplyMissingReason.." Checking other needs.")
                    or (kind=="water" and "No safe drink confirmed." or "No suitable food confirmed.")
            end
        end
    end
    if emergency then
        -- Neither an unavailable drink nor the absence of a meal makes
        -- sleeping safe. A bounded in-place hunger benefit is still possible;
        -- a newly available drink takes the queue back immediately.
        state.noEmergencyDrink=criticalWater or nil
        state.careNotice=nil
        local reason
        if criticalFood and state.noConfirmedFood then
            if Controller.hungerOpportunity(player,state) and Controller.criticalHungerRelief(player,state) then return true end
            local started
            started,reason=Controller.hungerPrerequisite(player,state)
            if started then return true end
            if not reason and state.hungerAid and state.hungerAid.tried then reason="Native hunger relief was not confirmed." end
        end
        local message=criticalWater and (full and "Dying of Thirst. No usable water found while the game restricts drinking."
            or "Dying of Thirst. Waiting for safe water.")
            or (full and "Starving to Death. Waiting for the game's eating restriction to end." or "Starving to Death. Waiting for suitable food.")
        if criticalWater and criticalFood then message=message.." Also waiting for suitable food." end
        setPhase(state,"recovering",message..(reason and (" "..reason) or ""),
            criticalWater and (full and "water-restricted" or "water-unavailable") or (full and "food-restricted" or "food-unavailable"))
        return true
    end
    local bedtime=sleepReadiness(player,state)
    if bedtime~="refused" then state.sleepDeclined=nil end
    if sleepAdmitted(bedtime) then
        -- Both native entry points clear the queue, even with a non-player
        -- successor. Never pass a queued or draining action to either.
        if #queueFor(player)>0 or ActionYield.nativeBusy(player) then yieldToPlayer(player,state); return true end
        if bedtime=="confirm" then
            ISWorldObjectContextMenu.onConfirmSleep(nil,{internal="YES"},player:getPlayerNum(),nil)
        else ISWorldObjectContextMenu.onSleepWalkToComplete(player:getPlayerNum(),nil) end
        if player:isAsleep() then
            setPhase(state,"sleeping","Sleeping on the ground. Training resumes after waking.")
            return true
        end
        -- The menu/server remains authoritative. A declined submission
        -- leaves care available; don't make the same request every poll.
        state.sleepDeclined,bedtime=true,"refused"
    end
    state.sleepBlock=bedtime
    if bedtime=="dialog" then return true end
    -- A fallback is not reason to skip an actionable treatment or reading,
    -- even in Yoga-only mode. Never mistake an unexplored crate for a book.
    if state.noConfirmedFood and not state.lowHealth then
        if painAvailable(player,state,getTimestampMs()) and supply(player,state,"pain") then return true end
        if stat(player,"BOREDOM")>=(state.recovery and recoveryPolicy.readAt or 20)
                and comfortSupplyAvailable(player,state,"literature",true)
                and supply(player,state,"literature",false,nil,nil,true,state.recovery and not state.recoveryReadyToScout) then return true end
    end
    return false
end

local sleepWaitMessages={
    server="Sleep is needed, but this server does not allow it.",
    cooldown="Waiting for the normal one-hour sleep cooldown to end.",
    pain="The game is blocking sleep because of pain. Waiting for pain to ease.",
    panic="The game is blocking sleep because of panic. Waiting for panic to ease.",
    smell="The game is blocking sleep because of a noxious smell. Move to a suitable spot.",
    exercise="The game has not marked exercise finished. Waiting for it, or use the normal in-game Sleep action.",
    refused="The game refused sleep. Other care is still available; use the normal in-game Sleep action.",
}

-- Sleep not admitted isn't a care action. Report/stop only *after* checking
-- supplies, suitable medicine and useful bounded relief.
local function waitForSleep(player,state)
    local reason=state.sleepBlock
    local message=sleepWaitMessages[reason]
    if not message then return false end
    if reason=="server" and not state.recovery then
        Controller.stop(player,"Sleep is needed but this server does not allow it. Recover fatigue before restarting.")
    else setPhase(state,"recovering",message) end
    return true
end

local function practiceReadings(player, meditation, skipStiffness)
    local stats=player:getStats()
    local function read(name)
        local key=CharacterStat[name]
        return key and stats:get(key) or nil
    end
    local body=player:getBodyDamage()
    local parts=not skipStiffness and body and body.getBodyParts and body:getBodyParts()
    local stiff
    if parts then
        for i=0,parts:size()-1 do
            local part=parts:get(i)
            local value=part and part.getStiffness and part:getStiffness()
            if type(value)=="number" then stiff=math.max(stiff or 0,value) end
        end
    end
    local moodles=player:getModData().LSMoodles
    local mindful=type(moodles)=="table" and moodles.MindfulState
    local tier=PracticeCare.nativeTier(type(mindful)=="table" and mindful.Value,meditation or levels(player))
    local smoking=CharacterTrait and CharacterTrait.SMOKER and player.hasTrait and player:hasTrait(CharacterTrait.SMOKER)
    local health=body and body:getOverallBodyHealth()
    local healthSafe=type(health)=="number" and health>0 and health<95 and body.isInfected
        and body:isInfected()==false and body:getNumPartsBleeding()==0 and body.getNumPartsBitten
        and body:getNumPartsBitten()==0 and read("POISON")==0 and read("SICKNESS")==0 and read("FOOD_SICKNESS")==0
        and read("ZOMBIE_INFECTION")==0 and read("ZOMBIE_FEVER")==0
    local painEffect=player.getPainEffect and player:getPainEffect()
    local painDelta=player.getPainDelta and player:getPainDelta()
    local painReliefActive=(type(painEffect)=="number" and painEffect>0) or (type(painDelta)=="number" and painDelta>0)
    return {BOREDOM=read("BOREDOM"),PAIN=read("PAIN"),STRESS=read("STRESS"),stiffness=stiff,painReliefActive=painReliefActive,
        HUNGER=read("HUNGER"),hungerLevel=Needs.level(player,"food"),PANIC=read("PANIC"),UNHAPPINESS=read("UNHAPPINESS"),HEALTH=health,healthSafe=healthSafe,
        healFactor=SandboxVars and SandboxVars.Meditation and SandboxVars.Meditation.HealFactor,
        withdrawal=smoking and read("NICOTINE_WITHDRAWAL") or nil,mindTier=tier}
end

function Controller.mindfulnessEnabled()
    return SandboxVars and SandboxVars.Text and SandboxVars.Text.DividerMeditationNew==true
end

function Controller.mindfulnessClock()
    local clock=getGameTime()
    local hours=clock and clock.getWorldAgeHours and clock:getWorldAgeHours()
    local day=clock and clock.getMinutesPerDay and clock:getMinutesPerDay()
    return type(hours)=="number" and hours>=0 and hours<math.huge and hours*60 or nil,
        type(day)=="number" and day>0 and day<math.huge and day or 120
end

function Controller.armMindfulnessWatch(player,state,now,plan,readings,fresh)
    if not Controller.mindfulnessEnabled() or not WellnessInfo.supported()
            or (Options.practiceCare and not Options.practiceCare()) then return end
    if not fresh and (state.mindfulnessWatch or (state.mindfulnessWatchNext and now<state.mindfulnessWatchNext)) then return end
    local watch=PracticeCare.watch(plan,readings or practiceReadings(player,nil,true))
    if not watch then return end
    local world,day=Controller.mindfulnessClock()
    local minutes=PracticeCare.receiptMinutes(watch.target,SandboxVars.LS and SandboxVars.LS.MoodUpdate,SandboxVars.DayLength)
    local settle=isClient() and 10000 or 2500
    watch.worldExpires=world and world+minutes
    watch.notBefore=now+settle
    -- Passive only: permit a Lua/server flush even if the tier expires first.
    -- A bounded wall deadline still wins with a missing or frozen clock.
    watch.expires=now+math.max(15000,minutes*math.min(day,1440)*60000/1440+settle)
    state.mindfulnessWatch,state.mindfulnessWatchNext=watch,now+120000
    if watch.target=="hunger" then
        state.hungerAid=state.hungerAid or {tried=true}
        if criticalNeed(player,"food") and state.hungerAid.best then
            -- Within one starvation episode, oscillations above the previous low are not net progress.
            watch.before=math.min(watch.before,state.hungerAid.best)
        end
    end
end

function Controller.observeMindfulness(player,state,head,now)
    local watch=state.mindfulnessWatch
    if not watch then return end
    local world=Controller.mindfulnessClock()
    local expired=(watch.worldExpires and world and world>=watch.worldExpires and now>=watch.notBefore) or now>=watch.expires
    if expired or not Controller.mindfulnessEnabled()
            or (Options.practiceCare and not Options.practiceCare())
            or (criticalNeed(player,"water") and (watch.target~="hunger" or not state.noEmergencyDrink
                or comfortSupplyAvailable(player,state,"water",true))) or (criticalNeed(player,"food") and watch.target~="hunger") then
        if watch.target=="hunger" and state.hungerAid then
            if not expired then state.hungerAid=nil -- displaced by a real priority, not a failed attempt
            elseif not state.hungerAid.helped or (criticalNeed(player,"food")
                    and (Tiers.current(player,"meditation") or watch.targetTier)>=watch.targetTier) then
                state.hungerAid.failed=true
            end
        end
        state.mindfulnessWatch=nil
        return
    end
    -- Ordinary training may coexist only with no direct matching benefit.
    if head and (head.autoMindfulOwner~=state or not Controller.canShareMindfulnessWatch(state,state.phase)) then
        state.mindfulnessWatch=nil
        return
    end
    local readings=practiceReadings(player,nil,true)
    if (watch.target=="pain" and readings.painReliefActive) or (watch.target=="health" and not PracticeCare.healingEnabled(readings.healFactor)) then
        state.mindfulnessWatch=nil; return
    end
    if PracticeCare.observed(watch,readings) then
        if watch.target=="hunger" and state.hungerAid then
            state.hungerAid.helped=true
            if criticalNeed(player,"food") then state.hungerAid.best=readings.HUNGER end
        end
        state.mindfulnessWatch=nil
        state.practiceCareNotice="Observed " .. (watch.target=="health" and "health improve" or watch.target .. " ease")
            .. " after native Mindfulness became active."
        state.practiceCareNoticeUntil=now+5000
    end
end

local function practiceCare(player,state,now,m,y,meditation,yoga,training,reading,pain,hungerOnly,healthOnly)
    local retry=state.utilityTierRetry
    if retry and (now<retry.startedAt or now>=retry.expires) then state.utilityTierRetry=nil; retry=nil end
    local cooling=state.practiceCareNext and now<state.practiceCareNext
    local sleepForRelief=state.sleepBlock=="pain" or state.sleepBlock=="panic"
    if state.excursion or (cooling and not healthOnly and not retry and not state.recovery and not state.noConfirmedFood and not sleepForRelief)
            or not Tiers.wellnessEnabled() or (Options.practiceCare and not Options.practiceCare()) then return false end
    local seated=state.recovery and player:isSittingOnFurniture()
    local readings=practiceReadings(player,meditation)
    local nextAt=state.practiceCareNext
    if retry and not healthOnly then nextAt=nil end
    if healthOnly then
        local sample=state.healSample
        local hp=readings.HEALTH
        -- With little HP left, don't spend several world minutes building a
        -- tier while health is dropping. Require a continuously watched
        -- quiet interval before starting; pre-existing Perfect can passively heal.
        local continuous=sample and now>=sample.at and now-sample.at<=1000
        local stable=continuous and hp and hp>=sample.health-0.01
        if not readings.healthSafe then state.healSample=nil; return false end
        state.healSample={health=hp,at=now,since=stable and sample.since or now}
        if (readings.mindTier or 0)<3 and now-state.healSample.since<1000 then return false end
        retry=nil
    end
    local course,passive=PracticeCare.choose({now=now,nextAt=nextAt,
        meditationRank=meditation,yogaRank=yoga,
        meditationReady=not seated and m.ready and careGearSafe(player,"meditation",meditation),
        yogaReady=not seated and y.ready and careGearSafe(player,"yoga",yoga),
        boredom=readings.BOREDOM,pain=readings.PAIN,stress=readings.STRESS,stiffness=readings.stiffness,
        reading=reading,painTreatment=pain,painReliefActive=readings.painReliefActive,
        preferTraining=not state.sleepBlock and training or nil,recovery=state.recovery,sleepRelief=sleepForRelief,
        hunger=readings.HUNGER,hungerLevel=readings.hungerLevel,withdrawal=readings.withdrawal,mindTier=readings.mindTier,
        panic=readings.PANIC,health=readings.HEALTH,healthSafe=readings.healthSafe,healFactor=readings.healFactor,
        unhappiness=readings.UNHAPPINESS,unhappinessReady=WellnessInfo.supported(),
        sleepBlocked=state.sleepBlock=="panic",confirmedFood=not state.noConfirmedFood,
        mindfulEnabled=Controller.mindfulnessEnabled() and WellnessInfo.supported(),
        hungerOnly=hungerOnly,healthOnly=healthOnly,renewHunger=not state.hungerAid or state.hungerAid.helped,
        acquireHunger=not (state.hungerAid and state.hungerAid.tried and not state.hungerAid.helped)})
    if passive then Controller.armMindfulnessWatch(player,state,now,passive,readings,
        hungerOnly and not (state.mindfulnessWatch and state.mindfulnessWatch.target=="hunger")) end
    if not course then
        if retry then state.utilityTierRetry=nil end
        return false
    end
    course.startedAt,course.before=now,readings
    course.rank=course.kind=="yoga" and yoga or meditation
    course.earlierRecovery=state.recovery==true
    course.lowHealthHeal=healthOnly or nil
    if not healthOnly and Options.minimumTier and course.need~="unhappiness" then
        local desired=Tiers.clamp(course.kind,Options.minimumTier("recovery",course.kind),course.rank)
        if desired>0 and Tiers.current(player,course.kind)~=nil then
            course.tierMinimum={kind=course.kind,target=desired}
            course.tierMaxMs=math.max(course.maxMs,course.kind=="meditation" and recoveryTierMs[desired] or 0)
            course.tierSleepBlocked=state.sleepBlock=="panic"
        end
    end
    if retry then
        local tier=course.tierMinimum
        if not tier or course.kind~=retry.kind or course.need~=retry.need or course.target~=retry.effect
                or tier.target~=retry.tier then
            state.utilityTierRetry=nil
            if cooling then return false end
        else course.tierRetry=true end
    end
    if not hungerOnly and not healthOnly and Controller.pinRecoveryTier(player,state,course) then
        state.utilityTierRetry=nil
        return Controller.runRecoveryTierCourse(player,state,course,now)
    end
    if train(player,state,course.kind,false,course) then state.utilityTierRetry=nil; return true end
    -- Posture changes are their own native batches and must settle before
    -- choosing again. Failed admission is not a successful care attempt.
    if state.pending and #state.pending>0 then return true end
    if (course.target=="hunger" or sleepForRelief or state.recovery)
            and (state.phase=="sitting" or state.phase=="between" and state.cycleUntil) then return true end
    if state.practiceCare then
        state.pending,state.practiceCare=nil,nil
    end
    state.utilityTierRetry=nil
    return false
end

-- The shared survival scheduler calls this only after intake and its
-- competing safety gates. Do not run unrelated practice at very low HP.
function Controller.lowHealthHealing(player,state,now)
    local med,yoga=levels(player)
    return practiceCare(player,state,now,meditationGate(player),{ready=false},med,yoga,nil,nil,nil,false,true)
end

-- No training while critically hungry: either a single bounded own practice
-- or a queue-free, time-limited wait for an actual change in the hunger stat.
function Controller.criticalHungerRelief(player,state)
    local msg=state.noEmergencyDrink and "Critical thirst and hunger. Watching for native hunger relief while rechecking for safe water or food."
        or "Critical hunger. Watching for native hunger relief; suitable food still comes first."
    local watch=state.mindfulnessWatch
    if watch and watch.target=="hunger" then
        local tier=Tiers.current(player,"meditation")
        if state.hungerAid and state.hungerAid.helped and tier and tier<watch.targetTier then
            state.mindfulnessWatch=nil -- the last badge helped and is spent; allow renewal now
        else
            setPhase(state,"recovering",msg,state.noEmergencyDrink and "water-unavailable" or "food-unavailable")
            return true
        end
    end
    local now=getTimestampMs()
    local med,yoga=levels(player)
    if practiceCare(player,state,now,meditationGate(player),yogaAdmission(player),med,yoga,nil,nil,nil,true) then return true end
    if state.mindfulnessWatch and state.mindfulnessWatch.target=="hunger" then
        setPhase(state,"recovering",msg,state.noEmergencyDrink and "water-unavailable" or "food-unavailable")
        return true
    end
    return false
end

local function waitForYoga(player,state,gate,bored)
    if gate.kind=="endurance" then
        restForYoga(player,state,gate.reason)
    elseif gate.kind=="embarrassment" and sit(player,state) then
        setPhase(state,"recovering",bored and "Waiting for embarrassment to fade so yoga can relieve boredom."
            or "Waiting for Lifestyle embarrassment to fade before the next yoga session.", "yoga-gate",gate.reason)
    end
end

-- Only continuously sampled empty admission time earns a distance/posture
-- request. A queued action, inspection, or an unobserved pause doesn't.
local function sampleRecoveryIdle(state,now)
    local previous=state.recoveryIdleLast
    if not previous or now<previous or now-previous>=recoveryPolicy.quietGapMs then
        state.recoveryIdleAt,state.recoverySitAttempted=now,nil
    end
    state.recoveryIdleLast=now
    state.recoveryReadyToScout=now-state.recoveryIdleAt>=recoveryPolicy.quietMs
end

local function restNaturally(player,state,endurance)
    if endurance==nil or EnduranceGoal.full(endurance) then
        state.recoverySitAttempted=nil
        return false
    end
    -- Standing still already allows native recovery near full; don't
    -- toggle posture for the last fraction. Never unseat or hold a queue.
    if state.recoveryReadyToScout and not state.recoverySitAttempted
            and (endurance<recoveryPolicy.sitBelow or state.recoveryFull)
            and not player:isSitting() and not player:isSitOnGround() and not player:isSittingOnFurniture()
            and not player:getModData().IsSittingOnSeat and not (player.isGettingUp and player:isGettingUp()) then
        state.recoverySitAttempted=true
        player:reportEvent("EventSitOnGround")
    end
    setPhase(state,"resting","Letting endurance recover naturally. Other actions can start.")
    return true
end

-- These preventive bites/sips are idle opportunities, not a reason to
-- interrupt an action or to delay sleep, pain treatment, or other normal care.
local function earlyRecoverySupply(player,state,localOnly)
    local full=player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN)>=3
    for _,kind in ipairs({"water","food"}) do
        local need=stat(player,kind=="water" and "THIRST" or "HUNGER")
        if need>=recoveryPolicy.supplyAt and need<Consumables.careThreshold and (kind=="water" or not full)
                and supply(player,state,kind,kind=="water" and full,nil,nil,true,localOnly) then return true end
    end
    return false
end

-- At a witnessed stop, share the same owned supply/fixture admission as
-- normal care. No sleep, speculative loot, practice, or waiting in the field.
-- Reopen a need only for measurably incomplete portions. Eight witnessed turns
-- bound a pantry of tiny snacks or needs fluctuating in multiplayer.
function Controller.continueErrands(player,state,now)
    local trip=state.excursion
    if not trip or (trip.stage~="errands" and trip.stage~="urgent") or not Options.searchNearby()
            or atOrigin(player:getSquare(),trip.origin) or trip.outing.turns>=8 then return false end
    local origin=resolveOrigin(trip.origin)
    if not origin or not Storage.permitted(player,origin) then return false end
    local served=trip.outing.served
    local full=player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN)>=3
    local function admitted(queued)
        if queued and state.excursion==trip and (state.supplyKind or state.fluidSupply or state.lifestyleCourse or state.lifestylePickup) then
            trip.stage,trip.localErrand="care",true
            if trip.walkTiming then trip.walkTiming.invalid=true end
        end
        return queued and (state.phase~="seated" or state.pending~=nil)
    end
    local function stock(kind,urgent)
        local renewed=urgent and Needs.due(player,kind)
        return (not served[kind] or renewed) and (kind~="food" or not full)
            and admitted(supply(player,state,kind,kind=="water" and full,nil,nil,true,trip.stage=="urgent"))
    end
    local function needs(kind)
        local value=stat(player,kind=="water" and "THIRST" or "HUNGER")
        return Needs.due(player,kind) or (state.careNeeds[kind] and value>(state.recovery and recoveryPolicy.remainder or Consumables.restoredThreshold))
    end
    local urgentWater,urgentFood=criticalNeed(player,"water"),criticalNeed(player,"food")
    if urgentWater or urgentFood then
        if urgentWater and stock("water",true) then return true end
        if urgentFood and stock("food",true) then return true end
        return false -- home has the normal missing-resource/wait/fallback policy
    end
    if state.lowHealth then
        return needs("water") and stock("water") or needs("food") and stock("food") or false
    end
    if trip.stage=="urgent" then return false end
    if (state.recovery or state.backgroundPractice) and not trip.openedWindow then
        trip.openedWindow=true
        state.cooperativePending={}
        if Controller.waitCooperativeWindow(player,state,now) then return true end
    end
    local bedtime=sleepReadiness(player,state)
    if sleepAdmitted(bedtime) or bedtime=="dialog" or state.recoveryFull and EnduranceGoal.full(EnduranceGoal.read(player))
            or state.cycle and atSkillGoal(player,state) then return false end
    if needs("water") and stock("water") or needs("food") and stock("food") then return true end
    local radius=math.min(Options.searchRadius(),trip.outing.radius)
    local target=LifestyleCare.ready(player,state,now,state.collectNearby,radius,origin,served)
    if target and admitted(lifestyleCare(player,state,target,now)) then return true end
    if stock("pain") then return true end
    if state.recovery then
        for _,kind in ipairs({"water","food"}) do
            local value=stat(player,kind=="water" and "THIRST" or "HUNGER")
            if value>=recoveryPolicy.supplyAt and value<Consumables.careThreshold and stock(kind) then return true end
        end
    end
    local meditation=state.tierGoal and state.tierGoal.kind=="meditation"
        or state.cycle and state.mode~="yoga" and (state.backgroundPractice or levels(player)<10)
        and not (state.cycle.owed=="yoga" and yogaAdmission(player).ready and meditationGate(player).kind~="boredom")
    return (state.recovery or meditation or bedtime) and stat(player,"BOREDOM")>=(state.recovery and recoveryPolicy.readAt or 20)
        and not player:tooDarkToRead() and stock("literature") or false
end

local function advanceRecovery(player,state,now)
    local endurance=EnduranceGoal.read(player)
    if state.recoveryFull and endurance==nil then
        Controller.stop(player,"Could not read endurance. Stopped without assuming recovery.")
        return
    end
    if state.recoveryFull and EnduranceGoal.full(endurance) and not state.excursion then
        state.active=false
        state.endPhase,state.endMessage="complete","Endurance is full. Recovery finished."
        setPhase(state,state.endPhase,state.endMessage)
        showSessionEnd(player,state)
        return
    end
    sampleRecoveryIdle(state,now)
    if care(player,state) then return end
    if lifestyleCare(player,state,lifestyleReady(player,state,now),now) then return end
    local pain=painAvailable(player,state,now)
    if pain and supply(player,state,"pain") then return end
    if earlyRecoverySupply(player,state,true) then return end
    local boredom=stat(player,"BOREDOM")
    local wantsReading=boredom>=recoveryPolicy.readAt
    if wantsReading and supply(player,state,"literature",false,nil,nil,true,true) then return end
    if state.recoveryStockWaiting then
        if not waitForSleep(player,state) then
            setPhase(state,"recovery-idle","Waiting for a quiet gap before collecting a known supply.")
        end
        return
    end
    local med,yoga=levels(player)
    if Controller.resumeRecoveryTier(player,state,now,med,yoga) then return end
    if practiceCare(player,state,now,meditationGate(player),yogaAdmission(player),med,yoga,nil,nil,pain) then return end
    if waitForSleep(player,state) then return end
    if state.recoveryReadyToScout then
        if earlyRecoverySupply(player,state,false) then return end
        if wantsReading and supply(player,state,"literature",false,nil,nil,true) then return end
    end
    -- Recovery has no owed XP turn. Only consider blind MP inspection after
    -- known care and optional native relief have both had their opportunity.
    if state.recoveryReadyToScout and isClient() and Options.searchNearby()
            and not (state.noConfirmedFood and Controller.hungerOpportunity(player,state)) then
        state.recoveryUnknown=true
        local started=false
        for _,kind in ipairs({"water","food","literature"}) do
            local wanted=kind=="literature" and boredom>=20
                or kind=="water" and Needs.due(player,"water")
                or kind=="food" and Needs.due(player,"food")
                    and player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN)<3
            local worldOnly=kind=="water" and player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN)>=3
            if wanted then
                local target=nearbyTarget(player,state,kind,worldOnly)
                if target and target.unknown then started=beginExcursion(player,state,kind,worldOnly); if started then break end end
            end
        end
        state.recoveryUnknown=nil
        if started then return end
    end
    if not restNaturally(player,state,endurance) then
        local strict=state.recoveryTier
        setPhase(state,"recovery-idle",strict and strict.waiting or "Recovery is watching for needs. You can carry on with other actions.")
    end
end

function Controller.finishTierGoal(player,state)
    local goal=state.tierGoal
    state.active,state.trainingKind=false,nil
    closePractice(state)
    if state.pending then clearOwned(player,state) end
    state.endPhase,state.endMessage="complete","Reached "..(Tiers.label(goal.kind,goal.target) or "the selected tier")..". Practice finished."
    setPhase(state,state.endPhase,state.endMessage)
    showSessionEnd(player,state)
end

-- Count only observed idle time at the native gate, and only elapsed time
-- with the same owned practice. Human work and pauses aren't failed attempts.
local function budget(goal,now,key,elapsed)
    local before=goal[key]
    if before and now>=before and now-before<=2500 then goal[elapsed]=(goal[elapsed] or 0)+now-before end
    goal[key]=now
    return goal[elapsed] or 0
end

-- Strict Recovery is a single objective anchored to a practice Recovery chose
-- for a real need. It is neither a training turn nor a buff maintenance loop.
function Controller.strictRecoveryEnabled(state)
    return state.mode=="recovery" and Options.strictRecoveryTier and Options.strictRecoveryTier()==true
        and (not Options.practiceCare or Options.practiceCare())
end

function Controller.pinRecoveryTier(player,state,course)
    local minimum=course.tierMinimum
    if state.recoveryTier or not minimum or not Controller.strictRecoveryEnabled(state)
            or not WellnessInfo.supported() or player:getModData().IsSittingOnSeat then return false end
    local selected=Options.minimumTier("recovery",course.kind)
    local suppressed=state.recoveryTierSuppressed and state.recoveryTierSuppressed[course.kind]
    if suppressed==selected then return false end
    local current=Tiers.current(player,course.kind)
    local floor=course.need=="mindfulness" and course.targetTier or 0
    local target=math.max(minimum.target,floor)
    -- No reason to hold the queue for a badge already active. The useful
    -- ordinary action may still proceed under the usual relief rules.
    if current==nil or current>=target or Tiers.clamp(course.kind,target,course.rank)~=target then return false end
    local goal={kind=course.kind,target=target,selected=selected,floor=floor,best=current}
    state.recoveryTier,course.strictTier=goal,goal
    return true
end

function Controller.endRecoveryTier(state,goal,now,result,reason)
    state.recoveryTier,goal.result=nil,result
    if result=="failed" then
        -- Don't immediately reseed the same failed minimum from the same
        -- lingering symptom. Ordinary Recovery keeps looking after needs.
        state.recoveryTierSuppressed=state.recoveryTierSuppressed or {}
        state.recoveryTierSuppressed[goal.kind]=goal.selected
    end
    state.tierNotice,state.tierNoticeUntil=reason,now+15000
end

function Controller.missRecoveryTier(state,goal,now,finished)
    local key=finished and "attempts" or "launchMisses"
    goal[key]=(goal[key] or 0)+1
    if goal[key]>=tierAttempts then
        Controller.endRecoveryTier(state,goal,now,"failed",finished
            and "Lifestyle did not reach the Recovery tier after four completed practices."
            or "Lifestyle repeatedly could not start or finish the Recovery practice.")
    else
        goal.nextAt=now+ActionYield.cooperativeWindowMs
    end
end

function Controller.runRecoveryTierCourse(player,state,course,now)
    if train(player,state,course.kind,false,course) then return true end
    if state.practiceCare==course then
        -- A native menu call with no admitted timed action is not a practice.
        state.practiceCare,state.pending=nil,nil
        if course.target=="hunger" then state.hungerAid=nil end
        if state.recoveryTier==course.strictTier then Controller.missRecoveryTier(state,course.strictTier,now,false) end
    end
    -- Posture preparation and a newly occupied queue keep the same objective.
    return true
end

function Controller.resumeRecoveryTier(player,state,now,med,yoga)
    local goal=state.recoveryTier
    if not goal then return false end
    if state.excursion or state.contextVisible or state.inspectingUI or (getGameSpeed and getGameSpeed()==0) then return false end
    if goal.nextAt and now<goal.nextAt then return true end
    local rank=goal.kind=="meditation" and med or yoga
    local gate=goal.kind=="meditation" and meditationGate(player) or yogaAdmission(player)
    if not gate.ready or player:isSittingOnFurniture() or player:getModData().IsSittingOnSeat
            or not careGearSafe(player,goal.kind,rank) then
        goal.waiting="Recovery tier pending: "..(Tiers.label(goal.kind,goal.target) or "selected tier")
            ..". Waiting for Lifestyle's requirements or safe equipment."
        -- Normal care may remove the blocker, including a different useful
        -- practice. It cannot create another strict objective while this waits.
        return false
    end
    goal.waiting=nil
    return Controller.runRecoveryTierCourse(player,state,{kind=goal.kind,need="tier",strictTier=goal,
        earlierRecovery=true,rank=rank,startedAt=now,before=practiceReadings(player,med,true)},now)
end

-- Read even during foreign work: observing that the badge is genuinely active
-- can satisfy the objective without claiming credit for somebody else's action.
function Controller.observeRecoveryTier(player,state,queue,now,paused)
    local goal=state.recoveryTier
    if not goal and not state.recoveryTierSuppressed then return end
    if not Controller.strictRecoveryEnabled(state) then
        state.recoveryTierSuppressed=nil
        if goal then Controller.endRecoveryTier(state,goal,now,"cancelled","Strict Recovery tier target was turned off.") end
        return
    end
    if state.recoveryTierSuppressed then
        local stillSuppressed=false
        for kind,chosen in pairs(state.recoveryTierSuppressed) do
            if not Options.minimumTier or Options.minimumTier("recovery",kind)~=chosen then
                state.recoveryTierSuppressed[kind]=nil
            else stillSuppressed=true end
        end
        if not stillSuppressed then state.recoveryTierSuppressed=nil end
    end
    if not goal then return end
    local med,yoga=levels(player)
    local rank=goal.kind=="meditation" and med or yoga
    local selected=Options.minimumTier and Options.minimumTier("recovery",goal.kind)
    local current=WellnessInfo.supported() and Tiers.current(player,goal.kind) or nil
    goal.current=current
    local reachable=selected==goal.selected and goal.target or Tiers.clamp(goal.kind,selected,rank)
    local target=math.max(reachable,goal.floor)
    if current==nil or reachable==0 or Tiers.clamp(goal.kind,target,rank)~=target then
        Controller.endRecoveryTier(state,goal,now,"cancelled","The Recovery tier is no longer selected, unlocked, or available.")
        return
    end
    if selected~=goal.selected then
        goal.target,goal.selected,goal.best=target,selected,current
        goal.attempts,goal.launchMisses,goal.workMs,goal.launchMs,goal.nextAt=nil,nil,nil,nil,nil
        goal.head,goal.sampleAt,goal.launchAt,goal.waiting=nil,nil,nil,nil
    end
    local course,head=state.practiceCare,queue[1]
    local ownCourse=course and course.strictTier==goal
    local running=ownCourse and head and head.autoMindfulOwner==state and isPractice(head,goal.kind)
        and not head.autoMindfulFinished and not head.autoMindfulStopped
    local yogaMayForfeit=running and goal.kind=="yoga" and head:isStarted()
        and (type(head.skillLevel)=="number" and head.skillLevel or course.rank)<10 and head.gainedXP~=0
    if current>=goal.target and not yogaMayForfeit then
        -- Stock Yoga's early stop can remove Zen. If it might, use the
        -- genuine post-action Value instead of paying a penalty for success.
        Controller.endRecoveryTier(state,goal,now,"met",(Tiers.label(goal.kind,goal.target) or "The selected tier")
            .." is active. Recovery will continue watching for needs.")
        return
    end
    if paused or not running then goal.sampleAt,goal.launchAt=nil,nil end
    if not ownCourse or not state.pending or course.strictReceipt or (head and head.autoMindfulOwner==state) then return end
    local finished, found=false,false
    for _,action in ipairs(state.pending) do
        if action.autoMindfulOwner==state and isPractice(action,goal.kind) then
            found=true
            if action.autoMindfulFinished and not action.autoMindfulStopped then finished=true end
        end
    end
    if finished or (not paused and not state.contextInterrupted and (found or #state.pending>0)) then
        course.strictReceipt=true
        Controller.missRecoveryTier(state,goal,now,finished)
    end
end

function Controller.waitTierGate(player,state,goal,gate)
    if (not state.tierGoal and not gate.temporary)
            or budget(goal,getTimestampMs(),"waitAt","waitMs")>=tierWaitingMs then
        local reason="Lifestyle kept blocking the selected tier practice."
        if state.tierGoal then Controller.stop(player,reason.." Check its requirements, then start again.",
            goal.kind.."-gate",gate.reason)
        else Controller.suspendTurnTier(state,goal,reason) end
        return
    end
    if goal.kind=="yoga" and gate.temporary then waitForYoga(player,state,gate,false)
    else setPhase(state,"recovering","Waiting for Lifestyle to allow the tier practice. Other actions can take over.",
        goal.kind.."-gate",gate.reason) end
end

local function advanceTierGoal(player,state)
    local goal=state.tierGoal
    local now=getTimestampMs()
    local current=Tiers.current(player,goal.kind)
    if (goal.met or current and current>=goal.target)
            and not (criticalNeed(player,"water") or criticalNeed(player,"food") or sleepAdmitted(sleepReadiness(player,state))) then
        Controller.finishTierGoal(player,state)
        return
    end
    if care(player,state) then return end
    if lifestyleCare(player,state,lifestyleReady(player,state,now),now) then return end
    if painAvailable(player,state,now) and supply(player,state,"pain") then return end
    if (goal.kind=="meditation" or state.sleepBlock) and stat(player,"BOREDOM")>=20
            and (not state.sleepBlock or comfortSupplyAvailable(player,state,"literature",true))
            and supply(player,state,"literature",false,nil,nil,state.sleepBlock~=nil) then return end
    local med,yoga=levels(player)
    if state.sleepBlock then
        local m,y=meditationGate(player),yogaAdmission(player)
        if practiceCare(player,state,now,m,y,med,yoga,nil,nil,false) or waitForSleep(player,state) then return end
    end
    local rank=goal.kind=="meditation" and med or yoga
    if goal.met or current and current>=goal.target then Controller.finishTierGoal(player,state); return end
    if Tiers.clamp(goal.kind,goal.target,rank)~=goal.target or current==nil then
        Controller.stop(player,"The selected tier is no longer available. Check the current skill and Lifestyle settings.")
        return
    end
    if goal.failure then Controller.stop(player,goal.failure); return end
    local gate=goal.kind=="meditation" and meditationGate(player) or yogaAdmission(player)
    if gate.ready then train(player,state,goal.kind); return end
    if gate.temporary then Controller.waitTierGate(player,state,goal,gate); return end
    Controller.stop(player,gate.reason or "Lifestyle blocked the selected practice.",goal.kind.."-gate",gate.reason)
end

local function configuredTierGroup(state)
    if state.backgroundPractice then return "capped" end
    if state.mode=="both" then return "rotation" end
end

local function pinTurnTier(player,state,kind,rank)
    if state.turnTier or not Options.minimumTier then return end
    local group=configuredTierGroup(state)
    if not group then return end
    local chosen=Options.minimumTier(group,kind)
    local suppressed=state.tierSuppressed and state.tierSuppressed[kind]
    if suppressed and suppressed.group==group and suppressed.chosen==chosen then return end
    if suppressed then state.tierSuppressed[kind]=nil end
    local minimum=Tiers.clamp(kind,chosen,rank)
    if minimum<=0 then return end
    local goal={kind=kind,target=minimum,chosen=chosen,group=group}
    if Tiers.current(player,kind)==nil then
        Controller.suspendTurnTier(state,goal,"Could not read the current Lifestyle tier.")
        return
    end
    state.turnTier=goal
    if not state.cycle.owed then
        goal.addedDebt=true
        setCycleDebt(state.cycle,kind)
    end
end

local function recheckTurnTier(state,meditation,yoga)
    local goal=state.turnTier
    if not goal then return end
    local rank=goal.kind=="meditation" and meditation or yoga
    -- Level 10 is still the end of an XP session, not a reason to keep
    -- practicing the finished skill. A level gain otherwise affects the
    -- next turn, not an already pinned reachable target.
    if (not state.backgroundPractice and rank>=10) or Tiers.clamp(goal.kind,goal.target,rank)~=goal.target
            or Options.minimumTier(goal.group,goal.kind)~=goal.chosen then
        state.turnTier=nil
        return
    end
    return goal
end

-- Low HP pauses *training objectives*, not the care that might reverse the
-- loss. This admission is shared by Recovery, normal training and tier goals.
-- It never treats health loss as proof of starvation or a healable injury.
function Controller.lowHealthCare(player,state,now)
    if state.recovery then sampleRecoveryIdle(state,now) end
    if care(player,state) then return end
    if state.noConfirmedFood and Controller.hungerOpportunity(player,state) then
        local med,yoga=levels(player)
        if practiceCare(player,state,now,meditationGate(player),{ready=false},med,yoga,nil,nil,nil,true) then return end
    end
    if wantsPainCare(player,state,now) and supply(player,state,"pain",false,nil,nil,true,true) then return end
    if not Needs.due(player,"food") and not Needs.due(player,"water")
            and Controller.lowHealthHealing(player,state,now) then return end
    setPhase(state,"recovering","Health is low. Training is paused; watching for food, safe water and eligible recovery.")
end

-- Stop only a genuinely optional owned operation. An already-started sip,
-- portion, or native hunger/healing course must keep its real action/receipt.
function Controller.lowHealthTransition(player,state)
    state.lowHealth=state.active and not state.endurance and Needs.lowHealth(player) or nil
    if not state.lowHealth then state.healSample=nil; return false end
    local trip,kind,course=state.excursion,state.supplyKind,state.practiceCare
    local stock=kind=="food" or kind=="water" or kind=="pain" or (kind=="literature" and state.prerequisiteReadAttempted)
    local useful=course and (course.target=="hunger" or course.lowHealthHeal)
    local tripSafe=trip and (trip.kind=="food" or trip.kind=="water") and trip.target and not trip.target.unknown
    if not (trip and not tripSafe or state.pending and not (stock or useful or tripSafe)) then return false end
    state.excursion=nil
    yieldToPlayer(player,state,false,false,false,"Health is low. Pausing optional work to check survival needs.","recovery-danger")
    return true
end

local function advance(player, state)
    if state.lowHealth then Controller.lowHealthCare(player,state,getTimestampMs()); return end
    if state.recovery then advanceRecovery(player,state,getTimestampMs()); return end
    if state.endurance then train(player, state, "meditation"); return end
    if state.tierGoal then advanceTierGoal(player,state); return end
    local cycle=state.cycle
    local meditation,yoga=levels(player)
    local needsMeditation=state.mode~="yoga" and (state.backgroundPractice or meditation<10)
    local needsYoga=state.mode~="meditation" and (state.backgroundPractice or yoga<10)
    if not needsMeditation and not needsYoga then
        state.turnTier=nil
        setCycleDebt(cycle,nil)
        noteCycle(state,"complete",nil,nil)
        -- XP is complete, not the shared care session. Preserve the native
        -- hunger watch, route failures, loans and all other care observations.
        state.endPhase = "complete"
        showSessionEnd(player, state)
        state.endPhase, state.endMessage = nil, nil
        state.mode, state.recovery, state.cycle, state.trainingKind = "recovery", true, nil, nil
        state.recoveryHandoffArmed = nil
        setPhase(state, "recovering", "Selected skills reached level 10. Recovery stays on.")
        return
    end
    local policy=state.backgroundPractice and "alternate" or currentCyclePolicy(player)
    if policy~=cycle.policy then
        cycle.policy=policy
        cycle.cooperativeKind,cycle.cooperativeTurns=nil,nil
        setCycleDebt(cycle,nil)
        state.trainingKind=nil
    end
    if state.tierSuppressed then
        for kind,blocked in pairs(state.tierSuppressed) do
            if Options.minimumTier(blocked.group,kind)~=blocked.chosen then state.tierSuppressed[kind]=nil end
        end
    end
    local pinned=recheckTurnTier(state,meditation,yoga)
    local m,y=meditationGate(player),yogaAdmission(player)
    cycle.gates.meditation,cycle.gates.yoga=m,y
    local progress=Progress.snapshot(player)
    local medInput={needed=needsMeditation,eligible=m.ready,progress=progress.meditation,allowCapped=state.backgroundPractice}
    local yogaInput={needed=needsYoga,eligible=y.ready,progress=progress.yoga,allowCapped=state.backgroundPractice}
    local choice=TrainingCycle.choose(cycle.policy,cycle.lastCompleted,cycle.owed,medInput,yogaInput)
    setCycleDebt(cycle,choice.owed)
    local retained=state.trainingKind
    local owedReady=cycle.owed and ((cycle.owed=="meditation" and medInput.needed and medInput.eligible)
        or (cycle.owed=="yoga" and yogaInput.needed and yogaInput.eligible))
    local kind,preferred,reason=choice.kind,choice.preferred,choice.reason
    if not owedReady then
        if (retained=="meditation" and medInput.needed and medInput.eligible)
                or (retained=="yoga" and yogaInput.needed and yogaInput.eligible) then
            kind,reason=retained,"retained"
        elseif cycle.policy=="alternate" and not cycle.lastCompleted and not cycle.owed
                and needsMeditation and needsYoga and y.ready
                and (stat(player,"BOREDOM")>=10 or stat(player,"PAIN")>=15) then
            -- With no history, Yoga can be the useful opener for an
            -- uncomfortable survivor; established turns are never overridden.
            kind,preferred,reason="yoga","yoga","ready"
        end
    end
    if pinned then
        local input=pinned.kind=="meditation" and medInput or yogaInput
        preferred=pinned.kind
        kind=input.eligible and preferred or nil
        reason=kind and "retained" or "blocked"
    end
    local recovering=(pinned and pinned.kind=="yoga" or not pinned and cycle.owed=="yoga") and needsYoga and y.temporary
    local useBridge
    if recovering and m.ready then
        if state.mode=="yoga" and y.kind=="endurance" and careGearSafe(player,"meditation",meditation) then
            useBridge=yogaEnduranceBridge
        elseif (kind=="meditation" or pinned and needsMeditation) and not cycle.bridgeUsed then
            useBridge=true -- Preserve Train Both's one bounded fallback.
        end
    end
    if recovering then
        reason,preferred=useBridge and "bridge" or "recovery","yoga"
        kind=useBridge and "meditation" or nil
    end
    noteCycle(state,reason,preferred,kind)
    if care(player,state) then return end
    local now=getTimestampMs()
    if lifestyleCare(player,state,lifestyleReady(player,state,now),now) then return end
    local pain=painAvailable(player,state,now)
    if pain and supply(player,state,"pain") then state.mindfulnessWatch=nil;return end
    if not pain and wantsPainCare(player,state,now) then
        Controller.armMindfulnessWatch(player,state,now,{target="pain",targetTier=2})
    end
    local boredBlock=needsMeditation and m.kind=="boredom"
    local wantsReading=not state.sleepBlock and needsMeditation and (boredBlock or stat(player,"BOREDOM")>=20)
        and not (cycle.owed=="yoga" and y.ready and kind=="yoga" and not boredBlock)
        or state.sleepBlock and stat(player,"BOREDOM")>=20 and comfortSupplyAvailable(player,state,"literature",true)
    local reading
    if wantsReading then
        local atHand=not player:tooDarkToRead()
            and Supplies.choose(player,"literature",state.collectNearby or Options.searchNearby(),state.rejected)
        if atHand then
            if supply(player,state,"literature") then return end
        elseif nearbyTarget(player,state,"literature",false) then
            reading="speculative"
        end
    end
    -- Let a scheduled, admissible practice provide its normal benefits; a
    -- separate optional care course must never consume the owed turn.
    if practiceCare(player,state,now,m,y,meditation,yoga,kind,reading,pain) then return end
    if wantsReading then
        if supply(player,state,"literature",false,nil,nil,state.sleepBlock~=nil) then return end
        if not boredBlock then state.careNotice="No eligible literature found; meditation is still allowed." end
    end
    if waitForSleep(player,state) then return end
    if recovering then
        if useBridge then train(player,state,"meditation",useBridge)
        else
            -- One bounded native Meditation is enough during a single owed
            -- Yoga turn; further waits use ordinary seated recovery.
            state.trainingKind=nil
            if pinned then Controller.waitTierGate(player,state,pinned,y)
            else waitForYoga(player,state,y,boredBlock) end
        end
        return
    end
    if kind then
        pinTurnTier(player,state,kind,kind=="meditation" and meditation or yoga)
        train(player,state,kind)
        return
    end
    if pinned then
        Controller.waitTierGate(player,state,pinned,pinned.kind=="yoga" and y or m)
        return
    end
    if needsYoga and y.temporary then waitForYoga(player,state,y,boredBlock);return end
    if state.backgroundPractice then
        local gate=preferred=="yoga" and y or m
        setPhase(state,"recovering","Waiting until the selected practice is available. Other actions can take over.",
            preferred=="yoga" and "yoga-gate" or "meditation-gate",gate.reason)
        return
    end
    if boredBlock then
        if state.practiceCareRelieved and y.ready and state.practiceCareNext and now<state.practiceCareNext
                and (not Options.practiceCare or Options.practiceCare()) then
            setPhase(state,"recovering","Yoga eased boredom but Meditation is still blocked. Waiting briefly before trying care again.",
                "meditation-gate",m.reason)
            return
        end
        Controller.stop(player,"Lifestyle blocked meditation because boredom is too high. "
            ..(player:tooDarkToRead() and "Move to a lit spot to read. " or "Bring eligible leisure literature. ")
            ..(state.mode=="both" and "Yoga is currently unavailable." or "Select Train both if you also want yoga."),
            "meditation-gate",m.reason)
    else
        local reason=needsYoga and y.reason or m.reason
        Controller.stop(player,reason or "The selected practice is unavailable. Check Lifestyle's requirements.",
            needsYoga and "yoga-gate" or "meditation-gate",reason)
    end
end

local function finishPending(player, state, now)
    if state.phase=="restoring-mask" then
        -- A canceled cleanup doesn't invalidate a supply or count as a
        -- failed training action. Only the observed worn slot is its receipt.
        state.pending=nil
        return false
    end
    local failed = false
    for _, action in ipairs(state.pending) do
        if not action.autoMindfulFinished or action.autoMindfulStopped then failed = true end
    end
    if state.practiceCare then
        local course=state.practiceCare
        local realPractice=false
        for _,action in ipairs(state.pending) do
            if isPractice(action,course.kind) and action.autoMindfulFinished and not action.autoMindfulStopped then
                realPractice=true
            end
        end
        local readings=practiceReadings(player)
        if course.strictTier then
            if realPractice and not failed and PracticeCare.acquired(course,readings) then
                Controller.armMindfulnessWatch(player,state,now,course,readings,true)
            elseif course.target=="hunger" then
                state.hungerAid=nil
            end
            state.practiceCare,state.pending=nil,nil
            return false
        end
        local minimum=course.tierMinimum
        local current=minimum and Tiers.current(player,minimum.kind)
        local acquired=not failed and realPractice and course.need=="mindfulness" and PracticeCare.acquired(course,readings)
        if acquired then Controller.armMindfulnessWatch(player,state,now,course,readings,true) end
        local improved=not failed and realPractice and course.need~="mindfulness" and PracticeCare.improved(course,readings)
        if course.need~="mindfulness" and not improved and not failed and realPractice and isClient()
                and not criticalNeed(player,"water") and (course.hungerPrerequisite or not criticalNeed(player,"food"))
                and not sleepAdmitted(sleepReadiness(player,state)) then
            course.receiptUntil=course.receiptUntil or now+2500
            if now<course.receiptUntil then return true end
        end
        state.practiceCare,state.pending=nil,nil
        state.practiceCareNext=now+120000
        if minimum and current and current<minimum.target and not failed and realPractice and not course.tierRetry
                and Controller.tierCareNeed(course,readings) then
            -- At most one retry, reselected through normal care after the
            -- queue and higher-priority needs have been checked again.
            state.utilityTierRetry={kind=course.kind,need=course.need,effect=course.target,tier=minimum.target,
                startedAt=now,expires=now+15000}
        end
        state.practiceCareRelieved=improved and course.need=="boredom" or nil
        state.practiceCareNotice=acquired and "Mindfulness is active. Checking for the matching effect."
            or improved and "The game showed relief after the care practice."
            or (state.recovery and "The care practice did not confirm relief; continuing to monitor needs."
                or "The care practice did not confirm relief; returning to training.")
        if minimum and not (current and current>=minimum.target) then
            state.practiceCareNotice=state.practiceCareNotice.." The selected tier was not confirmed."
        end
        state.practiceCareNoticeUntil=now+5000
        return false
    elseif state.lifestylePickup then
        local pickup=state.lifestylePickup
        state.lifestylePickup,state.pending=nil,nil
        local item=not failed and Supplies.inventoryItem(player,pickup.target.item)
        if item and item:getContainer()==player:getInventory() and item:getID()==pickup.id and item:getFullType()==pickup.fullType
                and Supplies.careLoanAllowed(player,pickup.loan,state.collectNearby or Options.searchNearby()) then
            pickup.target.item=item
            if queueLifestyle(player,state,pickup.target,now) then return true end
        end
        LifestyleCare.reject(state,pickup.target,now)
        pickup.loan.defer=nil
        resetSupply(state)
        return false
    elseif state.lifestyleCourse then
        local course=state.lifestyleCourse
        local repair=course.before.preparation=="unclog"
        local prepared=repair and not failed and LifestyleCare.prepared(player,course)
        local received=not repair and not failed and (course.received or LifestyleCare.receipt(player,course))
        if not received and not prepared and not failed then
            course.waitUntil=course.waitUntil or now+2500
            if now<course.waitUntil then
                setPhase(state,course.target.kind,"Waiting for the game to confirm care.")
                return true
            end
        end
        -- Completing Unclog only prepares the fixture. Once the native
        -- equip/repair/flush batch drained, rebuild the exact Use option.
        -- A new clog, changed need, revoked access or dry fixture cannot
        -- trigger a second repair or manufacture restroom credit.
        if prepared and not criticalNeed(player,"water") and not criticalNeed(player,"food")
                and not sleepAdmitted(sleepReadiness(player,state)) and (Options.searchNearby() or not state.excursion and state.collectNearby)
                and LifestyleCare.accessible(player,course.target) then
            state.lifestyleCourse,state.pending=nil,nil
            if queueLifestyle(player,state,course.target,now,true) then return true end
        end
        LifestyleCare.reject(state,course.target,now)
        if state.supplyLoan then state.supplyLoan.defer=nil end
        state.lifestyleCourse,state.pending=nil,nil
        state.lifestyleNotice=repair and (prepared and "Toilet cleared, but using it is no longer available. Rechecking needs."
            or "Unclogging was not confirmed. Skipping this toilet.") or
            (not received and "The care action was not confirmed. Continuing without repeating it immediately." or nil)
        if received then
            if course.target.kind=="restroom" then state.restroomToolsTried=nil end
            learnFacility(state,course.target,now)
            Controller.scoutRelief(state,course.target.kind)
        end
        resetSupply(state)
        return false
    elseif state.fluidSupply and state.fluidSupply.phase ~= "using" then
        local kind = state.fluidSupply.kind
        local result, vessel, loan = finishFluidPreparation(player, state, failed, now)
        if result == "consume" then return useSupply(player, state, kind, vessel, loan) end
        return result == "pending"
    elseif state.collectingItem then
        local collected = Supplies.inventoryItem(player, state.collectingItem)
        if not collected then
            state.rejected[state.collectingItem:getID()] = true
            failed = true
            if state.supplyLoan then state.supplyLoan.defer = nil end
        else
            local item, kind, loan = collected, state.supplyKind, state.supplyLoan
            state.pending, state.collectingItem = nil, nil
            return useSupply(player, state, kind, item, loan)
        end
    elseif state.supplyKind == "pain" then
        -- A completed client animation is not an authoritative medicine receipt.
        local status, note = PainCare.receipt(player, state, now)
        state.painNotice, state.painNoticeUntil = note, now + 8000
        if status == "pending" then
            setPhase(state, "paincare", "Waiting for the game to confirm pain relief.")
            return true
        end
        if status=="confirmed" then
            if state.supplyStop then learnFacility(state,state.supplyStop,now); state.supplyStop=nil end
            Controller.scoutRelief(state,"pain")
        end
        if not Supplies.finishLoan(player, state.supplyLoan, now) then return true end
        if state.supplyLoan then state.supplyLoan.defer = nil end
        state.pending = nil
        resetSupply(state)
        return false
    elseif state.preparation then
        local preparation = state.preparation
        local candidates = {}
        local current = Supplies.inventoryItem(player, preparation.item)
        if current then
            local descriptor = Consumables.inspect(player, current)
            if descriptor[preparation.kind] and not descriptor.needsOpening then candidates[1] = current end
        end
        if #candidates == 0 then
            for _, item in ipairs(Supplies.newOutputs(player, preparation.before, preparation.descriptor.outputTypes)) do
                local descriptor = Consumables.inspect(player, item)
                if descriptor[preparation.kind] and not descriptor.needsOpening then candidates[#candidates + 1] = item end
            end
        end
        if #candidates == 1 then
            if preparation.loan and not preparation.loan.interference then
                for _, output in ipairs(Supplies.newOutputs(player, preparation.before, preparation.descriptor.outputTypes)) do
                    preparation.loan.items[#preparation.loan.items + 1] = output
                end
            end
            for _, tool in ipairs(preparation.tools) do tool.defer = nil end
            state.pending, state.preparation = nil, nil
            return useSupply(player, state, preparation.kind, candidates[1], preparation.loan)
        end
        if #candidates == 0 and not failed then
            state.awaitSupplyUntil = state.awaitSupplyUntil or now + 2000
            if now < state.awaitSupplyUntil then return true end
        end
        failed = true
        for _, tool in ipairs(preparation.tools) do tool.defer = nil end
        state.returnNotice = #candidates > 1 and "Opening created several matching items; they stay in your inventory for you to choose." or nil
    elseif state.supplyBaseline then
        local before = state.supplyBaseline
        local improved = (state.supplyKind == "food" and (stat(player, "HUNGER") < before.hunger
                or player:getNutrition():getCalories() > before.calories))
            or (state.supplyKind == "water" and stat(player, "THIRST") < before.thirst)
            or (state.supplyKind == "literature" and stat(player, "BOREDOM") < before.boredom)
        if improved then
            if state.supplySource then state.rejected[state.supplySource.object]=nil end
            local completed = not failed
            local verifiedGoal = state.supplyKind~="literature" and Consumables.goalSatisfied(
                player,state.supplyItem,state.supplyKind,state.supplyGoal,completed)
            if completed and verifiedGoal and state.supplyKind=="water" and state.supplySource and state.supplySource.directDrink then
                local source=state.supplySource
                local object,square=source.object,source.square
                if object and square and object:getSquare()==square and not source.item then
                    learnFacility(state,{kind="water",object=object,square=square,part=source.part},now)
                end
            end
            if completed and state.supplyStop and (state.supplyKind=="literature" or verifiedGoal)
                    and (not state.fluidSupply or state.fluidSupply.verifiedStop) then
                learnFacility(state,state.supplyStop,now)
                state.supplyStop=nil
            end
            if completed then
                local kind=state.supplyKind
                local partial=not verifiedGoal and ((kind=="food" and stat(player,"HUNGER")<before.hunger-Consumables.restoredThreshold)
                    or (kind=="water" and stat(player,"THIRST")<before.thirst-Consumables.restoredThreshold))
                Controller.scoutRelief(state,kind,partial)
            end
            failed = false
            if state.supplyKind == "literature" then Supplies.markRead(player, state.supplyItem)
            elseif verifiedGoal then
                state.careNeeds[state.supplyKind] = nil
            end
        elseif not failed then
            state.awaitSupplyUntil = state.awaitSupplyUntil or now + 2000
            if now < state.awaitSupplyUntil then return true end
            failed = true
        end
        if not Supplies.finishLoan(player, state.supplyLoan, now) then return true end
        if state.supplyLoan then state.supplyLoan.defer = nil end
    end
    if state.supplyLoan then state.supplyLoan.defer = nil end
    state.pending, state.collectingItem = nil, nil
    if failed then
        if state.supplyStop and state.excursion then ScoutMemory.forget(state.scoutMemory,state.excursion.target) end
        -- Rejection belongs to the exact source, not the survivor. Three
        -- refused meals/sips do not make the next distinct option unsafe.
        local intake=(state.supplyKind=="food" or state.supplyKind=="water") and (state.supplyItem or state.supplySource)
        if not intake then state.failures=state.failures+1 end
        if state.supplyItem then
            state.rejected[state.supplyItem:getID()] = state.supplyKind == "literature" and now + 60000 or true
        end
        if state.supplySource then Needs.rejectDryReceipt(state.rejected,state.supplySource.object,now) end
        if intake then
            setPhase(state,"recovering","No intake confirmed from this source. Checking the remaining food and water.")
        elseif state.failures >= 3 then
            resetSupply(state)
            Controller.stop(player, "Actions were interrupted repeatedly. Resolve the disturbance or blocked supplies, then start again.")
            return true
        end
    else state.failures = 0 end
    resetSupply(state)
    return false
end

local function updateEndurance(player, state, now, quiet)
    local value = EnduranceGoal.read(player)
    local head = queueFor(player)[1]
    local running = quiet and head and head.autoMindfulOwner == state
        and head.Type == "LSMeditateAction" and head:isStarted()
    if running then state.endurance.meditated = true end
    if value == nil then
        Controller.stop(player, "Could not read endurance. Stopped without assuming recovery.")
    elseif Needs.lowHealth(player) then
        Controller.stop(player,"Health is too low for endurance meditation.")
    elseif quiet and EnduranceGoal.full(value) then
        state.active = false
        clearOwned(player, state)
        state.endPhase, state.endMessage = "complete", "Endurance is full. Meditation finished."
        setPhase(state, state.endPhase, state.endMessage)
        if not state.endurance.meditated then state.session = nil end
        showSessionEnd(player, state)
    elseif criticalNeed(player, "water") or criticalNeed(player, "food") then
        Controller.stop(player, "A critical hunger or thirst need interrupted endurance meditation.")
    else
        if not EnduranceGoal.observe(state.endurance, value, now, running) then return false end
        Controller.stop(player, "Endurance did not improve during five minutes of meditation. Check what is preventing recovery.")
    end
    return true
end

local function missedTier(goal)
    goal.attempts=(goal.attempts or 0)+1
    if goal.attempts>=tierAttempts then
        goal.failure="Lifestyle did not reach "..(Tiers.label(goal.kind,goal.target) or "the selected tier")
            .." after four completed practices."
    end
end

function Controller.observeTierHead(player,state,head,now)
    local goal=state.tierGoal or state.turnTier
    if not goal or not head or state.phase~=goal.kind or head.autoMindfulOwner~=state
            or not isPractice(head,goal.kind) or head.autoMindfulStopped
            or (state.practiceWork and state.practiceWork.bridge) then return false end
    if state.turnTier and recheckTurnTier(state,levels(player))~=goal then return false end
    if state.tierGoal then
        local med,yoga=levels(player)
        local rank=goal.kind=="meditation" and med or yoga
        if Tiers.clamp(goal.kind,goal.target,rank)~=goal.target then
            Controller.stop(player,"The selected tier is no longer unlocked for this survivor.")
            return true
        end
    end
    local current=Tiers.current(player,goal.kind)
    if current==nil then
        local reason="Could not read the current Lifestyle tier."
        if state.tierGoal then Controller.stop(player,reason); return true end
        Controller.suspendTurnTier(state,goal,reason)
        return false
    end
    if goal.head~=head then goal.head,goal.sampleAt,goal.launchAt,goal.launchMs=head,nil,nil,nil end
    if not head:isStarted() then
        if budget(goal,now,"launchAt","launchMs")<30000 then return false end
        local reason="Lifestyle did not start the selected tier practice."
        if state.tierGoal then Controller.stop(player,reason); return true end
        Controller.suspendTurnTier(state,goal,reason)
        return false
    end
    -- Yoga's success writes Zen in native perform, never cut it short for
    -- a pre-existing badge or merely a pose/XP gain.
    if goal.kind=="meditation" and current>=goal.target and (state.tierGoal or goal.belowAtAdmission) then
        if state.tierGoal then Controller.finishTierGoal(player,state)
        else
            completeTurn(player,state,goal.kind)
            state.turnTier,state.trainingKind=nil,nil
            closePractice(state)
            state.unknownPauses,state.quietMs,state.lostWithoutAction=nil,nil,nil
            state.cooperativePending={}
            state.careHandoff=true
            clearOwned(player,state)
            setPhase(state,"between",(Tiers.label(goal.kind,goal.target) or "The selected tier")
                .." is active. Leaving a short opening for other actions.")
        end
        return true
    end
    if not goal.best or current>goal.best then goal.best,goal.workMs=current,0 end
    if budget(goal,now,"sampleAt","workMs")>=tierWorkMs then
        local reason="Lifestyle did not make tier progress during eight minutes of practice."
        if state.tierGoal then Controller.stop(player,reason); return true end
        Controller.suspendTurnTier(state,goal,reason)
    end
    return false
end

-- Consume a receipt before yielding to a foreign successor. A queued or
-- stopped action, an empty admission or an individual finished prep action
-- does not advance Both's turn or reset its interruption budget.
local function observeTrainingBatch(player, state, queue, now)
    local batch = state.pending
    if not state.active or not state.trainingKind or not trainingPhase(state.phase) or not batch then return false end
    if queue[1] and queue[1].autoMindfulOwner == state then return false end
    -- The upstream menu may enqueue gear preparation before deciding not
    -- to enqueue practice. Its bag action alone is not a training receipt.
    local practiced = false
    for _, action in ipairs(batch) do
        if action.autoMindfulPostureBounced and not queue[1] then
            state.pending=nil
            closePractice(state)
            return false -- Keep the selected leg; this is not an unexplained interruption.
        end
        if action.autoMindfulStopped or not action.autoMindfulFinished then return not queue[1] end
        if isPractice(action,state.trainingKind) then practiced = true end
    end
    if not practiced then return not queue[1] end
    local cycle,kind=state.cycle,state.trainingKind
    if kind=="yoga" then state.yogaPostureBounces,state.yogaStandCompletedAt=nil,nil end
    local bridge=state.practiceWork and state.practiceWork.bridge
    local goal=state.tierGoal
    if not goal and state.turnTier then goal=recheckTurnTier(state,levels(player)) end
    local reached
    if not bridge and goal and goal.kind==kind then
        local current=Tiers.current(player,kind)
        reached=current and current>=goal.target
        goal.head,goal.sampleAt=nil,nil
        if reached and state.tierGoal then goal.met=true end
        if not reached then
            missedTier(goal)
            if state.turnTier and (current==nil or goal.failure) then
                Controller.suspendTurnTier(state,goal,current==nil and "Could not read the current Lifestyle tier." or goal.failure)
                goal=nil
            end
        end
    end
    if cycle then
        state.stalledSkill=state.stalledSkill or observePractice(player,state,queue,now,true)
        -- A native completion may leave a requested tier turn unserved.
        -- Record the real action, but only a live tier receipt can spend it.
        if not bridge then
            cycle.skills[kind].completed=cycle.skills[kind].completed+1
            if not goal or goal.kind~=kind or reached then
                completeTurn(player,state,kind)
                if goal and goal.kind==kind then state.turnTier=nil end
            end
        end
    end
    state.trainingKind=nil
    closePractice(state)
    if not bridge then state.unknownPauses, state.quietMs, state.lostWithoutAction = nil, nil, nil end
    return false
end

-- Stock owns the Java handle. Never interrupt an unrelated native action,
-- start a successor over a draining head or replace the player's queue tick.
-- If our *own stopped* handle alone refuses to drain, disarm this session
-- once; ActionYield still preserves waiting foreign work until stock drains.
local function nativeDrainStuck(player, state, queue, now)
    local head = queue[1]
    if not head or head.autoMindfulOwner ~= state or not head.autoMindfulNativeStoppedAt then return false end
    local hold = ISTimedActionQueue.getTimedActionQueue(player).autoMindfulHandoff
    if not hold or hold.inStop or hold.head ~= head then return false end
    local native = player:getCharacterActions()
    if native:size() ~= 1 or not head.action or not native:contains(head.action) or now < head.autoMindfulNativeStoppedAt then
        head.autoMindfulNativeStoppedAt = now
        return false
    end
    return now - head.autoMindfulNativeStoppedAt >= unconfirmedSettleTimeout
end

-- A long seated action can hide a recovered survivor behind the queue.
-- Give other schedulers one idle window per observed recovery, not one
-- per retry. This is not a completed practice or a workout-specific hook.
function Controller.offerRecoveryHandoff(player,state,head,now)
    local recovery = EnduranceGoal.read(player)
    if recovery and recovery <= 0.75 then state.recoveryHandoffArmed = true end
    if not state.recoveryHandoffArmed or not recovery or recovery < 0.95
            or now-state.actionStarted < minRecoveryPracticeMs
            or not state.pending or not head or head.autoMindfulOwner~=state or not isPractice(head,"meditation")
            or not head:isStarted() or head.autoMindfulStopped then return end
    state.recoveryHandoffArmed=nil
    -- Keep the actual started opportunity until someone claims this opening.
    -- If nobody does, retry the leg normally; an idle window is not a turn.
    state.cooperativePending={opportunity=state.practiceWork}
    closePractice(state)
    state.careHandoff=true
    clearOwned(player,state)
    setPhase(state,"between","Endurance recovered. Leaving a short opening for other actions.")
end

-- Count the work opportunity from the first observable empty queue,
-- after Java has drained. Do not claim it for collecting or posture.
function Controller.waitCooperativeWindow(player,state,now)
    local pending=state.cooperativePending
    if not pending then return false end
    if criticalNeed(player,"water") or criticalNeed(player,"food") or sleepAdmitted(sleepReadiness(player,state)) then
        state.cooperativePending=nil
        return false
    end
    if not pending.started or now<pending.started then pending.started=now end
    if now-pending.started<ActionYield.cooperativeWindowMs then
        setPhase(state,"between",(state.recovery or state.backgroundPractice) and "Leaving a short opening for other actions."
            or "Endurance recovered. Leaving a short opening for other actions.")
        return true
    end
    state.cooperativePending=nil
    return false
end

-- A configured minimum can extend an active care practice only while its
-- original need is still actionable. A badge is neither a need nor relief.
function Controller.tierCareNeed(course,readings)
    local need=course.need=="mindfulness" and course.target or course.need
    if need=="boredom" or need=="stiffness" or need=="stress" or need=="withdrawal" or need=="panic" or need=="unhappiness" then
        local value=need=="withdrawal" and readings.withdrawal or need=="stiffness" and readings.stiffness or readings[need:upper()]
        return PracticeCare.needsRelief(need,course.kind,course.rank,value,course.earlierRecovery,course.tierSleepBlocked)
            and (need~="unhappiness" or PracticeCare.unhappinessContext(readings.BOREDOM,readings.PAIN))
    end
    if course.kind=="yoga" and need=="pain" then
        return not readings.painReliefActive and (readings.PAIN or 0)>=(course.rank>=3 and 15 or 25)
    end
    if need=="pain" then return not readings.painReliefActive and (readings.PAIN or 0)>=10 and readings.PAIN<20 end
    if need=="hunger" then return PracticeCare.hungry(readings.HUNGER,readings.hungerLevel) end
    if need=="health" then
        return PracticeCare.healingEnabled(readings.healFactor) and readings.healthSafe and (readings.HUNGER or 1)<0.15
            and (readings.PAIN or 100)<=5 and (readings.PANIC or 100)<5
    end
    return false
end

function Controller.updateStrictRecoveryPractice(player,state,course,head,now,priority)
    local goal=course.strictTier
    local reading=goal.current
    local pause=state.contextVisible or state.inspectingUI or (getGameSpeed and getGameSpeed()==0)
    local matching=head and head.autoMindfulOwner==state and isPractice(head,goal.kind)
        and not head.autoMindfulFinished and not head.autoMindfulStopped
    if not priority and not goal.result and not pause and matching then
        if goal.head~=head then goal.head,goal.sampleAt,goal.launchAt,goal.launchMs=head,nil,nil,nil end
        local native=player:getCharacterActions()
        if head:isStarted() and head.action and native:size()==1 and native:contains(head.action) then
            goal.launchAt=nil
            if reading and reading>goal.best then goal.best,goal.workMs,goal.sampleAt=reading,0,nil end
            if budget(goal,now,"sampleAt","workMs")>=tierWorkMs then
                Controller.endRecoveryTier(state,goal,now,"failed","Lifestyle did not make Recovery tier progress during eight minutes of practice.")
            end
        elseif budget(goal,now,"launchAt","launchMs")>=30000 then
            Controller.endRecoveryTier(state,goal,now,"failed","Lifestyle did not start the queued Recovery tier practice.")
        end
    end
    if not priority and not goal.result then return end
    if pause and not priority then return end
    goal.head,goal.sampleAt,goal.launchAt=nil,nil,nil
    if course.target=="hunger" and (priority or goal.result~="met") then state.hungerAid=nil end
    if goal.result=="met" and not priority and matching and head:isStarted() and course.need=="mindfulness" then
        local readings=practiceReadings(player,nil,true)
        if PracticeCare.acquired(course,readings) then Controller.armMindfulnessWatch(player,state,now,course,readings,true) end
    end
    state.practiceCare=nil
    state.practiceCareNext=now+120000
    breakForCare(player,state,priority and (state.recoveryTier and "Prioritizing care. The Recovery tier will resume when safe."
        or "Prioritizing a more urgent need.") or goal.result=="met" and "Recovery tier reached. Leaving room for other actions."
        or "Ending the Recovery tier practice and checking other needs.")
    state.cooperativePending={}
end

function Controller.updateCarePractice(player,state,head,now,urgent,bedtime)
    local course=state.practiceCare
    if course.hungerPrerequisite then
        -- Starvation is why this bounded Yoga was admitted. It must not
        -- interrupt itself; newly usable food, water or hard danger still win.
        local water=criticalNeed(player,"water")
            or (Needs.due(player,"water") and comfortSupplyAvailable(player,state,"water",true,true))
        local food=Needs.due(player,"food") and comfortSupplyAvailable(player,state,"food",true,true)
        local priority=water or food or (not urgent and sleepAdmitted(bedtime)) or Needs.lowHealth(player)
        local unblocked=meditationGate(player).ready
        if priority or unblocked or not Tiers.wellnessEnabled() or not Controller.mindfulnessEnabled()
                or (Options.practiceCare and not Options.practiceCare()) or now-course.startedAt>=course.maxMs then
            state.practiceCare=nil
            breakForCare(player,state,priority and "Prioritizing a more urgent need."
                or unblocked and "Lifestyle now allows Meditation. Checking hunger again."
                or "Ending the bounded Yoga attempt to unblock Meditation.")
        end
        return
    end
    if course.strictTier then
        -- A committed tier stays behind real care, not speculative loot.
        local priority=urgent or sleepAdmitted(bedtime) or (course.target~="hunger" and Controller.firstHungerCourse(player,state))
            or (Needs.due(player,"food") and comfortSupplyAvailable(player,state,"food",true))
            or (Needs.due(player,"water") and comfortSupplyAvailable(player,state,"water",true))
            or (not state.contextVisible and (painAvailable(player,state,now) or lifestyleReady(player,state,now)
                or (stat(player,"BOREDOM")>=20 and not player:tooDarkToRead()
                    and Supplies.choose(player,"literature",state.collectNearby or Options.searchNearby(),state.rejected))))
        Controller.updateStrictRecoveryPractice(player,state,course,head,now,priority)
        return
    end
    local minimum=course.tierMinimum
    local configured=minimum and Options.minimumTier and Options.minimumTier("recovery",course.kind)
    local target=minimum and Tiers.clamp(course.kind,configured,course.rank)
    local current=target and target>0 and Tiers.current(player,course.kind)
    local minimumActive=current~=nil and current~=false
    local hungerCare=course.target=="hunger"
    local ordinaryCare=state.recovery or minimumActive or hungerCare or bedtime~=nil
    local priority=(urgent and (not hungerCare or criticalNeed(player,"water") and (not state.noEmergencyDrink
            or comfortSupplyAvailable(player,state,"water",true)))) and "critical-food-or-water"
        or (not urgent and sleepAdmitted(bedtime)) and "sleep"
        or (not hungerCare and Controller.firstHungerCourse(player,state)) and "hunger-care"
        or (Needs.due(player,"food",ordinaryCare and Consumables.careThreshold or 0.60) and comfortSupplyAvailable(player,state,"food",hungerCare)) and "food"
        or (Needs.due(player,"water",ordinaryCare and Consumables.careThreshold or 0.50) and comfortSupplyAvailable(player,state,"water",hungerCare)) and "water"
        or (ordinaryCare and not urgent and not state.contextVisible and (painAvailable(player,state,now) and "painkillers-available"
            or (stat(player,"BOREDOM")>=20 and comfortSupplyAvailable(player,state,"literature",hungerCare,state.recovery)) and "boredom-reading"))
    local relief, drawback, acquired, readings, waitingForTier, careResolved
    if course.kind=="meditation" and head.autoMindfulOwner==state and isPractice(head,course.kind)
            and head:isStarted() and not head.autoMindfulStopped then
        readings=practiceReadings(player,nil,true)
        if minimumActive then
            careResolved=not Controller.tierCareNeed(course,readings)
            waitingForTier=not careResolved and current<math.min(minimum.target,target)
        end
        if course.need=="mindfulness" then
            acquired=PracticeCare.acquired(course,readings)
            drawback=not Controller.mindfulnessEnabled() or (hungerCare and (not PracticeCare.hungry(readings.HUNGER,readings.hungerLevel)
                    or not PracticeCare.hungerUnlocked(levels(player))
                    or (readings.BOREDOM or 0)>(course.before.BOREDOM or 0)+20 and not meditationGate(player).ready)
                or not hungerCare and (readings.BOREDOM or 0)>20)
                or (readings.PAIN or 0)>(course.before.PAIN or 0)+10
                or (course.target=="health" and (not PracticeCare.healingEnabled(readings.healFactor)
                    or not readings.healthSafe or readings.HEALTH<course.before.HEALTH-(course.lowHealthHeal and 0.01 or 2)))
                or (course.target=="panic" and readings.PANIC and readings.PANIC<5)
                or (course.target=="pain" and readings.painReliefActive)
        else
            relief=PracticeCare.improved(course,readings)
            drawback=(readings.BOREDOM or 0)>10 or (readings.PAIN or 0)>=10
                or (course.need=="unhappiness" and not PracticeCare.unhappinessContext(readings.BOREDOM,readings.PAIN))
        end
        if state.recovery and course.need~="mindfulness" and not (priority or relief or drawback or waitingForTier) then
            Controller.offerRecoveryHandoff(player,state,head,now)
            if not state.pending then
                state.practiceCare=nil
                state.practiceCareNext=now+120000
                return
            end
        end
    end
    if not Tiers.wellnessEnabled() or priority or drawback or careResolved or (relief or acquired) and not waitingForTier
            or now-course.startedAt>=(waitingForTier and course.tierMaxMs or course.maxMs)
            or (Options.practiceCare and not Options.practiceCare()) then
        state.practiceCare=nil
        state.practiceCareNext=now+120000
        if hungerCare and priority then state.hungerAid=nil end -- a meal, drink or player need interrupted; no failure
        if waitingForTier and not priority and not drawback then
            state.practiceCareNotice="The selected tier was not confirmed before the care practice ended."
            state.practiceCareNoticeUntil=now+5000
        end
        if acquired and not priority and not drawback then
            Controller.armMindfulnessWatch(player,state,now,course,readings,true)
        elseif relief and not priority and not waitingForTier then
            state.practiceCareNotice="The game showed relief after the care practice."
            state.practiceCareNoticeUntil=now+5000
        end
        breakForCare(player,state,priority and "Prioritizing a more urgent need."
            or acquired and not drawback and "Mindfulness is active. Checking for the matching effect with the queue free."
            or relief and (state.recovery and "The care practice helped; monitoring other needs." or "Stress eased; returning to training.")
            or (state.recovery and "Ending the optional care break and checking needs again."
                or "Ending the optional care break and rechecking training and supplies."),
            priority or (drawback and "practice-drawback") or (careResolved and "need-resolved")
                or (acquired and "moodle-acquired") or (relief and "relief-observed") or "practice-window-ended")
        if state.recovery or state.backgroundPractice then state.cooperativePending={} end
    end
end

-- A wall timestamp cannot tell a paused game from a failed operation. Count
-- only neighboring observations of the same native head. A new batch step,
-- meaningful walking displacement, or forward job progress resets its stall.
function Controller.stallTime(player,state,operation,head,now,walking)
    local w=operation.stallWatch
    if not w or w.head~=head then
        w={head=head,ms=0}
        operation.stallWatch=w
    end
    local native=player:getCharacterActions()
    if not head or head.autoMindfulOwner~=state or head.autoMindfulStopped or head.autoMindfulFinished
            or not state.pending or ISTimedActionQueue.getTimedActionQueue(player).current~=head
            or not head.action or native:size()~=1 or not native:contains(head.action) or not head:isStarted()
            or state.contextVisible or state.inspectingUI or state.aimStarted
            or (getGameSpeed and getGameSpeed()==0) then
        w.at=nil
        return 0
    end
    local changed=false
    if walking and routeAction(head) then
        local x,y=player:getX(),player:getY()
        if not w.x or (x-w.x)^2+(y-w.y)^2>=0.01 then w.x,w.y,changed=x,y,true end
    elseif head.action.getJobDelta then
        local delta=head.action:getJobDelta()
        if type(delta)=="number" and delta>=0 and delta<=1 and (not w.delta or delta>w.delta+0.00001) then
            w.delta,changed=delta,true
        end
    end
    if changed then w.ms=0
    elseif w.at and now>=w.at and now-w.at<=2000 then w.ms=w.ms+now-w.at end
    w.at=now
    return w.ms
end

function Controller.update(player)
    local state = states[player]
    if not state or not player:isLocalPlayer() then return end
    ActionYield.finishHandoff(player)
    if not state.active and #state.loans == 0 and not state.releasePending and not state.maskRestore then return end
    local now = getTimestampMs()
    local queue = queueFor(player)
    Controller.observeMaskRestore(player,state,queue)
    sampleInspection(player, state, queue, now)
    if state.active and state.recovery then
        if Controller.recoveryYields(player,state,queue) then return end
    else
        local danger = unsafeReason(player, state)
        if danger then
            if state.active then Controller.stop(player, danger)
            elseif state.pending or state.releasePending then clearOwned(player, state) end
            return
        end
    end
    if Controller.lowHealthTransition(player,state) then return end
    local outbound=state.active and state.excursion
    if outbound and outbound.stage=="outbound" and not Options.searchNearby() then
        -- Retain only the way home. Release the exact owned batch, never the
        -- player's queue. The normal idle/drain gates decide when a return is safe.
        outbound.stage="resume-home"
        clearOwned(player,state)
        return
    end
    if state.active and nativeDrainStuck(player, state, queue, now) then
        if state.recovery then
            Controller.pauseRecovery(player,state,"Recovery is waiting for its canceled action to settle.","settling-action")
        else
            Controller.stop(player, "Training stopped because its canceled action did not settle. No other action was interrupted.")
        end
        return
    end
    if state.active and checkHomeRecovery(player, state, queue, now) then return end
    if state.active and not state.endurance then
        -- A possibly analgesic foreign pill invalidates attribution before sampling effects.
        PainCare.observeForeign(player, state, queue, now)
        PainCare.observe(player, state, now)
    end
    local drain=state.restroomDrain
    if drain then
        local native=player:getCharacterActions()
        if state.pending==drain.batch and not queue[1] and not state.contextVisible and not state.inspectingUI
                and not state.aimStarted and not state.walkTakenOver and not player:pressedMovement(false)
                and now>=drain.at and now-drain.at<750 and ((native:size()==1 and native:contains(drain.handle))
                    or (native:isEmpty() and ActionYield.nativeBusy(player))) then
            return -- a trailing handle/animation flag, never a different action
        end
        state.restroomDrain=nil
    end
    local occupied = ActionYield.occupied(player, queue, state) or state.inspectingUI
    local lost = observeTrainingBatch(player, state, queue, now)
    if state.stalledSkill then
        Controller.stop(player,stalledMessage(state.stalledSkill))
        return
    end
    if lost and not state.endurance and atSkillGoal(player, state) then
        -- XP may arrive before the missing action's receipt. Settle loans and
        -- complete normally; there is no fourth loss or restart after the goal.
        state.pending, state.trainingKind, lost = nil, nil, false
        closePractice(state)
    end
    local moving = state.active and (player:pressedMovement(false) or state.walkTakenOver)
    state.walkTakenOver=nil
    if state.active then
        Controller.observeRecoveryTier(player,state,queue,now,
            occupied or moving or player:isAsleep() or state.contextVisible or state.aimStarted or (getGameSpeed and getGameSpeed()==0))
    end
    local busy = occupied or lost or moving
    local careHandoff = state.active and state.careHandoff
    local careUIWait = careHandoff and (state.contextVisible and careMenuWait or state.inspectingUI and careWindowWait)
    -- Real actions and recognized game/UI states have no time limit. The
    -- animation flag can outlive either a lost action or our own care break.
    -- A bare flag with no Lua/Java or other evidence cannot arm us forever.
    local unconfirmed = occupied and state.active and (lost or state.lostWithoutAction or careHandoff)
        and not queue[1] and player:getCharacterActions():isEmpty() and not ISTimedActionQueue.isPlayerDoingAction(player)
        and not state.inspectingUI and not state.contextVisible and not player:isAsleep() and not moving and not state.aimStarted
    if unconfirmed then
        if not state.unconfirmedSince or now < state.unconfirmedSince then state.unconfirmedSince = now end
        if now - state.unconfirmedSince >= unconfirmedSettleTimeout then
            Controller.stop(player, careHandoff
                and "Care could not start: the game still reported activity without a current action. Start again when ready."
                or "Training stopped; the game reported activity without a current action. Start again when ready.")
            return
        end
    else
        state.unconfirmedSince = nil
    end
    if (occupied and not unconfirmed) or state.contextVisible or moving then
        -- A genuine takeover is not an unexplained loss, but also isn't a
        -- successful training action. Keep any pre-existing retry budget.
        state.lostWithoutAction = nil
    elseif lost and not state.yielding then
        state.lostWithoutAction = true
        state.unknownPauses = 1 + (state.unknownPauses or 0)
        if state.unknownPauses >= 4 then
            Controller.stop(player, "Training was interrupted repeatedly without another action. Start again when ready.")
            return
        end
        state.quietMs = 750 * 2 ^ (state.unknownPauses - 1)
    end
    local quietMs = state.recovery and ActionYield.cooperativeWindowMs or state.quietMs or 750
    if state.active then
        local ready, reason = available(player, state.mode)
        if not ready then Controller.stop(player, reason); return end
        if state.endurance then
            local quiet = not busy and not state.releasePending and not player:isAsleep() and not state.aimStarted
                and not state.contextVisible and (not state.yielding or (state.idleSince and now - state.idleSince >= quietMs))
            if updateEndurance(player, state, now, quiet) then return end
        end
    end
    if state.releasePending then
        if clearOwned(player, state) then
            state.careReleaseSince = nil
        elseif careHandoff then
            noteCareWait(state, careUIWait or "Waiting for the previous action to settle before care.")
            -- A real Java/foreign action owns its time. Only disarm the mod
            -- when the release is stuck with no evidence of actual player work.
            local orphaned = not careUIWait and not moving and not state.aimStarted and not player:isAsleep()
                and player:getCharacterActions():isEmpty() and not ISTimedActionQueue.isPlayerDoingAction(player)
                and not ActionYield.hasForeign(queueFor(player), state)
            if orphaned then
                if not state.careReleaseSince or now < state.careReleaseSince then state.careReleaseSince = now end
                if now - state.careReleaseSince >= unconfirmedSettleTimeout then
                    Controller.stop(player, "Care stopped: AutoMindful could not release its previous action. Start again when ready.")
                end
            else
                state.careReleaseSince = nil
            end
        end
        return
    end
    if not state.active and #state.loans == 0 and not state.maskRestore then return end
    if state.aimStarted then state.idleSince = nil; return end
    if busy then
        state.mindfulnessWatch=nil
        yieldToPlayer(player, state, lost and not occupied and not state.contextVisible and not moving, moving, unconfirmed)
        if careHandoff then
            noteCareWait(state, careUIWait or (unconfirmed and "Waiting for the game's animation flag to settle before care.")
                or "Waiting for your current action before care.")
        end
        return
    end
    if player:isAsleep() then
        state.idleSince,state.sleepDeclined=nil,nil
        if state.active then setPhase(state, "sleeping", "Sleeping. Training resumes after waking.") end
        return
    end
    if state.yielding then
        if state.contextVisible then
            if careHandoff then noteCareWait(state, careMenuWait) end
            state.idleSince = nil
            return
        end
        if not state.idleSince or now < state.idleSince then state.idleSince = now end
        if now - state.idleSince < quietMs then return end
        state.yielding, state.idleSince, state.lostWithoutAction, state.pauseNotice = nil, nil, nil, nil
        if state.active then setPhase(state, "resuming", state.recovery and "Checking recovery needs now that the queue is free."
            or "Checking your current needs and training spot.") end
    end
    if state.lastUpdate and now >= state.lastUpdate and now - state.lastUpdate < 250 then return end
    state.lastUpdate = now
    Controller.observeMindfulness(player,state,queue[1],now)
    local trip = state.excursion
    if trip and trip.indirect and (trip.stage=="outbound" or trip.stage=="inspect") then
        local urgent=Needs.critical(player,"water") and "water" or Needs.critical(player,"food") and "food"
        if urgent and trip.kind~=urgent then
            -- Don't spend the return walk thirsty if a ready drink is in hand.
            -- Only disarm this optional leg; ordinary native drain/yield gates
            -- run before re-admitting an urgent action on the next idle tick.
            trip.stage="urgent"
            clearOwned(player,state)
            return
        end
    end
    if trip and trip.stage == "outbound" and trip.careTarget
            and (not Options.searchNearby() or Needs.critical(player,"water") or Needs.critical(player,"food")
                or not LifestyleCare.need(player,trip.kind)) then
        trip.stage="resume-home"
        clearOwned(player,state)
        if not state.releasePending then returnToOrigin(player,state,now) end
        return
    end
    if trip and trip.kind == "pain" and (trip.stage == "outbound" or trip.stage == "inspect")
            and (not Options.searchNearby() or Needs.critical(player, "water") or Needs.critical(player, "food")
                or not wantsPainCare(player, state, now)) then
        -- The need, treatment or permission can change while walking. Never
        -- borrow or dose just because a previously valid trip reached its target.
        trip.stage = "resume-home"
        clearOwned(player, state)
        if not state.releasePending then returnToOrigin(player, state, now) end
        return
    end
    if trip and trip.egressPlan and not Options.searchNearby() then
        state.excursion=nil
        clearOwned(player,state)
        return
    end
    if state.excursion and state.excursion.stage == "outbound" and not state.excursion.egressPlan and state.excursion.target.part
            and not vehicleTargetAvailable(player, state.excursion.target) then
        Controller.stop(player, "The vehicle supply source moved or became inaccessible. Stopped without forcing movement.")
        return
    end
    if state.active and state.cycle and not state.contextVisible then
        local stalled=observePractice(player,state,queue,now,false)
        if stalled then
            Controller.stop(player,stalledMessage(stalled))
            return
        end
    end
    if #queue > 0 then
        if state.lifestyleCourse then
            local course=state.lifestyleCourse
            if not course.received and LifestyleCare.receipt(player,course) then
                course.received,course.stallWatch=true,nil
            end
            if Controller.stallTime(player,state,course,queue[1],now,false)>=60000 then
                Controller.stop(player,"The care action stopped making progress. Stopped without forcing it to finish."); return
            end
        end
        if state.excursion and state.phase=="travelling"
                and Controller.stallTime(player,state,state.excursion,queue[1],now,true)>=30000 then
            if state.excursion.egressPlan then
                state.excursion=nil
                clearOwned(player,state)
                state.careNotice="The path off the blocked tile did not finish. Checking other care options."
            elseif not Controller.abandonStalledSupply(player,state,now) then
                Controller.stop(player, "The supply route was blocked or took too long. Stopped without forcing movement.")
            end
            return
        end
        local urgent = Needs.critical(player, "water") or Needs.critical(player, "food")
        local bedtime=not state.endurance and sleepReadiness(player,state) or nil
        if state.practiceCare then
            Controller.updateCarePractice(player,state,queue[1],now,urgent,bedtime)
        elseif state.phase == "meditation" and not state.endurance then
            local meditation, yoga = levels(player)
            local work,cycle=state.practiceWork,state.cycle
            local enduranceOnly=work and work.bridge==yogaEnduranceBridge
            local boredom = stat(player, "BOREDOM")
            local reading = boredom >= 20 and comfortSupplyAvailable(player, state, "literature")
            local hungerCare=(state.noConfirmedFood and Controller.hungerOpportunity(player,state)) or (state.hungerAid and not state.hungerAid.failed)
            local eating=Needs.due(player,"food",hungerCare and Consumables.careThreshold or 0.2)
                and comfortSupplyAvailable(player,state,"food",hungerCare)
            local drinking = Needs.due(player,"water",0.2) and comfortSupplyAvailable(player, state, "water")
            local pain = not state.contextVisible and painAvailable(player, state, now)
            local lifestyle = not state.contextVisible and lifestyleReady(player,state,now)
            local reason=urgent and "critical-food-or-water" or drinking and "water" or eating and "food"
                or Controller.firstHungerCourse(player,state) and "hunger-care"
                or pain and "painkillers-available" or reading and "boredom-reading" or lifestyle and "lifestyle-care"
                or sleepAdmitted(bedtime) and "sleep" or (meditation >= 10 and not state.backgroundPractice
                    and not state.tierGoal and not enduranceOnly) and "meditation-rank-cap"
            if reason then
                breakForCare(player, state, "Taking a care break before resuming training.", reason)
            elseif not state.contextVisible or enduranceOnly then
                local head=queue[1]
                if Controller.observeTierHead(player,state,head,now) then return end
                if cycle and work and work.bridge and head.autoMindfulOwner==state and isPractice(head,"meditation")
                        and not head.autoMindfulStopped and (enduranceOnly or work.bridgeStartedAt and head:isStarted()) then
                    local gate=yogaAdmission(player)
                    cycle.gates.yoga=gate
                    local done=enduranceOnly and (gate.kind~="endurance" or (yoga>=10 and not state.backgroundPractice))
                        or not enduranceOnly and (gate.ready or now-work.bridgeStartedAt>=yogaBridgeMs)
                    if done then
                        state.trainingKind=nil
                        closePractice(state)
                        -- Intentional switch or recovery bound, never an
                        -- unexplained loss and never a completed Meditation.
                        -- Keep the same native idle/release guards as a care break.
                        state.careHandoff=true
                        clearOwned(player,state)
                        noteCycle(state,gate.ready and "handoff" or "recovery","yoga",nil)
                        setPhase(state,"cycling",enduranceOnly and yoga>=10 and not state.backgroundPractice and "Yoga has reached its training goal."
                            or gate.ready and "Yoga is now available. Finishing the current training handoff."
                            or enduranceOnly and "Endurance no longer blocks Yoga. Checking its other requirements."
                            or "Meditation recovery interval ended. Waiting for Yoga's native requirement.")
                    end
                end
                if not enduranceOnly then Controller.offerRecoveryHandoff(player,state,head,now) end
            end
        elseif state.phase == "yoga" then
            local hungerCare=(state.noConfirmedFood and Controller.hungerOpportunity(player,state)) or (state.hungerAid and not state.hungerAid.failed)
            if urgent or sleepAdmitted(bedtime) or Controller.firstHungerCourse(player,state)
                    or (bedtime=="pain" and not state.contextVisible and painAvailable(player,state,now))
                    or (Needs.due(player,"food",hungerCare and Consumables.careThreshold or 0.6)
                    and comfortSupplyAvailable(player,state,"food",hungerCare))
                    or (Needs.due(player,"water",0.5) and comfortSupplyAvailable(player, state, "water")) then
                breakForCare(player, state, "Taking an urgent care break. Lifestyle may apply its normal early-stop yoga penalty.")
            elseif not state.contextVisible then Controller.observeTierHead(player,state,queue[1],now) end
        elseif state.phase == "standing" and now - state.actionStarted > 15000 then
            Controller.stop(player, "Could not stand up here. Move to clear ground and start again.")
        end
        return
    end
    if state.contextVisible then
        if careHandoff then noteCareWait(state, careMenuWait) end
        if state.pending then
            for _, action in ipairs(state.pending) do
                if not action.autoMindfulFinished then state.contextInterrupted = true end
            end
        end
        return
    end
    if state.active and Controller.waitCooperativeWindow(player,state,now) then return end
    if careHandoff then state.careHandoff, state.careWait, state.careReleaseSince = nil, nil, nil end
    if state.contextInterrupted then
        state.contextInterrupted = nil
        local interrupted = false
        for _, action in ipairs(state.pending or {}) do if not action.autoMindfulFinished then interrupted = true end end
        if interrupted then
            Supplies.finishLoan(player, state.supplyLoan)
            for _, loan in ipairs(state.loans) do loan.defer = nil end
            PainCare.detach(player, state, now)
            state.pending = nil
            closePractice(state)
            state.lifestyleCourse, state.lifestylePickup, state.lifestyleScan, state.practiceCare, state.mindfulnessWatch = nil, nil, nil, nil, nil
            resetSupply(state)
        end
    end
    if state.excursion and state.pending and state.phase == "travelling" then
        local trip = state.excursion
        local failedPath = false
        for _, action in ipairs(state.pending) do
            if action.autoMindfulStopped then
                local nativeFailure = routeAction(action) and RouteOutcome.failed(action)
                if trip.homeFailedWalk ~= action then
                    print("[AutoMindful] " .. trip.stage .. " walk stopped: action=" .. tostring(action.Type)
                        .. " path=" .. (nativeFailure and "Failed" or tostring(action.result))
                        .. " speed=" .. tostring(getGameSpeed())
                        .. " need=" .. tostring(trip.kind) .. " from=" .. trip.origin.x .. ":" .. trip.origin.y .. ":" .. trip.origin.z
                        .. " to=" .. tostring(trip.target and trip.target.square and trip.target.square:getX()) .. ":"
                        .. tostring(trip.target and trip.target.square and trip.target.square:getY())
                        .. " approaches=" .. tostring(action.autoMindfulApproaches or "stock"))
                end
                if (trip.stage == "homebound" and trip.homeFailedWalk == action)
                        or (trip.stage ~= "homebound" and nativeFailure and not player:pressedMovement(false)
                            and not player:pressedCancelAction()) then
                    failedPath = true
                else
                    Controller.stop(player, trip.stage == "homebound" and homeCancel
                        or "The supply walk was cancelled. Stopped without forcing a return.")
                    return
                end
            end
        end
        state.pending = nil
        if trip.egressPlan then
            Controller.settleScoutEgress(player,state,trip,failedPath)
        elseif trip.stage == "homebound" then
            if atOrigin(player:getSquare(), trip.origin) then
                arrivedHome(state,trip,now)
            elseif failedPath and trip.homeRetrySince then
                trip.stage = "resume-home"
                -- Wait below after loan settlement, even if stock has already
                -- drained the failed walk from both queues in the same frame.
            else
                Controller.stop(player, "Could not return to the original training spot. Clear the route and start again.")
                return
            end
        else
            local here, target = player:getSquare(), trip.target.square
            local arrived = here and here:getZ() == target:getZ()
                and math.abs(here:getX()-target:getX()) <= 1 and math.abs(here:getY()-target:getY()) <= 1
                and (sameSquare(here, target) or here:canReachTo(target))
            if trip.careTarget then
                arrived = LifestyleCare.accessible(player,trip.careTarget)
            elseif trip.waterObject then
                -- Object paths may arrive at another part of a multi-tile fixture.
                -- The inspection below still requires this exact adjacent, usable source.
                arrived = not failedPath or WaterSources.choose(player, state.rejected, trip.waterObject) ~= nil
            elseif trip.target.part then
                arrived = vehicleTargetAvailable(player, trip.target) and Storage.vehicleAccessible(player, trip.target.part)
            end
            if arrived and Options.searchNearby() then
                trip.stage, trip.inspectUntil = "inspect", now + 3000
            else
                trip.stage = "care"
                Controller.forgetScoutStop(state,trip.target)
                if failedPath then Controller.rejectScoutPath(state,trip,now)
                else state.travelRejected[trip.target.key] = now+15000 end
                if trip.careTarget then LifestyleCare.reject(state,trip.careTarget,now) end
                state.travelScan = nil
                if failedPath then state.careNotice = "No route to this supply. Skipping it and returning to the training spot." end
            end
        end
    end
    trip = state.excursion
    if trip and trip.stage == "inspect" and trip.careTarget then
        local target=trip.careTarget
        if Options.searchNearby() and LifestyleCare.accessible(player,target) then
            if not stand(player,state,"Standing up for a care break.") then return end
            if queueLifestyle(player,state,target,now) then trip.stage="care"; return end
        end
        LifestyleCare.reject(state,target,now)
        Controller.forgetScoutStop(state,target)
        trip.stage="care"
    elseif trip and trip.stage == "inspect" then
        local exact=trip.exactStorage
        if Options.searchNearby() and (not exact or Controller.scoutedStorageAllowed(player,exact))
                and (not trip.target.part or (vehicleTargetAvailable(player, trip.target) and Storage.vehicleAccessible(player, trip.target.part))) then
            Supplies.refreshNearby(player)
            if supply(player, state, trip.kind, trip.onlyWorldWater, trip.waterObject, exact and exact.container) then
                trip.stage = "care"
                Nearby.invalidate(player)
                return
            end
            if not (exact and trip.target.remembered) and now < trip.inspectUntil then
                setPhase(state, "scouting", trip.waterObject and "Checking the selected water source is still usable."
                    or "Waiting for this container's contents; unknown is not empty.")
                return
            end
        end
        Controller.forgetScoutStop(state,trip.target)
        if not exact or not trip.target.remembered or trip.target.storageScoped then state.travelRejected[trip.target.key] = now+(trip.target.unknown and 60000 or 15000) end
        state.travelScan = nil
        state.careNotice = trip.waterObject and "The selected water source was not usable. Returning before trying another source."
            or "This container did not confirm a usable supply. Returning before trying another source."
        trip.stage = "care"
        Nearby.invalidate(player)
    end
    local endedTraining = state.pending and (state.phase == "meditation" or state.phase == "yoga")
    -- Standing is preparation, not a completed practice or care turn.
    -- At this point the normal foreign-action and native drain checks have
    -- passed; advance can recheck care and Lifestyle's gate immediately.
    local endedRecovery = (state.recovery or state.backgroundPractice) and state.pending and state.phase ~= "standing"
        and not state.excursion and not state.collectingItem and not state.preparation
    if state.pending and finishPending(player, state, now) then return end
    if Controller.restoreMask(player,state,now) then return end
    if state.active and endedRecovery and not state.pending then
        state.cooperativePending={}
        if Controller.waitCooperativeWindow(player,state,now) then return end
    end
    if endedTraining and state.active and not state.backgroundPractice and (state.endurance or not atSkillGoal(player, state)) then
        state.cycleUntil = now + ActionYield.cooperativeWindowMs
    end
    if not (state.active and state.endurance) and returnBorrowed(player, state) then return end
    if state.active and Controller.continueErrands(player,state,now) then return end
    if state.active and returnToOrigin(player, state, now) then return end
    if not state.active then
        if state.endPhase then setPhase(state, state.endPhase, state.endMessage, state.endCause, state.endNativeReason) end
        return
    end
    advance(player, state)
end

function Controller.start(player, mode, collectNearby, tier)
    if not player or not player:isLocalPlayer() then return false, "Choose a local survivor." end
    if not modeTitles[mode] then return false, "Unknown training mode." end
    local old = stateFor(player)
    if old.active and old.trainingStopReason then Controller.stop(player, old.trainingStopReason) end
    if old.active then return false, "Training is already active. Stop before changing the mode." end
    if old.releasePending and not clearOwned(player, old) then return false, "Waiting for the previous action to settle." end
    local ready, message = available(player, mode)
    if not ready then return false, message end
    local initialEndurance
    if mode == "endurance" or mode == "recoverEndurance" then
        initialEndurance = EnduranceGoal.read(player)
        if initialEndurance == nil then return false, "Could not read the survivor's endurance." end
        if EnduranceGoal.full(initialEndurance) then return false, "Endurance is already full." end
    end
    local tierKind=tierModes[mode]
    if tierKind then
        if not Tiers.providerCompatible() then return false,"Numeric tier goals are not verified for this Lifestyle version." end
        local med,yoga=levels(player)
        local rank=tierKind=="meditation" and med or yoga
        if type(tier)~="number" or tier<1 or Tiers.clamp(tierKind,tier,rank)~=tier then
            return false, "That tier is not unlocked for this survivor."
        end
        local current=Tiers.current(player,tierKind)
        if current==nil then return false,"The Lifestyle tier is unavailable or could not be read." end
        if current>=tier then return false,(Tiers.label(tierKind,tier) or "That tier").." is already active." end
    end
    local recovery=mode=="recovery" or mode=="recoverEndurance"
    local danger
    if recovery then
        if player:isDead() then danger="Stopped because the survivor died." end
    else danger=unsafeReason(player) end
    if mode=="endurance" and Needs.lowHealth(player) then danger="Health is too low for endurance meditation." end
    if danger then return false, danger end
    if player:isAsleep() then return false, "Wait until the survivor wakes up." end
    local yoga = HiddenSkills.getSkill(player, "Yoga")
    local state = {active = true, mode = mode, collectNearby = mode ~= "endurance" and collectNearby == true, phase = "starting",
        message = "Checking supplies and training requirements.", rejected = {}, careNeeds = {}, failures = 0}
    if player:getSquare() then ActionYield.rememberPosition(state, player) end
    if recovery then
        state.recovery=true
        state.recoveryFull=mode=="recoverEndurance"
        state.cooperativePending={}
        state.message="Watching for recovery needs and leaving room for other actions."
    elseif initialEndurance then state.endurance = {best=initialEndurance}
    elseif tierKind then
        state.tierGoal={kind=tierKind,target=tier}
        state.message="Checking the requirements for "..(Tiers.label(tierKind,tier) or "the selected Lifestyle tier").."."
    else
        state.cycle=newCycle(player)
        if atSkillGoal(player,state) then
            state.backgroundPractice=true
            state.cycle.policy="alternate"
            state.cooperativePending={}
            state.message="Practicing at max rank when idle. Other actions take priority."
        end
    end
    if state.recoveryFull or state.endurance or state.tierGoal or (not state.recovery
            and ((mode ~= "yoga" and player:getPerkLevel(Perks.Meditation) < 10) or (mode ~= "meditation" and yoga[1] < 10))) then
        state.session = {startedAt=getTimestampMs(), progress=Progress.snapshot(player)}
    end
    state.loans, state.returnNotice = old.loans or {}, old.returnNotice
    state.maskRestore, state.maskNotice = old.maskRestore, old.maskNotice
    state.scoutMemory = old.scoutMemory or {}
    state.decisionLog=old.decisionLog
    Decisions.transition(state,"starting")
    states[player] = state
    if #queueFor(player) > 0 or ActionYield.nativeBusy(player) then yieldToPlayer(player, state) end
    return true, state.message
end

function Controller.status(player)
    if not player then return {active = false, phase = "idle", message = "No local survivor.", meditation = 0, yoga = 0} end
    local state = stateFor(player)
    local meditation, yoga = levels(player)
    local cycle=state.cycle
    local cycleStatus=cycle and {policy=cycle.policy,due=cycle.owed,nextKind=cycle.nextKind,reason=cycle.reason,bridge=cycle.bridge,
        preferred=cycle.preferred,lastCompleted=cycle.lastCompleted,gates=cycle.gates,skills=cycle.skills} or nil
    local decisionCode,decisionLabel,decisionDetail=Decisions.current(state)
    local goal=state.active and (state.tierGoal or state.turnTier or state.recoveryTier
        or (state.practiceCare and not state.practiceCare.strictTier and state.practiceCare.tierMinimum))
    local tierGoal=goal and {kind=goal.kind,target=goal.target,current=Tiers.current(player,goal.kind)} or nil
    local tierNotice=state.active and state.tierNoticeUntil and getTimestampMs()<state.tierNoticeUntil and state.tierNotice or nil
    return {active = state.active, phase = state.phase, message = state.careWait or state.message,
        decisionCode=decisionCode, decisionLabel=decisionLabel, decisionDetail=decisionDetail, decisionRevision=Decisions.revision(state),
        careWaiting = state.careWait ~= nil, meditation = meditation, yoga = yoga, cycle=cycleStatus,tierGoal=tierGoal,tierNotice=tierNotice,
        progress = Progress.snapshot(player), mode = state.mode, backgroundPractice=state.backgroundPractice, collectNearby = state.collectNearby,
        endurance = (state.endurance or state.recovery) and EnduranceGoal.read(player) or nil,
        returnNotice = state.maskNotice or state.returnNotice or state.fluidNotice, careNotice = (state.practiceCareNoticeUntil and getTimestampMs()<state.practiceCareNoticeUntil and state.practiceCareNotice) or tierNotice or state.careNotice or state.lifestyleNotice, painNotice = state.painNotice, pendingReturns = #state.loans}
end

function Controller.recentDecisions(player)
    return Decisions.snapshot(states[player])
end

function Controller.prepare(player, collectNearby, showNearby, force)
    if not player then return {message = "No local survivor."} end
    local state = states[player]
    local area
    if showNearby then
        local trip = state and state.excursion
        local origin = trip and resolveOrigin(trip.origin) or player:getSquare()
        Supplies.refreshNearby(player)
        area = Nearby.scan(player, origin, Options.searchRadius(), force)
    end
    local walking = Options.searchNearby()
    local report = Supplies.report(player, showNearby == true or collectNearby == true,
        collectNearby == true or walking, area, walking)
    report.walkingEnabled = walking
    return report
end

local function onPlayerUpdate(player)
    local state = states[player]
    if not state or (not state.active and #state.loans == 0 and not state.releasePending and not state.maskRestore) then return end
    local ok, message = pcall(Controller.update, player)
    if not ok then
        Controller.stop(player, "AutoMindful stopped after an error. See console.txt for details.")
        print("[AutoMindful] ERROR: " .. tostring(message))
    end
end

if Events.OnTickEvenPaused then
    Events.OnTickEvenPaused.Add(function()
        -- A native inspection panel can open and pause single-player before
        -- the next player update. Observe UI only; never queue while paused.
        if getGameSpeed() ~= 0 then return end
        local now=getTimestampMs()
        for player,state in pairs(states) do
            if state.active and player:isLocalPlayer() then
                sampleInspection(player,state,queueFor(player),now)
                if state.excursion and state.excursion.stallWatch then state.excursion.stallWatch.at=nil end
                if state.lifestyleCourse and state.lifestyleCourse.stallWatch then state.lifestyleCourse.stallWatch.at=nil end
                local strict=state.recoveryTier
                if strict then strict.sampleAt,strict.launchAt=nil,nil end
            end
        end
    end)
end
Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnPlayerDeath.Add(function(player)
    if states[player] then
        states[player].scoutMemory=nil
        states[player].maskRestore=nil
        Controller.stop(player, "Stopped because the survivor died.")
    end
end)
Events.OnGameStart.Add(function() states = {} end)

return Controller
