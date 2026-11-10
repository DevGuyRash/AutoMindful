local Controller = require "AutoMindful/Controller"

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
    local scenario = {name = "AutoMindful isolated verification", startLoc = {x=11778, y=6749, z=0},
        onStart = function()
            local player = getSpecificPlayer(0)
            getCore():setOptionPauseOnFocusloss(false)
            local square = player:getSquare()
            for i=1,120 do square:AddWorldInventoryItem("Base.Crisps", 0.4, 0.4, 0) end
            for i=1,100 do square:AddWorldInventoryItem("Base.Book", 0.4, 0.4, 0) end
            for i=1,30 do
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
Events.OnPlayerUpdate.Add(function(player)
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
