local Window = require "AutoMindful/Window"
local Options = require "AutoMindful/Options"
local Theme = require "AutoMindful/Theme"
local Log = require "AutoMindful/Log"
local Presence = require "AutoMindful/Presence"
local WorldMenu = require "AutoMindful/WorldMenu"
require "XpSystem/ISUI/ISCharacterInfo"
require("AutoMindful/SkillsPane").install()
local ZenMoodle = require "AutoMindful/ZenMoodle"
ZenMoodle.install()
Log.setLevelSource(Options.logLevel)

local function version(id)
    local mod = getModInfoByID and getModInfoByID(id)
    return mod and mod.getModVersion and mod:getModVersion()
end

local function onGameStart()
    Log.start(version("AutoMindful"), version("LifestyleHobbies"))
    Theme.preload()
    ZenMoodle.onPlayerReady()
    WorldMenu.install()
end

local function keyPressed(key)
    Presence.key(getTimestampMs())
    if getCore():isDoingTextEntry() or (ISChat and ISChat.focused) then return end
    if key == 0 or key ~= Options.windowKey() then return end
    local player = getSpecificPlayer(0)
    if player and not player:isDead() then Window.toggle(player) end
end

local old = AutoMindful.uiEvents
if old then
    Events.OnFillWorldObjectContextMenu.Remove(old.context)
    Events.OnKeyPressed.Remove(old.key)
    Events.OnGameStart.Remove(old.start)
    if old.playerReady then Events.OnCreatePlayer.Remove(old.playerReady) end
    if old.save then
        Events.OnSave.Remove(old.save)
        Events.EveryOneMinute.Remove(old.save)
    end
end
AutoMindful.uiEvents = {context=WorldMenu.fill, key=keyPressed, start=onGameStart, playerReady=ZenMoodle.onPlayerReady, save=Log.flush}
Events.OnFillWorldObjectContextMenu.Add(WorldMenu.fill)
Events.OnKeyPressed.Add(keyPressed)
Events.OnGameStart.Add(onGameStart)
Events.OnCreatePlayer.Add(ZenMoodle.onPlayerReady)
Events.OnSave.Add(Log.flush)
Events.EveryOneMinute.Add(Log.flush) -- the last lines of a quiet spell
