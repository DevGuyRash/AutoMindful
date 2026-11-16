-- Discovery only. Native walking and the ordinary adjacent supply checks remain
-- responsible for access, collection, and use after reaching a candidate.
local Consumables = require "AutoMindful/Consumables"
local Supplies = require "AutoMindful/Supplies"
local Fluids = require "AutoMindful/Fluids"
local Nearby = {}

local function key(square)
    return tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
end

local function permitted(player, square, loot)
    return not isClient() or (SafeHouse.isSafehouseAllowInteract(square, player)
        and (not loot or SafeHouse.isSafehouseAllowLoot(square, player)))
end

local function eligibleItem(player, item, kind)
    if kind == "literature" then return Supplies.eligibleLiterature(player, item) end
    local description = Consumables.inspect(player, item, false)
    -- Opening tools and vessels may be different at the destination. Do not
    -- assume inaccessible tools or consume a remote item while discovering it.
    return description[kind] == true
end

local function usableWater(object)
    if not object:hasWater() or object:getFluidAmount() <= 0 or object:isTaintedWater() then return false end
    local fluid = object:getFluidContainer()
    if fluid and not fluid:isEmpty() then
        return fluid:isPureFluid(Fluid.Water) and Fluids.inspect(fluid) ~= nil
    end
    return object:getPrimaryFluid() == Fluid.Water
end

local function hasSupply(player, square, kind, onlyWorldWater)
    local loot = permitted(player, square, true)
    local function visit(objects, ground)
        for index = 0, objects:size() - 1 do
            local object = objects:get(index)
            local locked = instanceof(object, "IsoThumpable") and object:isLockedToCharacter(player)
            if not locked then
                if kind == "water" and (not ground or loot) and usableWater(object) then
                    local item = ground and object:getItem() or nil
                    if not item or not item:isSealed() then return true end
                end
                if loot and not onlyWorldWater then
                    if ground then
                        local item = object:getItem()
                        if item and eligibleItem(player, item, kind) then return true end
                    else
                        for containerIndex = 0, object:getContainerCount() - 1 do
                            local container = object:getContainerByIndex(containerIndex)
                            local items = container and container:getItems()
                            if items then
                                for itemIndex = 0, items:size() - 1 do
                                    if eligibleItem(player, items:get(itemIndex), kind) then return true end
                                end
                            end
                        end
                    end
                end
            end
        end
        return false
    end
    return visit(square:getObjects(), false) or visit(square:getWorldObjects(), true)
end

function Nearby.find(player, kind, originSquare, radius, rejectedTargets, onlyWorldWater)
    if kind ~= "food" and kind ~= "water" and kind ~= "literature" then return nil end
    local here = player:getSquare()
    if not here or not originSquare or here:getZ() ~= originSquare:getZ() then return nil end
    radius = tonumber(radius) or 10
    if radius ~= radius then radius = 10 end
    radius = math.max(1, math.min(50, math.floor(radius)))
    rejectedTargets = rejectedTargets or {}
    local candidates = {}
    local ox, oy, z = originSquare:getX(), originSquare:getY(), originSquare:getZ()
    for x = ox - radius, ox + radius do
        for y = oy - radius, oy + radius do
            local dx, dy = x - ox, y - oy
            if dx * dx + dy * dy <= radius * radius
                    and (math.abs(x - here:getX()) > 1 or math.abs(y - here:getY()) > 1) then
                local square = getCell():getGridSquare(x, y, z)
                if square and permitted(player, square, false) then
                    local id = key(square)
                    local rejected = rejectedTargets[id]
                    if type(rejected) == "number" and getTimestampMs() >= rejected then
                        rejectedTargets[id], rejected = nil, nil
                    end
                    if not rejected then
                        candidates[#candidates + 1] = {square = square, key = id,
                            distance = (x - here:getX()) ^ 2 + (y - here:getY()) ^ 2}
                    end
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.key < b.key
    end)
    for _, candidate in ipairs(candidates) do
        if hasSupply(player, candidate.square, kind, onlyWorldWater) then return candidate end
    end
end

return Nearby
