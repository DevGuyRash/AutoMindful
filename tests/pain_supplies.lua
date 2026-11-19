package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
for _, name in ipairs({"ISUI/ISInventoryPaneContextMenu","TimedActions/ISInventoryTransferUtil","TimedActions/ISDropWorldItemAction"}) do
    package.loaded[name]=true
end
-- Supply tests exercise real discovery/ranking, with deliberately explicit game and stock classification boundaries.
package.loaded["AutoMindful/PainCare"]={eligible=function(item) return item.medication==true and not item.empty end}
package.loaded["AutoMindful/Consumables"]={inspect=function(_,item)
    assert(not (item.medication and not item.empty), "A qualifying pain bottle is not edible food or fluid")
    return {food=item.food==true}
end}
package.loaded["AutoMindful/Fluids"]={container=function() end,emptyVessel=function() return false end}
package.loaded["AutoMindful/WaterSources"]={scan=function() return {} end}
local radiusSquares, areaContainers, clock, online = {}, {}, 1000, false
local function list(v)
    return {size=function()return #v end,get=function(_,i)return v[i+1]end}
end
function isClient() return online end
function getTimestampMs() return clock end
function instanceof(item,kind) return item and item.kind==kind end
function getPlayerInventory() return {} end
function getPlayerLoot() return {refreshBackpacks=function()end} end
function getCell() return {getGridSquare=function(_,x,y,z)return radiusSquares[x..":"..y..":"..z]end}end
ISInventoryPaneContextMenu={getContainers=function()return list(areaContainers)end}
SafeHouse={isSafehouseAllowInteract=function(s)return not s.deny end,isSafehouseAllowLoot=function(s)return not s.noLoot end}
SandboxVars={Yoga={}}
local function square(x,y,z)
    local s={x=x,y=y,z=z,objects={}}
    function s:getX()return self.x end
    function s:getY()return self.y end
    function s:getZ()return self.z end
    function s:getObjects()return list(self.objects)end
    function s:getWorldObjects()return list({})end
    function s:canReachTo(target)return not target.wall end
    radiusSquares[x..":"..y..":"..z]=s
    return s
end
local function container(s,kind)
    local c={square=s,kind=kind,items={},explored=true}
    function c:getSourceGrid()return self.square end
    function c:getType()return self.kind end
    function c:getItems()return list(self.items)end
    function c:getOutermostContainer()return self end
    function c:isExplored()return self.explored end
    function c:getContainingItem()end
    function c:hasRoomFor()return not self.full end
    function c:getParent()end
    function c:getVehiclePart()end
    return c
end
local function stockObject(s,c)
    local obj={}
    function obj:hasWater()return false end
    function obj:getContainerCount()return 1 end
    function obj:getContainerByIndex()return c end
    s.objects[#s.objects+1]=obj
end
local id=0
local function put(c,kind,medication,empty)
    id=id+1
    local i={kind=kind,medication=medication,empty=empty,id=id,container=c}
    function i:getContainer()return self.container end
    function i:getID()return self.id end
    function i:hasModData()return false end
    c.items[#c.items+1]=i
    return i
end
local home, adjacent, distant, upper, hidden = square(0,0,0),square(1,0,0),square(5,0,0),square(2,0,1),square(3,0,0)
local p={inventory=container(home,"inventory")}
function p:getSquare()return home end
function p:getInventory()return self.inventory end
function p:getPlayerNum()return 0 end
function p:tooDarkToRead()return false end
function p:getModData()return {} end
local bag=put(p.inventory,"InventoryContainer")
bag.inventory=container(home,"bag")
function bag:getInventory()return self.inventory end
local cabinet=container(adjacent,"cabinet")
local known=container(distant,"cabinet")
local unknown=container(hidden,"cabinet");unknown.explored=false
stockObject(adjacent,cabinet);stockObject(distant,known);stockObject(hidden,unknown)
local upstairs=container(upper,"cabinet");stockObject(upper,upstairs)
areaContainers={cabinet}
local carried=put(bag.inventory,"Drainable",true)
local nearby=put(cabinet,"Drainable",true)
local far=put(known,"Drainable",true)
put(cabinet,"Drainable",true,true)
put(cabinet,"Food").food=true
put(upstairs,"Drainable",true)
local S=require "AutoMindful/Supplies"
local N=require "AutoMindful/Nearby"
assert(S.choose(p,"pain",false,{}).item==carried and S.choose(p,"pain",true,{}).item==carried)
local rejected={[carried.id]=clock+100}
assert(not S.choose(p,"pain",false,rejected) and S.choose(p,"pain",true,rejected).item==nearby)
p.inventory.full=true; assert(not S.choose(p,"pain",true,rejected));p.inventory.full=false
online=true;adjacent.noLoot=true
assert(not S.choose(p,"pain",true,rejected))
adjacent.noLoot=false;adjacent.wall=true
assert(not S.choose(p,"pain",true,rejected))
adjacent.wall=false;online=false
clock=clock+101
assert(S.choose(p,"pain",true,rejected).item==carried)
print("PASS carried bag first; accessible adjacent, rejection expiry, capacity, wall, no-loot")
local area=N.scan(p,home,10,true)
assert(#area.pain==2 and N.find(p,"pain",home,10,{}).item==far and #area.unknownTargets==1)
assert(not N.find(p,"pain",home,4,{}))
assert(not N.find(p,"pain",home,10,{["pain:5:0:0"]=true}))
online=true;distant.deny=true
assert(not N.find(p,"pain",home,10,{}) and #N.scan(p,home,10,true).pain==1)
online=false;distant.deny=false
assert(#area.food==1 and #area.water==0 and #area.literature==0)
local report=S.report(p,true,true,area,true)
assert(report.pain==1 and report.adjacentPain==1 and report.nearbyPain==2 and report.nearbyFood==1)
local noArea=S.report(p,false,false)
assert(noArea.pain==1 and noArea.adjacentPain==0 and noArea.nearbyPain==0)
print("PASS known same-floor/radius sources only; no unknown rummage; independent visible counts")

function p.inventory:getItemById(key)
    for _, item in ipairs(self.items) do if item.id==key then return item end end
end
function bag.inventory:getOutermostContainer() return p.inventory end
ISInventoryPaneContextMenu.getContainers=function()return {contains=function(_,origin)
    for _, c in ipairs(areaContainers) do if c==origin then return true end end
    return false
end}end
local queued
ISTimedActionQueue={add=function(action) queued=action end}
ISInventoryTransferUtil={newInventoryTransferAction=function(_,item,source,dest)
    return {item=item,source=source,dest=dest,isValid=function()return true end}
end}
ISDropWorldItemAction={new=function(_,player,item,dest)
    return {item=item,dest=dest,isValid=function()return true end}
end}
local loan={pain=true,origin=cabinet,original=nearby,items={nearby}}
assert(S.painLoanAllowed(p,nil,false))
assert(S.painLoanAllowed(p,{origin=bag.inventory,original=carried},false))
assert(not S.painLoanAllowed(p,loan,false) and S.painLoanAllowed(p,loan,true))
assert(S.transfer(p,nearby,loan) and queued.source==cabinet and queued:isValid())
local pickup=queued
nearby.container=known
assert(not pickup:isValid() and not S.transfer(p,nearby,loan) and queued==pickup)
nearby.container=cabinet
online=true;adjacent.noLoot=true
assert(not pickup:isValid() and not S.painLoanAllowed(p,loan,true))
nearby.container=p.inventory; p.inventory.items[#p.inventory.items+1]=nearby
local action,notice=S.returnAction(p,loan)
assert(not action and notice)
adjacent.noLoot=false
action,notice=S.returnAction(p,loan)
assert(action and not notice and action.dest==cabinet and action:isValid(),
    "Dose permission off does not prevent safe return")
adjacent.deny=true
assert(not action:isValid(), "Permission is rechecked while an exact return is queued")
adjacent.deny=false;online=false; areaContainers={}
assert(not S.painLoanAllowed(p,loan,true) and not action:isValid(),
    "An original container missing from the native nearby list cannot be reused")
print("PASS fresh pain-loan permissions and exact original container on pickup/dose/return")

local floor=container(nil,"floor")
local bottle=put(floor,"Drainable",true)
local worldSpot=adjacent
function bottle:getWorldItem() return {getSquare=function()return worldSpot end} end
local ground={pain=true,origin=floor,original=bottle,items={bottle},floor={square=adjacent,x=0,y=0,z=0}}
assert(S.transfer(p,bottle,ground) and queued:isValid())
worldSpot=home
assert(not queued:isValid(), "Moving an item within the native floor pseudo-container is not the original source")
bottle.container=p.inventory;p.inventory.items[#p.inventory.items+1]=bottle
action=S.returnAction(p,ground)
assert(action and action.dest==adjacent and action:isValid())
online=true;adjacent.noLoot=true
assert(not action:isValid() and not S.returnAction(p,ground))
print("PASS ground-item pickup and return use the original permitted square")
