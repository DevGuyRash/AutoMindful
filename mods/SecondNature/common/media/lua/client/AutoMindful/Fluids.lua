require "Fluids/ISFluidContainer"
require "Fluids/ISFluidUtil"
require "Fluids/ISFluidTransferAction"
local IntakeGuard = require "AutoMindful/IntakeGuard"

AutoMindful = AutoMindful or {}
local Fluids = {allowTainted = false}
AutoMindful.Fluids = Fluids

local unsafeReason = "This fluid mixture contains a tainted, poisonous, alcoholic, or otherwise unsafe component."

function Fluids.container(item)
    local world = item:getWorldItem()
    return (world and world:getFluidContainer()) or item:getFluidContainer()
end

-- Nothing in the food itself would harm the survivor: not rotten, poisoned,
-- tainted, sickening or alcoholic, with no unknown eating effect. Cooking does
-- not change any of this, so eating and cooking share it.
function Fluids.harmless(item)
    -- BodyDamage.JustAteFood applies age >= offAgeMax even when isRotten()
    -- masks it (fertilized eggs). Stale food is below this threshold; vanilla
    -- nonperishables use a very large offAgeMax, not a freshness requirement.
    -- The stock wild-food callback only reads poison power, checked below.
    local effect = item:getOnEat()
    return (not effect or effect == "" or effect == "RecipeCodeOnEat.consumeWildFoodGeneric")
        and not item:isRotten() and item:getAge() < item:getOffAgeMax() and not item:isTainted()
        and not item:isPoison() and item:getPoisonPower() <= 0 and item:getFoodSicknessChange() <= 0
        and not item:isAlcoholic()
end

-- Safe to eat now: harmless, and not burnt, frozen or dangerous raw.
function Fluids.safeFood(item)
    if not instanceof(item, "Food") then return true end
    return Fluids.harmless(item) and not item:isBurnt() and not item:isFrozen()
        and (not item:isbDangerousUncooked() or item:isCooked())
end

local function safeOwner(container)
    local owner = container:getOwner()
    if owner and instanceof(owner, "IsoWorldInventoryObject") then owner = owner:getItem() end
    return not owner or Fluids.safeFood(owner)
end

local function safeSample(sample)
    for index = 0, sample:size() - 1 do
        if sample:getPercentage(index) > 0 then
            local fluid = sample:getFluid(index)
            local properties = fluid:getProperties()
            if not (fluid:isCategory(FluidCategory.Beverage) or fluid:isCategory(FluidCategory.Water))
                    or fluid:isCategory(FluidCategory.Hazardous) or fluid:isCategory(FluidCategory.Alcoholic)
                    or fluid:isCategory(FluidCategory.Poisons) or fluid:isCategory(FluidCategory.Fuel)
                    or fluid:isCategory(FluidCategory.Industrial) or fluid:isPoisonous() or properties:getPoison() > 0
                    or properties:getAlcohol() > 0 or properties:getFoodSicknessChange() > 0 then return false end
        end
    end
    return true
end

-- Plain water that would make the survivor ill, and nothing else. Only a last
-- resort (see Recovery) ever turns allowTainted on.
local function plainTainted(container)
    if not (Fluid and Fluid.TaintedWater) or not container:isTainted() then return false end
    local sample = container:createFluidSample()
    local ok, plain = pcall(function()
        for index = 0, sample:size() - 1 do
            local fluid = sample:getPercentage(index) > 0 and sample:getFluid(index)
            if fluid and fluid ~= Fluid.Water and fluid ~= Fluid.TaintedWater then return false end
        end
        return sample:size() > 0
    end)
    sample:release()
    return ok and plain
end

function Fluids.safe(container)
    if not container or not safeOwner(container) then return false, "The fluid's container is unsafe, frozen, or needs cooking." end
    if Fluids.allowTainted and plainTainted(container) then return true end
    local properties = container:getProperties()
    if container:isPoisonous() or container:isTainted() or properties:getPoison() > 0
            or properties:getAlcohol() > 0 or properties:getFoodSicknessChange() > 0 then return false, unsafeReason end
    local sample = container:createFluidSample()
    local succeeded, safe = pcall(safeSample, sample)
    sample:release()
    if not succeeded then error(safe) end
    return safe, not safe and unsafeReason or nil
end

function Fluids.isWater(container)
    return container:isPureFluid(Fluid.Water) or Fluids.allowTainted and plainTainted(container)
end

function Fluids.inspect(container)
    local safe, reason = Fluids.safe(container)
    if not safe then return nil, reason end
    if container:isEmpty() then return nil, "This fluid container is empty." end
    local properties = container:getProperties()
    local hunger, thirst = -properties:getHungerChange(), -properties:getThirstChange()
    return {fluid = container, remainingLiters = container:getAmount(), hungerEffect = hunger, thirstEffect = thirst,
        hungerRelief = math.max(0, hunger), thirstRelief = math.max(0, thirst), food = hunger > 0, water = thirst > 0,
        calories = math.max(0, properties:getCalories())}
end

function Fluids.drinkable(item, container, afterOpening)
    return container and Fluids.safeFood(item) and container:getCapacity() > 0
        and (container:getCapacity() <= 3 or item:isWorn())
        and (afterOpening == true or (not item:isSealed() and container:canPlayerEmpty()))
end

function Fluids.emptyVessel(item)
    local container = Fluids.container(item)
    return container and container:isEmpty() and not container:isInputLocked()
        and Fluids.drinkable(item, container) and Fluids.safe(container) or false
end

function Fluids.project(description, amountLiters)
    local result = {}
    for key, value in pairs(description) do result[key] = value end
    local amount = math.max(0, math.min(amountLiters, description.remainingLiters))
    local fraction = amount / description.remainingLiters
    for _, field in ipairs({"hungerEffect", "thirstEffect", "hungerRelief", "thirstRelief", "calories"}) do
        result[field] = description[field] * fraction
    end
    result.remainingLiters = amount
    return result
end

function Fluids.transfer(player, source, target, amountLiters, validate)
    local sourceDescription, reason = Fluids.inspect(source)
    if not sourceDescription then return false, reason end
    local targetOwner = target:getOwner()
    if not source:canPlayerEmpty() then return false, "The source cannot currently be opened or poured." end
    if not instanceof(targetOwner, "InventoryItem") or not Fluids.emptyVessel(targetOwner) then
        return false, "Use a clean, empty drinking vessel with free capacity."
    end
    if not FluidContainer.CanTransfer(source, target) then return false, "The game does not allow transferring between these containers." end
    local amount = math.min(amountLiters, source:getAmount(), target:getFreeCapacity())
    if amount <= 0 then return false, "There is no fluid or vessel space left to transfer." end
    if validate and not validate() then return false, "The source or drinking vessel is no longer available." end
    local sourceWrapper, targetWrapper = ISFluidContainer:new(source), ISFluidContainer:new(target)
    local action = ISFluidTransferAction:new(player, sourceWrapper, sourceWrapper:getFluidObject(),
        targetWrapper, targetWrapper:getFluidObject(), amount)
    local originalValid = action.isValid
    action.isValid = function(self)
        return (not validate or validate()) and originalValid(self)
    end
    -- Never turn rotten food into an apparently safe drink by pouring it into
    -- an ordinary cup between the last engine validity poll and the transfer.
    IntakeGuard.bind(action, function(self)
        return self.source:getFluidContainer() == source and self.target:getFluidContainer() == target
            and source:canPlayerEmpty() and Fluids.safe(source) and Fluids.safe(target)
    end, "update", "complete")
    if not action:isValid() then return false, "The game currently refuses this fluid transfer." end
    ISTimedActionQueue.add(action)
    return true
end

return Fluids
