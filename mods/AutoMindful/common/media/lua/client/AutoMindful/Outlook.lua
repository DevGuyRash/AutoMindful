-- Looks ahead: how long would this last, and what would go wrong first? Reads
-- the same known stock the Supplies tab shows. Never searches or walks.
local Danger = require "AutoMindful/Danger"
local FirstAid = require "AutoMindful/FirstAid"
local Needs = require "AutoMindful/SurvivalNeeds"
local Nearby = require "AutoMindful/Nearby"
local Options = require "AutoMindful/Options"
local Supplies = require "AutoMindful/Supplies"

local Outlook = {}
local endlessLiters = 9999
local sinkingAt = 0.7 -- the last moodle before health starts to fall
local rates = {}

-- Per game hour, until this survivor has been watched long enough. The game's
-- rates depend on traits, sandbox, sleep and work; watching covers all of them.
local defaults = {food=0.04, water=0.05}
local minimumHours, smoothing = 1, 0.3

local function worldHours()
    local clock = getGameTime and getGameTime()
    local hours = clock and clock.getWorldAgeHours and clock:getWorldAgeHours()
    return type(hours) == "number" and hours or nil
end

function Outlook.realHours(gameHours)
    local clock = getGameTime and getGameTime()
    local minutes = clock and clock.getMinutesPerDay and clock:getMinutesPerDay()
    return gameHours * ((type(minutes) == "number" and minutes > 0 and minutes) or 60) / 24 / 60
end

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

local function stock(player, range)
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
    if range == "walk" and player:getSquare() then
        local area = Nearby.scan(player, player:getSquare(), Options.searchRadius())
        if area then
            collect(area.food, "food", "hungerRelief")
            collect(area.water, "water", "thirstRelief")
            fixtures(area.waterSources)
            result.unknown = #area.unknownTargets
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
    local held = stock(player, range)
    local food, water = hoursLeft(player, "food", held.food), hoursLeft(player, "water", held.water)
    local result = {foodHours=food, waterHours=not held.endless and water or nil, endlessWater=held.endless,
        carriedFoodHours=hoursLeft(player, "food", held.carriedFood), carriedWaterHours=hoursLeft(player, "water", held.carriedWater),
        unknown=held.unknown, issues={}}
    local function issue(id, severity, text) result.issues[#result.issues + 1] = {id=id, severity=severity, text=text} end
    local danger, reason = Danger.read(player)
    if danger ~= "clear" then issue("danger", 3, "Not safe here: " .. reason .. ".") end
    if Danger.bleeding(player) then
        issue("bleeding", 3, FirstAid.bandagesWithin(player, range ~= "carried") and "Bleeding. It will be bandaged."
            or "Bleeding, and there is no bandage within reach.")
    end
    if held.food <= 0 then issue("food", 3, "No food it could use.")
    elseif food < 12 then issue("food", 2, "Food runs out soon.") end
    if not held.endless then
        if held.water <= 0 then issue("water", 3, "No drink it could use.")
        elseif water < 12 then issue("water", 2, "Drink runs out soon.") end
    end
    if state and state.boxedIn then issue("boxed", 3, "Every walk from this spot fails. Move the survivor to open floor.") end
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
