package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. (package.path or "")
for _, name in ipairs({"ISUI/ISInventoryPaneContextMenu", "TimedActions/ISDrinkFluidAction",
        "TimedActions/ISInventoryTransferUtil", "TimedActions/ISDropWorldItemAction"}) do package.loaded[name] = true end

CharacterStat = {HUNGER="hunger", THIRST="thirst"}
MoodleType = {HUNGRY="hunger", THIRST="thirst"}
local now, sources, containers, survivor, nextID = 0, {}, {}, nil, 0
function getTimestampMs() return now end
function instanceof(value, kind) return value.kind == kind end
function getPlayerInventory() return {} end
function getPlayerLoot() return {refreshBackpacks=function() end} end
package.loaded["AutoMindful/WaterSources"] = {scan=function() return sources end}

local function list(values)
    return {size=function() return #values end, get=function(_, index) return values[index + 1] end}
end
local function square(x)
    return {getX=function() return x end, getY=function() return 0 end, getZ=function() return 0 end,
        canReachTo=function() return true end}
end
local function container(x)
    local result = {items={}, square=square(x)}
    function result:getItems() return list(self.items) end
    function result:getOutermostContainer() return self end
    function result:getType() return "container" end
    function result:getSourceGrid() return self.square end
    function result:hasRoomFor() return true end
    return result
end
local function setup(hunger, thirst)
    local inventory, nearby = container(0), container(1)
    survivor = {inventory=inventory, values={hunger=hunger, thirst=thirst}, critical={}}
    function survivor:getStats() return {get=function(_, stat) return self.values[stat] end} end
    function survivor:getMoodles() return {getMoodleLevel=function(_, stat) return self.critical[stat] or 0 end} end
    function survivor:getInventory() return self.inventory end
    function survivor:getPlayerNum() return 0 end
    function survivor:getSquare() return self.inventory.square end
    function survivor:isSitOnGround() return false end
    containers, sources = {inventory, nearby}, {}
    return survivor, inventory, nearby
end
local function item(target, settings)
    nextID = nextID + 1
    local result = settings or {}
    result.id, result.container = nextID, target
    function result:getID() return self.id end
    function result:getContainer() return self.container end
    function result:getWorldItem() return nil end
    function result:getFluidContainer() return self.fluid end
    function result:getOpeningRecipe() return nil end
    function result:isSealed() return false end
    function result:isWorn() return false end
    function result:getScriptItem() return {isCantEat=function() return false end} end
    function result:getRequireInHandOrInventory() return nil end
    function result:getHungerChange() return self.hunger or 0 end
    function result:getThirstChange() return self.thirst or 0 end
    function result:getBaseHunger() return self.hunger or 0 end
    function result:getHungChange() return self.hunger or 0 end
    function result:getCalories() return self.calories or 0 end
    function result:getPoisonPower() return 0 end
    function result:getFoodSicknessChange() return 0 end
    for _, method in ipairs({"isRotten", "isBurnt", "isFrozen", "isTainted", "isPoison", "isAlcoholic", "isbDangerousUncooked"}) do
        result[method] = function() return false end
    end
    target.items[#target.items + 1] = result
    return result
end
local function food(target, hunger, thirst, calories)
    return item(target, {kind="Food", hunger=-hunger, thirst=-(thirst or 0), calories=calories})
end
local function drink(target, amount, hunger, thirst, capacity)
    local fluid = {amount=amount, capacity=capacity or amount}
    function fluid:getAmount() return self.amount end
    function fluid:getCapacity() return self.capacity end
    function fluid:isEmpty() return self.amount <= 0 end
    function fluid:isPoisonous() return false end
    function fluid:isTainted() return false end
    function fluid:canPlayerEmpty() return true end
    function fluid:getProperties()
        return {getHungerChange=function() return -hunger * self.amount end,
            getThirstChange=function() return -thirst * self.amount end, getCalories=function() return 0 end,
            getPoison=function() return 0 end, getFoodSicknessChange=function() return 0 end, getAlcohol=function() return 0 end}
    end
    return item(target, {kind="InventoryItem", fluid=fluid})
end
local function waterSource(amount)
    local source = {object={}, remainingLiters=amount}
    sources[#sources + 1] = source
    return source
end
ISInventoryPaneContextMenu = {getContainers=function() return list(containers) end,
    onDrinkFluid=function(selected, fraction, player)
        local properties = selected.fluid:getProperties()
        player.values.hunger = math.max(0, player.values.hunger + properties:getHungerChange() * fraction)
        player.values.thirst = math.max(0, player.values.thirst + properties:getThirstChange() * fraction)
        selected.fluid.amount = selected.fluid.amount * (1 - fraction)
    end,
    eatItem=function(selected, fraction)
        survivor.values.hunger = math.max(0, survivor.values.hunger + selected.hunger * fraction)
        survivor.values.thirst = math.max(0, survivor.values.thirst + selected.thirst * fraction)
    end}
local Supplies = require "AutoMindful/Supplies"
local Consumables = require "AutoMindful/Consumables"
local function near(actual, expected) assert(math.abs(actual - expected) < 0.000001, tostring(actual) .. " differs from " .. tostring(expected)) end
local passed = 0
local function test(name, check) check(); passed=passed+1; print("PASS supply policy " .. name) end

test("largest permitted current water stock wins across inventory and world", function()
    local player, inventory = setup(0, 0.2)
    local bottle = drink(inventory, 0.5, 0, 0.5)
    local source = waterSource(5)
    assert(Supplies.choose(player, "water", true, {}).source == source)
    assert(Supplies.choose(player, "water", false, {}).item == bottle)
    assert(Supplies.choose(player, "water", true, {[source.object]=now + 1000}).item == bottle)
    now = now + 1001
    assert(Supplies.choose(player, "water", true, {}).source == source)
end)
test("milk restores both actual needs before an abundant plain-water source", function()
    local player, inventory = setup(0.2, 0.2)
    local milk = drink(inventory, 1, 0.5, 0.5)
    waterSource(10000)
    assert(Supplies.choose(player, "water", true, {}).item == milk)
    near(Consumables.consume(player, milk, "water"), 0.4)
    near(player.values.hunger, 0); near(player.values.thirst, 0); near(milk.fluid.amount, 0.6)
end)
test("plain water preserves nourishing milk when hunger is already restored", function()
    local player, inventory = setup(0, 0.2)
    drink(inventory, 1, 0.5, 0.5)
    local source = waterSource(5)
    assert(Supplies.choose(player, "water", true, {}).source == source)
end)
test("mixed care stops at the first restored need then selects plain water", function()
    local player, inventory = setup(0.15, 0.2)
    local milk = drink(inventory, 1, 0.5, 0.5)
    local source = waterSource(5)
    assert(Supplies.choose(player, "water", true, {}).item == milk)
    near(Consumables.consume(player, milk, "water"), 0.3)
    near(player.values.hunger, 0); near(player.values.thirst, 0.05); near(milk.fluid.amount, 0.7)
    assert(Supplies.choose(player, "water", true, {}).source == source)
end)
test("tiny dual-purpose relief does not displace adequate hydration", function()
    local player, inventory = setup(0.2, 0.2)
    food(inventory, 0.005, 0.005)
    local source = waterSource(5)
    assert(Supplies.choose(player, "water", true, {}).source == source)
end)
test("a sufficient meal beats a tiny snack while an adequate owned portion beats a giant", function()
    local player, inventory, nearby = setup(0.15, 0)
    food(inventory, 0.05)
    local meal = food(nearby, 0.6)
    assert(Supplies.choose(player, "food", true, {}).item == meal)
    near(Consumables.consume(player, meal, "food"), 0.25)
    near(player.values.hunger, 0)
    player, inventory, nearby = setup(0.15, 0)
    local owned = food(inventory, 0.2)
    food(nearby, 0.6)
    assert(Supplies.choose(player, "food", true, {}).item == owned)
end)
test("calories do not outweigh useful relief and dehydrating food has a cost", function()
    local player, inventory, nearby = setup(0.2, 0.2)
    food(inventory, 0.24, 0, 3200)
    local juicy = food(nearby, 0.24, 0.24, 20)
    assert(Supplies.choose(player, "food", true, {}).item == juicy)
    player, inventory = setup(0.12, 0.2)
    food(inventory, 0.24, -0.2)
    local plain = food(inventory, 0.2)
    assert(Supplies.choose(player, "food", false, {}).item == plain)
end)
test("critical primary need outranks a partially useful dual-purpose item", function()
    local player, inventory = setup(0.2, 0.2)
    local dual = food(inventory, 0.2, 0.15)
    local source = waterSource(5)
    assert(Supplies.choose(player, "water", true, {}).item == dual)
    player.critical.thirst = 4
    assert(Supplies.choose(player, "water", true, {}).source == source)
end)
test("milk-only hydration remains usable and trace thirst cannot force food microsips", function()
    local player, inventory = setup(0, 0.2)
    local milk = drink(inventory, 1, 0.5, 0.5)
    assert(Supplies.choose(player, "water", false, {}).item == milk)
    near(Consumables.consume(player, milk, "water"), 0.4)
    near(player.values.thirst, 0)
    player, inventory = setup(0.3, 0.001)
    milk = drink(inventory, 1, 0.5, 0.5)
    near(Consumables.consume(player, milk, "food"), 0.6)
    near(player.values.hunger, 0)
end)
test("world-only restrictions and remaining volume are retained", function()
    local player, inventory = setup(0.2, 0.2)
    drink(inventory, 1, 0.5, 0.5)
    local source = waterSource(5)
    assert(Supplies.choose(player, "water", true, {}, true).source == source)
    assert(not Supplies.choose(player, "water", false, {}, true))
    player, inventory = setup(0, 0.2)
    drink(inventory, 0.1, 0, 0.5, 3)
    local fuller = drink(inventory, 0.5, 0, 0.5, 0.5)
    assert(Supplies.choose(player, "water", false, {}).item == fuller)
end)
print("SUPPLY POLICY " .. passed .. " PASS; real selectors and portions with explicit game boundaries")
