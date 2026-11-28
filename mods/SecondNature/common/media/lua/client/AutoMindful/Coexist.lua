-- Other automation that owns the survivor for now. While it runs, Autopilot
-- keeps to what cannot wait: such mods often wait for an empty action queue,
-- so a long optional practice of ours would hold them up until it ended.
local Coexist = {}

-- Auto All (exercise, and its other jobs) publishes the job that holds each
-- player's slot: AutoAll.tasks[playerNum]. Returns a name for the log and the
-- window, or nil when nothing else is in charge.
function Coexist.owner(player)
    local ok, name = pcall(function()
        if type(AutoAll) ~= "table" then return nil end
        if type(AutoAll.isRunning) == "function" and not AutoAll.isRunning(player) then return nil end
        local tasks = AutoAll.tasks
        local task = type(tasks) == "table" and tasks[player:getPlayerNum()]
        if type(task) ~= "table" or task.active == false then return nil end
        return "Auto All" .. (task.kind and (" (" .. tostring(task.kind) .. ")") or "")
    end)
    return ok and name or nil
end

return Coexist
