local Storage = require "AutoMindful/Storage"
local Grid = require "AutoMindful/Grid"
local Egress = {}

local cardinal = {{-1,0}, {1,0}, {0,-1}, {0,1}}

local key = Grid.key

function Egress.obstructed(square)
    return square and ((square.isSolid and square:isSolid()) or (square.isSolidTrans and square:isSolidTrans())
        or (square.canStand and not square:canStand()))
end

local function canUse(player, from, to, onArrival)
    local room = from and from.getRoom and from:getRoom()
    return room and to and to.getRoom and to:getRoom()==room and to.canStand and to:canStand()
        and (not to.isFree or to:isFree(not onArrival)) and Storage.permitted(player,to) and from:canReachTo(to)
        and (not from.isWindowTo or not from:isWindowTo(to))
        and (not from.isDoorTo or not from:isDoorTo(to))
        and (not from.isHoppableTo or not from:isHoppableTo(to))
end

function Egress.options(player, from, boxedIn)
    if not (boxedIn or Egress.obstructed(from)) or not Storage.permitted(player,from) then return end
    local goals, candidates, signature = {}, {}, {key(from)}
    local x,y,z = from:getX(),from:getY(),from:getZ()
    local cell = getCell()
    for _, offset in ipairs(cardinal) do
        local square = cell:getGridSquare(x+offset[1],y+offset[2],z)
        if canUse(player,from,square) then
            local id = key(square)
            signature[#signature+1] = id
            candidates[id] = true
            goals[#goals+1] = square:getX()+0.5
            goals[#goals+1] = square:getY()+0.5
            goals[#goals+1] = square:getZ()
        end
    end
    if #goals>0 then return {goals=goals, candidates=candidates, signature=table.concat(signature,"|")} end
end

function Egress.arrived(player, origin, plan)
    local here=player:getSquare()
    return here and plan.candidates[key(here)] and canUse(player,origin,here,true)
end

return Egress
