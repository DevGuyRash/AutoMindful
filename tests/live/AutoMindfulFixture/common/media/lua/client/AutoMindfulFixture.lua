local Controller = require "AutoMindful/Controller"
local Nearby = require "AutoMindful/Nearby"
local Options = require "AutoMindful/Options"

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

local fluidCase

local function fixtureFluidState(player, label)
    if not fluidCase then return end
    local status = Controller.status(player)
    local actions = {}
    for _, action in ipairs(ISTimedActionQueue.getTimedActionQueue(player).queue) do actions[#actions + 1] = action.Type end
    local function itemState(item)
        if not item then return "none" end
        local contents = fluid(item)
        local parent = item:getContainer()
        local bag = parent and parent:getContainingItem()
        local world = item:getWorldItem()
        return "id=" .. item:getID() .. ",amount=" .. tostring(contents and contents:getAmount())
            .. ",tainted=" .. tostring(contents and contents:isTainted())
            .. ",bag=" .. tostring(bag and bag:getID()) .. ",world=" .. tostring(world ~= nil)
    end
    print("[AutoMindfulFixture] FLUIDCASE label=" .. label .. " mode=" .. fluidCase.mode
        .. " phase=" .. status.phase .. " active=" .. tostring(status.active) .. " returns=" .. status.pendingReturns
        .. " hunger=" .. player:getStats():get(CharacterStat.HUNGER) .. " thirst=" .. player:getStats():get(CharacterStat.THIRST)
        .. " source={" .. itemState(fluidCase.source) .. "} vessel={" .. itemState(fluidCase.vessel) .. "}"
        .. " sourceOrigin=" .. tostring(fluidCase.sourceBag and fluidCase.sourceBag:getID())
        .. " vesselOrigin=" .. tostring(fluidCase.vesselBag and fluidCase.vesselBag:getID())
        .. " worldUnchanged=" .. tostring(fluidCase.initialWorld and fluidCase.source:getWorldItem() == fluidCase.initialWorld)
        .. " queue=" .. table.concat(actions, ",") .. " notice=" .. tostring(status.returnNotice))
end

local function removeFixtureItem(item)
    if not item then return end
    local world = item:getWorldItem()
    if world then world:removeFromWorld(); world:removeFromSquare()
    elseif item:getContainer() then item:getContainer():Remove(item) end
end

local function scoutTargetSquare(origin)
    for _, delta in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
        local previous = origin
        for step=1,6 do
            local square = getCell():getGridSquare(origin:getX()+delta[1]*step, origin:getY()+delta[2]*step, origin:getZ())
            if not square or not square:isFree(false) or not previous:canReachTo(square) then break end
            previous = square
            if step==6 then return square end
        end
    end
end

local scoutCase
local function startScoutCase(player, mode)
    if mode ~= "book" and mode ~= "fast-empty" then return end
    local status, origin = Controller.status(player), player:getSquare()
    if status.active or status.pendingReturns > 0 or player:tooDarkToRead() then
        print("[AutoMindfulFixture] SCOUTCASE_PRECONDITION need idle survivor, no loans and reading light"); return
    end
    if scoutCase then removeFixtureItem(scoutCase.item); scoutCase=nil end
    clearLiterature(player)
    local target = scoutTargetSquare(origin)
    if not target then print("[AutoMindfulFixture] SCOUTCASE_PRECONDITION need six clear floor tiles"); return end
    local item = target:AddWorldInventoryItem(mode=="book" and "Base.Book" or "Base.Bag_Schoolbag", 0.4, 0.4, 0)
    if mode=="fast-empty" then item:getInventory():setExplored(false) end
    Options.setSearchNearby(true)
    Nearby.invalidate(player)
    local selected = Nearby.find(player, "literature", origin, Options.searchRadius(), {})
    if not selected or (mode=="book" and selected.item~=item)
            or (mode=="fast-empty" and selected.container~=item:getInventory()) then
        removeFixtureItem(item)
        print("[AutoMindfulFixture] SCOUTCASE_PRECONDITION move away from competing supplies"); return
    end
    local stats = player:getStats()
    for _, key in ipairs({"HUNGER","THIRST","FATIGUE","PANIC"}) do stats:set(CharacterStat[key], 0) end
    stats:set(CharacterStat.ENDURANCE, 1)
    stats:set(CharacterStat.BOREDOM, mode=="book" and 40 or 25)
    scoutCase = {mode=mode, item=item, origin=origin}
    local started,message = Controller.start(player, "meditation", false)
    print("[AutoMindfulFixture] SCOUTCASE mode="..mode.." started="..tostring(started).." "..tostring(message))
end

local waterCase
local function startWaterCase(player, mode)
    if mode == "stop" and waterCase then
        Controller.stop(player, "Finished the water journey fixture.")
        removeFixtureItem(waterCase.item)
        waterCase = nil
        return
    end
    if mode ~= "finite" and mode ~= "mains" then return end
    local status, origin = Controller.status(player), player:getSquare()
    if status.active or status.pendingReturns > 0 then
        print("[AutoMindfulFixture] WATERCASE_PRECONDITION need idle survivor and no loans"); return
    end
    if waterCase then removeFixtureItem(waterCase.item); waterCase = nil end
    clearProvisions(player)
    local item
    if mode == "finite" then
        local target = scoutTargetSquare(origin)
        if not target then print("[AutoMindfulFixture] WATERCASE_PRECONDITION need six clear floor tiles"); return end
        item = target:AddWorldInventoryItem("Base.Bucket", 0.4, 0.4, 0)
        local water = fluid(item)
        water:Empty()
        water:addFluid(Fluid.Water, 5)
    end
    Options.setSearchNearby(true)
    Nearby.invalidate(player)
    local selected = Nearby.find(player, "water", origin, Options.searchRadius(), {}, true)
    local source = selected and selected.object and selected.object:getMasterObject()
    local adjacent = require "AutoMindful/WaterSources"
    if adjacent.choose(player, {}) or not source or (mode == "finite" and source ~= item:getWorldItem())
            or (mode == "mains" and (instanceof(source, "IsoWorldInventoryObject") or source:isTaintedWater())) then
        removeFixtureItem(item)
        print("[AutoMindfulFixture] WATERCASE_PRECONDITION need expected distant clean source and no adjacent water"); return
    end
    local stats = player:getStats()
    for _, key in ipairs({"HUNGER","BOREDOM","FATIGUE","PANIC"}) do stats:set(CharacterStat[key], 0) end
    stats:set(CharacterStat.ENDURANCE, 1)
    stats:set(CharacterStat.THIRST, 0.25)
    player:getNutrition():setCalories(1000)
    local started, message = Controller.start(player, "meditation", false)
    if started then
        waterCase = {mode=mode, item=item, origin=origin, source=source, before=source:getFluidAmount()}
        print("[AutoMindfulFixture] WATERCASE mode=" .. mode .. " started=true target=" .. source:getSquare():getX()
            .. "," .. source:getSquare():getY() .. " amount=" .. waterCase.before)
    else
        removeFixtureItem(item)
        print("[AutoMindfulFixture] WATERCASE_PRECONDITION " .. tostring(message))
    end
end

local function setupFluidCase(player, mode)
    if Controller.status(player).pendingReturns > 0 then
        print("[AutoMindfulFixture] FLUIDCASE_PRECONDITION pending returns")
        return
    end
    Controller.stop(player, "Preparing a controlled fluid fixture.")
    if fluidCase then
        for _, name in ipairs({"source", "vessel", "sourceBag", "vesselBag"}) do removeFixtureItem(fluidCase[name]) end
        for _, item in ipairs(fluidCase.extraVessels or {}) do removeFixtureItem(item) end
    end
    clearProvisions(player)
    clearLiterature(player)
    local inventory = player:getInventory()
    for index = inventory:getItems():size() - 1, 0, -1 do
        local item = inventory:getItems():get(index)
        if fluid(item) then player:removeWornItem(item); inventory:Remove(item) end
    end
    local square = player:getSquare()
    local case = {mode = mode, extraVessels = {}}
    fluidCase = case
    if mode == "borrowed" or mode == "partial" then
        case.sourceBag = square:AddWorldInventoryItem("Base.Bag_Schoolbag", 0.2, 0.2, 0)
        case.sourceBag:setName("Fixture bulk source bag")
        case.source = case.sourceBag:getInventory():AddItem("Base.Bucket")
    elseif mode == "ground" or mode == "mixed" or mode == "tainted" or mode == "contaminate" then
        case.source = square:AddWorldInventoryItem("Base.Bucket", 0.3, 0.3, 0)
        case.initialWorld = case.source:getWorldItem()
    else case.source = inventory:AddItem("Base.Bucket") end
    local source = fluid(case.source)
    source:Empty()
    local milk = instanceItem("Base.Milk"):getFluidContainer():getPrimaryFluid()
    if mode == "mixed" then
        source:addFluid(milk, 2.5); source:addFluid(Fluid.Water, 2.5)
    elseif mode == "tainted" then
        source:addFluid(milk, 4.999); source:addFluid(FluidType.FromNameLower("taintedwater"), 0.001)
    else source:addFluid(milk, 5) end
    if mode ~= "missing" then
        if mode == "borrowed" or mode == "partial" or mode == "contaminate" then
            case.vesselBag = square:AddWorldInventoryItem("Base.Bag_Schoolbag", 0.7, 0.7, 0)
            case.vesselBag:setName("Fixture empty vessel bag")
            case.vessel = case.vesselBag:getInventory():AddItem("Base.WaterBottle")
        else case.vessel = inventory:AddItem("Base.WaterBottle") end
        fluid(case.vessel):Empty()
        if mode == "nonempty" then fluid(case.vessel):addFluid(Fluid.Water, 0.3) end
    end
    if mode == "many" then
        for index = 1, 4 do
            local item = inventory:AddItem("Base.WaterBottle")
            fluid(item):Empty(); case.extraVessels[#case.extraVessels + 1] = item
        end
    end
    local hunger, thirst = 0.2, 0.2
    if mode == "mixed" then hunger = 0.1
    elseif mode == "nonempty" then thirst = 0
    elseif mode == "partial" then hunger, thirst = 0.6, 0.6 end
    player:getStats():set(CharacterStat.HUNGER, hunger)
    player:getStats():set(CharacterStat.THIRST, thirst)
    player:getStats():set(CharacterStat.BOREDOM, 0)
    player:getStats():set(CharacterStat.FATIGUE, 0)
    player:getStats():set(CharacterStat.ENDURANCE, 1)
    player:getStats():set(CharacterStat.PANIC, 0)
    player:getNutrition():setCalories(1000)
    getPlayerLoot(0):refreshBackpacks()
    fixtureFluidState(player, "seeded")
    local report = Controller.prepare(player, true, true)
    print("[AutoMindfulFixture] FLUIDCOUNTS food=" .. report.food .. " water=" .. report.water
        .. " nearbyFood=" .. report.nearbyFood .. " nearbyWater=" .. report.nearbyWater
        .. " reason=" .. tostring(report.fluidReason))
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
local nextFluidSample = 0
Events.OnPlayerUpdate.Add(function(player)
    if player == getSpecificPlayer(0) then
        local queue = ISTimedActionQueue.getTimedActionQueue(player).queue
        for _,action in ipairs(queue) do
            if action.Type == "ISTakeWaterAction" and action ~= lastWaterAction then
                lastWaterAction = action
                local object = action.waterObject
                if waterCase and object == waterCase.source and player:getSquare() ~= waterCase.origin then
                    waterCase.drinks = (waterCase.drinks or 0) + 1
                end
                local sprite = object and object:getSprite()
                print("[AutoMindfulFixture] WATERACTION x=" .. object:getSquare():getX() .. " y=" .. object:getSquare():getY()
                    .. " sprite=" .. tostring(sprite and sprite:getName()))
            end
            if fluidCase and action.Type == "ISFluidTransferAction" and getTimestampMs() >= nextFluidSample then
                nextFluidSample = getTimestampMs() + 150
                local target = fluid(fluidCase.vessel)
                if fluidCase.mode == "contaminate" and not fluidCase.contaminated and target and target:getAmount() > 0.001 then
                    target:addFluid(FluidType.FromNameLower("taintedwater"), 0.001)
                    fluidCase.contaminated = true
                    print("[AutoMindfulFixture] FLUIDCONTAMINATED vessel=" .. fluidCase.vessel:getID())
                end
                fixtureFluidState(player, "pouring")
            end
        end
    end
    if player ~= getSpecificPlayer(0) or getTimestampMs() < nextReport then return end
    nextReport = getTimestampMs() + 1000
    local status = Controller.status(player)
    if waterCase and not waterCase.reported and (status.phase == "meditation" or status.phase == "stopped") then
        waterCase.reported = true
        local amount = waterCase.source:getFluidAmount()
        local thirst = player:getStats():get(CharacterStat.THIRST)
        local atOrigin = player:getSquare() == waterCase.origin
        local expectedReserve = waterCase.mode == "finite" and amount < waterCase.before
            or waterCase.mode == "mains" and amount == waterCase.before
        local passed = status.active and status.phase == "meditation" and atOrigin and waterCase.drinks == 1
            and thirst <= 0.01 and expectedReserve
        print("[AutoMindfulFixture] WATERCASE_RESULT mode=" .. waterCase.mode .. " pass=" .. tostring(passed)
            .. " phase=" .. status.phase .. " atOrigin=" .. tostring(atOrigin) .. " drinks=" .. (waterCase.drinks or 0)
            .. " thirst=" .. thirst .. " before=" .. waterCase.before .. " after=" .. amount)
    end
    local levelText = tostring(status.meditation) .. "/" .. tostring(status.yoga)
    if scoutCase and scoutCase.mode=="fast-empty" and not scoutCase.sped and status.phase=="scouting" then
        scoutCase.sped=true; setGameSpeed(4)
        print("[AutoMindfulFixture] SCOUTCASE fast-forward during inspection")
    end
    if status.phase ~= lastPhase or levelText ~= lastLevels then
        lastPhase = status.phase
        lastLevels = levelText
        print("[AutoMindfulFixture] STATE " .. status.phase .. " meditation=" .. tostring(status.meditation)
            .. " yoga=" .. tostring(status.yoga) .. " " .. status.message)
        if scoutCase then print("[AutoMindfulFixture] SCOUTCASE phase="..status.phase.." active="..tostring(status.active)
            .." atOrigin="..tostring(player:getSquare()==scoutCase.origin).." speed="..getGameSpeed()) end
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
            elseif command == "watercase" then startWaterCase(player, line:match("^%S+%s+(%S+)"))
            elseif command == "scoutcase" then startScoutCase(player, line:match("^%S+%s+(%S+)"))
            elseif command == "fluidcase" then setupFluidCase(player, line:match("^%S+%s+(%S+)") or "owned")
            elseif command == "fluidstate" then fixtureFluidState(player, "requested")
            elseif command == "xpstate" then progressSnapshot(player)
            elseif command == "staminastate" then
                local actions = {}
                for _, action in ipairs(ISTimedActionQueue.getTimedActionQueue(player).queue) do
                    actions[#actions + 1] = tostring(action.Type)
                end
                print("[AutoMindfulFixture] STAMINA phase=" .. status.phase .. " mode=" .. tostring(status.mode)
                    .. " active=" .. tostring(status.active) .. " endurance=" .. player:getStats():get(CharacterStat.ENDURANCE)
                    .. " fatigue=" .. player:getStats():get(CharacterStat.FATIGUE)
                    .. " boredom=" .. player:getStats():get(CharacterStat.BOREDOM)
                    .. " queue=" .. table.concat(actions, ","))
                progressSnapshot(player)
            elseif command == "endurance" then
                local amount = tonumber(line:match("^%S+%s+([%d%.]+)"))
                if amount then player:getStats():set(CharacterStat.ENDURANCE, amount) end
            elseif command == "lowstamina" then
                clearLiterature(player)
                player:getStats():set(CharacterStat.HUNGER, 0)
                player:getStats():set(CharacterStat.THIRST, 0)
                player:getStats():set(CharacterStat.BOREDOM, 0)
                player:getStats():set(CharacterStat.FATIGUE, 0)
                player:getStats():set(CharacterStat.ENDURANCE, 0.1)
                player:getStats():set(CharacterStat.PANIC, 0)
                player:getModData().LSMoodles.Embarrassed.Value = 0
                player:getModData().LSMoodles.Embarrassed.Level = 0
                SandboxVars.Yoga.RequiresMat = false
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
                local scout = PZAPI.ModOptions:getOptions("AutoMindful"):getOption("searchNearby")
                print("[AutoMindfulFixture] SNAPSHOT xp=" .. tostring(player:getXp():getXP(Perks.Meditation))
                    .. " yogaXP=" .. tostring(HiddenSkills.getSkill(player, "Yoga")[2])
                    .. " thirst=" .. tostring(player:getStats():get(CharacterStat.THIRST))
                    .. " nearby=" .. tostring(window and window.nearby:isSelected(1))
                    .. " scoutPane=" .. tostring(window and window.scouting:isSelected(1))
                    .. " scoutOption=" .. tostring(scout:getValue())
                    .. " scoutMods=" .. tostring(scout.element and scout.element:isSelected(1)))
            end
            print("[AutoMindfulFixture] COMMAND " .. command)
        end
    end
end)
