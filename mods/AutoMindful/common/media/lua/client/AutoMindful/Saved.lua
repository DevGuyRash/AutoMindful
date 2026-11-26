-- What a survivor keeps across saves. In multiplayer the server holds the
-- survivor, so it has to be told.
local Saved = {}

-- Returns false when nothing changed, so nothing is sent.
function Saved.set(player, key, value)
    local data = player:getModData()
    -- A table changed in place is still news; only a same plain value is not.
    if data[key] == value and type(value) ~= "table" then return false end
    data[key] = value
    if isClient() and player.transmitModData then pcall(player.transmitModData, player) end
    return true
end

return Saved
