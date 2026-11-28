-- The first aid planner against the game's own doctor-menu rules
-- (ISHealthPanel's handlers and the timed actions under media/lua/shared).
-- Body parts, items and the world are doubles; every expected order comes
-- from those rules, not from the planner.
package.path = "mods/SecondNature/common/media/lua/client/?.lua;" .. package.path
for _, name in ipairs({"ISApplyBandage", "ISRemoveGlass", "ISRemoveBullet", "ISDisinfect", "ISStitch", "ISSplint",
        "ISCleanBurn", "ISComfreyCataplasm", "ISGarlicCataplasm", "ISPlantainCataplasm"}) do
    package.loaded["TimedActions/" .. name] = true
end

local function list(values)
    values.size = function(self) return #self end
    values.get = function(self, index) return self[index + 1] end
    values.contains = function(self, value) for _, v in ipairs(self) do if v == value then return true end end return false end
    return values
end
function instanceof(value, kind) return type(value) == "table" and value.kind == kind end
function getTimestampMs() return 0 end
function isClient() return false end
ItemTag = {REMOVE_GLASS = "removeglass", REMOVE_BULLET = "removebullet", SEWING_NEEDLE = "sewingneedle", THREAD = "thread"}
ComponentType = {FluidContainer = "fluid"}
Perks = {Doctor = "doctor"}
CharacterTrait = {HEMOPHOBIC = "hemophobic"}
MoodleType = {PANIC = "panic"}
BodyPartType = {getDisplayName = function(kind) return kind end}
local function action(name) return {new = function(_, ...) return {Type = name, args = {...}} end} end
ISApplyBandage, ISRemoveGlass, ISRemoveBullet, ISDisinfect = action("bandage"), action("glass"), action("bullet"), action("disinfect")
ISStitch, ISSplint, ISCleanBurn = action("stitch"), action("splint"), action("burn")
ISComfreyCataplasm, ISGarlicCataplasm, ISPlantainCataplasm = action("comfrey"), action("garlic"), action("plantain")

local function container()
    local c = {items = list({})}
    function c:getItems() return self.items end
    function c:contains(item) return self.items:contains(item) end
    function c:getSourceGrid() return nil end
    function c:getItemById(id) for _, it in ipairs(self.items) do if it:getID() == id then return it end end end
    function c:getContainingItem() return self.bag end
    function c:getType() return "none" end
    return c
end

local nextID = 0
local function item(kind, fields)
    local i = fields or {}
    nextID = nextID + 1
    i.id = i.id or nextID
    i.type = kind
    function i:getType() return self.type end
    function i:getDisplayName() return self.type end
    function i:getBandagePower() return self.power or 0 end
    function i:isAlcoholic() return self.alcoholic == true end
    function i:isInfected() return false end
    function i:isFavorite() return false end
    function i:hasTag(tag) return self.tags ~= nil and self.tags[tag] == true end
    function i:hasComponent(kind) return kind == "fluid" and self.fluid ~= nil end
    function i:getFluidContainer()
        local f = self.fluid
        if not f then return nil end
        return {getAmount = function() return f.amount end, getProperties = function() return {getAlcohol = function() return f.alcohol end} end}
    end
    function i:IsDrainable() return self.drainable == true end
    function i:getAlcoholPower() return self.alcoholPower or 0 end
    function i:getCurrentUsesFloat() return self.uses or 1 end
    function i:getContainer() return self.container end
    function i:getWorldItem() return nil end
    function i:getID() return self.id end
    return i
end

local function put(where, it)
    where.items[#where.items + 1] = it
    it.container = where
    return it
end

-- As the game keeps a body part: a dressing hides the bleeding, cut,
-- scratch, bite, deep-wound and stitched flags; their timers stay.
local function part(kind, fields)
    local b = fields or {}
    b.kind = kind
    local function shown(value) return value == true and not b.cover end
    function b:getType() return self.kind end
    function b:bandaged() return self.cover == true end
    function b:isBandageDirty() return self.filthy == true end
    function b:bleeding() return shown(self.blood) end
    function b:getBleedingTime() return self.blood and 10 or 0 end
    function b:scratched() return shown(self.scratch) end
    function b:getScratchTime() return self.scratch and 10 or 0 end
    function b:isCut() return shown(self.cut) end
    function b:getCutTime() return self.cut and 10 or 0 end
    function b:deepWounded() return shown(self.deep) end
    function b:getDeepWoundTime() return self.deep and 10 or 0 end
    function b:bitten() return shown(self.bite) end
    function b:getBiteTime() return self.bite and 10 or 0 end
    function b:stitched() return shown(self.stitches) end
    function b:getStitchTime() return self.stitches and (self.stitchTime or 5) or 0 end
    function b:getBurnTime() return self.burn or 0 end
    function b:isNeedBurnWash() return self.wash == true end
    function b:haveGlass() return self.glass == true end
    function b:haveBullet() return self.bullet == true end
    function b:isInfectedWound() return self.infected == true end
    function b:getWoundInfectionLevel() return self.infection or 0 end
    function b:getFractureTime() return self.fracture or 0 end
    function b:getSplintFactor() return self.splint or 0 end
    function b:getAlcoholLevel() return self.alcohol or 0 end
    function b:getPlantainFactor() return 0 end
    function b:getComfreyFactor() return 0 end
    function b:getGarlicFactor() return 0 end
    return b
end

local function survivor(parts, fields)
    local p = fields or {}
    p.inventory = container()
    p.parts = list(parts)
    p.square = {getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end}
    function p:getInventory() return self.inventory end
    function p:getSquare() return self.square end
    function p:getBodyDamage() local parts = self.parts; return {getBodyParts = function() return parts end} end
    function p:getPerkLevel() return self.doctor or 0 end
    function p:hasTrait(trait) return self.traits ~= nil and self.traits[trait] == true end
    function p:getMoodles() local panic = self.panic or 0; return {getMoodleLevel = function() return panic end} end
    return p
end

local FirstAid = require "AutoMindful/FirstAid"

-- Plays steps the way the game would: each action changes the body as its
-- complete() does, and items it uses up leave the inventory.
local function run(p, limit)
    local kinds = {}
    for _ = 1, limit or 20 do
        local step, why = FirstAid.plan(p, {radius = 0})
        if not step then return kinds, why end
        kinds[#kinds + 1] = step.kind
        local b = step.part
        local function use(entry)
            local list = p.inventory.items
            for index, it in ipairs(list) do if it == entry.item then table.remove(list, index); break end end
        end
        if step.kind == "take" then
            for _, entry in ipairs(step.entries) do
                local from = entry.item.container.items
                for index, it in ipairs(from) do if it == entry.item then table.remove(from, index); break end end
                put(p.inventory, entry.item)
            end
        else
            local made = FirstAid.action(p, step)
            assert(made, "the game would refuse " .. step.kind)
            if step.kind == "unbandage" then b.cover, b.filthy = nil, nil
            elseif step.kind == "bandage" then b.cover = true; use(step.item)
            elseif step.kind == "glass" then b.glass = nil
            elseif step.kind == "bullet" then b.bullet = nil
            elseif step.kind == "disinfect" then b.alcohol = 4
            elseif step.kind == "splint" then b.splint = 1; use(step.plank); if step.sheet then use(step.sheet) end
            elseif step.kind == "stitch" then b.stitches, b.deep, b.blood = true, nil, nil
            elseif step.kind == "burn" then b.wash = nil; use(step.rag)
            elseif step.kind == "unstitch" then b.stitches = nil; b.scratch = true
            elseif step.kind == "unsplint" then b.splint = 0 end
            assert(FirstAid.done(p, step), step.kind .. " is read back from the body")
        end
    end
    return kinds
end
local function joined(kinds) return table.concat(kinds, ">") end
local function carry(p, kind, fields) return put(p.inventory, item(kind, fields)) end
local function kit(p)
    carry(p, "Tweezers", {tags = {removeglass = true, removebullet = true}})
    carry(p, "SutureNeedle")
    carry(p, "Disinfectant", {fluid = {amount = 1, alcohol = 1}})
    carry(p, "Bandage", {power = 4})
end

do
    -- Glass must be out before stitches go in (HStitch refuses with glass);
    -- every treatment needs the wound bare; the dressing goes on last.
    local arm = part("ForeArm_R", {deep = true, glass = true, blood = true})
    local p = survivor({arm})
    kit(p)
    local kinds = run(p)
    assert(joined(kinds) == "glass>disinfect>stitch>bandage", joined(kinds))
    assert(arm.cover and arm.stitches and not arm.glass)
end
print("PASS glass, disinfecting, stitches, then the dressing, in the game's order")

do
    -- Two wounds bleeding: both stopped before anything slower, the neck first.
    local arm = part("ForeArm_L", {cut = true, blood = true})
    local neck = part("Neck", {cut = true, blood = true})
    local p = survivor({arm, neck})
    carry(p, "Bandage", {power = 4}); carry(p, "Bandage", {power = 4})
    local first = FirstAid.plan(p, {radius = 0})
    assert(first.kind == "bandage" and first.part == neck and first.urgent, first.kind)
    local kinds = run(p)
    assert(joined(kinds) == "bandage>bandage" and arm.cover and neck.cover, joined(kinds))
end
print("PASS heavy bleeding first, where it kills fastest")

do
    -- A stitched limb cannot be splinted (HSplint), so the splint goes on
    -- first; a wooden plank needs ripped sheets to tie it.
    local leg = part("LowerLeg_L", {deep = true, fracture = 30})
    local p = survivor({leg})
    carry(p, "SutureNeedle"); carry(p, "Plank"); carry(p, "RippedSheets", {power = 2}); carry(p, "Bandage", {power = 4})
    local kinds = run(p)
    assert(joined(kinds) == "splint>stitch>bandage", joined(kinds))
    assert(leg.splint > 0 and leg.stitches)
    -- Head and chest are never splinted.
    local chest = part("Torso_Upper", {fracture = 30})
    local q = survivor({chest}); carry(q, "Splint")
    assert(FirstAid.plan(q, {radius = 0}) == nil)
end
print("PASS splint before stitches, never on the head or chest")

do
    -- An unstitched deep wound under a dirty dressing: nothing to do without
    -- a needle (changing it only wastes dressings); with one, the dressing
    -- comes off only once everything is at hand.
    local leg = part("UpperLeg_L", {deep = true, cover = true, filthy = true})
    local p = survivor({leg})
    carry(p, "Bandage", {power = 4}); carry(p, "Bandage", {power = 4})
    assert(FirstAid.plan(p, {radius = 0}) == nil, "no churn without a needle")
    local bag = item("Bag_FirstAid"); bag.kind = "InventoryContainer"
    local inside = container(); inside.bag = bag
    function bag:getInventory() return inside end
    put(p.inventory, bag)
    put(inside, item("SutureNeedle"))
    local kinds = run(p)
    assert(joined(kinds) == "take>unbandage>stitch>bandage", joined(kinds))
end
print("PASS what a wound takes is fetched before its dressing comes off")

do
    -- Stitches come out only once good (over 40), or the wound opens again.
    local hand = part("Hand_R", {stitches = true, stitchTime = 30})
    local p = survivor({hand})
    carry(p, "Bandage", {power = 4})
    local step = FirstAid.plan(p, {radius = 0})
    assert(step and step.kind == "bandage", "fresh stitches are dressed, not pulled")
    hand.cover = true
    assert(FirstAid.plan(p, {radius = 0}) == nil)
    hand.stitchTime = 45; hand.cover = nil
    local kinds = run(p)
    assert(kinds[1] == "unstitch", joined(kinds))
    -- A healed bone's splint comes off and gives its wood back.
    local shin = part("LowerLeg_R", {splint = 2, fracture = 0})
    local q = survivor({shin})
    assert(joined(run(q)) == "unsplint")
end
print("PASS stitches and splints come off only once healed")

do
    -- Only a good doctor sees an infection early (the health panel's rule).
    local hand = part("Hand_L", {cut = true, infected = true, infection = 0.1})
    local p = survivor({hand}, {doctor = 0})
    carry(p, "Disinfectant", {fluid = {amount = 1, alcohol = 1}})
    local step = FirstAid.plan(p, {radius = 0})
    -- Not seen: a cut with no sterile dressing is still disinfected before it is dressed.
    assert(step and step.kind == "disinfect" and step.danger < 50, tostring(step and step.danger))
    p.doctor = 9
    step = FirstAid.plan(p, {radius = 0})
    assert(step.kind == "disinfect" and step.danger == 50, "a known infection ranks as one")
    -- A known infection under a dressing: the dressing comes off for it.
    hand.cover = true
    step = FirstAid.plan(p, {radius = 0})
    assert(step.kind == "unbandage", step.kind)
end
print("PASS infections are seen as the survivor's skill allows, and treated")

do
    -- Hemophobic and already panicking: what draws blood waits, unless the
    -- wound bleeds.
    local leg = part("UpperLeg_L", {deep = true, cover = true})
    local p = survivor({leg}, {traits = {hemophobic = true}, panic = 3})
    carry(p, "SutureNeedle"); carry(p, "Bandage", {power = 4})
    local step, why = FirstAid.plan(p, {radius = 0})
    assert(step == nil and why == "calming", "the dressing stays on while the stitches would have to wait")
    leg.cover = nil
    step, why = FirstAid.plan(p, {radius = 0})
    assert(step == nil and why == "calming", tostring(why))
    leg.blood = true
    step = FirstAid.plan(p, {radius = 0})
    assert(step and step.kind == "stitch" and step.urgent)
end
print("PASS the sight of blood is respected, but not over bleeding")

do
    -- A bullet with nothing to take it out: the wound is still dressed.
    local arm = part("UpperArm_R", {bullet = true, blood = true})
    local p = survivor({arm})
    carry(p, "Bandage", {power = 4})
    assert(joined(run(p)) == "bandage")
    -- Disinfectant before vodka; a sterile dressing before a plain one; a
    -- dirty rag only on a wound that bleeds.
    local cut = part("ForeArm_L", {cut = true})
    local q = survivor({cut})
    local vodka = carry(q, "Vodka", {fluid = {amount = 1, alcohol = 0.4}})
    local spirit = carry(q, "Disinfectant", {fluid = {amount = 1, alcohol = 1}})
    carry(q, "BandageDirty", {power = 0.5})
    local step = FirstAid.plan(q, {radius = 0})
    assert(step.kind == "disinfect" and step.alcohol.item == spirit and vodka)
    cut.alcohol = 4
    assert(FirstAid.plan(q, {radius = 0}) == nil, "a dirty rag is not worth an infection")
    local sterile = carry(q, "AlcoholBandage", {power = 4, alcoholic = true})
    carry(q, "Bandage", {power = 4})
    step = FirstAid.plan(q, {radius = 0})
    assert(step.kind == "bandage" and step.item.item == sterile)
    -- A burn is cleaned with the plainest cloth the game allows, then dressed.
    local hand = part("Hand_R", {burn = 50, wash = true})
    local r = survivor({hand})
    carry(r, "Bandage", {power = 4}); local rag = carry(r, "RippedSheets", {power = 2})
    step = FirstAid.plan(r, {radius = 0})
    assert(step.kind == "burn" and step.rag.item == rag)
    assert(joined(run(r)) == "burn>bandage")
end
print("PASS missing tools are worked around, and the right supply is used for each job")

do
    -- Under a dressing the game hides the deep wound; it is still stitched.
    local neck = part("Neck", {deep = true, blood = true, cover = true})
    local p = survivor({neck})
    kit(p)
    local kinds = run(p)
    assert(joined(kinds) == "unbandage>disinfect>stitch>bandage", joined(kinds))
    -- Glass in a dressed, bleeding neck: out once, not a dressing on and off for ever.
    local throat = part("Neck", {deep = true, blood = true, glass = true, cover = true})
    local q = survivor({throat})
    kit(q); carry(q, "Bandage", {power = 4})
    kinds = run(q, 12)
    assert(joined(kinds) == "unbandage>glass>disinfect>stitch>bandage", joined(kinds))
end
print("PASS a dressing hides the wound from the eye, not from the planner")

do
    -- A dressed burn that needs cleaning, with one cloth: the dressing stays
    -- on rather than leave the burn bare once the cloth is used.
    local hand = part("Hand_R", {burn = 50, wash = true, cover = true})
    local p = survivor({hand})
    carry(p, "RippedSheets", {power = 2})
    assert(FirstAid.plan(p, {radius = 0}) == nil)
    carry(p, "Bandage", {power = 4})
    local kinds = run(p)
    assert(joined(kinds) == "unbandage>burn>bandage", joined(kinds))
end
print("PASS a dressing comes off for a small job only with another to follow")

do
    -- Danger near: a bleeding wound gets a dressing where it stands, nothing slower.
    local arm = part("ForeArm_R", {deep = true, glass = true, blood = true})
    local p = survivor({arm})
    kit(p)
    local step = FirstAid.plan(p, {radius = 0, hurry = true})
    assert(step.kind == "bandage" and step.urgent)
    -- Something the game would not move is passed over for a while.
    local leg = part("ForeArm_L", {cut = true})
    local q = survivor({leg})
    local first = carry(q, "Bandage", {power = 4})
    local second = carry(q, "Bandage", {power = 4})
    step = FirstAid.plan(q, {radius = 0, rejected = {[first.id] = 100}, now = 10})
    assert(step.kind == "bandage" and step.item.item == second)
end
print("PASS danger keeps it to a dressing, and refused supplies are passed over")

do
    -- A broken neck is splinted: the game refuses only the head and chest.
    local neck = part("Neck", {fracture = 30})
    local p = survivor({neck}); carry(p, "Splint")
    assert(joined(run(p)) == "splint")
end
print("PASS a neck fracture is splinted like a limb")

do
    -- Asked for one part: only that part, then nothing more. Another wound
    -- that bleeds openly is dressed first all the same.
    local hand = part("Hand_R", {scratch = true})
    local leg = part("UpperLeg_L", {cut = true})
    local p = survivor({hand, leg})
    carry(p, "Bandage", {power = 4}); carry(p, "Bandage", {power = 4})
    local only = {[hand] = true}
    local step = FirstAid.plan(p, {radius = 0, only = only})
    assert(step.kind == "bandage" and step.part == hand, step.kind)
    hand.cover = true
    assert(FirstAid.plan(p, {radius = 0, only = only}) == nil, "the leg was not asked for")
    assert(FirstAid.plan(p, {radius = 0, onlyBleeding = true}) == nil, "nothing bleeds")
    leg.blood = true
    step = FirstAid.plan(p, {radius = 0, only = only})
    assert(step and step.part == leg and step.urgent, "a bleeding wound is never passed over")
end
print("PASS one part asked for is the one seen to, after any bleeding")

do
    -- A wound whose dressing came off stays first aid's job until another is
    -- on, whatever was asked next and whatever was refused.
    local arm = part("ForeArm_L", {cut = true})
    local hand = part("Hand_R", {scratch = true})
    local p = survivor({arm, hand})
    carry(p, "Bandage", {power = 4}); carry(p, "Bandage", {power = 4})
    local step = FirstAid.plan(p, {radius = 0, only = {[hand] = true}, keep = {[arm] = true},
        blocked = function(b) return b == arm end})
    assert(step.part == arm, "the bare forearm comes before the hand")
end
print("PASS a wound left bare is never dropped")

do
    -- A fresh dressing asked for on a clean one: off, then the chosen one on
    -- (HApplyBandage needs the part bare).
    local hand = part("Hand_R", {scratch = true, cover = true})
    local p = survivor({hand})
    carry(p, "Bandage", {power = 4})
    local sterile = carry(p, "AlcoholBandage", {power = 4, alcoholic = true})
    local plain = carry(p, "RippedSheets", {power = 2})
    assert(FirstAid.plan(p, {radius = 0}) == nil, "a clean dressing is left alone")
    local options = {radius = 0, only = {[hand] = true}, choice = function(b) return b == hand and {change = true, prefer = plain} or nil end}
    local step = FirstAid.plan(p, options)
    assert(step.kind == "unbandage" and step.part == hand, step.kind)
    hand.cover = nil
    step = FirstAid.plan(p, options)
    assert(step.kind == "bandage" and step.item.item == plain, "the chosen dressing, not the best one")
    local preview = FirstAid.preview(p, part("Hand_L", {scratch = true, cover = true}), 0, {change = true, prefer = sterile})
    assert(#preview.steps == 2 and preview.steps[1].kind == "unbandage" and preview.steps[2].item == "AlcoholBandage")
end
print("PASS a fresh dressing of the player's choosing replaces a clean one")

do
    -- Stitches still healing want a dressing; with none, the preview says so.
    local arm = part("ForeArm_L", {stitches = true, stitchTime = 10})
    local p = survivor({arm})
    local preview = FirstAid.preview(p, arm, 0)
    assert(#preview.steps == 0 and preview.missing[1] == "a bandage or a rag", tostring(preview.missing[1]))
    carry(p, "Bandage", {power = 4})
    preview = FirstAid.preview(p, arm, 0)
    assert(preview.steps[1].kind == "bandage" and preview.steps[1].carried and not preview.steps[1].walk)
end
print("PASS stitches that are healing need a dressing, and the preview says what is missing")

do
    -- The chosen dressing is only ever a dressing, and something the game
    -- refused is passed over even when chosen.
    local arm = part("ForeArm_L", {burn = 10, wash = true, cover = true})
    local p = survivor({arm})
    local chosen = carry(p, "AlcoholBandage", {power = 4, alcoholic = true})
    local other = carry(p, "Bandage", {power = 4})
    local rag = carry(p, "RippedSheets", {power = 2})
    local options = {radius = 0, only = {[arm] = true}, choice = function() return {change = true, prefer = chosen} end}
    local kinds, used = {}, {}
    for _ = 1, 6 do
        local step = FirstAid.plan(p, options)
        if not step then break end
        kinds[#kinds + 1] = step.kind
        if step.kind == "unbandage" then arm.cover = nil
        elseif step.kind == "burn" then used.burn = step.rag.item; arm.wash = nil
        elseif step.kind == "bandage" then used.bandage = step.item.item; arm.cover = true; break end
    end
    assert(used.bandage == chosen and used.burn ~= chosen, "the chosen dressing goes on; the burn gets a rag: " .. table.concat(kinds, ">"))
    arm.cover, arm.wash = true, nil
    local refused = FirstAid.plan(p, {radius = 0, only = {[arm] = true}, rejected = {[chosen.id] = 100}, now = 10,
        choice = function() return {change = true, prefer = chosen} end})
    arm.cover = nil
    refused = FirstAid.plan(p, {radius = 0, only = {[arm] = true}, rejected = {[chosen.id] = 100}, now = 10,
        choice = function() return {change = true, prefer = chosen} end})
    assert(refused.kind == "bandage" and refused.item.item ~= chosen, "a refused choice gives way to another dressing")
end
print("PASS the chosen dressing stays a dressing, and gives way when refused")

do
    -- A fresh dressing on a part that healed under the old one: off, and the
    -- new one still goes on.
    local hand = part("Hand_R", {cover = true})
    local p = survivor({hand})
    local fresh = carry(p, "Bandage", {power = 4})
    local options = {radius = 0, only = {[hand] = true}, choice = function() return {change = true, prefer = fresh} end}
    assert(FirstAid.plan(p, options).kind == "unbandage")
    hand.cover = nil
    local step = FirstAid.plan(p, options)
    assert(step and step.kind == "bandage" and step.item.item == fresh, "the replacement is not forgotten once the part is bare")
end
print("PASS a replacement asked for on a healed part is finished")
