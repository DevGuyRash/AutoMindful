-- Cooking crafts: the game's own craft recipes in its Cooking category, and any
-- other mod's there: opening cans, cutting a chicken, slicing bread or ham, pie
-- dough and a pie crust, cake batter, bread dough, a pot of pasta or rice, an
-- omelette, oatmeal, hot dogs, sushi, guacamole... Read at run time and judged
-- with the game's own crafting logic, which also knows which recipes the
-- survivor has learned and what their skills allow. A craft is made only when
-- what it makes leads to a better meal than what is there already: the dish
-- planner is asked what it would make if the craft's results existed, one or
-- two crafts ahead (pie dough, then the crust, then the pie).
local Dish = require "AutoMindful/Dish"
local Diet = require "AutoMindful/Diet"
local Fetch = require "AutoMindful/Fetch"
local Fluids = require "AutoMindful/Fluids"
local Grid = require "AutoMindful/Grid"
local Log = require "AutoMindful/Log"
local Options = require "AutoMindful/Options"

-- penalty: what a craft
-- step must earn over the best dish without it; tries: walks, cuts and checks
-- before a craft gives up; broad: an input that takes almost anything.
-- depth: crafts in a row the planner looks through; trials: dish plans it may
-- ask for in one look, however many crafts there are.
local Craft = {policy = {penalty = 5, holdMs = 600000, retryMs = 600000, broad = 200, tries = 3, depth = 4, trials = 40}}
local K, P

function Craft.bind(kitchen, parts) K, P = kitchen, parts end

local stages = {["craft-fetch"] = true, ["craft-walk"] = true, ["craft-make"] = true, ["craft-fill"] = true}
function Craft.handles(stage) return stages[stage] == true end

local function read(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then return value end
    return fallback
end

-- Crafts that would throw food away, are not cooking, or only carve and smash.
local excluded = {EmptyPan = true, EmptyTray = true, MakeHalloweenPumpkin = true, SmashPumpkin = true, SmashWatermelon = true,
    CreateBrainTan = true, SliceHead = true, PutEggsInCarton = true, MakeJar = true, OpenBottleOfBeer = true,
    OpenBottleOfWine = true, OpenCanOfBeverage = true, MakeMilkFromPowderBucket = true, MakeMilkFromPowderBottle = true}

local function names(list)
    local out = {}
    for index = 0, list and list:size() - 1 or -1 do
        local name = read(function() return list:get(index):getFullName() end)
        if name then out[#out + 1] = name end
    end
    return out
end

local catalog
-- Every cooking craft: what it can make, what it takes, and which of those are
-- tools it keeps (a knife on the belt may still cut).
function Craft.catalog()
    if catalog then return catalog end
    local built = {list = {}, count = 0, vessels = {}}
    local all = read(function() return getScriptManager():getAllCraftRecipes() end)
    for index = 0, all and all:size() - 1 or -1 do
        local recipe = all:get(index)
        local name = read(function() return recipe:getName() end)
        if name and not excluded[name] and read(function() return recipe:getCategory() end) == "Cooking" then
            local def = {recipe = recipe, name = name, outputs = {}, inputs = {}, keep = {},
                surface = read(function() return recipe:isAnySurfaceCraft() end, false) == true}
            local outputs = read(function() return recipe:getOutputs() end)
            for k = 0, outputs and outputs:size() - 1 or -1 do
                local output = outputs:get(k)
                if read(function() return output:getResourceType() == ResourceType.Item end, false) then
                    for _, kind in ipairs(names(read(function() return output:getPossibleResultItems() end))) do def.outputs[#def.outputs + 1] = kind end
                end
            end
            local inputs = read(function() return recipe:getInputs() end)
            for k = 0, inputs and inputs:size() - 1 or -1 do
                local input = inputs:get(k)
                if read(function() return input:getResourceType() == ResourceType.Item end, false) then
                    local choices = names(read(function() return input:getPossibleInputItems() end))
                    def.inputs[#def.inputs + 1] = choices
                    if read(function() return input:isKeep() or input:isTool() end, false) then
                        for _, kind in ipairs(choices) do def.keep[kind] = true end
                    end
                    -- A pot or saucepan that must already hold water (a pot of pasta, of rice).
                    local child = read(function() return input:hasConsumeFromItem() and input:getConsumeFromItemScript() end)
                    if child and read(function() return child:getResourceType() == ResourceType.Fluid and child:containsFluid(Fluid.Water) end, false) then
                        def.fill = {vessels = {}, amount = read(function() return child:getAmount() end, 1)}
                        for _, kind in ipairs(choices) do def.fill.vessels[kind] = true; built.vessels[kind] = true end
                    end
                end
            end
            if #def.outputs > 0 then
                built.list[#built.list + 1] = def
                built.count = built.count + 1
            end
        end
    end
    if built.count > 0 then catalog = built end
    return built
end
function Craft.reset() catalog = nil end


-- Worth asking the game about: something of every kind it takes is around.
local function possible(def, types)
    for _, choices in ipairs(def.inputs) do
        if #choices < Craft.policy.broad then
            local any = false
            for _, kind in ipairs(choices) do if types[kind] then any = true; break end end
            if not any then return false end
        end
    end
    return true
end

-- A pot or saucepan some craft wants water in, holding nothing or only water.
function Craft.vessel(item)
    if not item or Grid.favorite(item) or not Craft.catalog().vessels[item:getFullType()] then return false end
    local fluid = item.getFluidContainer and item:getFluidContainer()
    return fluid ~= nil and (fluid:isEmpty() or fluid:isPureFluid(Fluid.Water))
end

local function water(item)
    local fluid = item.getFluidContainer and item:getFluidContainer()
    return fluid and fluid:getAmount() or 0, fluid and fluid:getCapacity() or 0
end

-- Crafts that only lack water in their pot: fill it at a safe tap first.
local function fillOptions(found, skipped, now)
    local list, tap = {}, found.taps and found.taps[1]
    if not tap then return list end
    for _, def in ipairs(Craft.catalog().list) do
        local resting = skipped and skipped["craft:" .. def.name]
        if def.fill and not (resting and now < resting) then
            for _, entry in ipairs(found.vessels or {}) do
                local held = skipped and skipped[entry.item:getID()]
                local amount, capacity = water(entry.item)
                if def.fill.vessels[entry.item:getFullType()] and not (held and now < held) and amount < def.fill.amount
                        and capacity >= def.fill.amount then
                    local types = {}
                    for kind in pairs(found.types or {}) do types[kind] = true end
                    types[entry.item:getFullType()] = true
                    if possible(def, types) then
                        list[#list + 1] = {def = def, inputs = {entry.item}, outputs = def.outputs, fill = {vessel = entry, tap = tap}}
                        break
                    end
                end
            end
        end
    end
    return list
end

-- The survivor's own containers: the main inventory and the bags in it.
local function carried(player)
    local inventory = player:getInventory()
    local list, items = {inventory}, inventory:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if instanceof(item, "InventoryContainer") then list[#list + 1] = item:getInventory() end
    end
    return list
end

-- The game's crafting logic for this recipe with these containers, or nil
-- when the survivor cannot make it: not learned, not skilled, missing something.
function Craft.logic(player, def, containers, surface)
    local logic = read(function() return HandcraftLogic.new(player, nil, nil) end)
    if not logic then return nil end
    if surface then logic:setIsoObject(surface) end
    local list = ArrayList.new()
    for _, container in ipairs(containers) do list:add(container) end
    logic:setContainers(list)
    logic:setRecipe(def.recipe)
    if not read(function() return logic:isRecipeAvailableForCharacter(def.recipe) end, false) then return nil end
    if not read(function() return logic:canPerformCurrentRecipe() end, false) then return nil end
    return logic
end

local function inputsOf(logic)
    local out = {}
    local items = read(function() return logic:getRecipeData():getAllInputItems() end)
    for index = 0, items and items:size() - 1 or -1 do out[#out + 1] = items:get(index) end
    return out
end

-- What this logic will really make from the inputs it chose: a mapped output
-- (seventeen kinds of opened can) resolves to the one for this can.
local function outputsOf(logic, def)
    local out = {}
    local data = read(function() return logic:getRecipeData() end)
    local outputs = read(function() return def.recipe:getOutputs() end)
    for k = 0, outputs and outputs:size() - 1 or -1 do
        local output = outputs:get(k)
        if read(function() return output:getResourceType() == ResourceType.Item end, false) then
            local item = data and read(function() return output:getItem(data) end)
            local name = item and read(function() return item:getFullName() end)
            if name then out[#out + 1] = name end
        end
    end
    if #out == 0 and #def.outputs == 1 then out[1] = def.outputs[1] end
    return out
end

local function inUse(item)
    if read(function() return item:isEquipped() end, false) then return true end
    local slot = read(function() return item:getAttachedSlot() end, -1)
    return type(slot) == "number" and slot >= 0
end

-- Nothing held back, favourite or spoiled goes in, and nothing in the hands or
-- on the belt unless the recipe only uses it as a tool.
local function fit(def, inputs, skipped, now)
    for _, item in ipairs(inputs) do
        local held = skipped and skipped[item:getID()]
        if (held and now < held) or Grid.favorite(item) then return false end
        if inUse(item) and not def.keep[item:getFullType()] then return false end
        if instanceof(item, "Food") and (item:isBurnt() or not Fluids.harmless(item)) then return false end
    end
    return true
end

-- The crafts the survivor can make now with what the kitchen found.
function Craft.options(player, found, skipped, now)
    local list = {}
    local types, containers = found.types or {}, found.containers or {}
    -- The nearest counter the scan found: the game's own lookup only reaches the next square.
    local surface = found.surface and found.surface.object
    for _, def in ipairs(Craft.catalog().list) do
        local resting = skipped and skipped["craft:" .. def.name]
        if not (resting and now < resting) and possible(def, types) then
            if not def.surface or surface then
                local logic = Craft.logic(player, def, containers, def.surface and surface or nil)
                local inputs = logic and inputsOf(logic) or {}
                if logic and fit(def, inputs, skipped, now) then
                    list[#list + 1] = {def = def, inputs = inputs, outputs = outputsOf(logic, def), surface = def.surface and surface or nil}
                end
            end
        end
    end
    return list
end

-- A made-up item, never placed anywhere: what the craft would make.
local function made(kind)
    return read(function() return instanceItem(kind) end)
end

local function worth(player, item)
    if not instanceof(item, "Food") or item:getHungerChange() >= 0 then return 0 end
    return Diet.adjust(player, -item:getHungerChange() * 100, item)
end

-- What it costs: the food the craft uses up that could have been eaten as it is.
local function cost(player, inputs, def)
    local total = 0
    for _, item in ipairs(inputs) do
        -- A sealed can is not food until it is open: it costs nothing to open it.
        local sealed = (item.getOpeningRecipe and (item:getOpeningRecipe() or "") ~= "") or read(function() return item:isSealed() end, false)
        if not def.keep[item:getFullType()] and instanceof(item, "Food") and Fluids.safeFood(item) and not sealed then
            total = total + worth(player, item)
        end
    end
    return total
end

local function without(list, gone)
    local out = {}
    for _, entry in ipairs(list or {}) do if not gone[entry.item] then out[#out + 1] = entry end end
    return out
end

-- The dish planner, asked as if these made-up results existed and these inputs
-- were used up. Returns the plan's score with the made base's own food value,
-- or nil when the plan does not use any of them.
local function trial(player, found, virtual, gone, heatFor, skipped, now)
    local copy = {}
    for key, value in pairs(found) do copy[key] = value end
    copy.bases, copy.ingredients = without(found.bases, gone), without(found.ingredients, gone)
    for _, entry in ipairs(virtual) do
        if Dish.recipesFor(entry.item) then copy.bases[#copy.bases + 1] = entry end
        if Dish.ingredient(entry.item) then copy.ingredients[#copy.ingredients + 1] = entry end
    end
    local plan = Dish.plan(player, copy, "meal", heatFor, skipped, now)
    if not plan then return nil end
    local uses = plan.base.virtual
    for _, chosen in ipairs(plan.items) do uses = uses or chosen.virtual end
    if not uses then return nil end
    return plan.score + (plan.base.virtual and worth(player, plan.base.item) or 0)
end

local virtuals

-- Takes something of these kinds: the craft follows on from what came before.
local function feeds(def, kinds)
    for _, choices in ipairs(def.inputs) do
        for _, kind in ipairs(choices) do
            for _, out in ipairs(kinds) do if kind == out then return true end end
        end
    end
    return false
end

-- The best meal a chain of crafts leads to, each further craft paying the
-- step penalty again. kinds: everything the chain has made so far. depth: how
-- many crafts it has. budget: dish plans left for this look. seen: crafts in it.
local function chain(player, found, kinds, gone, heatFor, skipped, now, depth, budget, seen)
    if depth >= Craft.policy.depth or budget.left <= 0 then return nil end
    local types = {}
    for kind in pairs(found.types or {}) do types[kind] = true end
    for _, kind in ipairs(kinds) do types[kind] = true end
    local best
    for _, next in ipairs(Craft.catalog().list) do
        if budget.left <= 0 then break end
        if not seen[next.name] and not next.fill and #next.outputs <= 2 and feeds(next, kinds) and possible(next, types) then
            budget.left = budget.left - 1
            local made = {}
            for _, kind in ipairs(kinds) do made[#made + 1] = kind end
            for _, kind in ipairs(next.outputs) do made[#made + 1] = kind end
            local here = trial(player, found, virtuals(next.outputs), gone, heatFor, skipped, now)
            if here then here = here - (depth + 1) * Craft.policy.penalty end
            seen[next.name] = true
            local further = chain(player, found, made, gone, heatFor, skipped, now, depth + 1, budget, seen)
            seen[next.name] = nil
            for _, score in ipairs({here or false, further or false}) do
                if score and (not best or score > best) then best = score end
            end
        end
    end
    return best
end

virtuals = function(kinds)
    local out = {}
    for _, kind in ipairs(kinds) do
        local item = made(kind)
        if item then out[#out + 1] = {item = item, carried = true, virtual = true} end
    end
    return out
end

-- The craft that leads to a better meal than the best dish now (planned), or
-- nil. Each craft's results are made up for a moment and the dish planner asked
-- again; so is a second craft those results would allow (dough, then a crust).
-- A craft whose result is a meal on its own counts what it adds over its inputs,
-- and only when nothing else is ready to eat.
function Craft.best(player, found, planned, heatFor, skipped, now)
    local bar = planned and planned.score or 0
    local best
    local budget = {left = Craft.policy.trials}
    local options = Craft.options(player, found, skipped, now)
    for _, option in ipairs(fillOptions(found, skipped, now)) do options[#options + 1] = option end
    -- For the log: how many were possible, and the best of them even when it lost.
    local look = {options = #options, bar = math.floor(bar), surface = found.surface ~= nil}
    for _, option in ipairs(options) do
        local gone = {}
        for _, item in ipairs(option.inputs) do if not option.def.keep[item:getFullType()] then gone[item] = true end end
        local virtual = virtuals(option.outputs)
        local score = Options.makeSoup() and trial(player, found, virtual, gone, heatFor, skipped, now) or nil
        if score then score = score - Craft.policy.penalty * (option.fill and 2 or 1) end
        local forDish = score ~= nil
        -- Further crafts its results allow, toward a dish: dough, a crust, the pie.
        if Options.makeSoup() and not option.fill then
            local deeper = chain(player, found, option.outputs, gone, heatFor, skipped, now, 1, budget, {[option.def.name] = true})
            if deeper and (not score or deeper > score) then score, forDish = deeper, true end
        end
        if (found.ready or 0) == 0 and not option.fill then
            for _, entry in ipairs(virtual) do
                local raw = instanceof(entry.item, "Food") and entry.item:isbDangerousUncooked() and not entry.item:isCooked()
                if not raw or heatFor(entry.item) then
                    local gain = worth(player, entry.item) - cost(player, option.inputs, option.def) - Craft.policy.penalty
                    if gain > 0 and (not score or gain > score) then score, forDish = gain, false end
                end
            end
        end
        if score and (not look.score or score > look.score) then look.top, look.score = option.def.name, math.floor(score) end
        if score and score > bar and (not best or score > best.score) then best = {option = option, score = score, forDish = forDish} end
    end
    return best, look
end

-- ------------------------------------------------------------------- the steps

local function newOutputs(player, entry)
    local before, new, wanted = {}, {}, {}
    for _, id in ipairs(entry.before or {}) do before[id] = true end
    for _, kind in ipairs(entry.outputs) do wanted[kind] = true end
    for _, container in ipairs(carried(player)) do
        local items = container:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if wanted[item:getFullType()] and not before[item:getID()] then new[#new + 1] = item:getID() end
        end
    end
    -- A full inventory makes the game drop it at the survivor's feet.
    local square = player:getSquare()
    local worlds = square and square.getWorldObjects and square:getWorldObjects()
    for index = 0, worlds and worlds:size() - 1 or -1 do
        local item = read(function() return worlds:get(index):getItem() end)
        if item and wanted[item:getFullType()] and not before[item:getID()] then new[#new + 1] = item:getID() end
    end
    return new
end

local function snapshot(player, entry)
    entry.before = {}
    local saved = entry.before
    entry.before = nil
    for _, id in ipairs(newOutputs(player, entry)) do saved[#saved + 1] = id end
    entry.before = saved
end

local function release(state, entry)
    for _, id in ipairs(entry.inputs or {}) do state.rejected[id] = nil end
end

-- Tools borrowed for the craft (a knife, a tin opener, a pan) go back where
-- they came from once it is over: the controller's loans return them.
local function giveBack(player, state, entry)
    local sources = Craft.sources and Craft.sources[player]
    for _, item in ipairs(sources and sources.tools or {}) do
        if P.lend then P.lend(player, state, item, false) end
    end
    if sources then sources.tools = nil end
    entry.tools = nil
end

local function fail(player, state, now, entry, why)
    Log.event(player, "craft.giveup", "why", why, "stage", entry.stage, "craft", entry.craft)
    release(state, entry)
    giveBack(player, state, entry)
    state.kitchenSkip = state.kitchenSkip or {}
    state.kitchenSkip["craft:" .. entry.craft] = now + Craft.policy.retryMs
    if Craft.sources then Craft.sources[player] = nil end
    K.write(player, nil)
    return false
end
Craft.abandon = fail
function Craft.forget(player) if Craft.sources then Craft.sources[player] = nil end end

local function finish(player, state, entry, new)
    release(state, entry)
    giveBack(player, state, entry)
    Craft.forget(player)
    K.write(player, nil)
    -- Look again soon when the craft was for a dish: that dish comes next.
    if entry.forDish then state.kitchenNext, state.preferNext = nil, nil end
    Log.event(player, "craft.made", "craft", entry.craft, "made", #new)
    return false
end

-- Starts the chosen craft. Returns true when its first step was queued.
function Craft.start(player, state, now, best)
    local option, inventory = best.option, player:getInventory()
    if option.fill then
        local vessel, tapSquare = option.fill.vessel, option.fill.tap.square
        if not vessel.carried and not inventory:hasRoomFor(player, vessel.item) then return false, "room", vessel.item:getActualWeight() end
        local entry = {stage = "craft-fill", craft = option.def.name, vessel = vessel.item:getID(), amount = option.def.fill.amount,
            tap = {x = tapSquare:getX(), y = tapSquare:getY(), z = tapSquare:getZ()}, tries = 0, forDish = true,
            name = "Filling " .. vessel.item:getDisplayName() .. " with water"}
        state.rejected[vessel.item:getID()] = now + Craft.policy.holdMs
        entry.inputs = {vessel.item:getID()}
        Craft.sources = Craft.sources or {}
        Craft.sources[player] = {entries = vessel.carried and {} or {vessel}}
        K.write(player, entry)
        Log.event(player, "craft.fill", "craft", option.def.name, "vessel", vessel.item:getFullType(), "amount", entry.amount, "score", math.floor(best.score))
        if Craft.step(player, state, now, entry) then return true end
        release(state, entry)
        Craft.sources[player] = nil
        K.write(player, nil)
        return false
    end
    local ids, entries, weight, tools = {}, {}, 0, {}
    for _, item in ipairs(option.inputs) do
        ids[#ids + 1] = item:getID()
        local container = item:getContainer()
        if container ~= inventory and not (container and container:getOutermostContainer() == inventory) then
            weight = weight + item:getActualWeight()
            entries[#entries + 1] = Fetch.entry(item, container, nil, false)
            -- A tool from a cupboard is borrowed, not kept.
            if option.def.keep[item:getFullType()] then tools[#tools + 1] = item end
        end
    end
    for _, kind in ipairs(option.outputs) do
        local item = made(kind)
        weight = weight + (item and item:getActualWeight() or 0)
    end
    if not inventory:hasRoomFor(player, weight) then return false, "room", weight end
    local surface = option.surface and option.surface.getSquare and option.surface:getSquare()
    local entry = {stage = "craft-fetch", craft = option.def.name, inputs = ids, outputs = option.outputs,
        surface = surface and {x = surface:getX(), y = surface:getY(), z = surface:getZ()} or nil, tries = 0,
        name = read(function() return option.def.recipe:getTranslationName() end) or option.def.name,
        forDish = best.forDish == true}
    -- Borrowed while it is where it came from, so the return knows that place.
    entry.tools = {}
    local lent = {}
    for _, item in ipairs(tools) do
        if P.lend and P.lend(player, state, item, true) then entry.tools[#entry.tools + 1] = item:getID(); lent[#lent + 1] = item end
    end
    for _, id in ipairs(ids) do state.rejected[id] = now + Craft.policy.holdMs end
    Craft.sources = Craft.sources or {}
    Craft.sources[player] = {entries = entries, tools = lent}
    K.write(player, entry)
    Log.event(player, "craft.start", "craft", option.def.name, "inputs", #ids, "fetch", #entries, "makes", table.concat(option.outputs, "+"),
        "score", math.floor(best.score))
    if Craft.step(player, state, now, entry) then return true end
    release(state, entry)
    giveBack(player, state, entry)
    Craft.sources[player] = nil
    K.write(player, nil)
    return false
end

local function defNamed(name)
    for _, def in ipairs(Craft.catalog().list) do if def.name == name then return def end end
    return nil
end

-- One batch for the stage the craft is at.
function Craft.step(player, state, now, entry)
    local inventory = player:getInventory()
    local sources = Craft.sources and Craft.sources[player]
    if not Options.makeSoup() then return fail(player, state, now, entry, "turned-off") end
    local lower = string.lower(entry.name)
    if entry.stage == "craft-fill" then
        local vessel = inventory:getItemById(entry.vessel)
        if not vessel then
            local source = sources and sources.entries[1]
            if not source or not Fetch.present(source) then return fail(player, state, now, entry, "vessel-gone") end
            return P.ownBatch(player, state, "kitchen", "Getting " .. source.item:getDisplayName() .. " to fill.", function()
                local square = Fetch.square(source)
                if square and not Grid.reachable(player:getSquare(), square) and not luautils.walkAdj(player, square, true) then return end
                Fetch.queue(player, source)
            end)
        end
        -- Full enough: the craft itself now, with the real pot, before anything
        -- else (eating) can take what it needs.
        if water(vessel) >= entry.amount then
            release(state, entry)
            Craft.forget(player)
            K.write(player, nil)
            Log.event(player, "craft.filled", "craft", entry.craft, "litres", water(vessel))
            local found = K.scan and K.scan(player, state.kitchenSkip, now)
            for _, option in ipairs(found and Craft.options(player, found, state.kitchenSkip, now) or {}) do
                if option.def.name == entry.craft then
                    return Craft.start(player, state, now, {option = option, score = 0, forDish = true})
                end
            end
            state.kitchenNext, state.preferNext = nil, nil
            return false
        end
        local square = getCell():getGridSquare(entry.tap.x, entry.tap.y, entry.tap.z)
        local tap
        local objects = square and square:getObjects()
        for index = 0, objects and objects:size() - 1 or -1 do
            if not tap and Dish.isTap(objects:get(index)) then tap = objects:get(index) end
        end
        if not tap then return fail(player, state, now, entry, "no-water") end
        entry.before = {water(vessel)}
        K.write(player, entry)
        return P.ownBatch(player, state, "kitchen", entry.name .. ".", function()
            if not Grid.reachable(player:getSquare(), square) and not luautils.walkAdj(player, square, true) then return end
            ISTimedActionQueue.add(ISTakeWaterAction:new(player, vessel, tap, false))
        end)
    elseif entry.stage == "craft-fetch" then
        if not sources then return fail(player, state, now, entry, "reloaded") end
        local missing = {}
        for _, source in ipairs(sources.entries) do
            if not inventory:getItemById(source.item:getID()) then
                if not Fetch.present(source) then return fail(player, state, now, entry, "input-gone") end
                missing[#missing + 1] = source
            end
        end
        if #missing == 0 then
            entry.stage = entry.surface and "craft-walk" or "craft-make"
            K.write(player, entry)
            return Craft.step(player, state, now, entry)
        end
        return P.ownBatch(player, state, "kitchen", "Getting what it takes to " .. lower .. ".", function()
            local square = Fetch.square(missing[1])
            if square and not Grid.reachable(player:getSquare(), square) and not luautils.walkAdj(player, square, true) then return end
            for _, source in ipairs(missing) do
                if source.from == missing[1].from then Fetch.queue(player, source) end
            end
        end)
    elseif entry.stage == "craft-walk" then
        local square = entry.surface and getCell():getGridSquare(entry.surface.x, entry.surface.y, entry.surface.z)
        if not square then return fail(player, state, now, entry, "surface-gone") end
        if Grid.reachable(player:getSquare(), square) then
            entry.stage = "craft-make"; K.write(player, entry)
            return Craft.step(player, state, now, entry)
        end
        entry.walks = (entry.walks or 0) + 1
        if entry.walks > Craft.policy.tries then return fail(player, state, now, entry, "surface-unreachable") end
        K.write(player, entry)
        return P.ownBatch(player, state, "kitchen", "Going to the counter.", function()
            luautils.walkAdj(player, square, true)
        end)
    elseif entry.stage == "craft-make" then
        -- Made already, but told late (multiplayer): done.
        if entry.before then
            local new = newOutputs(player, entry)
            if #new > 0 then return finish(player, state, entry, new) end
        end
        local def = defNamed(entry.craft)
        if not def then return fail(player, state, now, entry, "unknown") end
        local probe = read(function() return HandcraftLogic.new(player, nil, nil) end)
        local surface = def.surface and probe and read(function() return probe:findCraftSurface(player, 2) end) or nil
        if def.surface and not surface then return fail(player, state, now, entry, "no-surface") end
        local logic = Craft.logic(player, def, carried(player), surface)
        if not logic then return fail(player, state, now, entry, "cannot-make") end
        -- Started as the game's own menu starts it: from one of its inputs, which
        -- sets the inputs the action is built from.
        local anchor
        for _, item in ipairs(inputsOf(logic)) do if not anchor and not def.keep[item:getFullType()] then anchor = item end end
        if anchor then
            logic:setRecipeFromContextClick(def.recipe, anchor)
            if not read(function() return logic:canPerformCurrentRecipe() end, false) then return fail(player, state, now, entry, "cannot-make") end
        end
        -- Exactly what was planned goes in: nothing the survivor kept back.
        local planned = {}
        for _, id in ipairs(entry.inputs) do planned[id] = true end
        for _, item in ipairs(inputsOf(logic)) do
            if not planned[item:getID()] and not def.keep[item:getFullType()] then return fail(player, state, now, entry, "inputs-changed") end
        end
        snapshot(player, entry)
        K.write(player, entry)
        return P.ownBatch(player, state, "kitchen", entry.name .. ".", function()
            local action = ISEntityUI.HandcraftStart(player, logic, false, true)
            if not action then return end
            action:setOnComplete(ISInventoryPaneContextMenu.OnNewCraftComplete, logic)
            logic:startCraftAction(action)
        end)
    end
    return false
end

-- After each batch. A craft is done when something it makes is new, in the
-- pockets or at the survivor's feet.
function Craft.settle(player, state, now, cut)
    local entry = K.ledger(player)
    if not entry then return end
    local inventory = player:getInventory()
    if entry.stage == "craft-fill" then
        local vessel = inventory:getItemById(entry.vessel)
        if cut or not vessel then return end
        -- No more water than before, again and again: the tap or the pot will not do.
        local before = entry.before and entry.before[1]
        if before and water(vessel) <= before then
            entry.tries = (entry.tries or 0) + 1
            if entry.tries >= Craft.policy.tries then return fail(player, state, now, entry, "not-filled") end
        end
        entry.before = nil
        K.write(player, entry)
        return
    end
    if entry.stage == "craft-fetch" then
        local sources = Craft.sources and Craft.sources[player]
        local count = 0
        for _, source in ipairs(sources and sources.entries or {}) do if inventory:getItemById(source.item:getID()) then count = count + 1 end end
        if cut then return end
        -- No closer than before, again and again: what is out of reach stays out of reach.
        entry.stalls = count > (entry.fetched or 0) and 0 or (entry.stalls or 0) + 1
        entry.fetched = count
        if entry.stalls >= 2 then return fail(player, state, now, entry, "fetch-stalled") end
        K.write(player, entry)
    elseif entry.stage == "craft-make" then
        local new = newOutputs(player, entry)
        if #new > 0 then return finish(player, state, entry, new) end
        -- Stopped (darkness, danger) or not told yet: a few more tries, then rest.
        entry.tries = (entry.tries or 0) + 1
        if entry.tries > Craft.policy.tries then return fail(player, state, now, entry, cut and "interrupted" or "nothing-made") end
        K.write(player, entry)
    end
end

return Craft
