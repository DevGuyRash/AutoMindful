package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. (package.path or "")

local names = {"CharacterStat", "ResourceType", "ArrayList", "HandcraftLogic", "getScriptManager",
    "moduleDotType", "instanceof", "ISInventoryPaneContextMenu", "ISEntityUI", "ISCraftingUI"}
local saved = {}
for _, name in ipairs(names) do saved[name] = _G[name] end
local modules = {"ISUI/ISInventoryPaneContextMenu", "TimedActions/ISDrinkFluidAction"}
local preloads = {}
for _, name in ipairs(modules) do
    preloads[name] = package.preload[name]
    package.preload[name] = function() end
end

local function array(values)
    local result = {values = values or {}}
    function result:size() return #self.values end
    function result:get(index) return self.values[index + 1] end
    function result:add(value) self.values[#self.values + 1] = value end
    function result:isEmpty() return #self.values == 0 end
    function result:contains(value)
        for _, candidate in ipairs(self.values) do if candidate == value then return true end end
        return false
    end
    return result
end

CharacterStat = {HUNGER = "hunger", THIRST = "thirst"}
ResourceType = {Item = "item"}
ArrayList = {new = function() return array() end}
function instanceof(item, kind) return item.kind == kind end
function moduleDotType(module, name) return name:find("%.") and name or module .. "." .. name end

local function container(owner)
    local result = {items = {}}
    function result:getOutermostContainer() return owner or self end
    function result:hasRoomFor() return self.room ~= false end
    function result:getFirstTypeEvalRecurse(fullType, predicate)
        for _, candidate in ipairs(self.items) do
            if candidate:getFullType() == fullType and predicate(candidate) then return candidate end
        end
    end
    return result
end

local function script(settings)
    local result = settings or {}
    function result:isCantEat() return self.cantEat == true end
    function result:getFullName() return self.fullType or "Base.OpenBeans" end
    function result:getHungerChange() return self.hunger or 0 end
    function result:getThirstChange() return self.thirst or 0 end
    function result:getPoisonPower() return self.poison or 0 end
    function result:getFoodSicknessChange() return self.sickness or 0 end
    function result:isAlcoholic() return self.alcoholic == true end
    function result:isDangerousUncooked() return self.dangerous == true end
    return result
end

local function fluid(settings)
    local result = settings or {}
    local properties = {}
    function properties:getHungerChange() return result.hunger or 0 end
    function properties:getThirstChange() return result.thirst or 0 end
    function properties:getCalories() return result.calories or 0 end
    function properties:getAlcohol() return result.alcohol or 0 end
    function properties:getPoison() return result.poison or 0 end
    function properties:getFoodSicknessChange() return result.sickness or 0 end
    function result:getProperties() return properties end
    function result:isEmpty() return self.empty == true end
    function result:isPoisonous() return self.poisonous == true end
    function result:isTainted() return self.tainted == true end
    function result:canPlayerEmpty() return self.locked ~= true end
    function result:getCapacity() return self.capacity or 1 end
    function result:getAmount() return self.amount or 1 end
    return result
end

local function item(settings)
    local result = settings or {}
    result.script = result.script or script()
    function result:getWorldItem() return nil end
    function result:getFluidContainer() return self.fluid end
    function result:getScriptItem() return self.script end
    function result:isRotten() return self.rotten == true end
    function result:isBurnt() return self.burnt == true end
    function result:isFrozen() return self.frozen == true end
    function result:isTainted() return self.tainted == true end
    function result:isPoison() return self.poisonous == true end
    function result:getPoisonPower() return self.poison or 0 end
    function result:getFoodSicknessChange() return self.sickness or 0 end
    function result:isAlcoholic() return self.alcoholic == true end
    function result:isbDangerousUncooked() return self.dangerous == true end
    function result:isCooked() return self.cooked == true end
    function result:isSealed() return self.sealed == true end
    function result:isWorn() return self.worn == true end
    function result:getOpeningRecipe() return self.opening end
    function result:getFullType() return self.fullType or "Base.Food" end
    function result:getContainer() return self.container end
    function result:getRequireInHandOrInventory() return self.required or array() end
    function result:getModule() return "Base" end
    function result:getCurrentUsesFloat() return 1 end
    function result:getHungerChange() return self.hunger or 0 end
    function result:getThirstChange() return self.thirst or 0 end
    function result:getCalories() return self.calories or 0 end
    function result:getBaseHunger() return self.base or self.hunger or 0 end
    function result:getHungChange() return self.remaining or self.hunger or 0 end
    function result:getReplaceOnUseFullType() return self.replacement end
    return result
end

local inventory, bag, nearby, player, available, events, recipes
local function setup()
    inventory = container()
    bag, nearby = container(inventory), container()
    available = array({inventory, bag, nearby})
    events, recipes = {}, {}
    player = {values = {hunger = 0, thirst = 0}}
    function player:getInventory() return inventory end
    function player:getPlayerNum() return 0 end
    function player:getStats()
        return {get = function(_, key) return player.values[key] end}
    end
end

ISInventoryPaneContextMenu = {
    getContainers = function() return available end,
    transferIfNeeded = function(_, input)
        if input:getContainer() ~= inventory then events[#events + 1] = {kind = "transfer", item = input} end
    end,
    eatItem = function(input, portion, index) events[#events + 1] = {kind = "eat", item = input, portion = portion, index = index} end,
    onDrinkFluid = function(input, portion, target) events[#events + 1] = {kind = "drink", item = input, portion = portion, player = target} end,
    OnNewCraftComplete = function() end,
}
ISCraftingUI = {ReturnItemsToOriginalContainer = function() error("Native trait-dependent return helper must not own AutoMindful loans") end}
ISEntityUI = {HandcraftStart = function(target, logic, force, queue)
    local action = {player = target, logic = logic, force = force, queue = queue}
    function action:setOnComplete(callback, argument) self.callback, self.argument = callback, argument end
    events[#events + 1] = {kind = "craft", action = action}
    return action
end}
function getScriptManager() return {getCraftRecipe = function(_, name) return recipes[name] end} end
HandcraftLogic = {new = function()
    local logic = {}
    function logic:findCraftSurface() return nil end
    function logic:setIsoObject() end
    function logic:setContainers(containers) self.containers = containers end
    function logic:setRecipeFromContextClick(recipe, selected) self.recipe, self.selected = recipe, selected end
    function logic:canPerformCurrentRecipe()
        self.tool = nil
        for _, source in ipairs(self.containers.values) do
            for _, candidate in ipairs(source.items) do
                if candidate:getFullType() == "Base.TinOpener" then self.tool = candidate end
            end
        end
        return not self.recipe.needsTool or self.tool ~= nil
    end
    function logic:getRecipeData()
        local inputs = {self.selected}
        if self.tool then inputs[#inputs + 1] = self.tool end
        return {selected = self.selected,
            getAllInputItems = function() return array(inputs) end,
            getAllPutBackInputItems = function() return array(self.tool and {self.tool} or {}) end}
    end
    function logic:isUsingRecipeAtHandBenefit() return false end
    function logic:startCraftAction(action) action.started = true end
    return logic
end}

local function recipe(outputs, needsTool)
    local result = {needsTool = needsTool}
    function result:isAnySurfaceCraft() return self.surface == true end
    function result:isCanBeDoneFromFloor() return false end
    function result:getOutputs()
        return array({{getResourceType = function() return ResourceType.Item end,
            getItem = function(_, data) return outputs[data.selected:getFullType()] end}})
    end
    return result
end

local C = require "AutoMindful/Consumables"
local count = 0
local function check(name, run)
    setup()
    run()
    count = count + 1
    print("PASS consumables " .. name)
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001, tostring(actual) .. " differs from " .. tostring(expected))
end

check("food portions use native original-base fractions", function()
    local meal = item({kind = "Food", hunger = -0.12, remaining = -0.12, base = -0.24, calories = 200, container = inventory})
    player.values.hunger = 0.03
    near(C.consume(player, meal, "food"), 0.125)
    assert(#events == 1 and events[1].kind == "eat" and events[1].item == meal and events[1].index == 0)
    near(events[1].portion, 0.125)
    player.values.hunger = 0
    assert(C.portion(player, meal, "food") == false)
end)

check("water portions depend on current fluid rather than bottle capacity", function()
    local bottle = item({fluid = fluid({capacity = 3, thirst = -1}), container = inventory})
    player.values.thirst = 0.1
    near(C.consume(player, bottle, "water"), 0.1)
    assert(#events == 1 and events[1].kind == "drink" and events[1].player == player)
    near(events[1].portion, 0.1)
end)

check("safe milk restores either need without drinking the whole item", function()
    local milk = item({fluid = fluid({hunger = -0.25, thirst = -0.25, calories = 307.5}), container = inventory})
    local description = C.inspect(player, milk)
    assert(description.food and description.water)
    near(description.calories, 307.5)
    player.values.hunger, player.values.thirst = 0.05, 0.1
    near(C.portion(player, milk, "food"), 0.2)
    near(C.portion(player, milk, "water"), 0.2)
    player.values.hunger = 0
    near(C.portion(player, milk, "water"), 0.4)
    player.values.hunger, player.values.thirst = 0.15, 0.2
    near(C.portion(player, milk, "water"), 0.6)
    player.values.hunger, player.values.thirst = 0.2, 0.001
    near(C.portion(player, milk, "food"), 0.8)
end)

check("selection predicts signed need changes and the same portion that is consumed", function()
    local dry = item({kind = "Food", hunger = -0.24, thirst = 0.2, container = inventory})
    player.values.hunger, player.values.thirst = 0.12, 0.2
    local description = C.inspect(player, dry)
    near(description.hungerEffect, 0.24)
    near(description.thirstEffect, -0.2)
    local plan = C.plan(player, description, "food")
    near(plan.fraction, 0.5)
    near(plan.primary, 1)
    near(plan.utility, 0.5)
    near(C.consume(player, dry, "food"), 0.5)
    near(events[1].portion, plan.fraction)
end)

check("worn hydration containers are usable and hydration food uses native eating", function()
    local worn = item({kind = "Clothing", worn = true, fluid = fluid({capacity = 5, thirst = -1}), container = inventory})
    assert(C.inspect(player, worn).water)
    worn.worn = false
    assert(not C.inspect(player, worn).water)
    local fruit = item({kind = "Food", hunger = -0.2, base = -0.2, thirst = -0.4, container = inventory})
    player.values.thirst = 0.1
    near(C.consume(player, fruit, "water"), 0.25)
    assert(events[1].kind == "eat")
end)

check("unsafe sources never become food or drinks", function()
    for _, setting in ipairs({{poisonous = true}, {tainted = true}, {alcohol = 0.01}, {sickness = 1}, {poison = 1}}) do
        setting.hunger, setting.thirst = -0.2, -0.5
        local unsafe = item({kind = "Food", hunger = -0.2, fluid = fluid(setting), container = inventory})
        local description = C.inspect(player, unsafe)
        assert(not description.food and not description.water)
        assert(C.consume(player, unsafe, "water") == false)
    end
    for _, flag in ipairs({"rotten", "burnt", "frozen", "poisonous", "alcoholic", "dangerous"}) do
        local unsafe = item({kind = "Food", hunger = -0.2, container = inventory})
        unsafe[flag] = true
        assert(not C.inspect(player, unsafe).food)
    end
    assert(#events == 0)
end)

check("native opening obeys nearby scope and exposes exact tool origins", function()
    local opener = item({fullType = "Base.TinOpener", container = nearby})
    nearby.items = {opener}
    local beans = item({kind = "Food", fullType = "Base.TinnedBeans", script = script({cantEat = true}), opening = "OpenFood", container = inventory})
    recipes.OpenFood = recipe({["Base.TinnedBeans"] = script({fullType = "Base.OpenBeans", hunger = -24})}, true)
    local unavailable = C.inspect(player, beans, false)
    assert(unavailable.needsOpening and not unavailable.food and unavailable.reason:find("can opener", 1, true))
    local description = C.inspect(player, beans, true)
    assert(description.food and description.needsOpening and description.outputTypes["Base.OpenBeans"])
    near(description.hungerEffect, 0.24)
    assert(description.returnItems[1] == opener and opener:getContainer() == nearby)
    assert(C.prepare(player, beans, description))
    assert(#events == 2 and events[1].kind == "transfer" and events[1].item == opener)
    local action = events[2].action
    assert(action.queue and not action.force and action.started)
    assert(action.callback == ISInventoryPaneContextMenu.OnNewCraftComplete and action.argument == description.openingLogic)
end)

check("opening metadata works without CantEat and mapped results are not guessed", function()
    local can = item({kind = "Food", fullType = "Base.CannedMilk", opening = "OpenFood", container = inventory})
    local result = script({fullType = "Base.CannedMilkOpen", hunger = -10, thirst = -10})
    recipes.OpenFood = recipe({["Base.CannedMilk"] = result}, false)
    local description = C.inspect(player, can)
    assert(description.needsOpening and description.food and description.water)
    assert(description.outputTypes["Base.CannedMilkOpen"] and not description.outputTypes["Base.OpenBeans"])
    assert(C.portion(player, can, "food") == false)
    recipes.OpenFood.surface = true
    assert(not C.inspect(player, can).food)
    assert(#events == 0)
end)

check("native replacements are explicit and tools need inventory room", function()
    local opened = item({kind = "Food", hunger = -0.24, replacement = "Base.TinCanEmpty", container = inventory})
    local replacements = C.replacements(opened)
    assert(replacements["Base.TinCanEmpty"] and not replacements["Base.EmptyBottle"])
    local opener = item({fullType = "Base.TinOpener", container = bag})
    bag.items = {opener}
    local can = item({kind = "Food", opening = "OpenFood", fullType = "Base.TinnedBeans", container = inventory})
    recipes.OpenFood = recipe({["Base.TinnedBeans"] = script({hunger = -24})}, true)
    local description = C.inspect(player, can, false)
    assert(description.food and description.returnItems[1] == opener)
    inventory.room = false
    local queued, reason = C.prepare(player, can, description)
    assert(queued == false and reason:find("Make room", 1, true) and #events == 0)
end)

for _, name in ipairs(names) do _G[name] = saved[name] end
for _, name in ipairs(modules) do package.preload[name] = preloads[name] end
print("CONSUMABLES PASS " .. tostring(count) .. " checks; native boundaries are explicit doubles")
