package.path = "mods/SecondNature/common/media/lua/client/?.lua;" .. package.path
local notices, events = {}, {}
package.loaded["AutoMindful/Alerts"] = {notice=function(_, title, detail) notices[#notices + 1] = {title=title, detail=detail} end}
package.loaded["AutoMindful/Log"] = {event=function(_, code) events[#events + 1] = code end}
package.loaded["AutoMindful/Saved"] = {set=function(player, key, value) player.data[key] = value end}
local Identity = require "AutoMindful/ModIdentity"
local function list(t) return {size=function() return #t end, get=function(_, i) return t[i + 1] end} end
local player = {data={}}
function player:getModData() return self.data end
local active = {}
function getActivatedMods() return list(active) end
local versions = {}
function getModInfoByID(id) return versions[id] and {getModVersion=function() return versions[id] end} or nil end

active = {"LifestyleHobbies", "SecondNature"}
assert(Identity.mode() == "current" and not Identity.notify(player) and #notices == 0, "A new save: no notice")
active = {"\\SecondNature", "\\AutoMindful"}
assert(Identity.mode() == "current" and not Identity.notify(player), "Both enabled, path-prefixed: still current, no notice")
active = {"\\AutoMindful"}
assert(Identity.mode() == "legacy", "Only the old ID: a legacy save")
assert(Identity.notify(player) and #notices == 1 and notices[1].detail:find("legacy entry", 1, true), "Told how to switch")
assert(not Identity.notify(player) and #notices == 1, "Only once per save")
active = {"AutoMindfulFixture"}
assert(Identity.mode() == "unknown", "A different mod whose ID merely starts the same is not ours")
function getActivatedMods() error("broken") end
assert(Identity.mode() == "unknown", "A broken list never breaks the mod")
versions = {AutoMindful = "0.6.0"}
assert(Identity.version() == "0.6.0", "The legacy copy's version when only it answers")
versions = {AutoMindful = "0.6.0", SecondNature = "0.7.0"}
assert(Identity.version() == "0.7.0", "The new ID first")
print("PASS the mod knows which ID a save uses, tells a legacy save once how to switch, and reads either version")
