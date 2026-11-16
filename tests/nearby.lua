package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
-- Explicit game-boundary doubles: discovery must never request/generate loot.
package.loaded["AutoMindful/Consumables"] = {inspect = function(_, item)
    return {food = item.food == true and not item.unsafe, water = item.water == true and not item.unsafe}
end}
package.loaded["AutoMindful/Supplies"] = {literatureInfo = function(_, item)
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
    local o = {kind="IsoObject",containers={}}
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
local adjacent=object(square(1,0),{item({food=true})})
local far=object(square(8,0),{item({food=true,book=true})})
local near=object(square(3,0),{item({food=true})})
local snapshot=Nearby.scan(player,origin,10)
assert(#snapshot.food==3 and #snapshot.literature==1 and snapshot.containerCount==3)
assert(snapshot.radius==10 and snapshot.scannedAt==1000 and snapshot.food[1].owned==false)
assert(snapshot.unloadedSquares>0 and #snapshot.unknownTargets==0)
assert(find("food").key=="food:3:0:0", "known targets skip adjacent sources included in snapshot")
assert(find("food",10,{["food:3:0:0"]=true}).key=="food:8:0:0")
assert(find("food",10,{["food:3:0:0"]=999}).key=="food:3:0:0")
local before=reads
assert(Nearby.scan(player,origin,10)==snapshot and reads==before, "cache reused across needs")
near.containers[1].items[1].unsafe=true
assert(find("food").key=="food:3:0:0", "cached positive remains bounded to its short lifetime")
now=1999; assert(Nearby.scan(player,origin,10)==snapshot)
now=2000; assert(find("food").key=="food:8:0:0", "cache expires after one second")
near.containers[1].items[1].unsafe=false
Nearby.scan(player,origin,10,true)
assert(find("food").key=="food:3:0:0", "forced scan refreshes data")
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
print("Nearby discovery and snapshot contracts passed; no native network/pathfinding exercised")
