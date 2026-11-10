require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISReadABook"
require "TimedActions/ISDrinkFluidAction"
require "TimedActions/ISWaitWhileGettingUp"
require "ISUI/ISWorldObjectContextMenu"
local Supplies = require "AutoMindful/Supplies"

AutoMindful = AutoMindful or {}
local Controller = {}
AutoMindful.Controller = Controller
local states = {}
local modes = {both = true, meditation = true, yoga = true}

local function stateFor(player)
    if not states[player] then
        states[player] = {active = false, phase = "idle", message = "Choose a training mode to begin."}
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
    state.active = false
    clearOwned(player, state)
    setPhase(state, "stopped", reason or "Stopped. Start again when you are ready.")
end

local function ownBatch(player, state, phase, message, addActions)
    addActions()
    local queue = queueFor(player)
    state.pending = {}
    for _, action in ipairs(queue) do
        action.autoMindfulOwner = state
        local originalPerform, originalStop = action.perform, action.stop
        action.perform = function(self, ...)
            self.autoMindfulFinished = true
            return originalPerform(self, ...)
        end
        action.stop = function(self, ...)
            self.autoMindfulStopped = true
            return originalStop(self, ...)
        end
        state.pending[#state.pending + 1] = action
    end
    state.actionStarted = getTimestampMs()
    setPhase(state, phase, message)
    return #state.pending > 0
end

local function needSleep(player)
    if isClient() and not getServerOptions():getBoolean("SleepNeeded") then return false end
    return stat(player, "FATIGUE") >= 0.6
end

local function unsafeReason(player)
    if player:isDead() then return "Stopped because the survivor died." end
    if player:isOnFire() then return "Stopped because the survivor is on fire." end
    if player:getVehicle() then return "Stopped because you entered a vehicle." end
    if player:isPlayerMoving() or player:isAiming() then return "Stopped because you moved or aimed." end
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

local function yogaGate(player)
    local blocked, message = ZenWellnessContextMenu.Options.Yoga.canPerform(player, "", nil)
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

local function supply(player, state, kind)
    if kind == "literature" and player:tooDarkToRead() then return false end
    local entry = Supplies.choose(player, kind, state.collectNearby, state.rejected)
    if not entry then return false end
    local item = entry.item
    state.supplyItem, state.supplyKind = item, kind
    if item:getContainer() ~= player:getInventory() then
        state.collectingItem = item
        return ownBatch(player, state, "collecting", "Collecting " .. item:getDisplayName() .. ".", function()
            Supplies.transfer(player, item)
        end)
    end
    state.collectingItem = nil
    state.supplyBaseline = {hunger = stat(player, "HUNGER"), calories = player:getNutrition():getCalories(),
        thirst = stat(player, "THIRST"), boredom = stat(player, "BOREDOM")}
    if kind == "literature" then
        state.rejected[item:getID()] = true
        return ownBatch(player, state, "reading", "Reading " .. item:getDisplayName() .. " to relieve boredom.", function()
            ISTimedActionQueue.add(ISReadABook:new(player, item))
        end)
    elseif kind == "food" then
        local fraction = math.min(1, math.max(0.25, (stat(player, "HUNGER") + 0.1) / -item:getHungerChange()))
        return ownBatch(player, state, "eating", "Eating " .. item:getDisplayName() .. ".", function()
            ISInventoryPaneContextMenu.eatItem(item, fraction, player:getPlayerNum())
        end)
    else
        local percentage = math.min(1, stat(player, "THIRST") * 2 / item:getFluidContainer():getAmount())
        return ownBatch(player, state, "drinking", "Drinking clean water.", function()
            local mask = ISInventoryPaneContextMenu.getEatingMask(player, true)
            ISTimedActionQueue.add(ISDrinkFluidAction:new(player, item, percentage))
            if mask then ISTimedActionQueue.add(ISWearClothing:new(player, mask, 50)) end
        end)
    end
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

local function care(player, state)
    if stat(player, "THIRST") >= 0.15 then
        if player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) >= 3 then
            setPhase(state, "recovering", "Waiting until the game's fluid drinking action permits another drink.")
            return true
        end
        if not supply(player, state, "water") then Controller.stop(player, "Clean water ran out. Bring an unsealed bottle of clean water, then start again.") end
        return true
    end
    local hungry = stat(player, "HUNGER") >= 0.15
    local needsCalories = player:getNutrition():getCalories() < 500
        and player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) < 3
    if hungry or needsCalories then
        if not supply(player, state, "food") then Controller.stop(player, "Ready-to-eat food ran out. Bring safe, unsealed food with enough calories, then start again.") end
        return true
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
    if stat(player, "ENDURANCE") < 0.85 then state.resting = true end
    if state.resting then
        if stat(player, "ENDURANCE") >= 0.95 then state.resting = nil
        else
            if sit(player, state) then setPhase(state, "resting", "Resting on the ground until endurance recovers.") end
            return true
        end
    end
    return false
end

local function advance(player, state)
    local meditation, yoga = levels(player)
    local needsMeditation = state.mode ~= "yoga" and meditation < 10
    local needsYoga = state.mode ~= "meditation" and yoga < 10
    if not needsMeditation and not needsYoga then
        state.active = false
        setPhase(state, "complete", "Training complete. Selected skills have reached level 10.")
        return
    end
    if care(player, state) then return end
    local canYoga, yogaMessage = yogaGate(player)
    local boredom, pain = stat(player, "BOREDOM"), stat(player, "PAIN")
    if needsMeditation and boredom >= 20 then
        if supply(player, state, "literature") then return end
        if canYoga then train(player, state, "yoga") return end
        if yogaMessage == getText("ContextMenu_Embarrassed") then
            if sit(player, state) then setPhase(state, "recovering", "Waiting for embarrassment to fade so yoga can relieve boredom.") end
            return
        end
        if boredom > 30 then
            Controller.stop(player, player:tooDarkToRead() and "Too dark to read and yoga is unavailable. Move to a lit training spot."
                or "Meditation needs lower boredom. Bring unread leisure books, comics, or magazines, or make yoga available.")
            return
        end
    end
    if needsYoga and canYoga and (not needsMeditation or state.lastTraining == "meditation" or boredom >= 10 or pain >= 15) then
        train(player, state, "yoga")
    elseif needsMeditation then
        train(player, state, "meditation")
    elseif yogaMessage == getText("ContextMenu_Embarrassed") then
        if sit(player, state) then setPhase(state, "recovering", "Waiting for Lifestyle embarrassment to fade before the next yoga session.") end
    else
        Controller.stop(player, yogaMessage or "Yoga is unavailable. Check the mat and Lifestyle sandbox requirements.")
    end
end

function Controller.update(player)
    local state = states[player]
    if not state or not state.active or not player:isLocalPlayer() then return end
    local danger = unsafeReason(player)
    if danger then Controller.stop(player, danger) return end
    if player:isAsleep() then setPhase(state, "sleeping", "Sleeping. Training resumes after waking.") return end
    local now = getTimestampMs()
    if state.lastUpdate and now - state.lastUpdate < 250 then return end
    state.lastUpdate = now
    local gameHours = player:getHoursSurvived()
    local yoga = HiddenSkills.getSkill(player, "Yoga")
    local meditationXP = player:getXp():getXP(Perks.Meditation)
    if meditationXP ~= state.progressMeditation or yoga[1] ~= state.progressYogaLevel or yoga[2] ~= state.progressYogaXP then
        state.hoursWithoutXP = 0
        state.progressMeditation, state.progressYogaLevel, state.progressYogaXP = meditationXP, yoga[1], yoga[2]
    elseif state.phase == "meditation" or state.phase == "yoga" then
        state.hoursWithoutXP = state.hoursWithoutXP + math.max(0, gameHours - state.observedGameHours)
    end
    state.observedGameHours = gameHours
    if state.hoursWithoutXP > 6 then
        Controller.stop(player, "Training produced no XP for six game hours. Check Lifestyle XP settings or server restrictions.")
        return
    end
    local queue = queueFor(player)
    if #queue > 0 then
        for _, action in ipairs(queue) do
            if action.autoMindfulOwner ~= state then
                Controller.stop(player, "Stopped for another queued action. Start again after it finishes.")
                return
            end
        end
        if state.phase == "meditation" then
            local meditation = levels(player)
            if meditation >= 10 or stat(player, "BOREDOM") >= 20 or stat(player, "HUNGER") >= 0.2
                    or stat(player, "THIRST") >= 0.2 or stat(player, "ENDURANCE") < 0.2 or needSleep(player) then
                clearOwned(player, state)
                setPhase(state, "care", "Taking a care break before resuming training.")
            end
        elseif state.phase == "yoga" and (stat(player, "HUNGER") >= 0.6 or stat(player, "THIRST") >= 0.5
                or stat(player, "ENDURANCE") <= 0.1) then
            clearOwned(player, state)
            setPhase(state, "care", "Taking an urgent care break. Lifestyle may apply its normal early-stop yoga penalty.")
        elseif state.phase == "standing" and now - state.actionStarted > 15000 then
            Controller.stop(player, "Could not stand up here. Move to clear ground and start again.")
        end
        return
    end
    if state.pending then
        local failed = false
        for _, action in ipairs(state.pending) do
            if not action.autoMindfulFinished then failed = true end
        end
        if state.collectingItem and state.collectingItem:getContainer() ~= player:getInventory() then
            state.rejected[state.collectingItem:getID()] = true
            failed = true
        end
        if not failed and not state.collectingItem and state.supplyBaseline then
            local before = state.supplyBaseline
            local improved = (state.supplyKind == "food" and (stat(player, "HUNGER") < before.hunger
                    or player:getNutrition():getCalories() > before.calories))
                or (state.supplyKind == "water" and stat(player, "THIRST") < before.thirst)
                or (state.supplyKind == "literature" and stat(player, "BOREDOM") < before.boredom)
            if not improved then
                state.awaitSupplyUntil = state.awaitSupplyUntil or now + 2000
                if now < state.awaitSupplyUntil then return end
                failed = true
            end
        end
        state.pending, state.collectingItem = nil, nil
        if failed then
            state.failures = state.failures + 1
            if state.supplyItem then state.rejected[state.supplyItem:getID()] = true end
            if state.failures >= 3 then
                Controller.stop(player, "Actions were interrupted repeatedly. Resolve the disturbance or blocked supplies, then start again.")
                return
            end
        else state.failures = 0 end
        state.supplyItem, state.supplyKind = nil, nil
        state.supplyBaseline, state.awaitSupplyUntil = nil, nil
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
        message = "Checking supplies and training requirements.", rejected = {}, failures = 0, hoursWithoutXP = 0,
        observedGameHours = player:getHoursSurvived(), progressMeditation = player:getXp():getXP(Perks.Meditation),
        progressYogaLevel = yoga[1], progressYogaXP = yoga[2]}
    states[player] = state
    return true, state.message
end

function Controller.status(player)
    if not player then return {active = false, phase = "idle", message = "No local survivor.", meditation = 0, yoga = 0} end
    local state = stateFor(player)
    local meditation, yoga = levels(player)
    return {active = state.active, phase = state.phase, message = state.message, meditation = meditation, yoga = yoga,
        mode = state.mode, collectNearby = state.collectNearby}
end

function Controller.prepare(player, collectNearby)
    if not player then return {message = "No local survivor."} end
    return Supplies.report(player, collectNearby == true)
end

local function onPlayerUpdate(player)
    local state = states[player]
    if not state or not state.active then return end
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
