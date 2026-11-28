-- Finds somewhere better than the floor to sleep. Read-only: the walk and the
-- sleep are the game's own.
local Grid = require "AutoMindful/Grid"

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

local function key(object) return Grid.key(object:getSquare()) end

-- rejected[key] is the time before which a bed is not tried again.
function Beds.find(player, radius, rejected, now)
    local best, score
    -- Nobody is sent across the street at night for a better mattress.
    Grid.around(player, radius, function(square, dx, dy)
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
    end)
    return best
end

Beds.key = key
return Beds
