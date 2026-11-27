-- First aid as the game's own doctor menu gives it, planned a wound at a time:
-- the most dangerous wound first, everything it will take fetched before the
-- old dressing comes off, then each treatment in the order the game allows.
-- Judgement only: Recovery queues the steps and checks what each one changed.
--
-- The game's rules this follows (ISHealthPanel's handlers): glass, bullets,
-- disinfecting, stitches, burns and herbs all need the dressing off; glass
-- must be out before stitches go in; a stitched limb cannot be splinted, so
-- the splint goes on first; stitches come out only once the game calls them
-- good, or the wound opens again.
require "TimedActions/ISApplyBandage"
require "TimedActions/ISRemoveGlass"
require "TimedActions/ISRemoveBullet"
require "TimedActions/ISDisinfect"
require "TimedActions/ISStitch"
require "TimedActions/ISSplint"
require "TimedActions/ISCleanBurn"
require "TimedActions/ISComfreyCataplasm"
require "TimedActions/ISGarlicCataplasm"
require "TimedActions/ISPlantainCataplasm"
local Fetch = require "AutoMindful/Fetch"
local Grid = require "AutoMindful/Grid"
local Storage = require "AutoMindful/Storage"

-- goodStitch: the stitch time at which the health panel calls stitches good
-- and taking them out no longer opens the wound. scanMs: how long a look
-- around stays good while the survivor stands on the same square.
local FirstAid = {policy = {goodStitch = 40, scanMs = 5000, calmPanic = 2, depth = 3}}

local function read(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then return value end
    return fallback
end

local function kind(item) return read(function() return item:getType() end, "") end
local function tagged(item, name)
    return read(function() local tag = ItemTag[name]; return tag ~= nil and item:hasTag(tag) end, false) == true
end
local function dirty(item) return string.find(kind(item), "Dirty", 1, true) ~= nil end
local function dressing(item)
    return item.getBandagePower ~= nil and item:getBandagePower() > 0 and not (item.isInfected and item:isInfected())
end

-- HDisinfect's own test: a bottle at least 40% alcohol with more than a sip
-- left, or a drainable as strong as disinfectant (wipes, doused cotton).
-- A bottle lying on the floor keeps its fluid on the world object.
local function fluidOf(item)
    local world = item:getWorldItem()
    return world and world:getFluidContainer() or item:getFluidContainer()
end

local function disinfectant(item)
    return read(function()
        local fluid = fluidOf(item)
        if fluid then
            local amount = fluid:getAmount()
            return amount > 0.15 and fluid:getProperties():getAlcohol() / amount + 0.001 >= 0.4
        end
        return item:IsDrainable() and item:getAlcoholPower() == 4.0
    end, false) == true
end

-- Sterile first, then the strongest; anything dirty last.
local function quality(item)
    return (dirty(item) and 10 or item:isAlcoholic() and 0 or 1) - item:getBandagePower() / 10
end

local planks = {Plank = true, TreeBranch2 = true, WoodenStick2 = true, TreeBranch = true, WoodenStick = true}

-- What each treatment takes, and which of several is better (lower first).
-- consumed: used up by the treatment, so one item cannot serve twice.
local roles = {
    dressing = {match = dressing, consumed = true, grade = function(item) return quality(item) end},
    clean = {match = function(item) return dressing(item) and not dirty(item) end, consumed = true,
        grade = function(item) return quality(item) end},
    sterile = {match = function(item) return dressing(item) and not dirty(item) and item:isAlcoholic() end, consumed = true},
    tweezers = {match = function(item) return tagged(item, "REMOVE_GLASS") or kind(item) == "Tweezers" or kind(item) == "SutureNeedleHolder" end,
        grade = function(item) return kind(item) == "Tweezers" and 1 or kind(item) == "SutureNeedleHolder" and 2 or 3 end},
    extractor = {match = function(item) return tagged(item, "REMOVE_BULLET") or kind(item) == "Tweezers" or kind(item) == "SutureNeedleHolder" end,
        grade = function(item) return kind(item) == "Tweezers" and 1 or kind(item) == "SutureNeedleHolder" and 2 or 3 end},
    -- Disinfectant and rubbing alcohol before a bottle of something to drink.
    alcohol = {match = disinfectant, grade = function(item)
        return read(function()
            local fluid = fluidOf(item)
            if not fluid then return 1 end
            return fluid:getProperties():getAlcohol() / fluid:getAmount() >= 0.9 and 1 or 2
        end, 2)
    end},
    suture = {match = function(item) return kind(item) == "SutureNeedle" end, consumed = true},
    needle = {match = function(item) return kind(item) == "Needle" or tagged(item, "SEWING_NEEDLE") end},
    thread = {match = function(item)
        return (kind(item) == "Thread" or tagged(item, "THREAD")) and read(function() return item:getCurrentUsesFloat() > 0 end, false)
    end},
    holder = {match = function(item) return kind(item) == "SutureNeedleHolder" end},
    splint = {match = function(item) return kind(item) == "Splint" end, consumed = true},
    plank = {match = function(item) return planks[kind(item)] == true end, consumed = true},
    sheet = {match = function(item) return kind(item) == "RippedSheets" end, consumed = true},
    -- Cleaning a burn uses the cloth up: the plainest that the game allows.
    burn = {match = function(item) return item.getBandagePower ~= nil and item:getBandagePower() >= 2 end, consumed = true,
        grade = function(item) return item:getBandagePower() + (item:isAlcoholic() and 10 or 0) end},
    comfrey = {match = function(item) return kind(item) == "ComfreyCataplasm" end, consumed = true},
    garlic = {match = function(item) return kind(item) == "WildGarlicCataplasm" end, consumed = true},
    plantain = {match = function(item) return kind(item) == "PlantainCataplasm" end, consumed = true},
}
FirstAid.roles = roles

local function anyRole(item)
    for _, role in pairs(roles) do if role.match(item) then return true end end
    return false
end

-- --------------------------------------------------------------- the wounds

-- A dressing hides the wound: the game's setBandaged clears the bleeding,
-- cut, scratch, bite, deep-wound and stitched flags, and puts each back from
-- its timer when the dressing comes off. Under a dressing, the timers tell.
local function has(part, flag, timer)
    if part:bandaged() then return read(function() return part[timer](part) > 0 end, false) == true end
    return part[flag](part) == true
end
local function isDeep(part) return has(part, "deepWounded", "getDeepWoundTime") end
local function isStitched(part) return has(part, "stitched", "getStitchTime") end
local function isCut(part) return has(part, "isCut", "getCutTime") end
local function isScratched(part) return has(part, "scratched", "getScratchTime") end
local function isBitten(part) return has(part, "bitten", "getBiteTime") end

local function open(part)
    return isScratched(part) or isCut(part) or isDeep(part) or isBitten(part) or part:getBurnTime() > 0
end
FirstAid.open = open

-- What the survivor would see on the health panel: only a good doctor knows
-- early that a wound has turned. Under a dressing nobody sees it; once seen,
-- an infection is remembered under the dressing that went on after it, until
-- it has gone.
local seenInfected = setmetatable({}, {__mode = "k"})
local function infectionKnown(player, part)
    if not read(function() return part:isInfectedWound() end, false) then seenInfected[part] = nil; return false end
    if seenInfected[part] then return true end
    if part:bandaged() then return false end
    local level = player:getPerkLevel(Perks.Doctor)
    local known = level > 8 or part:getWoundInfectionLevel() * 10 >= 2.5 - level
    if known then seenInfected[part] = true end
    return known
end

local function typeName(part) return tostring(read(function() return part:getType() end, "")) end
-- Where bleeding kills fastest.
local weights = {Neck = 30, Head = 20, Torso_Upper = 15, Torso_Lower = 12, Groin = 10, UpperLeg_L = 10, UpperLeg_R = 10}
-- HSplint's own exclusions.
local unsplintable = {Head = true, Torso_Upper = true, Torso_Lower = true}

local function bleedingOpen(part) return part:bleeding() and not part:bandaged() end
local function goodStitches(part) return isStitched(part) and part:getStitchTime() > FirstAid.policy.goodStitch end
local function unstitched(part) return isDeep(part) and not isStitched(part) end
local function fractured(part)
    return part:getFractureTime() > 0 and part:getSplintFactor() <= 0 and not unsplintable[typeName(part)]
end
local function poulticed(part)
    return read(function() return part:getPlantainFactor() > 0 or part:getComfreyFactor() > 0 or part:getGarlicFactor() > 0 end, true)
end
local function dressable(part)
    return open(part) or (isStitched(part) and part:getStitchTime() <= FirstAid.policy.goodStitch)
end
-- A dirty dressing on a wound that still bleeds or is not stitched is dirty
-- again in moments: changing it would only use up every clean one.
local function worthChanging(part)
    return part:bandaged() and part:isBandageDirty() and dressable(part) and not unstitched(part) and part:getBleedingTime() <= 0
end

-- How dangerous a wound is now. Bleeding first, and where it kills fastest.
function FirstAid.danger(player, part)
    local weight = weights[typeName(part)] or 0
    if bleedingOpen(part) then return 100 + weight + (isDeep(part) and 5 or 0) end
    if part:haveGlass() or part:haveBullet() then return 60 + weight end
    if infectionKnown(player, part) then return 50 end
    if unstitched(part) then return 45 + weight / 2 end
    if fractured(part) then return 40 end
    if part:isNeedBurnWash() and part:getBurnTime() > 0 then return 35 end
    if dressable(part) and not part:bandaged() then return 30 + (isBitten(part) and 3 or 0) + (isCut(part) and 1 or 0) end
    if worthChanging(part) then return 20 end
    if goodStitches(part) then return 5 end
    if part:getSplintFactor() > 0 and part:getFractureTime() <= 0 then return 4 end
    return 0
end

-- ------------------------------------------------------------- the supplies

-- Carried: in the main inventory, where every action needs it. Anything else
-- is {entry, square, reach}: reach true when no walk is needed.
local looks = {}

local function collect(player, radius)
    local here = player:getSquare()
    local now = getTimestampMs()
    local found, seen, inventory = {}, {}, player:getInventory()
    local function add(list, item, container, world, holder, body, square)
        if seen[item] or Grid.favorite(item) or not anyRole(item) then return end
        seen[item] = true
        local carried = container == inventory
        local entry = Fetch.entry(item, container, world, carried, holder, body)
        list[#list + 1] = {item = item, entry = entry, carried = carried, square = square,
            reach = carried or square == nil or Grid.reachable(here, square)}
    end
    local function inside(list, container, square, depth, holder, body)
        local items = container:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            if instanceof(item, "InventoryContainer") then
                if depth < FirstAid.policy.depth then inside(list, item:getInventory(), square, depth + 1, holder, body) end
            else add(list, item, container, nil, holder, body, square) end
        end
    end
    -- What is carried changes with every action: always read afresh. Bags
    -- carried need no walk, only a move into the hands.
    inside(found, inventory, nil, 0)
    if not (radius and radius > 0 and here) then return found end
    local carried = seen
    seen = {}
    local cached = looks[player]
    if not (cached and cached.square == here and cached.radius == radius and now >= cached.at and now - cached.at < FirstAid.policy.scanMs) then
        local around = {}
        -- At least the eight squares around: diagonals are within reach too.
        Grid.around(player, math.max(radius, 2), function(square)
            Fetch.floor(square, function(item, container, world, holder, body)
                if instanceof(item, "InventoryContainer") then
                    if not body then inside(around, item:getInventory(), square, 1, world or holder, body) end
                else add(around, item, container, world, holder, body, square) end
            end)
            local objects = square.getObjects and square:getObjects()
            for index = 0, objects and objects:size() - 1 or -1 do
                local object = objects:get(index)
                for c = 0, (object.getContainerCount and object:getContainerCount() or 0) - 1 do
                    local container = object:getContainerByIndex(c)
                    if container and Storage.containerReachable(player, container, true) then inside(around, container, square, 1) end
                end
            end
        end, true)
        cached = {square = here, radius = radius, at = now, around = around}
        looks[player] = cached
    end
    for _, entry in ipairs(cached.around) do
        -- Picked up since: it is in the list above.
        if not carried[entry.item] then found[#found + 1] = entry end
    end
    return found
end

function FirstAid.forget(player) looks[player] = nil end

-- A picker over what was found: anything at hand before anything to walk
-- for; at hand, the better grade, carried first; to walk for, the better
-- grade, then the nearest. Consumables serve once.
-- prefer: an item the player chose; it serves any role it fits, first.
local function picker(player, found, rejected, now, prefer)
    local used, here = {}, player:getSquare()
    local preferID = prefer and read(function() return prefer:getID() end, nil)
    local function key(entry, grade)
        if entry.carried then return {0, grade, 0, 0} end
        if entry.reach then return {0, grade, 1, 0} end
        local dx, dy = entry.square:getX() - here:getX(), entry.square:getY() - here:getY()
        return {1, grade, 2, dx * dx + dy * dy}
    end
    local function before(a, b)
        for index = 1, 4 do if a[index] ~= b[index] then return a[index] < b[index] end end
        return false
    end
    return function(name, options)
        local role = roles[name]
        -- The player's choice is a dressing; it never becomes a burn rag or
        -- anything else, and it is passed over like anything the game refused.
        if preferID and (name == "dressing" or name == "clean") and not (options and options.list) then
            for _, entry in ipairs(found) do
                local item = entry.item
                local held = rejected and rejected[item:getID()]
                if item:getID() == preferID and not used[item] and not (held and now and now < held)
                        and (not options or not options.near or entry.reach)
                        and role.match(item) and Fetch.present(entry.entry) then
                    if role.consumed and not (options and options.peek) then used[item] = true end
                    return entry
                end
            end
        end
        local best, bestKey
        local all = options and options.list and {}
        for _, entry in ipairs(found) do
            local item = entry.item
            local held = rejected and rejected[item:getID()]
            if not used[item] and not (held and now and now < held) and (not options or not options.near or entry.reach)
                    and (not options or not options.carried or entry.carried or (entry.reach and entry.square == nil))
                    and role.match(item) and Fetch.present(entry.entry) then
                local candidate = key(entry, role.grade and role.grade(item) or 1)
                -- The best wherever it is: a walk is no reason for a lesser one.
                if role.anywhere then candidate = {0, candidate[2], candidate[3], candidate[4]} end
                if all then all[#all + 1] = {entry = entry, key = candidate} end
                if not best or before(candidate, bestKey) then best, bestKey = entry, candidate end
            end
        end
        if all then
            table.sort(all, function(a, b) return before(a.key, b.key) end)
            local out = {}
            for _, candidate in ipairs(all) do out[#out + 1] = candidate.entry end
            return out
        end
        if best and role.consumed and not (options and options.peek) then used[best.item] = true end
        return best
    end
end

-- ------------------------------------------------------------- the planning

local bloody = {glass = true, bullet = true, stitch = true, burn = true}
local needsUncovered = {glass = true, bullet = true, disinfect = true, stitch = true, burn = true, poultice = true}

-- The treatments one wound needs now, in the game's order, with what each
-- takes. A treatment nothing is found for is left out; one it blocks waits.
-- change: the player asked for a fresh dressing on this part, dirty or not.
local function treatments(player, part, pick, change)
    local list = {}
    local function add(step) list[#list + 1] = step end
    local covered = part:bandaged()
    local glass, deep, stitched = part:haveGlass(), isDeep(part), isStitched(part)
    -- major: worth the dressing coming off even without a fresh one to follow.
    local major = false
    if glass then
        -- Bare hands hurt twice as long, but glass left in keeps cutting.
        local tool = pick("tweezers")
        add({kind = "glass", tool = tool, hands = tool == nil})
        glass, major = false, true
    end
    if part:haveBullet() then
        local tool = pick("extractor")
        if tool then add({kind = "bullet", tool = tool}); major = true end
    end
    if fractured(part) and not stitched then
        local splint = pick("splint")
        if splint then add({kind = "splint", plank = splint})
        else
            local plank, sheet = pick("plank"), pick("sheet")
            if plank and sheet then add({kind = "splint", plank = plank, sheet = sheet}) end
        end
    end
    local stitch
    if deep and not stitched and not glass then
        local suture = pick("suture")
        local needle = not suture and pick("needle") or nil
        local thread = needle and pick("thread") or nil
        if suture or (needle and thread) then
            -- A holder only makes it quicker: worth taking if at hand, not a walk.
            stitch = {kind = "stitch", thread = suture or thread, needle = needle, holder = pick("holder", {near = true})}
            major = true
        end
    end
    -- An infection is treated for itself, and again once the alcohol wears off.
    local infected = infectionKnown(player, part)
    local alcohol
    if infected and part:getAlcoholLevel() < 1 then
        alcohol = pick("alcohol")
        if alcohol then major = true end
    end
    local stillOpen = part:bleeding() or part:getBleedingTime() > 0 or isScratched(part) or isCut(part)
        or (deep and not stitch) or isBitten(part) or part:getBurnTime() > 0
        or ((stitched or stitch) and part:getStitchTime() <= FirstAid.policy.goodStitch)
    -- Under a dressing, the one to follow it is secured before cloth goes to a burn.
    local dress
    local function pickDress() return pick((part:bleeding() or part:getBleedingTime() > 0) and "dressing" or "clean") end
    if covered and (stillOpen or change) then dress = pickDress() end
    local burn
    if part:isNeedBurnWash() and part:getBurnTime() > 0 then
        local rag = pick("burn")
        if rag then burn = {kind = "burn", rag = rag} end
    end
    -- Riding along: only when the wound is bare, or coming bare anyway.
    local bare = not covered or major or (dress ~= nil and (burn ~= nil or worthChanging(part) or change))
    if not bare then burn = nil end
    if not alcohol and bare and (stitch or deep or isCut(part) or isBitten(part)) and part:getAlcoholLevel() <= 0
            and not pick("sterile", {peek = true}) then
        alcohol = pick("alcohol")
    end
    if alcohol then add({kind = "disinfect", alcohol = alcohol, level = part:getAlcoholLevel()}) end
    if stitch then add(stitch); deep, stitched = false, true end
    if burn then add(burn) end
    if bare and not poulticed(part) then
        local herb
        if infected then herb = pick("garlic")
        elseif part:getFractureTime() > 0 then herb = pick("comfrey")
        elseif deep or isCut(part) then herb = pick("plantain") end
        if herb then add({kind = "poultice", herb = herb}) end
    end
    local uncover = false
    for _, step in ipairs(list) do if needsUncovered[step.kind] then uncover = true end end
    if not covered and (stillOpen or change) then dress = pickDress() end
    if covered and not uncover and not (dress and (worthChanging(part) or change)) then dress = nil end
    if covered and (uncover or dress) then table.insert(list, 1, {kind = "unbandage"}) end
    if dress then add({kind = "bandage", item = dress}) end
    if #list == 0 then
        if goodStitches(part) then add({kind = "unstitch"})
        elseif part:getSplintFactor() > 0 and part:getFractureTime() <= 0 then add({kind = "unsplint"}) end
    end
    return list
end

local fields = {"tool", "alcohol", "plank", "sheet", "thread", "needle", "holder", "rag", "herb", "item"}

-- Every supply a list of steps takes, once each.
local function supplies(list)
    local out, seen = {}, {}
    for _, step in ipairs(list) do
        for _, field in ipairs(fields) do
            local entry = step[field]
            if entry and not seen[entry.item] then seen[entry.item] = true; out[#out + 1] = entry end
        end
    end
    return out
end

local function panicked(player)
    return player:hasTrait(CharacterTrait.HEMOPHOBIC)
        and player:getMoodles():getMoodleLevel(MoodleType.PANIC) >= FirstAid.policy.calmPanic
end

-- The next thing to do for the most dangerous wound, or nil and why not.
-- options.radius: how far to look and walk (0: carried and within reach);
-- options.blocked(part): a wound whose last treatment did not take;
-- options.rejected, options.now: items held back until a time;
-- options.hurry: danger is near, so a bleeding wound gets only a dressing;
-- options.only: the parts the player asked to see to, as a set (a bleeding
-- wound elsewhere still comes first); options.onlyBleeding: nothing else;
-- options.keep: parts always planned, never blocked (a wound left bare);
-- options.choice(part): {change, prefer}: a fresh dressing on that part
-- whatever the old one is like, and the item the player chose.
-- A step: {kind, part, danger, urgent, chain, uses} plus what it takes;
-- "walk" (square) and "take" (entries) come before anything is unwrapped.
-- urgent: for a wound that bleeds; uses: every item the wound's care takes;
-- waits: the care held back while only the bleeding is stopped.
function FirstAid.plan(player, options)
    options = options or {}
    local parts = player:getBodyDamage():getBodyParts()
    local list, bleeders = {}, 0
    for index = 0, parts:size() - 1 do
        local part = parts:get(index)
        -- Only what the game reads as a body part with wounds.
        local danger = part.bandaged and FirstAid.danger(player, part) or 0
        local choice = options.choice and options.choice(part)
        local kept = options.keep and options.keep[part]
        -- A fresh dressing asked for, or one taken off and not yet replaced.
        if danger <= 0 and ((choice and choice.change) or kept) then danger = 1 end
        if danger > 0 then
            if bleedingOpen(part) then bleeders = bleeders + 1 end
            local asked = bleedingOpen(part) or kept
                or (not options.onlyBleeding and (not options.only or options.only[part]))
            local blocked = options.blocked and options.blocked(part)
            -- A wound left bare is still covered after a refusal, but the
            -- refused treatment is not tried again until its wait is over.
            if asked and (kept or not blocked) then list[#list + 1] = {part = part, danger = danger, dressOnly = kept and blocked} end
        end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.danger > b.danger end)
    local found = collect(player, options.radius or 0)
    local function chosen(part) return part and options.choice and options.choice(part) or nil end
    local function fresh(part)
        local choice = chosen(part)
        return picker(player, found, options.rejected, options.now, choice and choice.prefer or nil)
    end
    local function chainFor(part)
        local choice = chosen(part)
        return treatments(player, part, fresh(part), choice and choice.change)
    end
    local missing, waiting
    for _, wound in ipairs(list) do
        local part = wound.part
        local chain = chainFor(part)
        if wound.dressOnly then
            local dress = not part:bandaged() and fresh(part)((part:bleeding() or part:getBleedingTime() > 0) and "dressing" or "clean")
            chain = dress and {{kind = "bandage", item = dress}} or {}
        end
        local urgent = bleedingOpen(part)
        local waits
        -- More than one wound bleeding, a walk, or danger near: the blood is
        -- stopped first, the rest of the care can follow.
        if urgent and #chain > 1 then
            local quick = fresh()("dressing")
            local walk = false
            for _, entry in ipairs(supplies(chain)) do if not entry.reach then walk = true end end
            if quick and (bleeders > 1 or walk or options.hurry) then
                local rest = {}
                for _, step in ipairs(chain) do rest[#rest + 1] = step.kind end
                waits = table.concat(rest, ">")
                chain = {{kind = "bandage", item = quick}}
            end
        end
        if #chain == 0 then
            if urgent and not missing then missing = "bleeding" end
        elseif not urgent and panicked(player) and (function()
                for _, step in ipairs(chain) do if bloody[step.kind] then return true end end
                return false
            end)() then
            -- Not even the dressing comes off while the sight of blood would wait.
            waiting = waiting or "calming"
        else
            local kinds, uses = {}, {}
            for _, step in ipairs(chain) do kinds[#kinds + 1] = step.kind end
            local far, near = nil, {}
            for _, entry in ipairs(supplies(chain)) do
                uses[entry.item] = true
                if not entry.carried then
                    if entry.reach then near[#near + 1] = entry
                    elseif not far then far = entry end
                end
            end
            -- Fetch first: nothing is unwrapped until all of it is at hand.
            local step
            if #near > 0 then step = {kind = "take", entries = near}
            elseif far then step = {kind = "walk", square = far.square, entry = far}
            else step = chain[1] end
            step.part, step.danger, step.urgent, step.uses = part, wound.danger, urgent, uses
            step.chain, step.waits = table.concat(kinds, ">"), waits
            -- What the other wounds will take stays borrowed too.
            for _, other in ipairs(list) do
                if other ~= wound then
                    for _, entry in ipairs(supplies(chainFor(other.part))) do uses[entry.item] = true end
                end
            end
            return step
        end
    end
    return nil, missing or waiting
end

-- What one wound's care would be now, read only: each step with what it
-- would use and where that is, and what nothing was found for.
-- radius: as for plan; choice: {change, prefer} as the player picked them.
-- A step: {kind, item, carried, walk, hands}.
function FirstAid.preview(player, part, radius, choice)
    choice = choice or {}
    local chain = treatments(player, part, picker(player, collect(player, radius or 0), nil, nil, choice.prefer), choice.change)
    local steps, have = {}, {}
    for _, step in ipairs(chain) do
        have[step.kind] = true
        local entry = step.item or step.tool or step.thread or step.plank or step.alcohol or step.rag or step.herb
        steps[#steps + 1] = {kind = step.kind, item = entry and read(function() return entry.item:getDisplayName() end, nil),
            carried = entry and entry.carried or false, walk = entry ~= nil and not entry.reach, hands = step.hands == true}
    end
    local missing = {}
    local function need(wanted, kind, what) if wanted and not have[kind] then missing[#missing + 1] = what end end
    local covered = part:bandaged()
    need(part:haveBullet(), "bullet", "tweezers or a suture needle holder")
    need(fractured(part) and not isStitched(part), "splint", "a splint, or a plank and ripped sheets")
    need(unstitched(part), "stitch", "a suture needle, or a needle and thread")
    need(infectionKnown(player, part) and part:getAlcoholLevel() < 1, "disinfect", "disinfectant or strong alcohol")
    need(not covered and (dressable(part) or part:bleeding()), "bandage", "a bandage or a rag")
    need(covered and worthChanging(part), "bandage", "a clean dressing")
    need(part:isNeedBurnWash() and part:getBurnTime() > 0, "burn", "a clean rag or bandage for the burn")
    return {steps = steps, missing = missing, covered = covered, danger = FirstAid.danger(player, part)}
end

FirstAid.infectionKnown = infectionKnown
FirstAid.fractured = fractured
FirstAid.worthChanging = worthChanging
FirstAid.dressable = dressable
FirstAid.wound = {deep = isDeep, stitched = isStitched, cut = isCut, scratched = isScratched, bitten = isBitten}

-- --------------------------------------------------------------- the actions

-- In the main inventory, by ID: in multiplayer the object may be replaced.
local function current(player, entry)
    local inventory = player:getInventory()
    local item = entry and inventory:getItemById(entry.item:getID())
    return item ~= nil and item:getContainer() == inventory and item or nil
end
local function held(player, entry) return current(player, entry) ~= nil end

-- The game's action for a step, or nothing when the game would refuse it.
function FirstAid.action(player, step)
    local part = step.part
    local k = step.kind
    if k == "unbandage" then return part:bandaged() and ISApplyBandage:new(player, player, nil, part, false) or nil end
    if needsUncovered[k] and part:bandaged() then return nil end
    for _, field in ipairs(fields) do
        if step[field] and not held(player, step[field]) then return nil end
    end
    local function use(field) return step[field] and current(player, step[field]) or nil end
    if k == "bandage" then return (not part:bandaged() and dressing(use("item"))) and ISApplyBandage:new(player, player, use("item"), part, true) or nil end
    if k == "glass" then return part:haveGlass() and ISRemoveGlass:new(player, player, part, step.hands == true) or nil end
    if k == "bullet" then return part:haveBullet() and ISRemoveBullet:new(player, player, part) or nil end
    if k == "disinfect" then return ISDisinfect:new(player, player, use("alcohol"), part) end
    if k == "splint" then return ISSplint:new(player, player, use("sheet"), use("plank"), part, true) end
    if k == "stitch" then return (part:deepWounded() and not part:haveGlass()) and ISStitch:new(player, player, use("thread"), part, true) or nil end
    if k == "burn" then return ISCleanBurn:new(player, player, use("rag"), part) end
    if k == "poultice" then
        local herb = use("herb")
        local class = kind(herb) == "ComfreyCataplasm" and ISComfreyCataplasm or kind(herb) == "WildGarlicCataplasm" and ISGarlicCataplasm or ISPlantainCataplasm
        return class:new(player, player, herb, part)
    end
    if k == "unstitch" then return goodStitches(part) and ISStitch:new(player, player, nil, part, false) or nil end
    if k == "unsplint" then return part:getSplintFactor() > 0 and ISSplint:new(player, player, nil, nil, part, false) or nil end
    return nil
end

-- Whether a step did what it was for, read from the survivor.
function FirstAid.done(player, step)
    local part, k = step.part, step.kind
    if k == "take" then
        for _, entry in ipairs(step.entries) do if not held(player, entry) then return false end end
        return true
    end
    if k == "walk" then return Grid.reachable(player:getSquare(), step.square) end
    if k == "unbandage" then return not part:bandaged() end
    if k == "bandage" then return part:bandaged() end
    if k == "glass" then return not part:haveGlass() end
    if k == "bullet" then return not part:haveBullet() end
    if k == "disinfect" then return part:getAlcoholLevel() > (step.level or 0) end
    if k == "splint" then return part:getSplintFactor() > 0 end
    if k == "stitch" then return part:stitched() end
    if k == "burn" then return not part:isNeedBurnWash() end
    if k == "poultice" then return poulticed(part) end
    if k == "unstitch" then return not part:stitched() end
    if k == "unsplint" then return part:getSplintFactor() <= 0 end
    return false
end

function FirstAid.partName(part)
    local ok, name = pcall(function() return BodyPartType.getDisplayName(part:getType()) end)
    return ok and type(name) == "string" and name or "wound"
end

local phrases = {unbandage = "Taking the dressing off", bandage = "Bandaging", glass = "Pulling glass out",
    bullet = "Taking the bullet out", disinfect = "Disinfecting", splint = "Splinting", stitch = "Stitching",
    burn = "Cleaning the burn", poultice = "Applying a poultice", unstitch = "Taking healed stitches out",
    unsplint = "Taking the splint off a healed bone"}

function FirstAid.describe(step)
    if step.kind == "take" then
        local names = {}
        for _, entry in ipairs(step.entries) do names[#names + 1] = entry.item:getDisplayName() end
        return "Getting " .. table.concat(names, ", ") .. "."
    end
    if step.kind == "walk" then return "Going for " .. step.entry.item:getDisplayName() .. "." end
    if step.kind == "glass" and step.hands then return "Pulling glass out by hand: " .. FirstAid.partName(step.part) .. "." end
    return (phrases[step.kind] or "First aid") .. ": " .. FirstAid.partName(step.part) .. "."
end

-- Other care's roles, found in the same look around (Dressings).
function FirstAid.addRoles(more)
    for name, role in pairs(more) do roles[name] = role end
    looks = {}
end

-- A picker over what is carried and within radius, for other care.
-- options.near: within reach; options.carried: carried, bags included;
-- options.peek: not counted as used; options.list: every match, best first.
function FirstAid.picker(player, radius, rejected, now)
    return picker(player, collect(player, radius or 0), rejected, now)
end

-- Whether any clean dressing is carried or within radius (for the outlook).
function FirstAid.bandagesWithin(player, radius)
    return picker(player, collect(player, radius or 0))("clean") ~= nil
end

return FirstAid
