-- Finds somewhere better than the floor to sleep. Read-only: the walk and the
-- sleep are the game's own.
local Storage = require "AutoMindful/Storage"

local Beds = {}
local quality = {goodBed=4, averageBed=3, badBed=2}

local function rank(player, object)
    local kind = ISWorldObjectContextMenu.getBedQuality(player, object)
    if type(kind) ~= "string" then return 0 end
    return quality[(kind:gsub("Pillow", ""))] or 1
end

local function isBed(object)
    local properties = object.getProperties and object:getProperties()
    return properties and IsoFlagType and properties:has(IsoFlagType.bed) or false
end

local function key(object)
    local square = object:getSquare()
    return square:getX() .. ":" .. square:getY() .. ":" .. square:getZ()
end

-- rejected[key] is the time before which a bed is not tried again.
function Beds.find(player, radius, rejected, now)
    local here = player:getSquare()
    if not here then return nil end
    local best, score
    local x0, y0, z = here:getX(), here:getY(), here:getZ()
    -- Nobody is sent across the street at night for a better mattress.
    local building = here.getBuilding and here:getBuilding()
    for x = x0 - radius, x0 + radius do
        for y = y0 - radius, y0 + radius do
            local dx, dy = x - x0, y - y0
            local square = dx * dx + dy * dy <= radius * radius and getCell():getGridSquare(x, y, z)
            if square and (square.getBuilding and square:getBuilding()) == building and Storage.permitted(player, square) then
                local objects = square:getObjects()
                for index = 0, objects:size() - 1 do
                    local object = objects:get(index)
                    if isBed(object) and not (object.isFurnitureOccupied and object:isFurnitureOccupied(player)) then
                        local waiting = rejected and rejected[key(object)]
                        if not (waiting and now < waiting) then
                            local value = rank(player, object) * 100 - (dx * dx + dy * dy)
                            if not score or value > score then best, score = object, value end
                        end
                    end
                end
            end
        end
    end
    return best
end

Beds.key = key
return Beds
