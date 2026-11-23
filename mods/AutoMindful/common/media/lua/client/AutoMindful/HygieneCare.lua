-- Optional Lifestyle 0.4.0.3 / PZ 42.22 adapter. Read the real moodles.
-- The only effectful operations are normal player timed actions.
local Care = {}

local function finite(v, high)
    return type(v) == "number" and v >= 0 and v < math.huge and (not high or v <= high)
end

local function readNeed(player)
    if not (SandboxVars and SandboxVars.Text and SandboxVars.Text.DividerHygiene == true) then return nil end
    local data = player:getModData()
    local moods = data and data.LSMoodles
    local bad, scent, raw = moods and moods.HygieneBad, moods and moods.SmellGood, data and data.hygieneNeed
    if not bad or not finite(bad.Value, 1) or not finite(raw, 100) then return nil end
    if scent and not finite(scent.Value, 1) then return nil end
    local unmasked = (raw > 90 and 4) or (raw > 80 and 3) or (raw > 70 and 2) or (raw > 60 and 1) or 0
    local predicted = (scent and scent.Value > 0) and math.max(0, unmasked - 2) or unmasked
    return {raw=raw, scent=scent and scent.Value, bad=bad.Value, unmasked=unmasked,
        -- Don't act ahead of the user's moodle or on last minute's stale moodle.
        level=math.min(predicted, math.floor(bad.Value * 5 + 0.5))}
end

function Care.need(player)
    local ok, state = pcall(readNeed, player)
    return ok and state and state.level or 0
end

local function fragranceDelta()
    local delta = PerfumeContextMenu and PerfumeContextMenu.UseDelta
    return finite(delta) and delta > 0 and delta or nil
end

local function fluidDose(item)
    local fc = item:getFluidContainer()
    if not fc then return nil end
    local f = fc:getPrimaryFluid()
    local name = f and f:getFluidTypeString()
    if type(name) ~= "string" or (name:sub(1,7) ~= "Perfume" and name:sub(1,7) ~= "Cologne") then return nil end
    local amount = fc:getAmount()
    return finite(amount) and amount or nil
end

local function fragranceWouldHelp(state)
    return state and state.level > 0 and state.scent == 0
        and math.max(0, state.unmasked - 2) < state.level
end

function Care.searchItems(player)
    local ok, state = pcall(readNeed, player)
    return ok and fragranceWouldHelp(state) == true
end

local function usableItem(player, item)
    if not fragranceWouldHelp(readNeed(player)) or not item then return false end
    -- Match BOTH the upstream inventory dispatcher and its primary-fluid gate.
    -- Otherwise an empty cologne bottle or fragrance poured into a random bottle qualifies incorrectly.
    local t = item:getFullType()
    if type(t) ~= "string" or (not t:find("Perfume", 1, true) and not t:find("Cologne", 1, true)) then return false end
    if item:isSealed() then return false end
    local amount, delta = fluidDose(item), fragranceDelta()
    return amount ~= nil and delta ~= nil and amount >= delta
end

function Care.item(player, item)
    local ok, value = pcall(usableItem, player, item)
    return ok and value == true
end

local function dirtyParts(player)
    local n = ISWashYourself.GetRequiredWater(player)
    return finite(n) and n == math.floor(n) and n or nil
end

-- Capture *before* handing the job to the native queue. Supply item when known.
function Care.snapshot(player, item)
    local ok, s = pcall(readNeed, player)
    if not ok or not s then return nil end
    local valid, parts = pcall(dirtyParts, player)
    if valid then s.parts = parts end
    if item then
        valid, s.amount = pcall(function() return item:getFluidContainer():getAmount() end)
        if not valid or not finite(s.amount) then s.amount = nil end
        s.item, s.dose = item, fragranceDelta()
    end
    return s
end

local function permitted(player, square, ground)
    return not isClient() or (SafeHouse.isSafehouseAllowInteract(square, player)
        and (not ground or SafeHouse.isSafehouseAllowLoot(square, player)))
end

local function appliance(object)
    return instanceof(object, "IsoClothingWasher") or instanceof(object, "IsoClothingDryer")
        or instanceof(object, "IsoCombinationWasherDryer") or instanceof(object, "IsoStackedWasherDryer")
end

local function loadedSquare(square)
    return square and getCell():getGridSquare(square:getX(), square:getY(), square:getZ()) == square
end

-- Cheap scout first; no UI callbacks, square loading, item acquisition, or navigation.
-- Only offer the actual source object, not a sprite-name match or a detached/stale proxy.
local function inspect(player, object)
    if not object or not object:hasFluid() or not object:hasWater() then return nil end
    local amount = object:getFluidAmount()
    if not finite(amount) or amount < 1 or appliance(object) then return nil end
    local square, here = object:getSquare(), player:getSquare()
    if not here or not square or here:getZ() ~= square:getZ() or not loadedSquare(square) then return nil end
    local ground = instanceof(object, "IsoWorldInventoryObject")
    if not permitted(player, square, ground) then return nil end
    local objects = ground and square:getWorldObjects() or square:getObjects()
    -- getObjectIndex() alone cannot distinguish the exact item that replaced a stale target.
    if not objects:contains(object) then return nil end
    if instanceof(object, "IsoThumpable") and object:isLockedToCharacter(player) then return nil end
    if instanceof(object, "IsoFeedingTrough") and object:getMasterTrough() ~= object then return nil end
    if ground then
        local item = object:getItem()
        if not item or item:isSealed() then return nil end
    end
    if object:hasComponent(ComponentType.FluidContainer) then
        -- Java doFluidContainerMenu excludes ground entities; checks canPlayerEmpty
        -- before offering wash. Ordinary sinks, lakes, etc. also have a separate menu path.
        if ground then return nil end
        local fc = object:getFluidContainer()
        if not fc or not fc:canPlayerEmpty() then return nil end
    else
        -- Vanilla suppresses this (non-component) branch if a dryer is in the clicked tile.
        local siblings = square:getObjects()
        for i=0,siblings:size()-1 do
            if instanceof(siblings:get(i), "IsoClothingDryer") then return nil end
        end
    end
    if Care.need(player) == 0 or (dirtyParts(player) or 0) < 1 then return nil end
    return {object=object, square=square}
end

function Care.inspect(player, object)
    local ok, result = pcall(inspect, player, object)
    return ok and result or nil
end

local function original(entry)
    if type(entry) ~= "table" then return nil end
    if type(entry.care) == "table" then
        if (entry.object and entry.object ~= entry.care.object) or (entry.square and entry.square ~= entry.care.square) then return nil end
        return entry.care
    end
    return entry
end

-- Recheck a remote scout before routing; the same square is not the same source.
function Care.validTarget(player, entry)
    local old = original(entry)
    local now = old and Care.inspect(player, old.object)
    return now ~= nil and now.square == old.square
end

-- Restrictions that are relative to the character are evaluated at the interaction spot,
-- not at the origin of a legitimate trip to a different building. Never wash through a wall.
function Care.accessible(player, entry)
    local e = original(entry)
    if not e or not Care.validTarget(player, e) then return false end
    local ok, yes = pcall(function()
        local here = player:getSquare()
        if not loadedSquare(here) or not permitted(player, here, false)
                or player:getBuilding() ~= e.square:getBuilding() then return false end
        local sq = luautils.getCorrectSquareForWall(player, e.square)
        return sq and loadedSquare(sq) and here:getZ() == sq:getZ() and permitted(player, sq, false)
            and math.abs(sq:getX() + 0.5 - player:getX()) <= 1.6
            and math.abs(sq:getY() + 0.5 - player:getY()) <= 1.6
            and here:canReachTo(sq)
    end)
    return ok and yes == true
end

-- The native classes return true unconditionally from isValid. Narrow *this instance's*
-- local admission; leave the stock server complete(), cost and replication entirely intact.
local function guard(action, check)
    if not action then return false end
    local valid, start = action.isValid, action.isValidStart
    action.isValid = function(self) return check() and valid(self) end
    action.isValidStart = function(self) return check() and (not start or start(self)) end
    return action:isValid()
end

function Care.queueItem(player, item, before)
    local function allow()
        if not Care.item(player, item) then return false end
        local inv = player:getInventory()
        return item:getContainer() == inv and inv:contains(item)
    end
    local ok, queued = pcall(function()
        if not allow() then return false end
        local cls = LSApplyPerfumeAction or require "TimedActions/LSApplyPerfumeAction"
        local action = cls:new(player, item, fragranceDelta())
        if not guard(action, allow) then return false end
        if before then before.item, before.amount, before.dose = item, fluidDose(item), fragranceDelta() end
        ISTimedActionQueue.add(action)
        return true
    end)
    return ok and queued == true
end

function Care.queueWash(player, entry)
    local e = original(entry)
    local function allow() return e and Care.accessible(player, e) end
    local ok, queued = pcall(function()
        if not allow() then return false end
        local action = ISWashYourself:new(player, e.object)
        if not guard(action, allow) then return false end
        -- addGetUpOption uses the stock get-up action. No deferred callback which could
        -- outlive the scout ownership; both actions are visible to the controller now.
        if player:isSitting() then ISTimedActionQueue.add(ISWaitWhileGettingUp:new(player)) end
        ISTimedActionQueue.add(action)
        return true
    end)
    return ok and queued == true
end

-- Fewer dirty body parts is independent of the mod's *later* passive hygiene recovery.
-- Empty queue, elapsed time, a moved bottle and fewer water units are not wash receipts.
function Care.receipt(player, before, kind)
    if type(before) ~= "table" then return false end
    if kind == "wash" or kind == "hygieneWash" then
        local ok, parts = pcall(dirtyParts, player)
        return ok and finite(parts) and finite(before.parts) and parts < before.parts
    end
    if kind ~= "item" and kind ~= "hygieneItem" then return false end
    local ok, after = pcall(readNeed, player)
    if not ok or not after or before.scent ~= 0 or not finite(before.level) or before.level < 1
            or not finite(after.scent) or after.scent <= 0 or math.max(0, after.unmasked - 2) >= before.level then return false end
    if not before.item then return true end -- scent activation itself is a native observable effect
    local read, amount = pcall(function() return before.item:getFluidContainer():getAmount() end)
    return read and finite(amount) and finite(before.amount) and finite(before.dose)
        and before.amount - amount + 0.000001 >= before.dose
end

return Care
