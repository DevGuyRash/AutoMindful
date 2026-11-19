AutoMindfulContractHarnessOnly = true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly = nil
local T = AutoMindfulTest
local Controller = T.controller
local Goal = require "AutoMindful/EnduranceGoal"

local function queued(player)
    return ISTimedActionQueue.getTimedActionQueue(player).queue
end

-- This journey uses the native Lifestyle timed-action type. The shared
-- fixture uses display-name types in its independent level-training cases.
local meditationType = "LSMeditateAction"
function ZenWellnessContextMenu.Options.Meditation.onAction(_, _, player)
    if player.preparingMeditation then
        ISTimedActionQueue.add(T.action(player, "ISUnequipAction"))
    end
    local action = T.action(player, meditationType)
    function action:start() self.nativeMeditationStarted = true end
    function action:isStarted() return self.nativeMeditationStarted == true end
    ISTimedActionQueue.add(action)
end

for _, value in ipairs({0, 0.5, 0.9999, 1}) do
    local player = T.playerNew()
    player.values.ENDURANCE = value
    assert(Goal.read(player) == value and Goal.full(value) == (value == 1))
end
for _, value in ipairs({-0.01, 1.01, "1", math.huge, 0/0}) do
    local player = T.playerNew()
    player.values.ENDURANCE = value
    assert(Goal.read(player) == nil, "Do not invent normalized endurance from invalid game values")
end
local unreadable = T.playerNew()
function unreadable:getStats() error("Unavailable stats") end
assert(Goal.read(unreadable) == nil)
print("PASS exact live-stat read rejects non-finite, unavailable or out-of-range values")

local observation = {}
assert(not Goal.observe(observation, .5, 0, true))
for i=1,150 do
    assert(not Goal.observe(observation, i % 2 == 0 and .499 or .5, i*1000, true))
end
assert(not Goal.observe(observation, .5, 900000, false))
assert(not Goal.observe(observation, .5, 1000000, true))
for i=1,149 do
    assert(not Goal.observe(observation, .5, 1000000+i*1000, true))
end
assert(Goal.observe(observation, .5, 1150000, true))
assert(not Goal.observe(observation, .501, 1151000, true), "A new measurable high renews the budget")
assert(not Goal.observe(observation, .501, 1000, true), "Backward clocks cannot add elapsed time")
assert(not Goal.observe(observation, .501, 5000000, true), "A suspended process is not observed meditating")
print("PASS bounded no-gain observes genuine recovery, not wiggles or time spent paused")

local full = T.playerNew()
local started, fullReason = Controller.start(full,"endurance",true)
assert(not started and not Controller.status(full).active and #queued(full) == 0 and #full.cards == 0
    and fullReason and fullReason:lower():find("already full", 1, true), "Already-full start is a clear no-op")
local invalid = T.playerNew()
invalid.values.ENDURANCE = -1
local _, invalidReason = Controller.start(invalid,"endurance",false)
assert(not Controller.status(invalid).active and #queued(invalid) == 0 and #invalid.cards == 0
    and invalidReason and invalidReason ~= fullReason and invalidReason:lower():find("endurance", 1, true),
    "Unreadable endurance reports its own reason without starting")
print("PASS already-full and unreadable requests do not queue an action or announce completion")

local player = T.playerNew()
player.sitting, player.noXP, player.meditation, player.xp = true, true, 10, 10000
player.values.ENDURANCE, player.values.HUNGER, player.values.THIRST, player.values.FATIGUE = .999, .5, .5, .62
local water = T.add(player.inventory,T.water())
local food = T.add(player.inventory,T.item("Food"))
assert(Controller.start(player,"endurance",true))
assert(not Controller.start(player,"meditation",false), "One endurance job cannot be replaced by another start")
T.tick(player,false)
assert(Controller.status(player).active and Controller.status(player).mode == "endurance"
    and queued(player)[1] and queued(player)[1].Type == meditationType and #player.cards == 0)
assert(not T.hasHistory(player,"Yoga") and not T.hasHistory(player,"eat") and not T.hasHistory(player,"drink")
    and player.inventory:contains(water) and player.inventory:contains(food))
player.values.ENDURANCE = 1
T.tick(player,false)
assert(not Controller.status(player).active and Controller.status(player).phase == "complete"
    and #queued(player) == 0 and #player.cards == 1 and player.xp == 10000
    and not player.cards[1].detail:find("XP", 1, true), "Observed full endurance alone completes once")
T.tick(player,false)
Controller.stop(player)
assert(#player.cards == 1, "Terminal calls do not emit another HUD card")
print("PASS honest one-shot recovery at skill cap, with no care, yoga, scouting or XP requirement")

local interrupted = T.playerNew()
interrupted.sitting, interrupted.noXP = true, true
interrupted.values.ENDURANCE = .60
assert(Controller.start(interrupted,"endurance",false))
T.tick(interrupted,false)
local previous = queued(interrupted)[1]
local workout = T.action(interrupted,"ISFitnessAction",function() interrupted.values.ENDURANCE = .55 end)
ISTimedActionQueue.add(workout)
T.tick(interrupted,false)
assert(Controller.status(interrupted).active and queued(interrupted)[1] == workout
    and not workout.autoMindfulOwner and workout.begins == 1 and #interrupted.cards == 0)
interrupted.values.ENDURANCE = 1
T.tick(interrupted,false)
assert(Controller.status(interrupted).active and queued(interrupted)[1] == workout and #interrupted.cards == 0,
    "A momentary full sample cannot complete during foreign workout")
workout:perform()
T.tick(interrupted,false)
assert(#queued(interrupted) == 0 and Controller.status(interrupted).active,
    "An idle grace leaves the foreign workout's successor clear runway")
for i=1,8 do
    T.tick(interrupted,false)
    if queued(interrupted)[1] then break end
end
local resumed = queued(interrupted)[1]
assert(resumed and resumed ~= previous and resumed.Type == meditationType
    and Controller.status(interrupted).active and #interrupted.cards == 0 and workout.begins == 1)
interrupted.values.ENDURANCE = .999
T.tick(interrupted,false)
assert(Controller.status(interrupted).active and #interrupted.cards == 0)
interrupted.values.ENDURANCE = 1
T.tick(interrupted,false)
assert(Controller.status(interrupted).phase == "complete" and #interrupted.cards == 1 and #queued(interrupted) == 0)
print("PASS ordinary workout takes priority, then the same endurance job resumes and stops at exact full")

local preparing = T.playerNew()
preparing.sitting, preparing.preparingMeditation = true, true
preparing.values.ENDURANCE = .7
assert(Controller.start(preparing,"endurance",false))
T.tick(preparing,false)
local preparation = queued(preparing)[1]
local waitingMeditation = queued(preparing)[2]
assert(preparation.Type == "ISUnequipAction" and waitingMeditation.Type == meditationType
    and not waitingMeditation:isStarted())
for i=1,310 do T.tick(preparing,false) end
assert(Controller.status(preparing).active and queued(preparing)[1] == preparation and #preparing.cards == 0,
    "An owned preparation head is not five minutes of meditation")
preparing.values.ENDURANCE = 1
T.tick(preparing,false)
assert(Controller.status(preparing).phase == "complete" and #preparing.cards == 0
    and #queued(preparing)==0 and not waitingMeditation:isStarted(),
    "Recovery during preparation must not claim a meditation-session receipt")
print("PASS Lifestyle preparation time never counts as started meditation")

local lostStat = T.playerNew()
lostStat.values.ENDURANCE = .65
lostStat.sitting = true
assert(Controller.start(lostStat,"endurance",false))
T.tick(lostStat,false)
lostStat.values.ENDURANCE = 0/0
T.tick(lostStat,false)
local lostStatus = Controller.status(lostStat)
assert(not lostStatus.active and lostStatus.phase == "stopped" and #lostStat.cards == 1
    and lostStatus.message:lower():find("endurance", 1, true), "A bad live reading stops safely without claiming completion")
T.tick(lostStat,false)
assert(#queued(lostStat) == 0 and #lostStat.cards == 1, "Recovery never silently restarts a stopped job")
print("PASS unavailable live endurance is a terminal stop, not a guessed success")

local blocked = T.playerNew()
blocked.sitting, blocked.noXP = true, true
blocked.values.ENDURANCE = .65
assert(Controller.start(blocked,"endurance",false))
for i=1,310 do
    T.tick(blocked,false)
    if not Controller.status(blocked).active then break end
end
local status = Controller.status(blocked)
assert(not status.active and status.phase == "stopped" and #blocked.cards == 1,
    "Five minutes of observed native meditation with no recovery ends as a stop, not a success")
print("PASS stalled recovery stops with one HUD instead of running indefinitely")
print("endurance-journey: PASS (native stat/action boundaries are explicit doubles)")
