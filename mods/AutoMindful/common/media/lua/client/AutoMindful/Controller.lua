require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISReadABook"
require "TimedActions/ISDrinkFluidAction"
require "TimedActions/ISWaitWhileGettingUp"
require "ISUI/ISWorldObjectContextMenu"
local Supplies = require "AutoMindful/Supplies"
local Consumables = require "AutoMindful/Consumables"
local WaterSources = require "AutoMindful/WaterSources"
local Progress = require "AutoMindful/Progress"

AutoMindful = AutoMindful or {}
local Controller = {}
AutoMindful.Controller = Controller
local states = {}
local modes = {both = true, meditation = true, yoga = true}
local yogaRecoveryStart, yogaRecoveryTarget = 0.85, 0.95

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
    local meditation = Perks.Meditation and player:getPerkLevel(Perks.Meditation) or 0
    local yoga = HiddenSkills and HiddenSkills.getLevel and HiddenSkills.getLevel(player, "Yoga") or 0
    return meditation, yoga
end

local function setPhase(state, phase, message)
    if state.phase ~= phase or state.message ~= message then
        print("[AutoMindful] " .. phase .. ": " .. message)
    end
    state.phase, state.message = phase, message
end

local function clearOwned(player, state)
    local timed = ISTimedActionQueue.getTimedActionQueue(player)
    if timed.queue[1] and timed.queue[1].autoMindfulOwner == state then
        local foreign = {}
        for index = #timed.queue, 1, -1 do
            local action = timed.queue[index]
            if action.autoMindfulOwner ~= state then
                table.insert(foreign, 1, action)
                timed:removeFromQueue(action)
            end
        end
        ISTimedActionQueue.clear(player)
        for _, action in ipairs(foreign) do ISTimedActionQueue.add(action) end
    else
        for index = #timed.queue, 1, -1 do
            local action = timed.queue[index]
            if action.autoMindfulOwner == state then
                action:forceCancel()
                timed:removeFromQueue(action)
            end
        end
    end
    state.pending = nil
end

function Controller.stop(player, reason)
    local state = stateFor(player)
    local wasActive = state.active
    state.active = false
    clearOwned(player, state)
    Supplies.finishLoan(player, state.supplyLoan)
    for _, loan in ipairs(state.loans) do loan.defer = nil end
    state.supplyItem, state.supplyKind, state.supplyLoan, state.supplySource = nil, nil, nil, nil
    state.supplyBaseline, state.preparation, state.collectingItem = nil, nil, nil
    state.endPhase, state.endMessage = "stopped", reason or "Stopped. Start again when you are ready."
    setPhase(state, state.endPhase, state.endMessage)
    if wasActive and HaloTextHelper then
        HaloTextHelper.addBadText(player, "AutoMindful: " .. state.endMessage)
    end
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
                if method == "stop" then self.autoMindfulStopped = true end
                local before = {}
                for _, queued in ipairs(queueFor(player)) do before[queued] = true end
                local result = original(self, ...)
                for _, queued in ipairs(queueFor(player)) do
                    if not before[queued] then ownAction(player, state, queued) end
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

local function unsafeReason(player, state)
    if player:isDead() then return "Stopped because the survivor died." end
    if player:isOnFire() then return "Stopped because the survivor is on fire." end
    if player:getVehicle() then return "Stopped because you entered a vehicle." end
    if player:isPlayerMoving() then return "Cancelled because you moved." end
    local menu = getPlayerContextMenu and getPlayerContextMenu(player:getPlayerNum())
    local inspecting = menu and menu:isVisible()
    if state then state.contextVisible = inspecting == true end
    if player:isAiming() and not inspecting then
        if not state then return "Stop aiming before starting training." end
        state.aimStarted = state.aimStarted or getTimestampMs()
        if getTimestampMs() - state.aimStarted >= 500 then return "Cancelled because you started aiming." end
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
    if not ZenWellnessContextMenu or not ZenWellnessContextMenu.Options or not HiddenSkills
            or not HiddenSkills.getSkill or not Perks.Meditation then
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

local function sit(player, state)
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
    state.supplyItem, state.supplyKind, state.supplyLoan, state.supplySource = nil, nil, nil, nil
    state.supplyBaseline, state.awaitSupplyUntil, state.preparation = nil, nil, nil
end

local function useSupply(player, state, kind, item, loan)
    local descriptor = Consumables.inspect(player, item, state.collectNearby)
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
    if kind ~= "literature" and descriptor.needsOpening then
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
                Consumables.consume(player, item, kind)
            end)
        end
    end
    if not queued then Controller.stop(player, "The game could not start using " .. item:getDisplayName() .. ". Check its tools and action requirements.") end
    return true
end

local function supply(player, state, kind, onlyWorldWater)
    if kind == "literature" and player:tooDarkToRead() then return false end
    state.supplyMissingReason = nil
    local entry = Supplies.choose(player, kind, state.collectNearby, state.rejected, onlyWorldWater)
    while entry and entry.source do
        local source = entry.source
        state.supplyItem, state.supplyLoan, state.collectingItem = nil, nil, nil
        state.supplyKind, state.supplySource = "water", source
        state.supplyBaseline = {thirst = stat(player, "THIRST")}
        local queued = ownBatch(player, state, "drinking", "Drinking from a nearby clean-water source.", function()
            local used, reason = WaterSources.drink(player, source)
            if not used then state.supplyMissingReason = reason end
        end)
        if not queued then
            state.rejected[source.object] = getTimestampMs() + 60000
            state.supplyKind, state.supplySource, state.supplyBaseline = nil, nil, nil
            state.pending = nil
        end
        if queued then return true end
        entry = Supplies.choose(player, kind, state.collectNearby, state.rejected, onlyWorldWater)
    end
    if not entry then
        if kind ~= "literature" then
            local report = Supplies.report(player, state.collectNearby)
            state.supplyMissingReason = state.supplyMissingReason
                or (kind == "water" and report.waterSourceReason or report.openingReason)
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
    if kind == "meditation" then
        if not sit(player, state) then return end
        local blocked, message = ZenWellnessContextMenu.Options.Meditation.canPerform(player, "", nil)
        if blocked then Controller.stop(player, message) return end
    elseif not stand(player, state) then return end
    local option = kind == "meditation" and ZenWellnessContextMenu.Options.Meditation or ZenWellnessContextMenu.Options.Yoga
    state.lastTraining = kind
    if not ownBatch(player, state, kind, kind == "yoga" and "Practicing yoga. Poses may fail normally; completed sessions restart automatically."
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
        if player:tooDarkToRead() then return false end
    end
    local full = kind ~= "literature" and player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) >= 3
    if full and kind == "food" then return false end
    return Supplies.choose(player, kind, state.collectNearby, state.rejected, full) ~= nil
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
    local meditation, yoga = levels(player)
    local needsMeditation = state.mode ~= "yoga" and meditation < 10
    local needsYoga = state.mode ~= "meditation" and yoga < 10
    if not needsMeditation and not needsYoga then
        state.active = false
        state.endPhase, state.endMessage = "complete", "Training complete. Selected skills have reached level 10."
        setPhase(state, state.endPhase, state.endMessage)
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

local function allowedManual(action)
    return action.Type == "ISInventoryTransferAction"
end

local function finishPending(player, state, now)
    local failed = false
    for _, action in ipairs(state.pending) do
        if not action.autoMindfulFinished then failed = true end
    end
    if state.collectingItem then
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
            failed = false
            if state.supplyKind == "literature" then Supplies.markRead(player, state.supplyItem) end
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

function Controller.update(player)
    local state = states[player]
    if not state or not player:isLocalPlayer() then return end
    if not state.active and #state.loans == 0 then return end
    local danger = unsafeReason(player, state)
    if danger then
        if state.active then Controller.stop(player, danger)
        elseif state.pending then clearOwned(player, state) end
        return
    end
    if state.aimStarted then return end
    if player:isAsleep() then
        if state.active then setPhase(state, "sleeping", "Sleeping. Training resumes after waking.") end
        return
    end
    local now = getTimestampMs()
    if state.lastUpdate and now - state.lastUpdate < 250 then return end
    state.lastUpdate = now
    local queue = queueFor(player)
    local foreign, takeover
    for _, action in ipairs(queue) do
        if action.autoMindfulOwner ~= state then
            foreign = action
            if not allowedManual(action) then takeover = action; break end
        end
    end
    if takeover then
        if state.active then
            print("[AutoMindful] manual action took over: " .. tostring(takeover.Type))
            Controller.stop(player, takeover.Type == "ISWalkToTimedAction"
                and "Cancelled because you started walking."
                or "Cancelled because another action took over. Start again after it finishes.")
        end
        return
    end
    if foreign then
        if state.pending then
            for _, loan in ipairs(state.loans) do loan.interference = true end
            clearOwned(player, state)
            Supplies.finishLoan(player, state.supplyLoan)
            for _, loan in ipairs(state.loans) do loan.defer = nil end
            resetSupply(state)
        end
        if state.active then setPhase(state, "manual", "Waiting for your inventory transfer. Training resumes afterward.") end
        return
    end
    if state.active then
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
        local urgent = criticalNeed(player, "water") or criticalNeed(player, "food")
        if state.phase == "meditation" then
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
    if state.pending and finishPending(player, state, now) then return end
    if returnBorrowed(player, state) then return end
    if not state.active then
        if state.endPhase then setPhase(state, state.endPhase, state.endMessage) end
        return
    end
    advance(player, state)
end

function Controller.start(player, mode, collectNearby)
    if not player or not player:isLocalPlayer() then return false, "Choose a local survivor." end
    if not modes[mode] then return false, "Unknown training mode." end
    local ready, message = available(player)
    if not ready then return false, message end
    local danger = unsafeReason(player)
    if danger then return false, danger end
    local old = stateFor(player)
    if old.active then return false, "Training is already active. Stop before changing the mode." end
    if #queueFor(player) > 0 or player:hasTimedActions() then return false, "Finish the current action before starting." end
    if player:isSittingOnFurniture() or player:getModData().IsSittingOnSeat then return false, "Stand up from the seat before starting." end
    if player:isAsleep() then return false, "Wait until the survivor wakes up." end
    local yoga = HiddenSkills.getSkill(player, "Yoga")
    local state = {active = true, mode = mode, collectNearby = collectNearby == true, phase = "starting",
        message = "Checking supplies and training requirements.", rejected = {}, careNeeds = {}, failures = 0, hoursWithoutXP = 0,
        observedGameHours = player:getHoursSurvived(), progressMeditation = player:getXp():getXP(Perks.Meditation),
        progressYogaLevel = yoga[1], progressYogaXP = yoga[2]}
    state.loans, state.returnNotice = old.loans or {}, old.returnNotice
    states[player] = state
    return true, state.message
end

function Controller.status(player)
    if not player then return {active = false, phase = "idle", message = "No local survivor.", meditation = 0, yoga = 0} end
    local state = stateFor(player)
    local meditation, yoga = levels(player)
    return {active = state.active, phase = state.phase, message = state.message, meditation = meditation, yoga = yoga,
        progress = Progress.snapshot(player), mode = state.mode, collectNearby = state.collectNearby,
        returnNotice = state.returnNotice, careNotice = state.careNotice, pendingReturns = #state.loans}
end

function Controller.prepare(player, collectNearby, showNearby)
    if not player then return {message = "No local survivor."} end
    return Supplies.report(player, showNearby == true or collectNearby == true, collectNearby == true)
end

local function onPlayerUpdate(player)
    local state = states[player]
    if not state or (not state.active and #state.loans == 0) then return end
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
