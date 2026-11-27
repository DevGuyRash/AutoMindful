package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
local Coexist = require "AutoMindful/Coexist"
local player = {getPlayerNum=function() return 0 end}
assert(Coexist.owner(player) == nil, "No Auto All: nothing else is in charge")
AutoAll = {tasks = {}}
function AutoAll.isRunning(p, kind)
    local task = AutoAll.tasks[p:getPlayerNum()]
    return task ~= nil and task.active == true and (kind == nil or task.kind == kind)
end
assert(Coexist.owner(player) == nil, "Auto All loaded but idle")
AutoAll.tasks[0] = {kind = "exercise", active = true}
assert(Coexist.owner(player) == "Auto All (exercise)", tostring(Coexist.owner(player)))
AutoAll.tasks[0].active = false
assert(Coexist.owner(player) == nil, "A stopped job no longer counts")
AutoAll.tasks[0] = {kind = "farming", active = true}
assert(Coexist.owner({getPlayerNum=function() return 1 end}) == nil, "Another player's job is theirs")
AutoAll.isRunning = function() error("broken") end
assert(Coexist.owner(player) == nil, "A broken Auto All never breaks Autopilot")
print("PASS Auto All's running job is seen, stopped or foreign jobs are not, and errors are contained")
