require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISReadABook"
require "TimedActions/ISDrinkFluidAction"
require "TimedActions/ISWaitWhileGettingUp"
require "ISUI/ISWorldObjectContextMenu"
local Supplies = require "AutoMindful/Supplies"
local Consumables = require "AutoMindful/Consumables"
local WaterSources = require "AutoMindful/WaterSources"
local Progress = require "AutoMindful/Progress"
require "AutoMindful/CompletionHUD"
local Fluids = require "AutoMindful/Fluids"
local Nearby = require "AutoMindful/Nearby"
local Storage = require "AutoMindful/Storage"
require "Vehicles/TimedActions/ISPathFindAction"
local Options = require "AutoMindful/Options"
local ActionYield = require "AutoMindful/ActionYield"
local EnduranceGoal = require "AutoMindful/EnduranceGoal"
require "TimedActions/WalkToTimedAction"

AutoMindful = AutoMindful or {}
local Controller = {}
AutoMindful.Controller = Controller
local states = {}
local modeTitles = {both = "Training", meditation = "Meditation", yoga = "Yoga", endurance = "Endurance meditation"}
local yogaRecoveryStart, yogaRecoveryTarget = 0.85, 0.95
local aimStopMessage = "Cancelled because you started aiming."

local function stateFor(player)
    if not states[player] then
        states[player] = {active = false, loans = {}, phase = "idle", message = "Choose a training mode to begin."}
    end
    return states[player]
end

local function queueFor(player)
    return ISTimedActionQueue.getTimedActionQueue(player).queue
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
    local meditation, yoga = levels(player)
    return (state.mode == "yoga" or meditation >= 10) and (state.mode == "meditation" or yoga >= 10)
end

local function setPhase(state, phase, message)
    if state.phase ~= phase or state.message ~= message then
        print("[AutoMindful] " .. phase .. ": " .. message)
    end
    state.phase, state.message = phase, message
end

local function clearOwned(player, state)
    state.pending = nil
    local done = ActionYield.release(player, state)
    state.releasePending = not done or nil
    return done
end

local function showSessionEnd(player, state)
    local session = state.session
    if not session then return end
    state.session = nil
    local hud = PZActionCompletionHUD
    local detail = {hud.duration((getTimestampMs() - session.startedAt) / 1000)}
    if state.endurance and state.endPhase == "complete" then detail[#detail+1] = "100% endurance" end
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

function Controller.stop(player, reason)
    local state = stateFor(player)
    state.active, state.trainingAimStopped = false, nil
    state.excursion = nil
    state.yielding, state.idleSince, state.cycleUntil = nil, nil, nil
    if ActionYield.hasForeign(queueFor(player), state) then
        for _, loan in ipairs(state.loans) do loan.interference = true end
    end
    clearOwned(player, state)
    Supplies.finishLoan(player, state.supplyLoan)
    for _, loan in ipairs(state.loans) do loan.defer = nil end
    state.supplyItem, state.supplyKind, state.supplyLoan, state.supplySource = nil, nil, nil, nil
    state.supplyBaseline, state.preparation, state.collectingItem, state.fluidSupply = nil, nil, nil, nil
    state.endPhase, state.endMessage = "stopped", reason or "Stopped. Start again when you are ready."
    setPhase(state, state.endPhase, state.endMessage)
    showSessionEnd(player, state)
end

function Controller.setCollectNearby(player, enabled)
    stateFor(player).collectNearby = enabled == true
end

local function ownAction(player, state, action)
    if action.autoMindfulOwner == state then return end
    action.autoMindfulOwner = state
    state.pending[#state.pending + 1] = action
    for _, method in ipairs({"start", "perform", "stop"}) do
        local original = action[method]
        if original then
            action[method] = function(self, ...)
                if method == "perform" then self.autoMindfulFinished = true end
                local pending, queue = state.pending, queueFor(player)
                if method == "stop" then
                    self.autoMindfulStopped = true
                    -- Native aim can cancel Lifestyle between two player updates.
                    -- Our own cleanup clears pending before it invokes stop.
                    if pending and state.active and queue[1] == self
                            and (state.phase == "meditation" or state.phase == "yoga") and player:isAiming() then
                        state.trainingAimStopped = true
                        return ActionYield.nativeAimStop(player, state, self, original, ...)
                    end
                end
                -- A foreign successor may begin and append its own children
                -- inside stock perform(). Those children are never ours.
                if not pending or ActionYield.hasForeign(queue, state) then return original(self, ...) end
                local before = {}
                for _, queued in ipairs(queue) do before[queued] = true end
                local result = original(self, ...)
                if state.pending == pending then
                    for _, queued in ipairs(queueFor(player)) do
                        if not before[queued] then ownAction(player, state, queued) end
                    end
                end
                return result
            end
        end
    end
end

local function ownBatch(player, state, phase, message, addActions)
    local before = {}
    for _, action in ipairs(queueFor(player)) do before[action] = true end
    state.pending = {}
    addActions()
    for _, action in ipairs(queueFor(player)) do
        if not before[action] then ownAction(player, state, action) end
    end
    state.actionStarted = getTimestampMs()
    setPhase(state, phase, message)
    return #state.pending > 0
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

local function routeAction(action)
    return action and (action.Type == "ISWalkToTimedAction" or action.Type == "ISPathFindAction")
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

local function unsafeReason(player, state)
    if player:isDead() then return "Stopped because the survivor died." end
    if player:isOnFire() then return "Stopped because the survivor is on fire." end
    if player:getVehicle() then return "Stopped because you entered a vehicle." end
    if not player:getSquare() then return "Stopped because the survivor has no loaded square." end
    if player:isRunning() or player:isSprinting() then return "Cancelled because you started running." end
    if player:pressedCancelAction() and not (state and state.uiCancelHeld) then return "Cancelled by your input." end
    if player:isAttacking() then return "Stopped because you started attacking." end
    if state and state.active then
        if ActionYield.leftArea(state, player, excursionMotion(player, state)) then
            return "Cancelled because you moved away from the activity or changed floor."
        end
    elseif player:isPlayerMoving() and (player:pressedMovement(false) or not ActionYield.nativeBusy(player)) then
        return "Stop moving before training."
    end
    if player:isAiming() or (state and state.trainingAimStopped) then
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
    if player:getBodyDamage():getOverallBodyHealth() <= 50 then return "Stopped because health is low. Recover before training." end
    if player:getBodyDamage():getNumPartsBleeding() > 0 then return "Stopped because you are bleeding. Treat the wound first." end
end

local function available(player)
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

local function yogaGate(player, state)
    local blocked, message = ZenWellnessContextMenu.Options.Yoga.canPerform(player, "", nil)
    local endurance = stat(player, "ENDURANCE")
    if endurance < yogaRecoveryStart then state.resting = true
    elseif endurance >= yogaRecoveryTarget then state.resting = nil end
    if not blocked and state.resting then return false, getText("Tooltip_Action_Exhausted") end
    return not blocked, message
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

local function stand(player, state)
    if not leaveFurniture(player, state) then return false end
    state.furnitureAttempted = nil
    if not player:isSitting() then return true end
    ownBatch(player, state, "standing", "Standing up for yoga.", function()
        ISTimedActionQueue.add(ISWaitWhileGettingUp:new(player))
    end)
    return false
end

local function restForYoga(player, state)
    if sit(player, state) then
        setPhase(state, "resting", string.format("Resting for yoga until stamina reaches %.0f%%.", yogaRecoveryTarget * 100))
    end
end

local function resetSupply(state)
    if state.fluidSupply then
        for _, loan in ipairs(state.fluidSupply.loans) do loan.defer = nil end
    end
    state.fluidSupply = nil
    state.supplyItem, state.supplyKind, state.supplyLoan, state.supplySource = nil, nil, nil, nil
    state.supplyBaseline, state.awaitSupplyUntil, state.preparation, state.supplyGoal = nil, nil, nil, nil
end

local function yieldToPlayer(player, state, unexplained)
    local entering = not state.yielding
    if entering then
        state.yielding = true
        for _, loan in ipairs(state.loans) do loan.interference, loan.defer = true, nil end
        Supplies.finishLoan(player, state.supplyLoan)
        resetSupply(state)
        state.collectingItem, state.contextInterrupted, state.travelScan = nil, nil, nil
        state.furnitureAttempted, state.cycleUntil = nil, nil
        state.careNeeds = {}
        -- Keep the way home, never the old target, item, action or portion.
        if state.excursion then state.excursion = {origin=state.excursion.origin, stage="resume-home"} end
        Nearby.invalidate(player)
        if state.active then
            setPhase(state, "manual", unexplained and "Training was interrupted. Checking before resuming."
                or "Waiting for your action. Training will resume when you are ready.")
        end
    end
    state.idleSince = nil
    state.observedGameHours = player:getHoursSurvived()
    if state.endurance then EnduranceGoal.observe(state.endurance, nil, getTimestampMs(), false) end
    if entering or state.pending or state.releasePending then clearOwned(player, state) end
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
    local collecting = {}
    for _, item in ipairs(items) do
        local loan = loanFor(player, state, item)
        if loan then
            loan.defer = true
            flow.loans[#flow.loans + 1] = loan
            if item:getID() == flow.vessel.item:getID() then flow.vesselLoan = loan end
        end
        if item:getContainer() ~= player:getInventory() then collecting[#collecting + 1] = item end
    end
    if #collecting == 0 then return queueFluidTransfer(player, state) end
    if not ownBatch(player, state, "collecting", "Collecting the bulk liquid and empty drinking vessel as needed.", function()
        for _, item in ipairs(collecting) do Supplies.transfer(player, item) end
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
    flow.phase, state.pending = "using", nil
    return "consume", vessel, flow.vesselLoan
end

local function useSupply(player, state, kind, item, loan)
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

local function nearbyTarget(player, state, kind, onlyWorldWater)
    if state.excursion or not Options.searchNearby() then return nil end
    state.travelRejected = state.travelRejected or {}
    local now, square, radius = getTimestampMs(), player:getSquare(), Options.searchRadius()
    local critical = kind ~= "literature" and player:getMoodles():getMoodleLevel(
        kind == "water" and MoodleType.THIRST or MoodleType.HUNGRY) >= 4
    state.travelScan = state.travelScan or {}
    local cached = state.travelScan[kind]
    if cached and cached.square == square and cached.radius == radius and cached.onlyWorldWater == onlyWorldWater and cached.critical == critical
            and now - cached.time < 1000 then return cached.target end
    local target = Nearby.find(player, kind, square, radius, state.travelRejected, onlyWorldWater)
    if critical and target and target.unknown then target = nil end
    state.travelScan[kind] = {square=square, radius=radius, onlyWorldWater=onlyWorldWater,
        critical=critical, time=now, target=target}
    return target
end

local function beginExcursion(player, state, kind, onlyWorldWater)
    local target = nearbyTarget(player, state, kind, onlyWorldWater)
    if not target then return false end
    local worldWater = kind == "water" and target.object ~= nil
    local waterObject = worldWater and Nearby.waterObject(player, target) or nil
    if (worldWater and not waterObject) or not vehicleTargetAvailable(player, target) then
        state.travelRejected[target.key] = true
        state.travelScan = nil
        return false
    end
    state.excursion = {origin = player:getSquare(), target = target, kind = kind,
        onlyWorldWater = onlyWorldWater, waterObject = waterObject, stage = "outbound"}
    state.travelScan = nil
    local here = player:getSquare()
    if target.unknown and ((target.part and Storage.vehicleAccessible(player, target.part))
            or (not target.part and here and here:canReachTo(target.square))) then
        state.excursion.stage, state.excursion.inspectUntil = "inspect", getTimestampMs() + 3000
        setPhase(state, "scouting", "Inspecting a nearby container through the normal loot interface.")
        return true
    end
    local route
    local message = waterObject and "Walking to a clean-water source; returning here after care."
        or "Walking to a supply container; returning here after care."
    local queued = ownBatch(player, state, "travelling", message, function()
        prepareScoutWalk()
        if player:isSitOnGround() then ISTimedActionQueue.add(ISWaitWhileGettingUp:new(player)) end
        if target.part then
            local vehicle = Storage.vehiclePart(target.part)
            if vehicle then
                ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(player, vehicle, target.part:getArea()))
                route = true
            end
        elseif waterObject then
            route = luautils.walkAdjObject(player, waterObject, true, true)
        else
            route = luautils.walkAdj(player, target.square, true)
        end
    end)
    if not route then clearOwned(player, state); queued = false end
    if not queued then
        state.travelRejected[target.key] = true
        state.pending = nil; state.excursion = nil
    end
    return queued
end

local function returnToOrigin(player, state)
    local trip = state.excursion
    if not trip then return false end
    if sameSquare(player:getSquare(), trip.origin) then
        state.excursion = nil
        return false
    end
    if trip.stage == "resume-home" and trip.origin then
        local cell, origin = getCell(), trip.origin
        trip.origin = cell and cell:getGridSquare(origin:getX(), origin:getY(), origin:getZ())
    end
    if not trip.origin or trip.origin:getZ() ~= player:getSquare():getZ() or not Storage.permitted(player, trip.origin) then
        Controller.stop(player, "The original training spot is no longer accessible. Stopped without forcing movement.")
        return true
    end
    trip.stage = "homebound"
    local queued = ownBatch(player, state, "travelling", "Returning to the original training spot.", function()
        prepareScoutWalk()
        if player:isSitOnGround() then ISTimedActionQueue.add(ISWaitWhileGettingUp:new(player)) end
        ISTimedActionQueue.add(ISWalkToTimedAction:new(player, trip.origin))
    end)
    if not queued then Controller.stop(player, "Could not start the walk back to the original training spot.") end
    return true
end

local function supply(player, state, kind, onlyWorldWater, waterObject)
    if kind == "literature" and player:tooDarkToRead() then return beginExcursion(player, state, kind, onlyWorldWater) end
    state.supplyMissingReason = nil
    local collect = state.collectNearby or Options.searchNearby() or state.excursion ~= nil
    local entry
    if waterObject then
        local source = WaterSources.choose(player, state.rejected, waterObject)
        if not source then return false end
        entry = {source=source}
    else
        entry = Supplies.choose(player, kind, collect, state.rejected, onlyWorldWater)
    end
    while entry and entry.source do
        local source = entry.source
        state.supplyItem, state.supplyLoan, state.collectingItem = nil, nil, nil
        state.supplyKind, state.supplySource = "water", source
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
        else return beginFluidSupply(player, state, entry.transfer) end
    end
    if not entry then
        if beginExcursion(player, state, kind, onlyWorldWater) then return true end
        if kind ~= "literature" then
            local report = Supplies.report(player, state.collectNearby or Options.searchNearby())
            state.supplyMissingReason = state.supplyMissingReason
                or report.fluidReason or (kind == "water" and report.waterSourceReason or report.openingReason)
        end
        return false
    end
    local item = entry.item
    local loan = loanFor(player, state, item)
    state.supplyItem, state.supplyKind, state.supplyLoan = item, kind, loan
    if item:getContainer() ~= player:getInventory() then
        state.collectingItem = item
        return ownBatch(player, state, "collecting", "Collecting " .. item:getDisplayName() .. ".", function()
            Supplies.transfer(player, item)
        end)
    end
    state.collectingItem = nil
    return useSupply(player, state, kind, item, loan)
end

local function train(player, state, kind)
    if state.cycleUntil then
        local remaining = state.cycleUntil - getTimestampMs()
        if remaining > 0 and remaining <= 500 then
            setPhase(state, "between", "Waiting briefly before the next training action.")
            return
        end
        state.cycleUntil = nil
    end
    if kind == "meditation" then
        if not sit(player, state) then return end
        local blocked, message = ZenWellnessContextMenu.Options.Meditation.canPerform(player, "", nil)
        if blocked then Controller.stop(player, message) return end
    elseif not stand(player, state) then return end
    local option = kind == "meditation" and ZenWellnessContextMenu.Options.Meditation or ZenWellnessContextMenu.Options.Yoga
    state.lastTraining = kind
    if not ownBatch(player, state, kind, kind == "yoga" and "Practicing yoga. Poses may fail normally; completed sessions restart automatically."
            or state.endurance and "Meditating until endurance reaches 100%."
            or "Meditating. AutoMindful will take care breaks and resume.", function()
        option.onAction({}, option, player)
    end) then
        Controller.stop(player, "Lifestyle did not start the action. Stand on clear ground and check its requirements.")
    end
end

local function criticalNeed(player, kind)
    return player:getMoodles():getMoodleLevel(kind == "water" and MoodleType.THIRST or MoodleType.HUNGRY) >= 4
end

local function comfortSupplyAvailable(player, state, kind)
    if kind == "literature" then
        if player:tooDarkToRead() then return nearbyTarget(player, state, kind, false) ~= nil end
    end
    local full = kind ~= "literature" and player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) >= 3
    if full and kind == "food" then return false end
    return Supplies.choose(player, kind, state.collectNearby or Options.searchNearby(), state.rejected, full) ~= nil
        or nearbyTarget(player, state, kind, full) ~= nil
end

local function care(player, state)
    state.careNotice = nil
    local fullness = player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN)
    for _, kind in ipairs({"water", "food"}) do
        local value = stat(player, kind == "water" and "THIRST" or "HUNGER")
        if value <= Consumables.restoredThreshold then state.careNeeds[kind] = nil end
        if value >= Consumables.careThreshold or criticalNeed(player, kind) then state.careNeeds[kind] = true end
    end
    local order = criticalNeed(player, "food") and not criticalNeed(player, "water")
        and {"food", "water"} or {"water", "food"}
    for _, kind in ipairs(order) do
        local critical = criticalNeed(player, kind)
        if state.careNeeds[kind] then
            if (kind == "water" or fullness < 3) and supply(player, state, kind, kind == "water" and fullness >= 3) then return true end
            if critical then
                if fullness >= 3 then
                    setPhase(state, "recovering", kind == "water"
                        and "Thirst is critical, but the game currently refuses another drink. Waiting for the drinking restriction to end."
                        or "Hunger is critical, but the game currently refuses more food. Waiting for the eating restriction to end.")
                else
                    Controller.stop(player, (kind == "water"
                        and "Stopped because thirst reached the game's Dying of Thirst stage and no suitable drink is available."
                        or "Stopped because hunger reached the game's Starving to Death stage and no suitable food is available.")
                        .. (state.supplyMissingReason and (" " .. state.supplyMissingReason) or ""))
                end
                return true
            end
            state.careNeeds[kind] = nil
            state.careNotice = state.supplyMissingReason and (state.supplyMissingReason .. " Training can continue.")
                or (kind == "water" and "No drink found; continuing while thirst is safe." or "No food found; continuing while hunger is safe.")
        end
    end
    if needSleep(player) then
        if isClient() and not getServerOptions():getBoolean("SleepAllowed") then
            Controller.stop(player, "Sleep is needed but this server does not allow it. Recover fatigue before restarting.")
            return true
        end
        if stat(player, "PANIC") > 0 or (player:getMoodles():getMoodleLevel(MoodleType.PAIN) >= 2
                and stat(player, "FATIGUE") <= 0.85) then
            if sit(player, state) then setPhase(state, "recovering", "Waiting for panic or pain to ease enough for normal sleep.") end
            return true
        end
        if player:getHoursSurvived() - player:getLastHourSleeped() <= 1 then
            if sit(player, state) then setPhase(state, "recovering", "Resting until the normal one-hour sleep cooldown ends.") end
            return true
        end
        player:setVariable("ExerciseStarted", false)
        player:setVariable("ExerciseEnded", true)
        ISWorldObjectContextMenu.onSleepWalkToComplete(player:getPlayerNum(), nil)
        if player:isAsleep() then setPhase(state, "sleeping", "Sleeping on the ground. Training resumes after waking.")
        else Controller.stop(player, "The game refused sleep. Resolve the sleep restriction, then start again.") end
        return true
    end
    return false
end

local function advance(player, state)
    if state.endurance then train(player, state, "meditation"); return end
    local meditation, yoga = levels(player)
    local needsMeditation = state.mode ~= "yoga" and meditation < 10
    local needsYoga = state.mode ~= "meditation" and yoga < 10
    if not needsMeditation and not needsYoga then
        state.active = false
        state.endPhase, state.endMessage = "complete", "Training complete. Selected skills have reached level 10."
        setPhase(state, state.endPhase, state.endMessage)
        showSessionEnd(player, state)
        return
    end
    if care(player, state) then return end
    local canYoga, yogaMessage = yogaGate(player, state)
    local boredom, pain = stat(player, "BOREDOM"), stat(player, "PAIN")
    if needsMeditation and boredom >= 20 then
        if supply(player, state, "literature") then return end
        if boredom > 30 then
            if state.mode == "both" and canYoga then train(player, state, "yoga") return end
            if state.mode == "both" and yogaMessage == getText("Tooltip_Action_Exhausted") then
                restForYoga(player, state)
                return
            end
            if state.mode == "both" and yogaMessage == getText("ContextMenu_Embarrassed") then
                if sit(player, state) then setPhase(state, "recovering", "Waiting for embarrassment to fade so yoga can relieve boredom.") end
                return
            end
            Controller.stop(player, "Meditation is blocked above 30 boredom. "
                .. (player:tooDarkToRead() and "Move to a lit spot to read. " or "Bring eligible leisure literature. ")
                .. (state.mode == "both" and "Yoga is currently unavailable." or "Select Train both if you also want yoga."))
            return
        end
        state.careNotice = "No eligible literature found; meditation is still allowed."
    end
    if needsYoga and canYoga and (not needsMeditation or state.lastTraining == "meditation" or boredom >= 10 or pain >= 15) then
        train(player, state, "yoga")
    elseif needsMeditation then
        train(player, state, "meditation")
    elseif yogaMessage == getText("Tooltip_Action_Exhausted") then
        restForYoga(player, state)
    elseif yogaMessage == getText("ContextMenu_Embarrassed") then
        if sit(player, state) then setPhase(state, "recovering", "Waiting for Lifestyle embarrassment to fade before the next yoga session.") end
    else
        Controller.stop(player, yogaMessage or "Yoga is unavailable. Check the mat and Lifestyle sandbox requirements.")
    end
end

local function finishPending(player, state, now)
    local failed = false
    for _, action in ipairs(state.pending) do
        if not action.autoMindfulFinished or action.autoMindfulStopped then failed = true end
    end
    if state.fluidSupply and state.fluidSupply.phase ~= "using" then
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
            local completed = not failed
            failed = false
            if state.supplyKind == "literature" then Supplies.markRead(player, state.supplyItem)
            elseif Consumables.goalSatisfied(player, state.supplyItem, state.supplyKind, state.supplyGoal, completed) then
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
        state.failures = state.failures + 1
        if state.supplyItem then
            state.rejected[state.supplyItem:getID()] = state.supplyKind == "literature" and now + 60000 or true
        end
        if state.supplySource then state.rejected[state.supplySource.object] = now + 60000 end
        if state.failures >= 3 then
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

local function lostTrainingAction(state, queue)
    if #queue > 0 or not state.pending or (state.phase ~= "meditation" and state.phase ~= "yoga") then return false end
    for _, action in ipairs(state.pending) do
        if action.autoMindfulStopped or not action.autoMindfulFinished then return true end
    end
    return false
end

function Controller.update(player)
    local state = states[player]
    if not state or not player:isLocalPlayer() then return end
    ActionYield.finishHandoff(player)
    if not state.active and #state.loans == 0 and not state.releasePending then return end
    local now = getTimestampMs()
    local queue = queueFor(player)
    if state.uiQueueHead ~= queue[1] or (state.paperMapOpen and player:pressedCancelAction()) then
        state.windowChecked = nil
    end
    state.uiQueueHead = queue[1]
    local wasInspecting = state.inspectingUI
    state.inspectingUI = ActionYield.inspecting(player, state, now)
    if not player:pressedCancelAction() then state.uiCancelHeld = nil
    elseif state.inspectingUI or wasInspecting then state.uiCancelHeld = true end
    local danger = unsafeReason(player, state)
    if danger then
        if state.active then Controller.stop(player, danger)
        elseif state.pending or state.releasePending then clearOwned(player, state) end
        return
    end
    local occupied = ActionYield.occupied(player, queue, state) or state.inspectingUI
    local lost = state.active and lostTrainingAction(state, queue)
    local busy = occupied or lost or (state.active and player:pressedMovement(false))
    -- Recognized activity (including a long map/workout) has no time limit.
    -- A stale native busy flag with neither a Lua action nor Java handle is
    -- ambiguous: while recovering from a vanished action, only disarm our loop.
    local unconfirmed = occupied and state.active and (lost or state.lostWithoutAction)
        and not queue[1] and player:getCharacterActions():isEmpty() and not ISTimedActionQueue.isPlayerDoingAction(player)
        and not state.inspectingUI and not state.contextVisible and not player:isAsleep() and not player:pressedMovement(false)
    if unconfirmed then
        if not state.unconfirmedSince or now < state.unconfirmedSince then state.unconfirmedSince = now end
        if now - state.unconfirmedSince >= 5000 then
            Controller.stop(player, "Training stopped; the game reported activity without a current action. Start again when ready.")
            return
        end
    else
        state.unconfirmedSince = nil
    end
    if (occupied and not unconfirmed) or state.contextVisible then
        state.unknownPauses, state.quietMs, state.lostWithoutAction = nil, 750, nil
    elseif lost and not state.yielding then
        state.lostWithoutAction = true
        state.unknownPauses = 1 + (state.unknownPauses or 0)
        if state.unknownPauses >= 4 then
            Controller.stop(player, "Training was interrupted repeatedly without another action. Start again when ready.")
            return
        end
        state.quietMs = 750 * 2 ^ (state.unknownPauses - 1)
    end
    local quietMs = state.quietMs or 750
    if state.active then
        local ready, reason = available(player)
        if not ready then Controller.stop(player, reason); return end
        if state.endurance then
            local quiet = not busy and not state.releasePending and not player:isAsleep() and not state.aimStarted
                and not state.contextVisible and (not state.yielding or (state.idleSince and now - state.idleSince >= quietMs))
            if updateEndurance(player, state, now, quiet) then return end
        end
    end
    if state.releasePending then clearOwned(player, state); return end
    if not state.active and #state.loans == 0 then return end
    if state.aimStarted then state.idleSince = nil; return end
    if busy then
        yieldToPlayer(player, state, lost and not occupied and not state.contextVisible)
        return
    end
    if player:isAsleep() then
        state.idleSince = nil
        if state.active then setPhase(state, "sleeping", "Sleeping. Training resumes after waking.") end
        return
    end
    if state.yielding then
        if state.contextVisible then state.idleSince = nil; return end
        if not state.idleSince or now < state.idleSince then state.idleSince = now end
        if now - state.idleSince < quietMs then return end
        state.yielding, state.idleSince, state.lostWithoutAction = nil, nil, nil
        state.observedGameHours = player:getHoursSurvived()
        if state.active then setPhase(state, "resuming", "Checking your current needs and training spot.") end
    end
    if state.lastUpdate and now >= state.lastUpdate and now - state.lastUpdate < 250 then return end
    state.lastUpdate = now
    if state.excursion and state.excursion.stage == "outbound" and state.excursion.target.part
            and not vehicleTargetAvailable(player, state.excursion.target) then
        Controller.stop(player, "The vehicle supply source moved or became inaccessible. Stopped without forcing movement.")
        return
    end
    if state.active and not state.endurance then
        local gameHours = player:getHoursSurvived()
        local yoga = HiddenSkills.getSkill(player, "Yoga")
        local meditationXP = player:getXp():getXP(Perks.Meditation)
        if meditationXP ~= state.progressMeditation or yoga[1] ~= state.progressYogaLevel or yoga[2] ~= state.progressYogaXP then
            state.hoursWithoutXP = 0
            state.progressMeditation, state.progressYogaLevel, state.progressYogaXP = meditationXP, yoga[1], yoga[2]
        elseif not state.contextVisible and (state.phase == "meditation" or state.phase == "yoga") then
            state.hoursWithoutXP = state.hoursWithoutXP + math.max(0, gameHours - state.observedGameHours)
        end
        state.observedGameHours = gameHours
        if state.hoursWithoutXP > 6 then
            Controller.stop(player, "Training produced no XP for six game hours. Check Lifestyle XP settings or server restrictions.")
            return
        end
    end
    if #queue > 0 then
        if state.excursion and state.phase == "travelling" and now - state.actionStarted > 30000 then
            Controller.stop(player, "The supply route was blocked or took too long. Stopped without forcing movement.")
            return
        end
        local urgent = criticalNeed(player, "water") or criticalNeed(player, "food")
        if state.phase == "meditation" and not state.endurance then
            local meditation = levels(player)
            local boredom = stat(player, "BOREDOM")
            local reading = boredom >= 20 and comfortSupplyAvailable(player, state, "literature")
            local eating = stat(player, "HUNGER") >= 0.2 and comfortSupplyAvailable(player, state, "food")
            local drinking = stat(player, "THIRST") >= 0.2 and comfortSupplyAvailable(player, state, "water")
            if meditation >= 10 or boredom > 30 or reading or eating or drinking
                    or urgent or needSleep(player) then
                clearOwned(player, state)
                setPhase(state, "care", "Taking a care break before resuming training.")
            end
        elseif state.phase == "yoga" and (urgent
                or (stat(player, "HUNGER") >= 0.6 and comfortSupplyAvailable(player, state, "food"))
                or (stat(player, "THIRST") >= 0.5 and comfortSupplyAvailable(player, state, "water"))
                or stat(player, "ENDURANCE") <= 0.1) then
            clearOwned(player, state)
            setPhase(state, "care", "Taking an urgent care break. Lifestyle may apply its normal early-stop yoga penalty.")
        elseif state.phase == "standing" and now - state.actionStarted > 15000 then
            Controller.stop(player, "Could not stand up here. Move to clear ground and start again.")
        end
        return
    end
    if state.contextVisible then
        if state.pending then
            for _, action in ipairs(state.pending) do
                if not action.autoMindfulFinished then state.contextInterrupted = true end
            end
        end
        return
    end
    if state.contextInterrupted then
        state.contextInterrupted = nil
        local interrupted = false
        for _, action in ipairs(state.pending or {}) do if not action.autoMindfulFinished then interrupted = true end end
        if interrupted then
            Supplies.finishLoan(player, state.supplyLoan)
            for _, loan in ipairs(state.loans) do loan.defer = nil end
            state.pending = nil
            resetSupply(state)
        end
    end
    if state.excursion and state.pending and state.phase == "travelling" then
        local trip = state.excursion
        local failedPath = false
        for _, action in ipairs(state.pending) do
            if action.autoMindfulStopped then
                print("[AutoMindful] " .. trip.stage .. " walk stopped: action=" .. tostring(action.Type)
                    .. " path=" .. tostring(action.result) .. " speed=" .. tostring(getGameSpeed()))
                if routeAction(action) and action.result ~= nil and action.result == BehaviorResult.Failed
                        and not player:pressedMovement(false) and not player:pressedCancelAction() then
                    failedPath = true
                else
                    Controller.stop(player, trip.stage == "homebound"
                        and "The return walk was cancelled. Start again when you are ready."
                        or "The supply walk was cancelled. Stopped without forcing a return.")
                    return
                end
            end
        end
        state.pending = nil
        if trip.stage == "homebound" then
            if not sameSquare(player:getSquare(), trip.origin) then
                Controller.stop(player, failedPath
                    and "The game found no path back to the original training spot. Clear the route and start training again."
                    or "Could not return to the original training spot. Clear the route and start again.")
                return
            end
            state.excursion = nil
        else
            local here, target = player:getSquare(), trip.target.square
            local arrived = here and here:getZ() == target:getZ()
                and math.abs(here:getX()-target:getX()) <= 1 and math.abs(here:getY()-target:getY()) <= 1
                and (sameSquare(here, target) or here:canReachTo(target))
            if trip.waterObject then
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
                state.travelRejected[trip.target.key] = true
                state.travelScan = nil
                if failedPath then state.careNotice = "No route to this supply. Skipping it and returning to the training spot." end
            end
        end
    end
    local trip = state.excursion
    if trip and trip.stage == "inspect" then
        if Options.searchNearby() and (not trip.target.part or (vehicleTargetAvailable(player, trip.target) and Storage.vehicleAccessible(player, trip.target.part))) then
            Supplies.refreshNearby(player)
            if supply(player, state, trip.kind, trip.onlyWorldWater, trip.waterObject) then
                trip.stage = "care"
                Nearby.invalidate(player)
                return
            end
            if now < trip.inspectUntil then
                setPhase(state, "scouting", trip.waterObject and "Checking the selected water source is still usable."
                    or "Waiting for this container's contents; unknown is not empty.")
                return
            end
        end
        state.travelRejected[trip.target.key] = true
        state.travelScan = nil
        state.careNotice = trip.waterObject and "The selected water source was not usable. Returning before trying another source."
            or "This container did not confirm a usable supply. Returning before trying another source."
        trip.stage = "care"
        Nearby.invalidate(player)
    end
    local endedTraining = state.pending and (state.phase == "meditation" or state.phase == "yoga")
    if state.pending and finishPending(player, state, now) then return end
    if endedTraining then state.unknownPauses, state.quietMs = nil, nil end
    if endedTraining and state.active and (state.endurance or not atSkillGoal(player, state)) then
        state.cycleUntil = now + 500
    end
    if not (state.active and state.endurance) and returnBorrowed(player, state) then return end
    if state.active and returnToOrigin(player, state) then return end
    if not state.active then
        if state.endPhase then setPhase(state, state.endPhase, state.endMessage) end
        return
    end
    advance(player, state)
end

function Controller.start(player, mode, collectNearby)
    if not player or not player:isLocalPlayer() then return false, "Choose a local survivor." end
    if not modeTitles[mode] then return false, "Unknown training mode." end
    local old = stateFor(player)
    if old.active and old.trainingAimStopped then Controller.stop(player, aimStopMessage) end
    if old.active then return false, "Training is already active. Stop before changing the mode." end
    if old.releasePending and not clearOwned(player, old) then return false, "Waiting for the previous action to settle." end
    local ready, message = available(player)
    if not ready then return false, message end
    local initialEndurance
    if mode == "endurance" then
        initialEndurance = EnduranceGoal.read(player)
        if initialEndurance == nil then return false, "Could not read the survivor's endurance." end
        if EnduranceGoal.full(initialEndurance) then return false, "Endurance is already full." end
    end
    local danger = unsafeReason(player)
    if danger then return false, danger end
    if player:isAsleep() then return false, "Wait until the survivor wakes up." end
    local yoga = HiddenSkills.getSkill(player, "Yoga")
    local state = {active = true, mode = mode, collectNearby = collectNearby == true, phase = "starting",
        message = "Checking supplies and training requirements.", rejected = {}, careNeeds = {}, failures = 0, hoursWithoutXP = 0,
        observedGameHours = player:getHoursSurvived(), progressMeditation = player:getXp():getXP(Perks.Meditation),
        progressYogaLevel = yoga[1], progressYogaXP = yoga[2]}
    ActionYield.rememberPosition(state, player)
    if initialEndurance then state.endurance = {best=initialEndurance} end
    if state.endurance or (mode ~= "yoga" and player:getPerkLevel(Perks.Meditation) < 10) or (mode ~= "meditation" and yoga[1] < 10) then
        state.session = {startedAt=getTimestampMs(), progress=Progress.snapshot(player)}
    end
    state.loans, state.returnNotice = old.loans or {}, old.returnNotice
    states[player] = state
    if #queueFor(player) > 0 or ActionYield.nativeBusy(player) then yieldToPlayer(player, state) end
    return true, state.message
end

function Controller.status(player)
    if not player then return {active = false, phase = "idle", message = "No local survivor.", meditation = 0, yoga = 0} end
    local state = stateFor(player)
    local meditation, yoga = levels(player)
    return {active = state.active, phase = state.phase, message = state.message, meditation = meditation, yoga = yoga,
        progress = Progress.snapshot(player), mode = state.mode, collectNearby = state.collectNearby,
        endurance = state.endurance and EnduranceGoal.read(player) or nil,
        returnNotice = state.returnNotice or state.fluidNotice, careNotice = state.careNotice, pendingReturns = #state.loans}
end

function Controller.prepare(player, collectNearby, showNearby, force)
    if not player then return {message = "No local survivor."} end
    local state = states[player]
    local origin = state and state.excursion and state.excursion.origin or player:getSquare()
    if showNearby then Supplies.refreshNearby(player) end
    local area = showNearby and Nearby.scan(player, origin, Options.searchRadius(), force) or nil
    local walking = Options.searchNearby()
    local report = Supplies.report(player, showNearby == true or collectNearby == true,
        collectNearby == true or walking, area, walking)
    report.walkingEnabled = walking
    return report
end

local function onPlayerUpdate(player)
    local state = states[player]
    if not state or (not state.active and #state.loans == 0 and not state.releasePending) then return end
    local ok, message = pcall(Controller.update, player)
    if not ok then
        Controller.stop(player, "AutoMindful stopped after an error. See console.txt for details.")
        print("[AutoMindful] ERROR: " .. tostring(message))
    end
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnPlayerDeath.Add(function(player) if states[player] then Controller.stop(player, "Stopped because the survivor died.") end end)
Events.OnGameStart.Add(function() states = {} end)

return Controller
