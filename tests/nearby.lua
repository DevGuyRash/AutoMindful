package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
-- Explicit game-boundary doubles: discovery must never request/generate loot.
package.loaded["AutoMindful/Consumables"] = {inspect = function(_, item)
    return {food = item.food == true and not item.unsafe, water = item.water == true and not item.unsafe}
end}
package.loaded["AutoMindful/Supplies"] = {scoutProbe=function()
    return function(entry) return entry.item and not entry.item.unsafe and not entry.item.noUsableVessel end
end,literatureInfo = function(_, item)
    if not item.book then return false end
    if item.cooldown then return "cooldown" end
    return item.lastRead and "reread" or "unread", item.lastRead
end}
package.loaded["AutoMindful/Fluids"] = {inspect = function(fluid) return not fluid.unsafe and {} or nil end}
local cells, client, now, reads = {}, false, 1000, 0
function isClient() return client end
function getTimestampMs() return now end
function instanceof(object, kind) return object and object.kind == kind end
function getCell() return {getGridSquare=function(_, x,y,z)
    reads=reads+1; return cells[x..":"..y..":"..z]
end} end
SafeHouse = {isSafehouseAllowInteract=function(s) return not s.noInteract end,
    isSafehouseAllowLoot=function(s) return not s.noLoot end}
Fluid = {Water="water"}
local function forbidden() error("Discovery must not request, explore or generate contents") end
requestItemsForContainer=forbidden
sendClientCommand=forbidden
ItemPicker= {fillContainer=forbidden}
local function list(values)
    return {size=function() return #values end, get=function(_, i) return values[i+1] end}
end
local function square(x,y,z)
    local s = {x=x,y=y,z=z or 0,objects={},world={}}
    function s:getX() return self.x end
    function s:getY() return self.y end
    function s:getZ() return self.z end
    function s:canReachTo(other) return not other.acrossWall end
    function s:getObjects() return list(self.objects) end
    function s:getWorldObjects() return list(self.world) end
    cells[x..":"..y..":"..s.z] = s
    return s
end
local function container(items, explored)
    local c={items=items or {},explored=explored ~= false}
    function c:getItems() return list(self.items) end
    function c:isExplored() return self.explored end
    c.setExplored=forbidden; c.requestServerItemsForContainer=forbidden
    return c
end
local function object(s, items)
    local o = {kind="IsoObject",containers={},square=s}
    function o:getSquare() return self.square end
    function o:getMasterObject() return self.master or self end
    if items then o.containers={container(items)} end
    function o:hasWater() return self.water == true end
    function o:getFluidAmount() return self.empty and 0 or 5 end
    function o:isTaintedWater() return self.tainted == true end
    function o:getFluidContainer() return self.fluid end
    function o:getPrimaryFluid() return self.otherFluid and "other" or Fluid.Water end
    function o:getContainerCount() return #self.containers end
    function o:getContainerByIndex(i) return self.containers[i+1] end
    function o:isLockedToCharacter() return self.locked == true end
    function o:getItem() return self.item end
    s.objects[#s.objects+1]=o
    return o
end
local function ground(s,item)
    local o=object(s)
    table.remove(s.objects)
    s.world[#s.world+1]=o
    o.kind="IsoWorldInventoryObject"; o.item=item
    return o
end
local function item(props)
    props=props or {}
    function props:isSealed() return self.sealed == true end
    return props
end
local Nearby = require "AutoMindful/Nearby"
local origin, player
local function reset()
    cells={}; client=false; now=1000; reads=0
    origin=square(0,0); player={square=origin,getSquare=function(self) return self.square end}
end
local function find(kind,radius,rejected,worldOnly)
    return Nearby.find(player,kind,origin,radius or 10,rejected,worldOnly)
end
local function refresh() Nearby.invalidate(player) end
reset()
local tile=square(5,0)
local bottle=item({water=true})
local water=ground(tile,bottle); water.water=true
local target=find("water")
assert(target.object==water and target.item==bottle and Nearby.waterObject(player,target)==water,
    "A directly drinkable ground vessel keeps its world object even when it is also a portable supply")
water.tainted=true; assert(not Nearby.waterObject(player,target)); water.tainted=false
bottle.sealed=true; assert(not Nearby.waterObject(player,target)); bottle.sealed=false
client=true;tile.noLoot=true; assert(not Nearby.waterObject(player,target)); tile.noLoot=false
water.square=nil; assert(not Nearby.waterObject(player,target)); water.square=tile
assert(Nearby.waterObject(player,target)==water)
reset()
local adjacent=object(square(1,0),{item({food=true})})
local far=object(square(8,0),{item({food=true,book=true})})
local near=object(square(3,0),{item({food=true})})
local snapshot=Nearby.scan(player,origin,10)
assert(#snapshot.food==3 and #snapshot.literature==1 and snapshot.containerCount==3)
assert(snapshot.radius==10 and snapshot.scannedAt==1000 and snapshot.food[1].owned==false)
assert(snapshot.unloadedSquares>0 and #snapshot.unknownTargets==0)
assert(find("food").key=="food:3:0:0", "known targets skip adjacent sources included in snapshot")
assert(find("food",10,{["food:3:0:0"]=true}).key=="food:8:0:0")
adjacent.square.acrossWall=true
assert(find("food").square==adjacent.square,"A geometrically adjacent but unreachable holder needs a native approach")
adjacent.square.acrossWall=false
assert(find("food").square==near.square,"A normally reachable neighbor is handled without travel")
assert(find("food",10,{["food:3:0:0"]=999}).key=="food:3:0:0")
local before=reads
assert(Nearby.scan(player,origin,10)==snapshot and reads==before, "cache reused across needs")
near.containers[1].items[1].unsafe=true
assert(find("food").key=="food:8:0:0", "admission rechecks even a cached positive before choosing a route")
now=1999; assert(Nearby.scan(player,origin,10)==snapshot)
now=2000; assert(find("food").key=="food:8:0:0", "cache expires after one second")
near.containers[1].items[1].unsafe=false
Nearby.scan(player,origin,10,true)
assert(find("food").key=="food:3:0:0", "forced scan refreshes data")
near.containers[1].items[1].noUsableVessel=true
assert(find("food").square==far.square,"A potential but unusable bulk donor cannot hide a usable alternative")
near.containers[1].items[1].noUsableVessel=false
assert(find("food").square==near.square,"A newly viable holder is selectable from the same read-only snapshot")
near.containers[1].items={}; refresh()
assert(not find("food",5), "radius honored")
object(square(7,8),{item({food=true})}); object(square(2,0,1),{item({food=true})})
far.containers[1].items={}; refresh()
assert(not find("food"), "circle and floor bounds")
far.containers[1].items={item({book=true,cooldown=true})}; refresh()
assert(not find("literature"), "cooldown excluded")
far.containers[1].items[1].cooldown=false; refresh()
assert(find("literature").key=="literature:8:0:0")
local sinkSquare=square(4,0); local sink=object(sinkSquare); sink.water=true; refresh()
assert(find("water",10,nil,true).key=="water:4:0:0")
assert(#Nearby.scan(player,origin,10).waterSources==1)
sink.tainted=true; refresh(); assert(not find("water",10,nil,true))
sink.tainted=false; sink.kind="IsoThumpable"; sink.locked=true; refresh()
assert(not find("water",10,nil,true), "locked water source")
sink.locked=false; client=true; sinkSquare.noInteract=true; refresh()
assert(not find("water",10,nil,true), "safehouse interaction respected")
sinkSquare.noInteract=false; sink.water=false
near.containers[1].items={item({food=true})}; cells["3:0:0"].noLoot=true; refresh()
assert(not find("food",5), "safehouse loot respected, including unknown candidates")
cells["3:0:0"].noLoot=false; refresh(); assert(find("food",5).key=="food:3:0:0")
near.containers[1].items={item({water=true})}; refresh()
assert(not find("water",10,nil,true), "world-only skips item and unknown container targets")
assert(find("water").key=="water:3:0:0")
reset()
local unknown=object(square(2,0),{}).containers[1]; unknown.explored=false
assert(find("literature").unknown and find("literature").container==unknown)
assert(find("food").key=="unknown:2:0:0", "unknown rejection key is shared across needs")
assert(not find("water",10,{["unknown:2:0:0"]=true}), "shared unknown rejection respected")
unknown.items={item({book=true})}; refresh()
assert(#Nearby.scan(player,origin,10).unknownTargets==1 and #Nearby.scan(player,origin,10).literature==1)
assert(not find("literature").unknown, "positive observed contents usable even while unexplored")
unknown.explored=true; refresh(); assert(#Nearby.scan(player,origin,10).unknownTargets==0)
unknown.items={}; refresh(); assert(not find("food"), "confirmed SP explored empty is empty")
client=true; refresh(); assert(find("food").unknown, "MP explored empty remains unconfirmed")
now=1000000; assert(find("food").unknown, "elapsed time never proves MP empty")
unknown.items={item({unsafe=true,food=true})}; refresh()
assert(not find("food"), "MP explored nonempty with only unsafe stock is not an unknown target")
unknown.explored=false; refresh(); assert(find("food").unknown, "unexplored nonempty still unknown")
local known=object(square(8,0),{item({food=true})}); refresh()
assert(find("food").key=="food:8:0:0", "known useful stock takes precedence over nearer unknown")
local adjacentUnknown=object(square(1,0),{}).containers[1]; adjacentUnknown.explored=false
refresh(); assert(find("literature").key=="unknown:1:0:0", "unknown adjacency permits inspection without walking")
reset()
do
    local sameTile=square(4,0)
    local function staticStorage(sprite)
        local o=object(sameTile,{item({book=true})})
        local c=o.containers[1]
        o.spriteName=sprite
        function o:getObjectName()return "IsoObject" end
        function o:getSprite()return {getName=function()return o.spriteName end,getProperties=function()return nil end} end
        function c:getParent()return o end
        function c:getSourceGrid()return sameTile end
        function c:getType()return "shelves" end
        return o,c
    end
    local ao,a=staticStorage("cabinet_west")
    local bo,b=staticStorage("cabinet_east")
    local first=find("literature")
    assert(first and first.storageScoped)
    local sibling=find("literature",10,{[first.key]=true})
    assert(sibling and sibling.storageScoped and sibling.container~=first.container and sibling.square==first.square,
        "Rejecting one verified shelf must not hide suitable contents of its same-tile sibling")
    client=true; a.items,b.items={},{}; refresh()
    local unknownFirst=find("literature")
    assert(unknownFirst and unknownFirst.unknown and unknownFirst.storageScoped)
    local unknownSibling=find("food",10,{[unknownFirst.key]=true})
    assert(unknownSibling and unknownSibling.unknown and unknownSibling.container~=unknownFirst.container,
        "Both MP empty lists are unconfirmed, with rejection scoped to the concrete source")
    bo.spriteName=ao.spriteName
    refresh()
    local ambiguous=find("literature")
    assert(ambiguous and ambiguous.unknown and not ambiguous.storageScoped,
        "Identical native furniture signatures do not invent stable object identity")
end
reset()
local bag=item({kind="InventoryContainer"}); bag.inventory=container({item({book=true})})
function bag:getInventory() return self.inventory end
local inner=item({kind="InventoryContainer"}); inner.inventory=container({item({food=true})})
function inner:getInventory() return self.inventory end
bag.inventory.items[#bag.inventory.items+1]=inner
ground(square(3,0),bag)
local bagScan=Nearby.scan(player,origin,10)
assert(bagScan.containerCount==1 and #bagScan.literature==1 and #bagScan.food==0, "ground bags inspected one level only")
assert(find("literature").container==bag.inventory)
local duplicate=cells["3:0:0"].world[1]; cells["3:0:0"].world[2]=duplicate; refresh()
assert(Nearby.scan(player,origin,10).containerCount==1 and #Nearby.scan(player,origin,10).literature==1)
local first=Nearby.scan(player,origin,10)
player.square=square(0,0,1); assert(not find("literature"))
player.square=origin
local different=Nearby.scan(player,square(1,0),10)
assert(different~=first, "origin change invalidates cache")
assert(Nearby.scan(player,origin,2).radius==2, "radius change invalidates cache")
local p2={getSquare=function() return origin end}
assert(Nearby.scan(p2,origin,2)~=Nearby.scan(player,origin,2), "cache isolated by player")
-- Native storage boundaries are explicit; no door or body action is provided.
reset()
local bodySquare=square(5,0)
local body={kind="IsoDeadBody", inventory=container({item({book=true})}), reanimate=-1}
function body:isAnimal() return self.animal end
function body:isFakeDead() return self.fake end
function body:getReanimateTime() return self.reanimate end
function body:getContainer() return self.inventory end
function bodySquare:getStaticMovingObjects() return list({body,body}) end
assert(#Nearby.scan(player,origin,10).literature==1, "corpse container counted once")
for _, flag in ipairs({"animal","fake"}) do
    body[flag]=true; refresh(); assert(#Nearby.scan(player,origin,10).literature==0); body[flag]=false
end
body.reanimate=0; refresh(); assert(#Nearby.scan(player,origin,10).literature==0, "scheduled reanimation excluded")
body.reanimate=-1; bodySquare.noLoot=true; client=true; refresh()
assert(#Nearby.scan(player,origin,10).literature==0, "corpse safehouse protection")
reset()
local area=square(8,0); local center=square(6,0)
local vehicle={parts={},speed=0,doors={},id=12}
function vehicle:getId() return self.id end
function vehicle:getSquare() return center end
function vehicle:getCurrentAbsoluteSpeedKmHour() return self.speed end
function vehicle:getPartCount() return #self.parts end
function vehicle:getPartByIndex(i) return self.parts[i+1] end
function vehicle:getPartById(id) return self.doors[id] end
function vehicle:getPassengerDoor() return self.doors.passenger end
function vehicle:getSquareForArea() return area end
function vehicle:canAccessContainer() return self.access==true end
function center:getVehicleContainer() return vehicle end
function area:getVehicleContainer() return vehicle end
local part={id="TruckBed",inventory=container({item({book=true,water=true})})}
function part:getVehicle() return vehicle end
function part:getId() return self.id end
function part:getArea() return "TruckBed" end
function part:getIndex() return 0 end
function part:getItemContainer() return self.inventory end
function part:isInventoryItemUninstalled() return self.uninstalled end
function part:getContainerCapacity() return self.zeroCapacity and 0 or 50 end
function part:getContainerSeatNumber() return 0 end
function part:getInventoryItem() return not self.uninstalled end
vehicle.parts={part}
local scan=Nearby.scan(player,origin,10)
assert(#scan.literature==1 and scan.containerCount==1, "vehicle deduplicated across occupied squares")
assert(find("literature").part==part and find("literature").square==area)
assert(not find("literature",7), "radius is based on storage interaction area, not car center")
local door={open=false}
function door:getDoor() return self end
function door:getInventoryItem() return not self.missing end
function door:isOpen() return self.open end
vehicle.doors.TrunkDoor=door; refresh(); assert(not find("literature"), "closed trunk excluded; no opening/unlocking")
door.open=true; refresh(); assert(find("literature"))
vehicle.speed=1; refresh(); assert(not find("literature"), "moving vehicles excluded")
vehicle.speed=0; part.id="UnverifiedModStorage"; refresh(); assert(not find("literature"), "unknown layouts fail closed")
part.id="TruckBedOpen"; door.open=false; refresh(); assert(find("literature"), "open bed needs no door")
part.id="TrailerTrunk"; refresh(); assert(find("literature"))
part.id="GloveBox"; vehicle.doors.DoorFrontRight=door; refresh(); assert(not find("literature"))
door.missing=true; refresh(); assert(not find("literature"), "native glovebox still requires door open")
door.open=true; refresh(); assert(find("literature"))
part.id="SeatFrontRight"; vehicle.doors.passenger=door; door.open=false; door.missing=false
refresh(); assert(not find("literature"))
door.missing=true; refresh(); assert(find("literature"), "missing passenger door allows exterior seat access")
part.uninstalled=true; refresh(); assert(not find("literature"), "uninstalled seats excluded")
part.uninstalled=false; vehicle.doors.passenger=nil; vehicle.doors.DoorFrontLeft=door
refresh(); assert(not find("literature"), "no exterior path into rear two-door seats")
part.id="TruckBedOpen"; part.zeroCapacity=true; part.uninstalled=true; refresh(); assert(not find("literature"))
part.zeroCapacity=false; part.uninstalled=false; client=true; area.noLoot=true; refresh()
assert(not find("literature"), "vehicle area safehouse protected")
area.noLoot=false; center.noLoot=true; refresh(); assert(not find("literature"), "vehicle center safehouse protected")
center.noLoot=false; part.inventory.items={}; refresh()
assert(find("food").unknown and find("food").part==part, "unknown MP vehicle contents are scoutable")
assert(find("food").key=="unknown:8:0:0:vehicle:12:0")
assert(not find("food",10,{["unknown:8:0:0:vehicle:12:0"]=true}))
print("Nearby discovery and snapshot contracts passed; no native network/pathfinding exercised")

-- A proven path failure is not a failed sip. Cooldown expiry alone must not
-- turn the same disconnected rooms back into an opportunity to abandon care.
do
    reset()
    local Routes=require "AutoMindful/SurvivalRoute"
    local first=object(square(3,0)); first.water=true
    local second=object(square(5,0)); second.water=true
    local gate=object(square(2,0)); gate.kind="IsoDoor"
    function gate:IsOpen() return self.open end
    function gate:isBarricaded() return self.barricaded end
    local rejected={}
    local function fail(want)
        local target=find("water",10,rejected,true)
        assert(target and target.object==want)
        Routes.reject(rejected,target,"water",now)
    end
    fail(first); fail(second)
    for _,wait in ipairs({16000,60000,3600000}) do
        now=now+wait; refresh()
        assert(not find("water",10,rejected,true),"unchanged native layout must leave all failed sources exhausted")
    end
    -- A genuinely new fixture on the SAME tile is not its neighbor's route.
    local third=object(first.square); third.water=true; refresh()
    assert(find("water",10,rejected,true).object==third)
    fail(third); assert(not find("water",10,rejected,true))
    gate.open=true; refresh()
    assert(find("water",10,rejected,true).object==first,"opening a door must re-admit a previously disconnected setup")
end
print("PASS: exhausted known fixtures remain exhausted on unchanged terrain; new fixture and native door change re-arm")

do
    reset()
    origin=square(7188,8335); player.square=origin
    local Routes=require "AutoMindful/SurvivalRoute"
    local pain=require "AutoMindful/PainCare"
    local original=pain.eligible
    pain.eligible=function(candidate) return candidate.pain==true end
    local first=object(square(7194,8331),{item({pain=true})})
    local second=object(square(7188,8343),{item({pain=true})})
    local gate=object(square(7189,8335)); gate.kind="IsoDoor"
    function gate:IsOpen() return self.open end
    local rejected={}
    local failed=find("pain",10,rejected)
    assert(failed.container==first.containers[1])
    Routes.reject(rejected,failed,"pain",now)
    for _,delay in ipairs({16000,60000}) do
        now=now+delay; refresh()
        assert(find("pain",10,rejected).container==second.containers[1],
            "Pain care must not interrupt practice for an unchanged failed route")
    end
    gate.open=true; refresh()
    assert(find("pain",10,rejected).container==first.containers[1],
        "Observable navigation changes must restore the painkiller route")
    pain.eligible=original
end

do
    reset()
    client=true
    local Route=require "AutoMindful/SurvivalRoute"
    local a=object(square(3,0),{}).containers[1]
    local b=object(square(4,0),{}).containers[1]
    local door=object(square(1,0)); door.kind="IsoDoor"
    function door:IsOpen() return self.open end
    local rejected={}
    local first=find("water",10,rejected)
    assert(first.unknown and first.container==a)
    assert(Route.reject(rejected,first,"water",now)=="when-navigation-changes-after-15s")
    local second=find("water",10,rejected)
    assert(second.unknown and second.container==b)
    Route.reject(rejected,second,"water",now)
    for _,elapsed in ipairs({16000,60000,3600000}) do
        now=now+elapsed; refresh()
        assert(not find("water",10,rejected) and not find("literature",10,rejected),
            "Elapsed time alone must not re-arm unchanged unconfirmed routes")
    end
    b.items={item({water=true})}; refresh()
    local known=find("water",10,rejected)
    assert(known and not known.unknown and known.container==b,
        "New positive stock has a separate admission from an unconfirmed route")
    b.items={}; door.open=true; refresh()
    assert(find("water",10,rejected).container==a,"A real route change re-arms speculative scouting")
end
print("PASS: unconfirmed path exhaustion persists; positive stock and navigation changes rearm")
