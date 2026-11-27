-- Dressing care against the game's crafts: CleanBandage takes a dirty
-- bandage or strip and 0.5 l of water; DisinfectRag a clean bandage or rag
-- and 0.1 l of rubbing alcohol, vodka or whiskey (recipes_medical.txt).
package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
for _, name in ipairs({"ISApplyBandage", "ISRemoveGlass", "ISRemoveBullet", "ISDisinfect", "ISStitch", "ISSplint",
        "ISCleanBurn", "ISComfreyCataplasm", "ISGarlicCataplasm", "ISPlantainCataplasm"}) do
    package.loaded["TimedActions/" .. name] = true
end
package.loaded["AutoMindful/Fluids"] = {isWater = function(fluid) return fluid.water == true end}
function getTimestampMs() return 0 end
ItemTag, ComponentType, Perks = {}, {FluidContainer = "fluid"}, {Doctor = "doctor"}

local Dressings = require "AutoMindful/Dressings"
local roles = Dressings.roles

local function item(kind, fluid)
    local primary = fluid and {getFluidTypeString = function() return fluid.type or "Water" end}
    return {kind = kind, getType = function() return kind end, getWorldItem = function() return nil end,
        getFluidContainer = function()
            if not fluid then return nil end
            return {getAmount = function() return fluid.amount end, isTainted = function() return fluid.tainted == true end,
                water = fluid.water, getPrimaryFluid = function() return primary end, getProperties = function() return {getAlcohol = function() return fluid.alcohol or 0 end} end}
        end}
end

-- What may be washed, and what sterilized.
assert(roles.dirty.match(item("BandageDirty")) and roles.dirty.match(item("RippedSheetsDirty")) and not roles.dirty.match(item("Bandage")))
assert(roles.plain.match(item("Bandage")) and roles.plain.match(item("RippedSheets")) and not roles.plain.match(item("AlcoholBandage")))
-- Water: clean, and enough that some is left to drink.
assert(roles.water.match(item("WaterBottle", {amount = 1, water = true})))
assert(not roles.water.match(item("WaterBottle", {amount = 0.6, water = true})), "the last drink is not washing water")
assert(not roles.water.match(item("WaterBottle", {amount = 1, water = true, tainted = true})))
assert(not roles.water.match(item("PopBottle", {amount = 1, water = false})))
-- Spirit: at least 0.1 l of something strong; disinfectant before a drink.
local disinfectant = item("Disinfectant", {amount = 0.5, alcohol = 0.5, type = "RubbingAlcohol"})
local vodka = item("Vodka", {amount = 0.75, alcohol = 0.3, type = "Vodka"})
local cologne = item("Cologne", {amount = 0.2, alcohol = 0.2, type = "Cologne"})
local beer = item("BeerBottle", {amount = 0.5, alcohol = 0.025, type = "Beer"})
assert(roles.spirit.match(disinfectant) and roles.spirit.match(vodka) and not roles.spirit.match(beer) and not roles.spirit.match(cologne), "only what DisinfectRag takes")
assert(roles.spirit.grade(disinfectant) < roles.spirit.grade(vodka))
assert(not roles.spirit.match(item("Disinfectant", {amount = 0.05, alcohol = 0.05, type = "RubbingAlcohol"})))
print("PASS what may be washed, sterilized, and with what")

-- Planning, over a picker double: role name -> entry.
local function body(parts)
    local list = {size = function() return #parts end, get = function(_, index) return parts[index + 1] end}
    return {getBodyParts = function() return list end}
end
local function wound(cover) return {bandaged = function() return cover end, deepWounded = function() return false end,
    scratched = function() return true end, isCut = function() return false end, bitten = function() return false end,
    getBurnTime = function() return 0 end} end
local function survivor(parts, carried)
    local items = {size = function() return #carried end, get = function(_, index) return carried[index + 1] end}
    return {getBodyDamage = function() return body(parts) end, getInventory = function() return {getItems = function() return items end} end}
end
local function looker(byRadius, scans)
    return function(radius)
        scans[#scans + 1] = radius
        local available = byRadius[radius] or {}
        return function(name) return available[name] end
    end
end

do
    -- Nothing carried to wash or sterilize: the area is not even searched.
    local scans = {}
    assert(Dressings.plan(survivor({}, {}), looker({}, scans), 10) == nil and #scans == 1 and scans[1] == 0)
    -- A dirty one carried and water nearby: washed.
    local dirty, water = {item = item("BandageDirty")}, {item = item("WaterBottle")}
    local job = Dressings.plan(survivor({}, {}), looker({[0] = {dirty = dirty}, [10] = {water = water}}, scans), 10)
    assert(job.kind == "wash" and job.recipe == "CleanBandage" and job.anchor == dirty and job.uses[1] == water)
    -- No water: nothing to do.
    assert(Dressings.plan(survivor({}, {}), looker({[0] = {dirty = dirty}}, {}), 10) == nil)
end
print("PASS a dirty dressing is washed when there is water to spare")

do
    local plain, spirit = {item = item("Bandage")}, {item = disinfectant}
    local function sterile()
        return {getType = function() return "AlcoholBandage" end, getBandagePower = function() return 4 end, isAlcoholic = function() return true end}
    end
    -- No wound: alcohol is not spent on dressings nobody needs yet.
    assert(Dressings.plan(survivor({}, {}), looker({[0] = {plain = plain}, [10] = {spirit = spirit}}, {}), 10) == nil)
    -- One wound, no sterile dressing carried: sterilize.
    local job = Dressings.plan(survivor({wound(true)}, {}), looker({[0] = {plain = plain}, [10] = {spirit = spirit}}, {}), 10)
    assert(job.kind == "sterilize" and job.recipe == "DisinfectRag" and job.uses[1] == spirit)
    -- One wound and a spare sterile already: enough.
    assert(Dressings.plan(survivor({wound(true)}, {sterile(), sterile()}), looker({[0] = {plain = plain}, [10] = {spirit = spirit}}, {}), 10) == nil)
end
print("PASS clean dressings are sterilized for the wounds there are, one spare")
