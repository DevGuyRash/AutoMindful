Events.OnMainMenuEnter.Add(function()
    if AutoMindfulMPConnecting then return end
    local reader = getFileReader("automindful-mp-port.txt", false)
    if not reader then return end
    local port = reader:readLine()
    reader:close()
    if not tonumber(port) then return end
    AutoMindfulMPConnecting = true
    ConnectToServer.instance:connect(MainScreen.instance.bottomPanel, "AutoMindful loopback verification",
        "mindfulplayer", "local-probe", "127.0.0.1", "127.0.0.1", port, "", false, false, 0)
end)

local nextReport = 0
Events.OnPlayerUpdate.Add(function(player)
    if player ~= getSpecificPlayer(0) or getTimestampMs() < nextReport then return end
    nextReport = getTimestampMs() + 5000
    local status = AutoMindful and AutoMindful.Controller and AutoMindful.Controller.status(player)
    if not status then print("[AutoMindfulMPFixture] AUTOINTERFACE_MISSING") return end
    local skill = HiddenSkills.getSkill(player, "Yoga")
    print("[AutoMindfulMPFixture] phase=" .. status.phase .. " med=" .. status.meditation
        .. " medXP=" .. player:getXp():getXP(Perks.Meditation) .. " yoga=" .. status.yoga
        .. " yogaXP=" .. skill[2] .. " access=" .. player:getAccessLevel()
        .. " hunger=" .. player:getStats():get(CharacterStat.HUNGER)
        .. " thirst=" .. player:getStats():get(CharacterStat.THIRST))
    local reader = getFileReader("automindful-mp-command.txt", false)
    if reader then
        local command = reader:readLine()
        reader:close()
        if command and command ~= AutoMindfulMPLastCommand then
            AutoMindfulMPLastCommand = command
            if command == "boredom" then player:getStats():set(CharacterStat.BOREDOM, 40)
            elseif command == "hunger" then LSUtil.changeCharacterMoodGroup(player, {Hunger={0.25,false,true,true}})
            elseif command == "thirst" then LSUtil.changeCharacterMoodGroup(player, {Thirst={0.25,false,true,true}})
            end
            print("[AutoMindfulMPFixture] COMMAND " .. command)
        end
    end
end)
