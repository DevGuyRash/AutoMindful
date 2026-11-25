-- Per-survivor choices that are not global Mod Options, and where this
-- computer last put the window. Screen position is local, never character data.
local Options = require "AutoMindful/Options"
local Preferences = {}

local function saved(player)
    local data = player:getModData()
    data.AutoMindfulPreferences = data.AutoMindfulPreferences or {}
    return data.AutoMindfulPreferences
end

function Preferences.collectNearby(player)
    local value = saved(player).collectNearby
    return value == nil or value == true
end

-- One question with three answers replaces two overlapping switches: how far
-- may care reach for something it needs?
Preferences.ranges = {
    {id="walk", label="Walk to nearby supplies"},
    {id="reach", label="Only what is within reach"},
    {id="carried", label="Only what you carry"},
}

function Preferences.range(player)
    if Options.searchNearby() then return "walk" end
    return Preferences.collectNearby(player) and "reach" or "carried"
end

function Preferences.setRange(player, id)
    saved(player).collectNearby = id ~= "carried"
    Options.setSearchNearby(id == "walk")
end

local function file(player) return "AutoMindful/window-" .. tostring(player:getPlayerNum()) .. ".txt" end

local function integer(text, minimum)
    local n = tonumber(text)
    if n and n >= minimum and n <= 65535 then return math.floor(n + 0.5) end
end

-- Version 1 stored the old oversized window. Its position carries over; its
-- size does not, so nobody inherits a window shaped for the previous layout.
function Preferences.geometry(player)
    if getFileReader then
        local ok, line = pcall(function()
            local reader = getFileReader(file(player), false)
            if not reader then return nil end
            local value = reader:readLine()
            reader:close()
            return value
        end)
        if ok and type(line) == "string" and #line < 80 then
            local x, y, w, h, mini = line:match("^2 ([%d-]+) ([%d-]+) ([%d-]+) ([%d-]+) ([01])$")
            if mini then
                return {x=integer(x, -65535), y=integer(y, -65535), width=integer(w, 1), height=integer(h, 1), mini=mini == "1"}
            end
            x, y = line:match("^1 ([%d-]+) ([%d-]+) ")
            if x then return {x=integer(x, -65535), y=integer(y, -65535)} end
        end
    end
    return {}
end

function Preferences.saveGeometry(player, geometry)
    if not getFileWriter then return false end
    local function field(n) return n and string.format("%d", n) or "-" end
    local ok, done = pcall(function()
        local writer = getFileWriter(file(player), true, false)
        if not writer then return false end
        writer:write(table.concat({"2", field(geometry.x), field(geometry.y), field(geometry.width), field(geometry.height),
            geometry.mini and "1" or "0"}, " ") .. "\n")
        writer:close()
        return true
    end)
    return ok and done == true
end

return Preferences
