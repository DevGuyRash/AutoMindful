local EnduranceGoal = {}

function EnduranceGoal.read(player)
    if not player or not CharacterStat or not CharacterStat.ENDURANCE then return nil end
    local ok, value = pcall(function()
        return player:getStats():get(CharacterStat.ENDURANCE)
    end)
    if ok and type(value) == "number" and value >= 0 and value <= 1 then return value end
end

function EnduranceGoal.full(value)
    return value == 1
end

-- Five minutes without a new measurable high, counting only consecutive
-- observations of running meditation. An unobserved gap is not active time.
function EnduranceGoal.observe(observer, value, now, active)
    if not active or value == nil then
        observer.lastActiveAt = nil
        return false
    end
    if not observer.best or value > observer.best + 0.000001 then
        observer.best = value
        observer.noGainMs = 0
    elseif observer.lastActiveAt then
        local elapsed = now - observer.lastActiveAt
        if elapsed > 0 and elapsed <= 2000 then
            observer.noGainMs = (observer.noGainMs or 0) + elapsed
        end
    end
    observer.lastActiveAt = now
    return (observer.noGainMs or 0) >= 300000
end

return EnduranceGoal
