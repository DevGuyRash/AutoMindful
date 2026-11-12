require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISDrinkFluidAction"

AutoMindful = AutoMindful or {}
local Consumables = {careThreshold = 0.15, restoredThreshold = 0.01}
AutoMindful.Consumables = Consumables

local function fluidFor(item)
    local world = item:getWorldItem()
    return (world and world:getFluidContainer()) or item:getFluidContainer()
end

local function safeFood(item)
    return not item:isRotten() and not item:isBurnt() and not item:isFrozen() and not item:isTainted()
        and not item:isPoison() and item:getPoisonPower() <= 0 and item:getFoodSicknessChange() <= 0
        and not item:isAlcoholic() and (not item:isbDangerousUncooked() or item:isCooked())
end

local function safeScriptFood(script)
    return not script:isCantEat() and script:getPoisonPower() <= 0 and script:getFoodSicknessChange() <= 0
        and not script:isAlcoholic() and not script:isDangerousUncooked()
end

local function opening(player, item, includeNearby)
    local name = item:getOpeningRecipe()
    local recipe = name and getScriptManager():getCraftRecipe(name)
    if not recipe then return nil, nil, "This item has no usable native opening recipe. Open it before training." end
    if recipe:isAnySurfaceCraft() then
        return nil, nil, "This opening recipe needs a separate crafting surface. Open the item before training."
    end
    local logic = HandcraftLogic.new(player, nil, nil)
    logic:setIsoObject(logic:findCraftSurface(player, 2))
    local containers = ArrayList.new()
    local available = ISInventoryPaneContextMenu.getContainers(player)
    local inventory = player:getInventory()
    for index = 0, available:size() - 1 do
        local container = available:get(index)
        if includeNearby or container:getOutermostContainer() == inventory then containers:add(container) end
    end
    logic:setContainers(containers)
    logic:setRecipeFromContextClick(recipe, item)
    if not logic:canPerformCurrentRecipe() then
        return nil, nil, "Opening needs its native recipe's tools, such as a can opener. Bring the required tool or open the item first."
    end
    return recipe, logic
end

local function requiredItemsAvailable(player, item)
    local required = item:getRequireInHandOrInventory()
    if not required or required:isEmpty() then return true end
    for index = 0, required:size() - 1 do
        local fullType = moduleDotType(item:getModule(), required:get(index))
        local available = player:getInventory():getFirstTypeEvalRecurse(fullType, function(candidate)
            return candidate:getCurrentUsesFloat() > 0
        end)
        if available then return true end
    end
    return false
end

function Consumables.replacements(item)
    local result = {}
    local replacement = item:getReplaceOnUseFullType()
    if replacement and replacement ~= "" then result[replacement] = true end
    return result
end

local function effects(description, hunger, thirst)
    description.hungerEffect, description.thirstEffect = hunger, thirst
    description.hungerRelief, description.thirstRelief = math.max(0, hunger), math.max(0, thirst)
    description.food, description.water = hunger > 0, thirst > 0
end

function Consumables.inspect(player, item, includeNearby)
    local description = {food = false, water = false, needsOpening = false,
        outputTypes = {}, hungerRelief = 0, thirstRelief = 0, hungerEffect = 0, thirstEffect = 0, calories = 0}
    local food = instanceof(item, "Food")
    local fluid = fluidFor(item)
    local cantEat = food and item:getScriptItem():isCantEat()
    if food and not safeFood(item) then
        description.reason = "This food is unsafe, frozen, or needs cooking."
        return description
    end
    description.needsOpening = item:isSealed() or (food and (cantEat == true or item:getOpeningRecipe() ~= nil))
    if description.needsOpening then
        local recipe, logic, reason = opening(player, item, includeNearby == true)
        if not recipe then
            description.reason = reason
            return description
        end
        description.openingRecipe = recipe
        description.openingLogic = logic
        description.inputItems, description.returnItems = {}, {}
        local recipeData = logic:getRecipeData()
        local inputs, putBack = recipeData:getAllInputItems(), recipeData:getAllPutBackInputItems()
        for index = 0, inputs:size() - 1 do
            local input = inputs:get(index)
            description.inputItems[#description.inputItems + 1] = input
            if putBack:contains(input) then description.returnItems[#description.returnItems + 1] = input end
        end
        if logic:isUsingRecipeAtHandBenefit() then
            local reference = logic:getUsingRecipeAtHandItem()
            if reference then
                description.inputItems[#description.inputItems + 1] = reference
                description.returnItems[#description.returnItems + 1] = reference
            end
        end
        description.outputTypes[item:getFullType()] = true
        local outputs = recipe:getOutputs()
        local consumableOutputs = 0
        for index = 0, outputs:size() - 1 do
            local output = outputs:get(index)
            local result = output:getResourceType() == ResourceType.Item and output:getItem(recipeData)
            if result then
                description.outputTypes[result:getFullName()] = true
                if safeScriptFood(result) and (result:getHungerChange() < 0 or result:getThirstChange() < 0) then
                    consumableOutputs = consumableOutputs + 1
                    effects(description, -result:getHungerChange() / 100, -result:getThirstChange() / 100)
                end
            end
        end
        if consumableOutputs > 1 then
            effects(description, 0, 0)
            description.reason = "Opening creates several usable items. Open it before training so each item can be assessed."
            return description
        end
    end
    if food and not cantEat and not description.needsOpening and requiredItemsAvailable(player, item) then
        effects(description, -item:getHungerChange(), -item:getThirstChange())
        description.calories = math.max(0, item:getCalories())
    end
    if fluid and not fluid:isEmpty() then
        description.food, description.water = false, false
        local properties = fluid:getProperties()
        if fluid:isPoisonous() or fluid:isTainted() or properties:getPoison() > 0
                or properties:getFoodSicknessChange() > 0 or properties:getAlcohol() > 0 then
            description.reason = "This drink is tainted, poisonous, alcoholic, or causes food sickness."
            return description
        end
        if not fluid:canPlayerEmpty() and not description.openingRecipe then
            description.reason = "This container cannot currently be opened for drinking."
            return description
        end
        if fluid:getCapacity() > 3 and not item:isWorn() then
            description.reason = "Use a drinkable bottle, canteen, or worn hydration container."
            return description
        end
        description.fluid = fluid
        effects(description, -properties:getHungerChange(), -properties:getThirstChange())
        description.remainingLiters = fluid:getAmount()
        description.calories = math.max(0, properties:getCalories())
    end
    return description
end

function Consumables.prepare(player, item, description)
    description = description or Consumables.inspect(player, item)
    if not description.needsOpening then return false, "This item is already open." end
    if not description.openingRecipe then return false, description.reason end
    local recipe, logic = description.openingRecipe, description.openingLogic
    if not logic:canPerformCurrentRecipe() then return false, "The opening recipe's tools or working conditions changed." end
    local inventory = player:getInventory()
    if not recipe:isCanBeDoneFromFloor() then
        for _, input in ipairs(description.inputItems) do
            if input:getContainer() ~= inventory and not inventory:hasRoomFor(player, input) then
                return false, "Make room in your inventory for the opening recipe's tools."
            end
        end
        for _, input in ipairs(description.inputItems) do
            ISInventoryPaneContextMenu.transferIfNeeded(player, input)
        end
        logic:setRecipeFromContextClick(recipe, item)
    end
    local action = ISEntityUI.HandcraftStart(player, logic, false, true)
    if not action then return false, "The native opening action could not start here." end
    action:setOnComplete(ISInventoryPaneContextMenu.OnNewCraftComplete, logic)
    logic:startCraftAction(action)
    return true
end

function Consumables.plan(player, description, kind)
    local hunger = math.max(0, player:getStats():get(CharacterStat.HUNGER))
    local thirst = math.max(0, player:getStats():get(CharacterStat.THIRST))
    local hungerEffect, thirstEffect = description.hungerEffect, description.thirstEffect
    local need, otherNeed = kind == "water" and thirst or hunger, kind == "water" and hunger or thirst
    local effect, otherEffect = kind == "water" and thirstEffect or hungerEffect, kind == "water" and hungerEffect or thirstEffect
    if need <= 0 or effect <= 0 then return nil end
    local fraction = math.min(1, need / effect)
    if hunger > Consumables.restoredThreshold and thirst > Consumables.restoredThreshold and hungerEffect > 0 and thirstEffect > 0 then
        fraction = math.min(fraction, hunger / hungerEffect, thirst / thirstEffect)
    end
    local primary = math.min(1, effect * fraction / need)
    local secondary = otherNeed > 0 and math.min(1, math.max(0, otherEffect * fraction) / otherNeed) or 0
    local penalty = (math.max(0, -otherEffect * fraction) + math.max(0, otherEffect * fraction - otherNeed)) / math.max(otherNeed, Consumables.careThreshold)
    return {fraction = fraction, primary = primary, secondary = secondary,
        utility = primary + math.min(primary, secondary) - penalty}
end

function Consumables.portion(player, item, kind)
    local description = Consumables.inspect(player, item)
    if description.needsOpening then return false, "Open this item before measuring its portion." end
    if not description[kind] then return false, description.reason or "This item cannot restore that need." end
    local plan = Consumables.plan(player, description, kind)
    if not plan then return false, "That need is already restored." end
    local remainingFraction = plan.fraction
    if description.fluid then return remainingFraction end
    local baseHunger, remainingHunger = item:getBaseHunger(), item:getHungChange()
    if baseHunger ~= 0 and remainingHunger ~= 0 then
        return math.min(1, remainingFraction * remainingHunger / baseHunger)
    end
    return remainingFraction
end

function Consumables.consume(player, item, kind)
    local portion, reason = Consumables.portion(player, item, kind)
    if not portion then return false, reason end
    local fluid = fluidFor(item)
    if fluid and not fluid:isEmpty() then
        ISInventoryPaneContextMenu.onDrinkFluid(item, portion, player)
    else
        ISInventoryPaneContextMenu.eatItem(item, portion, player:getPlayerNum())
    end
    return portion
end

return Consumables
