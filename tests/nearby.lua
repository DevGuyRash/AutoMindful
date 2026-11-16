package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
-- Discovery boundaries are explicit doubles. This does not exercise native
-- pathfinding, network access, or actual inventory transfer.
package.loaded["AutoMindful/Consumables"] = {inspect = function(_, item)
    return {food = item.food == true and not item.unsafe, water = item.water == true and not item.unsafe}
end}
package.loaded["AutoMindful/Supplies"] = {eligibleLiterature = function(_, item)
    return item.book == true and not item.cooldown
end}
package.loaded["AutoMindful/Fluids"] = {inspect = function(fluid) return not fluid.unsafe and {} or nil end}
local cells, client, now = {}, false, 1000
function isClient() return client end
function getTimestampMs() return now end
function instanceof(object, kind) return object.kind == kind end
function getCell() return {getGridSquare=function(_, x,y,z) return cells[x..":"..y..":"..z] end} end
SafeHouse = {isSafehouseAllowInteract=function(s) return not s.noInteract end,
    isSafehouseAllowLoot=function(s) return not s.noLoot end}
Fluid = {Water="water"}
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
local function object(s, items)
    local o = {items=items or {},kind="IsoObject"}
    function o:hasWater() return self.water == true end
    function o:getFluidAmount() return self.empty and 0 or 5 end
    function o:isTaintedWater() return self.tainted == true end
    function o:getFluidContainer() return self.fluid end
    function o:getPrimaryFluid() return self.otherFluid and "other" or Fluid.Water end
    function o:getContainerCount() return 1 end
    function o:getContainerByIndex() return {getItems=function() return list(self.items) end} end
    function o:isLockedToCharacter() return self.locked == true end
    function o:getItem() return self.item end
    s.objects[#s.objects+1]=o
    return o
end
local origin = square(0,0)
local player = {square=origin,getSquare=function(self) return self.square end}
local Nearby = require "AutoMindful/Nearby"
local adjacent = object(square(1,0),{{food=true}})
local far = object(square(8,0),{{food=true,book=true}})
local near = object(square(3,0),{{food=true}})
assert(Nearby.find(player,"food",origin,10).key=="3:0:0", "nearest non-adjacent supply")
assert(Nearby.find(player,"food",origin,10,{["3:0:0"]=true}).key=="8:0:0", "rejected target skipped")
assert(Nearby.find(player,"food",origin,10,{["3:0:0"]=999}).key=="3:0:0", "expired rejection retried")
near.items[1].unsafe=true
assert(Nearby.find(player,"food",origin,10).key=="8:0:0", "unsafe food skipped")
assert(not Nearby.find(player,"food",origin,5), "radius honored")
object(square(7,8),{{food=true}})
object(square(2,0,1),{{food=true}})
far.items={}
assert(not Nearby.find(player,"food",origin,10), "circle excludes corner and other floor")
far.items={{book=true,cooldown=true}}
assert(not Nearby.find(player,"literature",origin,10), "cooldown excluded")
far.items[1].cooldown=false
assert(Nearby.find(player,"literature",origin,10).key=="8:0:0", "eligible book found")
local sinkSquare=square(4,0)
local sink=object(sinkSquare); sink.water=true
assert(Nearby.find(player,"water",origin,10,nil,true).key=="4:0:0", "world water found")
sink.tainted=true
assert(not Nearby.find(player,"water",origin,10,nil,true), "tainted water excluded")
sink.tainted=false; sink.kind="IsoThumpable"; sink.locked=true
assert(not Nearby.find(player,"water",origin,10,nil,true), "locked source excluded")
sink.locked=false; client=true; sinkSquare.noInteract=true
assert(not Nearby.find(player,"water",origin,10,nil,true), "safehouse interaction respected")
sinkSquare.noInteract=false
local nearSquare=cells["3:0:0"]; near.items={{food=true}}; nearSquare.noLoot=true
assert(not Nearby.find(player,"food",origin,5), "safehouse loot respected")
nearSquare.noLoot=false
assert(Nearby.find(player,"food",origin,5).key=="3:0:0")
near.items={{water=true}}; sink.water=false
assert(not Nearby.find(player,"water",origin,10,nil,true), "world-only does not collect food or drink")
assert(Nearby.find(player,"water",origin,10).key=="3:0:0")
player.square=square(5,0)
assert(Nearby.find(player,"literature",origin,10).key=="8:0:0", "origin remains search anchor")
player.square=square(0,0,1)
assert(not Nearby.find(player,"literature",origin,10), "floor change stops discovery")
print("Nearby discovery contracts passed")
