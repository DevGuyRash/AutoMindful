-- Independent lifecycle cases. All native players, actions and clock inputs
-- are explicit doubles; this does not substitute for a live gameplay test.
AutoMindfulContractHarnessOnly = true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly = nil
local T, C = AutoMindfulTest, AutoMindfulTest.controller

local function queue(player)
    return ISTimedActionQueue.getTimedActionQueue(player).queue
end

local function step(player, count)
    for _ = 1, count or 1 do
        T.now = T.now + 250
        C.update(player)
    end
end

local function await(player, kind)
    for _ = 1, 50 do
        step(player)
        assert(C.status(player).active, C.status(player).message)
        local head = queue(player)[1]
        if head and head.Type == kind then return head end
        if head and head.Type == "stand" then head:perform() end
    end
    error("No " .. kind .. " after " .. C.status(player).message)
end

do
    local player = T.playerNew()
    player.sitting, player.meditation, player.yoga = false, 10, {6,0,30}
    player.nativeYogaLimit, player.values.ENDURANCE = .60, .40
    assert(C.start(player, "yogaTo", false, 4))
    step(player, 13)
    assert(C.status(player).active and not queue(player)[1], "Wait for the native endurance gate")
    player.values.ENDURANCE = .80
    local yoga = await(player, "Yoga")
    player.data.LSMoodles.Zen.Value = .75
    step(player, 8)
    assert(queue(player)[1] == yoga and C.status(player).active and not yoga.stopped,
        "Seeing the tier cannot cut short ongoing Yoga")

    local foreign = T.action(player, "ForeignTimedAction")
    ISTimedActionQueue.add(foreign)
    yoga:perform()
    local handle = foreign.action
    step(player, 20)
    assert(queue(player)[1] == foreign and player.nativeHead == handle
            and not foreign.stopped and not foreign.cancelled and not foreign.autoMindfulOwner,
        "Preserve the foreign successor and its exact handle")
    assert(C.status(player).active, "Let admitted foreign work settle before completing")
    foreign:perform()
    step(player, 16)
    assert(not C.status(player).active and C.status(player).phase == "complete" and #player.cards == 1,
        C.status(player).message)
    print("PASS one-shot live gate, natural Yoga finish, and untouched foreign timed action")
end

do
    local player = T.playerNew()
    player.sitting, player.meditation, player.yoga = true, 10, {6,0,30}
    assert(C.start(player, "meditateTo", false, 3))
    local meditation = await(player, "Meditation")
    T.add(player.inventory, T.water())
    player.values.THIRST, player.thirstMoodle = .65, 4
    player.data.LSMoodles.MindfulState.Value = .6
    local drink = await(player, "drink")
    assert(C.status(player).active and meditation.stopped, "Critical treatment wins the simultaneous tier edge")
    drink:perform()
    player.thirstMoodle = 0
    step(player, 20)
    assert(not C.status(player).active and C.status(player).phase == "complete" and #player.cards == 1,
        C.status(player).message)
    print("PASS critical native treatment takes precedence over a simultaneous tier receipt")
end

do
    local player = T.playerNew()
    player.sitting, player.meditation, player.yoga = true, 10, {6,0,30}
    player.yogaBlocked = getText("Tooltip_Yoga_MissingMat")
    assert(C.start(player, "yogaTo", false, 4))
    step(player, 8)
    assert(not C.status(player).active and not queue(player)[1]
        and C.status(player).message == getText("Tooltip_Yoga_MissingMat"))
    print("PASS permanent Lifestyle mat denial queues no action")
end
