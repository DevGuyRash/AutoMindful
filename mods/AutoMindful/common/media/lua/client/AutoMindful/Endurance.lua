local Endurance = {}

function Endurance.read(player)
    if not player or not CharacterStat or not CharacterStat.ENDURANCE then return nil end
    local ok, value = pcall(function()
        return player:getStats():get(CharacterStat.ENDURANCE)
    end)
    if ok and type(value) == "number" and value >= 0 and value <= 1 then return value end
end

function Endurance.full(value)
    return value == 1
end

return Endurance
