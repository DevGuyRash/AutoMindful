-- Shared storage access checks. Never opens doors, enters vehicles or wakes bodies.
local Storage = {}

function Storage.permitted(player, square)
    return square and (not isClient() or (SafeHouse.isSafehouseAllowInteract(square, player)
        and SafeHouse.isSafehouseAllowLoot(square, player)))
end

function Storage.safeCorpse(body)
    return instanceof(body, "IsoDeadBody") and not body:isAnimal()
        and not body:isFakeDead() and body:getReanimateTime() < 0
end

local function outerContainer(container)
    return container.getOutermostContainer and container:getOutermostContainer() or container
end

function Storage.partFor(container)
    local outer = outerContainer(container)
    return outer.getVehiclePart and outer:getVehiclePart()
end

function Storage.corpseFor(container)
    container = outerContainer(container)
    local parent = container.getParent and container:getParent()
    return parent and instanceof(parent, "IsoDeadBody") and parent or nil
end

local function closed(doorPart, requireInstalled)
    return doorPart and doorPart:getDoor() and (not requireInstalled or doorPart:getInventoryItem())
        and not doorPart:getDoor():isOpen()
end

-- Container luaTest metadata is not exposed to Lua. Limit remote discovery to
-- standard storage layouts; native canAccessContainer is authoritative on arrival.
function Storage.vehiclePart(part)
    if not part or not part:getItemContainer() then return nil end
    local vehicle = part:getVehicle()
    if not vehicle or vehicle:getCurrentAbsoluteSpeedKmHour() > 0.1 or not part:getArea() then return nil end
    local id = part:getId()
    if part:isInventoryItemUninstalled() and part:getContainerCapacity() <= 0 then return nil end
    if id == "TruckBed" then
        local door = vehicle:getPartById("TrunkDoor") or vehicle:getPartById("DoorRear")
            or vehicle:getPartById("TrunkDoorOpened")
        if closed(door, true) then return nil end
    elseif id == "TruckBedOpen" or id == "TrailerTrunk" then
        -- Native open-bed storage has no access door.
    elseif id == "GloveBox" then
        if closed(vehicle:getPartById("DoorFrontRight"), false) then return nil end
    elseif id == "SeatFrontLeft" or id == "SeatFrontRight" or id == "SeatMiddleLeft"
            or id == "SeatMiddleRight" or id == "SeatRearLeft" or id == "SeatRearRight" then
        local seat = part:getContainerSeatNumber()
        if seat < 0 or not part:getInventoryItem() then return nil end
        local door = vehicle:getPassengerDoor(seat)
        if closed(door, true) or (not door and vehicle:getPartById("DoorFrontLeft")) then return nil end
    else
        return nil
    end
    local square = vehicle:getSquareForArea(part:getArea())
    if not square then return nil end
    return vehicle, square
end

function Storage.vehicleAccessible(player, part)
    local vehicle, square = Storage.vehiclePart(part)
    return vehicle and Storage.permitted(player, square) and Storage.permitted(player, vehicle:getSquare())
        and player:getSquare() and player:getSquare():getZ() == square:getZ()
        and vehicle:canAccessContainer(part:getIndex(), player) or false
end

function Storage.containerReachable(player, container, squareReachable)
    local part = Storage.partFor(container)
    if part then return Storage.vehicleAccessible(player, part) end
    local body = Storage.corpseFor(container)
    if body and (not Storage.safeCorpse(body) or not Storage.permitted(player, body:getSquare())) then return false end
    return squareReachable
end

return Storage
