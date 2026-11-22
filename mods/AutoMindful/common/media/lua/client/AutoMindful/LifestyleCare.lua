-- Discover ready Lifestyle care only; actual work and success stay in the
-- native adapters. Nothing here owns a queue or changes the player's needs.
local Storage = require "AutoMindful/Storage"
local Supplies = require "AutoMindful/Supplies"
local Restroom = require "AutoMindful/RestroomCare"
local Hygiene = require "AutoMindful/HygieneCare"
local ScoutMemory = require "AutoMindful/ScoutMemory"
local Care = {}
local adapters = {restroom=Restroom, hygiene=Hygiene}
local SCAN_MS, COOLDOWN_MS = 1000, 15000

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
    local key = kind .. ":" .. square:getX() .. ":" .. square:getY() .. ":" .. square:getZ() .. ":" .. index
    if state.lifestyleRejected and state.lifestyleRejected[key] then return nil end
    local a=adapters[kind]
    local data=checked(a.inspect,player,object)
    if data then
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

local function fixture(player, state, kind, radius, now)
    local here, cell = player:getSquare(), getCell()
    if not here or not cell then return nil end
    local cache = state.lifestyleScan or {}
    state.lifestyleScan = cache
    local cacheKey=kind .. ":" .. radius
    local old = cache[cacheKey]
    if old and old.here == here and old.radius == radius and now >= old.at and now-old.at < SCAN_MS then
        return old.target
    end
    local x0,y0,z = here:getX(),here:getY(),here:getZ()
    local best
    for x=x0-radius,x0+radius do
        for y=y0-radius,y0+radius do
            local dx,dy=x-x0,y-y0
            local d=dx*dx+dy*dy
            if (d <= radius*radius or (radius==1 and d==2)) and (not best or d <= best.distance) then
                local square = cell:getGridSquare(x,y,z)
                if square and Storage.permitted(player,square) then
                    local objects = square:getObjects()
                    for i=0,objects:size()-1 do
                        local object = objects:get(i)
                        local target=fixtureTarget(player,state,kind,object,square,i,d)
                        if target and (radius>1 or target.close) and (not best or d<best.distance
                                or (d==best.distance and target.close and not best.close)) then
                            best=target
                        end
                    end
                end
            end
        end
    end
    cache[cacheKey]={here=here,radius=radius,at=now,target=best}
    return best
end

function Care.reject(state, target, now)
    state.lifestyleRejected = state.lifestyleRejected or {}
    state.lifestyleRejected[target.key] = now+COOLDOWN_MS
    state.lifestyleScan = nil
end

local function allowedItem(player, item)
    return checked(Hygiene.item,player,item) == true
end

function Care.ready(player, state, now, collect, scoutRadius)
    local rejected = state.lifestyleRejected or {}
    for key,untilTime in pairs(rejected) do
        if now>=untilTime then rejected[key]=nil; state.lifestyleScan=nil end
    end
    local function selectFixture(kind)
        if not collect and not scoutRadius then return end
        local localTarget=fixture(player,state,kind,1,now)
        if localTarget or not scoutRadius or scoutRadius<=1 then return localTarget end
        return recalledFixture(player,state,kind,scoutRadius,now) or fixture(player,state,kind,scoutRadius,now)
    end
    if Care.need(player,"restroom") then
        local target=selectFixture("restroom")
        if target then return target end
        if not rejected["ground"] and checked(Restroom.groundAllowed,player)==true then
            return {kind="restroom", key="ground", ground=true, close=true}
        end
    end
    if Care.need(player,"hygiene") then
        if not Hygiene.searchItems or checked(Hygiene.searchItems,player)==true then
            local item=Supplies.findCareItem(player,function(candidate)
                return not rejected["hygiene:item:"..candidate:getID()] and allowedItem(player,candidate)
            end,collect or scoutRadius~=nil)
            if item then return {kind="hygiene", key="hygiene:item:"..item:getID(), item=item,close=true} end
        end
        return selectFixture("hygiene")
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

function Care.begin(player,target)
    if not Care.accessible(player,target) then return nil end
    local a=adapters[target.kind]
    local before=checked(a.snapshot,player,target.item)
    if not before then return nil end
    local ok
    if target.item then ok=checked(a.queueItem,player,target.item,before)
    elseif target.ground then ok=checked(a.queueGround,player,before)
    elseif target.kind=="restroom" then ok=checked(a.queueToilet,player,target.care,before)
    else ok=checked(a.queueWash,player,target.care,before) end
    if ok~=true then return nil end
    return {target=target,before=before}
end

function Care.receipt(player,course)
    local t=course.target
    local a=adapters[t.kind]
    local kind=t.item and "item" or t.ground and "ground" or t.kind=="restroom" and "toilet" or "wash"
    return checked(a.receipt,player,course.before,kind)==true
end

return Care
