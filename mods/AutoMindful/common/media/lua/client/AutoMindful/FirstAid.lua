-- Stops bleeding and covers wounds with the game's own bandage action. It
-- never stitches, pulls out glass or bullets, or sets bones: those hurt, need
-- tools and skill, and are the player's decision.
require "TimedActions/ISApplyBandage"
local Supplies = require "AutoMindful/Supplies"
local Danger = require "AutoMindful/Danger"

local FirstAid = {}

local function dirty(item) return string.find(item:getType() or "", "Dirty", 1, true) ~= nil end

local function bandage(item)
    return item.getBandagePower and item:getBandagePower() > 0 and not (item.isInfected and item:isInfected())
end

local grades = {
    function(item) return bandage(item) and not dirty(item) and item:isAlcoholic() end,
    function(item) return bandage(item) and not dirty(item) end,
}

local function open(part)
    return part:scratched() or part:isCut() or part:deepWounded() or part:bitten()
end

-- The one wound to look after next: whatever bleeds, then open wounds, then
-- bandages that have turned dirty.
function FirstAid.wound(player)
    local parts = player:getBodyDamage():getBodyParts()
    local best, rank = nil, 0
    for index = 0, parts:size() - 1 do
        local part = parts:get(index)
        local covered = part.bandaged and part:bandaged()
        local value = 0
        if covered == nil then value = 0
        elseif part:bleeding() and not covered then value = 4 + (part:deepWounded() and 1 or 0)
        elseif open(part) and not covered then value = 2
        elseif covered and part:isBandageDirty() and part:HasInjury() then value = 1 end
        if value > rank then best, rank = part, value end
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

function FirstAid.next(player, includeNearby)
    local part, rank = FirstAid.wound(player)
    if not part then return nil end
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

function FirstAid.needed(player)
    if Danger.bleeding(player) then return true end
    local body = player:getBodyDamage()
    return body.getBodyParts ~= nil and FirstAid.wound(player) ~= nil
end

return FirstAid
