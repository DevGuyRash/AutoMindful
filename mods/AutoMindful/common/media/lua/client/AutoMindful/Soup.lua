-- Soups and stews: a pot, water from the tap, and what spoils soonest, made with
-- the game's own evolved recipes and then cooked like any dish. Each step is
-- its own batch, and the world, not how the actions ended, says what happened:
-- the pot becomes a new item when the first ingredient goes in.
local Grid = require "AutoMindful/Grid"
local Log = require "AutoMindful/Log"
local Snap = require "AutoMindful/Snapshot"
local Options = require "AutoMindful/Options"

local Soup = {policy = {water = 0.9, ingredients = 4}}
local K, P

-- Kitchen hands over what it shares: its ledger writer, the stove placer and
-- the controller parts.
function Soup.bind(kitchen, parts) K, P = kitchen, parts end

local stages = {["soup-pot"] = true, ["soup-fetch"] = true, ["soup-fill"] = true, ["soup-add"] = true}
function Soup.handles(stage) return stages[stage] == true end

local meaty = {Meat = true, Poultry = true, Game = true, Fish = true, Seafood = true}
local function isMeat(item)
    local ok, kind = pcall(function() return item:getFoodType() end)
    return ok and meaty[kind] == true
end

-- An empty pot, or one holding nothing but water.
function Soup.isPot(item)
    if not item or item:getFullType() ~= "Base.Pot" or Grid.favorite(item) then return false end
    local fluid = item:getFluidContainer()
    return fluid ~= nil and (fluid:isEmpty() or fluid:isPureFluid(Fluid.Water))
end

-- Running water that is safe: a sink or tap with enough for a pot.
function Soup.isTap(object)
    local ok, water = pcall(function() return object:hasWater() and not object:isTaintedWater() and object:getFluidAmount() end)
    return ok and type(water) == "number" and water >= Soup.policy.water
end

local function water(pot)
    local fluid = pot:getFluidContainer()
    return fluid and fluid:getAmount() or 0
end

-- The game's recipe for this base, by name, judged with what is carried.
function Soup.recipe(player, base, name)
    local containers = ArrayList.new()
    containers:add(player:getInventory())
    local ok, recipes = pcall(RecipeManager.getEvolvedRecipe, base, player, containers, true)
    if not ok or not recipes then return nil end
    for index = 0, recipes:size() - 1 do
        local recipe = recipes:get(index)
        if recipe:getUntranslatedName() == name then return recipe, containers end
    end
    return nil
end

local function squareAt(point) return point and getCell():getGridSquare(point.x, point.y, point.z) end

local function tapAt(point)
    local square = squareAt(point)
    if not square then return nil end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        if Soup.isTap(objects:get(index)) then return objects:get(index) end
    end
    return nil
end

-- Everything held back for the soup may be eaten again.
local function release(state, entry)
    for _, id in ipairs(entry.ingredients or {}) do state.rejected[id] = nil end
    for _, id in ipairs(entry.dropped or {}) do state.rejected[id] = nil end
    if entry.pot then state.rejected[entry.pot] = nil end
    if entry.base then state.rejected[entry.base] = nil end
end

-- Gives up: nothing stays held back, and the kitchen leaves those ingredients alone for a while.
local function fail(player, state, now, entry, why)
    Log.event(player, "soup.giveup", "why", why, "stage", entry.stage)
    release(state, entry)
    state.kitchenSkip = state.kitchenSkip or {}
    for _, id in ipairs(entry.ingredients or {}) do state.kitchenSkip[id] = now + 600000 end
    if Soup.sources then Soup.sources[player] = nil end
    K.write(player, nil)
    return false
end
Soup.abandon = fail

local function drop(entry, id)
    local left = {}
    for _, other in ipairs(entry.ingredients) do if other ~= id then left[#left + 1] = other end end
    entry.ingredients = left
    entry.dropped = entry.dropped or {}
    entry.dropped[#entry.dropped + 1] = id
end

local function soupItems(inventory)
    local found, items = {}, inventory:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local kind = item:getFullType()
        if kind == "Base.PotOfSoupRecipe" or kind == "Base.PotOfStew" then found[#found + 1] = item end
    end
    return found
end

-- Starts a soup instead of plain cooking when there is a pot, water and at
-- least two ingredients from the same place. Returns true when it started.
function Soup.start(player, state, now, main, pool, stove, found, reason)
    -- Practice never borrows the pot the survivor is carrying.
    local pot
    for _, candidate in ipairs(found.pots) do
        if reason ~= "practice" or not candidate.carried then pot = candidate; break end
    end
    if not pot then return false end
    local ingredients = {main}
    for _, entry in ipairs(pool) do
        if #ingredients >= Soup.policy.ingredients then break end
        if entry.item ~= main.item and (entry.container == main.container or (entry.carried and main.carried)) then
            ingredients[#ingredients + 1] = entry
        end
    end
    if #ingredients < 2 then return false end
    local tap = found.taps[1]
    if water(pot.item) < Soup.policy.water and not tap then return false end
    local inventory, weight = player:getInventory(), pot.carried and 0 or pot.item:getActualWeight()
    local ids, fetched, stew = {}, {}, false
    for _, entry in ipairs(ingredients) do
        weight = weight + (entry.carried and 0 or entry.item:getActualWeight())
        ids[#ids + 1] = entry.item:getID()
        fetched[tostring(entry.item:getID())] = not entry.carried or nil
        stew = stew or isMeat(entry.item)
    end
    if not inventory:hasRoomFor(player, weight) then return false end
    local square = stove.object:getSquare()
    local tapSquare = tap and tap.square
    local name = stew and "Stew" or "Soup"
    local entry = {x = square:getX(), y = square:getY(), z = square:getZ(), stage = "soup-pot", pot = pot.item:getID(),
        base = pot.item:getID(), ingredients = ids, recipe = name, reason = reason, fetched = fetched, tries = 0,
        name = name, tap = tapSquare and {x = tapSquare:getX(), y = tapSquare:getY(), z = tapSquare:getZ()} or nil,
        potFrom = not pot.carried and Grid.key(Grid.containerSquare(pot.container)) or nil}
    -- Kept out of ordinary eating while they wait to go in.
    for _, id in ipairs(ids) do state.rejected[id] = now + 600000 end
    state.rejected[pot.item:getID()] = now + 600000
    -- Where things come from, for the fetch batches.
    Soup.sources = Soup.sources or {}
    Soup.sources[player] = {pot = pot, ingredients = ingredients}
    K.write(player, entry)
    Log.event(player, "soup.start", "recipe", name, "reason", reason, "count", #ids, "pot", Snap.item(pot.item),
        "water", water(pot.item), "tap", tapSquare and Grid.key(tapSquare))
    if Soup.step(player, state, now, entry, stove.object) then return true end
    -- The first step could not even be queued: nothing stays held back.
    release(state, entry)
    Soup.sources[player] = nil
    K.write(player, nil)
    return false
end

-- One batch for the stage the soup is at.
function Soup.step(player, state, now, entry, stove)
    local inventory = player:getInventory()
    local sources = Soup.sources and Soup.sources[player]
    if not Options.makeSoup() then return fail(player, state, now, entry, "turned-off") end
    -- After a reload the places things came from are gone: start over rather than guess.
    if not sources and (entry.stage == "soup-pot" or entry.stage == "soup-fetch") then return fail(player, state, now, entry, "reloaded") end
    if entry.stage == "soup-pot" then
        local pot = inventory:getItemById(entry.pot)
        if pot then entry.stage = "soup-fetch"; K.write(player, entry); return Soup.step(player, state, now, entry, stove) end
        local from = sources and sources.pot
        if not from or not from.container then return fail(player, state, now, entry, "pot-lost") end
        return P.ownBatch(player, state, "kitchen", "Getting a pot for " .. string.lower(entry.name) .. ".", function()
            local square = Grid.containerSquare(from.container)
            if square and not Grid.adjacent(player:getSquare(), square) and not luautils.walkAdj(player, square, true) then return end
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player, from.item, from.container, inventory))
        end)
    elseif entry.stage == "soup-fetch" then
        local missing = {}
        for _, ingredient in ipairs(sources.ingredients) do
            local id = ingredient.item:getID()
            if not ingredient.carried and not inventory:getItemById(id) then
                -- Gone from where it was (someone took it): leave it out.
                if ingredient.container:contains(ingredient.item) then missing[#missing + 1] = ingredient
                else drop(entry, id); state.rejected[id] = nil end
            end
        end
        if #entry.ingredients < 1 then return fail(player, state, now, entry, "ingredients-gone") end
        if #missing == 0 then
            entry.stage = water(inventory:getItemById(entry.pot)) >= Soup.policy.water and "soup-add" or "soup-fill"
            K.write(player, entry)
            return Soup.step(player, state, now, entry, stove)
        end
        return P.ownBatch(player, state, "kitchen", "Getting the ingredients for " .. string.lower(entry.name) .. ".", function()
            local square = Grid.containerSquare(missing[1].container)
            if square and not Grid.adjacent(player:getSquare(), square) and not luautils.walkAdj(player, square, true) then return end
            for _, ingredient in ipairs(missing) do
                ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player, ingredient.item, ingredient.container, inventory))
            end
        end)
    elseif entry.stage == "soup-fill" then
        local pot, tap = inventory:getItemById(entry.pot), tapAt(entry.tap)
        if not pot then return fail(player, state, now, entry, "pot-lost") end
        if water(pot) >= Soup.policy.water then entry.stage = "soup-add"; K.write(player, entry); return Soup.step(player, state, now, entry, stove) end
        if not tap then return fail(player, state, now, entry, "no-water") end
        return P.ownBatch(player, state, "kitchen", "Filling the pot with water.", function()
            local square = tap:getSquare()
            if not Grid.adjacent(player:getSquare(), square) and not luautils.walkAdj(player, square, true) then return end
            ISTimedActionQueue.add(ISTakeWaterAction:new(player, pot, tap, false))
        end)
    elseif entry.stage == "soup-add" then
        local base = inventory:getItemById(entry.base)
        if not base then return fail(player, state, now, entry, "pot-lost") end
        local recipe, containers = Soup.recipe(player, base, entry.recipe)
        local usable = recipe and recipe:getItemsCanBeUse(player, base, containers)
        local next
        for _, id in ipairs(entry.ingredients) do
            local item = inventory:getItemById(id)
            if item and usable and usable:contains(item) then next = item; break end
        end
        if not next then
            -- Nothing more goes in. With at least one ingredient it is a soup to cook.
            if entry.base == entry.pot then return fail(player, state, now, entry, "nothing-added") end
            -- Ready to cook: nothing is held back any more; leftovers may be eaten.
            release(state, entry)
            entry.stage, entry.item, entry.items, entry.lit = "ready", entry.base, {entry.base}, nil
            entry.fetched = {[tostring(entry.base)] = true}
            K.write(player, entry)
            Log.event(player, "soup.ready", "dish", Snap.item(base))
            return K.place(player, state, now, entry, stove)
        end
        entry.adding = next:getID()
        -- The soup that appears is the one that was not there before.
        entry.before = {}
        for _, item in ipairs(soupItems(inventory)) do entry.before[#entry.before + 1] = item:getID() end
        K.write(player, entry)
        return P.ownBatch(player, state, "kitchen", "Adding " .. next:getDisplayName() .. " to the " .. string.lower(entry.name) .. ".", function()
            ISTimedActionQueue.add(ISAddItemInRecipe:new(player, recipe, base, next))
        end)
    end
    return false
end

-- After each batch: what changed. The pot is a new item once something is in it.
function Soup.settle(player, state, now, cut)
    local entry = K.ledger(player)
    if not entry then return end
    local inventory = player:getInventory()
    if entry.stage == "soup-pot" and not inventory:getItemById(entry.pot) then
        return fail(player, state, now, entry, cut and "pot-fetch-interrupted" or "pot-not-fetched")
    elseif entry.stage == "soup-fetch" then
        local any = false
        for _, id in ipairs(entry.ingredients) do any = any or inventory:getItemById(id) ~= nil end
        if not any and not cut then return fail(player, state, now, entry, "nothing-fetched") end
    elseif entry.stage == "soup-fill" then
        local pot = inventory:getItemById(entry.pot)
        if (not pot or water(pot) < Soup.policy.water) and not cut then return fail(player, state, now, entry, "not-filled") end
    elseif entry.stage == "soup-add" and entry.adding then
        if not inventory:getItemById(entry.adding) then
            -- It went in. The base is the newest item of the result's kind, if the pot changed.
            local base = inventory:getItemById(entry.base)
            if not base then
                local before, newest = {}, nil
                for _, id in ipairs(entry.before or {}) do before[id] = true end
                for _, item in ipairs(soupItems(inventory)) do
                    if not before[item:getID()] then newest = item end
                end
                if not newest then return fail(player, state, now, entry, "pot-vanished") end
                entry.base = newest:getID()
                -- Half a soup is not a meal yet.
                state.rejected[entry.base] = now + 600000
            end
            local left = {}
            for _, id in ipairs(entry.ingredients) do if id ~= entry.adding then left[#left + 1] = id end end
            entry.ingredients = left
        elseif not cut then
            -- Refused: leave that one out, free to be eaten, and carry on with the rest.
            drop(entry, entry.adding)
            state.rejected[entry.adding] = nil
        end
        entry.adding, entry.before = nil, nil
        K.write(player, entry)
    end
end

return Soup
