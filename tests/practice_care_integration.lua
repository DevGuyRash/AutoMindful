-- Exercise Controller with the real PracticeCare policy and explicit game-boundary doubles.
AutoMindfulContractHarnessOnly = true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly = nil
local T, C = AutoMindfulTest, AutoMindfulTest.controller
local Options = require "AutoMindful/Options"
local Facts = require "AutoMindful/WellnessFacts"
local PracticeCare = require "AutoMindful/PracticeCare"
local Q = ISTimedActionQueue
local originalProvider, originalOption = getModInfoByID, Options.practiceCare
local enabled, version = true, Facts.version
function getModInfoByID(id)
    if id == "LifestyleHobbies" and version then return {getModVersion=function() return version end} end
end
Options.practiceCare = function() return enabled end

local function head(p) return Q.getTimedActionQueue(p).queue[1] end
local function step(p)
    T.now = T.now + 250
    C.update(p)
end
local function count(p, kind)
    local n = 0
    for _, seen in ipairs(p.history) do if seen == kind then n = n + 1 end end
    return n
end
local function awaitHead(p, kind)
    for _ = 1, 24 do
        step(p)
        local status, action = C.status(p), head(p)
        assert(status.active, status.message)
        if action and action.Type == kind then return action end
        if action then
            assert(action.Type == "stand", "Expected " .. kind .. "; found " .. tostring(action.Type))
            action:perform()
        end
    end
    error("Did not admit " .. kind .. ": " .. C.status(p).message)
end
local function unchangedYogaCycle(p)
    local cycle = C.status(p).cycle
    local yoga = cycle.skills.yoga
    assert(cycle.lastCompleted == "meditation" and p.data.AutoMindfulLastCompleted == "meditation")
    assert(yoga.started == 0 and yoga.completed == 0 and yoga.positiveXPGains == 0 and yoga.hoursWithoutXP == 0,
        "The optional Yoga course must not enter the training ledger")
end
local function survivor()
    local p = T.playerNew()
    p.meditation, p.xp, p.yoga = 5, 510, {10, 0, 0}
    p.values.BOREDOM, p.fixtureYogaRelief = 46, 28
    p.data.AutoMindfulLastCompleted = "meditation"
    function p:getPrimaryHandItem() return self.fixtureHeldItem end
    function p:getSecondaryHandItem() return nil end
    return p
end
local function start(p)
    assert(C.start(p, "both", false))
end
local function startYogaCare(p)
    start(p)
    local action = awaitHead(p, "Yoga")
    assert(C.status(p).phase == "practice-care" and action.autoMindfulOwner and p.nativeHead == action.action)
    assert(action.begins == 1 and #p.cards == 0)
    unchangedYogaCycle(p)
    return action
end

-- Model an actual menu's unconditional clear, then its separate native action.
-- A capped native skill may change comfort, not XP. The mock changes the stat
-- only inside natural perform so the controller must read a real fixture delta.
local originalMenus = {}
for _, kind in ipairs({"Yoga", "Meditation"}) do
    local option = ZenWellnessContextMenu.Options[kind]
    local onAction = option.onAction
    originalMenus[kind] = onAction
    function option.onAction(world, self, p)
        assert(not head(p) and not p.nativeHead, "A native menu clear must never reach another action")
        assert(p:isSitOnGround() == (kind == "Meditation"), "Native posture changed before dispatch")
        assert(not self.canPerform(p), "A stale Lifestyle eligibility check reached native dispatch")
        Q.clear(p)
        if kind ~= "Yoga" then return onAction(world, self, p) end
        Q.add(T.action(p, "Yoga", function()
            p.fixtureYogaEffects = (p.fixtureYogaEffects or 0) + 1
            p.values.BOREDOM = math.max(0, p.values.BOREDOM - p.fixtureYogaRelief)
        end))
    end
end

-- A pleasure action at an already capped rank cannot pay the owed skill turn
-- or accrue a no-XP watchdog penalty, even across a jump in the game clock.
do
    local p = survivor()
    p.sitting = true
    local origin, xp = p:getSquare(), p.xp
    local yoga = startYogaCare(p)
    assert(C.status(p).cycle.due == "meditation", "Blocked Meditation remains owed")
    p.hours = p.hours + 7
    step(p)
    assert(head(p) == yoga and C.status(p).active and not yoga.stopped)
    unchangedYogaCycle(p)
    assert(p.values.BOREDOM == 46 and not p.fixtureYogaEffects)
    yoga:perform()
    local meditation = awaitHead(p, "Meditation")
    local status = C.status(p)
    assert(status.phase == "meditation" and status.cycle.due == "meditation" and p:getSquare() == origin)
    assert(status.careNotice and status.careNotice:find("showed relief", 1, true))
    assert(p.values.BOREDOM == 18 and p.fixtureYogaEffects == 1 and p.xp == xp and p.yoga[1] == 10)
    unchangedYogaCycle(p)
    meditation:perform()
    step(p)
    assert(C.status(p).cycle.skills.meditation.completed == 1 and C.status(p).cycle.due == nil,
        "Only the real Meditation receipt may pay the owed turn")
    C.stop(p)
    print("PASS capped Yoga relieves boredom without spending Meditation's owed turn or accruing no-XP time")
end

local function provision(p, kind)
    return T.add(p.inventory, kind == "water" and T.water({thirst=-0.8})
        or T.item("Food", {hunger=-0.8, baseHunger=-0.8, calories=320}))
end
local function requestSurvivalCare(p, kind, urgent)
    if kind == "water" then p.values.THIRST, p.thirstMoodle = urgent and 0.46 or 0.17, urgent and 4 or 0
    else p.values.HUNGER, p.hungerMoodle = urgent and 0.46 or 0.17, urgent and 4 or 0 end
end
local function workingSupply(p, kind, item)
    local before = kind == "water" and p.values.THIRST or p.values.HUNGER
    local amount = kind == "water" and item.fluid:getAmount() or -item:getHungerChange()
    local calories = p.calories
    local action = awaitHead(p, kind == "water" and "drink" or "eat")
    assert(action.autoMindfulOwner and head(p) == action)
    action:perform()
    local after = kind == "water" and p.values.THIRST or p.values.HUNGER
    local afterAmount = kind == "water" and item.fluid:getAmount() or -item:getHungerChange()
    assert(after < before and afterAmount < amount, "Verify native need and exact source both changed")
    if kind == "food" then assert(p.calories > calories, "Food must still supply calories") end
end
for _, kind in ipairs({"water", "food"}) do
    local p = survivor()
    local item = provision(p, kind)
    local yoga = startYogaCare(p)
    requestSurvivalCare(p, kind, true)
    workingSupply(p, kind, item)
    assert(yoga.stopped and not yoga.autoMindfulFinished and not p.fixtureYogaEffects)
    assert(C.status(p).cycle.due == "meditation" and count(p, "Yoga") == 1)
    unchangedYogaCycle(p)
    C.stop(p)
    print("PASS critical " .. kind .. " preempts only the owned optional practice and uses the native supply")
end

-- Foreign work already queued behind Yoga gets the native handoff untouched,
-- even when the survivor develops a high-priority need at the same boundary.
do
    local p = survivor()
    local meal, treatments = provision(p, "food"), 0
    local yoga = startYogaCare(p)
    local workout = T.action(p, "ISFitnessAction", function() treatments = treatments + 1 end)
    Q.add(workout)
    requestSurvivalCare(p, "food", true)
    step(p)
    assert(yoga.stopped and not yoga.autoMindfulFinished and not p.fixtureYogaEffects)
    local native = workout.action
    for _ = 1, 5 do
        step(p)
        assert(head(p) == workout and p.nativeHead == native and native and workout.begins == 1)
        assert(not workout.autoMindfulOwner and not workout.stopped and not workout.forceStopped and not workout.cancelled)
        assert(count(p, "eat") == 0 and treatments == 0 and C.status(p).active)
    end
    workout:perform()
    workingSupply(p, "food", meal)
    assert(treatments == 1 and count(p, "Yoga") == 1 and #p.cards == 0)
    unchangedYogaCycle(p)
    C.stop(p)
    print("PASS a queued foreign workout retains its exact native head, then urgent care runs after it")
end

-- Mild ordinary needs present before admission still use the regular supply
-- loop; not even a ready optional practice can stand in for calories or water.
for _, kind in ipairs({"water", "food"}) do
    local p = survivor()
    local item = provision(p, kind)
    requestSurvivalCare(p, kind, false)
    start(p)
    workingSupply(p, kind, item)
    assert(count(p, "Yoga") == 0 and C.status(p).cycle.due == "meditation")
    C.stop(p)
    print("PASS ordinary " .. kind .. " takes priority over newly eligible comfort practice")
end

do
    local p = survivor()
    local book = T.add(p.inventory, T.item("Literature", {boredom=-25, data={literatureTitle="CareOrderFixture"}}))
    start(p)
    local reading = awaitHead(p, "read")
    assert(count(p, "Yoga") == 0 and p.inventory:contains(book))
    reading:perform()
    awaitHead(p, "Meditation")
    assert(p.values.BOREDOM == 21 and p.read.CareOrderFixture == T.nights and count(p, "Yoga") == 0)
    C.stop(p)
    print("PASS ready literature still wins and returns to normal training")
end

for _, missing in ipairs({false, true}) do
    enabled, version = missing, missing and nil or Facts.version
    if missing then version = nil end
    local p = survivor()
    start(p)
    step(p)
    local status = C.status(p)
    assert(not status.active and status.phase == "stopped" and status.message:find("boredom is too high", 1, true),
        "Disabled or unavailable optional care must retain the normal native blocker")
    assert(not head(p) and count(p, "Yoga") == 0 and count(p, "Meditation") == 0 and #p.cards == 1)
    unchangedYogaCycle(p)
    print("PASS " .. (missing and "missing provider metadata" or "disabled setting") .. " uses unchanged training fallback")
end
enabled, version = true, Facts.version

do
    local p = survivor()
    p.sitting, p.nativeYogaLimit = true, 0.6
    start(p)
    step(p)
    local stand = head(p)
    assert(stand and stand.Type == "stand" and count(p, "Yoga") == 0)
    p.values.ENDURANCE = 0.5
    stand:perform()
    step(p)
    assert(not head(p) and count(p, "Yoga") == 0 and not C.status(p).active,
        "A posture action is neither an optional practice nor permission to start a stale one")
    unchangedYogaCycle(p)
    print("PASS native Yoga eligibility is rechecked after standing")
end

do
    local p = survivor()
    p.nativeMeditationBoredomLimit, p.fixtureYogaRelief = 60, 0
    local yoga = startYogaCare(p)
    yoga:perform()
    awaitHead(p, "Meditation")
    local status = C.status(p)
    assert(status.careNotice and status.careNotice:find("did not confirm relief", 1, true))
    assert(count(p, "Yoga") == 1 and p.values.BOREDOM == 46 and #p.cards == 0)
    unchangedYogaCycle(p)
    C.stop(p)
    print("PASS a finished native course with no readback does not report success or impede a normal turn")
end

do
    local p = survivor()
    p.nativeMeditationBoredomLimit = 60
    local yoga = startYogaCare(p)
    local course = assert(PracticeCare.choose({now=T.now, yogaReady=true, yogaRank=10, boredom=p.values.BOREDOM}))
    T.now = T.now + course.maxMs
    C.update(p)
    assert(yoga.stopped and not p.fixtureYogaEffects and C.status(p).active)
    awaitHead(p, "Meditation")
    assert(count(p, "Yoga") == 1 and #p.cards == 0,
        "A timed-out optional course must not immediately displace an eligible training turn again")
    unchangedYogaCycle(p)
    C.stop(p)
    print("PASS an optional practice watchdog releases the exact action and hands back to a normal turn")
end

for kind, onAction in pairs(originalMenus) do ZenWellnessContextMenu.Options[kind].onAction = onAction end
getModInfoByID, Options.practiceCare = originalProvider, originalOption
print("PRACTICE CARE INTEGRATION PASS 12 cases; explicit game-boundary doubles, not native gameplay evidence")
