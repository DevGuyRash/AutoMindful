package.path = "mods/SecondNature/common/media/lua/client/?.lua;" .. (package.path or "")
local Cycle = require "AutoMindful/TrainingCycle"

local function entry(level, fraction, eligible, needs, rawXP)
    return {needed = needs ~= false, eligible = eligible == true,
        progress = {level = level, fraction = fraction, total = rawXP, current = rawXP}}
end

local count = 0
local function test(name, run)
    run()
    count = count + 1
    print("PASS " .. name)
end

local function assertPlan(plan, kind, preferred, owed, reason)
    assert(plan.kind == kind and plan.preferred == preferred and plan.owed == owed and plan.reason == reason,
        "Unexpected plan: " .. tostring(plan.kind) .. ", " .. tostring(plan.preferred) .. ", "
            .. tostring(plan.owed) .. ", " .. tostring(plan.reason))
end

test("alternate uses strict native history and a deterministic first skill", function()
    local med, yoga = entry(8, 0.25, true), entry(3, 0.5, true)
    assertPlan(Cycle.choose("alternate", nil, nil, med, yoga), "meditation", "meditation", nil, "ready")
    local last, owed = Cycle.complete(nil, nil, "meditation")
    assertPlan(Cycle.choose("alternate", last, owed, med, yoga), "yoga", "yoga", nil, "ready")
    last, owed = Cycle.complete(last, owed, "yoga")
    assertPlan(Cycle.choose("alternate", last, owed, med, yoga), "meditation", "meditation", nil, "ready")
end)

test("lowest and closest compare rank plus next-rank fraction, not raw XP", function()
    local med, yoga = entry(8, 0.25, true, true, 47), entry(3, 0.8, true, true, 800)
    assertPlan(Cycle.choose("lowest", "yoga", nil, med, yoga), "yoga", "yoga", nil, "ready")
    assertPlan(Cycle.choose("closest", "meditation", nil, med, yoga), "meditation", "meditation", nil, "ready")
    med, yoga = entry(4, 0.2, true, true, 800), entry(4, 0.8, true, true, 47)
    assertPlan(Cycle.choose("lowest", "meditation", nil, med, yoga), "meditation", "meditation", nil, "ready")
    assertPlan(Cycle.choose("closest", "yoga", nil, med, yoga), "yoga", "yoga", nil, "ready")
end)

test("tied or unavailable progress falls back to alternation without inventing XP", function()
    local med, yoga = entry(4, 0.5, true), entry(4, 0.5, true)
    for _, policy in ipairs({"lowest", "closest"}) do
        assertPlan(Cycle.choose(policy, "meditation", nil, med, yoga), "yoga", "yoga", nil, "ready")
        assertPlan(Cycle.choose(policy, "yoga", nil, med, yoga), "meditation", "meditation", nil, "ready")
        for _, sample in ipairs({false, {level = "0", fraction = 0}, {level = -1, fraction = 0.1},
                {level = 3.5, fraction = 0.1}, {level = 3, fraction = "0.1"},
                {level = 3, fraction = 0/0}, {level = 3, fraction = 1/0}, {level = 3}}) do
            yoga.progress = sample
            assertPlan(Cycle.choose(policy, "meditation", nil, med, yoga), "yoga", "yoga", nil, "ready")
        end
        yoga.progress = {level = 4, fraction = 0.5}
    end
end)

test("a temporarily blocked Yoga turn survives repeated real Meditation fallback completions", function()
    for _, policy in ipairs({"alternate", "lowest", "closest"}) do
        local med, yoga = entry(1, 0, true), entry(2, 0.5, false)
        if policy == "lowest" then med.progress.level = 8 end
        local last, owed = "meditation", nil
        for i = 1, 4 do
            local blocked = Cycle.choose(policy, last, owed, med, yoga)
            assertPlan(blocked, "meditation", "yoga", "yoga", "fallback")
            last, owed = Cycle.complete(last, blocked.owed, "meditation")
            assert(last == "meditation" and owed == "yoga")
        end
        yoga.eligible = true
        -- Even a changed rank score cannot displace an earlier earned chance.
        med.progress.level = policy == "lowest" and 0 or 8
        assertPlan(Cycle.choose(policy, last, owed, med, yoga), "yoga", "yoga", "yoga", "ready")
        last, owed = Cycle.complete(last, owed, "yoga")
        assert(last == "yoga" and owed == nil)
    end
end)

test("a blocked Meditation turn is symmetric and a different completion cannot spend it", function()
    local med, yoga = entry(1, 0, false), entry(2, 0.5, true)
    local plan = Cycle.choose("lowest", "yoga", nil, med, yoga)
    assertPlan(plan, "yoga", "meditation", "meditation", "fallback")
    local last, owed = Cycle.complete("yoga", plan.owed, "yoga")
    assert(last == "yoga" and owed == "meditation")
    med.eligible, yoga.eligible = true, false
    assertPlan(Cycle.choose("lowest", last, owed, med, yoga), "meditation", "meditation", "meditation", "ready")
end)

test("when both gates deny admission the selected debt stays put without starting an action", function()
    local med, yoga = entry(1, 0, false), entry(2, 0.5, false)
    assertPlan(Cycle.choose("lowest", nil, nil, med, yoga), nil, "meditation", "meditation", "blocked")
    assertPlan(Cycle.choose("lowest", nil, "yoga", med, yoga), nil, "yoga", "yoga", "blocked")
    assertPlan(Cycle.choose("lowest", nil, "yoga", nil, yoga), nil, "yoga", "yoga", "blocked")
end)

test("earned XP, posture and admitted-but-not-completed work do not spend a turn", function()
    local med, yoga = entry(8, 0.25, true), entry(3, 0.5, true)
    local last, owed = "meditation", "yoga"
    yoga.progress.fraction, yoga.progress.level = 0.9, 9
    assertPlan(Cycle.choose("lowest", last, owed, med, yoga), "yoga", "yoga", "yoga", "ready")
    last, owed = Cycle.complete(last, owed, "ISUnequipAction")
    assert(last == "meditation" and owed == "yoga")
    last, owed = Cycle.complete(last, owed, nil)
    assert(last == "meditation" and owed == "yoga")
end)

test("capped or no longer needed skills cannot be admitted or keep owed turns", function()
    local med, yoga = entry(8, 0.25, true), entry(10, 1, true)
    assertPlan(Cycle.choose("closest", "meditation", "yoga", med, yoga), "meditation", "meditation", nil, "ready")
    yoga.progress = {capped = true}
    assertPlan(Cycle.choose("alternate", "meditation", "yoga", med, yoga), "meditation", "meditation", nil, "ready")
    med.needed, yoga.needed = false, false
    assertPlan(Cycle.choose("closest", "meditation", "yoga", med, yoga), nil, nil, nil, "complete")
    assertPlan(Cycle.choose("alternate", nil, nil, nil, false), nil, nil, nil, "complete")
end)

test("normalization rejects unknown settings and unsafe eligibility coercion", function()
    assert(Cycle.normalizePolicy("alternate") == "alternate" and Cycle.normalizePolicy("lowest") == "lowest"
        and Cycle.normalizePolicy("closest") == "closest")
    assert(Cycle.normalizePolicy(nil) == "alternate" and Cycle.normalizePolicy("unknown") == "alternate"
        and Cycle.normalizePolicy(3) == "alternate")
    local med, yoga = entry(2, 0, true), entry(1, 0, true)
    assertPlan(Cycle.choose("unknown", nil, "invalid", med, yoga), "meditation", "meditation", nil, "ready")
    med.eligible, yoga.needed = "true", 1
    assertPlan(Cycle.choose(nil, "invalid", "invalid", med, yoga), nil, "meditation", "meditation", "blocked")
end)

test("all policies never admit a missing, excluded, or native-blocked skill or mutate inputs", function()
    for _, policy in ipairs({"alternate", "lowest", "closest"}) do
        for _, last in ipairs({false, "meditation", "yoga"}) do
            for _, oldDebt in ipairs({false, "meditation", "yoga"}) do
                for mMask = 0, 3 do
                    for yMask = 0, 3 do
                        local mNeeds, yNeeds = mMask >= 2, yMask >= 2
                        local mReady, yReady = mMask % 2 == 1, yMask % 2 == 1
                        local med, yoga = entry(3, 0.1, mReady, mNeeds), entry(2, 0.9, yReady, yNeeds)
                        local plan = Cycle.choose(policy, last, oldDebt, med, yoga)
                        assert((plan.kind == nil) == (not (mNeeds and mReady) and not (yNeeds and yReady)))
                        if plan.kind == "meditation" then assert(mNeeds and mReady)
                        elseif plan.kind == "yoga" then assert(yNeeds and yReady) end
                        if (oldDebt == "meditation" and mNeeds) or (oldDebt == "yoga" and yNeeds) then
                            assert(plan.owed == oldDebt and plan.preferred == oldDebt)
                        end
                        assert(med.progress.fraction == 0.1 and yoga.progress.fraction == 0.9
                            and med.needed == mNeeds and yoga.needed == yNeeds
                            and med.eligible == mReady and yoga.eligible == yReady)
                    end
                end
            end
        end
    end
end)

print("PASS " .. count .. " training cycle cases (432 policy/history/gate combinations)")
