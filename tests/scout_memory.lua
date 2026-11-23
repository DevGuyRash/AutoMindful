-- Explicit world/adapter doubles only. Run in Lua 5.1 or the installed Kahlua
-- verifier. Controller, stock pathfinding, safehouses and MP are not simulated.
package.path="mods/AutoMindful/common/media/lua/client/?.lua;"..package.path
local M=require "AutoMindful/ScoutMemory"
local cells, reads, calls
local function lookup(x,y,z) return x..":"..y..":"..z end
function getCell()
    return {getGridSquare=function(_,x,y,z)
        reads=reads+1; return cells[lookup(x,y,z)]
    end}
end
function instanceof(o, ty)
    return o and (o.javaType==ty or (ty=="IsoObject") or (ty=="IsoMovingObject" and o.moving)) or false
end
local function square(x,y,z)
    local s={x=x,y=y,z=z or 0,list={}}
    function s:getX()return self.x end
    function s:getY()return self.y end
    function s:getZ()return self.z end
    function s:getObjects()
        return {size=function()return #self.list end, get=function(_,i)return self.list[i+1]end,
            contains=function(_,o)for _,v in ipairs(self.list) do if o==v then return true end end;return false end}
    end
    cells[lookup(s.x,s.y,s.z)]=s
    return s
end
local function object(s, spec)
    local o=spec or {}
    o.square,o.javaType=s,o.javaType or "IsoObject"
    o.tile,o.type,o.props=o.tile or "fixtures_bathroom_01_0",o.type or "IsoObject",o.props or {GroupName="Fancy",Facing="S"}
    function o:getSquare()return self.square end
    function o:getMasterObject()return self.master or self end
    function o:getObjectName()return self.type end
    function o:getSprite()return {getName=function()return self.tile end,
        getProperties=function()return {get=function(_,k)return self.props[k]end}end} end
    s.list[#s.list+1]=o
    return o
end
local function entry(kind,o)
    return {kind=kind,object=o,square=o.square,key=kind..":fresh"}
end
local function resolve(kind,o,s)
    calls=calls+1
    if o.blocked or o.dry then return nil end
    local e=entry(kind,o)
    assert(e.square==s)
    return e
end
local home
local n=0
local function test(name,f)
    cells={};reads=0;calls=0;home=square(0,0,0)
    f();n=n+1;print("PASS "..name)
end
local function pick(mem,kind,r,now,fn,s)
    return M.choose(mem,kind,s or home,r or 10,now or 1000,fn or resolve)
end

test("remember only primitive hints and re-resolve exactly despite tile object list order",function()
    local mem={}
    local s=square(3,4)
    local o=object(s)
    local original=entry("restroom",o); original.care={object=o,front=home}
    assert(M.remember(mem,original,300))
    local deco=object(s,{tile="decor_0"});s.list={deco,o}
    local a,d=pick(mem,"restroom",5)
    assert(a and a.object==o and a~=original and a.key=="restroom:fresh" and d==25 and calls==1)
    for _,v in pairs(mem.restroom[1]) do assert(type(v)=="number" or type(v)=="string" or type(v)=="boolean") end
end)
test("unloaded/moved tiles, radius and floor fail closed; a later load can restore a hint",function()
    local mem={}
    local s=square(3,4);local o=object(s)
    local upstairs=square(3,4,1)
    assert(M.remember(mem,entry("restroom",o),200))
    local before=reads;assert(not pick(mem,"restroom",4));assert(reads-before==1 and calls==0)
    assert(not pick(mem,"restroom",5,1000,nil,upstairs));assert(calls==0)
    cells[lookup(3,4,0)]=nil
    assert(not pick(mem,"restroom",5) and #mem.restroom==1 and calls==0)
    -- A detached object and square must not qualify, even if both still exist.
    assert(not M.remember(mem,entry("restroom",o),240))
    local loaded=square(3,4);local live=object(loaded)
    local a=pick(mem,"restroom",5)
    assert(a and a.object==live and a.object~=o and a.square~=s)
end)
test("removed/fingerprint changes and otherwise indistinguishable copies never guess",function()
    local mem={}
    local s=square(1,0);local o=object(s)
    assert(M.remember(mem,entry("restroom",o),100))
    local other=object(s)
    assert(not pick(mem,"restroom") and calls==0 and #mem.restroom==0)
    assert(not M.remember(mem,entry("restroom",o),101))
    s.list={other};assert(M.remember(mem,entry("restroom",other),102))
    other.props={GroupName="Fancy",Facing="E"}
    assert(not pick(mem,"restroom") and #mem.restroom==0)
    assert(M.remember(mem,entry("restroom",other),103))
    s.list={}; object(s,{tile="new_sprite"})
    assert(not pick(mem,"restroom") and #mem.restroom==0 and calls==0)
end)
test("stale permissions, bad resolver result and exact object disappearing during observation",function()
    local mem={}
    local s=square(2,0);local o=object(s)
    assert(M.remember(mem,entry("water",o),200))
    o.blocked=true;assert(not pick(mem,"water") and #mem.water==1);o.blocked=false
    o.dry=true;assert(not pick(mem,"water") and #mem.water==1);o.dry=false
    assert(not pick(mem,"water",nil,nil,function() return {object=o,square=home} end))
    assert(not pick(mem,"water",nil,nil,function() return {object=o,square=s,kind="restroom"} end))
    assert(not pick(mem,"water",nil,nil,function() error("native permission probe unavailable") end))
    assert(pick(mem,"water").object==o)
    local a=pick(mem,"water",nil,nil,function()
        s.list={};local replacement=object(s)
        return entry("water",replacement)
    end)
    assert(not a,"Never replace the exact candidate inside the resolver")
end)
test("static scope excludes loot, loose bottles, corpses and all vehicle or side-part IDs",function()
    local mem={}
    local s=square(1,0);local o=object(s)
    for _,k in ipairs({"food","pain","literature","vehicle","unknown"}) do
        assert(not M.remember(mem,entry(k,o),200))
    end
    for _,k in ipairs({"item","part","ground","unknown","vehicle","container"}) do
        local e=entry("water",o);e[k]={};assert(not M.remember(mem,e,200))
    end
    local deco=object(s,{tile="trough_other_end",master=o})
    local bottle=object(s,{tile="bottle",javaType="IsoWorldInventoryObject"})
    local car=object(s,{tile="car",javaType="BaseVehicle",moving=true})
    local corpse=object(s,{tile="corpse",javaType="IsoDeadBody",moving=true})
    for _,x in ipairs({deco,bottle,car,corpse})do assert(not M.remember(mem,entry("water",x),200))end
    s.list={};assert(not M.remember(mem,entry("restroom",o),200))
    s.list={o}
    local water=entry("water",o);water.part=o
    assert(M.remember(mem,water,200) and pick(mem,"water").object==o)
    assert(not M.remember(mem,entry("restroom",object(square(0,10),{tile=""})),200))
end)
test("distance precedes recency, cooldown can reject nearest, memory capped/TTL and player-local",function()
    local mem,other={},{}
    local o1=object(square(1,0))
    local o2=object(square(-1,0))
    local o3=object(square(2,-2))
    local o4=object(square(1,3))
    local o5=object(square(7,2))
    assert(M.remember(mem,entry("hygiene",o3),10));assert(M.remember(mem,entry("hygiene",o1),11))
    assert(M.remember(mem,entry("hygiene",o2),12));assert(M.remember(mem,entry("hygiene",o4),13))
    assert(pick(mem,"hygiene").object==o2) -- equal distance: last verified
    o2.blocked=true;assert(pick(mem,"hygiene").object==o1);o2.blocked=false
    assert(M.remember(mem,entry("hygiene",o5),14));assert(#mem.hygiene==4)
    assert(M.remember(mem,entry("hygiene",o2),15));assert(#mem.hygiene==4 and mem.hygiene[1].at==15)
    assert(not pick(other,"hygiene") and not pick(mem,"water"))
    assert(not pick(mem,"hygiene",10,2*60*60*1000+15) and #mem.hygiene==0)
    assert(M.remember(mem,entry("hygiene",o1),20000))
    assert(not pick(mem,"hygiene",10,10000) and #mem.hygiene==0)
end)

local function sampleAt(s,ms) return {x=s.x,y=s.y,z=s.z,ms=ms} end

local function storage(o, kind)
    local c={object=o,kind=kind}
    o.storage=o.storage or {}
    o.storage[#o.storage+1]=c
    function c:getParent()return self.object end
    function c:getSourceGrid()return self.object.square end
    function c:getType()return self.kind end
    function o:getContainerCount()return #self.storage end
    function o:getContainerByIndex(i)return self.storage[i+1]end
    return c,{getContainer=function()return c end}
end
local function exactStorage(kind,o,s,c)
    calls=calls+1
    if c and not c.denied then return {kind=kind,object=o,square=s,container=c} end
end
test("only a fixed typed container is saved; newest verified book stop wins without probing older shelves",function()
    local mem={}
    local a,b=object(square(2,0)),object(square(4,0))
    local c1,book1=storage(a,"shelves")
    local c2,book2=storage(b,"crate")
    assert(M.remember(mem,M.supplyTarget("literature",book1),100))
    assert(M.remember(mem,M.supplyTarget("literature",book2),101))
    local result=pick(mem,"literature",6,200,exactStorage)
    assert(result and result.container==c2 and calls==1 and M.liveStorage(result))
    assert(not pick(mem,"food",6,200,exactStorage),"Never reuse a bookshelf proof for different care")
    for _,value in pairs(mem.literature[1]) do
        assert(type(value)=="number" or type(value)=="string" or type(value)=="boolean")
    end
    assert(pick(mem,"literature",3,200,exactStorage).container==c1)
    c2.denied=true
    assert(pick(mem,"literature",6,200,exactStorage).container==c1)
end)
test("reloading resolves the exact slot/type; changed identity, duplicates and explicit misses expire only that hint",function()
    local mem={}
    local s=square(3,0)
    local o=object(s)
    storage(o,"pantry")
    local c,book=storage(o,"bookshelf")
    assert(M.remember(mem,M.supplyTarget("literature",book),100))
    local first=pick(mem,"literature",6,200,exactStorage)
    assert(first.container==c and mem.literature[1].slot==1 and M.liveStorage(first))
    local replacement=square(3,0)
    local fresh=object(replacement)
    storage(fresh,"pantry")
    local restored=storage(fresh,"bookshelf")
    assert(not M.liveStorage(first))
    local second=pick(mem,"literature",6,200,exactStorage)
    assert(second.container==restored and second.object==fresh and M.liveStorage(second))
    assert(not pick(mem,"literature",6,200,function()return nil,true end) and #mem.literature==0)
    assert(M.remember(mem,second,201))
    fresh.storage[2].kind="different"
    assert(not M.liveStorage(second) and not pick(mem,"literature",6,300,exactStorage) and #mem.literature==0)
    fresh.storage[2].kind="bookshelf"
    assert(M.remember(mem,second,301))
    local recalled=pick(mem,"literature",6,400,exactStorage)
    M.forget(mem,recalled)
    assert(#mem.literature==0)
    fresh.storage[2].getContainingItem=function()return {}end
    assert(not M.remember(mem,second,402))
end)

test("a farther fixture wins when its verified round trip was quicker from this exact tile",function()
    local mem={}
    local near,far=object(square(2,0)),object(square(5,0))
    local offset=square(0,1)
    assert(M.remember(mem,entry("restroom",near),100,sampleAt(home,12000)))
    assert(M.remember(mem,entry("restroom",far),101,sampleAt(offset,3000)))
    assert(pick(mem,"restroom").object==near,"Other origin's time is not comparable")
    assert(M.remember(mem,entry("restroom",far),102,sampleAt(home,6000)))
    local target,d=pick(mem,"restroom")
    assert(target.object==far and d==25)
    assert(pick(mem,"restroom",3).object==near,"Faster does not expand the range")
    assert(pick(mem,"restroom",nil,nil,nil,offset).object==near,"Unmeasured nearest still wins from the adjacent origin")
    local otherFloor=square(0,0,1)
    assert(not pick(mem,"restroom",nil,nil,nil,otherFloor))
    far.blocked=true;assert(pick(mem,"restroom").object==near)
    far.blocked=false
    cells[lookup(5,0,0)]=nil;assert(pick(mem,"restroom").object==near)
end)

test("unknown nearest keeps proximity; sample ties use distance then last verified",function()
    local mem={}
    local near,far,twin=object(square(2,0)),object(square(5,0)),object(square(0,-2))
    assert(M.remember(mem,entry("hygiene",near),100))
    assert(M.remember(mem,entry("hygiene",far),101,sampleAt(home,10)))
    assert(pick(mem,"hygiene").object==near,"An unknown nearer walk is not assumed slower")
    assert(M.remember(mem,entry("hygiene",near),102,sampleAt(home,10)))
    assert(pick(mem,"hygiene").object==near,"Equal measured times favor nearer")
    assert(M.remember(mem,entry("hygiene",twin),103,sampleAt(home,10)))
    assert(pick(mem,"hygiene").object==twin,"Equal measured times and distances favor last verified")
end)

test("direct fixture use preserves old samples but cannot refresh their independent TTL",function()
    local mem={}
    local near,far=object(square(2,0)),object(square(4,0))
    local ttl=2*60*60*1000
    local source=sampleAt(home,250)
    assert(M.remember(mem,entry("water",near),100,sampleAt(home,3000)))
    assert(M.remember(mem,entry("water",far),101,source))
    source.ms=9000
    assert(pick(mem,"water").object==far,"Store an immutable copy of the supplied timing")
    assert(M.remember(mem,entry("water",near),ttl-1))
    assert(M.remember(mem,entry("water",far),ttl))
    assert(pick(mem,"water",nil,ttl+1).object==far)
    assert(pick(mem,"water",nil,ttl+101).object==near)
    assert(#mem.water==2 and not mem.water[1].times and not mem.water[2].times)
end)

test("new measurements replace only that origin; malformed ones and old excess origins are ignored",function()
    local mem={}
    local o=object(square(2,0))
    local t=entry("water",o)
    for i=1,6 do assert(M.remember(mem,t,i,{x=i,y=0,z=0,ms=i*500})) end
    assert(#mem.water[1].times==4 and mem.water[1].times[4].x==3)
    assert(M.remember(mem,t,7,{x=4,y=0,z=0,ms=777}))
    assert(#mem.water[1].times==4 and mem.water[1].times[1].x==4 and mem.water[1].times[1].ms==777)
    for _,bad in ipairs({{x=4,y=0,z=0,ms=0},{x=4,y=0,z=0,ms=-5},{x=4,y=0,z=0,ms=math.huge},
            {x=4.5,y=0,z=0,ms=100},{x=4,y=0,z=1,ms=100},{x=4,y=0,z=0,ms="200"}, {ms=50}}) do
        assert(M.remember(mem,t,8,bad))
        assert(#mem.water[1].times==4 and mem.water[1].times[1].ms==777 and mem.water[1].times[1].at==7)
    end
    for _,t in ipairs(mem.water[1].times) do for _,n in pairs(t) do assert(type(n)=="number") end end
end)

print("scouting fixture memory: "..n.." passed; no save, route, receipt, or permission emulation")
