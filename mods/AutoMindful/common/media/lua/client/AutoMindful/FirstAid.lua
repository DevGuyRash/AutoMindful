-- Stops bleeding and covers wounds with the game's own bandage action. It
-- never stitches, pulls out glass or bullets, or sets bones: those hurt, need
-- tools and skill, and are the player's decision.
require "TimedActions/ISApplyBandage"
local Supplies = require "AutoMindful/Supplies"

local FirstAid = {}

local function dirty(item) return string.find(item:getType() or "", "Dirty", 1, true) ~= nil end

local function bandage(item)
    return item.getBandagePower and item:getBandagePower() > 0 and not (item.isInfected and item:isInfected())
end

local grades = {
    function(item) return bandage(item) and not dirty(item) and item:isAlcoholic() end,
    function(item) return bandage(item) and not dirty(item) end,
}

-- The game's own test for what may be dressed, without fractures: a dressing
-- does nothing for those.
local function open(part)
    return part:scratched() or part:isCut() or part:deepWounded() or part:bitten() or part:getBurnTime() > 0
end

-- A dressing on a wound that has not been stitched, or still bleeds, is dirty
-- again in moments. Changing it would only use up every clean one.
local function worthChanging(part)
    return part:isBandageDirty() and open(part) and not part:deepWounded() and part:getBleedingTime() <= 0
end

-- The one wound to look after next: whatever bleeds, then open wounds, then
-- bandages that have turned dirty.
function FirstAid.wound(player, blocked)
    local parts = player:getBodyDamage():getBodyParts()
    local best, rank = nil, 0
    for index = 0, parts:size() - 1 do
        local part = parts:get(index)
        local covered = part.bandaged and part:bandaged()
        local value = 0
        if covered == nil then value = 0
        elseif part:bleeding() and not covered then value = 4 + (part:deepWounded() and 1 or 0)
        elseif open(part) and not covered then value = 2
        elseif covered and worthChanging(part) then value = 1 end
        if value > rank and not (blocked and blocked(part)) then best, rank = part, value end
    end
    return best, rank
end

local function find(player, includeNearby, bleeding)
    for _, grade in ipairs(grades) do
        local item = Supplies.findCareItem(player, grade, includeNearby)
        if item then return item end
    end
    -- A dirty rag still stops blood; it is not worth an infection otherwise.
    return bleeding and Supplies.findCareItem(player, bandage, includeNearby) or nil
end

-- blocked(part) holds back a wound whose last treatment did not take.
function FirstAid.next(player, includeNearby, part, rank)
    local bleeding = rank >= 4
    local item = find(player, includeNearby, bleeding)
    if not item then return nil, bleeding and "bleeding" or rank >= 2 and "open" or nil end
    return {part=part, item=item, remove=rank == 1, bleeding=bleeding}
end

function FirstAid.bandagesWithin(player, includeNearby)
    return find(player, includeNearby, false) ~= nil
end

function FirstAid.partName(part)
    local ok, name = pcall(function() return BodyPartType.getDisplayName(part:getType()) end)
    return ok and type(name) == "string" and name or "wound"
end

-- Returns the native action, or nothing when the game would refuse it.
function FirstAid.action(player, plan)
    local part = plan.part
    if part:bandaged() ~= plan.remove then return nil end
    if plan.remove then return ISApplyBandage:new(player, player, nil, part, false) end
    if plan.item:getContainer() ~= player:getInventory() or not bandage(plan.item) then return nil end
    return ISApplyBandage:new(player, player, plan.item, part, true)
end

return FirstAid
