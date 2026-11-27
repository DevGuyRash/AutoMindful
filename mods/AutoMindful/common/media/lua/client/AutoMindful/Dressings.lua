-- Dressings looked after between wounds, with the game's own crafts: a dirty
-- bandage or rag washed in clean water (CleanBandage), a clean one sterilized
-- with alcohol (DisinfectRag) or in water hot off a heat (DisinfectBandage).
-- Judgement only: Recovery queues the steps and checks what each changed.
local Fluids = require "AutoMindful/Fluids"
local FirstAid = require "AutoMindful/FirstAid"

local Dressings = {policy = {washLiters = 0.5, keepLiters = 0.5, spiritLiters = 0.1, spare = 1}}

local function read(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then return value end
    return fallback
end

local function kind(item) return read(function() return item:getType() end, "") end
local function fluidOf(item)
    local world = read(function() return item:getWorldItem() end)
    return world and world:getFluidContainer() or read(function() return item:getFluidContainer() end)
end

-- CleanBandage's inputs, and DisinfectRag's and DisinfectBandage's.
-- Dressings only: denim and leather strips are kept for tailoring.
local washable = {BandageDirty = true, RippedSheetsDirty = true}
local sterilizable = {Bandage = true, RippedSheets = true}
local spirits = {RubbingAlcohol = 1, Vodka = 2, Whiskey = 2}

Dressings.roles = {
    dirty = {match = function(item) return washable[kind(item)] == true end, consumed = true},
    plain = {match = function(item) return sterilizable[kind(item)] == true end, consumed = true},
    -- Clean water to wash in, with some left to drink afterwards.
    water = {match = function(item)
        local fluid = fluidOf(item)
        return fluid ~= nil and read(function()
            return fluid:getAmount() >= Dressings.policy.washLiters + Dressings.policy.keepLiters
                and Fluids.isWater(fluid) and not fluid:isTainted()
        end, false) == true
    end, grade = function(item) return -fluidOf(item):getAmount() end},
    -- RubbingAlcohol, Vodka or Whiskey: exactly what DisinfectRag takes (not
    -- cologne). Disinfectant is rubbing alcohol; a drink only when nothing else is there.
    spirit = {match = function(item)
        local fluid = fluidOf(item)
        return fluid ~= nil and read(function()
            return fluid:getAmount() >= Dressings.policy.spiritLiters and spirits[fluid:getPrimaryFluid():getFluidTypeString()] ~= nil
        end, false) == true
    end, grade = function(item) return spirits[fluidOf(item):getPrimaryFluid():getFluidTypeString()] end},
}

local recipes = {wash = "CleanBandage", spirit = "DisinfectRag", boil = "DisinfectBandage"}

-- The survivor's own containers: the main inventory and the bags in it,
-- as deep as first aid looks.
local function carried(player)
    local list = {}
    local function add(container, depth)
        list[#list + 1] = container
        local items = container:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if depth < 3 and instanceof(item, "InventoryContainer") then add(item:getInventory(), depth + 1) end
        end
    end
    add(player:getInventory(), 0)
    return list
end

-- The game's crafting logic for a recipe, started from one input as its own
-- menu does, with what is carried; nil when the survivor cannot make it now,
-- and "last-drink" when the game would wash in water someone may need to drink.
function Dressings.logic(player, name, anchor)
    local recipe = read(function() return getScriptManager():getCraftRecipe(name) end)
    local logic = recipe and read(function() return HandcraftLogic.new(player, nil, nil) end)
    if not logic then return nil end
    local list = ArrayList.new()
    for _, container in ipairs(carried(player)) do list:add(container) end
    logic:setContainers(list)
    logic:setRecipe(recipe)
    if not read(function() return logic:isRecipeAvailableForCharacter(recipe) end, false) then return nil end
    if anchor then logic:setRecipeFromContextClick(recipe, anchor) end
    if not read(function() return logic:canPerformCurrentRecipe() end, false) then return nil end
    -- The game picks the other inputs itself: never someone's last drink.
    if name == recipes.wash then
        local items = read(function() return logic:getRecipeData():getAllInputItems() end)
        for index = 0, items and items:size() - 1 or -1 do
            local fluid = fluidOf(items:get(index))
            if fluid and fluid:getAmount() < Dressings.policy.washLiters + Dressings.policy.keepLiters then return nil, "last-drink" end
        end
    end
    return logic
end

-- Queues the craft; true when the game's action was queued.
function Dressings.craft(player, logic)
    local action = ISEntityUI.HandcraftStart(player, logic, false, true)
    if not action then return false end
    action:setOnComplete(ISInventoryPaneContextMenu.OnNewCraftComplete, logic)
    logic:startCraftAction(action)
    return true
end

Dressings.recipes = recipes

-- How many wounds would take a dressing now or soon, and how many sterile
-- dressings are carried for them.
function Dressings.need(player)
    local parts = player:getBodyDamage():getBodyParts()
    local wounds, sterile = 0, 0
    for index = 0, parts:size() - 1 do
        local part = parts:get(index)
        if part.bandaged and (part:bandaged() or FirstAid.open(part)) then wounds = wounds + 1 end
    end
    for _, container in ipairs(carried(player)) do
        local items = container:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if item.getBandagePower and item:getBandagePower() > 0 and read(function() return item:isAlcoholic() end, false)
                    and not string.find(kind(item), "Dirty", 1, true) then sterile = sterile + 1 end
        end
    end
    return wounds, sterile
end

-- The next dressing job, or nil. look(radius) gives FirstAid's picker with
-- these roles; the area is searched only once a carried dressing needs care.
-- A step: {kind = "wash" or "sterilize", recipe, anchor, uses}; anchor and
-- uses are found entries, the anchor always carried.
function Dressings.plan(player, look, radius)
    local carried = look(0)
    local dirty = carried("dirty", {carried = true})
    local wounds, sterile = Dressings.need(player)
    local plain = wounds > 0 and sterile < wounds + Dressings.policy.spare and carried("plain", {carried = true}) or nil
    if not dirty and not plain then return nil end
    local pick = look(radius)
    local water = dirty and pick("water")
    if water then return {kind = "wash", recipe = recipes.wash, anchor = dirty, uses = {water}} end
    local spirit = plain and pick("spirit")
    if spirit then return {kind = "sterilize", recipe = recipes.spirit, anchor = plain, uses = {spirit}} end
    return nil
end

FirstAid.addRoles(Dressings.roles)

return Dressings
