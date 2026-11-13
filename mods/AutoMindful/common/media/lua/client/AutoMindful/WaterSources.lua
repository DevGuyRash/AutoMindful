require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISTakeWaterAction"
require "TimedActions/ISWaitWhileGettingUp"
require "TimedActions/ISWearClothing"
local Fluids = require "AutoMindful/Fluids"

AutoMindful = AutoMindful or {}
local WaterSources = {}
AutoMindful.WaterSources = WaterSources

local function reachable(player, object)
    local here, square = player:getSquare(), object:getSquare()
    if not here or not square then return false end
    square = luautils.getCorrectSquareForWall(player, square)
    return square and square:getZ() == here:getZ()
        and math.abs(square:getX() - here:getX()) <= 1
        and math.abs(square:getY() - here:getY()) <= 1
        and (square == here or here:canReachTo(square))
end

function WaterSources.inspect(player, object, part)
    part = part or object
    if part:getMasterObject() ~= object or not reachable(player, part) then return nil end
    local square = object:getSquare()
    if not square then return nil end
    local ground = instanceof(object, "IsoWorldInventoryObject")
    if isClient() and (not SafeHouse.isSafehouseAllowInteract(square, player)
            or (ground and not SafeHouse.isSafehouseAllowLoot(square, player))) then return nil end
    if instanceof(object, "IsoThumpable") and object:isLockedToCharacter(player) then return nil end
    if object:getFluidAmount() <= 0 or object:isTaintedWater() then return nil end
    local item = ground and object:getItem() or nil
    if item and item:isSealed() then
        return nil, "A nearby fluid container is sealed. Open it before using it as a supply."
    end
    local fluid = object:getFluidContainer()
    local description, direct
    if fluid and not fluid:isEmpty() then
        local reason
        description, reason = Fluids.inspect(fluid)
        if not description then return nil, reason end
        direct = fluid:isPureFluid(Fluid.Water) and object:hasWater()
        if not direct then
            if not fluid:canPlayerEmpty() then return nil, "A nearby fluid supply cannot currently be opened or poured." end
            if item and Fluids.drinkable(item, fluid) then return nil end
            if not description.food and not description.water then return nil end
            description.needsVessel = true
        end
    else
        if not object:hasWater() or object:getPrimaryFluid() ~= Fluid.Water then return nil end
        direct = true
    end
    local remaining = object:getFluidAmount()
    if direct then
        description = {fluid = fluid, remainingLiters = remaining, hungerEffect = 0, thirstEffect = remaining / 2,
            hungerRelief = 0, thirstRelief = remaining / 2, food = false, water = true, calories = 0}
    end
    return {object = object, part = part, item = item, square = square, remainingLiters = remaining,
        description = description, directDrink = direct}
end

function WaterSources.scan(player)
    local result, seen = {}, {}
    local here = player:getSquare()
    if not here then return result end
    local function visit(objects)
        for index = 0, objects:size() - 1 do
            local part = objects:get(index)
            local object = part:getMasterObject()
            if object and not seen[object] then
                local source, reason = WaterSources.inspect(player, object, part)
                if source then result[#result + 1] = source; seen[object] = true end
                result.reason = result.reason or reason
            end
        end
    end
    for x = here:getX() - 1, here:getX() + 1 do
        for y = here:getY() - 1, here:getY() + 1 do
            local square = getCell():getGridSquare(x, y, here:getZ())
            if square then
                visit(square:getObjects())
                visit(square:getWorldObjects())
            end
        end
    end
    return result
end

function WaterSources.choose(player, rejected)
    local best
    for _, source in ipairs(WaterSources.scan(player)) do
        local rejection = rejected[source.object]
        if type(rejection) == "number" and getTimestampMs() >= rejection then
            rejected[source.object] = nil
            rejection = nil
        end
        if source.directDrink and not rejection and (not best or source.remainingLiters > best.remainingLiters) then best = source end
    end
    return best
end

function WaterSources.drink(player, source)
    local current, reason = WaterSources.inspect(player, source.object, source.part)
    if not current then return false, reason or "The nearby water source is empty, unsafe, or no longer reachable." end
    if not current.directDrink then return false, "Transfer this nearby fluid supply into a drinking vessel first." end
    local action = ISTakeWaterAction:new(player, nil, current.object, false)
    if not action:isValid() then return false, "The game currently refuses drinking from this water source. Make room in your inventory." end
    local originalValid = action.isValid
    action.isValid = function(self)
        local live = WaterSources.inspect(self.character, self.waterObject, source.part)
        return live ~= nil and live.directDrink and originalValid(self)
    end
    if player:isSitOnGround() then ISTimedActionQueue.add(ISWaitWhileGettingUp:new(player)) end
    local mask = ISInventoryPaneContextMenu.getEatingMask(player, true)
    ISTimedActionQueue.add(action)
    if mask then ISTimedActionQueue.add(ISWearClothing:new(player, mask, 50)) end
    return true
end

return WaterSources
