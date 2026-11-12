require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISDropWorldItemAction"
local Consumables = require "AutoMindful/Consumables"
local WaterSources = require "AutoMindful/WaterSources"

AutoMindful = AutoMindful or {}
local Supplies = {}
AutoMindful.Supplies = Supplies
local refreshes = {}

local function readingHistory(player, item)
    local data = item:hasModData() and item:getModData()
    if data and data.literatureTitle then
        local last = player:getReadLiterature():get(data.literatureTitle)
        return data.literatureTitle, last and tonumber(last) or nil
    end
    local key = "item:" .. tostring(item:getID())
    local history = player:getModData().AutoMindfulReadHistory
    return key, history and history[key] or nil
end

local function readingState(player, item)
    if not instanceof(item, "Literature") or item:getBoredomChange() >= 0 then return false end
    if SkillBook[item:getSkillTrained()] or item:hasTag(ItemTag.UNINTERESTING) then return false end
    if player:hasTrait(CharacterTrait.ILLITERATE)
            and not item:hasTag(ItemTag.PICTUREBOOK) and not item:hasTag(ItemTag.PICTURE) then return false end
    local data = item:hasModData() and item:getModData()
    if data and data.literatureTitle and player:isLiteratureRead(data.literatureTitle) then return "cooldown" end
    if data and data.printMedia and player:getReadPrintMedia():contains(data.printMedia.id) then return false end
    local _, last = readingHistory(player, item)
    return last ~= nil and "reread" or "unread"
end

local function containers(player)
    local index = player:getPlayerNum()
    local loot = getPlayerLoot(index)
    if not getPlayerInventory(index) or not loot then return nil end
    local now, square = getTimestampMs(), player:getSquare()
    local previous = refreshes[player]
    if not previous or previous.square ~= square or now - previous.time >= 1000 then
        loot:refreshBackpacks()
        refreshes[player] = {square = square, time = now}
    end
    return ISInventoryPaneContextMenu.getContainers(player)
end

local function reachable(player, square)
    local here = player:getSquare()
    return square and here and square:getZ() == here:getZ()
        and math.abs(square:getX() - here:getX()) <= 1
        and math.abs(square:getY() - here:getY()) <= 1
        and (square == here or here:canReachTo(square))
end

local function containerSquare(container)
    local square = container:getSourceGrid()
    if square then return square end
    local item = container:getContainingItem()
    local world = item and item:getWorldItem()
    return world and world:getSquare()
end

function Supplies.scan(player, includeNearby, useNearbyTools)
    if useNearbyTools == nil then useNearbyTools = includeNearby end
    local result = {food = {}, water = {}, literature = {}, cooldownLiterature = 0, nearbyCooldownLiterature = 0}
    result.waterSources = includeNearby and WaterSources.scan(player) or {}
    local inventory, visited = player:getInventory(), {}
    local nearby = includeNearby and containers(player) or nil
    local function visit(container, owned, recurse, floor)
        if not container or visited[container] then return end
        visited[container] = true
        local items = container:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            local world = floor and item:getWorldItem()
            if not floor or (world and reachable(player, world:getSquare())) then
                local entry = {item = item, owned = owned}
                local consumable = Consumables.inspect(player, item, useNearbyTools)
                entry.description = consumable
                if consumable.food then result.food[#result.food + 1] = entry end
                if consumable.water then result.water[#result.water + 1] = entry end
                if consumable.needsOpening and consumable.reason then result.openingReason = consumable.reason end
                local reading = readingState(player, item)
                if reading == "cooldown" then
                    local key = owned and "cooldownLiterature" or "nearbyCooldownLiterature"
                    result[key] = result[key] + 1
                elseif reading then
                    local _, last = readingHistory(player, item)
                    entry.lastRead = last
                    result.literature[#result.literature + 1] = entry
                end
            end
            if recurse and instanceof(item, "InventoryContainer") then visit(item:getInventory(), owned, true) end
        end
    end
    visit(inventory, true, true)
    if includeNearby then
        if nearby then
            for index = 0, nearby:size() - 1 do
                local container = nearby:get(index)
                local owned = container:getOutermostContainer() == inventory
                local floor = container:getType() == "floor"
                if owned or floor or reachable(player, containerSquare(container)) then
                    visit(container, owned, owned, floor)
                end
            end
        end
    end
    return result
end

local function rejectedItem(rejected, key)
    local rejection = rejected[key]
    if type(rejection) == "number" and getTimestampMs() >= rejection then
        rejected[key], rejection = nil, nil
    end
    return rejection
end

local function preparationCost(player, entry)
    if entry.source then return 1 + (player:isSitOnGround() and 1 or 0) end
    local description, inventory = entry.description, player:getInventory()
    local cost = 1 + (description.needsOpening and 1 or 0)
    if entry.item:getContainer() ~= inventory then cost = cost + 2 end
    for _, tool in ipairs(description.returnItems or {}) do
        if tool:getContainer() ~= inventory then cost = cost + 2 end
    end
    return cost
end

local function better(candidate, best, kind, critical)
    if not best then return true end
    local comparisons = {}
    if critical then comparisons[#comparisons + 1] = {candidate.plan.primary, best.plan.primary} end
    comparisons[#comparisons + 1] = {candidate.plan.utility, best.plan.utility}
    comparisons[#comparisons + 1] = {candidate.plan.secondary > 0 and 1 or 0, best.plan.secondary > 0 and 1 or 0}
    if kind == "water" then comparisons[#comparisons + 1] = {candidate.reserve, best.reserve} end
    comparisons[#comparisons + 1] = {-candidate.cost, -best.cost}
    for _, comparison in ipairs(comparisons) do
        if math.abs(comparison[1] - comparison[2]) > 0.000001 then return comparison[1] > comparison[2] end
    end
    return candidate.item and best.item and candidate.item:getID() < best.item:getID() or false
end

function Supplies.choose(player, kind, includeNearby, rejected, worldOnly)
    local scan = Supplies.scan(player, includeNearby)
    local best
    if kind == "literature" then
        for _, entry in ipairs(scan.literature) do
            if not rejectedItem(rejected, entry.item:getID()) and (entry.owned or player:getInventory():hasRoomFor(player, entry.item))
                    and (not best or (entry.lastRead == nil and best.lastRead ~= nil)
                        or ((entry.lastRead == nil) == (best.lastRead == nil)
                            and ((entry.lastRead or -1) < (best.lastRead or -1)
                                or (entry.lastRead == best.lastRead and entry.owned and not best.owned)))) then
                best = entry
            end
        end
        return best
    end
    local critical = player:getMoodles():getMoodleLevel(kind == "water" and MoodleType.THIRST or MoodleType.HUNGRY) >= 4
    local function consider(entry)
        entry.plan = Consumables.plan(player, entry.description, kind)
        if not entry.plan then return end
        entry.reserve = entry.description.remainingLiters or entry.description.thirstRelief * 2
        entry.cost = preparationCost(player, entry)
        if better(entry, best, kind, critical) then best = entry end
    end
    if not worldOnly then
        for _, entry in ipairs(scan[kind]) do
            if not rejectedItem(rejected, entry.item:getID()) and (entry.owned or player:getInventory():hasRoomFor(player, entry.item)) then
                consider(entry)
            end
        end
    end
    if kind == "water" then
        for _, source in ipairs(scan.waterSources) do
            if not rejectedItem(rejected, source.object) and not (source.item and rejectedItem(rejected, source.item:getID())) then
                consider({source = source, description = {hungerEffect = 0, thirstEffect = source.remainingLiters / 2,
                    thirstRelief = source.remainingLiters / 2, remainingLiters = source.remainingLiters}})
            end
        end
    end
    return best
end

function Supplies.markRead(player, item)
    local data = item:hasModData() and item:getModData()
    if data and data.literatureTitle then return end
    local saved = player:getModData()
    saved.AutoMindfulReadHistory = saved.AutoMindfulReadHistory or {}
    saved.AutoMindfulReadHistory["item:" .. tostring(item:getID())] = getGameTime():getNightsSurvived()
end

function Supplies.transfer(player, item)
    if item:getContainer() == player:getInventory() then return true end
    if not player:getInventory():hasRoomFor(player, item) then return false end
    local action = ISInventoryTransferUtil.newInventoryTransferAction(player, item, item:getContainer(), player:getInventory())
    if action.ignoreAction then return false end
    ISTimedActionQueue.add(action)
    return true
end

function Supplies.inventoryItem(player, item)
    return player:getInventory():getItemById(item:getID())
end

function Supplies.inventoryIDs(player)
    local ids = {}
    local items = player:getInventory():getItems()
    for index = 0, items:size() - 1 do ids[items:get(index):getID()] = true end
    return ids
end

function Supplies.newOutputs(player, before, types)
    local found = {}
    local items = player:getInventory():getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if not before[item:getID()] and types[item:getFullType()] then found[#found + 1] = item end
    end
    return found
end

function Supplies.loan(player, item)
    if item:getContainer() == player:getInventory() then return nil end
    local loan = {origin = item:getContainer(), items = {item}, original = item,
        before = Supplies.inventoryIDs(player), expected = Consumables.replacements(item), defer = true}
    local world = item:getWorldItem()
    if world then
        loan.floor = {square = world:getSquare(), x = world:getOffX(), y = world:getOffY(), z = world:getOffZ()}
    end
    return loan
end

function Supplies.watchLoan(player, loan, item)
    if not loan then return end
    loan.before = Supplies.inventoryIDs(player)
    loan.interference = nil
    loan.expected = Consumables.replacements(item)
    loan.usedItem = item
    local known = false
    for index, entry in ipairs(loan.items) do
        if entry:getID() == item:getID() then loan.items[index] = item; known = true; break end
    end
    if not known then loan.items[#loan.items + 1] = item end
end

function Supplies.finishLoan(player, loan, now)
    if not loan or not loan.usedItem then return true end
    if not Supplies.inventoryItem(player, loan.usedItem) and not loan.interference then
        local replacements = Supplies.newOutputs(player, loan.before, loan.expected)
        if #replacements == 1 then loan.items[#loan.items + 1] = replacements[1]
        elseif #replacements > 1 then loan.notice = "An empty container could not be identified safely; it stays in your inventory."
        elseif next(loan.expected) and now then
            loan.awaitResultUntil = loan.awaitResultUntil or now + 3000
            if now < loan.awaitResultUntil then return false end
            loan.notice = "The game did not confirm an empty container; any delayed result stays in your inventory."
        end
    end
    loan.usedItem, loan.awaitResultUntil = nil, nil
    return true
end

function Supplies.returnAction(player, loan)
    local inventory = player:getInventory()
    local origin = loan.origin
    local item
    for _, candidate in ipairs(loan.items) do
        local current = Supplies.inventoryItem(player, candidate)
        if current and current:getContainer() ~= origin then item = current; break end
    end
    if not item then return nil, nil, true end
    if loan.floor then
        if not reachable(player, loan.floor.square) then
            return nil, "Borrowed supplies stay with you because their original floor square is out of reach."
        end
        local floor = loan.floor
        local action = ISDropWorldItemAction:new(player, item, floor.square, floor.x, floor.y, floor.z, 0, false)
        action.isPlaceItem = true
        if not action:isValid() then return nil, "Borrowed supplies stay with you because the original floor square cannot accept them." end
        return action
    end
    local owned = origin:getOutermostContainer() == inventory
    if not owned then
        local nearby = containers(player)
        if not nearby or not nearby:contains(origin) or not reachable(player, containerSquare(origin)) then
            return nil, "Borrowed supplies stay with you because their original container is no longer reachable."
        end
    end
    if not origin:hasRoomFor(player, item) then
        return nil, "Borrowed supplies stay with you because their original container is full."
    end
    local action = ISInventoryTransferUtil.newInventoryTransferAction(player, item, item:getContainer(), origin)
    if action.ignoreAction or not action:isValid() then
        return nil, "Borrowed supplies stay with you because the original container cannot currently accept them."
    end
    return action
end

function Supplies.report(player, includeNearby, collectNearby)
    if collectNearby == nil then collectNearby = includeNearby end
    local scan = Supplies.scan(player, includeNearby, collectNearby)
    local report = {food = 0, water = 0, literature = 0, nearbyFood = 0, nearbyWater = 0,
        nearbyLiterature = 0, unreadLiterature = 0, rereadLiterature = 0,
        nearbyUnreadLiterature = 0, nearbyRereadLiterature = 0, warnings = {}}
    report.cooldownLiterature, report.nearbyCooldownLiterature = scan.cooldownLiterature, scan.nearbyCooldownLiterature
    report.openingReason = scan.openingReason
    report.nearbyWaterSourceCount = #scan.waterSources
    report.waterSourceReason = scan.waterSources.reason
    local nearbyKeys = {food = "nearbyFood", water = "nearbyWater", literature = "nearbyLiterature"}
    for _, kind in ipairs({"food", "water", "literature"}) do
        for _, entry in ipairs(scan[kind]) do
            local key = entry.owned and kind or nearbyKeys[kind]
            report[key] = report[key] + 1
            if kind == "literature" then
                local typeKey = entry.lastRead and "rereadLiterature" or "unreadLiterature"
                if not entry.owned then typeKey = entry.lastRead and "nearbyRereadLiterature" or "nearbyUnreadLiterature" end
                report[typeKey] = report[typeKey] + 1
            end
        end
    end
    local portableWater = {}
    for _, entry in ipairs(scan.water) do portableWater[entry.item] = true end
    for _, source in ipairs(scan.waterSources) do
        if not source.item or not portableWater[source.item] then report.nearbyWater = report.nearbyWater + 1 end
    end
    local usableFood = report.food + (collectNearby and report.nearbyFood or 0)
    local usableWater = report.water + (collectNearby and report.nearbyWater or 0)
    local usableLiterature = report.literature + (collectNearby and report.nearbyLiterature or 0)
    if includeNearby and not collectNearby then report.warnings[#report.warnings + 1] = "Nearby stock is visible, but collection is off. Enable it or move supplies into your inventory." end
    if usableFood == 0 then report.warnings[#report.warnings + 1] = scan.openingReason or "Bring safe food or a nourishing drink. Opening tools must be available for sealed food." end
    if usableWater == 0 then report.warnings[#report.warnings + 1] = report.waterSourceReason or "Bring safe water or another safe hydrating drink, or enable a reachable clean-water source." end
    if usableLiterature == 0 then
        report.warnings[#report.warnings + 1] = scan.cooldownLiterature + scan.nearbyCooldownLiterature > 0
            and "Available literature was read too recently. The native reread cooldown must expire; unread literature or yoga can help now."
            or "Bring boredom-reducing literature that is unread or past the game's reread cooldown. Yoga can also help."
    end
    if player:tooDarkToRead() then report.warnings[#report.warnings + 1] = "It is too dark to read here. Use a lit training spot." end
    if SandboxVars.Yoga and SandboxVars.Yoga.RequiresMat then report.warnings[#report.warnings + 1] = "Yoga requires a deployed, complete yoga mat under your current square." end
    local lines = {string.format("In your inventory: %d food, %d hydrating drinks, %d useful literature.", report.food, report.water, report.literature)}
    if includeNearby then
        lines[#lines + 1] = string.format("Within adjacent loot range: %d food, %d drinks, %d literature.", report.nearbyFood, report.nearbyWater, report.nearbyLiterature)
        lines[#lines + 1] = "Borrowed supplies and their empty containers are returned to their original reachable source."
    end
    for _, warning in ipairs(report.warnings) do lines[#lines + 1] = warning end
    lines[#lines + 1] = "Unread literature is used first, then eligible rereads from oldest to newest. Native cooldowns still apply."
    report.message = table.concat(lines, "\n")
    return report
end

return Supplies
