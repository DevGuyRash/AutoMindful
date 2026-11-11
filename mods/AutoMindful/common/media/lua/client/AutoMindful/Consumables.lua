require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISDrinkFluidAction"

AutoMindful = AutoMindful or {}
local Consumables = {}
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

function Consumables.inspect(player, item, includeNearby)
    local description = {food = false, water = false, needsOpening = false,
        outputTypes = {}, hungerRelief = 0, thirstRelief = 0, calories = 0}
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
        for index = 0, outputs:size() - 1 do
            local output = outputs:get(index)
            local result = output:getResourceType() == ResourceType.Item and output:getItem(recipeData)
            if result then
                description.outputTypes[result:getFullName()] = true
                if safeScriptFood(result) then
                    description.food = description.food or result:getHungerChange() < 0
                    description.water = description.water or result:getThirstChange() < 0
                end
            end
        end
    end
    if food and not cantEat and not description.needsOpening and requiredItemsAvailable(player, item) then
        description.hungerRelief = math.max(0, -item:getHungerChange())
        description.thirstRelief = math.max(0, -item:getThirstChange())
        description.food = description.hungerRelief > 0
        description.water = description.thirstRelief > 0
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
        description.hungerRelief = math.max(0, -properties:getHungerChange())
        description.thirstRelief = math.max(0, -properties:getThirstChange())
        description.calories = math.max(0, properties:getCalories())
        description.water = description.thirstRelief > 0
        description.food = description.hungerRelief > 0
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

function Consumables.portion(player, item, kind)
    local description = Consumables.inspect(player, item)
    if description.needsOpening then return false, "Open this item before measuring its portion." end
    if not description[kind] then return false, description.reason or "This item cannot restore that need." end
    local need = math.max(0, player:getStats():get(kind == "water" and CharacterStat.THIRST or CharacterStat.HUNGER))
    local relief = kind == "water" and description.thirstRelief or description.hungerRelief
    local remainingFraction = relief > 0 and need / relief or 0
    remainingFraction = math.min(1, remainingFraction)
    if remainingFraction <= 0 then return false, "That need is already restored." end
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
