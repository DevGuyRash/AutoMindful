-- Bounded, read-only discovery. Missing multiplayer contents are unknown, not
-- empty. Only native adjacent interaction may request or generate those contents.
local Consumables = require "AutoMindful/Consumables"
local Supplies = require "AutoMindful/Supplies"
local Fluids = require "AutoMindful/Fluids"
local Storage = require "AutoMindful/Storage"
local PainCare = require "AutoMindful/PainCare"
local ScoutMemory = require "AutoMindful/ScoutMemory"
local Nearby = {}
local snapshots = {}

local function key(square)
    return tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
end

local function permitted(player, square, loot)
    return not isClient() or (SafeHouse.isSafehouseAllowInteract(square, player)
        and (not loot or SafeHouse.isSafehouseAllowLoot(square, player)))
end

local function normalizedRadius(radius)
    radius = tonumber(radius) or 10
    if radius ~= radius then radius = 10 end
    return math.max(1, math.min(50, math.floor(radius)))
end

local function usableWater(object)
    if not object:hasWater() or object:getFluidAmount() <= 0 or object:isTaintedWater() then return false end
    local fluid = object:getFluidContainer()
    if fluid and not fluid:isEmpty() then
        return fluid:isPureFluid(Fluid.Water) and Fluids.inspect(fluid) ~= nil
    end
    return object:getPrimaryFluid() == Fluid.Water
end

-- Revalidate a radius-cache entry before handing its current object to stock pathfinding.
function Nearby.waterObject(player, target)
    local part = target.object
    if not part or part:getSquare() ~= target.square then return nil end
    local master = part:getMasterObject()
    local square = master and master:getSquare()
    local ground = instanceof(part, "IsoWorldInventoryObject")
    if not square or not permitted(player, target.square, ground) or not permitted(player, square, ground)
            or (instanceof(master, "IsoThumpable") and master:isLockedToCharacter(player))
            or (ground and (not part:getItem() or part:getItem():isSealed())) or not usableWater(master) then return nil end
    return master
end

function Nearby.invalidate(player)
    snapshots[player] = nil
end

function Nearby.scan(player, originSquare, radius, force)
    local result = {food = {}, water = {}, literature = {}, pain = {}, waterSources = {},
        unknownTargets = {}, containerCount = 0, unloadedSquares = 0, cooldownLiterature = 0, potentialBulk = 0}
    local here = player:getSquare()
    if not here or not originSquare or here:getZ() ~= originSquare:getZ() then return result end
    radius = normalizedRadius(radius)
    local now, originKey = getTimestampMs(), key(originSquare)
    result.radius, result.scannedAt = radius, now
    local cached = snapshots[player]
    if not force and cached and cached.originKey == originKey and cached.radius == radius
            and cached.client == isClient() and now >= cached.time and now - cached.time < 1000 then
        return cached.result
    end
    local seenContainers, seenItems, seenWater, seenVehicles = {}, {}, {}, {}
    local function visitItem(item, square, container, part, scopedKey, storageScoped)
        if not item or seenItems[item] then return end
        seenItems[item] = true
        local entry = {square=square,key=scopedKey or key(square),item=item,container=container,
            owned=false,part=part,storageScoped=storageScoped}
        if PainCare.eligible(item) then
            result.pain[#result.pain + 1] = entry
            return
        end
        local description = Consumables.inspect(player, item, false)
        entry.description = description
        if description.needsVessel and (description.food or description.water) then
            result.potentialBulk = result.potentialBulk + 1
        end
        if description.food then result.food[#result.food + 1] = entry end
        if description.water then result.water[#result.water + 1] = entry end
        local reading, last = Supplies.literatureInfo(player, item)
        if reading == "cooldown" then result.cooldownLiterature = result.cooldownLiterature + 1
        elseif reading then
            entry.lastRead = last
            result.literature[#result.literature + 1] = entry
        end
    end
    local function visitContainer(container, square, part)
        if not container or seenContainers[container] then return end
        seenContainers[container] = true
        result.containerCount = result.containerCount + 1
        local suffix=not part and ScoutMemory.storageSuffix(container,square) or nil
        local scopedKey=key(square)..(suffix or (part and ":vehicle:"..tostring(part:getVehicle():getId())..":"..tostring(part:getIndex()) or ""))
        local items = container:getItems()
        -- isExplored can become true before the MP server sends its contents.
        -- An empty replicated list never establishes confirmed emptiness here.
        if not container:isExplored() or (isClient() and items:size() == 0) then
            result.unknownTargets[#result.unknownTargets + 1] = {
                square=square,key=scopedKey,container=container,unknown=true,part=part,storageScoped=suffix~=nil}
        end
        for index=0,items:size()-1 do visitItem(items:get(index),square,container,part,scopedKey,suffix~=nil) end
    end
    local function visitObjects(objects, square, ground)
        local loot = permitted(player, square, true)
        for index = 0, objects:size() - 1 do
            local object = objects:get(index)
            local locked = instanceof(object, "IsoThumpable") and object:isLockedToCharacter(player)
            if not locked then
                local item = ground and object:getItem() or nil
                local master = object.getMasterObject and object:getMasterObject() or object
                if (not ground or loot) and not seenWater[master] and usableWater(object)
                        and (not item or not item:isSealed()) then
                    seenWater[master] = true
                    result.waterSources[#result.waterSources + 1] = {
                        square = square, key = key(square), object = object, source = object, item = item}
                end
                if loot then
                    if ground then
                        visitItem(item, square, nil)
                        -- Match native ground-bag access, without recursively
                        -- inventing access to every bag inside another bag.
                        if item and instanceof(item, "InventoryContainer") then
                            visitContainer(item:getInventory(), square)
                        end
                    else
                        for ci = 0, object:getContainerCount() - 1 do
                            visitContainer(object:getContainerByIndex(ci), square)
                        end
                    end
                end
            end
        end
    end
    local ox, oy, z = originSquare:getX(), originSquare:getY(), originSquare:getZ()
    local cell = getCell()
    for x = ox - radius, ox + radius do
        for y = oy - radius, oy + radius do
            local dx, dy = x - ox, y - oy
            if dx * dx + dy * dy <= radius * radius then
                local square = cell:getGridSquare(x, y, z)
                if not square then result.unloadedSquares = result.unloadedSquares + 1
                elseif permitted(player, square, false) then
                    visitObjects(square:getObjects(), square, false)
                    visitObjects(square:getWorldObjects(), square, true)
                    if permitted(player, square, true) and square.getStaticMovingObjects then
                        local bodies = square:getStaticMovingObjects()
                        for index = 0, bodies:size() - 1 do
                            local body = bodies:get(index)
                            if Storage.safeCorpse(body) then visitContainer(body:getContainer(), square) end
                        end
                    end
                    local vehicle = square.getVehicleContainer and square:getVehicleContainer()
                    if vehicle and not seenVehicles[vehicle] then
                        seenVehicles[vehicle] = true
                        for index = 0, vehicle:getPartCount() - 1 do
                            local part = vehicle:getPartByIndex(index)
                            local eligible, area = Storage.vehiclePart(part)
                            if eligible and area:getZ() == z and Storage.permitted(player, area)
                                    and Storage.permitted(player, vehicle:getSquare()) then
                                local ax, ay = area:getX() - ox, area:getY() - oy
                                if ax * ax + ay * ay <= radius * radius then
                                    visitContainer(part:getItemContainer(), area, part)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    snapshots[player] = {originKey = originKey, radius = radius, client = isClient(), time = now, result = result}
    return result
end

function Nearby.find(player, kind, originSquare, radius, rejectedTargets, onlyWorldWater)
    if kind ~= "food" and kind ~= "water" and kind ~= "literature" and kind ~= "pain" then return nil end
    local here = player:getSquare()
    if not here or not originSquare or here:getZ() ~= originSquare:getZ() then return nil end
    local snapshot = Nearby.scan(player, originSquare, radius)
    rejectedTargets = rejectedTargets or {}
    local function choose(entries, allowAdjacent, best)
        for _, entry in ipairs(entries) do
            local square = entry.square
            local dx, dy = square:getX() - here:getX(), square:getY() - here:getY()
            local targetKey = (entry.unknown and "unknown:" or kind .. ":") .. entry.key
            local rejection = rejectedTargets[targetKey]
            if type(rejection) == "number" and getTimestampMs() >= rejection then
                rejectedTargets[targetKey], rejection = nil, nil
            end
            if not rejection and (allowAdjacent or (entry.part and not Storage.vehicleAccessible(player, entry.part))
                    or math.abs(dx) > 1 or math.abs(dy) > 1) then
                local distance = dx * dx + dy * dy
                if not best or distance < best.distance or (distance == best.distance and (targetKey < best.key
                        or (targetKey == best.key and entry.object and entry.item and entry.item == best.item and not best.object))) then
                    -- Do not mutate the shared snapshot while choosing targets.
                    best = {square = square, key = targetKey, distance = distance,
                        unknown = entry.unknown, container = entry.container, storageScoped = entry.storageScoped,
                        item = entry.item, object = entry.object, part = entry.part}
                end
            end
        end
        return best
    end
    local best = not onlyWorldWater and choose(snapshot[kind], false) or nil
    if kind == "water" then best = choose(snapshot.waterSources, false, best) end
    if best then return best end
    -- Pain care only scouts known medicine; never rummage blind for a dose.
    if kind ~= "pain" and not onlyWorldWater then return choose(snapshot.unknownTargets, true) end
end

return Nearby
