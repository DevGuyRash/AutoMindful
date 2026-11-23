-- Optional session hints for verified reusable fixtures or typed storage. Caller owns the table for
-- one local survivor/world and records only after the exact native success receipt.
-- Hints are never object IDs, permission, path proof, or entries in game ModData.
local Memory = {}
local MAX_PER_KIND, MAX_ORIGINS, TTL_MS = 4, 4, 2*60*60*1000
local fixtures = {restroom=true, hygiene=true, water=true}
local supplies = {literature=true, food=true, pain=true, water=true}

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function static(target,kind)
    if type(target) ~= "table" or not target.object or not target.square
            or target.item or target.ground or target.unknown or target.vehicle then return false end
    kind=kind or target.kind
    if target.container then return supplies[kind] and not target.part end
    return fixtures[kind] and (not target.part or target.part == target.object)
end

local function storageSlot(object,square,container)
    if not container or not container.getParent or container:getParent()~=object
            or not container.getSourceGrid or container:getSourceGrid()~=square
            or (container.getContainingItem and container:getContainingItem())
            or (container.getVehiclePart and container:getVehiclePart())
            or not object.getContainerCount or not object.getContainerByIndex then return end
    local kind=container:getType()
    local count=object:getContainerCount()
    if type(kind)~="string" or kind=="" or kind=="floor" or not finite(count)
            or count<=0 or count>16 or math.floor(count)~=count then return end
    local slot
    for i=0,count-1 do
        if object:getContainerByIndex(i)==container then
            if slot~=nil then return end -- ambiguous native membership
            slot=i
        end
    end
    return slot,kind
end

local function property(props, key)
    local value = props and props:get(key)
    return type(value) == "string" and value or false
end

local function signature(object, square)
    -- Both doors/fixtures and decoration can be listed as IsoObject. The caller's
    -- fresh native-kind probe must still recognize this one on every resolution.
    if not object or not instanceof(object,"IsoObject") or instanceof(object,"IsoMovingObject")
            or instanceof(object,"IsoWorldInventoryObject") or object:getSquare() ~= square
            or object:getMasterObject() ~= object then return end
    local sprite = object:getSprite()
    local tile = sprite and sprite:getName()
    local className = object:getObjectName()
    if type(tile) ~= "string" or tile == "" or type(className) ~= "string" or className == "" then return end
    local props = sprite:getProperties()
    return tile, className, property(props,"GroupName"), property(props,"Facing")
end

local function matches(h, object, square)
    local tile, className, group, facing = signature(object,square)
    return tile == h.tile and className == h.className and group == h.group and facing == h.facing
end

local function fresh(at, now)
    return finite(at) and now >= at and now-at < TTL_MS
end

local function bucket(memory, kind, now)
    local records = memory[kind]
    if not records then return end
    for i=#records,1,-1 do
        local h = records[i]
        if not fresh(h.at,now) then
            table.remove(records,i)
        elseif h.times then
            for j=#h.times,1,-1 do
                if not fresh(h.times[j].at,now) then table.remove(h.times,j) end
            end
            if #h.times == 0 then h.times = nil end
        end
    end
    return records
end

local function unique(hint, square)
    local objects, match = square:getObjects()
    for i=0,objects:size()-1 do
        local object = objects:get(i)
        if matches(hint,object,square) then
            if match then return end -- no persistent ID; never guess between twins
            match=object
        end
    end
    return match
end

local function suffix(h)
    local function key(v)
        local s=type(v)=="string" and v or ""
        return #s..":"..s
    end
    return ":storage:"..h.slot..":"..key(h.containerType)..key(h.tile)..key(h.className)..key(h.group)..key(h.facing)
end

-- Share the exact same identity with normal scouting. Never partition a
-- rejection by an invented position in an ambiguous native object list.
function Memory.storageSuffix(container,square)
    local ok,value=pcall(function()
        local object=container.getParent and container:getParent()
        if not object then return end
        local slot,containerType=storageSlot(object,square,container)
        if slot==nil then return end
        local tile,className,group,facing=signature(object,square)
        if not tile then return end
        local h={slot=slot,containerType=containerType,tile=tile,className=className,group=group,facing=facing}
        if unique(h,square)==object then return suffix(h) end
    end)
    if ok then return value end
end

local function storageTarget(kind,container)
    if not supplies[kind] then return end
    local object=container and container.getParent and container:getParent()
    local square=object and object.getSquare and object:getSquare()
    if square and signature(object,square) and storageSlot(object,square,container)~=nil then
        return {kind=kind,object=object,square=square,container=container}
    end
end

function Memory.storageTarget(kind,container)
    local ok,target=pcall(storageTarget,kind,container)
    if ok then return target end
end

-- Capture the exact, fixed storage source before the native pickup. It is not
-- a success receipt and is never itself saved to survivor or world data.
function Memory.supplyTarget(kind,item)
    local ok,target=pcall(function() return storageTarget(kind,item and item:getContainer()) end)
    if ok then return target end
end

local function liveStorage(target)
    if not static(target) or not target.container then return false end
    local object,square=target.object,target.square
    local cell=getCell()
    if not cell or cell:getGridSquare(square:getX(),square:getY(),square:getZ())~=square
            or not square:getObjects():contains(object) or not signature(object,square) then return false end
    local slot,kind=storageSlot(object,square,target.container)
    local hint=target.scoutHint
    return slot~=nil and (not hint or (slot==hint.slot and kind==hint.containerType and unique(hint,square)==object))
end

function Memory.liveStorage(target)
    local ok,result=pcall(liveStorage,target)
    return ok and result==true
end

local function coordinate(n) return finite(n) and math.floor(n) == n end

local function originIs(t,x,y,z) return t.x == x and t.y == y and t.z == z end

local function recordTime(h, sample, now)
    if type(sample) ~= "table" or not coordinate(sample.x) or not coordinate(sample.y)
            or sample.z ~= h.z or not finite(sample.ms) or sample.ms <= 0 then return end
    h.times = h.times or {}
    for i=#h.times,1,-1 do
        if originIs(h.times[i],sample.x,sample.y,sample.z) then table.remove(h.times,i) end
    end
    table.insert(h.times,1,{x=sample.x,y=sample.y,z=sample.z,ms=sample.ms,at=now})
    if #h.times > MAX_ORIGINS then table.remove(h.times) end
end

local function timeFor(h,x,y,z)
    if not h.times then return end
    for _,t in ipairs(h.times) do
        if originIs(t,x,y,z) then return t.ms end
    end
end

local function remember(memory,target,now,sample)
    if type(memory) ~= "table" or not finite(now) or not static(target) then return false end
    local kind, object, square, cell = target.kind, target.object, target.square, getCell()
    local x,y,z = square:getX(),square:getY(),square:getZ()
    if not cell or cell:getGridSquare(x,y,z) ~= square then return false end
    local tile, className, group, facing = signature(object,square)
    if not tile then return false end
    local hint = {x=x,y=y,z=z,tile=tile,className=className,group=group,facing=facing,at=now}
    if target.container then
        hint.slot,hint.containerType=storageSlot(object,square,target.container)
        if hint.slot==nil then return false end
    end
    if unique(hint,square) ~= object then return false end
    local records = bucket(memory,kind,now) or {}
    memory[kind] = records
    for i=#records,1,-1 do
        local h=records[i]
        if h.x==x and h.y==y and h.z==z and h.tile==tile and h.className==className and h.group==group
                and h.facing==facing and h.slot==hint.slot and h.containerType==hint.containerType then
            hint.times=h.times
            table.remove(records,i)
        end
    end
    recordTime(hint,sample,now)
    table.insert(records,1,hint)
    if #records > MAX_PER_KIND then table.remove(records) end
    return true
end

-- target is the already-confirmed fixed fixture, or its exact fixed container.
-- A water fixture may have .part == .object (canonical water adapter);
-- movable item, vehicle, corpse and loose floor targets are excluded. A successful
-- round trip can supply {x,y,z,ms}, measured at the exact training tile. An
-- adjacent use without a sample keeps, but does not refresh, older timings.
function Memory.remember(memory,target,now,sample)
    local ok, result = pcall(remember,memory,target,now,sample)
    return ok and result == true
end

local function closer(d,at,oldD,oldAt)
    return not oldD or d < oldD or (d == oldD and at > oldAt)
end

local function choose(memory, kind, currentSquare, radius, now, resolve)
    if type(memory) ~= "table" or (not fixtures[kind] and not supplies[kind]) or not currentSquare or not finite(radius) or radius < 0
            or not finite(now) or type(resolve) ~= "function" then return end
    local records = bucket(memory,kind,now)
    local cell = records and #records>0 and getCell()
    if not cell then return end
    local x,y,z = currentSquare:getX(),currentSquare:getY(),currentSquare:getZ()
    if cell:getGridSquare(x,y,z) ~= currentSquare then return end
    local nearest, nearestD, nearestAt, nearestMs
    local fastest, fastestD, fastestAt, fastestMs
    local latest, latestD, latestAt
    local i=1
    while i<=#records do
        local h=records[i]
        local dx,dy=h.x-x,h.y-y
        local d=dx*dx+dy*dy
        local remove
        if h.z==z and d<=radius*radius and (h.slot==nil or not latest) then
            local square = cell:getGridSquare(h.x,h.y,h.z)
            -- An unloaded/unknown tile is not evidence that the fixture is gone.
            if square then
                local object = unique(h,square)
                if not object then
                    remove=true -- loaded but removed/replaced/ambiguous
                else
                    local container
                    if h.slot~=nil then
                        container=object.getContainerByIndex and object:getContainerByIndex(h.slot)
                        local slot,containerType=storageSlot(object,square,container)
                        if slot~=h.slot or containerType~=h.containerType then remove=true end
                    end
                    if not remove then
                        local checked, candidate, obsolete = pcall(resolve,kind,object,square,container,container and suffix(h))
                        if checked and not candidate and obsolete==true then remove=true end
                        if checked and static(candidate,kind) and candidate.object==object and candidate.square==square
                                and candidate.container==container and (not candidate.kind or candidate.kind==kind)
                                and object:getSquare()==square and cell:getGridSquare(h.x,h.y,h.z)==square
                                and square:getObjects():contains(object)
                                and (not container or storageSlot(object,square,container)==h.slot) then
                            candidate.scoutHint=h
                            if container then
                                latest,latestD,latestAt=candidate,d,h.at
                            else
                                local ms = timeFor(h,x,y,z)
                                if closer(d,h.at,nearestD,nearestAt) then
                                    nearest,nearestD,nearestAt,nearestMs = candidate,d,h.at,ms
                                end
                                if ms and (not fastestMs or ms < fastestMs
                                        or (ms == fastestMs and closer(d,h.at,fastestD,fastestAt))) then
                                    fastest,fastestD,fastestAt,fastestMs = candidate,d,h.at,ms
                                end
                            end
                        end
                    end
                end
            end
        end
        if remove then table.remove(records,i) else i=i+1 end
    end
    -- A travel-time comparison cannot displace a nearer, unmeasured fixture.
    -- If nearest was measured, only other comparable measurements compete.
    if nearestMs then nearest,nearestD,nearestAt=fastest,fastestD,fastestAt end
    if latest and (not nearest or latestAt>=nearestAt) then return latest,latestD end
    return nearest,nearestD
end

-- resolve(kind, liveObject, liveSquare, liveContainer, storageSuffix) returns a new native
-- candidate (or nil for permission/usability). Only explicit, confirmed obsolete
-- stock returns a second true. No routes get saved, replayed
-- or assumed. Revalidate the returned exact object normally on arrival.
function Memory.choose(memory,kind,currentSquare,radius,now,resolve)
    local ok, target, distance = pcall(choose,memory,kind,currentSquare,radius,now,resolve)
    if ok then return target,distance end
end

-- Remove only the exact recalled record that failed a later live check.
function Memory.forget(memory,target)
    local records=type(memory)=="table" and target and memory[target.kind]
    if not records or not target.scoutHint then return end
    for i=#records,1,-1 do
        if records[i]==target.scoutHint then table.remove(records,i); return end
    end
end

return Memory
