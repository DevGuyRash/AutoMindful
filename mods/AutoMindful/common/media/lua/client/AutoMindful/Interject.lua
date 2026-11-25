-- Looks after the survivor between somebody else's actions. A row of trees, a
-- crafting batch or another mod's loop can keep the queue busy for hours; a
-- helper that waits for it to be empty never helps. One bite or sip of what is
-- already carried goes between the running action and the next, through the
-- game's own "add after". Nothing is cancelled, replaced or reordered.
require "TimedActions/ISQueueActionsAction"
local Consumables = require "AutoMindful/Consumables"
local Danger = require "AutoMindful/Danger"
local Log = require "AutoMindful/Log"
local Needs = require "AutoMindful/SurvivalNeeds"
local Snap = require "AutoMindful/Snapshot"
local Supplies = require "AutoMindful/Supplies"

local Interject = {}
local retryMs, confirmMs, blockedRetryMs = 20000, 4000, 60000

local function stat(player, kind)
    return player:getStats():get(kind == "water" and CharacterStat.THIRST or CharacterStat.HUNGER)
end

-- Only what is on the survivor and ready: no walking, opening or pouring in
-- the middle of someone else's work.
function Interject.supply(player, kind, rejected)
    if kind == "food" and player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) >= 3 then return nil end
    local entry = Supplies.choose(player, kind, false, rejected)
    if not entry or entry.transfer or not entry.item or not entry.owned then return nil end
    if entry.description and (entry.description.needsOpening or entry.description.needsVessel) then return nil end
    return entry.item
end

local function due(player)
    for _, kind in ipairs({"water", "food"}) do if Needs.critical(player, kind) then return kind end end
    local worst, level
    for _, kind in ipairs({"water", "food"}) do
        local current = Needs.level(player, kind)
        if current >= 1 and (not level or current > level) then worst, level = kind, current end
    end
    return worst
end

-- The stock chooser, except that finding nothing to do must not reset the
-- queue it was put into.
local function chooser(player, rejected, kind, receipt)
    local action = ISQueueActionsAction:new(player, function()
        local item = Interject.supply(player, kind, rejected)
        if not item then return end
        receipt.item, receipt.before = item, stat(player, kind)
        Consumables.consume(player, item, kind)
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

local function settle(player, state, queue, now)
    local receipt = state.interject
    if not receipt then return false end
    for _, action in ipairs(queue) do if action == receipt.action then return true end end
    if receipt.queued == nil or not receipt.item then
        state.interject, state.interjectNext = nil, now + blockedRetryMs
        return false
    end
    receipt.leftAt = receipt.leftAt or now
    local value = stat(player, receipt.kind)
    local helped = value < receipt.before - Consumables.restoredThreshold
    if not helped and now - receipt.leftAt < confirmMs + 6000 then return true end
    Log.event(player, "interject.result", "kind", receipt.kind, "item", Snap.item(receipt.item), "before", receipt.before,
        "now", value, "helped", helped)
    if not helped then Supplies.rejectScoutIntake(state.rejected, receipt.item, receipt.kind, true) end
    state.interject = nil
    state.interjectNext = now + (helped and retryMs or blockedRetryMs)
    return false
end

-- queue[1] is foreign and running. Returns the kind when something was placed.
function Interject.consider(player, state, queue, now)
    if settle(player, state, queue, now) then return nil end
    if state.interjectNext and now < state.interjectNext and state.interjectNext - now <= blockedRetryMs then return nil end
    local head = queue[1]
    local timed = ISTimedActionQueue.getTimedActionQueue(player)
    if not head or head.autoMindfulOwner == state or not head.isStarted or not head:isStarted() or head.autoMindfulStopped
            or timed.current ~= head or timed:isCurrentActionAddingOtherActions() or timed.autoMindfulHandoff then return nil end
    local danger = Danger.read(player)
    if danger == "engaged" or player:isAiming() or player:isAttacking() or player:isDraggingCorpse() then return nil end
    local kind = due(player)
    if not kind then return nil end
    state.interjectNext = now + retryMs
    if not Interject.supply(player, kind, state.rejected) then
        Log.change(player, "interject.none", kind, "kind", kind, "level", Needs.level(player, kind), "behind", Snap.action(head))
        return nil
    end
    local receipt = {kind=kind}
    local action = chooser(player, state.rejected, kind, receipt)
    if not ISTimedActionQueue.addAfter(head, action) then return nil end
    receipt.action = action
    state.interject = receipt
    Log.event(player, "interject", "kind", kind, "level", Needs.level(player, kind), "behind", Snap.action(head), "ahead", #queue)
    return kind
end

return Interject
