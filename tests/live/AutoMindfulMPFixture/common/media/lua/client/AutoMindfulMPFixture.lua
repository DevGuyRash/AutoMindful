Events.OnMainMenuEnter.Add(function()
    if AutoMindfulMPConnecting then return end
    local reader = getFileReader("automindful-mp-port.txt", false)
    if not reader then return end
    local port = reader:readLine()
    reader:close()
    if not tonumber(port) then return end
    AutoMindfulMPConnecting = true
    ConnectToServer.instance:connect(MainScreen.instance.bottomPanel, "AutoMindful loopback verification",
        "mindfulplayer", "local-probe", "127.0.0.1", "127.0.0.1", port, "", false, true, 1)
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
        .. " thirst=" .. player:getStats():get(CharacterStat.THIRST)
        .. " active=" .. tostring(status.active)
        .. " returns=" .. tostring(status.pendingReturns))
    local reader = getFileReader("automindful-mp-command.txt", false)
    if reader then
        local line = reader:readLine()
        reader:close()
        if line and line ~= AutoMindfulMPLastCommand then
            AutoMindfulMPLastCommand = line
            local command = line:match("^(%S+)")
            if command == "boredom" then LSUtil.changeCharacterMoodGroup(player, {Boredom={40,false,true,true}})
            elseif command == "hunger" then LSUtil.changeCharacterMoodGroup(player, {Hunger={0.25,false,true,true}})
            elseif command == "thirst" then LSUtil.changeCharacterMoodGroup(player, {Thirst={0.25,false,true,true}})
            elseif command == "probe" then
                local report = AutoMindful.Controller.prepare(player, status.collectNearby, true)
                local window = AutoMindful.UI.windows[0]
                local books = 0
                local items = player:getInventory():getItems()
                for i=0,items:size()-1 do
                    if instanceof(items:get(i), "Literature") then books=books+1 end
                end
                local floorBooks = 0
                local worlds = player:getSquare():getWorldObjects()
                for i=0,worlds:size()-1 do
                    if instanceof(worlds:get(i):getItem(), "Literature") then floorBooks=floorBooks+1 end
                end
                print("[AutoMindfulMPFixture] PROBE visible=" .. tostring(window and window:isVisible())
                    .. " food=" .. report.food .. " water=" .. report.water .. " literature=" .. report.literature
                    .. " nearbyFood=" .. report.nearbyFood .. " nearbyWater=" .. report.nearbyWater
                    .. " nearbyLiterature=" .. report.nearbyLiterature
                    .. " inventoryBooks=" .. books .. " floorBooks=" .. floorBooks
                    .. " boredom=" .. player:getStats():get(CharacterStat.BOREDOM)
                    .. " notice=" .. tostring(status.returnNotice or status.careNotice))
            end
            print("[AutoMindfulMPFixture] COMMAND " .. command)
        end
    end
end)
