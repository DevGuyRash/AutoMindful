-- Looks ahead: how long would this last, and what would go wrong first? Reads
-- the same known stock the Supplies tab shows. Never searches or walks.
local Clock = require "AutoMindful/Clock"
local Danger = require "AutoMindful/Danger"
local FirstAid = require "AutoMindful/FirstAid"
local Needs = require "AutoMindful/SurvivalNeeds"
local Nearby = require "AutoMindful/Nearby"
local Options = require "AutoMindful/Options"
local Supplies = require "AutoMindful/Supplies"
local Fluids = require "AutoMindful/Fluids"

local Outlook = {}
local endlessLiters = 9999
local sinkingAt = 0.7 -- the last moodle before health starts to fall
local rates = {}

-- Per game hour, until this survivor has been watched long enough. The game's
-- rates depend on traits, sandbox, sleep and work; watching covers all of them.
local defaults = {food=0.04, water=0.05}
local minimumHours, smoothing = 1, 0.3

local worldHours = Clock.worldHours

function Outlook.realHours(gameHours) return Clock.realSeconds(gameHours * 60) / 3600 end

-- Every rise counts; a drop is a meal and starts the next span.
function Outlook.sample(player, now)
    local hours = worldHours()
    if not hours then return end
    local mine = rates[player]
    if not mine then mine = {}; rates[player] = mine end
    for kind, name in pairs({food="HUNGER", water="THIRST"}) do
        local value = player:getStats():get(CharacterStat[name])
        local span = mine[kind]
        if not span then span = {hours=0, rise=0}; mine[kind] = span end
        if span.at and hours > span.at and hours - span.at < 2 and value >= span.value and value < 0.95 then
            span.hours, span.rise = span.hours + hours - span.at, span.rise + value - span.value
            if span.hours >= minimumHours then
                local measured = span.rise / span.hours
                span.rate = span.rate and span.rate + (measured - span.rate) * smoothing or measured
                span.hours, span.rise = 0, 0
            end
        end
        span.at, span.value = hours, value
    end
end

function Outlook.rate(player, kind)
    local span = rates[player] and rates[player][kind]
    return math.max(span and span.rate or defaults[kind], 0.002)
end

local function add(total, entry, field)
    local d = entry.description
    if not d or entry.transfer then return total end
    return total + math.max(0, d[field] or 0)
end

local function stock(player, range, boxedIn, skip)
    local near = range ~= "carried"
    local scan = Supplies.scan(player, near, near)
    local result = {food=0, water=0, carriedWater=0, carriedFood=0, endless=false}
    local counted = {}
    local function collect(list, kind, field)
        for _, entry in ipairs(list) do
            local id = entry.item or entry.worldSource and entry.worldSource.object
            if id and not counted[kind .. tostring(id)] then
                counted[kind .. tostring(id)] = true
                result[kind] = add(result[kind], entry, field)
                if entry.owned then
                    local key = kind == "food" and "carriedFood" or "carriedWater"
                    result[key] = add(result[key], entry, field)
                end
            end
        end
    end
    collect(scan.food, "food", "hungerRelief")
    collect(scan.water, "water", "thirstRelief")
    local function fixtures(list)
        for _, source in ipairs(list) do
            local object = source.object
            local id = object and "fixture" .. tostring(object)
            if object and not counted[id] then
                counted[id] = true
                local liters = object:getFluidAmount()
                if liters >= endlessLiters then result.endless = true else result.water = result.water + liters / 2 end
            end
        end
    end
    fixtures(scan.waterSources)
    if range == "walk" and player:getSquare() and not boxedIn then
        local area = Nearby.scan(player, player:getSquare(), Options.searchRadius())
        if area then
            collect(area.food, "food", "hungerRelief")
            collect(area.water, "water", "thirstRelief")
            fixtures(area.waterSources)
            result.unknown = #area.unknownTargets
        end
    end
    -- Food the kitchen can make safe: raw meat and the like, with a stove or
    -- grill to cook it on. Read lazily; the outlook works without a kitchen.
    -- Not while boxed in, in danger or in a car: the stove is out of reach then.
    if near and not boxedIn and Options.cookMeals and Options.cookMeals() then
        local ok, Kitchen = pcall(require, "AutoMindful/Kitchen")
        local found = ok and type(Kitchen) == "table" and Kitchen.scan(player, skip, getTimestampMs()) or nil
        if found and found.heats > 0 then
            result.cookFood = 0
            -- Raw food to cook, and frozen food once it has thawed.
            local both = {}
            for _, entry in ipairs(found.food) do both[#both + 1] = entry end
            for _, entry in ipairs(found.frozen or {}) do both[#both + 1] = entry end
            for _, entry in ipairs(both) do
                local id = entry.item
                if not Fluids.safeFood(id) and not counted["food" .. tostring(id)] then
                    counted["food" .. tostring(id)] = true
                    result.cookFood = result.cookFood + math.max(0, -id:getHungerChange())
                end
            end
            result.food = result.food + result.cookFood
        end
    end
    return result
end

local function hoursLeft(player, kind, relief)
    local current = player:getStats():get(kind == "water" and CharacterStat.THIRST or CharacterStat.HUNGER)
    return math.max(0, sinkingAt - current + relief) / Outlook.rate(player, kind)
end

local function moodle(player, name)
    return MoodleType[name] and player:getMoodles():getMoodleLevel(MoodleType[name]) or 0
end

-- severity 3: would likely kill an unattended survivor. 2: would cost a lot.
-- 1: worth knowing. Only what is true right now is listed.
function Outlook.read(player, range, state)
    local held = stock(player, range, state and (state.boxedIn or state.guard) and true, state and state.kitchenSkip)
    local food, water = hoursLeft(player, "food", held.food), hoursLeft(player, "water", held.water)
    local result = {foodHours=food, waterHours=not held.endless and water or nil, endlessWater=held.endless,
        carriedFoodHours=hoursLeft(player, "food", held.carriedFood), carriedWaterHours=hoursLeft(player, "water", held.carriedWater),
        unknown=held.unknown, issues={},
        cookHours=held.cookFood and held.cookFood > 0 and held.cookFood / Outlook.rate(player, "food") or nil}
    local function issue(id, severity, text) result.issues[#result.issues + 1] = {id=id, severity=severity, text=text} end
    local danger, reason = Danger.read(player)
    if danger ~= "clear" then issue("danger", 3, "Not safe here: " .. reason .. ".") end
    if Danger.bleeding(player) then
        issue("bleeding", 3, FirstAid.bandagesWithin(player, range == "walk" and Options.searchRadius() or range ~= "carried" and 2 or 0) and "Bleeding. It will be bandaged."
            or "Bleeding, and there is no bandage within reach.")
    end
    -- A dish on the stove is food on the way, not none at all.
    -- Only while the stove is seen to be on: a ledger left behind is no dinner.
    local kitchen = player.getModData and player:getModData().AutoMindfulKitchen
    local ok, Kitchen = pcall(require, "AutoMindful/Kitchen")
    local status = kitchen and kitchen.lit and ok and type(Kitchen) == "table" and Kitchen.status(player)
    -- A dish in a stove that is on and powered.
    local cooking = status and status.on and status.progress ~= nil
    if held.food <= 0 and cooking then issue("food", 2, "Food is cooking on the stove.")
    elseif held.food <= 0 then issue("food", 3, "No food it could use.")
    elseif food < 24 then issue("food", 2, "Food runs out soon.") end
    if not held.endless then
        if held.water <= 0 then issue("water", 3, "No drink it could use.")
        elseif water < 24 then issue("water", 2, "Drink runs out soon.") end
    end
    if state and state.boxedIn then issue("boxed", 3, "Cannot walk to any supply from here: closed doors, or a stuck spot.") end
    local square = player:getSquare()
    if square and not (square.isInARoom and square:isInARoom()) and not player:getVehicle() then
        issue("outside", 2, "Outdoors: weather and zombies can reach the survivor.")
    end
    if moodle(player, "HYPOTHERMIA") >= 2 then issue("cold", 3, "Getting dangerously cold. Warmer clothes or a fire are needed.")
    elseif moodle(player, "HYPOTHERMIA") == 1 then issue("cold", 1, "Feeling cold.") end
    if moodle(player, "HYPERTHERMIA") >= 2 then issue("heat", 3, "Overheating. Take off warm clothes or find shade.") end
    if moodle(player, "WET") >= 2 then issue("wet", 1, "Wet clothes can bring a cold.") end
    if moodle(player, "SICK") >= 2 then issue("sick", 2, "Sick. Food, drink and rest help.") end
    if moodle(player, "NOXIOUS_SMELL") >= 1 then issue("smell", 2, "Bad air here makes the survivor sick and blocks sleep.") end
    if moodle(player, "HEAVY_LOAD") >= 3 then issue("load", 3, "Carrying so much that it hurts. Put something down.") end
    if range == "carried" and held.carriedFood <= 0 then issue("range", 1, "Set to use only what is carried.") end
    result.food, result.carriedFood = Outlook.duration(food), Outlook.duration(result.carriedFoodHours)
    result.cook = result.cookHours and Outlook.duration(result.cookHours) or nil
    result.water, result.carriedWater = Outlook.duration(water), Outlook.duration(result.carriedWaterHours)
    table.sort(result.issues, function(a, b) return a.severity > b.severity end)
    return result
end

-- Real time is what matters to someone deciding whether to walk away.
function Outlook.duration(gameHours)
    local real = Outlook.realHours(gameHours)
    if real >= 48 then return string.format("%d days", math.floor(real / 24)) end
    if real >= 1 then return string.format("%d h", math.floor(real)) end
    return string.format("%d min", math.floor(real * 60))
end

function Outlook.forget(player) rates[player] = nil end

return Outlook
