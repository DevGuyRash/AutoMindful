package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
local Fixtures = loadTest and loadTest("fluid_fixtures.lua") or assert(loadfile("tests/fluid_fixtures.lua"))()
for _, name in ipairs({"ISUI/ISInventoryPaneContextMenu", "TimedActions/ISTakeWaterAction",
        "TimedActions/ISWaitWhileGettingUp", "TimedActions/ISWearClothing", "TimedActions/ISBaseTimedAction",
        "TimedActions/ISInventoryTransferUtil", "TimedActions/ISDropWorldItemAction",
        "Fluids/ISFluidContainer", "Fluids/ISFluidUtil", "Fluids/ISFluidTransferAction"}) do package.loaded[name] = true end

local function list(values)
    values.size = function(self) return #self end
    values.get = function(self, index) return self[index + 1] end
    return values
end

function instanceof(value, kind) return value and value.kind == kind end
local clock, client, cells, queue = 0, false, {}, {}
function getTimestampMs() return clock end
function isClient() return client end
function getCell() return {getGridSquare = function(_, x,y,z) return cells[x .. ":" .. y .. ":" .. z] end} end
Fluid = {Water = "water"}
FluidCategory = Fixtures.categories
CharacterStat = {THIRST = "thirst"}
FluidContainer = {DisposeContainer = function(container) container.disposed = true end}
SafeHouse = {isSafehouseAllowInteract = function(square) return not square.noInteract end,
    isSafehouseAllowLoot = function(square) return not square.noLoot end}
luautils = {getCorrectSquareForWall = function(_, square) return square.corrected or square end}
ISTimedActionQueue = {add = function(action) queue[#queue + 1] = action end}
ISWaitWhileGettingUp = {new = function(_, player) return {Type="get-up", character=player} end}
ISWearClothing = {new = function(_, player, item) return {Type="wear", character=player, item=item} end}
ISInventoryPaneContextMenu = {getEatingMask = function(player)
    if player.mask then queue[#queue + 1] = {Type="remove-mask"}; return player.mask end
end}

ISBaseTimedAction = {}
function ISBaseTimedAction:derive(name)
    local class = {Type = name}
    class.__index = class
    return setmetatable(class, {__index = self})
end
function ISBaseTimedAction:new(character) return setmetatable({character=character}, self) end
function ISBaseTimedAction:stop() end
function ISBaseTimedAction:perform() end

local nativeAction = false
if loadUpstream then
    loadUpstream("shared/TimedActions/ISTakeWaterAction.lua")
    nativeAction = true
elseif arg and arg[1] then
    dofile(arg[1] .. "/lua/shared/TimedActions/ISTakeWaterAction.lua")
    nativeAction = true
else
    ISTakeWaterAction = ISBaseTimedAction:derive("ISTakeWaterAction")
    function ISTakeWaterAction:new(player, item, object, tainted)
        return setmetatable({character=player, item=item, waterObject=object, waterTaintedCL=tainted}, self)
    end
    function ISTakeWaterAction:isValid() return self.waterObject:hasFluid() and not self.character:hasFullInventory() end
end

local Sources = require "AutoMindful/WaterSources"
local function square(x,y,z)
    local result = {x=x, y=y, z=z or 0, objects=list({}), world=list({})}
    function result:getX() return self.x end
    function result:getY() return self.y end
    function result:getZ() return self.z end
    function result:canReachTo(other) return not other.blocked end
    function result:getObjects() return self.objects end
    function result:getWorldObjects() return self.world end
    cells[x .. ":" .. y .. ":" .. result.z] = result
    return result
end

local function player()
    cells, queue, client = {}, {}, false
    local result = {square=square(0,0), thirst=0.25}
    function result:getSquare() return self.square end
    function result:getStats() return {get=function(_, _) return self.thirst end} end
    function result:hasFullInventory() return self.full == true end
    function result:isSitOnGround() return self.sitting == true end
    function result:isTimedActionInstant() return false end
    function result:DrinkFluid(container, percentage)
        assert(percentage == 1)
        self.thirst = math.max(0, self.thirst - container.amount * 0.5)
    end
    return result
end

local function source(where, ground)
    local result = {square=where, amount=2, kind=ground and "IsoWorldInventoryObject" or "IsoObject"}
    if ground then result.item = {isSealed=function() return result.sealed == true end,isWorn=function() return false end} end
    function result:getSquare() return self.square end
    function result:getMasterObject() return self.master or self end
    function result:hasWater() return self.amount > 0 and not self.otherFluid end
    function result:hasFluid() return self.amount > 0 end
    function result:getFluidAmount() return self.amount end
    function result:isTaintedWater() return self.tainted == true end
    function result:getItem() return self.item end
    function result:getPrimaryFluid() return self.otherFluid and "other" or Fluid.Water end
    function result:isLockedToCharacter() return self.locked end
    local container = Fixtures.attach({isEmpty=function() return result.amount <= 0 end,
            isPureFluid=function(_, expected) return expected == Fluid.Water and not result.otherFluid end,
            isPoisonous=function() return result.poison == true end,
            isTainted=function() return result.tainted == true end,
            canPlayerEmpty=function() return not result.cannotEmpty end,
            getAmount=function() return result.amount end,
            getCapacity=function() return result.capacity or 5 end,
            getProperties=function() return {getPoison=function() return result.poison and 1 or 0 end,
                getFoodSicknessChange=function() return result.sickness and 1 or 0 end,
                getAlcohol=function() return result.alcohol and 1 or 0 end,
                getHungerChange=function() return result.milk and -0.5*result.amount or 0 end,
                getThirstChange=function() return -0.5*result.amount end,
                getCalories=function() return 0 end} end}, result, function()
        local categories = result.otherFluid and not result.milk and {} or {[FluidCategory.Beverage]=true}
        return {{fluid=Fixtures.component({categories=categories}),percentage=1}}
    end)
    function result:getFluidContainer()
        if self.piped then return nil end
        return container
    end
    function result:moveFluidToTemporaryContainer(amount)
        amount = math.min(amount, self.amount)
        self.amount = self.amount - amount
        return {amount=amount}
    end
    local objects = ground and where.world or where.objects
    objects[#objects + 1] = result
    return result
end

local passed = 0
local function test(name, run)
    run()
    passed = passed + 1
    print("PASS " .. name)
end

test("plumbed fixtures use native remaining-water state", function()
    for _, name in ipairs({"sink", "bath", "toilet", "shower"}) do
        local p = player()
        local tap = source(square(1,0))
        tap.piped, tap.name, tap.amount = true, name, 10000
        assert(#Sources.scan(p) == 1)
        tap.amount = 0
        assert(#Sources.scan(p) == 0)
    end
end)

test("ground water stays in place without a portable size restriction", function()
    local p = player()
    local barrel = source(p.square, true)
    barrel.amount = 12
    local found = Sources.choose(p, {})
    assert(found.object == barrel and found.item == barrel.item)
    assert(Sources.drink(p, found))
    assert(#queue == 1 and queue[1].item == nil and queue[1].waterObject == barrel)
end)

test("safe world milk is offered for transfer rather than direct water drinking", function()
    local p = player()
    local bucket = source(p.square, true)
    bucket.milk, bucket.otherFluid, bucket.amount = true, true, 5
    local found = Sources.scan(p)
    assert(#found == 1 and found[1].object == bucket and not found[1].directDrink)
    assert(found[1].description.food and found[1].description.water and found[1].description.needsVessel)
    assert(not Sources.choose(p, {}) and not Sources.drink(p, found[1]) and #queue == 0)
    bucket.cannotEmpty = true
    assert(#Sources.scan(p) == 0)
end)

test("portable milk is left to ordinary item collection and drinking", function()
    local p = player()
    local bottle = source(p.square, true)
    bottle.milk, bottle.otherFluid, bottle.capacity = true, true, 1
    assert(#Sources.scan(p) == 0)
end)

test("selection prefers current remaining water rather than discovery order or capacity", function()
    local p = player()
    local small = source(p.square); small.amount, small.capacity = 0.5, 100
    local large = source(square(1,0)); large.amount, large.capacity = 5, 5
    local unsafe = source(square(0,1)); unsafe.amount, unsafe.tainted = 10000, true
    assert(Sources.choose(p, {}).object == large)
    large.amount = 0.1
    assert(Sources.choose(p, {}).object == small)
    large.amount = 10000
    assert(Sources.choose(p, {[large]=clock + 1000}).object == small)
    clock = clock + 1001
    assert(Sources.choose(p, {}).object == large)
end)

test("unsafe and sealed sources cannot enter the drink queue", function()
    for _, flag in ipairs({"tainted", "poison", "sickness", "alcohol", "otherFluid", "sealed"}) do
        local p = player()
        local water = source(p.square, true)
        water[flag] = true
        assert(#Sources.scan(p) == 0, flag)
        assert(not Sources.drink(p, {object=water}), flag)
        assert(#queue == 0)
    end
end)

test("reachability rejects walls, another floor, and walking targets", function()
    local p = player()
    local blocked = source(square(1,0)); blocked.square.blocked = true
    source(square(2,0))
    source(square(0,0,1))
    local wrongSide = source(square(0,1)); wrongSide.square.corrected = square(2,1)
    assert(#Sources.scan(p) == 0)
end)

test("multi-tile sources use the reachable native part once", function()
    local p = player()
    local master = source(square(2,0))
    local part = source(square(1,0)); part.master = master
    local otherPart = source(square(1,1)); otherPart.master = master
    local found = Sources.scan(p)
    assert(#found == 1 and found[1].object == master)
    assert(Sources.drink(p, found[1]))
    assert(#queue == 1 and queue[1].waterObject == master)
end)

test("safehouse and locked-object rules remain native boundaries", function()
    local p = player(); client = true
    local tap = source(square(1,0)); tap.square.noInteract = true
    local ground = source(p.square, true); p.square.noLoot = true
    local locked = source(square(0,1)); locked.kind, locked.locked = "IsoThumpable", true
    assert(#Sources.scan(p) == 0)
end)

test("standing, mouth equipment, validity and rejected-source retries are controlled", function()
    local p = player(); p.sitting, p.mask = true, "mask"
    local tap = source(p.square)
    assert(Sources.drink(p, {object=tap}))
    assert(queue[1].Type == "get-up" and queue[2].Type == "remove-mask")
    assert(queue[3].waterObject == tap and queue[4].Type == "wear" and queue[4].item == "mask")
    tap.poison = true
    assert(not queue[3]:isValid())
    tap.poison = false
    local rejected = {[tap]=clock + 1000}
    assert(not Sources.choose(p, rejected))
    clock = clock + 1001
    assert(Sources.choose(p, rejected))
    queue, p.full = {}, true
    local queued, reason = Sources.drink(p, {object=tap})
    assert(not queued and reason:find("room") and #queue == 0)
end)

test("nearby previews honor collection permission and avoid counting ground bottles twice", function()
    local p = player()
    local bottle = source(p.square, true)
    local barrel = source(p.square, true); barrel.amount = 12
    source(square(1,0))
    local inventory = {items=list({})}
    function inventory:getItems() return self.items end
    function inventory:getOutermostContainer() return self end
    function inventory:getType() return "inventory" end
    function p:getInventory() return inventory end
    function p:getPlayerNum() return 0 end
    function p:tooDarkToRead() return false end
    local floor = {getItems=function() return list({bottle.item, barrel.item}) end,
        getType=function() return "floor" end, getOutermostContainer=function(self) return self end}
    for _, object in ipairs({bottle, barrel}) do
        object.item.getWorldItem = function() return object end
    end
    function getPlayerInventory() return {} end
    function getPlayerLoot() return {refreshBackpacks=function() end} end
    ISInventoryPaneContextMenu.getContainers = function() return list({inventory, floor}) end
    package.loaded["AutoMindful/Consumables"] = {inspect=function(_, item)
        return {food=false, water=item == bottle.item}
    end}
    SandboxVars = {Yoga={RequiresMat=false}}
    local supplies = require "AutoMindful/Supplies"
    local preview = supplies.report(p, true, false)
    assert(preview.water == 0 and preview.nearbyWater == 3 and preview.nearbyWaterSourceCount == 3)
    assert(table.concat(preview.warnings, " "):find("collection is off"))
    local allowed = supplies.report(p, true, true)
    assert(allowed.nearbyWater == 3)
    assert(not table.concat(allowed.warnings, " "):find("Bring safe water"))
    local ownedOnly = supplies.report(p, false, false)
    assert(ownedOnly.nearbyWater == 0 and ownedOnly.nearbyWaterSourceCount == 0)
end)

if nativeAction then
    test("installed native TakeWater sips only the needed amount across updates", function()
        local p = player()
        local tap = source(p.square)
        assert(Sources.drink(p, {object=tap}))
        local action = queue[1]
        assert(action.waterUnit == 0.5 and action.maxTime == 65)
        action:updateUse(0.5)
        assert(p.thirst == 0.125 and tap.amount == 1.75)
        assert(action:complete())
        assert(p.thirst == 0 and tap.amount == 1.5)
        p, queue = player(), {}
        tap = source(p.square); tap.amount = 0.1
        assert(Sources.drink(p, {object=tap}))
        assert(queue[1]:complete())
        assert(math.abs(p.thirst - 0.2) < 0.000001 and tap.amount == 0)
    end)
end

print("WATER SOURCES " .. passed .. " PASS; " .. (nativeAction and "installed action with explicit game boundaries" or "portable native-action boundary doubles"))
