-- Fires that cook: fireplaces, antique stoves and charcoal grills (the game's
-- "fire interaction" objects) and campfires. Only what nobody would miss is
-- burned, the least worth first: twigs and branches, then paper and packaging
-- rubbish, then charcoal and firewood, then rags, a bed sheet, and planks and
-- logs only when nothing else will do. Never books, magazines, notes, maps,
-- money, photos, cards, keepsakes, clothes, favourites or anything worn. Lit
-- with the game's own actions, the least wasteful way there is: tinder and the
-- cheapest starter (matches before a lighter), else petrol and a starter, else
-- a notched plank worked with a stick. Put out only if lit here.
local Grid = require "AutoMindful/Grid"

local Fire = {policy = {margin = 30, kindleTries = 3}}

-- What may be burned, and in which order (lower first). Anything not listed is
-- never burned, whatever the game would allow: writing paper (it may hold
-- notes), toilet paper and tissues, chopsticks, wallpaper, keepsakes such as a
-- Spiffo's bag, readable papers, books, clothes. Rags are wanted for dressings
-- and splints, planks and logs for building: late.
local ranks = {
    -- What falls off trees and out of work: worth nothing else.
    Twigs = 1, Splinters = 1, Pinecone = 1, TreeBranch = 1, TreeBranch2 = 1, WoodenStick = 1, WoodenStick2 = 1,
    LargeBranch = 1, UnusableWood = 1,
    -- Rubbish: yesterday's paper, empty bags, napkins, a tongue depressor.
    Newspaper = 2, PaperBag = 2, Paperbag_Jays = 2, PaperNapkins2 = 2, TongueDepressor = 2,
    -- Made to be burned, but worth keeping for when it is needed.
    Charcoal = 3, CharcoalCrafted = 3, Firewood = 3,
    -- Rags: a dirty one before a clean one, which could still dress a wound.
    RippedSheetsDirty = 4, RippedSheets = 4.5,
    -- Carrier bags still carry things: after the rags.
    GroceryBag1 = 4.8, GroceryBag2 = 4.8, GroceryBag3 = 4.8, GroceryBag4 = 4.8, Plasticbag = 4.8,
    Sheet = 5,
    -- Building material: only when nothing else will do.
    Plank = 6, Log = 7,
}
-- Of those, what lights a fire as the game allows.
local tinders = {Twigs = true, Splinters = true, Pinecone = true, Newspaper = true, PaperBag = true, Paperbag_Jays = true,
    GroceryBag1 = true, GroceryBag2 = true, GroceryBag3 = true, GroceryBag4 = true, Plasticbag = true, PaperNapkins2 = true,
    TongueDepressor = true, RippedSheetsDirty = true, RippedSheets = true, Sheet = true}

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

-- How little it is worth (lower is burned first); nil: never burned.
function Fire.rank(item) return ranks[typeOf(item) or ""] end

-- Looked up once: the pre-filter runs on nearly every item in every container.
local tags
local function tagged(item, name)
    if not tags then
        local ok, found = pcall(function() return {START_FIRE = ItemTag.START_FIRE, PETROL = ItemTag.PETROL} end)
        tags = ok and found or {}
    end
    local tag = tags[name]
    return tag ~= nil and item.hasTag ~= nil and item:hasTag(tag) == true
end

-- Starters, the cheapest first: anything the game tags as starting a fire.
local starterRanks = {Matches = 1, Matchbox = 1, LighterDisposable = 2, MagnesiumFirestarter = 3, Lighter = 4,
    Lighter_Battery = 4, LighterBBQ = 5, CandleLit = 6}
-- Tagged as starting fires, but wanted for themselves: refills and paint.
local notStarters = {LighterFluid = true, SprayPaint = true}
function Fire.starterRank(item) return starterRanks[typeOf(item) or ""] or 5 end
-- A notched plank and a stick or branch to work it: no starter needed.
local sticks = {TreeBranch = true, TreeBranch2 = true, WoodenStick = true, WoodenStick2 = true}

-- Cheap: only these types are worth the checks below.
function Fire.candidate(item)
    local kind = typeOf(item) or ""
    return ranks[kind] ~= nil or starterRanks[kind] ~= nil or kind == "PercedWood" or tagged(item, "START_FIRE")
        or tagged(item, "PETROL")
end
function Fire.isFuel(item) return ranks[typeOf(item) or ""] ~= nil and spare(item) and camping("isValidFuel", item) end
function Fire.isTinder(item) return tinders[typeOf(item) or ""] == true and spare(item) and camping("isValidTinder", item) end
function Fire.isStarter(item)
    -- A lighter in the hand is still a lighter; a favourite is kept.
    if not item or Grid.favorite(item) then return false end
    local kind = typeOf(item)
    if notStarters[kind or ""] then return false end
    local ok, uses = pcall(function() return item:getCurrentUses() end)
    return (kind == "Lighter" or kind == "Matches" or tagged(item, "START_FIRE")) and ok and type(uses) == "number" and uses > 0
end
-- Enough petrol to light a fire with, as the game judges it.
function Fire.isPetrol(item) return spare(item) and camping("isPetrol", item) end
function Fire.isKindling(item) return typeOf(item) == "PercedWood" and spare(item) end
function Fire.isStick(item) return sticks[typeOf(item) or ""] == true and spare(item) end

-- Sorts a found thing into what a fire may use: result.fuel, tinder,
-- starters, petrol, kindling (notched planks) and sticks. entry() makes the
-- found entry only when it is needed.
function Fire.collect(item, result, entry)
    if not Fire.candidate(item) then return end
    local made
    local function add(list)
        result[list] = result[list] or {}
        made = made or entry()
        result[list][#result[list] + 1] = made
    end
    if Fire.isFuel(item) then add("fuel") end
    if Fire.isTinder(item) then add("tinder") end
    if Fire.isStarter(item) then add("starters") end
    if Fire.isPetrol(item) then add("petrol") end
    if Fire.isKindling(item) then add("kindling") end
    if Fire.isStick(item) then add("sticks") end
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
    local keep = {}
    if not lit then
        local function least(list, rank)
            local best
            for _, entry in ipairs(list or {}) do
                if not best or rank(entry.item) < rank(best.item) then best = entry end
            end
            return best
        end
        -- The least worth that lights (twigs before paper, paper before a rag),
        -- and the cheapest starter (matches before a lighter).
        local tinder = least(materials.tinder, function(item) return Fire.rank(item) or 9 end)
        local starter = least(materials.starters, Fire.starterRank)
        if tinder and starter then
            plan.method, plan.tinder, plan.starter = "tinder", tinder, starter
            keep[tinder.item] = true
            -- The game adds the tinder's own fuel as it lights, campfire or fireplace.
            have = have + Fire.duration(tinder.item)
        elseif starter and materials.petrol and materials.petrol[1] then
            -- The lightest can: lighting takes a splash, not the generator's supply.
            local petrol = least(materials.petrol, function(item)
                local ok, weight = pcall(function() return item:getActualWeight() end)
                return ok and weight or 99
            end)
            plan.method, plan.starter, plan.petrol = "petrol", starter, petrol
        elseif materials.kindling and materials.kindling[1] and materials.sticks and materials.sticks[1] and not materials.tired then
            -- No starter at all: a notched plank, slow and tiring, but it lights.
            plan.method, plan.plank, plan.stick = "kindle", materials.kindling[1], materials.sticks[1]
            -- Every stick is kept for rubbing: they break, and the next go needs one.
            for _, entry in ipairs(materials.sticks) do keep[entry.item] = true end
        else
            return nil
        end
    end
    -- Each piece's burn time and kind read once, not on every comparison.
    local fuel, cap = {}, maximum()
    for _, entry in ipairs(materials.fuel or {}) do
        -- Never the same thing twice: the tinder or the stick is not burned first.
        if not keep[entry.item] then
            fuel[#fuel + 1] = {entry = entry, minutes = Fire.duration(entry.item), rank = Fire.rank(entry.item) or 9}
        end
    end
    -- The least worth first; within that, what burns longest, so fewer go in.
    -- Should small pieces leave no room under the fire's cap for what is
    -- needed, the longest-burning first instead, worth or not.
    local start = have
    local function fill(order)
        table.sort(fuel, order)
        local chosen, total = {}, start
        for _, piece in ipairs(fuel) do
            if total >= need then break end
            if piece.minutes > 0 and total + piece.minutes <= cap then
                chosen[#chosen + 1] = piece.entry
                total = total + piece.minutes
            end
        end
        return total >= need and chosen or nil
    end
    local chosen = fill(function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.minutes > b.minutes
    end) or fill(function(a, b)
        if a.minutes ~= b.minutes then return a.minutes > b.minutes end
        return a.rank < b.rank
    end)
    if not chosen then return nil end
    plan.fuel = chosen
    return plan
end

-- What a plan is written down as (item IDs, for the ledger), and what it
-- takes into the hands.
function Fire.record(plan)
    local function id(entry) return entry and entry.item:getID() or nil end
    local record = {fuel = {}, method = plan.method, tinder = id(plan.tinder), starter = id(plan.starter),
        petrol = id(plan.petrol), plank = id(plan.plank), stick = id(plan.stick)}
    for _, fuel in ipairs(plan.fuel) do record.fuel[#record.fuel + 1] = fuel.item:getID() end
    return record
end
function Fire.wanted(plan)
    local list = {}
    for _, fuel in ipairs(plan.fuel) do list[#list + 1] = fuel end
    for _, field in ipairs({"tinder", "starter", "petrol", "plank", "stick"}) do
        if plan[field] then list[#list + 1] = plan[field] end
    end
    return list
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
    if Fire.lit(object) then return end
    local function held(id) return id and inventory:getItemById(id) or nil end
    local method = plan.method or (plan.tinder and "tinder")
    local light
    if method == "tinder" then
        local tinder, starter = held(plan.tinder), held(plan.starter)
        if not tinder or not starter then return end
        light = campfire and ISLightFromLiterature:new(player, tinder, starter, campfire, Fire.duration(tinder))
            or ISBBQLightFromLiterature:new(player, tinder, starter, object)
    elseif method == "petrol" then
        local starter, petrol = held(plan.starter), held(plan.petrol)
        if not starter or not petrol then return end
        light = campfire and ISLightFromPetrol:new(player, campfire, starter, petrol, 20) or ISBBQLightFromPetrol:new(player, object, starter, petrol)
    elseif method == "kindle" then
        local plank, stick = held(plan.plank), held(plan.stick)
        if not plank or not stick then return end
        light = campfire and ISLightFromKindle:new(player, plank, stick, campfire) or ISBBQLightFromKindle:new(player, plank, stick, object)
    else
        return
    end
    local tries, credited = 0, false
    local function credit()
        if lit and not credited then credited = true; lit() end
    end
    local function queue(action)
        tries = tries + 1
        local plank, stick = action.plank, action.item
        local start = action.start
        function action:start(...)
            self.autoMindfulStarted = true
            if start then return start(self, ...) end
        end
        local valid = action.isValid
        function action:isValid(...)
            -- A fireplace's plank lights it mid-action and the game then ends the
            -- action without finishing it: caught while ours is running, it is ours.
            if Fire.lit(object) then
                if self.autoMindfulStarted and method == "kindle" then credit() end
                return false
            end
            -- A plank attempt needs its own stick still in the hands: one that broke is gone.
            if method == "kindle" and not (stick and stick:getContainer() == inventory and plank:getContainer() == inventory) then return false end
            return ours() and (not valid or valid(self, ...))
        end
        local perform = action.perform
        function action:perform(...)
            -- The game's campfire plank queues its own next go, unowned and
            -- with any stick: ours instead, a few at most.
            local add, result, args = ISTimedActionQueue.add, nil, {...}
            if method == "kindle" then
                ISTimedActionQueue.add = function(next)
                    if next and next.Type == "ISLightFromKindle" then return nil end
                    return add(next)
                end
            end
            local ok, failure = pcall(function() result = perform(self, (table.unpack or unpack)(args)) end)
            ISTimedActionQueue.add = add
            if not ok then error(failure) end
            -- Ours only if it caught: rubbing a plank may well fail.
            if method ~= "kindle" or Fire.lit(object) then credit() end
            if method == "kindle" and not Fire.lit(object) and tries < Fire.policy.kindleTries then
                local rub = stick and stick:getContainer() == inventory and stick or nil
                if not rub then
                    local items = inventory:getItems()
                    for index = 0, items:size() - 1 do
                        local candidate = items:get(index)
                        if not rub and Fire.isStick(candidate) then rub = candidate end
                    end
                end
                if rub and plank:getContainer() == inventory then
                    queue(campfire and ISLightFromKindle:new(player, plank, rub, campfire) or ISBBQLightFromKindle:new(player, plank, rub, object))
                end
            end
            return result
        end
        ISTimedActionQueue.add(action)
    end
    queue(light)
end

function Fire.stop(player, object)
    local campfire = Fire.campfire(object)
    if campfire then return ISPutOutCampfireAction:new(player, campfire) end
    return ISBBQExtinguish:new(player, object)
end

return Fire
