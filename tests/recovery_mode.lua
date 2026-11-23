-- Controller integration: the queue, stats and native effects are explicit
-- game-boundary doubles. No live client or synthetic player-stat writes by
-- the controller are needed to demonstrate the mode's decisions.
AutoMindfulContractHarnessOnly = true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly = nil

local T, C = AutoMindfulTest, AutoMindfulTest.controller
local Q = ISTimedActionQueue
local Options = require "AutoMindful/Options"
local Facts = require "AutoMindful/WellnessFacts"
local previousInfo, previousCare = getModInfoByID, Options.practiceCare
function getModInfoByID(id)
    if id == "LifestyleHobbies" then return {getModVersion=function() return Facts.version end} end
end
Options.practiceCare = function() return true end
CharacterStat.STRESS = "STRESS"
CharacterStat.INTOXICATION = "INTOXICATION"

local function head(p) return Q.getTimedActionQueue(p).queue[1] end
local function step(p, ms)
    T.now = T.now + (ms or 250)
    C.update(p)
end
local function steps(p, count)
    for _ = 1, count do step(p) end
end
local function started(p, mode, nearby)
    local ok, reason = C.start(p, mode, nearby == true)
    assert(ok, reason)
    local status = C.status(p)
    assert(status.active and status.mode == mode)
    if mode ~= "endurance" then assert(status.cycle == nil, "Recovery must not create a training ledger") end
end
local function survivor(rank)
    local p = T.playerNew()
    p.sitting, p.meditation, p.xp = true, rank, rank == 10 and 10000 or 0
    p.yoga = rank == 10 and {10, 0, 0} or {0, 0, 100}
    p.data.AutoMindfulLastCompleted = "yoga"
    function p:getPrimaryHandItem() return nil end
    function p:getSecondaryHandItem() return nil end
    function p:getPainEffect() return self.fixtureEffect or 0 end
    function p:getPainDelta() return self.fixturePainDelta or 0 end
    function p:getSleepingTabletEffect() return 0 end
    return p
end
local function count(p, kind)
    local n = 0
    for _, name in ipairs(p.history) do if kind == name then n = n + 1 end end
    return n
end
local function noTraining(p, expectedYoga, expectedMeditation)
    assert(count(p, "Yoga") == (expectedYoga or 0) and count(p, "Meditation") == (expectedMeditation or 0),
        "A recovery job must not practice without a useful current need")
    assert(C.status(p).cycle == nil and p.data.AutoMindfulLastCompleted == "yoga",
        "Native comfort effects must not mark a training turn complete")
end
local function awaitHead(p, kind, extra)
    for _ = 1, 32 do
        step(p)
        local status, a = C.status(p), head(p)
        assert(status.active, status.message)
        if a then
            if a.Type == kind then return a end
            assert(a.Type == "stand" or extra and extra[a.Type],
                "Expected " .. kind .. ", found " .. tostring(a.Type))
            assert(a.autoMindfulOwner and a:isStarted() and a:isValid(), "Unexpected preparation")
            a:perform()
        end
    end
    error("Did not admit " .. kind .. "; " .. C.status(p).message)
end
local function untouched(p, action)
    assert(head(p) == action and p.nativeHead == action.action and action:isStarted(),
        "Foreign job must retain its actual Lua and native handles")
    assert(action.adds == 1 and action.begins == 1 and not action.removes
        and not action.autoMindfulOwner and not action.stopped and not action.forceStopped
        and not action.cancelled, "Never cancel, requeue or claim foreign work")
end
local function food(p)
    return T.add(p.inventory, T.item("Food", {hunger=-0.8, baseHunger=-0.8, calories=320}))
end
local function water(p)
    return T.add(p.inventory, T.water({thirst=-0.8}))
end

-- Match Lifestyle's native destructive menu boundary. The game fixture owns
-- every effect; the controller can only choose/observe this actual action.
local menus = {}
for _, kind in ipairs({"Yoga","Meditation"}) do
    local option = ZenWellnessContextMenu.Options[kind]
    menus[kind] = option.onAction
    function option.onAction(_, self, p)
        assert(not head(p) and not p.nativeHead, "An upstream clear cannot touch a foreign/native head")
        assert(p:isSitOnGround() == (kind=="Meditation"), "Wait until native posture is settled")
        assert(not self.canPerform(p), "Recheck the current Lifestyle gate at admission")
        Q.clear(p)
        Q.add(T.action(p,kind,function()
            p.fixturePracticesDone = (p.fixturePracticesDone or 0) + 1
            if kind == "Yoga" then
                p.values.BOREDOM = math.max(0, p.values.BOREDOM - (p.fixtureYogaRelief or 30))
            end
        end))
    end
end

local cases = 0
local function test(name, run)
    run()
    cases = cases + 1
    print("PASS " .. name)
end

test("persistent Recovery stays armed at both caps without practicing at low or full endurance", function()
    local p = survivor(10)
    p.values.ENDURANCE = 0.24
    started(p, "recovery")
    for _, endurance in ipairs({0.24, 0.82, 0.9999, 1}) do
        p.values.ENDURANCE = endurance
        p.hours = p.hours + 7
        steps(p, 12)
        assert(C.status(p).active and not head(p) and #p.cards == 0,
            "A quiet, comfortable survivor does not need a practice, timeout, or completion card")
        noTraining(p)
        assert(p.xp == 10000 and p.yoga[1] == 10 and p.values.ENDURANCE == endurance)
    end
    C.stop(p)
end)

test("lifesaving drinking and ordinary meals run at rank zero and both caps without a practice", function()
    for _, rank in ipairs({0,10}) do
        local p = survivor(rank)
        local bottle, meal = water(p), food(p)
        p.values.THIRST, p.thirstMoodle, p.values.HUNGER = 0.46, 4, 0.35
        local calories = p.calories
        started(p, "recovery")
        local drink = awaitHead(p, "drink")
        assert(drink.autoMindfulOwner and p.values.THIRST == 0.46 and bottle.fluid:getAmount() == 1)
        drink:perform()
        p.thirstMoodle = 0
        assert(p.values.THIRST < 0.46 and bottle.fluid:getAmount() < 1, "Only native drink produces the reading and source delta")
        local eat = awaitHead(p, "eat")
        eat:perform()
        assert(p.values.HUNGER < 0.35 and p.calories > calories and meal:getHungerChange() > -0.8)
        steps(p, 12)
        assert(C.status(p).active and count(p,"drink")==1 and count(p,"eat")==1 and #p.cards == 0)
        noTraining(p)
        C.stop(p)
    end
end)

test("missing critical water keeps persistent Recovery waiting and uses water that becomes available", function()
    local p = survivor(0)
    p.values.THIRST,p.thirstMoodle=0.46,4
    started(p,"recovery")
    steps(p,24)
    assert(C.status(p).active and not head(p) and p.values.THIRST==0.46 and #p.cards==0,
        "Unavailable water must not be invented or cancel requested persistent help")
    noTraining(p)
    local bottle=water(p)
    local drink=awaitHead(p,"drink")
    drink:perform()
    p.thirstMoodle=0
    steps(p,14)
    assert(C.status(p).active and p.values.THIRST<0.46 and bottle.fluid:getAmount()<1 and count(p,"drink")==1)
    noTraining(p)
    C.stop(p)
end)

test("nearby literature is borrowed, used, and returned before optional Yoga", function()
    local p, shelf = survivor(10), T.container(1, 0)
    local origin = p:getSquare()
    local book = T.add(shelf, T.item("Literature", {boredom=-40, data={literatureTitle="RecoveryFixture"}}))
    p.nearby, p.available, p.values.BOREDOM = {shelf}, {shelf}, 42
    started(p, "recovery", true)
    local read = awaitHead(p, "read", {ISInventoryTransferAction=true})
    assert(C.status(p).collectNearby and p.inventory:contains(book) and not shelf:contains(book))
    assert(p.values.BOREDOM == 42 and not p.read.RecoveryFixture)
    read:perform()
    for _ = 1, 24 do
        step(p)
        local a = head(p)
        if a then assert(a.Type=="ISInventoryTransferAction" and a.autoMindfulOwner); a:perform() end
        if shelf:contains(book) then break end
    end
    assert(shelf:contains(book) and not p.inventory:contains(book) and p:getSquare()==origin)
    assert(p.values.BOREDOM == 2 and p.read.RecoveryFixture == T.nights and count(p,"read")==1)
    steps(p, 8)
    noTraining(p)
    assert(C.status(p).active)
    C.stop(p)
end)

test("native painkiller receipt happens only once during Recovery", function()
    local p = survivor(0)
    local item = T.add(p.inventory, T.item("DrainableComboItem", {fullType="Base.Pills",uses=4}))
    function item:getCurrentUses() return self.uses end
    function item:getUseDelta() return 0.1 end
    function item:getOnEat() return nil end
    function item:getReplaceOnDeplete() return nil end
    local original = ISInventoryPaneContextMenu.takePill
    ISInventoryPaneContextMenu.takePill = function(actual, slot)
        assert(actual == item and slot == p:getPlayerNum())
        local dose = T.action(p,"ISTakePillAction",function()
            actual.uses = actual.uses-1
            p.fixtureEffect,p.fixturePainDelta=5400,0.3
        end)
        dose.item = actual
        Q.add(dose)
    end
    p.values.PAIN = 27
    started(p,"recovery")
    local dose = awaitHead(p,"ISTakePillAction")
    assert(dose.item==item and item.uses==4)
    dose:perform()
    assert(item.uses==3 and p.fixtureEffect>0 and p.fixturePainDelta>0)
    -- The fixture's next native pain sample eases after the treatment.
    p.values.PAIN=5
    steps(p,24)
    assert(C.status(p).active and not head(p) and count(p,"ISTakePillAction")==1 and item.uses==3)
    noTraining(p)
    C.stop(p)
    ISInventoryPaneContextMenu.takePill=original
end)

test("a permitted native Lifestyle restroom action is admitted and its receipt is not a training turn", function()
    local p = survivor(0)
    local R = require "AutoMindful/RestroomCare"
    local previous = {need=R.need, snapshot=R.snapshot, groundAllowed=R.groundAllowed, receipt=R.receipt, queueGround=R.queueGround}
    p.fixtureUrge = 0.6
    R.need = function(player) return player.fixtureUrge or 0 end
    R.groundAllowed = function(player) return player.fixtureUrge and player.fixtureUrge>=0.4 end
    R.snapshot = function(player) return {before=player.fixtureUrge} end
    R.receipt = function(player, baseline, which)
        return which=="ground" and player.fixtureUrge<baseline.before
    end
    R.queueGround = function(player)
        assert(not player:isSitting())
        Q.add(T.action(player,"LSUseToiletGround",function() player.fixtureUrge=0 end))
        return true
    end
    started(p,"recovery")
    local use = awaitHead(p,"LSUseToiletGround")
    assert(use.autoMindfulOwner and p.fixtureUrge==0.6)
    use:perform()
    steps(p,16)
    assert(C.status(p).active and p.fixtureUrge==0 and count(p,"LSUseToiletGround")==1)
    noTraining(p)
    C.stop(p)
    for key,fn in pairs(previous) do R[key]=fn end
end)

test("foreign work stays untouched and new care starts only after its native handle drains", function()
    local p = survivor(0)
    started(p,"recovery"); step(p)
    local completed = 0
    local job = T.action(p,"OtherModsTimedWork",function() completed=completed+1 end)
    Q.add(job)
    local bottle = water(p)
    p.values.THIRST,p.thirstMoodle=0.46,4
    for _ = 1,16 do
        step(p)
        untouched(p,job)
        assert(C.status(p).active and #p.cards==0 and count(p,"drink")==0 and completed==0)
    end
    job:perform()
    local drink = awaitHead(p,"drink")
    drink:perform()
    p.thirstMoodle=0
    steps(p,12)
    assert(C.status(p).active and completed==1 and count(p,"drink")==1 and bottle.fluid:getAmount()<1)
    noTraining(p)
    C.stop(p)
end)

test("starting one-shot at already full does not claim a recovery or touch a foreign action", function()
    local p = survivor(0)
    local job = T.action(p,"ForeignWorkout")
    Q.add(job)
    local ok, reason = C.start(p,"recoverEndurance",false)
    assert(not ok and reason and reason:lower():find("already full",1,true) and not C.status(p).active)
    untouched(p,job)
    assert(#p.cards==0)
    job:perform()
    steps(p,12)
    assert(not C.status(p).active and not head(p) and #p.cards==0)
end)

test("one-shot recovery ignores a transient full sample during foreign work and completes only at quiet, exact full", function()
    local p = survivor(10)
    p.values.ENDURANCE=0.55
    local job = T.action(p,"ForeignWorkout",function() p.values.ENDURANCE=0.9999 end)
    local follow = T.action(p,"ForeignCleanup")
    Q.add(job); Q.add(follow)
    started(p,"recoverEndurance")
    p.values.ENDURANCE=1
    steps(p,12)
    untouched(p,job)
    assert(C.status(p).active and #p.cards==0)
    job:perform()
    steps(p,8)
    untouched(p,follow)
    assert(C.status(p).active and p.values.ENDURANCE==0.9999)
    follow:perform()
    steps(p,16)
    assert(C.status(p).active and not head(p) and #p.cards==0)
    noTraining(p)
    p.values.ENDURANCE=1
    for _=1,24 do
        step(p)
        if not C.status(p).active then break end
    end
    assert(not C.status(p).active and C.status(p).phase=="complete" and not head(p),
        C.status(p).message or "A quiet exact-full native reading must end the one-shot mode")
    assert(not job.stopped and not follow.stopped and not follow.autoMindfulOwner)
    local cards=#p.cards
    assert(cards==1 and p.cards[1].status=="complete", "A real passive recovery emits exactly one success card")
    p.values.ENDURANCE=0.7
    steps(p,16)
    assert(not C.status(p).active and not head(p) and #p.cards==cards, "Full is terminal, not a loop")
end)

test("true Stop and confirmed aim never rearm and never cancel an unrelated action", function()
    for _, stop in ipairs({"button","aim"}) do
        local p = survivor(10)
        started(p,"recovery")
        local job=T.action(p,"OtherModsTimedWork")
        Q.add(job); step(p)
        untouched(p,job)
        if stop=="button" then C.stop(p) else p.aiming=true; step(p) end
        assert(not C.status(p).active and C.status(p).phase=="stopped")
        untouched(p,job)
        p.aiming=false
        job:perform()
        water(p); p.values.THIRST,p.thirstMoodle=0.46,4
        steps(p,16)
        assert(not C.status(p).active and not head(p) and count(p,"drink")==0)
        noTraining(p)
    end
end)

test("eligible Yoga is allowed at rank zero or cap, but relief is not credited as training", function()
    for _, rank in ipairs({0,10}) do
        local p = survivor(rank)
        p.values.BOREDOM=43
        started(p,"recovery")
        local a=awaitHead(p,"Yoga")
        assert(a.autoMindfulOwner and a:isStarted() and a.begins==1 and not a.stopped)
        assert(p.values.BOREDOM==43 and not p.fixturePracticesDone)
        -- This native pose helps before the whole course finishes.
        p.values.BOREDOM=36
        steps(p,5)
        assert(head(p)==a and not a.stopped and p.fixturePracticesDone==nil,
            "Do not interrupt native Yoga just because the first pose helped")
        a:perform()
        steps(p,16)
        assert(C.status(p).active and p.values.BOREDOM==6 and p.fixturePracticesDone==1 and not head(p))
        noTraining(p,1)
        C.stop(p)
    end
end)

test("urgent water interrupts only owned optional Yoga, then Recovery remains available", function()
    local p = survivor(10)
    local bottle=water(p)
    p.values.BOREDOM=43
    started(p,"recovery")
    local a=awaitHead(p,"Yoga")
    p.values.THIRST,p.thirstMoodle=0.48,4
    local drink=awaitHead(p,"drink")
    assert(a.stopped and not a.autoMindfulFinished and not p.fixturePracticesDone,
        "Only the owned optional practice can be cut short for immediate survival care")
    drink:perform()
    p.thirstMoodle=0
    steps(p,20)
    assert(C.status(p).active and bottle.fluid:getAmount()<1 and count(p,"drink")==1
        and not head(p), "No immediate Yoga retry or duplicate drink")
    noTraining(p,1)
    C.stop(p)
end)

test("an owned no-relief Yoga offer is bounded and fails without a retry loop", function()
    local p=survivor(10)
    p.values.BOREDOM=43
    started(p,"recovery")
    local a=awaitHead(p,"Yoga")
    -- Beyond the policy's longest optional Yoga budget, but not an
    -- unobserved wall-clock leap that could invalidate testing the deadline.
    for _=1,480 do
        step(p,1000)
        if a.stopped then break end
    end
    assert(a.stopped and not a.autoMindfulFinished and not p.fixturePracticesDone, "Optional Yoga must relinquish without a native result")
    steps(p,20)
    assert(C.status(p).active and not head(p) and p.values.BOREDOM==43)
    noTraining(p,1)
    C.stop(p)
end)

test("Strong Mindfulness opens the queue at its native tier without meal, calorie, or turn credit", function()
    local priorText=SandboxVars.Text
    SandboxVars.Text={DividerMeditationNew=true,EffectMultiplier=2}
    local p=survivor(0)
    p.meditation,p.xp,p.values.HUNGER=6,605,0.24
    local beforeHunger,calories,xp=p.values.HUNGER,p.calories,p.xp
    local effect=p.data.LSMoodles.MindfulState
    started(p,"recovery")
    local meditation=awaitHead(p,"Meditation")
    assert(C.status(p).phase=="practice-care" and meditation.autoMindfulOwner
        and meditation:isStarted() and p.nativeHead==meditation.action and effect.Value==0)
    assert(count(p,"eat")==0 and count(p,"Yoga")==0 and p.values.HUNGER==beforeHunger and p.calories==calories)
    -- A rank/unlock or the first native Mindfulness tier is not Strong.
    effect.Value,effect.Level=0.2,2
    steps(p,5)
    assert(head(p)==meditation and not meditation.stopped and C.status(p).active)
    -- The running native practice now exposes its actual tier value. It
    -- has not supplied a meal or changed hunger in this boundary fixture.
    effect.Value=0.4
    step(p)
    assert(meditation.stopped and not meditation.autoMindfulFinished and not head(p) and not p.nativeHead)
    steps(p,16)
    assert(C.status(p).active and #p.cards==0 and not head(p) and effect.Value==0.4)
    assert(count(p,"eat")==0 and p.values.HUNGER==beforeHunger and p.calories==calories and p.xp==xp
        and not p.fixturePracticesDone)
    noTraining(p,0,1)
    C.stop(p)
    SandboxVars.Text=priorText
end)

test("verified smoker withdrawal selects brief rank-zero care and waits for the matching native stat", function()
    local priorTrait,priorStat=CharacterTrait.SMOKER,CharacterStat.NICOTINE_WITHDRAWAL
    CharacterTrait.SMOKER,CharacterStat.NICOTINE_WITHDRAWAL="smoker","NICOTINE_WITHDRAWAL"
    local nonsmoker=survivor(0)
    nonsmoker.values.NICOTINE_WITHDRAWAL=0.50
    started(nonsmoker,"recovery")
    steps(nonsmoker,12)
    assert(C.status(nonsmoker).active and not head(nonsmoker))
    noTraining(nonsmoker)
    C.stop(nonsmoker)

    local p=survivor(0)
    p.traits.smoker=true
    p.values.NICOTINE_WITHDRAWAL,p.values.STRESS=0.50,0.24
    started(p,"recovery")
    local meditation=awaitHead(p,"Meditation")
    assert(C.status(p).phase=="practice-care" and p.nativeHead==meditation.action and meditation.autoMindfulOwner)
    p.values.STRESS=0.10
    steps(p,4)
    assert(head(p)==meditation and not meditation.stopped,
        "An unrelated native mood reduction does not confirm withdrawal relief")
    p.values.NICOTINE_WITHDRAWAL=0.42
    step(p)
    assert(meditation.stopped and not meditation.autoMindfulFinished and not head(p))
    steps(p,16)
    assert(C.status(p).active and not head(p) and #p.cards==0 and p.meditation==0 and p.xp==0
        and p.values.NICOTINE_WITHDRAWAL==0.42,
        "A measured reduction releases the optional course without immediately repeating it")
    noTraining(p,0,1)
    C.stop(p)
    CharacterTrait.SMOKER,CharacterStat.NICOTINE_WITHDRAWAL=priorTrait,priorStat
end)

test("Basic opens the queue for panic but only a late matching native reading is relief", function()
    local beforeText,beforeLS=SandboxVars.Text,SandboxVars.LS
    SandboxVars.Text,SandboxVars.LS={DividerMeditationNew=true},{MoodUpdate=5}
    local p=survivor(3)
    p.values.PANIC,p.values.FATIGUE=7,0.65 -- sleepy, but a separate native restriction prevents sleep
    started(p,"recovery")
    local med=awaitHead(p,"Meditation")
    local tier=p.data.LSMoodles.MindfulState
    tier.Value=0.2
    step(p)
    assert(med.stopped and not head(p) and p.values.PANIC==7)
    assert(not (C.status(p).careNotice or ""):find("Observed",1,true))
    p.values.STRESS=0.25
    step(p,16000)
    assert(not head(p) and not (C.status(p).careNotice or ""):find("Observed",1,true))
    tier.Value=0 -- native tier drops before its accumulated mood change flushes
    p.values.PANIC=6
    step(p,20000)
    assert(C.status(p).active and not head(p))
    assert((C.status(p).careNotice or ""):find("panic ease",1,true))
    noTraining(p,0,1)
    C.stop(p)
    SandboxVars.Text,SandboxVars.LS=beforeText,beforeLS
end)

test("Strong pain starts at rank six and separately watches real pain after queue release", function()
    local beforeText=SandboxVars.Text
    SandboxVars.Text={DividerMeditationNew=true}
    local p=survivor(6)
    p.values.PAIN=12
    started(p,"recovery")
    local med=awaitHead(p,"Meditation")
    local tier=p.data.LSMoodles.MindfulState
    tier.Value=0.2
    steps(p,4)
    assert(head(p)==med and not med.stopped)
    tier.Value=0.4
    step(p)
    assert(med.stopped and not head(p) and p.values.PAIN==12)
    p.values.HUNGER=0.04
    step(p,16000)
    assert(not (C.status(p).careNotice or ""):find("Observed",1,true))
    p.values.PAIN=11
    step(p)
    assert((C.status(p).careNotice or ""):find("pain ease",1,true) and not head(p))
    noTraining(p,0,1)
    C.stop(p)
    SandboxVars.Text=beforeText
end)

test("foreign work and direct meals invalidate the passive symptom baseline without losing priority", function()
    local beforeText=SandboxVars.Text
    SandboxVars.Text={DividerMeditationNew=true}
    for _, kind in ipairs({"foreign","meal"}) do
        local p=survivor(6)
        p.values.HUNGER=0.24
        p.data.LSMoodles.MindfulState.Value=0.2
        started(p,"recovery")
        local med=awaitHead(p,"Meditation")
        p.data.LSMoodles.MindfulState.Value=0.4
        step(p)
        assert(med.stopped and not head(p))
        local action
        if kind=="foreign" then
            action=T.action(p,"ForeignFoodEffect",function() p.values.HUNGER=0.05 end)
            Q.add(action)
            step(p); untouched(p,action)
        else
            food(p)
            action=awaitHead(p,"eat")
            assert(action.autoMindfulOwner)
        end
        action:perform()
        steps(p,10)
        assert(p.values.HUNGER<0.15 and C.status(p).active and not head(p))
        assert(not (C.status(p).careNotice or ""):find("Observed",1,true), "Other work is not Mindfulness relief")
        noTraining(p,0,1)
        C.stop(p)
    end
    SandboxVars.Text=beforeText
end)

test("a newly available drink beats acquisition even at the ordinary care threshold", function()
    local beforeText=SandboxVars.Text
    SandboxVars.Text={DividerMeditationNew=true}
    local p=survivor(3)
    p.values.PANIC=34
    started(p,"recovery")
    local med=awaitHead(p,"Meditation")
    p.values.THIRST=0.16
    local bottle=water(p)
    local drink=awaitHead(p,"drink")
    assert(med.stopped and count(p,"Meditation")==1 and p.values.PANIC==34)
    drink:perform()
    assert(p.values.THIRST<0.16 and bottle.fluid:getAmount()<1)
    C.stop(p)
    SandboxVars.Text=beforeText
end)

test("Perfect needs safe health, the full native tier, and a real health increase", function()
    local beforeText=SandboxVars.Text
    SandboxVars.Text={DividerMeditationNew=true}
    for _, name in ipairs({"POISON","SICKNESS","FOOD_SICKNESS","ZOMBIE_INFECTION","ZOMBIE_FEVER"}) do CharacterStat[name]=name end
    local function injured(rank,hp,poison)
        local p=survivor(rank)
        p.hp,p.values.POISON=hp,poison
        local body={getOverallBodyHealth=function() return p.hp end,getNumPartsBleeding=function() return 0 end,
            isInfected=function() return false end,getNumPartsBitten=function() return 0 end}
        function p:getBodyDamage() return body end
        return p
    end
    for _, p in ipairs({injured(9,87),injured(10,70),injured(10,87,1)}) do
        started(p,"recovery"); steps(p,8); noTraining(p); C.stop(p)
    end
    local p=injured(10,85)
    started(p,"recovery")
    local med=awaitHead(p,"Meditation")
    for _, value in ipairs({0.2,0.4}) do
        p.data.LSMoodles.MindfulState.Value=value
        steps(p,5)
        assert(head(p)==med and not med.stopped and p.hp==85)
    end
    p.data.LSMoodles.MindfulState.Value=0.6
    step(p)
    assert(med.stopped and not head(p) and p.hp==85)
    assert(not (C.status(p).careNotice or ""):find("Observed",1,true))
    p.hp=86
    step(p)
    assert((C.status(p).careNotice or ""):find("health improve",1,true))
    noTraining(p,0,1)
    C.stop(p)
    SandboxVars.Text=beforeText
end)

test("legacy endurance meditation still admits its selected native action and ends at full", function()
    local p = survivor(10)
    p.values.ENDURANCE = 0.6
    started(p,"endurance",true)
    local a=awaitHead(p,"Meditation")
    assert(a.autoMindfulOwner and a:isStarted() and not C.status(p).collectNearby)
    p.values.ENDURANCE=1
    steps(p,8)
    assert(not C.status(p).active and C.status(p).phase=="complete" and not head(p) and a.stopped)
end)

for kind, fn in pairs(menus) do ZenWellnessContextMenu.Options[kind].onAction=fn end
getModInfoByID, Options.practiceCare=previousInfo, previousCare
print("PASS "..cases.." Recovery mode integration cases (explicit game-boundary doubles)")
