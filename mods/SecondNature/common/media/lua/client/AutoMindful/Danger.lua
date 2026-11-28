-- How dangerous this moment is, in three steps rather than one switch. A
-- zombie in the street outside is a reason to stay put and keep quiet, not a
-- reason to die of thirst beside a full bottle.
local Danger = {}

-- "engaged": hands off, the player or the survivor's legs are needed.
-- "wary": stay where you are; only care that needs no walking and no noise.
function Danger.read(player)
    if player:isOnFire() then return "engaged", "the survivor is on fire" end
    local stats = player:getStats()
    if stats:getNumChasingZombies() > 0 then return "engaged", "zombies are after the survivor" end
    if stats:getNumVeryCloseZombies() > 0 then return "engaged", "zombies are nearby" end
    if stats:getNumVisibleZombies() > 0 then return "wary", "zombies are nearby" end
    return "clear"
end

-- Bleeding is an injury to treat, not a danger to wait out.
function Danger.bleeding(player)
    return player:getBodyDamage():getNumPartsBleeding() > 0
end

return Danger
