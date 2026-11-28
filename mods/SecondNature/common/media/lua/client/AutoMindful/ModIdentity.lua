-- Which of the mod's two IDs this save enabled. Saves and servers made before
-- 0.7.0 name it AutoMindful: they keep working unchanged, and the survivor is
-- told once how to move to the new ID. New saves only ever use SecondNature.
local Alerts = require "AutoMindful/Alerts"
local Log = require "AutoMindful/Log"
local Saved = require "AutoMindful/Saved"

local Identity = {current = "SecondNature", legacy = "AutoMindful", noticeKey = "SecondNatureLegacyNoticed"}

-- Build 42 may list an ID on its own or after a path ("\AutoMindful").
local function enabled(id)
    local ok, list = pcall(function() return getActivatedMods and getActivatedMods() end)
    if not ok or not list then return false end
    for index = 0, list:size() - 1 do
        local entry = tostring(list:get(index))
        if entry == id or entry:sub(-(#id + 1)) == "\\" .. id or entry:sub(-(#id + 1)) == "/" .. id then return true end
    end
    return false
end

-- "current" when the new ID is on (alone or beside the legacy one), "legacy"
-- when only the old one is, "unknown" when the game cannot say.
function Identity.mode()
    if enabled(Identity.current) then return "current" end
    if enabled(Identity.legacy) then return "legacy" end
    return "unknown"
end

-- The version of whichever ID is installed, the new one first.
function Identity.version()
    for _, id in ipairs({Identity.current, Identity.legacy}) do
        local ok, version = pcall(function()
            local mod = getModInfoByID and getModInfoByID(id)
            return mod and mod.getModVersion and mod:getModVersion()
        end)
        if ok and version then return version end
    end
    return nil
end

-- Once per save, on a save still using the old ID: it keeps working, and
-- this is how to switch. True when the notice was shown.
function Identity.notify(player)
    if not player or Identity.mode() ~= "legacy" then return false end
    if player:getModData()[Identity.noticeKey] then return false end
    Saved.set(player, Identity.noticeKey, true)
    -- On a server the host chooses the mods: nothing for the player to change.
    local online = isClient and isClient()
    Alerts.notice(player, "Second Nature has a new mod ID", online
        and ("This server uses the old one (AutoMindful) and keeps working as it is. The host can switch to SecondNature "
            .. "in the server's mod list at any time. Settings and progress carry over.")
        or ("This save uses the old one (AutoMindful) and keeps working as it is. To switch, enable Second Nature and turn off "
            .. "its legacy entry in this save's mods. Settings and progress carry over."))
    Log.event(player, "identity.legacy", "noticed", true)
    return true
end

return Identity
