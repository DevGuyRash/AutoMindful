-- Fires that cook: fireplaces, antique stoves and charcoal grills (the game's
-- "fire interaction" objects) and campfires. Only safe things are burned:
-- wood and scraps of paper, never books worth reading, favourites or what the
-- survivor wears. Lit with the game's own actions; put out only if lit here.
local Grid = require "AutoMindful/Grid"

local Fire = {policy = {margin = 30}}

local fuelTypes = {Log = true, Firewood = true, Plank = true, TreeBranch = true, TreeBranch2 = true, WoodenStick = true,
    WoodenStick2 = true, Twigs = true, UnusableWood = true, Charcoal = true, LargeBranch = true, Splinters = true}
-- Not writing paper (it may hold notes) or toilet paper and tissues (wanted).
local tinderTypes = {Newspaper = true, Paperbag = true, PaperNapkins2 = true, Twigs = true, Splinters = true}
-- Planks are wanted for building: burned last.
local lastResort = {Plank = true}

local function spare(item)
    if not item or Grid.favorite(item) then return false end
    local ok, worn = pcall(function() return item:isEquipped() end)
    return not (ok and worn)
end

local function typeOf(item)
    local ok, kind = pcall(function() return item:getType() end)
    return ok and kind or nil
end

local function camping(check, item)
    local ok, result = pcall(function() return ISCampingMenu and ISCampingMenu[check](item) end)
    return ok and result == true
end

-- Cheap: only these types are worth the checks below.
function Fire.candidate(item)
    local kind = typeOf(item) or ""
    return fuelTypes[kind] or tinderTypes[kind] or kind == "Lighter" or kind == "Matches" or false
end
function Fire.isFuel(item) return fuelTypes[typeOf(item) or ""] == true and spare(item) and camping("isValidFuel", item) end
function Fire.isTinder(item) return tinderTypes[typeOf(item) or ""] == true and spare(item) and camping("isValidTinder", item) end
function Fire.isStarter(item)
    if not item then return false end
    local kind = typeOf(item)
    local ok, uses = pcall(function() return item:getCurrentUses() end)
    return (kind == "Lighter" or kind == "Matches") and ok and type(uses) == "number" and uses > 0
end

function Fire.duration(item)
    local ok, minutes = pcall(function() return ISCampingMenu.getFuelDurationForItem(item) end)
    return ok and type(minutes) == "number" and minutes or 0
end

-- The camping system's object for a campfire, when this is one.
function Fire.campfire(object)
    local system = CCampfireSystem and CCampfireSystem.instance
    if not system or not object or not object.getSquare then return nil end
    local ok, campfire = pcall(function() return system:getLuaObjectOnSquare(object:getSquare()) end)
    if ok and campfire and campfire:getObject() == object then return campfire end
    return nil
end

-- "fire" for fireplaces, antique stoves and charcoal grills; "campfire"; or nil.
function Fire.kind(object)
    if not object or not object.getContainer or not object:getContainer() then return nil end
    if Fire.campfire(object) then return "campfire" end
    local ok, fire = pcall(function() return object:isFireInteractionObject() end)
    if not (ok and fire) then return nil end
    if instanceof(object, "IsoBarbecue") and object:isPropaneBBQ() then return nil end
    return "fire"
end

function Fire.lit(object)
    local campfire = Fire.campfire(object)
    if campfire then return campfire.isLit == true end
    return object:isLit() == true
end

function Fire.fuel(object)
    local campfire = Fire.campfire(object)
    if campfire then return campfire.fuelAmt or 0 end
    return object:getFuelAmount() or 0
end

local function maximum()
    local ok, value = pcall(getCampingFuelMax)
    return ok and type(value) == "number" and value or 480
end

-- What it takes to cook for so many minutes here: fuel to add, and if it is not
-- lit, a tinder and a starter. nil when the materials found are not enough.
function Fire.plan(object, minutes, materials)
    local lit, have = Fire.lit(object), Fire.fuel(object)
    local need = math.min(minutes + Fire.policy.margin, maximum())
    local plan = {fuel = {}}
    if not lit then
        plan.tinder, plan.starter = materials.tinder and materials.tinder[1], materials.starters and materials.starters[1]
        if not plan.tinder or not plan.starter then return nil end
        -- Only a campfire gets fuel from its tinder.
        if Fire.campfire(object) then have = have + Fire.duration(plan.tinder.item) end
    end
    -- Each piece's burn time and kind read once, not on every comparison.
    local fuel, cap = {}, maximum()
    for _, entry in ipairs(materials.fuel or {}) do
        -- Never the same thing twice: the tinder is not burned as fuel first.
        if not (plan.tinder and entry.item == plan.tinder.item) then
            fuel[#fuel + 1] = {entry = entry, minutes = Fire.duration(entry.item), last = lastResort[typeOf(entry.item)] and 1 or 0}
        end
    end
    table.sort(fuel, function(a, b)
        if a.last ~= b.last then return a.last < b.last end
        return a.minutes > b.minutes
    end)
    for _, piece in ipairs(fuel) do
        if have >= need then break end
        if piece.minutes > 0 and have + piece.minutes <= cap then
            plan.fuel[#plan.fuel + 1] = piece.entry
            have = have + piece.minutes
        end
    end
    if have < need then return nil end
    return plan
end

-- Only while our dish is in it: nobody's fire is fed or lit for nothing.
local function only(action, check)
    local valid = action.isValid
    function action:isValid() return check() and (not valid or valid(self)) end
    return action
end

-- Fuel in, then lit, from the inventory: the survivor stands beside it.
-- lit(): called when our own light actually caught, the one proof it is ours.
function Fire.start(player, object, plan, dish, lit)
    local inventory = player:getInventory()
    local campfire = Fire.campfire(object)
    local function ours() return dish == nil or object:getContainer():contains(dish) end
    for _, id in ipairs(plan.fuel or {}) do
        local item = inventory:getItemById(id)
        if item then
            local minutes = Fire.duration(item)
            ISTimedActionQueue.add(only(campfire and ISAddFuelAction:new(player, campfire, item, minutes)
                or ISBBQAddFuel:new(player, object, item, minutes), ours))
        end
    end
    if Fire.lit(object) or not plan.tinder then return end
    local tinder, starter = inventory:getItemById(plan.tinder), inventory:getItemById(plan.starter)
    if not tinder or not starter then return end
    local light = only(campfire and ISLightFromLiterature:new(player, tinder, starter, campfire, Fire.duration(tinder))
        or ISBBQLightFromLiterature:new(player, tinder, starter, object), function() return ours() and not Fire.lit(object) end)
    local perform = light.perform
    function light:perform(...)
        local result = perform(self, ...)
        if lit then lit() end
        return result
    end
    ISTimedActionQueue.add(light)
end

function Fire.stop(player, object)
    local campfire = Fire.campfire(object)
    if campfire then return ISPutOutCampfireAction:new(player, campfire) end
    return ISBBQExtinguish:new(player, object)
end

return Fire
