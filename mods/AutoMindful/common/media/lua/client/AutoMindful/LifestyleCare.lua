-- Discover ready Lifestyle care only; actual work and success stay in the
-- native adapters. Nothing here owns a queue or changes the player's needs.
local Storage = require "AutoMindful/Storage"
local Grid = require "AutoMindful/Grid"
local Supplies = require "AutoMindful/Supplies"
local Restroom = require "AutoMindful/RestroomCare"
local Hygiene = require "AutoMindful/HygieneCare"
local ScoutMemory = require "AutoMindful/ScoutMemory"
local SurvivalRoute = require "AutoMindful/SurvivalRoute"
local Log = require "AutoMindful/Log"
local Care = {}
local adapters = {restroom=Restroom, hygiene=Hygiene}
local SCAN_MS, EMPTY_SCAN_MS, COOLDOWN_MS, COOLDOWN_LIMIT_MS = 1000, 10000, 15000, 900000

local function checked(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, result = pcall(f, ...)
    if ok then return result end
end

function Care.need(player, kind)
    local a = adapters[kind]
    local value = a and checked(a.need, player)
    return type(value) == "number" and value > 0
end

local function fixtureTarget(player, state, kind, object, square, index, distance)
    if not object or not square then return nil end
    local key = kind .. ":" .. Grid.key(square) .. ":" .. index
    if state.lifestyleRejected and state.lifestyleRejected[key] then return nil end
    if SurvivalRoute.roomBlocked(state.travelRejected,square,player:getSquare(),nil,getTimestampMs()) then return nil end
    local a=adapters[kind]
    local data=checked(a.inspect,player,object)
    if data then
        if data.plungerId and state.restroomToolsTried and state.restroomToolsTried[key]==data.plungerId then return end
        return {kind=kind,object=object,square=square,care=data,key=key,distance=distance,
            close=checked(a.accessible,player,data)==true}
    end
end

local function recalledFixture(player,state,kind,radius,now)
    if not state.scoutMemory then return nil end
    local target=ScoutMemory.choose(state.scoutMemory,kind,player:getSquare(),radius,now,function(_,object,square)
        if not Storage.permitted(player,square) then return nil end
        local objects=square:getObjects()
        for index=0,objects:size()-1 do
            if objects:get(index)==object then return fixtureTarget(player,state,kind,object,square,index) end
        end
    end)
    if target then target.remembered=true end
    return target
end

function Care.frontInRange(target,x,y,z,radius)
    local front=target and type(target.care)=="table" and target.care.front
    if not front then return true end
    local dx,dy=front:getX()-x,front:getY()-y
    return front:getZ()==z and dx*dx+dy*dy<=radius*radius
end

local function fixture(player, state, kind, radius, now, origin)
    local anchored=origin~=nil
    local here, cell = player:getSquare(), getCell()
    origin=origin or here
    if not here or not cell or here:getZ()~=origin:getZ() then return nil end
    local cache = state.lifestyleScan or {}
    state.lifestyleScan = cache
    local cacheKey=kind .. ":" .. radius
    local old = cache[cacheKey]
    if old and old.here == here and old.origin==origin and old.radius == radius and now >= old.at
            and now-old.at < (old.target and SCAN_MS or EMPTY_SCAN_MS) then
        return old.target
    end
    local x0,y0,z = origin:getX(),origin:getY(),origin:getZ()
    local hx,hy=here:getX(),here:getY()
    local best
    for x=x0-radius,x0+radius do
        for y=y0-radius,y0+radius do
            local dx,dy=x-x0,y-y0
            local fromOrigin=dx*dx+dy*dy
            local d=(x-hx)*(x-hx)+(y-hy)*(y-hy)
            if (fromOrigin <= radius*radius or (radius==1 and fromOrigin==2)) and (not best or d <= best.distance) then
                local square = cell:getGridSquare(x,y,z)
                if square and Storage.permitted(player,square) then
                    local objects = square:getObjects()
                    for i=0,objects:size()-1 do
                        local object = objects:get(i)
                        local target=fixtureTarget(player,state,kind,object,square,i,d)
                        if target and (not anchored or Care.frontInRange(target,x0,y0,z,radius))
                                and (radius>1 or target.close) and (not best or d<best.distance
                                or (d==best.distance and target.close and not best.close)) then
                            best=target
                        end
                    end
                end
            end
        end
    end
    cache[cacheKey]={here=here,origin=origin,radius=radius,at=now,target=best}
    return best
end

function Care.reject(state, target, now)
    -- The same fixture failing again and again is not worth the same walk.
    state.lifestyleMisses = state.lifestyleMisses or {}
    local misses = (state.lifestyleMisses[target.key] or 0) + 1
    state.lifestyleMisses[target.key] = misses
    local wait = math.min(COOLDOWN_LIMIT_MS, COOLDOWN_MS * 4 ^ (misses - 1))
    Log.event(state.player, "lifestyle.reject", "kind", target.kind, "key", target.key, "misses", misses, "waitS", wait / 1000)
    state.lifestyleRejected = state.lifestyleRejected or {}
    state.lifestyleRejected[target.key] = now+wait
    state.lifestyleScan = nil
end

local function allowedItem(player, item)
    return checked(Hygiene.item,player,item) == true
end

function Care.ready(player, state, now, collect, scoutRadius, origin, served)
    local rejected = state.lifestyleRejected or {}
    for key,untilTime in pairs(rejected) do
        if now>=untilTime then rejected[key]=nil; state.lifestyleScan=nil end
    end
    local function selectFixture(kind)
        if not collect and not scoutRadius then return end
        -- An already usable adjacent fixture needs no scouting walk, even at
        -- the rim. Only a new walk must keep both fixture and known feet in range.
        local localTarget=fixture(player,state,kind,1,now)
        if localTarget or not scoutRadius or scoutRadius<=1 then return localTarget end
        if origin then return fixture(player,state,kind,scoutRadius,now,origin) end
        return recalledFixture(player,state,kind,scoutRadius,now) or fixture(player,state,kind,scoutRadius,now)
    end
    local restroomNeeded=Care.need(player,"restroom")
    if not restroomNeeded then state.restroomToolsTried=nil end
    if not restroomNeeded and not Care.need(player,"hygiene") then state.lifestyleMisses=nil end
    if restroomNeeded and not (served and served.restroom) then
        local target=selectFixture("restroom")
        if target then return target end
        if not rejected["ground"] and checked(Restroom.groundAllowed,player)==true then
            return {kind="restroom", key="ground", ground=true, close=true}
        end
    end
    if not (served and served.hygiene) and Care.need(player,"hygiene") then
        if not Hygiene.searchItems or checked(Hygiene.searchItems,player)==true then
            local item=Supplies.findCareItem(player,function(candidate)
                return not rejected["hygiene:item:"..candidate:getID()] and allowedItem(player,candidate)
            end,collect or scoutRadius~=nil)
            if item then return {kind="hygiene", key="hygiene:item:"..item:getID(), item=item,close=true} end
        end
        if not Hygiene.washable or checked(Hygiene.washable,player)==true then return selectFixture("hygiene") end
    end
end

function Care.validTarget(player,target)
    local a=adapters[target.kind]
    if not a or not target.object or not Care.need(player,target.kind)
        or not target.object.getSquare or target.object:getSquare()~=target.square then return false end
    if a.validTarget then return checked(a.validTarget,player,target.care)==true end
    local live=checked(a.inspect,player,target.object)
    return type(live)=="table" and live.object==target.object and live.square==target.square
        and (not target.care.front or live.front==target.care.front)
end

function Care.accessible(player,target)
    local a=adapters[target.kind]
    if not a or not Care.need(player,target.kind) then return false end
    if target.item then return allowedItem(player,target.item) end
    if target.ground then return checked(a.groundAllowed,player)==true end
    return checked(a.accessible,player,target.care)==true
end

function Care.begin(player,target,state,useOnly)
    if not Care.accessible(player,target) then return nil end
    local a=adapters[target.kind]
    local before=checked(a.snapshot,player,target.item)
    if not before then return nil end
    local ok
    if target.item then ok=checked(a.queueItem,player,target.item,before)
    elseif target.ground then ok=checked(a.queueGround,player,before)
    elseif target.kind=="restroom" then
        local tried=state and state.restroomToolsTried and state.restroomToolsTried[target.key]
        ok=checked(a.queueToilet,player,target.care,before,useOnly,tried)
        -- Even a refused/partial click can mean the same trip would only
        -- repeat. Remember the tool for this need episode; another fixture,
        -- a new tool or a newly usable toilet is still eligible.
        local tool=before.toolId or (ok~=true and target.care.plungerId)
        if state and tool then
            state.restroomToolsTried=state.restroomToolsTried or {}
            state.restroomToolsTried[target.key]=tool
            state.lifestyleScan=nil
        end
    else ok=checked(a.queueWash,player,target.care,before) end
    if ok~=true then return nil end
    return {target=target,before=before}
end

function Care.prepared(player,course)
    return course.target.kind=="restroom" and checked(Restroom.prepared,player,course.before)==true
end

function Care.receipt(player,course)
    local t=course.target
    local a=adapters[t.kind]
    local kind=t.item and "item" or t.ground and "ground" or t.kind=="restroom" and "toilet" or "wash"
    return checked(a.receipt,player,course.before,kind)==true
end

return Care
