-- Shared admission for supplies and native hunger relief. A native first
-- moodle is evidence of a need, not a receipt or permission to force intake.
local Needs={careThreshold=0.15,restoredThreshold=0.000001}

function Needs.level(player,kind)
    return player:getMoodles():getMoodleLevel(kind=="water" and MoodleType.THIRST or MoodleType.HUNGRY)
end

function Needs.valueDue(value,level,threshold)
    return type(value)=="number" and value>Needs.restoredThreshold and value<=1
        and (value>=(threshold or Needs.careThreshold) or (level or 0)>=1)
end

function Needs.due(player,kind,threshold)
    local stat=kind=="water" and CharacterStat.THIRST or CharacterStat.HUNGER
    return Needs.valueDue(player:getStats():get(stat),Needs.level(player,kind),threshold)
end

-- Due is a reason to act between practices. Pressing is a reason to break one
-- off: the second moodle, where the game's own penalties begin. The first
-- moodle appears at 12-15% and is not worth a forfeited session.
function Needs.pressing(player,kind)
    return Needs.level(player,kind)>=2
end

function Needs.critical(player,kind)
    return Needs.level(player,kind)>=4
end

function Needs.lowHealth(player)
    return player:getBodyDamage():getOverallBodyHealth()<=50
end
-- A completed fixture action with no hydration receipt is not a drink.
-- Try that exact fixture once more after a delay, then only if the native
-- resource itself changes. Other fixtures and newly found items remain live.
function Needs.rejectDryReceipt(rejected,object,now)
    local old=rejected[object]
    local amount=object:getFluidAmount()
    local square=object.getSquare and object:getSquare()
    local again=type(old)=="table" and old.noIntake and old.amount==amount and old.square==square
    rejected[object]={noIntake=true,amount=amount,square=square,retryAt=not again and now+60000 or nil}
end

function Needs.supplyRejected(rejected,key,now)
    local entry=rejected[key]
    if type(entry)=="number" then
        if (now or getTimestampMs())<entry then return true end
        rejected[key]=nil
    elseif type(entry)=="table" and entry.noIntake then
        if (key.getSquare and key:getSquare())~=entry.square or key:getFluidAmount()~=entry.amount then
            rejected[key]=nil -- real refill/replacement/movement; admit only through ordinary safety checks
        else return not entry.retryAt or (now or getTimestampMs())<entry.retryAt end
    else return entry end
    return false
end
return Needs
