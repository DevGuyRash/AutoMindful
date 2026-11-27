-- What goes on a fire, and in what order: the least worth first (twigs and
-- branches, paper rubbish, charcoal and firewood, rags, a sheet, planks and
-- logs last), and never what a player would want kept. Durations stand in for
-- ISCampingMenu.getFuelDurationForItem; the game's own isValidFuel still decides.
package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
function isClient() return false end
local minutes = {Twigs = 15, Splinters = 10, TreeBranch2 = 60, LargeBranch = 90, Newspaper = 15, PaperBag = 5,
    Charcoal = 60, Firewood = 120, RippedSheetsDirty = 5, RippedSheets = 5, Sheet = 15, Plank = 120, Log = 360,
    Book = 15, Note = 5, Map = 15, Money = 5, Tshirt_DefaultTEXTURE = 15, Paperbag_Spiffos = 5, Chopsticks = 5,
    Tissue = 2, ToiletPaper = 12, Newspaper_Recent = 15, SkillBook = 15, Wallpaper_BeigeStripe = 15}
ItemTag = {START_FIRE = "startfire", PETROL = "petrol"}
ISCampingMenu = {isValidFuel = function() return true end, isValidTinder = function() return true end,
    isPetrol = function(item) return item.petrol == true end,
    getFuelDurationForItem = function(item) return minutes[item:getType()] or 0 end}
function getCampingFuelMax() return 480 end

local Fire = require "AutoMindful/Fire"

local function item(kind, fields)
    local i = fields or {}
    function i:getType() return kind end
    function i:isFavorite() return self.favorite == true end
    function i:isEquipped() return self.worn == true end
    function i:hasTag(tag) return self.tags ~= nil and self.tags[tag] == true end
    function i:getCurrentUses() return self.uses or 10 end
    function i:getID() self.id = self.id or tostring(self); return self.id end
    return i
end
local function fire(lit, fuel)
    return {isLit = function() return lit end, getFuelAmount = function() return fuel end}
end
local function kinds(plan)
    local out = {}
    for _, entry in ipairs(plan.fuel) do out[#out + 1] = entry.item:getType() end
    return table.concat(out, ",")
end
local function entries(list)
    local out = {}
    for _, kind in ipairs(list) do out[#out + 1] = {item = item(kind)} end
    return out
end

do
    -- A lit fire wanting an hour and a half (with the half-hour margin): the
    -- branches and twigs go first, longest-burning first within them.
    local plan = Fire.plan(fire(true, 0), 60, {fuel = entries({"Log", "Plank", "RippedSheets", "Newspaper", "Twigs", "TreeBranch2"})})
    assert(kinds(plan) == "TreeBranch2,Twigs,Newspaper", kinds(plan))
    -- Not enough rubbish: then charcoal and firewood, then rags, then the sheet; planks and logs last.
    plan = Fire.plan(fire(true, 0), 240, {fuel = entries({"Log", "Plank", "Sheet", "RippedSheets", "RippedSheetsDirty", "Firewood", "Charcoal", "Twigs"})})
    assert(kinds(plan) == "Twigs,Firewood,Charcoal,RippedSheetsDirty,RippedSheets,Sheet,Plank", kinds(plan))
end
print("PASS the least worth goes on the fire first, planks and logs last")

do
    -- Never burned, whatever the game would allow.
    for _, kind in ipairs({"Book", "SkillBook", "Note", "Map", "Money", "Tshirt_DefaultTEXTURE", "Paperbag_Spiffos", "Chopsticks",
            "Tissue", "ToiletPaper", "Newspaper_Recent", "Wallpaper_BeigeStripe"}) do
        local thing = item(kind)
        assert(not Fire.isFuel(thing) and not Fire.isTinder(thing) and not Fire.candidate(thing), kind .. " is never burned")
    end
    -- Nor a favourite or anything worn, even of a kind that may be.
    assert(not Fire.isFuel(item("Twigs", {favorite = true})) and not Fire.isFuel(item("RippedSheets", {worn = true})))
    assert(Fire.isFuel(item("Twigs")) and Fire.isTinder(item("Newspaper")))
    -- And nothing goes in when only the unburnable is around.
    assert(Fire.plan(fire(true, 0), 30, {fuel = {}}) == nil)
end
print("PASS books, notes, maps, money, keepsakes, clothes and favourites are never burned")

do
    -- Lighting an unlit fire: twigs before paper, paper before a rag.
    local plan = Fire.plan(fire(false, 0), 30, {fuel = entries({"Log"}), tinder = entries({"RippedSheets", "Newspaper", "Twigs"}),
        starters = {{item = item("Matches")}}})
    assert(plan.tinder.item:getType() == "Twigs", plan.tinder.item:getType())
    plan = Fire.plan(fire(false, 0), 30, {fuel = entries({"Log"}), tinder = entries({"RippedSheets", "Newspaper"}), starters = {{item = item("Matches")}}})
    assert(plan.tinder.item:getType() == "Newspaper")
end
print("PASS a fire is lit with the least worth that will light it")

do
    -- Starters: anything the game tags as starting a fire, the cheapest first.
    local magnesium = item("MagnesiumFirestarter", {tags = {startfire = true}})
    assert(Fire.isStarter(magnesium) and Fire.isStarter(item("Matchbox", {tags = {startfire = true}})))
    assert(not Fire.isStarter(item("Lighter", {uses = 0})), "an empty lighter lights nothing")
    assert(not Fire.isStarter(item("Lighter", {favorite = true})), "nor a favourite one")
    local plan = Fire.plan(fire(false, 0), 30, {fuel = entries({"Log"}), tinder = entries({"Newspaper"}),
        starters = {{item = item("Lighter")}, {item = magnesium}, {item = item("Matches")}}})
    assert(plan.method == "tinder" and plan.starter.item:getType() == "Matches", plan.starter.item:getType())
    -- No tinder: petrol and a starter.
    local petrol = item("PetrolCan", {petrol = true, tags = {petrol = true}})
    assert(Fire.isPetrol(petrol) and Fire.candidate(petrol))
    plan = Fire.plan(fire(false, 0), 30, {fuel = entries({"Log"}), starters = {{item = item("Lighter")}}, petrol = {{item = petrol}}})
    assert(plan.method == "petrol" and plan.petrol.item == petrol and not plan.tinder)
    -- No starter at all: a notched plank worked with a stick, the stick not burned.
    local stick = item("TreeBranch2")
    plan = Fire.plan(fire(false, 0), 30, {fuel = {{item = stick}, {item = item("Log")}}, kindling = entries({"PercedWood"}), sticks = {{item = stick}}})
    assert(plan.method == "kindle" and plan.stick.item == stick)
    for _, entry in ipairs(plan.fuel) do assert(entry.item ~= stick, "the stick works the plank, it is not burned") end
    -- Nothing to light it with: no plan.
    assert(Fire.plan(fire(false, 0), 30, {fuel = entries({"Log"}), tinder = entries({"Newspaper"})}) == nil)
    -- Written down and fetched: everything the method takes.
    local record, wanted = Fire.record(plan), Fire.wanted(plan)
    assert(record.method == "kindle" and record.plank and record.stick and #wanted == #plan.fuel + 2)
end
print("PASS any starter the game allows, the cheapest first; petrol, then a notched plank, when that is all there is")

do
    -- The game's own actions for each method; a plank's light is ours only if it caught.
    local queued = {}
    ISTimedActionQueue = {add = function(action) queued[#queued + 1] = action end}
    local function action(name) return {new = function(_, ...) return {Type = name, args = {...}, isValid = function() return true end,
        perform = function() end} end} end
    ISBBQLightFromPetrol, ISBBQLightFromKindle, ISBBQLightFromLiterature, ISBBQAddFuel = action("petrol"), action("kindle"), action("tinder"), action("fuel")
    local inventory = {}
    local player = {getInventory = function() return {getItemById = function(_, id) return inventory[id] end} end}
    local function hold(kind, fields) local thing = item(kind, fields); inventory[thing:getID()] = thing; return thing end
    local lit, burning = 0, false
    local place = {isLit = function() return burning end, getFuelAmount = function() return 0 end,
        getContainer = function() return {contains = function() return true end} end}
    local starter, petrol = hold("Lighter"), hold("PetrolCan", {petrol = true})
    Fire.start(player, place, {method = "petrol", fuel = {}, starter = starter:getID(), petrol = petrol:getID()}, nil, function() lit = lit + 1 end)
    assert(queued[1].Type == "petrol" and queued[1].args[2] == place and queued[1].args[3] == starter and queued[1].args[4] == petrol)
    queued[1]:perform(); assert(lit == 1)
    queued = {}
    local plank, stick = hold("PercedWood"), hold("TreeBranch2")
    Fire.start(player, place, {method = "kindle", fuel = {}, plank = plank:getID(), stick = stick:getID()}, nil, function() lit = lit + 1 end)
    assert(queued[1].Type == "kindle" and queued[1].args[2] == plank and queued[1].args[3] == stick and queued[1].args[4] == place)
    assert(#queued == 3, "a plank gets three goes")
    queued[1]:perform(); assert(lit == 1, "rubbed but did not catch: not ours")
    burning = true; queued[1]:perform(); assert(lit == 2)
end
print("PASS each way of lighting uses the game's own action")
