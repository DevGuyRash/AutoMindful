package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. (package.path or "")
local Care = require "AutoMindful/PracticeCare"

local count = 0
local function test(name, run)
    run()
    count = count + 1
    print("PASS " .. name)
end

local function sample(changes)
    local input = {now=1000, yogaReady=true, meditationReady=true, yogaRank=0, meditationRank=0,
        boredom=0, pain=0, stress=0, stiffness=0, panic=0, hunger=0.05}
    for key, value in pairs(changes or {}) do input[key] = value end
    return input
end

local function assertCourse(input, kind, need, stat)
    local course = Care.choose(sample(input))
    assert(course and course.kind == kind and course.need == need and course.stat == stat,
        "Expected " .. kind .. "/" .. need .. "/" .. stat .. ", got "
            .. tostring(course and course.kind) .. "/" .. tostring(course and course.need))
    assert(type(course.maxMs) == "number" and course.maxMs > 0, "Course must have a finite time limit")
    return course
end

local function assertNone(input)
    local course = Care.choose(sample(input))
    assert(not course, "Unexpected " .. tostring(course and course.kind) .. "/" .. tostring(course and course.need))
end

test("native meditation boredom blocker can make even novice Yoga useful", function()
    assertNone({boredom=30})
    assertCourse({boredom=30.01, meditationReady=false}, "yoga", "boredom", "BOREDOM")
    assertNone({boredom=35, yogaReady=false, meditationReady=false})
end)

test("higher Yoga rank admits useful preemptive boredom relief, not a different target magnitude", function()
    assertNone({boredom=25, yogaRank=2})
    assertNone({boredom=24.99, yogaRank=10})
    local course = assertCourse({boredom=25, yogaRank=3}, "yoga", "boredom", "BOREDOM")
    course.before = 25
    assert(Care.improved(course, {boredom=20}))
    course = assertCourse({boredom=25, yogaRank=10}, "yoga", "boredom", "BOREDOM")
    course.before = 25
    assert(Care.improved(course, {boredom=20}))
end)

test("confirmed faster care wins; speculative reading does not monopolize the decision", function()
    assertNone({boredom=45, pain=30, reading="confirmed"})
    assertCourse({boredom=45, reading="speculative"}, "yoga", "boredom", "BOREDOM")
    assertNone({pain=30, stiffness=30, painTreatment=true})
    assertCourse({pain=30, painTreatment=false}, "yoga", "pain", "PAIN")
end)

test("Yoga favors an actual blocker then specific stiffness over general pain", function()
    assertCourse({boredom=45, pain=35, stiffness=25}, "yoga", "boredom", "BOREDOM")
    assertCourse({pain=35, stiffness=25}, "yoga", "stiffness", "STIFFNESS")
    assertNone({pain=24.99, stiffness=19.99, yogaRank=2})
    assertCourse({pain=15, yogaRank=3}, "yoga", "pain", "PAIN")
    assertCourse({stiffness=12.5, yogaRank=3}, "yoga", "stiffness", "STIFFNESS")
    assertNone({pain=14.99, stiffness=12.49, yogaRank=3})
end)

test("normal Meditation is considered only for substantial stress and with little boredom or pain", function()
    assertCourse({stress=0.50, meditationRank=6, boredom=5, pain=5}, "meditation", "stress", "STRESS")
    assertNone({stress=0.499, meditationRank=10, boredom=5, pain=5})
    assertCourse({stress=0.50, meditationRank=0, boredom=5, pain=5}, "meditation", "stress", "STRESS")
    assertCourse({stress=0.50, meditationRank=5, boredom=5, pain=5}, "meditation", "stress", "STRESS")
    assertNone({stress=0.50, meditationRank=10, boredom=5.01, pain=5})
    assertNone({stress=0.50, meditationRank=10, boredom=5, pain=5.01})
    assertNone({stress=0.50, meditationRank=10, meditationReady="yes"})
    assertNone({pain=30, yogaReady=false, meditationRank=10})
    assertNone({boredom=35, yogaReady=false, meditationRank=10})
end)

test("ready Yoga at any rank can relieve pronounced stress when Meditation is unsuitable", function()
    assertNone({stress=0.649, yogaRank=0, meditationReady=false})
    assertCourse({stress=0.65, yogaRank=0, meditationReady=false}, "yoga", "stress", "STRESS")
    assertCourse({stress=0.65, yogaRank=3, boredom=6}, "yoga", "stress", "STRESS")
    assertCourse({stress=0.80, yogaRank=10, boredom=10, pain=6, meditationRank=10},
        "yoga", "stress", "STRESS")
    assertCourse({stress=0.80, yogaRank=10, meditationRank=10}, "meditation", "stress", "STRESS")
end)

test("an already scheduled practice that can relieve the need stays ordinary training", function()
    assertNone({boredom=45, preferTraining="yoga"})
    assertNone({stress=0.8, meditationRank=10, preferTraining="meditation"})
    assertNone({stress=0.8, meditationRank=10, yogaRank=6, preferTraining="yoga"})
    assertCourse({boredom=45, preferTraining="meditation", meditationReady=false},
        "yoga", "boredom", "BOREDOM")
end)

test("hunger, thirst and malformed observations do not cause an optional course", function()
    assertNone({hunger=1, thirst=1, HUNGER=100, THIRST=100, yogaRank=10, meditationRank=10})
    assertNone({boredom="45", pain=1/0, stiffness=0/0, stress=60, yogaRank=10, meditationRank=10})
    assertNone({boredom=45, yogaRank=11})
    assertNone({boredom=45, yogaRank=5.5})
    assertNone({boredom=45, yogaReady="true"})
    assertNone({stress=0.8, meditationRank=10, yogaReady=false, boredom=false})
    assertNone({stress=0.8, meditationRank=10, yogaReady=false, pain=-1})
    assert(not Care.choose(nil))
end)

test("optional courses respect the next eligible timestamp and have a bounded wall budget", function()
    assertNone({boredom=45, nextAt=1001})
    assertNone({boredom=45, nextAt=0/0})
    assertNone({boredom=45, now=false})
    local novice = assertCourse({boredom=45, nextAt=1000}, "yoga", "boredom", "BOREDOM").maxMs
    local mid = assertCourse({boredom=45, yogaRank=6}, "yoga", "boredom", "BOREDOM").maxMs
    local master = assertCourse({boredom=45, yogaRank=10}, "yoga", "boredom", "BOREDOM").maxMs
    assert(210000 < novice and novice < mid and mid < master and 405000 < master and master <= 450000,
        "Allow a usual native finish even for nested poses, but bound a stuck workout")
    local stress = assertCourse({stress=0.50, meditationRank=6}, "meditation", "stress", "STRESS").maxMs
    assert(stress >= 10000 and stress <= 30000, "Stress only needs a short opportunity to relieve")
end)

test("receipt requires a strict numeric decrease of the measured target", function()
    local course = assertCourse({stiffness=25}, "yoga", "stiffness", "STIFFNESS")
    course.before = {stiffness=25, PAIN=30}
    assert(Care.improved(course, {stiffness=21, PAIN=31}))
    assert(not Care.improved(course, {stiffness=25, PAIN=10}))
    assert(not Care.improved(course, {PAIN=10}))
    assert(not Care.improved(course, {stiffness="21"}))

    course = assertCourse({pain=25}, "yoga", "pain", "PAIN")
    course.before = {PAIN=25}
    assert(Care.improved(course, {PAIN=24.99}))
    assert(not Care.improved(course, {pain=26, stiffness=0}))
    assert(not Care.improved(course, {PAIN=-1}))

    course = assertCourse({stress=0.8, meditationRank=6}, "meditation", "stress", "STRESS")
    course.before = 0.8
    assert(Care.improved(course, {stress=0.799}))
    assert(not Care.improved(course, {stress=0.8}))
    assert(not Care.improved(course, {stress=0/0}))
    assert(not Care.improved(course, {}))
    course.before = "0.8"
    assert(not Care.improved(course, {stress=0}))
    assert(not Care.improved({kind="meditation", need="hunger", before=1}, {hunger=0}))
end)

test("the new policy is opt-in and honors ordinary care and the existing cooldown", function()
    assertNone({withdrawal=0.51, meditationRank=10})
    assertNone({recovery="true", withdrawal=0.51, meditationRank=6})
    assertNone({recovery=false, hunger=0.20, mindfulEnabled=true, mindTier=0,
        confirmedFood=false, meditationRank=10})
    assertNone({recovery=true, withdrawal=0.51, reading="confirmed"})
    assertNone({recovery=true, withdrawal=0.51, painTreatment=true})
    assertNone({recovery=true, withdrawal=0.51, nextAt=1001})
end)

test("direct nicotine withdrawal relief is real at novice rank, with bounded native choices", function()
    assertNone({recovery=true, withdrawal=0.349})
    assertNone({recovery=true, withdrawal=35, meditationRank=10, yogaRank=10})
    assertNone({recovery=true, withdrawal=0.35, meditationReady=false, yogaReady=false})
    local meditation = assertCourse({recovery=true, withdrawal=0.35, mindfulEnabled=false},
        "meditation", "withdrawal", "NICOTINE_WITHDRAWAL")
    local yoga = assertCourse({recovery=true, withdrawal=0.51, meditationReady=false},
        "yoga", "withdrawal", "NICOTINE_WITHDRAWAL")
    local master = assertCourse({recovery=true, NICOTINE_WITHDRAWAL=0.40, meditationReady=false, yogaRank=10},
        "yoga", "withdrawal", "NICOTINE_WITHDRAWAL")
    assert(meditation.maxMs <= 30000 and yoga.maxMs > meditation.maxMs and master.maxMs > yoga.maxMs)
end)

test("withdrawal doesn't displace helpful training or opt into unsafe Meditation", function()
    assertNone({recovery=true, withdrawal=0.51, preferTraining="meditation"})
    assertNone({recovery=true, withdrawal=0.51, preferTraining="yoga"})
    assertNone({recovery=true, withdrawal=0.51, yogaReady=false, boredom=5.01})
    assertNone({recovery=true, withdrawal=0.51, yogaReady=false, pain=5.01})
    assertCourse({recovery=true, withdrawal=0.51, boredom=7, pain=7, preferTraining="meditation"},
        "yoga", "withdrawal", "NICOTINE_WITHDRAWAL")
    assertCourse({recovery=true, withdrawal=0.51, boredom=35}, "yoga", "boredom", "BOREDOM")
end)

test("withdrawal receipt measures nicotine directly rather than incidental stress relief", function()
    local course = assertCourse({recovery=true, withdrawal=0.51}, "meditation", "withdrawal", "NICOTINE_WITHDRAWAL")
    course.before = {NICOTINE_WITHDRAWAL=0.51, STRESS=0.80}
    assert(Care.improved(course, {NICOTINE_WITHDRAWAL=0.48, STRESS=0.82}))
    assert(Care.improved(course, {withdrawal=0.48}))
    assert(not Care.improved(course, {withdrawal=0.51, STRESS=0}))
    assert(not Care.improved(course, {withdrawal=-1, STRESS=0}))
    assert(not Care.improved({need="withdrawal", before=0.51}, {withdrawal=0.48}))
end)

local function strongInput(changes)
    local input = {recovery=true, mindfulEnabled=true, meditationRank=6, mindTier=0,
        hunger=0.20, pain=0, confirmedFood=false, painTreatment=false}
    for key, value in pairs(changes or {}) do input[key] = value end
    return input
end

test("Strong acquisition uses native rank, actual current tier, and stage-specific time bounds", function()
    local first = assertCourse(strongInput({hunger=0.15}), "meditation", "mindfulness", "HUNGER")
    local next = assertCourse(strongInput({hunger=0.30, mindTier=1, meditationRank=10}),
        "meditation", "mindfulness", "HUNGER")
    assert(first.recovery and first.target=="hunger" and first.fromTier==0 and first.targetTier==2)
    assert(next.recovery and next.target=="hunger" and next.fromTier==1 and next.targetTier==2)
    assert(first.maxMs == 240000 and next.maxMs == 180000,
        "Allow the 1x native tier countdown without creating an unbounded care job")
    assertNone(strongInput({meditationRank=5}))
    assertNone(strongInput({mindTier=2}))
    assertNone(strongInput({mindTier=3}))
    assertNone(strongInput({mindTier=0.2}))
    assertNone(strongInput({mindTier="1"}))
    local unknown = strongInput(); unknown.mindTier=nil
    assertNone(unknown)
    assertNone(strongInput({mindfulEnabled=false}))
    assertNone(strongInput({mindfulEnabled="yes"}))
end)

test("Strong is a mild fallback and never takes the place of an eligible meal or painkiller", function()
    assertNone(strongInput({hunger=0.149}))
    assertNone(strongInput({hunger=0.301, pain=12}))
    assertNone(strongInput({hunger=0.20, confirmedFood=true, pain=12}))
    local unknown = strongInput(); unknown.confirmedFood=nil
    assertNone(unknown)
    assertNone(strongInput({boredom=5.001}))
    assertNone(strongInput({pain=20, yogaReady=false}))
    assertNone(strongInput({preferTraining="meditation"}))
    assertNone(strongInput({meditationReady=false}))
    local pain = assertCourse(strongInput({hunger=0.05, pain=12, yogaReady=false, mindTier=1}),
        "meditation", "mindfulness", "PAIN")
    assert(pain.target=="pain" and pain.targetTier==2)
    assertNone(strongInput({hunger=0.05, pain=9.99, yogaReady=false}))
    assertNone(strongInput({hunger=0.05, pain=12, yogaReady=false, painTreatment=true}))
    assertNone(strongInput({hunger=0.05, pain=12, yogaReady=false, painReliefActive=true}))
    assertNone(strongInput({hunger=0.05, pain=12, preferTraining="yoga"}))
    assertCourse(strongInput({hunger=0.05, pain=15, yogaRank=3}), "yoga", "pain", "PAIN")
end)

test("native Strong tier acquisition is separate from real target mood relief", function()
    local course = assertCourse(strongInput({mindTier=1}), "meditation", "mindfulness", "HUNGER")
    course.before = {MIND_TIER=1, HUNGER=0.20, PAIN=0}
    assert(not Care.acquired(course, {MIND_TIER=1}))
    assert(not Care.acquired(course, {mindTier=1.99}))
    assert(Care.acquired(course, {MIND_TIER=2}))
    assert(Care.acquired(course, {mindTier=3}))
    assert(not Care.improved(course, {mindTier=1, HUNGER=0.13}), "A changed stat alone is not a Strong receipt")
    assert(not Care.improved(course, {mindTier=2, HUNGER=0.20}), "The new tier alone cannot prove relief")
    assert(not Care.improved(course, {mindTier=2, HUNGER=0.19999}), "Stat noise isn't relief")
    assert(Care.improved(course, {mindTier=2, HUNGER=0.19}))

    local pain = assertCourse(strongInput({hunger=0.05, pain=12, yogaReady=false}), "meditation", "mindfulness", "PAIN")
    pain.before = {mindTier=0, HUNGER=0.05, PAIN=12}
    assert(not Care.improved(pain, {MIND_TIER=2, PAIN=12, HUNGER=0.01}))
    assert(not Care.improved(pain, {MIND_TIER=2, PAIN=11.999}))
    assert(Care.improved(pain, {MIND_TIER=2, PAIN=11.8}))
end)

test("panic needs native Basic; blocked-sleep panic may qualify, Yoga is not a substitute", function()
    assertNone(strongInput({hunger=0.05, meditationRank=2, panic=35}))
    assertNone(strongInput({hunger=0.05, meditationRank=10, panic=35, meditationReady=false}))
    assertNone(strongInput({hunger=0.05, meditationRank=3, panic=24.99}))
    local basic=assertCourse(strongInput({hunger=0.05,meditationRank=3,panic=25}),"meditation","mindfulness","PANIC")
    assert(basic.target=="panic" and basic.targetTier==1 and basic.fromTier==0 and basic.maxMs==90000)
    basic=assertCourse(strongInput({hunger=0.05,meditationRank=3,panic=5,sleepBlocked=true}),"meditation","mindfulness","PANIC")
    assert(basic.targetTier==1)
    assertNone(strongInput({hunger=0.05,meditationRank=3,panic=4.99,sleepBlocked=true}))
end)

test("Perfect requires rank ten, minor safe health loss, and every prerequisite tier", function()
    assertNone(strongInput({hunger=0.05,meditationRank=9,health=88,healthSafe=true,mindTier=2}))
    assertNone(strongInput({hunger=0.05,meditationRank=10,health=74,healthSafe=true,mindTier=0}))
    assertNone(strongInput({hunger=0.05,meditationRank=10,health=87,healthSafe=false,mindTier=2}))
    assertNone(strongInput({hunger=0.05,meditationRank=10,health=95,healthSafe=true,mindTier=2}))
    local budgets={}
    for tier=0,2 do
        local attempt=assertCourse(strongInput({hunger=0.05,meditationRank=10,health=85,healthSafe=true,mindTier=tier}),
            "meditation","mindfulness","HEALTH")
        assert(attempt.target=="health" and attempt.targetTier==3 and attempt.fromTier==tier)
        budgets[tier]=attempt.maxMs
        assert(not Care.acquired(attempt,{mindTier=2}))
        assert(Care.acquired(attempt,{mindTier=3}))
    end
    assert(budgets[0]>budgets[1] and budgets[1]>budgets[2])
end)

test("an active native tier offers passive target observation even without admission or after cooldown", function()
    local input=sample(strongInput({hunger=0.05,meditationRank=3,mindTier=2,panic=50,meditationReady=false,nextAt=2000}))
    local attempt,plan=Care.choose(input)
    assert(not attempt and plan.target=="panic" and plan.targetTier==1)
    assert(Care.nativeTier(0.4,2)==0 and Care.nativeTier(0.4,3)==2 and Care.nativeTier(0.6,10)==3)
    assert(Care.nativeTier(1.01,10)==nil and Care.nativeTier(false,10)==nil)
    local w=assert(Care.watch(plan,{mindTier=2,PANIC=50}))
    assert(not Care.observed(w,{mindTier=3,PANIC=50,STRESS=0.1}))
    assert(Care.observed(w,{mindTier=0,PANIC=45}),"A contribution may flush after tier expiry")
    assert(not Care.observed(w,{mindTier=2,PANIC=51}))
    assert(not Care.watch({target="boredom",targetTier=1},{mindTier=3,BOREDOM=70}))
    assert(not Care.acquired({need="mindfulness",recovery=true,target="boredom",fromTier=0},{mindTier=3}))
    w=assert(Care.watch({target="health",targetTier=3},{mindTier=3,HEALTH=85}))
    assert(not Care.observed(w,{mindTier=3,HEALTH=84,PAIN=0}))
    assert(Care.observed(w,{mindTier=3,HEALTH=86}))
end)

test("passive deadlines follow the pinned mood flush, not a fixed 15 seconds or a badge timer", function()
    assert(Care.receiptMinutes("panic",2,24)==3)
    assert(Care.receiptMinutes("panic",9,24)==122)
    assert(Care.receiptMinutes("hunger",1,1)==122)
    assert(Care.receiptMinutes("pain",1,5)==12)
    assert(Care.receiptMinutes("withdrawal",1,24)==3)
    assert(Care.receiptMinutes("health",9,1)==3)
end)

print("PASS " .. count .. " practice-care policy cases")
