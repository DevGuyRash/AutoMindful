-- Admission and negative evidence for a known care supply. The engine
-- still owns every movement, collision, stop and actual interaction.
local Route = {}
local scopeKey={}

function Route.tracks(kind)
    return kind=="food" or kind=="water" or kind=="pain"
end

function Route.known(target,kind)
    return target and not target.unknown and Route.tracks(kind)
end

function Route.identity(target)
    return target.container or target.object or target.item or target.key
end

-- This table shares the existing rejection map with short, numeric stock and
-- replication cooldowns. Never let one water fixture reject its neighbor on
-- the same square. No route/objects are persisted to the save or ModData.
-- Keep at most the failed sources from the active search area. In particular,
-- persistent Recovery must not retain old chunks when its survivor relocates.
function Route.scope(rejections,scope)
    if rejections[scopeKey] and rejections[scopeKey]~=scope then
        for key,r in pairs(rejections) do
            if type(r)=="table" and r.sources then rejections[key]=nil end
        end
        rejections[scopeKey]=nil
    end
end

function Route.reject(rejections,target,kind,now)
    if not Route.known(target,kind) or not target.routeLayout then
        rejections[target.key]=now+15000
        return "cooldown-15s"
    end
    if target.routeScope then
        Route.scope(rejections,target.routeScope)
        rejections[scopeKey]=target.routeScope
    end
    local r=rejections[target.key]
    if type(r)~="table" or r.layout~=target.routeLayout then
        r={layout=target.routeLayout, sources={}}
        rejections[target.key]=r
    end
    r.sources[Route.identity(target)]=true
    return "until-navigation-changes"
end

function Route.blocked(rejections,key,entry,layout,now)
    local r=rejections[key]
    if type(r)=="table" and r.sources then
        if layout==r.layout then return r.sources[Route.identity(entry)]==true end
        rejections[key]=nil
        return false
    end
    if type(r)=="number" and now>=r then rejections[key]=nil; return false end
    return r
end

-- Fingerprint observable *navigation* evidence, not every snapshot/time/loot
-- refresh. Opening a door, removing an obstruction, or loading new floor may
-- justify another path. An unrelated new can of food does not.
function Route.edgeState(object)
    if not (instanceof(object,"IsoDoor") or instanceof(object,"IsoWindow")
            or (instanceof(object,"IsoThumpable") and
                ((object.isDoor and object:isDoor()) or (object.isWindow and object:isWindow())))) then return "" end
    local open=object.IsOpen and object:IsOpen() or object.isOpen and object:isOpen()
    return "d"..(open and "1" or "0")..(object.isBarricaded and object:isBarricaded() and "1" or "0")
        ..(object.isLocked and object:isLocked() and "1" or "0")
end

function Route.tileState(square,vehicle)
    local n=0
    if square.getPathMatrix then
        if square:getPathMatrix(-1,0,0) then n=n+1 end
        if square:getPathMatrix(0,-1,0) then n=n+2 end
    end
    if square.canStand and square:canStand() then n=n+4 end
    if vehicle then n=n+8 end
    return string.sub("ABCDEFGHIJKLMNOP",n+1,n+1)
end

local function adjacent(here,square)
    return here and square and square:getZ()==here:getZ()
        and math.abs(square:getX()-here:getX())<=1 and math.abs(square:getY()-here:getY())<=1
end

function Route.waterInReach(point,here,partSquare)
    -- The adjacent scanner first visits physical parts within one square,
    -- then uses the same wall correction as the stock Drink interaction.
    if not adjacent(here,partSquare) then return false end
    local square=partSquare
    if luautils and luautils.getCorrectSquareForWall then square=luautils.getCorrectSquareForWall(point,partSquare) end
    return adjacent(here,square) and (here==square or here:canReachTo(square))
end

local function pointX(self) return self.x end
local function pointY(self) return self.y end

function Route.walk(player,square,world)
    local paths=ISPathFindAction
    if not (paths and paths.pathToNearest and paths.pathAdjacentToSquares
            and player.getCurrentSquare and square.getAdjacentSquare
            and (not world or (paths.pathAdjacentToMultiTileObject and world.getSpriteGridObjectsIncludingSelf and ArrayList))) then
        if world then return luautils.walkAdjObject(player,world,true,true) end
        return luautils.walkAdj(player,square,true)
    end
    if not player:getCurrentSquare() then return false end
    local squares={square}
    local a
    if world then
        local objects=ArrayList.new()
        world:getSpriteGridObjectsIncludingSelf(objects)
        for i=0,objects:size()-1 do
            local part=objects:get(i)
            local s=part:getSquare()
            if s and s~=square and (not isClient() or SafeHouse.isSafehouseAllowInteract(s,player)) then squares[#squares+1]=s end
        end
        a=paths:pathAdjacentToMultiTileObject(player,world,true)
    else
        a=paths:pathAdjacentToSquares(player,squares,true)
    end
    local goals={}
    local point={getX=pointX,getY=pointY}
    local cell=getCell()
    local function admit(x,y,z)
        local s=cell:getGridSquare(math.floor(x),math.floor(y),z)
        if not s or (isClient() and not SafeHouse.isSafehouseAllowInteract(s,player)) then return end
        point.x,point.y=x,y
        for _,part in ipairs(squares) do
            if world and Route.waterInReach(point,s,part)
                    or not world and adjacent(s,part) and (s==part or s:canReachTo(part)) then
                goals[#goals+1]=x; goals[#goals+1]=y; goals[#goals+1]=z
                return
            end
        end
    end
    if a then
        local g=a.goal
        -- Do not reinterpret an unknown future or third-party native goal.
        if not g or (g[1]~="NearestPreferred" and g[1]~="Nearest") then
            ISTimedActionQueue.add(a); return true
        end
        for pass=2,(g[1]=="NearestPreferred" and 3 or 2) do
            for i=1,#g[pass],3 do admit(g[pass][i],g[pass][i+1],g[pass][i+2]) end
        end
    end
    -- A dropped bottle/bag can sit on a genuinely clear floor tile. Stock
    -- permits same-tile interaction too; never route onto a solid fixture.
    if square.isFree and square:isFree(false) and square.canStand and square:canStand()
            and not square:isSolid() and not square:isSolidTrans() then
        admit(square:getX()+0.5,square:getY()+0.5,square:getZ())
    end
    if #goals==0 then return false end
    -- Stock 42.22's NearestPreferred submits diagonals on failure and then
    -- forceStops in the *same update*. Pass the native menu's actual legal
    -- alternatives to one normal navmesh request before the action starts.
    local action=paths:pathToNearest(player,goals)
    action.autoMindfulApproaches=#goals/3
    ISTimedActionQueue.add(action)
    return true
end

return Route
