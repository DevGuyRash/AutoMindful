package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. (package.path or "")
local Fixtures = loadTest and loadTest("fluid_fixtures.lua") or assert(loadfile("tests/fluid_fixtures.lua"))()
FluidCategory = Fixtures.categories
for _, name in ipairs({"Fluids/ISFluidContainer", "Fluids/ISFluidUtil", "Fluids/ISFluidTransferAction",
        "ISBaseObject", "TimedActions/ISBaseTimedAction"}) do package.loaded[name] = true end

function instanceof(value, kind)
    if not value then return false end
    if kind == "InventoryItem" then return value.kind == "InventoryItem" or value.kind == "Food" or value.kind == "Clothing" end
    if kind == "IsoObject" then return value.kind == "IsoObject" or value.kind == "IsoWorldInventoryObject" end
    return value.kind == kind
end
function isClient() return false end
function isServer() return false end
Metabolics = {LightDomestic=1, HeavyDomestic=2, MediumWork=3}
FluidUtil = {getTransferActionTimePerLiter=function() return 30 end, getMinTransferActionTime=function() return 15 end}
local queue = {}
ISTimedActionQueue = {add=function(action) queue[#queue + 1] = action end}
local player = {isTimedActionInstant=function() return false end, setMetabolicTarget=function() end,
    faceThisObject=function() end}
function getPlayer() return {getInventory=function() return {containsID=function() return false end} end} end
ISBaseObject = {}
function ISBaseObject:derive(name)
    local result = {Type=name};result.__index=result
    return setmetatable(result,{__index=self})
end
function ISBaseObject:new() return {} end
ISBaseTimedAction = ISBaseObject:derive("ISBaseTimedAction")
function ISBaseTimedAction:new(character) return setmetatable({character=character},self) end
function ISBaseTimedAction:perform() end
function ISBaseTimedAction:stop() end

local function inventoryItem(kind)
    local item = {kind=kind or "InventoryItem", owned=true, flags={}}
    function item:isInPlayerInventory() return self.owned end
    function item:getID() return 1 end
    function item:getWorldItem() return self.world end
    function item:getFluidContainer() return self.fluid end
    function item:isSealed() return self.sealed == true end
    function item:isWorn() return self.worn == true end
    function item:syncItemFields() self.synced = (self.synced or 0) + 1 end
    function item:isCooked() return true end
    for _, method in ipairs({"isRotten", "isBurnt", "isFrozen", "isTainted", "isPoison", "isAlcoholic", "isbDangerousUncooked"}) do
        item[method] = function(self) return self.flags[method] == true end
    end
    function item:getPoisonPower() return 0 end
    function item:getFoodSicknessChange() return 0 end
    return item
end
local function fluid(owner, amount, capacity, components)
    local container = {kind="FluidContainer", amount=amount, capacity=capacity, components=components or {}}
    function container:getAmount() return self.amount end
    function container:getCapacity() return self.capacity end
    function container:isEmpty() return self.amount <= 0 end
    function container:isFull() return self.amount >= self.capacity end
    function container:isPoisonous() return self.poison == true end
    function container:isTainted() return self.tainted == true end
    function container:canPlayerEmpty() return not self.cannotEmpty end
    function container:getProperties()
        local hunger,thirst=0,0
        for _, entry in ipairs(self.components) do
            hunger=hunger+(entry.fluid.hunger or 0)*entry.percentage*self.amount
            thirst=thirst+(entry.fluid.thirst or 0)*entry.percentage*self.amount
        end
        return {getHungerChange=function() return hunger end, getThirstChange=function() return thirst end,
            getCalories=function() return 100*self.amount end, getPoison=function() return 0 end,
            getAlcohol=function() return 0 end, getFoodSicknessChange=function() return 0 end}
    end
    Fixtures.attach(container, nil, function(self) return self.components end)
    container.owner=owner
    if owner then owner.fluid=container end
    return container
end
local function safeComponents(hunger, thirst)
    return {{fluid=Fixtures.component({hunger=-(hunger or 0),thirst=-(thirst or 0.5)}),percentage=1}}
end
FluidContainer = {}
function FluidContainer.CanTransfer(source,target)
    return source ~= target and not source:isEmpty() and not target:isFull()
        and not target:isInputLocked() and not target.blockTransfer
end
function FluidContainer.Transfer(source,target,amount)
    local moved=math.min(amount,source.amount,target:getFreeCapacity())
    if target:isEmpty() then target.components=source.components end
    source.amount,target.amount=source.amount-moved,target.amount+moved
end

local native=false
if not loadUpstream and arg and arg[1] then
    local reference=arg[1]
    function loadUpstream(name) return assert(loadfile(reference.."/lua/"..name))() end
end
if loadUpstream then
    loadUpstream("shared/Fluids/ISFluidContainer.lua")
    loadUpstream("shared/Fluids/ISFluidUtil.lua")
    loadUpstream("shared/Fluids/ISFluidTransferAction.lua")
    native=true
else
    ISFluidContainer = ISBaseObject:derive("ISFluidContainer")
    function ISFluidContainer:new(container) return setmetatable({fluidContainer=container},self) end
    function ISFluidContainer:getFluidObject() return self.fluidContainer end
    function ISFluidContainer:getFluidContainer() return self.fluidContainer end
    function ISFluidContainer:getOwner() return self.fluidContainer:getOwner() end
    function ISFluidContainer:sync()
        local owner=self:getOwner()
        if instanceof(owner,"IsoObject") then owner:sync() else owner:syncItemFields() end
    end
    ISFluidTransferAction = ISBaseTimedAction:derive("ISFluidTransferAction")
    function ISFluidTransferAction:new(character,sourceContainer,sourceFluidObject,targetContainer,targetFluidObject,amount)
        return setmetatable({character=character,source=sourceContainer,target=targetContainer,
            sourceFluidObject=sourceFluidObject,targetFluidObject=targetFluidObject,
            sourceStartAmount=sourceFluidObject:getAmount(),amount=amount},self)
    end
    function ISFluidTransferAction:isValid()
        local sourceOwner,targetOwner=self.source:getOwner(),self.target:getOwner()
        local sourceAvailable=instanceof(sourceOwner,"IsoObject") and sourceOwner:isExistInTheWorld()
            or instanceof(sourceOwner,"InventoryItem") and sourceOwner:isInPlayerInventory()
        return sourceAvailable and targetOwner:isInPlayerInventory()
            and FluidContainer.CanTransfer(self.sourceFluidObject,self.targetFluidObject)
    end
    function ISFluidTransferAction:complete()
        FluidContainer.Transfer(self.sourceFluidObject,self.targetFluidObject,self.amount)
        self.source:sync();self.target:sync();return true
    end
end
local Fluids = require "AutoMindful/Fluids"
local passed=0
local function near(actual,expected) assert(math.abs(actual-expected)<0.000001,tostring(actual).." differs from "..tostring(expected)) end
local function test(name,run) queue={};run();passed=passed+1;print("PASS fluid transfer "..name) end

test("safe milk and water mixture exposes current effects and a projected portion",function()
    local components={{fluid=Fixtures.component({hunger=-0.5,thirst=-0.5}),percentage=0.5},
        {fluid=Fixtures.component({thirst=-0.5}),percentage=0.5}}
    local source=fluid(inventoryItem(),1,5,components)
    local description=assert(Fluids.inspect(source))
    assert(description.food and description.water and source.lastSample.released)
    near(description.hungerEffect,0.25);near(description.thirstEffect,0.5)
    local portion=Fluids.project(description,0.4)
    near(portion.hungerEffect,0.1);near(portion.thirstEffect,0.2);near(portion.remainingLiters,0.4)
    near(source.amount,1)
end)
test("diluted unsafe constituents are rejected even when aggregate sickness is absent",function()
    for _, bad in ipairs({{sickness=1},{poisonous=true},{poison=0.001},{alcohol=0.001},
            {categories={[FluidCategory.Beverage]=true,[FluidCategory.Hazardous]=true}},
            {categories={[FluidCategory.Beverage]=true,[FluidCategory.Alcoholic]=true}},{categories={}}}) do
        local source=fluid(inventoryItem(),1,5,{{fluid=Fixtures.component(),percentage=0.999999},
            {fluid=Fixtures.component(bad),percentage=0.000001}})
        assert(not Fluids.inspect(source) and source.lastSample.released)
    end
    local tainted=fluid(inventoryItem(),1,5,safeComponents());tainted.tainted=true
    assert(not Fluids.inspect(tainted))
end)
test("allocated samples are released even when a component API fails",function()
    local source=fluid(inventoryItem(),1,5,{{fluid=Fixtures.component({propertiesError="sample failure"}),percentage=1}})
    local succeeded=pcall(Fluids.safe,source)
    assert(not succeeded and source.lastSample.released)
end)
test("only clean empty drinkable vessels are eligible",function()
    local owner=inventoryItem();local target=fluid(owner,0,1)
    assert(Fluids.emptyVessel(owner))
    target.amount=0.1;assert(not Fluids.emptyVessel(owner));near(target.amount,0.1)
    target.amount=0;target.inputLocked=true;assert(not Fluids.emptyVessel(owner))
    target.inputLocked=false;owner.sealed=true;assert(not Fluids.emptyVessel(owner))
    owner.sealed=false;target.capacity=5;assert(not Fluids.emptyVessel(owner))
    owner.worn=true;assert(Fluids.emptyVessel(owner))
    local rotten=inventoryItem("Food");rotten.flags.isRotten=true;fluid(rotten,0,1)
    assert(not Fluids.emptyVessel(rotten))
end)
test("the actual world component is used while an item is on the ground",function()
    local item=inventoryItem();local world={kind="IsoWorldInventoryObject",getItem=function() return item end}
    local source=fluid(world,5,5,safeComponents())
    function world:getFluidContainer() return source end
    item.world=world;item.fluid=nil
    assert(Fluids.container(item)==source)
    item.world=nil;item.fluid=source;source.owner=item
    assert(Fluids.container(item)==source)
end)
test("native transfer receives current raw objects and measured liters",function()
    local source=fluid(inventoryItem(),5,5,safeComponents(0.5,0.5))
    local target=fluid(inventoryItem(),0,1)
    assert(Fluids.transfer(player,source,target,0.4,function() return true end))
    assert(#queue==1 and queue[1].Type=="ISFluidTransferAction")
    local action=queue[1]
    assert(action.sourceFluidObject==source and action.targetFluidObject==target)
    near(action.amount,0.4);near(source.amount,5);near(target.amount,0)
    if native then
        function action:getJobDelta() return 0.5 end
        action:update()
        near(target.amount,0.2)
        assert(action:isValid(),"Partial filling must not invalidate the original empty-vessel requirement")
    end
    assert(action:complete());near(source.amount,4.6);near(target.amount,0.4)
    assert(source:getOwner().synced and target:getOwner().synced)
end)
test("native capacity and source amount bound requested transfers",function()
    local source=fluid(inventoryItem(),0.2,5,safeComponents())
    local target=fluid(inventoryItem(),0,0.1)
    assert(Fluids.transfer(player,source,target,0.4));near(queue[1].amount,0.1)
end)
test("world fluid sources use native wrappers and retain caller reach checks",function()
    local owner={kind="IsoObject",exists=true,sync=function(self) self.synced=true end,
        isExistInTheWorld=function(self) return self.exists end}
    local source=fluid(owner,5,5,safeComponents(0.5,0.5))
    local target=fluid(inventoryItem(),0,1)
    local reachable=true
    assert(Fluids.transfer(player,source,target,0.4,function() return reachable end))
    local action=queue[1]
    assert(action:isValid())
    reachable=false;assert(not action:isValid())
    near(source.amount,5);near(target.amount,0)
    reachable=true;assert(action:isValid())
    assert(action:complete());near(source.amount,4.6);near(target.amount,0.4)
    assert(owner.synced and target:getOwner().synced)
end)
test("existing contents and locked sources are left unchanged",function()
    local source=fluid(inventoryItem(),5,5,safeComponents())
    local target=fluid(inventoryItem(),0.2,1,safeComponents())
    assert(not Fluids.transfer(player,source,target,0.4) and #queue==0)
    near(source.amount,5);near(target.amount,0.2)
    target.amount=0;source.cannotEmpty=true
    assert(not Fluids.transfer(player,source,target,0.4) and #queue==0)
end)
test("compatibility and changing reachability prevent native queuing or continuation",function()
    local source=fluid(inventoryItem(),5,5,safeComponents())
    local target=fluid(inventoryItem(),0,1);target.blockTransfer=true
    assert(not Fluids.transfer(player,source,target,0.4) and #queue==0)
    target.blockTransfer=false;local reachable=true
    assert(Fluids.transfer(player,source,target,0.4,function() return reachable end))
    reachable=false;assert(not queue[1]:isValid())
    near(source.amount,5);near(target.amount,0)
end)
test("live source and destination mixtures remain guarded",function()
    local source=fluid(inventoryItem(),5,5,safeComponents())
    local target=fluid(inventoryItem(),0,1)
    assert(Fluids.transfer(player,source,target,0.4))
    source.components={{fluid=Fixtures.component({sickness=1}),percentage=1}}
    assert(not queue[1]:isValid())
    source.components=safeComponents();target.components={{fluid=Fixtures.component({poisonous=true}),percentage=1}};target.amount=0.01
    assert(not queue[1]:isValid())
end)
print("FLUID TRANSFERS PASS "..passed.." cases; "..(native and "installed native action" or "native action boundary double"))
