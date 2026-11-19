local ActionYield = {}

local function advanceAfterStop(timed, head)
    -- This is a cancellation, not a door/action retrigger or a successful
    -- perform. Stock onCompleted still validates and begins the actual next head.
    timed.current = nil
    timed:onCompleted(head)
end

function ActionYield.hasForeign(queue, owner)
    for _, action in ipairs(queue) do
        if action.autoMindfulOwner ~= owner then return true end
    end
    return false
end

-- Only needed if a stop callback starts unrelated native work after stock clear.
-- Don't start a foreign successor on top of that activity: native StartAction
-- wipes the character's current Java stack. Stock tick must not reap our stopped
-- Lua head as "bugged" while it waits. This hook belongs to this player only.
function ActionYield.finishHandoff(player)
    local timed = ISTimedActionQueue.getTimedActionQueue(player)
    local hold = timed.autoMindfulHandoff
    if not hold then return true end
    local unchanged = timed.queue[1] == hold.head and (not timed.current or timed.current == hold.head)
    if unchanged and not player:getCharacterActions():isEmpty() then return false end
    if timed.tick == hold.tick then timed.tick = hold.prior end
    timed.autoMindfulHandoff = nil
    if unchanged then advanceAfterStop(timed, hold.head) end
    return true
end

local function keepWaiters() end

function ActionYield.release(player, owner)
    local timed = ISTimedActionQueue.getTimedActionQueue(player)
    if not ActionYield.finishHandoff(player) then return false end
    local queue, head = timed.queue, timed.queue[1]
    for index = #queue, 2, -1 do
        local action = queue[index]
        if action.autoMindfulOwner == owner and not action:isStarted() then
            timed:removeFromQueue(action)
            action:forceCancel()
        end
    end
    if not head or head.autoMindfulOwner ~= owner then
        for _, action in ipairs(queue) do if action.autoMindfulOwner == owner then return false end end
        return true
    end
    local native = player:getCharacterActions()
    -- Never stop an unidentified native action, even if Lua still lists our old head.
    if timed.current ~= head or timed:isCurrentActionAddingOtherActions() or (not native:isEmpty() and
            (native:size() ~= 1 or not head.action or not native:contains(head.action))) then return false end
    -- Stock stop resets the Lua queue and then clears the Java stack. Suppress
    -- only this player's two bulk wipes for that synchronous call. The real
    -- queue stays visible, even to mods that append inside our stop callback.
    local reset, clear = rawget(timed, "resetQueue"), rawget(timed, "clearQueue")
    timed.resetQueue, timed.clearQueue = keepWaiters, keepWaiters
    local ok, reason = pcall(ISTimedActionQueue.clear, player)
    if timed.resetQueue == keepWaiters then timed.resetQueue = reset end
    if timed.clearQueue == keepWaiters then timed.clearQueue = clear end
    if not ok then error(reason) end
    if timed.queue[1] ~= head or (timed.current and timed.current ~= head) then return true end
    if not player:getCharacterActions():isEmpty() then
        local previous = timed.tick
        local hold = {head=head, prior=rawget(timed, "tick")}
        hold.tick = function(self)
            if ActionYield.finishHandoff(player) and previous then return previous(self) end
        end
        timed.autoMindfulHandoff, timed.tick = hold, hold.tick
        return false
    end
    advanceAfterStop(timed, head)
    return true
end

function ActionYield.nativeBusy(player)
    return ISTimedActionQueue.isPlayerDoingAction(player) or player:hasTimedActions()
end

function ActionYield.occupied(player, queue, owner)
    if ActionYield.hasForeign(queue, owner) then return true end
    if not queue[1] then return ActionYield.nativeBusy(player) end
    local native = player:getCharacterActions()
    return not native:isEmpty() and (native:size() ~= 1 or not queue[1].action or not native:contains(queue[1].action))
end

function ActionYield.rememberPosition(state, player)
    state.motionX, state.motionY, state.motionZ = player:getX(), player:getY(), player:getSquare():getZ()
end

function ActionYield.leftArea(state, player, ownWalk)
    local square = player:getSquare()
    if not square or not state.motionZ or state.motionZ ~= square:getZ() then return true end
    if ownWalk then
        ActionYield.rememberPosition(state, player)
        return false
    end
    local dx, dy = player:getX() - state.motionX, player:getY() - state.motionY
    return dx * dx + dy * dy > 1.5 * 1.5
end

return ActionYield
