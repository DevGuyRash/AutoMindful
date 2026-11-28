-- One click for a wound, or for all of them, wherever the player asks (the
-- Body tab, the Health panel): what it will do, step by step and with what,
-- what it would use up, and the request itself. The planning is FirstAid's,
-- the doing Recovery's; this only words it and asks.
local Coexist = require "AutoMindful/Coexist"
local Controller = require "AutoMindful/Controller"
local Danger = require "AutoMindful/Danger"
local FirstAid = require "AutoMindful/FirstAid"
local Log = require "AutoMindful/Log"
local Options = require "AutoMindful/Options"
local Preferences = require "AutoMindful/Preferences"

local Treat = {}

-- As far as first aid looks: the search radius when it may collect nearby.
function Treat.radius(player)
    return (Preferences.collectNearby(player) or Options.searchNearby()) and Options.searchRadius() or 0
end

local verbs = {
    glass = "Pull the glass out with %s", bullet = "Take the bullet out with %s", disinfect = "Disinfect with %s",
    stitch = "Stitch with %s", splint = "Splint with %s", burn = "Clean the burn with %s", poultice = "Apply %s",
}

-- One step in words, with the item and where it is.
function Treat.stepText(step, covered)
    local item = step.item or "it"
    local where = step.walk and " (walks for it)" or (step.item and not step.carried) and " (within reach)" or ""
    if step.kind == "unbandage" then return "Take the old dressing off" end
    if step.kind == "bandage" then return (covered and "Change the dressing for " or "Dress it with ") .. item .. where end
    if step.kind == "glass" and step.hands then return "Pull the glass out by hand (it hurts more)" end
    if step.kind == "unstitch" then return "Take the healed stitches out" end
    if step.kind == "unsplint" then return "Take the splint off the healed bone" end
    return string.format(verbs[step.kind] or "%s", item) .. where
end

-- What one part's care would be: {steps (words), missing (words), items, walk, count}.
function Treat.plan(player, part, choice)
    local preview = FirstAid.preview(player, part, Treat.radius(player), choice)
    local plan = {steps = {}, missing = preview.missing, items = {}, walk = false, count = 0, danger = preview.danger}
    for _, step in ipairs(preview.steps) do
        plan.steps[#plan.steps + 1] = Treat.stepText(step, preview.covered)
        if step.kind ~= "unbandage" then plan.count = plan.count + 1 end
        if step.item then plan.items[#plan.items + 1] = step.item end
        plan.walk = plan.walk or step.walk
    end
    return plan
end

-- A short line on the cost: "3 steps, uses Bandage and Disinfectant, walks".
function Treat.cost(plan)
    if plan.count == 0 then return nil end
    local text = plan.count .. (plan.count == 1 and " step" or " steps")
    if #plan.items > 0 then
        local names, seen = {}, {}
        for _, name in ipairs(plan.items) do if not seen[name] then seen[name] = true; names[#names + 1] = name end end
        text = text .. ", uses " .. table.concat(names, ", ")
    end
    return text .. (plan.walk and ", walks for supplies" or "")
end

-- The plan as a tooltip: numbered steps, then what is missing.
function Treat.tip(plan, extra)
    local lines = {}
    for index, step in ipairs(plan.steps) do lines[#lines + 1] = index .. ". " .. step end
    if #plan.missing > 0 then lines[#lines + 1] = "Not found nearby: " .. table.concat(plan.missing, "; ") .. "." end
    if extra then lines[#lines + 1] = extra end
    return table.concat(lines, " <LINE> ")
end

-- Whether the player may ask now, and why not. Danger close at hand waits;
-- with zombies in view only a dressing where the survivor stands is done.
function Treat.allowed(player)
    if not player or player:isDead() then return false, "No survivor." end
    if player:isAsleep() then return false, "The survivor is asleep." end
    if Coexist.owner(player) then return false, "Auto All is looking after the survivor now." end
    local level, reason = Danger.read(player)
    if level == "engaged" then return false, "Waits: " .. (reason or "danger is close") .. "." end
    return true, level == "wary" and "Zombies are in view: only a dressing where the survivor stands, until they are gone." or nil
end

-- Another wound bleeds: it is dressed first, whatever was asked.
function Treat.bleedingElsewhere(player, part)
    local parts = player:getBodyDamage():getBodyParts()
    for index = 0, parts:size() - 1 do
        local other = parts:get(index)
        if other ~= part and other:bleeding() and not other:bandaged() then return FirstAid.partName(other) end
    end
end

function Treat.request(player, part, choice)
    local ok, reason = Treat.allowed(player)
    if not ok then return false, reason end
    local started, message = Controller.treat(player, part, choice)
    Log.event(player, "ui.treat", "part", part and FirstAid.partName(part) or "all", "change", choice and choice.change,
        "started", started, "message", message)
    local window = AutoMindful and AutoMindful.UI and AutoMindful.UI.windows[player:getPlayerNum()]
    if window then
        window.startError = not started and message or nil
        window:invalidate()
    end
    return started, message
end

-- Dressings to choose from, one of each kind, best first: {item, name, where}.
function Treat.dressings(player)
    local out, seen = {}, {}
    -- Clean ones only: a dirty dressing on a wound is how infection starts.
    local list = FirstAid.picker(player, Treat.radius(player))("clean", {list = true}) or {}
    for _, entry in ipairs(list) do
        local item = entry.item
        local kind = item:getFullType()
        if not seen[kind] then
            seen[kind] = true
            out[#out + 1] = {item = item, name = item:getDisplayName(),
                where = entry.carried and "carried" or entry.reach and "within reach" or "walks for it"}
        end
    end
    return out
end

-- The dressing on a part now, by name, or nil.
function Treat.dressingName(part)
    if not part:bandaged() then return nil end
    local kind = part:getBandageType()
    if not kind or kind == "" then return nil end
    local ok, name = pcall(function()
        local script = getScriptManager():FindItem(kind)
        return script and script:getDisplayName()
    end)
    return ok and name or kind
end

return Treat
