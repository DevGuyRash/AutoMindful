local Controller = require "AutoMindful/Controller"

local function fluid(item)
    local world = item:getWorldItem()
    return (world and world:getFluidContainer()) or item:getFluidContainer()
end

local function provision(item)
    local container = fluid(item)
    return instanceof(item, "Food") or (container and not container:isEmpty())
end

local function clearProvisions(player)
    local inventory = player:getInventory()
    for i=inventory:getItems():size()-1,0,-1 do
        local item = inventory:getItems():get(i)
        if provision(item) then
            player:removeWornItem(item)
            inventory:Remove(item)
        end
    end
    local square = player:getSquare()
    for i=square:getWorldObjects():size()-1,0,-1 do
        local world = square:getWorldObjects():get(i)
        if instanceof(world, "IsoWorldInventoryObject") and provision(world:getItem()) then
            world:removeFromWorld()
            world:removeFromSquare()
        end
    end
end

local function clearLiterature(player)
    local inventory = player:getInventory()
    for i=inventory:getItems():size()-1,0,-1 do
        local item = inventory:getItems():get(i)
        if instanceof(item, "Literature") then inventory:Remove(item) end
    end
    local square = player:getSquare()
    for i=square:getWorldObjects():size()-1,0,-1 do
        local world = square:getWorldObjects():get(i)
        if instanceof(world, "IsoWorldInventoryObject") and instanceof(world:getItem(), "Literature") then
            world:removeFromWorld()
            world:removeFromSquare()
        end
    end
end

local function progressSnapshot(player)
    local window = AutoMindful.UI.windows[0]
    local status = Controller.status(player)
    for _, name in ipairs({"meditation", "yoga"}) do
        local sample = status.progress[name]
        if sample then
            print("[AutoMindfulFixture] XP skill=" .. name .. " level=" .. sample.level
                .. " current=" .. sample.current .. " required=" .. sample.required
                .. " fraction=" .. sample.fraction .. " total=" .. tostring(sample.total))
        end
    end
    if window then
        print("[AutoMindfulFixture] GEOMETRY x=" .. window:getX() .. " y=" .. window:getY()
            .. " width=" .. window.width .. " height=" .. window.height
            .. " bodyHeight=" .. window.body.height .. " bodyScrollHeight=" .. window.body:getScrollHeight()
            .. " activityHeight=" .. window.activity.height .. " activityScrollHeight=" .. window.activity:getScrollHeight()
            .. " activityVScroll=" .. tostring(window.activity.vscroll) .. " visible=" .. tostring(window:getIsVisible()))
    end
    for _, kind in ipairs({"food", "water"}) do
        local choice = AutoMindful.Supplies.choose(player, kind, true, {})
        print("[AutoMindfulFixture] CHOICE kind=" .. kind
            .. " item=" .. tostring(choice and choice.item and choice.item:getFullType())
            .. " world=" .. tostring(choice and choice.source ~= nil)
            .. " reserve=" .. tostring(choice and choice.reserve)
            .. " utility=" .. tostring(choice and choice.plan.utility)
            .. " fraction=" .. tostring(choice and choice.plan.fraction))
    end
end

local function stockSnapshot(player)
    local counts = {inventoryBooks=0, floorBooks=0, inventoryFood=0, floorFood=0,
        inventoryTools=0, floorTools=0, inventoryEmptyCans=0, floorEmptyCans=0}
    local function count(item, prefix)
        if instanceof(item, "Literature") then counts[prefix .. "Books"] = counts[prefix .. "Books"] + 1 end
        if instanceof(item, "Food") then counts[prefix .. "Food"] = counts[prefix .. "Food"] + 1 end
        if item:getFullType() == "Base.TinOpener" then counts[prefix .. "Tools"] = counts[prefix .. "Tools"] + 1 end
        if item:getFullType() == "Base.TinCanEmpty" then counts[prefix .. "EmptyCans"] = counts[prefix .. "EmptyCans"] + 1 end
        if instanceof(item, "Food") or item:getFullType() == "Base.TinOpener" or item:getFullType() == "Base.TinCanEmpty" then
            local source = item:getContainer()
            local parent = source and source:getContainingItem()
            print("[AutoMindfulFixture] LOCATION type=" .. item:getFullType() .. " itemID=" .. item:getID()
                .. " containingItemID=" .. tostring(parent and parent:getID()) .. " location=" .. prefix)
        end
        local container = fluid(item)
        if container and not container:isEmpty() then
            print("[AutoMindfulFixture] FLUID " .. prefix .. " type=" .. item:getFullType()
                .. " amount=" .. container:getAmount() .. " worn=" .. tostring(player:isEquipped(item)))
        end
        if instanceof(item, "Food") and item:getHungerChange() < 0 then
            counts[prefix .. "HungerRemaining"] = (counts[prefix .. "HungerRemaining"] or 0) - item:getHungerChange()
        end
        if instanceof(item, "InventoryContainer") then
            local contents = item:getInventory():getItems()
            for i=0,contents:size()-1 do count(contents:get(i), prefix) end
        end
    end
    for i=0,player:getInventory():getItems():size()-1 do count(player:getInventory():getItems():get(i), "inventory") end
    for i=0,player:getSquare():getWorldObjects():size()-1 do
        local world = player:getSquare():getWorldObjects():get(i)
        if instanceof(world, "IsoWorldInventoryObject") then count(world:getItem(), "floor") end
    end
    local window = AutoMindful.UI.windows[0]
    local status = Controller.status(player)
    if window then
        local shown = window.report or {}
        print("[AutoMindfulFixture] WINDOW food=" .. tostring(shown.food) .. " nearbyFood=" .. tostring(shown.nearbyFood)
            .. " water=" .. tostring(shown.water) .. " nearbyWater=" .. tostring(shown.nearbyWater)
            .. " dueInMs=" .. tostring((window.nextRefresh or 0) - getTimestampMs())
            .. " visible=" .. tostring(window:getIsVisible()) .. " collection=" .. tostring(window.nearby:isSelected(1)))
    end
    local report = Controller.prepare(player, window and window.nearby:isSelected(1) or status.collectNearby, true)
    print("[AutoMindfulFixture] SNAPSHOT phase=" .. status.phase .. " active=" .. tostring(status.active)
        .. " visible=" .. tostring(window and window:isVisible()) .. " pendingReturns=" .. tostring(status.pendingReturns)
        .. " hunger=" .. player:getStats():get(CharacterStat.HUNGER) .. " thirst=" .. player:getStats():get(CharacterStat.THIRST)
        .. " food=" .. report.food .. " nearbyFood=" .. report.nearbyFood .. " water=" .. report.water .. " nearbyWater=" .. report.nearbyWater
        .. " literature=" .. report.literature .. " nearbyLiterature=" .. report.nearbyLiterature
        .. " worldWater=" .. tostring(report.nearbyWaterSourceCount) .. " returnNotice=" .. tostring(status.returnNotice)
        .. " position=" .. player:getX() .. "," .. player:getY())
    for key,value in pairs(counts) do print("[AutoMindfulFixture] STOCK " .. key .. "=" .. value) end
end

Events.OnMainMenuEnter.Add(function()
    if AutoMindfulFixtureLaunched then return end
    AutoMindfulFixtureLaunched = true
    require "DebugUIs/DebugScenarios"
    MainScreen.instance:setDefaultSandboxVars()
    getWorld():setGameMode(GameMode.SANDBOX)
    SandboxVars.Zombies = 6
    SandboxVars.ZombieConfig.PopulationMultiplier = 0
    SandboxVars.ZombieConfig.PopulationStartMultiplier = 0
    SandboxVars.ZombieConfig.RespawnHours = 0
    SandboxVars.MultiplierConfig.Meditation = 1000
    SandboxVars.Yoga.YogaXPMultiplier = 5
    local start = {x=11778, y=6749, z=0}
    local location = getFileReader("automindful-fixture-location.txt", false)
    if location then
        local line = location:readLine()
        location:close()
        if line then
            local x,y,z = line:match("^(%d+),(%d+),(%d+)$")
            if x then start = {x=tonumber(x),y=tonumber(y),z=tonumber(z)} end
        end
    end
    local scenario = {name = "AutoMindful isolated verification", startLoc = start,
        onStart = function()
            local player = getSpecificPlayer(0)
            getCore():setOptionPauseOnFocusloss(false)
            local square = player:getSquare()
            for i=1,10 do square:AddWorldInventoryItem("Base.Crisps", 0.4, 0.4, 0) end
            for i=1,20 do square:AddWorldInventoryItem("Base.Book", 0.4, 0.4, 0) end
            for i=1,5 do
                local bottle = square:AddWorldInventoryItem("Base.WaterBottle", 0.4, 0.4, 0)
                local world = bottle and bottle:getWorldItem()
                local fluid = (world and world:getFluidContainer()) or (bottle and bottle:getFluidContainer())
                if fluid then
                    fluid:Empty()
                    fluid:addFluid(Fluid.Water, 1)
                end
            end
            player:getStats():set(CharacterStat.BOREDOM, 40)
            player:getStats():set(CharacterStat.HUNGER, 0.25)
            player:getStats():set(CharacterStat.THIRST, 0.25)
            print("[AutoMindfulFixture] SEEDED " .. tostring(getCore():getVersionNumber()))
        end}
    DebugScenarios.instance = DebugScenarios:new(0, 0, 100, 100)
    DebugScenarios.instance:launchScenario(scenario)
end)

local nextReport, lastPhase, lastLevels = 0, nil, nil
local lastWaterAction
Events.OnPlayerUpdate.Add(function(player)
    if player == getSpecificPlayer(0) then
        local queue = ISTimedActionQueue.getTimedActionQueue(player).queue
        for _,action in ipairs(queue) do
            if action.Type == "ISTakeWaterAction" and action ~= lastWaterAction then
                lastWaterAction = action
                local object = action.waterObject
                local sprite = object and object:getSprite()
                print("[AutoMindfulFixture] WATERACTION x=" .. object:getSquare():getX() .. " y=" .. object:getSquare():getY()
                    .. " sprite=" .. tostring(sprite and sprite:getName()))
            end
        end
    end
    if player ~= getSpecificPlayer(0) or getTimestampMs() < nextReport then return end
    nextReport = getTimestampMs() + 1000
    local status = Controller.status(player)
    local levelText = tostring(status.meditation) .. "/" .. tostring(status.yoga)
    if status.phase ~= lastPhase or levelText ~= lastLevels then
        lastPhase = status.phase
        lastLevels = levelText
        print("[AutoMindfulFixture] STATE " .. status.phase .. " meditation=" .. tostring(status.meditation)
            .. " yoga=" .. tostring(status.yoga) .. " " .. status.message)
    end
    local reader = getFileReader("automindful-fixture-command.txt", false)
    if reader then
        local line = reader:readLine()
        reader:close()
        if line and line ~= AutoMindfulFixtureLastCommand then
            AutoMindfulFixtureLastCommand = line
            local command = line:match("^(%S+)")
            if command == "boredom" then player:getStats():set(CharacterStat.BOREDOM, 40)
            elseif command == "hunger" then player:getStats():set(CharacterStat.HUNGER, 0.25)
            elseif command == "thirst" then player:getStats():set(CharacterStat.THIRST, 0.25)
            elseif command == "fatigue" then player:getStats():set(CharacterStat.FATIGUE, 0.65)
            elseif command == "fast" then getGameTime():setMultiplier(200)
            elseif command == "normal" then getGameTime():setMultiplier(1)
            elseif command == "stock" then stockSnapshot(player)
            elseif command == "diagnostic" then
                print("[AutoMindfulFixture] INPUT mouse=" .. getMouseX() .. "," .. getMouseY()
                    .. " screen=" .. getCore():getScreenWidth() .. "x" .. getCore():getScreenHeight()
                    .. " position=" .. player:getX() .. "," .. player:getY())
            elseif command == "open" then AutoMindful.UI.open(player)
            elseif command == "xpstate" then progressSnapshot(player)
            elseif command == "xpadd" then
                local amount = tonumber(line:match("^%S+%s+([%d%.%-]+)"))
                if amount then player:getXp():AddXPNoMultiplier(Perks.Meditation, amount) end
            elseif command == "calm" then
                player:getStats():set(CharacterStat.HUNGER, 0)
                player:getStats():set(CharacterStat.THIRST, 0)
                player:getStats():set(CharacterStat.BOREDOM, 0)
                player:getStats():set(CharacterStat.FATIGUE, 0)
                player:getStats():set(CharacterStat.ENDURANCE, 1)
                player:getStats():set(CharacterStat.PANIC, 0)
            elseif command == "medblock" then
                clearLiterature(player)
                player:getStats():set(CharacterStat.HUNGER, 0)
                player:getStats():set(CharacterStat.THIRST, 0)
                player:getStats():set(CharacterStat.BOREDOM, 40)
                player:getStats():set(CharacterStat.FATIGUE, 0)
                player:getStats():set(CharacterStat.ENDURANCE, 1)
                SandboxVars.Yoga.RequiresMat = false
            elseif command == "watermix" or command == "milkmix" then
                clearProvisions(player)
                local bucket = player:getSquare():AddWorldInventoryItem("Base.Bucket", 0.4, 0.4, 0)
                fluid(bucket):Empty()
                fluid(bucket):addFluid(Fluid.Water, 5)
                local bottle = player:getInventory():AddItem(command == "milkmix" and "Base.Milk" or "Base.WaterBottle")
                local contents = fluid(bottle)
                local milk = instanceItem("Base.Milk"):getFluidContainer():getPrimaryFluid()
                contents:Empty()
                contents:addFluid(command == "milkmix" and milk or Fluid.Water, command == "milkmix" and 1 or 0.5)
                player:getStats():set(CharacterStat.HUNGER, command == "milkmix" and 0.2 or 0)
                player:getStats():set(CharacterStat.THIRST, 0.2)
                player:getStats():set(CharacterStat.BOREDOM, 0)
                print("[AutoMindfulFixture] MIX bucket=" .. bucket:getID() .. " amount=" .. fluid(bucket):getAmount()
                    .. " owned=" .. bottle:getFullType() .. " amount=" .. contents:getAmount())
                progressSnapshot(player)
            elseif command == "waterlocate" then
                local seen = {}
                for x=player:getSquare():getX()-20,player:getSquare():getX()+20 do
                    for y=player:getSquare():getY()-20,player:getSquare():getY()+20 do
                        local square = getCell():getGridSquare(x,y,player:getSquare():getZ())
                        if square then
                            for i=0,square:getObjects():size()-1 do
                                local object = square:getObjects():get(i):getMasterObject()
                                if object and not seen[object] and object:hasWater() and object:getFluidAmount() > 0 then
                                    seen[object] = true
                                    print("[AutoMindfulFixture] WATERPOINT x=" .. object:getSquare():getX()
                                        .. " y=" .. object:getSquare():getY() .. " amount=" .. object:getFluidAmount()
                                        .. " tainted=" .. tostring(object:isTaintedWater())
                                        .. " sprite=" .. tostring(object:getSprite() and object:getSprite():getName()))
                                end
                            end
                        end
                    end
                end
            elseif command == "inspectcans" then
                local supplies = require "AutoMindful/Consumables"
                getPlayerLoot(0):refreshBackpacks()
                local containers = ISInventoryPaneContextMenu.getContainers(player)
                for i=0,containers:size()-1 do
                    local container = containers:get(i)
                    local parent = container:getContainingItem()
                    print("[AutoMindfulFixture] CONTAINER type=" .. container:getType() .. " grid=" .. tostring(container:getSourceGrid())
                        .. " containingItemID=" .. tostring(parent and parent:getID()))
                    for j=0,container:getItems():size()-1 do
                        local item = container:getItems():get(j)
                        if item:getFullType() == "Base.TinnedBeans" then
                            local descriptor = supplies.inspect(player, item, true)
                            local outputTypes = {}
                            for name in pairs(descriptor.outputTypes) do outputTypes[#outputTypes+1] = name end
                            print("[AutoMindfulFixture] CANPLAN food=" .. tostring(descriptor.food) .. " opening=" .. tostring(descriptor.needsOpening)
                                .. " reason=" .. tostring(descriptor.reason) .. " outputs=" .. table.concat(outputTypes, ","))
                        end
                    end
                end
            elseif command == "nostock" then
                clearProvisions(player)
                player:getStats():set(CharacterStat.HUNGER, 0.25)
                player:getStats():set(CharacterStat.THIRST, 0.25)
                player:getStats():set(CharacterStat.BOREDOM, 0)
                player:getNutrition():setCalories(0)
            elseif command == "cans" then
                clearProvisions(player)
                player:getSquare():AddWorldInventoryItem("Base.TinnedBeans", 0.2, 0.2, 0)
                player:getSquare():AddWorldInventoryItem("Base.TinOpener", 0.7, 0.7, 0)
                player:getStats():set(CharacterStat.HUNGER, 0.16)
                player:getStats():set(CharacterStat.THIRST, 0)
                player:getStats():set(CharacterStat.BOREDOM, 0)
                player:getNutrition():setCalories(0)
            elseif command == "wearable" then
                clearProvisions(player)
                local item = player:getInventory():AddItem("Base.CanteenCowboy")
                local milk = instanceItem("Base.Milk"):getFluidContainer():getPrimaryFluid()
                item:getFluidContainer():Empty()
                item:getFluidContainer():addFluid(milk, 0.9)
                player:getStats():set(CharacterStat.HUNGER, 0.25)
                player:getStats():set(CharacterStat.THIRST, 0.25)
                player:getStats():set(CharacterStat.BOREDOM, 0)
                player:getNutrition():setCalories(0)
            elseif command == "cansbags" then
                clearProvisions(player)
                local foodBag = player:getSquare():AddWorldInventoryItem("Base.Bag_Schoolbag", 0.2, 0.2, 0)
                local toolBag = player:getSquare():AddWorldInventoryItem("Base.Bag_Schoolbag", 0.7, 0.7, 0)
                foodBag:setName("Fixture food bag")
                toolBag:setName("Fixture opener bag")
                foodBag:getInventory():AddItem("Base.TinnedBeans")
                toolBag:getInventory():AddItem("Base.TinOpener")
                print("[AutoMindfulFixture] SOURCES foodBagID=" .. foodBag:getID() .. " openerBagID=" .. toolBag:getID())
                player:getStats():set(CharacterStat.HUNGER, 0.16)
                player:getStats():set(CharacterStat.THIRST, 0)
                player:getStats():set(CharacterStat.BOREDOM, 0)
                player:getNutrition():setCalories(0)
            elseif command == "groundwater" then
                clearProvisions(player)
                local item = player:getSquare():AddWorldInventoryItem("Base.Bucket", 0.4, 0.4, 0)
                local water = fluid(item)
                water:Empty()
                water:addFluid(Fluid.Water, 5)
                print("[AutoMindfulFixture] GROUNDBUCKET itemID=" .. item:getID() .. " amount=" .. water:getAmount())
                player:getStats():set(CharacterStat.HUNGER, 0)
                player:getStats():set(CharacterStat.THIRST, 0.25)
                player:getStats():set(CharacterStat.BOREDOM, 0)
                player:getNutrition():setCalories(1000)
            elseif command == "ownedbook" then
                local bag = player:getInventory():AddItem("Base.Bag_Schoolbag")
                bag:setName("Fixture owned book bag")
                local book = bag:getInventory():AddItem("Base.Book")
                print("[AutoMindfulFixture] OWNEDBOOK bagID=" .. bag:getID() .. " bookID=" .. book:getID())
                player:getStats():set(CharacterStat.HUNGER, 0)
                player:getStats():set(CharacterStat.THIRST, 0)
                player:getStats():set(CharacterStat.BOREDOM, 40)
                player:getNutrition():setCalories(1000)
            elseif command == "snapshot" then
                local window = AutoMindful.UI.windows[0]
                print("[AutoMindfulFixture] SNAPSHOT xp=" .. tostring(player:getXp():getXP(Perks.Meditation))
                    .. " yogaXP=" .. tostring(HiddenSkills.getSkill(player, "Yoga")[2])
                    .. " thirst=" .. tostring(player:getStats():get(CharacterStat.THIRST))
                    .. " nearby=" .. tostring(window and window.nearby:isSelected(1)))
            end
            print("[AutoMindfulFixture] COMMAND " .. command)
        end
    end
end)
