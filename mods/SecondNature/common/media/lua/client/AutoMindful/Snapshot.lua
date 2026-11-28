-- Read-only descriptions of live game objects for the log. Every getter is
-- optional: a missing method or a refused call becomes an absent field, never
-- an error in the decision being described.
local Snap = {}

local function get(object, method, ...)
    if object == nil then return nil end
    local fn = object[method]
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, object, ...)
    if ok then return result end
end

local function number(value, digits)
    if type(value) ~= "number" or value ~= value then return nil end
    return (string.format("%." .. (digits or 2) .. "f", value):gsub("(%..-)0+$", "%1"):gsub("%.$", ""))
end

local function part(out, name, value)
    if value ~= nil and value ~= "" then out[#out + 1] = name .. ":" .. tostring(value) end
end

local function flag(out, name, value) if value == true then out[#out + 1] = name end end

local function xyz(object)
    local x, y, z = get(object, "getX"), get(object, "getY"), get(object, "getZ")
    if not x or not y then return nil end
    return math.floor(x) .. ":" .. math.floor(y) .. ":" .. math.floor(z or 0)
end

local function isType(object, name)
    if not instanceof or object == nil then return false end
    local ok, result = pcall(instanceof, object, name)
    return ok and result == true
end

function Snap.square(square)
    if not square then return "none" end
    local out = {xyz(square) or "?"}
    local room = get(square, "getRoom")
    part(out, "room", room and get(room, "getName") or get(square, "isOutside") and "outside" or nil)
    if get(square, "canStand") == false then out[#out + 1] = "cannot-stand" end
    if get(square, "isFree", false) == false then out[#out + 1] = "occupied" end
    return table.concat(out, ",")
end

local function fluidOf(object)
    local world = get(object, "getWorldItem")
    return (world and get(world, "getFluidContainer")) or get(object, "getFluidContainer")
end

local function fluidText(fluid)
    if not fluid then return nil end
    if get(fluid, "isEmpty") == true then return "empty/" .. tostring(number(get(fluid, "getCapacity")) or "?") .. "L" end
    local primary = get(fluid, "getPrimaryFluid")
    local name = primary and (get(primary, "getFluidTypeString") or get(primary, "getTranslatedName")) or "unknown"
    return tostring(name) .. " " .. tostring(number(get(fluid, "getAmount"), 3) or "?") .. "/"
        .. tostring(number(get(fluid, "getCapacity")) or "?") .. "L" .. (get(fluid, "isTainted") == true and " TAINTED" or "")
        .. (get(fluid, "canPlayerEmpty") == false and " closed" or "")
end

function Snap.item(item)
    if not item then return "none" end
    local out = {tostring(get(item, "getFullType") or "?") .. "#" .. tostring(get(item, "getID") or "?")}
    local holder = get(item, "getContainer")
    part(out, "in", holder and get(holder, "getType"))
    part(out, "fluid", fluidText(fluidOf(item)))
    if isType(item, "Food") then
        part(out, "hunger", number(get(item, "getHungerChange"), 3))
        part(out, "thirst", number(get(item, "getThirstChange"), 3))
        flag(out, "rotten", get(item, "isRotten"))
        flag(out, "frozen", get(item, "isFrozen"))
        flag(out, "burnt", get(item, "isBurnt"))
    end
    flag(out, "sealed", get(item, "isSealed"))
    flag(out, "favorite", get(item, "isFavorite"))
    return "{" .. table.concat(out, " ") .. "}"
end

-- Enough of the contents to answer "why did it not use that?" without
-- printing a warehouse: types with counts, and every fluid's amount.
function Snap.container(container, limit)
    if not container then return "none" end
    local out = {tostring(get(container, "getType") or "?")}
    part(out, "at", xyz(get(container, "getSourceGrid")))
    local parent = get(container, "getParent")
    part(out, "sprite", parent and get(parent, "getSpriteName"))
    local explored = get(container, "isExplored")
    if explored == false then out[#out + 1] = "unexplored" end
    part(out, "load", number(get(container, "getContentsWeight"), 1)
        and (number(get(container, "getContentsWeight"), 1) .. "/" .. tostring(number(get(container, "getCapacity"), 0) or "?")))
    local items = get(container, "getItems")
    local size = items and get(items, "size") or 0
    part(out, "items", size)
    local counts, order, more = {}, {}, 0
    for index = 0, size - 1 do
        local item = get(items, "get", index)
        local fluid = fluidText(fluidOf(item))
        local name = tostring(get(item, "getFullType") or "?") .. (fluid and "(" .. fluid .. ")" or "")
        if counts[name] then counts[name] = counts[name] + 1
        elseif #order < (limit or 12) then counts[name] = 1; order[#order + 1] = name
        else more = more + 1 end
    end
    for index, name in ipairs(order) do order[index] = counts[name] > 1 and (name .. "x" .. counts[name]) or name end
    if more > 0 then order[#order + 1] = "+" .. more .. " more" end
    if #order > 0 then out[#out + 1] = "[" .. table.concat(order, ", ") .. "]" end
    return "{" .. table.concat(out, " ") .. "}"
end

function Snap.object(object)
    if not object then return "none" end
    local out = {tostring(get(object, "getObjectName") or "object")}
    part(out, "at", xyz(get(object, "getSquare")))
    part(out, "sprite", get(object, "getSpriteName"))
    if get(object, "hasWater") == true or fluidOf(object) then
        part(out, "water", tostring(number(get(object, "getFluidAmount"), 2) or "?") .. "/"
            .. tostring(number(get(object, "getFluidCapacity"), 2) or "?") .. "L")
        flag(out, "TAINTED", get(object, "isTaintedWater"))
        flag(out, "plumbed", get(object, "getUsesExternalWaterSource"))
    end
    part(out, "containers", get(object, "getContainerCount"))
    flag(out, "open", get(object, "IsOpen"))
    flag(out, "locked", get(object, "isLocked"))
    return "{" .. table.concat(out, " ") .. "}"
end

-- A trip's destination: what it is, how sure we are of it, and its contents.
function Snap.target(target)
    if not target then return "none" end
    local out = {}
    part(out, "key", target.key)
    part(out, "tile", xyz(target.square))
    out[#out + 1] = target.unknown and "contents-unconfirmed" or target.remembered and "remembered" or "known-stock"
    if target.part then
        part(out, "vehiclePart", get(target.part, "getId"))
        part(out, "vehicle", get(get(target.part, "getVehicle"), "getScriptName"))
    end
    if target.item then part(out, "item", Snap.item(target.item)) end
    if target.container then part(out, "container", Snap.container(target.container))
    elseif target.object then part(out, "object", Snap.object(target.object)) end
    return "{" .. table.concat(out, " ") .. "}"
end

function Snap.action(action)
    if not action then return "none" end
    local out = {tostring(action.Type or "?")}
    part(out, "item", action.item and get(action.item, "getFullType"))
    part(out, "max", number(action.maxTime, 0))
    local native = action.action
    part(out, "progress", native and number(get(native, "getJobDelta")))
    flag(out, "started", get(action, "isStarted"))
    flag(out, "finished", action.autoMindfulFinished)
    flag(out, "stopped", action.autoMindfulStopped)
    flag(out, "pathFailed", action.autoMindfulPathFailed)
    flag(out, "ours", action.autoMindfulOwner ~= nil)
    if action.result ~= nil then part(out, "result", tostring(action.result)) end
    return table.concat(out, ",")
end

function Snap.queue(player)
    if not ISTimedActionQueue or not ISTimedActionQueue.getTimedActionQueue then return "?" end
    local ok, timed = pcall(ISTimedActionQueue.getTimedActionQueue, player)
    if not ok or not timed then return "?" end
    local out = {}
    for index, action in ipairs(timed.queue or {}) do
        if index > 5 then out[#out + 1] = "+" .. (#timed.queue - 5); break end
        out[#out + 1] = Snap.action(action)
    end
    local native = get(get(player, "getCharacterActions"), "size")
    return "[" .. table.concat(out, " > ") .. "]" .. (native and native > 0 and ("native:" .. native) or "")
end

local stats = {{"hunger","HUNGER","HUNGRY"}, {"thirst","THIRST","THIRST"}, {"endurance","ENDURANCE"},
    {"fatigue","FATIGUE"}, {"boredom","BOREDOM"}, {"stress","STRESS"}, {"pain","PAIN"}, {"panic","PANIC"},
    {"unhappy","UNHAPPINESS"}, {"sick","SICKNESS"}}

-- value/moodle: 0.18/1 is 18% thirst showing the first moodle.
function Snap.needs(player)
    local source, moodles, out = get(player, "getStats"), get(player, "getMoodles"), {}
    for _, row in ipairs(stats) do
        local key = CharacterStat and CharacterStat[row[2]]
        local value = key and source and get(source, "get", key)
        if type(value) == "number" then
            local moodle = row[3] and MoodleType and MoodleType[row[3]]
            local level = moodle and moodles and get(moodles, "getMoodleLevel", moodle)
            out[#out + 1] = row[1] .. ":" .. number(value) .. (level and ("/" .. level) or "")
        end
    end
    return table.concat(out, " ")
end

function Snap.posture(player)
    if get(player, "isDead") == true then return "dead" end
    if get(player, "isAsleep") == true then return "asleep" end
    if get(player, "getVehicle") then return "vehicle" end
    if get(player, "isGettingUp") == true then return "getting-up" end
    if get(player, "isSittingOnFurniture") == true then return "furniture" end
    if get(player, "isSitOnGround") == true then return "floor" end
    if get(player, "isPlayerMoving") == true then return "moving" end
    return "standing"
end

local function moodleValue(player, name)
    local data = get(player, "getModData")
    local moodles = type(data) == "table" and data.LSMoodles
    local entry = type(moodles) == "table" and moodles[name]
    return type(entry) == "table" and type(entry.Value) == "number" and entry.Value or nil
end

function Snap.player(player)
    if not player then return "none" end
    local out = {}
    part(out, "pos", xyz(player))
    part(out, "tile", Snap.square(get(player, "getSquare")))
    part(out, "pose", Snap.posture(player))
    part(out, "state", get(player, "getCurrentStateName"))
    part(out, "hp", number(get(get(player, "getBodyDamage"), "getOverallBodyHealth"), 1))
    local bleeding = get(get(player, "getBodyDamage"), "getNumPartsBleeding")
    if bleeding and bleeding > 0 then part(out, "bleeding", bleeding) end
    out[#out + 1] = Snap.needs(player)
    part(out, "mindful", number(moodleValue(player, "MindfulState")))
    part(out, "zen", number(moodleValue(player, "Zen")))
    part(out, "embarrassed", number(moodleValue(player, "Embarrassed")))
    local primary, secondary = get(player, "getPrimaryHandItem"), get(player, "getSecondaryHandItem")
    part(out, "hands", (primary or secondary) and (tostring(primary and get(primary, "getType") or "-")
        .. "+" .. tostring(secondary and get(secondary, "getType") or "-")))
    part(out, "carry", number(get(player, "getInventoryWeight"), 1)
        and (number(get(player, "getInventoryWeight"), 1) .. "/" .. tostring(number(get(player, "getMaxWeight"), 0) or "?")))
    local source = get(player, "getStats")
    local seen, chasing = get(source, "getNumVisibleZombies") or 0, get(source, "getNumChasingZombies") or 0
    if seen > 0 or chasing > 0 then part(out, "zombies", seen .. " seen/" .. chasing .. " chasing") end
    flag(out, "too-dark", get(player, "tooDarkToRead"))
    flag(out, "aiming", get(player, "isAiming"))
    flag(out, "input-move", get(player, "pressedMovement", false))
    flag(out, "input-cancel", get(player, "pressedCancelAction"))
    if getGameSpeed then part(out, "speed", getGameSpeed()) end
    part(out, "queue", Snap.queue(player))
    return table.concat(out, " ")
end

return Snap
