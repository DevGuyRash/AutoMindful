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

-- A Java-initiated stop drains the native head after the Lua callback returns.
-- Don't start a foreign successor on top of that activity: native StartAction
-- wipes the character's current Java stack. Stock tick must not reap our stopped
-- Lua head as "bugged" while it waits. This hook belongs to this player only.
function ActionYield.finishHandoff(player)
    local timed = ISTimedActionQueue.getTimedActionQueue(player)
    local hold = timed.autoMindfulHandoff
    if not hold then return true end
    if hold.inStop then return false end
    local unchanged = timed.queue[1] == hold.head and (not timed.current or timed.current == hold.head)
    if unchanged and not player:getCharacterActions():isEmpty() then return false end
    if timed.tick == hold.tick then timed.tick = hold.prior end
    timed.autoMindfulHandoff = nil
    if unchanged then advanceAfterStop(timed, hold.head) end
    return true
end

local function keepWaiters() end

local function deferHandoff(player, timed, head)
    if timed.autoMindfulHandoff then return timed.autoMindfulHandoff end
    local previous = timed.tick
    local hold = {head=head, prior=rawget(timed, "tick")}
    hold.tick = function(self)
        if ActionYield.finishHandoff(player) and previous then return previous(self) end
    end
    timed.autoMindfulHandoff, timed.tick = hold, hold.tick
    return hold
end

local function preserveWaiters(timed, fn, ...)
    -- Protect this player's actual queue only while stock stop/reset is on
    -- the stack. Additions remain visible and explicit later clears still win.
    local reset, clear = rawget(timed, "resetQueue"), rawget(timed, "clearQueue")
    timed.resetQueue, timed.clearQueue = keepWaiters, keepWaiters
    local ok, result = pcall(fn, ...)
    if timed.resetQueue == keepWaiters then timed.resetQueue = reset end
    if timed.clearQueue == keepWaiters then timed.clearQueue = clear end
    return ok, result
end

local function removeOwnWaiters(timed, owner)
    local queue = timed.queue
    for index = #queue, 2, -1 do
        local action = queue[index]
        if action.autoMindfulOwner == owner and not action:isStarted() then
            timed:removeFromQueue(action)
            action:forceCancel()
        end
    end
end

function ActionYield.nativeAimStop(player, owner, head, original, ...)
    local timed = ISTimedActionQueue.getTimedActionQueue(player)
    if timed.current ~= head or timed.queue[1] ~= head or timed:isCurrentActionAddingOtherActions() then
        return original(head, ...)
    end
    -- Already in the native stop callback. Never recursively clear the Java
    -- stack, nor begin a successor that its still-unwinding clear would erase.
    local hold = deferHandoff(player, timed, head)
    hold.inStop = true
    local ok, result = preserveWaiters(timed, original, head, ...)
    hold.inStop = nil
    if timed.queue[1] == head and (not timed.current or timed.current == head) then removeOwnWaiters(timed, owner) end
    if not ok then error(result) end
    return result
end

function ActionYield.release(player, owner)
    local timed = ISTimedActionQueue.getTimedActionQueue(player)
    if not ActionYield.finishHandoff(player) then return false end
    local queue, head = timed.queue, timed.queue[1]
    removeOwnWaiters(timed, owner)
    if not head or head.autoMindfulOwner ~= owner then
        for _, action in ipairs(queue) do if action.autoMindfulOwner == owner then return false end end
        return true
    end
    local native = player:getCharacterActions()
    -- Never stop an unidentified native action, even if Lua still lists our old head.
    if timed.current ~= head or timed:isCurrentActionAddingOtherActions() or (not native:isEmpty() and
            (native:size() ~= 1 or not head.action or not native:contains(head.action))) then return false end
    local ok, reason = preserveWaiters(timed, ISTimedActionQueue.clear, player)
    if not ok then error(reason) end
    if timed.queue[1] ~= head or (timed.current and timed.current ~= head) then return true end
    if not player:getCharacterActions():isEmpty() then
        deferHandoff(player, timed, head)
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

local function visibleOptions(menu)
    return menu and menu.options and menu.options[1] ~= nil and menu:isVisible()
        and (not menu.isReallyVisible or menu:isReallyVisible())
end

function ActionYield.contextOpen(player)
    local menu = getPlayerContextMenu and getPlayerContextMenu(player:getPlayerNum())
    if visibleOptions(menu) then return true end
    -- In single-menu mode the root can be hidden while a submenu is open.
    if menu and menu.instanceMap and #menu.instanceMap > 0 and menu.isOptionSingleMenu and menu:isOptionSingleMenu() then
        for _, child in ipairs(menu.instanceMap) do
            if visibleOptions(child) then return true end
        end
    end
    return false
end

-- Stock map reading ends its timed action before the map closes. Paper maps
-- are nonmodal windows, unlike a true blocking dialog. Neither the minimap
-- nor an always-open inventory panel is evidence of a player taking over.
function ActionYield.inspecting(player, state, now)
    local index = player:getPlayerNum()
    local world = ISWorldMap_instance
    if world and world.playerNum == index and world:isVisible() then return true end
    local modal = UIManager and UIManager.getModal and UIManager.getModal()
    if modal and modal:isVisible() then
        local panel = modal.getTable and modal:getTable()
        if not panel or panel.playerNum == nil or panel.playerNum == index then return true end
    end
    if not UIManager or not UIManager.getUI then return false end
    if state.windowChecked and now >= state.windowChecked and now - state.windowChecked < 250 then
        return state.paperMapOpen
    end
    state.windowChecked, state.paperMapOpen = now, false
    local elements = UIManager.getUI()
    for i = 0, elements:size()-1 do
        local element = elements:get(i)
        local panel = element and element.getTable and element:getTable()
        if panel and panel.Type == "ISMapWrapper" and panel.mapUI and panel.mapUI.playerNum == index
                and not panel.isCollapsed and panel:isReallyVisible() then
            state.paperMapOpen = true
            break
        end
    end
    return state.paperMapOpen
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
