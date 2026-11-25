-- Looks after the survivor between somebody else's actions. A row of trees, a
-- crafting batch or another mod's loop can keep the queue busy for hours; a
-- helper that waits for it to be empty never helps. One bite or sip of what is
-- already carried goes between the running action and the next, through the
-- game's own "add after". Nothing is cancelled, replaced or reordered.
require "TimedActions/ISQueueActionsAction"
local Yield = require "AutoMindful/ActionYield"
local Consumables = require "AutoMindful/Consumables"
local Danger = require "AutoMindful/Danger"
local Log = require "AutoMindful/Log"
local Needs = require "AutoMindful/SurvivalNeeds"
local Snap = require "AutoMindful/Snapshot"
local Supplies = require "AutoMindful/Supplies"

local Interject = {}
local retryMs, confirmMs, blockedRetryMs, tries = 20000, 10000, 60000, 6

local function stat(player, kind)
    return player:getStats():get(kind == "water" and CharacterStat.THIRST or CharacterStat.HUNGER)
end

-- Only what is on the survivor and ready: no walking, opening or pouring in
-- the middle of someone else's work. The best supply may not be ready; the next
-- one may be.
function Interject.supply(player, kind, rejected)
    if kind == "food" and player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) >= 3 then return nil end
    local skipped = {}
    for key, value in pairs(rejected) do skipped[key] = value end
    for _ = 1, tries do
        local entry = Supplies.choose(player, kind, false, skipped)
        local item = entry and entry.item
        if not item then return nil end
        local d = entry.description
        if entry.owned and not entry.transfer and not (d and (d.needsOpening or d.needsVessel)) then return item end
        if entry.transfer and entry.transfer.source.item then skipped[entry.transfer.source.item:getID()] = getTimestampMs() + 1000 end
        skipped[item:getID()] = getTimestampMs() + 1000
    end
end

-- Most pressing first. One that cannot be met must not hide one that can.
local function due(player)
    local kinds = {}
    for _, kind in ipairs({"water", "food"}) do if Needs.level(player, kind) >= 1 then kinds[#kinds + 1] = kind end end
    if #kinds == 2 and Needs.level(player, "food") > Needs.level(player, "water") then kinds = {"food", "water"} end
    return kinds
end

local function allowed(player, state)
    return state.active and state.recovery and Danger.read(player) ~= "engaged" and not player:isAiming()
        and not player:isAttacking() and not player:isDraggingCorpse()
end

-- A stopped action resets the whole stock queue. That is right when the player
-- asked for it and wrong when a bite could not be finished.
local function protect(action, player, receipt)
    action.autoMindfulOwner = receipt
    local begin, validStart, stop = action.begin, action.isValidStart, action.stop
    action.isValidStart = function() return true end
    action.begin = function(self, ...)
        if validStart(self) then return begin(self, ...) end
        self.autoMindfulStopped = true
        local timed = ISTimedActionQueue.getTimedActionQueue(self.character)
        if timed.current == self and timed.queue[1] == self then timed:onCompleted(self) end
    end
    action.stop = function(self, ...)
        self.autoMindfulStopped = true
        if player:pressedMovement(false) or player:pressedCancelAction() or player:isAiming() then return stop(self, ...) end
        return Yield.nativeStop(player, receipt, self, stop, ...)
    end
end

-- The stock chooser, except that finding nothing to do must not reset the
-- queue it was put into.
local function chooser(player, state, kind, receipt)
    local timed = ISTimedActionQueue.getTimedActionQueue(player)
    local action = ISQueueActionsAction:new(player, function()
        if state.interject ~= receipt or not allowed(player, state) or Needs.level(player, kind) < 1 then return end
        local item = Interject.supply(player, kind, state.rejected)
        if not item then return end
        local before = {}
        for _, queued in ipairs(timed.queue) do before[queued] = true end
        receipt.item, receipt.before = item, stat(player, kind)
        Consumables.consume(player, item, kind)
        for _, queued in ipairs(timed.queue) do
            if not before[queued] then protect(queued, player, receipt); receipt.actions[#receipt.actions + 1] = queued end
        end
    end)
    action.autoMindfulInterject = true
    function action:start()
        self:beginAddingActions()
        local ok, message = pcall(self.addActionsFunction, self.character)
        local added = self:endAddingActions()
        receipt.queued = ok and added
        if not ok then Log.error(self.character, "Interject", message) end
        self:forceComplete()
    end
    return action
end

function Interject.settle(player, state, queue, now)
    local receipt = state.interject
    if not receipt then return false end
    for _, action in ipairs(queue) do
        if action == receipt.action or action.autoMindfulOwner == receipt then return true end
    end
    if not receipt.queued or not receipt.item then
        state.interject, state.interjectNext = nil, now + blockedRetryMs
        return false
    end
    receipt.leftAt = receipt.leftAt or now
    local value = stat(player, receipt.kind)
    local helped = value < receipt.before - Consumables.restoredThreshold
    if not helped and now >= receipt.leftAt and now - receipt.leftAt < confirmMs then return true end
    Log.event(player, "interject.result", "kind", receipt.kind, "item", Snap.item(receipt.item), "before", receipt.before,
        "now", value, "helped", helped)
    local interrupted = false
    for _, action in ipairs(receipt.actions) do if action.autoMindfulStopped then interrupted = true end end
    if not helped and not interrupted then Supplies.rejectScoutIntake(state.rejected, receipt.item, receipt.kind, true) end
    state.interject = nil
    state.interjectNext = now + (helped and retryMs or blockedRetryMs)
    return false
end

-- queue[1] is foreign and running. Returns the kind when something was placed.
function Interject.consider(player, state, queue, now)
    if Interject.settle(player, state, queue, now) then return nil end
    if state.interjectNext and now < state.interjectNext and state.interjectNext - now <= blockedRetryMs then return nil end
    local head = queue[1]
    local timed = ISTimedActionQueue.getTimedActionQueue(player)
    if not head or head.autoMindfulOwner == state or not head.isStarted or not head:isStarted() or head.autoMindfulStopped
            or timed.current ~= head or timed:isCurrentActionAddingOtherActions() or timed.autoMindfulHandoff then return nil end
    if not allowed(player, state) then return nil end
    local kinds = due(player)
    if #kinds == 0 then return nil end
    state.interjectNext = now + retryMs
    -- Taking a mask off and putting it back on is too much in between.
    if ISInventoryPaneContextMenu.getEatingMask(player, false) then return nil end
    local kind
    for _, candidate in ipairs(kinds) do
        if not kind and Interject.supply(player, candidate, state.rejected) then kind = candidate end
    end
    if not kind then
        Log.change(player, "interject.none", table.concat(kinds), "needs", table.concat(kinds, " "), "behind", Snap.action(head))
        return nil
    end
    local receipt = {kind=kind, actions={}}
    local action = chooser(player, state, kind, receipt)
    if not ISTimedActionQueue.addAfter(head, action) then return nil end
    receipt.action = action
    state.interject = receipt
    Log.event(player, "interject", "kind", kind, "level", Needs.level(player, kind), "behind", Snap.action(head), "ahead", #queue)
    return kind
end

return Interject
