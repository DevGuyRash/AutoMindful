require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISInventoryTransferUtil"

AutoMindful = AutoMindful or {}
local Supplies = {}
AutoMindful.Supplies = Supplies

local function readable(player, item)
    if not instanceof(item, "Literature") or item:getBoredomChange() >= 0 then return false end
    if SkillBook[item:getSkillTrained()] or item:hasTag(ItemTag.UNINTERESTING) then return false end
    if player:hasTrait(CharacterTrait.ILLITERATE)
            and not item:hasTag(ItemTag.PICTUREBOOK) and not item:hasTag(ItemTag.PICTURE) then return false end
    local data = item:hasModData() and item:getModData()
    if data and data.literatureTitle and player:isLiteratureRead(data.literatureTitle) then return false end
    if data and data.printMedia and player:getReadPrintMedia():contains(data.printMedia.id) then return false end
    return true
end

local function edible(item)
    if not instanceof(item, "Food") or item:getHungerChange() >= 0 then return false end
    if item:isRotten() or item:isBurnt() or item:isFrozen() or item:isTainted()
            or item:isPoison() or item:getPoisonPower() > 0 or item:getFoodSicknessChange() > 0
            or item:isAlcoholic() or item:isSealed() then return false end
    if item:isbDangerousUncooked() and not item:isCooked() then return false end
    local required = item:getRequireInHandOrInventory()
    return not required or required:isEmpty()
end

local function drinkable(item)
    local fluid = item:getFluidContainer()
    return fluid and not fluid:isEmpty() and fluid:canPlayerEmpty()
        and fluid:getCapacity() <= 3 and fluid:isPureFluid(Fluid.Water)
        and not fluid:isPoisonous() and not fluid:isTainted() and not item:isSealed()
end

local predicates = {food = function(_, item) return edible(item) end, water = function(_, item) return drinkable(item) end,
    literature = readable}

function Supplies.scan(player, includeNearby)
    local result = {food = {}, water = {}, literature = {}}
    local inventory, visited = player:getInventory(), {}
    local function visit(container, owned, recurse)
        if not container or visited[container] then return end
        visited[container] = true
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            for kind, predicate in pairs(predicates) do
                if predicate(player, item) then
                    result[kind][#result[kind] + 1] = {item = item, owned = owned}
                end
            end
            if recurse and instanceof(item, "InventoryContainer") then visit(item:getInventory(), owned, true) end
        end
    end
    visit(inventory, true, true)
    if includeNearby and getPlayerInventory(player:getPlayerNum()) and getPlayerLoot(player:getPlayerNum()) then
        local containers = ISInventoryPaneContextMenu.getContainers(player)
        if containers then
            for i = 0, containers:size() - 1 do
                local container = containers:get(i)
                local owned = container:getOutermostContainer() == inventory
                local square = container:getSourceGrid()
                local here = player:getSquare()
                if owned or (square and here and square:getZ() == here:getZ()
                        and math.abs(square:getX() - here:getX()) <= 1
                        and math.abs(square:getY() - here:getY()) <= 1) then
                    visit(container, owned, owned)
                end
            end
        end
    end
    return result
end

function Supplies.choose(player, kind, includeNearby, rejected)
    local best, bestScore
    for _, entry in ipairs(Supplies.scan(player, includeNearby)[kind]) do
        local item = entry.item
        if not rejected[item:getID()] and (entry.owned or player:getInventory():hasRoomFor(player, item)) then
            local score = entry.owned and 100000 or 0
            if kind == "literature" then score = score - item:getBoredomChange()
            elseif kind == "food" then score = score + math.max(0, item:getCalories()) - item:getBoredomChange() * 5
            else score = score + item:getFluidContainer():getAmount() end
            if not bestScore or score > bestScore then best, bestScore = entry, score end
        end
    end
    return best
end

function Supplies.transfer(player, item)
    if item:getContainer() == player:getInventory() then return true end
    if not player:getInventory():hasRoomFor(player, item) then return false end
    local action = ISInventoryTransferUtil.newInventoryTransferAction(player, item, item:getContainer(), player:getInventory())
    if action.ignoreAction then return false end
    ISTimedActionQueue.add(action)
    return true
end

function Supplies.report(player, includeNearby)
    local scan = Supplies.scan(player, includeNearby)
    local report = {food = 0, water = 0, literature = 0, nearbyFood = 0, nearbyWater = 0,
        nearbyLiterature = 0, warnings = {}}
    local nearbyKeys = {food = "nearbyFood", water = "nearbyWater", literature = "nearbyLiterature"}
    for kind, entries in pairs(scan) do
        for _, entry in ipairs(entries) do
            local key = entry.owned and kind or nearbyKeys[kind]
            report[key] = report[key] + 1
        end
    end
    if report.food + report.nearbyFood == 0 then report.warnings[#report.warnings + 1] = "Bring ready-to-eat, safe food. Open cans and thaw or cook meals first." end
    if report.water + report.nearbyWater == 0 then report.warnings[#report.warnings + 1] = "Bring bottles of clean water." end
    if report.literature + report.nearbyLiterature == 0 then report.warnings[#report.warnings + 1] = "Bring unread boredom-reducing literature. Yoga can also relieve boredom when available." end
    if player:tooDarkToRead() then report.warnings[#report.warnings + 1] = "It is too dark to read here. Use a lit training spot." end
    if SandboxVars.Yoga and SandboxVars.Yoga.RequiresMat then report.warnings[#report.warnings + 1] = "Yoga requires a deployed, complete yoga mat under your current square." end
    local lines = {string.format("In your inventory: %d safe food, %d clean water, %d useful literature.", report.food, report.water, report.literature)}
    if includeNearby then
        lines[#lines + 1] = string.format("Within adjacent loot range: %d food, %d water, %d literature.", report.nearbyFood, report.nearbyWater, report.nearbyLiterature)
        lines[#lines + 1] = "Nearby collection takes supplies as needed, one item at a time. It does not walk away."
    end
    for _, warning in ipairs(report.warnings) do lines[#lines + 1] = warning end
    lines[#lines + 1] = "Use a safe, quiet, lit spot. Training uses normal XP rates and may take many game days."
    lines[#lines + 1] = "AutoMindful rests and sleeps in place when needed, then resumes. Move, aim, or press Stop to cancel."
    report.message = table.concat(lines, "\n")
    return report
end

return Supplies
