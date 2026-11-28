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
-- Next to it with nothing in between: no wall, no closed window. What the
-- game needs before an item can be picked up or a stove used.
function Grid.reachable(here, square)
    if not Grid.adjacent(here, square) then return false end
    return here == square or not here.canReachTo or here:canReachTo(square)
end

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
-- same building: nobody crosses the street for a bed. openAir: the open air
-- counts too, and from outdoors any building nearby (the grill in the yard, the
-- kitchen through the back door).
function Grid.around(player, radius, visit, openAir)
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
            local squareBuilding = square and square.getBuilding and square:getBuilding()
            if square and (squareBuilding == building or (openAir and (building == nil or squareBuilding == nil)))
                    and Storage.permitted(player, square) then
                visit(square, dx, dy)
            end
        end
    end
end

return Grid
