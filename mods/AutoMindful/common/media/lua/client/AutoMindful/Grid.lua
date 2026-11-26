-- Squares and where things are: the one place that says what "next to",
-- "nearby" and "the same spot" mean. Read-only.
local Storage = require "AutoMindful/Storage"

local Grid = {}

-- "x:y:z", the identity of a square across frames and saves.
function Grid.key(square)
    return square:getX() .. ":" .. square:getY() .. ":" .. square:getZ()
end

-- One of the eight squares around, or the same one, on the same floor.
function Grid.adjacent(here, square)
    return here ~= nil and square ~= nil and here:getZ() == square:getZ()
        and math.abs(here:getX() - square:getX()) <= 1 and math.abs(here:getY() - square:getY()) <= 1
end

-- Where a container is: its own square, or that of the bag lying on the floor.
function Grid.containerSquare(container)
    local square = container:getSourceGrid()
    if square then return square end
    local holder = container:getContainingItem()
    local world = holder and holder:getWorldItem()
    return world and world:getSquare()
end

function Grid.favorite(item)
    return item ~= nil and item.isFavorite ~= nil and item:isFavorite() == true
end

-- Each loaded, permitted square within radius on the survivor's floor and in the
-- same building (outdoors: outdoors): nobody crosses the street for a stove or a bed.
-- visit(square, dx, dy) may return true to stop early.
function Grid.around(player, radius, visit)
    local here = player:getSquare()
    if not here then return end
    local x0, y0, z = here:getX(), here:getY(), here:getZ()
    local building = here.getBuilding and here:getBuilding()
    local cell, reach = getCell(), radius * radius
    for x = x0 - radius, x0 + radius do
        local dx = x - x0
        for y = y0 - radius, y0 + radius do
            local dy = y - y0
            -- Outside the circle, the square is never fetched.
            local square = dx * dx + dy * dy <= reach and cell:getGridSquare(x, y, z)
            if square and (square.getBuilding and square:getBuilding()) == building
                    and Storage.permitted(player, square) then
                if visit(square, dx, dy) then return end
            end
        end
    end
end

return Grid
