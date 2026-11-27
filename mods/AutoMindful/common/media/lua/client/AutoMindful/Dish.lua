-- Dishes from the game's own evolved recipes, all of them: soups, stews, stir
-- fries, roasts, salads, sandwiches, burgers, tacos, burritos, pies, cakes,
-- muffins, pasta, rice, omelettes, pizza, oatmeal, bread and the rest. The list
-- is read from the game at run time, so recipes other mods add count too.
-- A base nearby (a pot of water, a pan, a bowl, bread slices, a pie crust...)
-- gets the best ingredients the game takes for it, then is cooked like any dish
-- or, when it needs no cooking, is ready to eat. Each step is its own batch, and
-- the world, not how the actions ended, says what happened: a base usually
-- becomes a new item when the first ingredient goes in.
local Diet = require "AutoMindful/Diet"
local Fetch = require "AutoMindful/Fetch"
local Grid = require "AutoMindful/Grid"
local Log = require "AutoMindful/Log"
local Options = require "AutoMindful/Options"
local Saved = require "AutoMindful/Saved"
local Snap = require "AutoMindful/Snapshot"

-- ingredients: real ones per dish, at most; spices: on top. rottenLevel: the
-- Cooking level from which the game takes rotten food, at a fraction of its value.
local Dish = {policy = {ingredients = 4, spices = 1, holdMs = 600000, soonHours = 72, rottenLevel = 7, tap = 1}}
local K, P

-- Kitchen hands over what it shares: its ledger writer, the stove placer and
-- the controller parts.
function Dish.bind(kitchen, parts) K, P = kitchen, parts end

local stages = {["dish-base"] = true, ["dish-fetch"] = true, ["dish-fill"] = true, ["dish-add"] = true}
-- Saved by 0.5.0 and earlier: given up after loading, like any plan whose sources are gone.
local older = {["soup-pot"] = true, ["soup-fetch"] = true, ["soup-fill"] = true, ["soup-add"] = true}
function Dish.handles(stage) return stages[stage] == true or older[stage] == true end

-- ------------------------------------------------------------------ the recipes

local function fullType(name)
    if type(name) ~= "string" or name == "" then return nil end
    return name:find("%.") and name or ("Base." .. name)
end

local function read(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then return value end
    return fallback
end

-- Hot drinks: coffee, tea and the like in a mug of water, made when thirsty.
local function drink(name) return name:find("^HotDrink") ~= nil end

-- Not made: buckets keep the survivor's water, and a result that does not
-- feed (fishing chum) is not a dish. Hot drinks are their own kind.
local function excluded(name, base, result)
    if base == "Base.Bucket" or base == "Base.BucketEmpty" then return true end
    if drink(name) then return false end
    local script = result and read(function() return getScriptManager():FindItem(result) end)
    local hunger = script and read(function() return script:getHungerChange() end)
    return type(hunger) == "number" and hunger >= 0
end

-- The game lets these be grilled, but they are as good cold: made without heat.
local cold = {Sandwich = true, BagelPlain = true, BagelPoppy = true, BagelSesame = true, Toast = true}

local catalog
-- Every recipe by the base it starts from, and every type some recipe takes.
function Dish.catalog()
    if catalog then return catalog end
    local built = {byBase = {}, ingredients = {}, results = {}, count = 0}
    local all = read(function() return getEvolvedRecipes() end)
    for index = 0, all and all:size() - 1 or -1 do
        local recipe = all:get(index)
        local name = read(function() return recipe:getUntranslatedName() end)
        local base = fullType(read(function() return recipe:getBaseItem() end))
        local result = fullType(read(function() return recipe:getFullResultItem() end) or read(function() return recipe:getResultItem() end))
        if name and base and not read(function() return recipe:isHidden() end, false) and not excluded(name, base, result) then
            local def = {recipe = recipe, name = name, base = base, result = result,
                cookable = read(function() return recipe:isCookable() end, false) == true and not cold[name],
                water = read(function() return recipe:getMinimumWater() end, 0) or 0,
                max = read(function() return recipe:getMaxItems() end, Dish.policy.ingredients), drink = drink(name)}
            -- A hot drink left over is not a meal waiting to be eaten.
            if result and not def.drink then built.results[result] = true end
            built.byBase[base] = built.byBase[base] or {}
            table.insert(built.byBase[base], def)
            built.count = built.count + 1
            local possible = read(function() return recipe:getPossibleItems() end)
            for k = 0, possible and possible:size() - 1 or -1 do
                local kind = fullType(read(function() return possible:get(k):getFullType() end))
                if kind then built.ingredients[kind] = true end
            end
        end
    end
    -- Kept once the game has its recipes; early on the list can still be empty.
    if built.count > 0 then catalog = built end
    return built
end
function Dish.reset() catalog = nil end

-- What the player would call it: Soup, Salad, Stir Fry.
function Dish.title(def)
    local key = "ContextMenu_EvolvedRecipe_" .. def.name
    local text = getText and read(function() return getText(key) end)
    return (text and text ~= key) and text or def.name
end

-- ---------------------------------------------------------------- the things

local water

-- Enough water for this recipe, as the game counts it: a mug wants to be full,
-- a pot a measure. Falls back to litres when the game cannot say.
local function wet(def, item)
    if not def or (def.water or 0) <= 0 then return true end
    local answer = read(function() return def.recipe:hasMinimumWater(item) end)
    if type(answer) == "boolean" then return answer end
    return water(item) >= def.water
end

-- The recipe a ledger entry is making, from the catalog.
local function defFor(entry)
    for _, def in ipairs(Dish.catalog().byBase[entry.vesselType or ""] or {}) do
        if def.name == entry.recipe then return def end
    end
    return nil
end

water = function(item)
    local fluid = item.getFluidContainer and item:getFluidContainer()
    return fluid and fluid:getAmount() or 0
end

-- A pot, pan, bowl or mug holding nothing, or nothing but water when the recipe wants water.
local function plainVessel(item, wet)
    local fluid = item.getFluidContainer and item:getFluidContainer()
    return not fluid or fluid:isEmpty() or (wet and fluid:isPureFluid(Fluid.Water))
end

-- In the survivor's hands or on their belt: a frying pan is a weapon too.
local function inUse(item)
    if read(function() return item:isEquipped() end, false) then return true end
    local slot = read(function() return item:getAttachedSlot() end, -1)
    return type(slot) == "number" and slot >= 0
end

-- Already holding all the ingredients its recipe takes.
local function full(item, def)
    local extra = read(function() return item:haveExtraItems() and item:getExtraItems():size() end, 0)
    return type(extra) == "number" and extra >= (def.max or Dish.policy.ingredients)
end

-- Cooked to be eaten: a cookable recipe, or a raw egg base such as an omelette.
local function needsHeat(def, item)
    return def.cookable or (instanceof(item, "Food") and item:isbDangerousUncooked() and not item:isCooked())
end

-- Safe in every way but age: no eating effect, poison, taint, sickness or drink.
local function harmlessButAge(item)
    local effect = item:getOnEat()
    return (not effect or effect == "") and not item:isTainted() and not item:isPoison() and item:getPoisonPower() <= 0
        and item:getFoodSicknessChange() <= 0 and not item:isAlcoholic()
end

local function rotten(item) return item:isRotten() or item:getAge() >= item:getOffAgeMax() end

-- The recipes this item can start: a clean pot, pan, bowl or mug, or food such
-- as bread slices or a pie crust that is still good. nil when none.
function Dish.recipesFor(item)
    local list = item and Dish.catalog().byBase[item:getFullType()]
    if not list or Grid.favorite(item) or inUse(item) then return nil end
    local food = instanceof(item, "Food")
    if food and (item:isBurnt() or item:isFrozen() or rotten(item) or not harmlessButAge(item)) then return nil end
    local fits = {}
    for _, def in ipairs(list) do
        -- The game refuses a base holding the wrong liquid, or already full.
        if (food or plainVessel(item, def.water > 0)) and not full(item, def) then fits[#fits + 1] = def end
    end
    return #fits > 0 and fits or nil
end

-- A dish someone made: a recipe's result with ingredients in it (a plain bagel
-- or toast is a recipe's result too, but nobody made anything of it).
function Dish.made(item)
    return Dish.catalog().results[item:getFullType()] == true and item.haveExtraItems ~= nil and item:haveExtraItems() == true
end

-- Worth looking at as an ingredient: some recipe takes this type.
function Dish.ingredient(item)
    return instanceof(item, "Food") and Dish.catalog().ingredients[item:getFullType()] == true and not Grid.favorite(item)
end

-- Running water that is safe: a sink, tap or rain barrel with enough in it.
function Dish.isTap(object)
    -- Walls and floors have no water: answered without building a closure.
    if not object or not object.hasWater then return false end
    local has, wet = pcall(object.hasWater, object)
    if not (has and wet) then return false end
    local ok, amount = pcall(function() return not object:isTaintedWater() and object:getFluidAmount() end)
    return ok and type(amount) == "number" and amount >= Dish.policy.tap
end

-- The game's own rules for an ingredient, and ours on top: never poison, drink
-- or anything with an effect, and rotten food only where the game allows it
-- (Cooking 7) and the setting does.
-- cook: whether the dish will be cooked (defaults to the recipe's own word).
function Dish.usable(def, item, level, base, cook)
    if cook == nil then cook = def.cookable end
    if item == base or not instanceof(item, "Food") or Grid.favorite(item) or inUse(item) then return false end
    if not read(function() return def.recipe:getItemRecipe(item) end) then return false end
    if item:isBurnt() or (item:isFrozen() and not read(function() return def.recipe:isAllowFrozenItem() end, false)) then return false end
    -- Dangerous raw: only into a dish that will be cooked.
    if item:isbDangerousUncooked() and not item:isCooked() and not cook then return false end
    -- What the recipe wants cooked first (bacon, eggs, a fillet in a sandwich) goes in cooked.
    -- The game's name reads backwards: false means "not like this, cook it first".
    if read(function() return def.recipe:needToBeCooked(item) end, true) == false then return false end
    -- Sealed food is opened by hand first.
    local opening = item.getOpeningRecipe and item:getOpeningRecipe()
    if opening and opening ~= "" then return false end
    if not harmlessButAge(item) then return false end
    if rotten(item) then return level >= Dish.policy.rottenLevel and Options.rottenRecipes() end
    return true
end

-- What an ingredient adds to the dish, as the game counts it: the recipe's
-- share, and only a sliver of anything rotten.
local function share(def, item, level)
    local whole = math.abs(item:getHungerChange() * 100)
    local use = read(function() return def.recipe:getItemRecipe(item):getUse() end)
    local value = type(use) == "number" and use > 0 and math.min(use, whole) or whole
    if rotten(item) then value = math.abs(item:getBaseHunger() * 100) * (level >= 9 and 0.1 or 0.05) end
    return value
end

local function spoilHours(item) return math.max(0, item:getOffAgeMax() - item:getAge()) * 24 end

local function held(skipped, item, now)
    local until_ = skipped and skipped[item:getID()]
    return until_ ~= nil and now < until_
end

local function cookingLevel(player)
    return read(function() return player:getPerkLevel(Perks.Cooking) end, 0)
end

-- The ingredients for this recipe and base: what spoils first, then what fills
-- most for the diet goal, and a spice once there is something to season.
local function pick(player, def, base, pool, reason, level, skipped, now, cook)
    local all = reason == "practice" and Options.cookTraining() == "all"
    local candidates, spices = {}, {}
    for _, entry in ipairs(pool) do
        local item = entry.item
        if item ~= base.item and not held(skipped, item, now) and not (reason == "practice" and entry.carried)
                and Dish.usable(def, item, level, base.item, cook) then
            if item:isSpice() then
                spices[#spices + 1] = entry
            elseif reason ~= "practice" or all or rotten(item) or spoilHours(item) <= Dish.policy.soonHours then
                candidates[#candidates + 1] = {entry = entry, day = math.floor(spoilHours(item) / 24),
                    value = Diet.adjust(player, share(def, item, level), item)}
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.day ~= b.day then return a.day < b.day end
        return a.value > b.value
    end)
    local items, value, real = {}, 0, 0
    local limit = math.min(def.max or Dish.policy.ingredients, Dish.policy.ingredients)
    for _, candidate in ipairs(candidates) do
        if real >= limit then break end
        items[#items + 1], real = candidate.entry, real + 1
        value = value + candidate.value + (candidate.day * 24 <= Dish.policy.soonHours and 10 or 0)
    end
    local seasoned, types = 0, {}
    for _, entry in ipairs(spices) do
        if real == 0 or seasoned >= Dish.policy.spices then break end
        local kind = entry.item:getFullType()
        if not types[kind] then types[kind], seasoned, value = true, seasoned + 1, value + 3; items[#items + 1] = entry end
    end
    return items, value, real
end

-- The best dish to make now from what the kitchen found. heatFor(item) gives a
-- heat that cooks it, or nil. reason: "meal" or "practice". nil when nothing
-- fits, and then why: a tally of what ruled each recipe out. Third: the best
-- plan for each recipe that fits, best first, for the Kitchen tab.
function Dish.plan(player, found, reason, heatFor, skipped, now)
    local level, best, each = cookingLevel(player), nil, {}
    local why = {bases = #(found.bases or {}), ingredients = #(found.ingredients or {}), dry = 0, cold = 0, cooked = 0, few = 0}
    local tap = found.taps and found.taps[1]
    for _, base in ipairs(found.bases or {}) do
        local vessel = not instanceof(base.item, "Food")
        -- Practice never borrows what the survivor carries.
        if not (reason == "practice" and base.carried) and not held(skipped, base.item, now) then
            for _, def in ipairs(Dish.recipesFor(base.item) or {}) do
              -- Drinks only when a drink is wanted, and only drinks then.
              if (reason == "drink") == (def.drink == true) then
                local dry = not wet(def, base.item)
                local cook = needsHeat(def, base.item)
                -- A finished dish is not cooked again to take more.
                local done = not vessel and cook and base.item:isCooked()
                local heat = cook and heatFor(base.item) or nil
                if dry and not tap then why.dry = why.dry + 1
                elseif done then why.cooked = why.cooked + 1
                elseif cook and not heat then why.cold = why.cold + 1 end
                if not (dry and not tap) and not done and (heat or not cook) then
                    local items, value, real = pick(player, def, base, found.ingredients or {}, reason, level, skipped, now, cook)
                    -- A pot or pan wants two things in it; bread, a crust or a mug one.
                    local least = (vessel and not def.drink) and 2 or 1
                    if real < least then why.few = why.few + 1 end
                    if real >= least then
                        local score = value + (vessel and 0 or 5)
                        local plan = {base = base, def = def, heat = heat, items = items, score = score, real = real, tap = dry and tap or nil, cook = cook}
                        if not best or score > best.score then best = plan end
                        if not each[def.name] or score > each[def.name].score then each[def.name] = plan end
                    end
                end
              end
            end
        end
    end
    local list = {}
    for _, plan in pairs(each) do list[#list + 1] = plan end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.def.name < b.def.name
    end)
    return best, why, list
end

-- ------------------------------------------------------------------- the steps

local function squareAt(point) return point and getCell():getGridSquare(point.x, point.y, point.z) end

local function tapAt(point)
    local square = squareAt(point)
    if not square then return nil end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        if Dish.isTap(objects:get(index)) then return objects:get(index) end
    end
    return nil
end

local function byName(name, base)
    for _, def in ipairs(Dish.catalog().byBase[base] or {}) do if def.name == name then return def end end
    for _, list in pairs(Dish.catalog().byBase) do
        for _, def in ipairs(list) do if def.name == name then return def end end
    end
    return nil
end

-- The game's recipe for this base, by name, judged with what is carried.
function Dish.recipe(player, base, name)
    local containers = ArrayList.new()
    containers:add(player:getInventory())
    local recipes = read(function() return RecipeManager.getEvolvedRecipe(base, player, containers, true) end)
    for index = 0, recipes and recipes:size() - 1 or -1 do
        local recipe = recipes:get(index)
        if recipe:getUntranslatedName() == name then return recipe, containers end
    end
    return nil
end

-- What was fetched for the dish and is still in the pockets goes on the list for
-- the fridge, rather than spoiling there.
local function putAway(player, entry)
    local inventory, list, seen = player:getInventory(), {}, {}
    for _, id in ipairs(player:getModData().AutoMindfulLeftovers or {}) do list[#list + 1], seen[id] = id, true end
    local added = false
    for _, group in ipairs({entry.ingredients or {}, entry.dropped or {}}) do
        for _, id in ipairs(group) do
            if entry.fetched and entry.fetched[tostring(id)] and not seen[id] and inventory:getItemById(id) then
                list[#list + 1], seen[id], added = id, true, true
            end
        end
    end
    if added then Saved.set(player, "AutoMindfulLeftovers", list) end
end

-- Everything held back for the dish may be eaten again.
local function release(state, entry)
    for _, id in ipairs(entry.ingredients or {}) do state.rejected[id] = nil end
    for _, id in ipairs(entry.dropped or {}) do state.rejected[id] = nil end
    if entry.vessel then state.rejected[entry.vessel] = nil end
    if entry.base then state.rejected[entry.base] = nil end
end

-- Gives up: nothing stays held back, and the kitchen leaves those ingredients alone for a while.
local function fail(player, state, now, entry, why)
    Log.event(player, "dish.giveup", "why", why, "stage", entry.stage, "recipe", entry.recipe)
    putAway(player, entry)
    release(state, entry)
    state.kitchenSkip = state.kitchenSkip or {}
    for _, id in ipairs(entry.ingredients or {}) do state.kitchenSkip[id] = now + Dish.policy.holdMs end
    if entry.vessel then state.kitchenSkip[entry.vessel] = now + Dish.policy.holdMs end
    if Dish.sources then Dish.sources[player] = nil end
    K.write(player, nil)
    return false
end
Dish.abandon = fail

local function drop(entry, id)
    local left = {}
    for _, other in ipairs(entry.ingredients) do if other ~= id then left[#left + 1] = other end end
    entry.ingredients = left
    entry.dropped = entry.dropped or {}
    entry.dropped[#entry.dropped + 1] = id
end

local function ofType(inventory, kind)
    local found, items = {}, inventory:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item:getFullType() == kind then found[#found + 1] = item end
    end
    return found
end

-- Starts the planned dish. Returns true when its first step was queued.
function Dish.start(player, state, now, plan, reason)
    local base, def = plan.base, plan.def
    local inventory = player:getInventory()
    local weight = base.carried and 0 or base.item:getActualWeight()
    local ids, fetched = {}, {}
    for _, chosen in ipairs(plan.items) do
        weight = weight + (chosen.carried and 0 or chosen.item:getActualWeight())
        ids[#ids + 1] = chosen.item:getID()
        fetched[tostring(chosen.item:getID())] = not chosen.carried or nil
    end
    -- Too much to carry: the kitchen may set some carried things aside first.
    if not inventory:hasRoomFor(player, weight) then return false, "room", weight end
    local heat = plan.heat and plan.heat.object
    local square = heat and heat:getSquare()
    local tapSquare = plan.tap and plan.tap.square
    local name = Dish.title(def)
    local entry = {x = square and square:getX(), y = square and square:getY(), z = square and square:getZ(),
        heat = heat and K.heatKind(heat) or nil, stage = "dish-base", vessel = base.item:getID(), base = base.item:getID(),
        ingredients = ids, recipe = def.name, vesselType = base.item:getFullType(), result = def.result or base.item:getFullType(), water = def.water,
        max = def.max, cookable = plan.cook, reason = reason, fetched = fetched, tries = 0, name = name,
        tap = tapSquare and {x = tapSquare:getX(), y = tapSquare:getY(), z = tapSquare:getZ()} or nil}
    -- Kept out of ordinary eating while they wait to go in.
    for _, id in ipairs(ids) do state.rejected[id] = now + Dish.policy.holdMs end
    state.rejected[base.item:getID()] = now + Dish.policy.holdMs
    -- Where things come from, for the fetch batches.
    Dish.sources = Dish.sources or {}
    Dish.sources[player] = {base = base, ingredients = plan.items}
    K.write(player, entry)
    Log.event(player, "dish.start", "recipe", def.name, "reason", reason, "count", #ids, "base", Snap.item(base.item),
        "heat", entry.heat, "cooked", plan.cook, "score", math.floor(plan.score))
    if Dish.step(player, state, now, entry, heat) then return true end
    -- The first step could not even be queued: nothing stays held back.
    release(state, entry)
    Dish.sources[player] = nil
    K.write(player, nil)
    return false
end

-- Made and needing no cooking: ready to eat. Practice puts it in the fridge.
function Dish.forget(player) if Dish.sources then Dish.sources[player] = nil end end

local function finished(player, state, entry, dish)
    putAway(player, entry)
    release(state, entry)
    Dish.forget(player)
    K.write(player, nil)
    if entry.reason == "practice" then
        local list, seen = {}, false
        for _, id in ipairs(player:getModData().AutoMindfulLeftovers or {}) do list[#list + 1] = id; seen = seen or id == dish:getID() end
        if not seen then list[#list + 1] = dish:getID() end
        Saved.set(player, "AutoMindfulLeftovers", list)
    end
    Log.event(player, "dish.made", "dish", Snap.item(dish), "reason", entry.reason)
    return false
end

-- One batch for the stage the dish is at. stove: the heat it will cook on, if any.
function Dish.step(player, state, now, entry, stove)
    local inventory = player:getInventory()
    local sources = Dish.sources and Dish.sources[player]
    if older[entry.stage] then return fail(player, state, now, entry, "reloaded") end
    if not Options.makeSoup() then return fail(player, state, now, entry, "turned-off") end
    if entry.cookable and not stove then return fail(player, state, now, entry, "stove-gone") end
    -- After a reload the places things came from are gone: start over rather than guess.
    if not sources and (entry.stage == "dish-base" or entry.stage == "dish-fetch") then return fail(player, state, now, entry, "reloaded") end
    local lower = string.lower(entry.name)
    if entry.stage == "dish-base" then
        if inventory:getItemById(entry.vessel) then
            entry.stage = "dish-fetch"; K.write(player, entry)
            return Dish.step(player, state, now, entry, stove)
        end
        local from = sources.base
        if not from or not Fetch.present(from) then return fail(player, state, now, entry, "base-lost") end
        return P.ownBatch(player, state, "kitchen", "Getting " .. from.item:getDisplayName() .. " for " .. lower .. ".", function()
            local square = Fetch.square(from)
            if square and not Grid.reachable(player:getSquare(), square) and not luautils.walkAdj(player, square, true) then return end
            Fetch.queue(player, from)
        end)
    elseif entry.stage == "dish-fetch" then
        local missing = {}
        for _, ingredient in ipairs(sources.ingredients) do
            local id = ingredient.item:getID()
            if not ingredient.carried and not inventory:getItemById(id) then
                -- Gone from where it was (someone took it): leave it out.
                if Fetch.present(ingredient) then missing[#missing + 1] = ingredient
                else drop(entry, id); state.rejected[id] = nil end
            end
        end
        if #entry.ingredients < 1 then return fail(player, state, now, entry, "ingredients-gone") end
        if #missing == 0 then
            local base = inventory:getItemById(entry.vessel)
            entry.stage = (entry.water or 0) > 0 and base and not wet(defFor(entry) or {water = entry.water}, base) and "dish-fill" or "dish-add"
            K.write(player, entry)
            return Dish.step(player, state, now, entry, stove)
        end
        return P.ownBatch(player, state, "kitchen", "Getting the ingredients for " .. lower .. ".", function()
            -- One place per batch: the walk is decided from where the survivor stands now.
            local square = Fetch.square(missing[1])
            if square and not Grid.reachable(player:getSquare(), square) and not luautils.walkAdj(player, square, true) then return end
            for _, ingredient in ipairs(missing) do
                if ingredient.from == missing[1].from then Fetch.queue(player, ingredient) end
            end
        end)
    elseif entry.stage == "dish-fill" then
        local vessel, tap = inventory:getItemById(entry.vessel), tapAt(entry.tap)
        if not vessel then return fail(player, state, now, entry, "base-lost") end
        if wet(defFor(entry) or {water = entry.water}, vessel) then entry.stage = "dish-add"; K.write(player, entry); return Dish.step(player, state, now, entry, stove) end
        if not tap then return fail(player, state, now, entry, "no-water") end
        return P.ownBatch(player, state, "kitchen", "Filling " .. vessel:getDisplayName() .. " with water.", function()
            local square = tap:getSquare()
            if not Grid.reachable(player:getSquare(), square) and not luautils.walkAdj(player, square, true) then return end
            ISTimedActionQueue.add(ISTakeWaterAction:new(player, vessel, tap, false))
        end)
    elseif entry.stage == "dish-add" then
        local base = inventory:getItemById(entry.base)
        if not base then return fail(player, state, now, entry, "base-lost") end
        local recipe = Dish.recipe(player, base, entry.recipe)
        local usable = recipe and recipe:getItemsCanBeUse(player, base, nil)
        -- Our own rules again at the moment it goes in: something may have rotted on the way.
        local def, level = byName(entry.recipe, entry.vesselType), cookingLevel(player)
        local nextItem
        for _, id in ipairs(entry.ingredients) do
            local item = inventory:getItemById(id)
            if item and usable and usable:contains(item) and def and Dish.usable(def, item, level, base, entry.cookable) then nextItem = item; break end
        end
        if (entry.adds or 0) >= (entry.max or Dish.policy.ingredients) then nextItem = nil end
        if not nextItem then
            -- Nothing more goes in. Without a single ingredient there is no dish.
            if (entry.adds or 0) == 0 then return fail(player, state, now, entry, "nothing-added") end
            if not entry.cookable then return finished(player, state, entry, base) end
            -- Ready to cook: nothing is held back any more; leftovers may be eaten.
            putAway(player, entry)
            release(state, entry)
            Dish.forget(player)
            entry.stage, entry.item, entry.items, entry.lit = "ready", entry.base, {entry.base}, nil
            entry.fetched = {[tostring(entry.base)] = true}
            K.write(player, entry)
            Log.event(player, "dish.ready", "dish", Snap.item(base))
            return K.place(player, state, now, entry, stove)
        end
        entry.adding, entry.addingHunger = nextItem:getID(), nextItem:getHungerChange()
        -- The dish that appears is the one that was not there before.
        entry.before = {}
        for _, item in ipairs(ofType(inventory, entry.result)) do entry.before[#entry.before + 1] = item:getID() end
        K.write(player, entry)
        return P.ownBatch(player, state, "kitchen", "Adding " .. nextItem:getDisplayName() .. " to the " .. lower .. ".", function()
            ISTimedActionQueue.add(ISAddItemInRecipe:new(player, recipe, base, nextItem))
        end)
    end
    return false
end

-- After each batch: what changed. The base is often a new item once something is in it.
function Dish.settle(player, state, now, cut)
    local entry = K.ledger(player)
    if not entry or older[entry.stage] then return end
    local inventory = player:getInventory()
    if entry.stage == "dish-base" and not inventory:getItemById(entry.vessel) then
        return fail(player, state, now, entry, cut and "base-fetch-interrupted" or "base-not-fetched")
    elseif entry.stage == "dish-fetch" then
        local carried = 0
        for _, id in ipairs(entry.ingredients) do if inventory:getItemById(id) then carried = carried + 1 end end
        if carried == 0 and not cut then return fail(player, state, now, entry, "nothing-fetched") end
        -- No closer than before, twice running: what is still out of reach is left out.
        if not cut then
            entry.stalls = carried > (entry.carried or 0) and 0 or (entry.stalls or 0) + 1
            entry.carried = carried
            if entry.stalls >= 2 then
                local left = {}
                for _, id in ipairs(entry.ingredients) do
                    if inventory:getItemById(id) then left[#left + 1] = id
                    else state.rejected[id] = nil; state.kitchenSkip = state.kitchenSkip or {}; state.kitchenSkip[id] = now + Dish.policy.holdMs end
                end
                entry.ingredients, entry.stalls = left, 0
                if Dish.sources and Dish.sources[player] then
                    local kept = {}
                    for _, ingredient in ipairs(Dish.sources[player].ingredients) do
                        if inventory:getItemById(ingredient.item:getID()) then kept[#kept + 1] = ingredient end
                    end
                    Dish.sources[player].ingredients = kept
                end
            end
            K.write(player, entry)
        end
    elseif entry.stage == "dish-fill" then
        local vessel = inventory:getItemById(entry.vessel)
        if (not vessel or not wet(defFor(entry) or {water = entry.water}, vessel)) and not cut then return fail(player, state, now, entry, "not-filled") end
    elseif entry.stage == "dish-add" and entry.adding then
        local changedBase = false
        if not inventory:getItemById(entry.base) then
            local before, newest, count = {}, nil, 0
            for _, id in ipairs(entry.before or {}) do before[id] = true end
            for _, item in ipairs(ofType(inventory, entry.result)) do
                if not before[item:getID()] then newest, count = item, count + 1 end
            end
            -- Exactly one new dish, or it cannot be told which is ours.
            if count ~= 1 then return fail(player, state, now, entry, count == 0 and "base-vanished" or "base-ambiguous") end
            entry.base, changedBase = newest:getID(), true
            -- Half a dish is not a meal yet.
            state.rejected[entry.base] = now + Dish.policy.holdMs
        end
        -- Meat goes in a part at a time: what is left of it may go in again.
        local item = inventory:getItemById(entry.adding)
        local shrank = item ~= nil and entry.addingHunger ~= nil and math.abs(item:getHungerChange() - entry.addingHunger) > 0.000001
        if changedBase or not item or shrank then
            entry.adds = (entry.adds or 0) + 1
            if not item then
                local left = {}
                for _, id in ipairs(entry.ingredients) do if id ~= entry.adding then left[#left + 1] = id end end
                entry.ingredients = left
                state.rejected[entry.adding] = nil
            end
        elseif not cut then
            -- Refused: leave that one out, free to be eaten, and carry on with the rest.
            drop(entry, entry.adding)
            state.rejected[entry.adding] = nil
        end
        entry.adding, entry.before, entry.addingHunger = nil, nil, nil
        K.write(player, entry)
    end
end

return Dish
