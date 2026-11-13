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

local function fluidInventoryProbe(inventory)
    local items = inventory:getItems()
    local holder = inventory:getContainingItem()
    for index=0,items:size()-1 do
        local item = items:get(index)
        local container = item:getFluidContainer()
        if container then
            print("[AutoMindfulMPFixture] FLUID id=" .. item:getID() .. " type=" .. item:getFullType()
                .. " amount=" .. container:getAmount() .. " capacity=" .. container:getCapacity()
                .. " owner=" .. tostring(container:getOwner()) .. " tainted=" .. tostring(container:isTainted())
                .. " holder=" .. tostring(holder and holder:getID() or "root"))
        end
        if instanceof(item, "InventoryContainer") then fluidInventoryProbe(item:getInventory()) end
    end
end

local function fluidProbe(player)
    fluidInventoryProbe(player:getInventory())
    local queue = ISTimedActionQueue.getTimedActionQueue(player).queue
    local action = queue[1]
    print("[AutoMindfulMPFixture] ACTION type=" .. tostring(action and action.Type)
        .. " amount=" .. tostring(action and action.amount)
        .. " sourceObject=" .. tostring(action and action.sourceFluidObject)
        .. " targetObject=" .. tostring(action and action.targetFluidObject))
end

local function fluidSetup(player, borrowed)
    local inventory = player:getInventory()
    local source, vessel, bag
    local items = inventory:getItems()
    for index=0,items:size()-1 do
        local item = items:get(index)
        if item:getFullType() == "Base.Bucket" then source = item end
        if item:getFullType() == "Base.WaterBottle" then vessel = item end
        if item:getFullType() == "Base.Bag_Schoolbag" then bag = item end
    end
    if not source or not vessel then
        print("[AutoMindfulMPFixture] SETUP_NEEDS_SERVER_GRANT Base.Bucket Base.WaterBottle")
        return
    end
    if borrowed and not bag then
        print("[AutoMindfulMPFixture] SETUP_NEEDS_SERVER_GRANT Base.Bag_Schoolbag")
        return
    end
    local milkItem = instanceItem("Base.Milk")
    local milk = milkItem:getFluidContainer():getPrimaryFluid()
    source:getFluidContainer():Empty()
    source:getFluidContainer():addFluid(milk, 5)
    vessel:getFluidContainer():Empty()
    source:syncItemFields()
    vessel:syncItemFields()
    sendItemStats(source)
    sendItemStats(vessel)
    local hunger = borrowed and 0.4 or 0.2
    player:getStats():set(CharacterStat.HUNGER, hunger)
    player:getStats():set(CharacterStat.THIRST, 0.2)
    LSUtil.changeCharacterMoodGroup(player, {Hunger={hunger,false,true,true}, Thirst={0.2,false,true,true},
        Boredom={0,false,true,true}, Fatigue={0,false,true,true}, Endurance={1,false,true,true}})
    if borrowed then
        ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player, vessel, inventory, bag:getInventory()))
    end
    print("[AutoMindfulMPFixture] SETUP source=" .. source:getID() .. " vessel=" .. vessel:getID()
        .. " returnHolder=" .. tostring(borrowed and bag:getID() or "root"))
    fluidProbe(player)
end

local nextReport = 0
Events.OnPlayerUpdate.Add(function(player)
    if player ~= getSpecificPlayer(0) then return end
    local action = ISTimedActionQueue.getTimedActionQueue(player).queue[1]
    if action and action.Type == "ISFluidTransferAction" and action ~= AutoMindfulMPObservedFluidAction then
        AutoMindfulMPObservedFluidAction = action
        print("[AutoMindfulMPFixture] POUR requested=" .. action.amount
            .. " source=" .. action.source:getFluidContainer():getAmount()
            .. " target=" .. action.target:getFluidContainer():getAmount()
            .. " hunger=" .. player:getStats():get(CharacterStat.HUNGER)
            .. " thirst=" .. player:getStats():get(CharacterStat.THIRST))
    end
    if getTimestampMs() < nextReport then return end
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
            if command == "open" then AutoMindful.UI.open(player)
            elseif command == "fluidsetup" then fluidSetup(player)
            elseif command == "fluidbag" then fluidSetup(player, true)
            elseif command == "fluids" then fluidProbe(player)
            elseif command == "boredom" then LSUtil.changeCharacterMoodGroup(player, {Boredom={40,false,true,true}})
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
