require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISDropWorldItemAction"
local Consumables = require "AutoMindful/Consumables"
local Diet = require "AutoMindful/Diet"
local WaterSources = require "AutoMindful/WaterSources"
local Fluids = require "AutoMindful/Fluids"
local Storage = require "AutoMindful/Storage"
local Grid = require "AutoMindful/Grid"
local PainCare = require "AutoMindful/PainCare"

AutoMindful = AutoMindful or {}
local Supplies = {}
local Needs = require "AutoMindful/SurvivalNeeds"
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

-- Shared by adjacent scanning and read-only wider-area discovery.
function Supplies.literatureInfo(player, item)
    local state = readingState(player, item)
    local _, last = readingHistory(player, item)
    return state, last
end

function Supplies.eligibleLiterature(player, item)
    local state = readingState(player, item)
    return state == "unread" or state == "reread"
end

-- The loot window belongs to the player: a refresh rebuilds its buttons, sorts
-- its list, and fires an event other inventory and crafting mods act on. The
-- game already refreshes it on every step and turn, and containers are live
-- objects, so looking needs none. One per new square covers a hidden window.
local staleMs, arrivalMs = 30000, 1000
local function containers(player, arriving)
    local index = player:getPlayerNum()
    local loot = getPlayerLoot(index)
    if not getPlayerInventory(index) or not loot then return nil end
    local now, square = getTimestampMs(), player:getSquare()
    local previous = refreshes[player]
    if not previous or previous.square ~= square or now < previous.time
            or now - previous.time >= (arriving and arrivalMs or staleMs) then
        loot:refreshBackpacks()
        refreshes[player] = {square = square, time = now}
    end
    return ISInventoryPaneContextMenu.getContainers(player)
end

-- Arrived somewhere, or about to use something: current contents matter, and
-- in multiplayer this is what requests them.
function Supplies.refreshNearby(player)
    return containers(player, true)
end

-- Next to the survivor, with nothing in between.
local function reachable(player, square)
    local here = player:getSquare()
    return Grid.reachable(here, square)
end

local containerSquare = Grid.containerSquare

-- Where a container is: its own square, the bag lying there, the vehicle it
-- belongs to or the body whose pockets it is. nil when none of those (a
-- vehicle that is moving or shut counts as nowhere).
local function sourceSquare(container)
    local square = containerSquare(container)
    if square then return square end
    local part = Storage.partFor(container)
    if part then
        local _, vehicleSquare = Storage.vehiclePart(part)
        return vehicleSquare
    end
    local body = Storage.corpseFor(container)
    return body and body:getSquare() or nil
end
Supplies.sourceSquare = sourceSquare

local function canCollect(player, entry)
    return entry.worldSource ~= nil or entry.owned or entry.item:getContainer() == player:getInventory()
        or player:getInventory():hasRoomFor(player, entry.item)
end

local function transferCompatible(player, source, vessel)
    if not Fluids.emptyVessel(vessel.item) then return false, "A clean empty drinking vessel is needed for bulk liquids." end
    if not canCollect(player, source) or not canCollect(player, vessel) then
        return false, "Make room in your inventory for the bulk source and drinking vessel."
    end
    local fluid, target = source.description.fluid, Fluids.container(vessel.item)
    if not fluid or fluid == target then return false, "The bulk source is no longer available." end
    if not FluidContainer.CanTransfer(fluid, target)
            and not (source.description.needsOpening and source.description.openingRecipe) then
        return false, "No clean empty drinking vessel can receive this liquid."
    end
    return true
end

function Supplies.scan(player, includeNearby, useNearbyTools)
    if useNearbyTools == nil then useNearbyTools = includeNearby end
    local result = {food = {}, water = {}, literature = {}, pain = {}, vessels = {}, waterSources = {},
        cooldownLiterature = 0, nearbyCooldownLiterature = 0, worldFluidSourceCount = 0}
    local worldSources = includeNearby and WaterSources.scan(player) or {}
    result.waterSources.reason = worldSources.reason
    result.fluidReason = worldSources.reason
    local bulk, worldFluids = {}, {}
    for _, source in ipairs(worldSources) do
        if source.description.fluid then worldFluids[source.description.fluid] = true end
        if source.directDrink then
            result.waterSources[#result.waterSources + 1] = source
            result.worldFluidSourceCount = result.worldFluidSourceCount + 1
        else
            bulk[#bulk + 1] = {worldSource = source, item = source.item, owned = false, description = source.description}
        end
    end
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
                if PainCare.eligible(item) then
                    if owned or Storage.permitted(player, world and world:getSquare() or sourceSquare(container)) then
                        result.pain[#result.pain + 1] = entry
                    else
                        -- Seen, but not to be taken from here: said, never silently dropped.
                        result.painBlocked = (result.painBlocked or 0) + 1
                    end
                else
                    local consumable = Consumables.inspect(player, item, useNearbyTools)
                    entry.description = consumable
                    if Fluids.emptyVessel(item) and (owned or useNearbyTools) then result.vessels[#result.vessels + 1] = entry end
                    if consumable.needsVessel then
                        if not worldFluids[consumable.fluid] then bulk[#bulk + 1] = entry end
                    else
                        if consumable.food then result.food[#result.food + 1] = entry end
                        if consumable.water then result.water[#result.water + 1] = entry end
                    end
                    if Fluids.container(item) and consumable.reason and not consumable.needsVessel and not consumable.unsafeFluid then
                        result.fluidReason = result.fluidReason or consumable.reason
                    end
                    if consumable.needsOpening and consumable.reason and instanceof(item, "Food") then
                        result.openingReason = consumable.reason
                    end
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
                if owned or floor or Storage.containerReachable(player, container, reachable(player, containerSquare(container))) then
                    visit(container, owned, owned, floor)
                end
            end
        end
    end
    for _, source in ipairs(bulk) do
        local usable, reason
        for _, vessel in ipairs(result.vessels) do
            usable, reason = transferCompatible(player, source, vessel)
            if usable then break end
        end
        if usable then
            if source.description.food then result.food[#result.food + 1] = source end
            if source.description.water then result.water[#result.water + 1] = source end
            if source.worldSource and source.description.water then result.worldFluidSourceCount = result.worldFluidSourceCount + 1 end
        else
            reason = reason or "A clean empty drinking vessel is needed for bulk liquids."
            if source.description.water then result.waterReason = result.waterReason or reason end
            if source.description.food then result.foodReason = result.foodReason or reason end
        end
    end
    -- A reason is only shown for the need that supply would have met.
    result.waterReason = result.waterReason or result.fluidReason
    result.fluidReason = result.waterReason
    return result
end

-- Find an exact already-carried or native-accessible adjacent care item.
-- Do not request unloaded remote loot or rummage in other people's storage.
function Supplies.findCareItem(player, eligible, includeNearby)
    local main, visited, seenCount = player:getInventory(), {}, 0
    local function visit(container, depth, floor)
        if not container or visited[container] or depth > 8 then return nil end
        visited[container] = true
        local items = container:getItems()
        for i=0,items:size()-1 do
            if seenCount >= 2048 then return nil end
            seenCount = seenCount+1
            local item=items:get(i)
            if item and item:getContainer()==container then
                local world=floor and item:getWorldItem()
                local legal=not floor or (world and reachable(player,world:getSquare())
                    and Storage.permitted(player,world:getSquare()))
                if legal and not Grid.favorite(item) and eligible(item)
                        and (container==main or main:hasRoomFor(player,item)) then return item end
            end
        end
        if depth < 8 then
            for i=0,items:size()-1 do
                if seenCount >= 2048 then return nil end
                local item=items:get(i)
                if item and item:getContainer()==container and instanceof(item, "InventoryContainer") then
                    local nested=visit(item:getInventory(),depth+1,false)
                    if nested then return nested end
                end
            end
        end
    end
    local item=visit(main,0,false)
    if item or not includeNearby then return item end
    local nearby=containers(player)
    if not nearby then return nil end
    for i=0,nearby:size()-1 do
        local container=nearby:get(i)
        if container and not visited[container] then
            local floor=container:getType()=="floor"
            local square=containerSquare(container)
            if floor or (Storage.permitted(player,square)
                    and Storage.containerReachable(player,container,reachable(player,square))) then
                item=visit(container,8,floor)
                if item then return item end
            end
        end
    end
end

local rejectedItem=Needs.supplyRejected

local intakeKey={}
local function stockStamp(item)
    local fluid=Fluids.container(item)
    local effects=fluid and fluid:getProperties()
    return table.concat({item:getFullType(), tostring(item:isSealed()),
        tostring(fluid and fluid:getAmount()), tostring(fluid and fluid.getPrimaryFluid and fluid:getPrimaryFluid()),
        tostring(fluid and fluid:isTainted()), tostring(fluid and fluid:canPlayerEmpty()),
        tostring(effects and effects:getThirstChange()), tostring(effects and effects:getHungerChange()),
        tostring(instanceof(item,"Food") and item:getHungerChange()),
        tostring(instanceof(item,"Food") and item:getThirstChange())}, "|")
end

function Supplies.scoutIntakeDetails(item)
    local fluid=Fluids.container(item)
    local primary=fluid and fluid.getPrimaryFluid and fluid:getPrimaryFluid()
    local holder=item:getContainer()
    return "item="..tostring(item:getID()).." type="..tostring(item:getFullType())
        .." itemHolder="..tostring(holder and holder:getType() or "ground-or-unassigned")
        .." sealed="..tostring(item:isSealed()).." fluid="..tostring(primary or "n/a")
        .." liters="..tostring(fluid and fluid:getAmount() or "n/a")
        .." capacity="..tostring(fluid and fluid:getCapacity() or "n/a")
        .." tainted="..tostring(fluid and fluid:isTainted() or false)
end

-- This is evidence about an item on one need, not a blacklist of its crate or
-- a permanent ban: a late server receipt looks exactly like an item that did
-- nothing. Changed contents clear it at once; otherwise the wait doubles, and
-- starts longer for an item that also costs a walk.
function Supplies.rejectScoutIntake(rejected,item,kind,carried)
    rejected[intakeKey]=rejected[intakeKey] or {}
    local id=item:getID()
    local byItem=rejected[intakeKey]
    local entry=byItem[id]
    if not entry or entry.stamp~=stockStamp(item) then
        entry={stamp=stockStamp(item)}
        byItem[id]=entry
    end
    local record=entry[kind] or {count=0}
    record.count=record.count+1
    record.nextAt=getTimestampMs()+math.min(1800000,(carried and 60000 or 600000)*2^(record.count-1))
    entry[kind]=record
end

local function rejectedIntake(rejected,item,kind)
    if not item then return false end
    local evidence=rejected[intakeKey]
    local id=item:getID()
    local entry=evidence and evidence[id]
    if not entry then return false end
    if entry.stamp~=stockStamp(item) then
        evidence[id]=nil
        return false
    end
    return entry[kind]~=nil and getTimestampMs()<entry[kind].nextAt
end

local function preparationCost(player, entry)
    if entry.source then return 1 + (player:isSitOnGround() and 1 or 0) end
    local source = entry.transfer and entry.transfer.source or entry
    local description, inventory = source.description, player:getInventory()
    local cost = (entry.transfer and 2 or 1) + (description.needsOpening and 1 or 0)
    if not source.worldSource and source.item:getContainer() ~= inventory then cost = cost + 2 end
    if entry.transfer and entry.transfer.vessel.item:getContainer() ~= inventory then cost = cost + 2 end
    for _, tool in ipairs(description.returnItems or {}) do
        if tool:getContainer() ~= inventory then cost = cost + 2 end
    end
    return cost
end

local function rejectedSource(rejected, entry)
    return (entry.item and rejectedItem(rejected, entry.item:getID()))
        or (entry.worldSource and rejectedItem(rejected, entry.worldSource.object))
end

function Supplies.transferPlan(player, source, vessel, kind)
    local description, world
    if source.worldSource then
        local reason
        world, reason = WaterSources.inspect(player, source.worldSource.object, source.worldSource.part)
        if not world or world.directDrink then return nil, reason or "The bulk source is no longer available." end
        description = world.description
    else
        description = Consumables.inspect(player, source.item, source.useNearbyTools == true)
    end
    if not description.needsVessel or not description[kind] then return nil, description.reason or "This bulk source cannot restore that need." end
    local current = {worldSource = world, item = source.item, owned = source.owned, description = description,
        useNearbyTools = source.useNearbyTools}
    if world then current.item = world.item end
    local compatible, reason = transferCompatible(player, current, vessel)
    if not compatible then return nil, reason end
    local target = Fluids.container(vessel.item)
    local available = math.min(description.remainingLiters, target:getCapacity() - target:getAmount())
    local projected = Fluids.project(description, available)
    local plan = Consumables.plan(player, projected, kind)
    if not plan then return nil, "That need is already restored." end
    return {item = current.item, owned = current.owned, description = projected, plan = plan,
        transfer = {source = current, vessel = vessel, kind = kind, amount = available * plan.fraction}}
end

local function better(candidate, best, kind, critical)
    if not best then return true end
    local comparisons = {}
    if critical then comparisons[#comparisons + 1] = {candidate.plan.primary, best.plan.primary} end
    comparisons[#comparisons + 1] = {candidate.plan.utility, best.plan.utility}
    comparisons[#comparisons + 1] = {candidate.plan.secondary > 0 and 1 or 0, best.plan.secondary > 0 and 1 or 0}
    if kind == "water" then comparisons[#comparisons + 1] = {candidate.reserve, best.reserve} end
    comparisons[#comparisons + 1] = {-candidate.cost, -best.cost}
    -- Otherwise equal: do not make the survivor unhappier, then eat what will
    -- spoil first.
    if kind == "food" then
        comparisons[#comparisons + 1] = {-candidate.gloom, -best.gloom}
        comparisons[#comparisons + 1] = {-candidate.keeps, -best.keeps}
    end
    for _, comparison in ipairs(comparisons) do
        if math.abs(comparison[1] - comparison[2]) > 0.000001 then return comparison[1] > comparison[2] end
    end
    return candidate.item and best.item and candidate.item:getID() < best.item:getID() or false
end

-- Whether the kitchen may cook (read when needed: Options loads the game's settings).
local function kitchenCooks()
    local ok, options = pcall(require, "AutoMindful/Options")
    return ok and type(options) == "table" and type(options.cookMeals) == "function" and options.cookMeals() == true
end

local function consider(player, candidate, best, kind, critical)
    if not candidate.plan then
        candidate.plan = Consumables.plan(player, candidate.description, kind)
        -- The diet goal decides between foods that would do about as well.
        if candidate.plan and kind == "food" and candidate.item then
            candidate.plan.utility = Diet.adjust(player, candidate.plan.utility, candidate.item)
        end
    end
    if not candidate.plan then return best end
    -- Worse than nothing (dry pasta that only makes the survivor thirstier): left
    -- for the kitchen to cook, unless hunger is critical.
    local dry = kind == "food" and not candidate.transfer and candidate.item and instanceof(candidate.item, "Food")
        and candidate.item:getThirstChange() > 0
    -- Only when the kitchen may cook it instead; with cooking off it is still food.
    local cooks = dry and kitchenCooks()
    if dry and cooks and not critical and (candidate.plan.utility or 0) <= 0 then return best end
    local reserve = candidate.transfer and candidate.transfer.source.description or candidate.description
    candidate.reserve = reserve.remainingLiters or reserve.thirstRelief * 2
    candidate.cost = preparationCost(player, candidate)
    candidate.gloom, candidate.keeps = 0, 1000
    local food = candidate.item
    if kind == "food" and food and instanceof(food, "Food") then
        candidate.gloom = math.max(0, food.getUnhappyChange and food:getUnhappyChange() or 0)
        local limit, age = food.getOffAgeMax and food:getOffAgeMax(), food.getAge and food:getAge()
        if type(limit) == "number" and type(age) == "number" then candidate.keeps = math.max(0, math.min(1000, limit - age)) end
    end
    if better(candidate, best, kind, critical) then return candidate end
    return best
end

function Supplies.chooseTransfer(player, source, kind, includeNearby, rejected)
    if rejectedSource(rejected, source) then return nil, "This bulk source was temporarily rejected." end
    local container = source.item and source.item:getContainer()
    if not includeNearby and (source.worldSource or not container or container:getOutermostContainer() ~= player:getInventory()) then
        return nil, "Adjacent supplies must be enabled to use this bulk source."
    end
    local scan, best, reason = Supplies.scan(player, includeNearby)
    local critical = player:getMoodles():getMoodleLevel(kind == "water" and MoodleType.THIRST or MoodleType.HUNGRY) >= 4
    source.useNearbyTools = includeNearby == true
    for _, vessel in ipairs(scan.vessels) do
        if not rejectedItem(rejected, vessel.item:getID()) then
            local candidate, currentReason = Supplies.transferPlan(player, source, vessel, kind)
            if candidate then best = consider(player, candidate, best, kind, critical) end
            reason = reason or currentReason
        end
    end
    if best then return best end
    return nil, reason or scan.fluidReason or "A clean empty drinking vessel is needed for bulk liquids."
end

-- The radius report can show potential donors. Admission must instead prove
-- a usable current portion. For a bulk donor the vessel must travel with us
-- or already be positively visible in the same holder (or same ground tile).
-- No loot refresh, load request, remote transfer, or inferred empty vessel.
function Supplies.scoutProbe(player,kind,rejected)
    local inventory=player:getInventory()
    local carried,byHolder=nil,{}
    local function vessels(holder,owned,ground)
        local results,visited,left={},{},256
        local function visit(container,depth)
            if visited[container] or left<=0 then return end
            visited[container]=true
            local items=container:getItems()
            for i=0,math.min(items:size(),left)-1 do
                if left<=0 then break end
                left=left-1
                local item=items:get(i)
                if item and item:getContainer()==container then
                    if not rejectedItem(rejected,item:getID()) and Fluids.emptyVessel(item) then
                        results[#results+1]={item=item,owned=owned}
                    elseif owned and depth<8 and instanceof(item,"InventoryContainer") then
                        visit(item:getInventory(),depth+1)
                    end
                end
            end
        end
        if ground then
            local objects=holder:getWorldObjects()
            for i=0,math.min(objects:size(),128)-1 do
                local object=objects:get(i)
                local item=object and object:getItem()
                if item and item:getWorldItem()==object and object:getSquare()==holder
                        and not rejectedItem(rejected,item:getID()) and Fluids.emptyVessel(item) then
                    results[#results+1]={item=item,owned=false}
                end
            end
        else visit(holder,0) end
        return results
    end
    return function(entry)
        local item,holder=entry.item,entry.container
        if not item or rejectedItem(rejected,item:getID()) or rejectedIntake(rejected,item,kind) then return false end
        if holder then
            if item:getContainer()~=holder or not holder:contains(item) then return false end
        else
            local world=item:getWorldItem()
            if not world or not entry.square or world:getSquare()~=entry.square or world:getItem()~=item then return false end
        end
        local source={item=item,owned=false}
        if not canCollect(player,source) then return false end
        if kind=="literature" then return Supplies.eligibleLiterature(player,item) end
        if kind=="pain" then return PainCare.eligible(item) end
        local d=Consumables.inspect(player,item,false,holder)
        if not d[kind] then return false end
        if not d.needsVessel then return Consumables.plan(player,d,kind)~=nil end
        source.description=d
        local function viable(list)
            for _,v in ipairs(list) do
                if transferCompatible(player,source,v) then
                    local fc=Fluids.container(v.item)
                    local available=math.min(d.remainingLiters,fc:getCapacity()-fc:getAmount())
                    if available>0 and Consumables.plan(player,Fluids.project(d,available),kind) then return true end
                end
            end
        end
        carried=carried or vessels(inventory,true,false)
        if viable(carried) then return true end
        local key=holder or entry.square
        if not byHolder[key] then byHolder[key]=vessels(key,false,holder==nil) end
        return viable(byHolder[key])==true
    end
end

-- Read only already-replicated stock of this recalled stop. MP's empty list
-- is never proof of emptiness; observing positive contents needs no request.
function Supplies.scoutedStock(player,kind,container,rejected)
    local items=container:getItems()
    local size=items:size()
    if size==0 then return false,container:isExplored() and not isClient() end
    local probe=Supplies.scoutProbe(player,kind,rejected)
    for i=0,math.min(size,128)-1 do
        if probe({item=items:get(i),container=container}) then return true end
    end
    return false
end

-- explain, when given, receives one line per candidate: its score or the
-- reason it was not eligible. It never changes the choice.
function Supplies.choose(player, kind, includeNearby, rejected, worldOnly, exactContainer, explain)
    if exactContainer and (not includeNearby or worldOnly) then return nil end
    local scan = Supplies.scan(player, includeNearby)
    local function note(entry, why, candidate)
        if not explain or #explain >= 8 then return end
        local plan = candidate and candidate.plan
        explain[#explain + 1] = (entry.item and (tostring(entry.item:getFullType()) .. "#" .. tostring(entry.item:getID())) or "fixture")
            .. (entry.owned and " owned" or " nearby") .. " "
            .. (why or plan and string.format("utility=%.2f relief=%.2f cost=%d", plan.utility, plan.primary, candidate.cost or 0) or "eligible")
    end
    if explain and scan.fluidReason then explain[1] = "fluids: " .. scan.fluidReason end
    if explain and scan.openingReason then explain[#explain + 1] = "opening: " .. scan.openingReason end
    local function selected(entry)
        return not exactContainer or (not entry.worldSource and entry.item and entry.item:getContainer()==exactContainer)
    end
    local best
    if kind == "pain" then
        -- Only the painkillers' own story: the general notes above are about drinks and food.
        if explain then for index = #explain, 1, -1 do explain[index] = nil end end
        if explain and (scan.painBlocked or 0) > 0 then
            explain[#explain + 1] = scan.painBlocked .. " painkillers seen where taking them is not allowed (safehouse rules, or the place is unknown)"
        end
        local inspected = false
        for _, entry in ipairs(scan.pain) do
            local blocked = not selected(entry) and "not-in-the-inspected-container"
                or rejectedItem(rejected, entry.item:getID()) and "rejected-earlier"
                or not canCollect(player, entry) and "no-room-to-carry"
                or not PainCare.eligible(entry.item) and "not-plain-painkillers"
            inspected = inspected or selected(entry)
            if blocked then
                note(entry, blocked)
            else
                note(entry, "eligible")
                if entry.owned then return entry end
                best = best or entry
            end
        end
        if explain and exactContainer and not inspected then
            explain[#explain + 1] = "no painkillers visible in the inspected container from here (not in the loot list, not reachable, or not permitted)"
        end
        return best
    end
    if kind == "literature" then
        for _, entry in ipairs(scan.literature) do
            if selected(entry) and not rejectedItem(rejected, entry.item:getID()) and canCollect(player, entry)
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
    if not worldOnly then
        for _, entry in ipairs(scan[kind]) do
            local blocked = not selected(entry) and "not-in-the-inspected-container"
                or rejectedSource(rejected, entry) and "rejected-earlier" or rejectedIntake(rejected,entry.item,kind) and "no-relief-last-time"
                or not canCollect(player, entry) and "no-room-to-carry"
            if blocked then note(entry, blocked)
            elseif entry.description.needsVessel then
                entry.useNearbyTools = includeNearby == true
                for _, vessel in ipairs(scan.vessels) do
                    if not rejectedItem(rejected, vessel.item:getID()) then
                        local candidate, reason = Supplies.transferPlan(player, entry, vessel, kind)
                        if candidate then best = consider(player, candidate, best, kind, critical) end
                        note(entry, not candidate and reason or nil, candidate)
                    end
                end
            else
                best = consider(player, entry, best, kind, critical)
                note(entry, not entry.plan and "cannot-take-a-useful-portion" or nil, entry)
            end
        end
    end
    if kind == "water" and not exactContainer then
        for _, source in ipairs(scan.waterSources) do
            if not rejectedItem(rejected, source.object) and not (source.item and rejectedItem(rejected, source.item:getID())) then
                local candidate = {source = source, description = source.description}
                best = consider(player, candidate, best, kind, critical)
                note(candidate, nil, candidate)
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

local function guardStorageAction(player, action, container)
    if not (Storage.partFor(container) or Storage.corpseFor(container)) then return true end
    local function accessible()
        return Storage.containerReachable(player, container, reachable(player, containerSquare(container)))
    end
    if not accessible() then return false end
    local nativeValid = action.isValid
    action.isValid = function(self)
        return accessible() and (not nativeValid or nativeValid(self))
    end
    return true
end

function Supplies.careLoanAllowed(player, loan, worldAllowed)
    if not loan then return true end
    local origin = loan.origin
    if not origin then return false end
    if not loan.floor and origin:getOutermostContainer() == player:getInventory() then return true end
    if not worldAllowed then return false end
    if loan.floor then
        local square = loan.floor.square
        return reachable(player, square) and Storage.permitted(player, square)
    end
    local nearby = containers(player)
    if not nearby or not nearby:contains(origin) then return false end
    local part = Storage.partFor(origin)
    if part then return Storage.vehicleAccessible(player, part) end
    local square = containerSquare(origin)
    return Storage.permitted(player, square) and Storage.containerReachable(player, origin, reachable(player, square))
end

Supplies.painLoanAllowed = Supplies.careLoanAllowed

local function guardCareLoanAction(action, accessible)
    if not accessible() then return false end
    local nativeValid = action.isValid
    action.isValid = function(self)
        return accessible() and (not nativeValid or nativeValid(self))
    end
    return true
end

local function refuseMerge() return false end
local function onExactTransferComplete() end

local function exactTransfer(player, item, source, target)
    local action = ISInventoryTransferUtil.newInventoryTransferAction(player, item, source, target)
    if action.canMergeAction then
        -- Stock's merged head replaces self.item. An exact loan guard and
        -- ownership receipt belong to one item, not a batch of same-shelf moves.
        action.canMergeAction = refuseMerge
        -- Stock also rejects merging an incoming action with an onComplete.
        -- This protects our action if some other work becomes the native head.
        if action.setOnComplete and not action.onCompleteFunc then
            action:setOnComplete(onExactTransferComplete)
        end
    end
    return action
end

function Supplies.transfer(player, item, careLoan)
    local source = item:getContainer()
    if source == player:getInventory() then return true end
    if not player:getInventory():hasRoomFor(player, item) then return false end
    local action = exactTransfer(player, item, source, player:getInventory())
    if action.ignoreAction then return false end
    if careLoan then
        if not guardCareLoanAction(action, function()
            if item ~= careLoan.original or item:getContainer() ~= careLoan.origin then return false end
            if careLoan.floor then
                local world = item:getWorldItem()
                if not world or world:getSquare() ~= careLoan.floor.square then return false end
            end
            return Supplies.careLoanAllowed(player, careLoan, true)
        end) then return false end
    elseif not guardStorageAction(player, action, source) then return false end
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

local function expectsReplacement(types)
    for _ in pairs(types) do return true end
    return false
end

function Supplies.finishLoan(player, loan, now)
    if not loan or not loan.usedItem then return true end
    if not Supplies.inventoryItem(player, loan.usedItem) and not loan.interference then
        local replacements = Supplies.newOutputs(player, loan.before, loan.expected)
        if #replacements == 1 then loan.items[#loan.items + 1] = replacements[1]
        elseif #replacements > 1 then loan.notice = "An empty container could not be identified safely; it stays in your inventory."
        elseif now and expectsReplacement(loan.expected) then
            loan.awaitResultUntil = loan.awaitResultUntil or now + 3000
            if now < loan.awaitResultUntil then return false end
            loan.notice = "The game did not confirm an empty container; any delayed result stays in your inventory."
        end
    end
    loan.usedItem, loan.awaitResultUntil = nil, nil
    return true
end

local favoriteReturnNotice = "Borrowed supplies marked as favorites stay in your inventory. Unfavorite them to allow their return."

local favorite = Grid.favorite

local function protectFavoriteReturn(action, item)
    local nativeValid = action.isValid
    action.isValid = function(self, ...)
        return not favorite(self.item or item) and nativeValid(self, ...)
    end
end

function Supplies.returnAction(player, loan)
    local inventory = player:getInventory()
    local origin = loan.origin
    local item, protected
    for _, candidate in ipairs(loan.items) do
        local current = Supplies.inventoryItem(player, candidate)
        if current and current:getContainer() ~= origin then
            if favorite(current) then protected = true
            else item = current; break end
        end
    end
    if not item then
        -- Native container returns silently do nothing for a favorite, and
        -- native exact placement can drop it. Don't queue either kind; leave
        -- this loan pending without blocking other loans or training.
        if protected then return nil, favoriteReturnNotice end
        return nil, nil, true
    end
    local function painReturnAllowed()
        -- Returning a borrowed bottle does not require permission to take a new dose.
        return Supplies.painLoanAllowed(player, loan, true)
    end
    if loan.pain and not painReturnAllowed() then
        return nil, "Borrowed supplies stay with you because their original source cannot currently be accessed."
    end
    if loan.floor then
        if not reachable(player, loan.floor.square) then
            return nil, "Borrowed supplies stay with you because their original floor square is out of reach."
        end
        local floor = loan.floor
        local action = ISDropWorldItemAction:new(player, item, floor.square, floor.x, floor.y, floor.z, 0, false)
        action.isPlaceItem = true
        if loan.pain and not guardCareLoanAction(action, painReturnAllowed) then
            return nil, "Borrowed supplies stay with you because their original floor square cannot be accessed."
        end
        protectFavoriteReturn(action, item)
        if not action:isValid() then return nil, "Borrowed supplies stay with you because the original floor square cannot accept them." end
        return action
    end
    local owned = origin:getOutermostContainer() == inventory
    if not owned then
        local nearby = containers(player)
        if not nearby or not nearby:contains(origin) or not Storage.containerReachable(player, origin, reachable(player, containerSquare(origin))) then
            return nil, "Borrowed supplies stay with you because their original container is no longer reachable."
        end
    end
    if not origin:hasRoomFor(player, item) then
        return nil, "Borrowed supplies stay with you because their original container is full."
    end
    local action = exactTransfer(player, item, item:getContainer(), origin)
    local guarded = not action.ignoreAction and ((loan.pain and guardCareLoanAction(action, painReturnAllowed))
        or (not loan.pain and guardStorageAction(player, action, origin)))
    if guarded then protectFavoriteReturn(action, item) end
    if not guarded or not action:isValid() then
        return nil, "Borrowed supplies stay with you because the original container cannot currently accept them."
    end
    return action
end

function Supplies.report(player, includeNearby, collectNearby, area, collectArea)
    if collectNearby == nil then collectNearby = includeNearby end
    local scan = Supplies.scan(player, includeNearby, collectNearby)
    local adjacent = {food=0, water=0, literature=0, pain=0}
    local adjacentWater = {}
    for _, kind in ipairs({"food", "water", "literature", "pain"}) do
        for _, entry in ipairs(scan[kind]) do
            if not entry.owned then adjacent[kind] = adjacent[kind] + 1 end
            if kind == "water" and entry.item then adjacentWater[entry.item] = true end
        end
    end
    for _, source in ipairs(scan.waterSources) do
        if not source.item or not adjacentWater[source.item] then adjacent.water = adjacent.water + 1 end
    end
    if area then
        for _, kind in ipairs({"food", "water", "literature", "pain"}) do
            local entries = {}
            for _, entry in ipairs(scan[kind]) do if entry.owned then entries[#entries + 1] = entry end end
            for _, entry in ipairs(area[kind] or {}) do entries[#entries + 1] = entry end
            scan[kind] = entries
        end
        scan.waterSources = area.waterSources
        scan.worldFluidSourceCount = #area.waterSources
        scan.nearbyCooldownLiterature = area.cooldownLiterature or 0
    end
    local report = {food = 0, water = 0, literature = 0, nearbyFood = 0, nearbyWater = 0,
        nearbyLiterature = 0, pain = 0, nearbyPain = 0, adjacentPain = adjacent.pain,
        unreadLiterature = 0, rereadLiterature = 0,
        nearbyUnreadLiterature = 0, nearbyRereadLiterature = 0, warnings = {}}
    if area then
        report.radius, report.containerCount = area.radius, area.containerCount
        report.unknownContainers, report.unloadedSquares = #area.unknownTargets, area.unloadedSquares
        if (area.potentialBulk or 0) > 0 then
            report.warnings[#report.warnings + 1] = tostring(area.potentialBulk)
                .. " known bulk liquid source(s) need a compatible empty vessel. Counts are potential supplies; care rechecks prerequisites at the source."
        end
        if report.unknownContainers > 0 then
            report.warnings[#report.warnings + 1] = tostring(report.unknownContainers)
                .. " container(s) have uninspected or unconfirmed contents. Counts show known supplies, not a guarantee of access."
        end
        if report.unloadedSquares > 0 then
            report.warnings[#report.warnings + 1] = "Part of the search area is not loaded; those supplies are unknown."
        end
    end
    report.cooldownLiterature, report.nearbyCooldownLiterature = scan.cooldownLiterature, scan.nearbyCooldownLiterature
    report.openingReason = scan.openingReason
    report.fluidReason = scan.fluidReason
    report.foodReason = scan.foodReason or scan.openingReason
    report.nearbyWaterSourceCount = scan.worldFluidSourceCount
    report.waterSourceReason = scan.waterSources.reason
    local nearbyKeys = {food = "nearbyFood", water = "nearbyWater", literature = "nearbyLiterature", pain = "nearbyPain"}
    for _, kind in ipairs({"food", "water", "literature", "pain"}) do
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
    for _, entry in ipairs(scan.water) do if entry.item then portableWater[entry.item] = true end end
    for _, source in ipairs(scan.waterSources) do
        if not source.item or not portableWater[source.item] then report.nearbyWater = report.nearbyWater + 1 end
    end
    local allowed = area and not collectArea and adjacent
        or {food=report.nearbyFood, water=report.nearbyWater, literature=report.nearbyLiterature}
    local usableFood = report.food + (collectNearby and allowed.food or 0)
    local usableWater = report.water + (collectNearby and allowed.water or 0)
    local usableLiterature = report.literature + (collectNearby and allowed.literature or 0)
    if area and not collectArea then
        report.warnings[#report.warnings + 1] = "Care trips are off. Distant known stock is shown but will not be used."
    end
    if includeNearby and not collectNearby then report.warnings[#report.warnings + 1] = "Nearby stock is visible, but collection is off. Enable it or move supplies into your inventory." end
    local foodWarning
    if usableFood == 0 then
        foodWarning = report.foodReason or "Bring safe food or a nourishing drink. Opening tools must be available for sealed food."
        report.warnings[#report.warnings + 1] = foodWarning
    end
    if usableWater == 0 then
        local waterWarning = scan.fluidReason or report.waterSourceReason or "Bring safe water or another safe hydrating drink, or enable a reachable clean-water source."
        if waterWarning ~= foodWarning then report.warnings[#report.warnings + 1] = waterWarning end
    end
    if usableLiterature == 0 then
        report.warnings[#report.warnings + 1] = scan.cooldownLiterature + scan.nearbyCooldownLiterature > 0
            and "Available literature was read too recently. The native reread cooldown must expire; unread literature or yoga can help now."
            or "Bring boredom-reducing literature that is unread or past the game's reread cooldown. Yoga can also help."
    end
    if player:tooDarkToRead() then report.warnings[#report.warnings + 1] = "It is too dark to read here. Use a lit training spot." end
    local lines = {string.format("In your inventory: %d food, %d hydrating drinks, %d useful literature.", report.food, report.water, report.literature)}
    if includeNearby then
        local scope = area and ("Known within " .. tostring(area.radius) .. " tiles") or "Within adjacent loot range"
        lines[#lines + 1] = string.format("%s: %d food, %d drinks, %d literature.", scope, report.nearbyFood, report.nearbyWater, report.nearbyLiterature)
        lines[#lines + 1] = "Borrowed supplies and their empty containers are returned to their original reachable source."
    end
    for _, warning in ipairs(report.warnings) do lines[#lines + 1] = warning end
    lines[#lines + 1] = "Unread literature is used first, then eligible rereads from oldest to newest. Native cooldowns still apply."
    report.message = table.concat(lines, "\n")
    return report
end

return Supplies
