local Fixtures = {}
Fixtures.categories = {Beverage="Beverage", Water="Water", Hazardous="Hazardous", Alcoholic="Alcoholic"}

function Fixtures.component(settings)
    local fluid = settings or {}
    local categories = fluid.categories or {[Fixtures.categories.Beverage]=true}
    function fluid:isCategory(category) return categories[category] == true end
    function fluid:isPoisonous() return self.poisonous == true end
    function fluid:getProperties()
        if self.propertiesError then error(self.propertiesError) end
        return {getPoison=function() return self.poison or 0 end,
            getAlcohol=function() return self.alcohol or 0 end,
            getFoodSicknessChange=function() return self.sickness or 0 end}
    end
    return fluid
end

function Fixtures.sample(components)
    local sample = {released=false}
    function sample:size() return #components end
    function sample:getFluid(index) return components[index + 1].fluid end
    function sample:getPercentage(index) return components[index + 1].percentage end
    function sample:release() self.released = true end
    return sample
end

function Fixtures.attach(container, owner, components)
    function container:getOwner() return owner or self.owner end
    function container:isInputLocked() return self.inputLocked == true end
    function container:getFreeCapacity() return math.max(0, self:getCapacity() - self:getAmount()) end
    function container:createFluidSample()
        local entries = type(components) == "function" and components(self) or components
        self.lastSample = Fixtures.sample(entries)
        return self.lastSample
    end
    return container
end

return Fixtures
