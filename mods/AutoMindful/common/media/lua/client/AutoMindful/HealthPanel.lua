-- Second Nature inside the game's own Health tab: a button to the Body tab,
-- a line on weight under the body, and the one-click care on each part's
-- right-click menu. Every hook calls the game's (and other mods') version
-- first; nothing is shown while the panel is looking after someone else.
require "ISUI/ISButton"
require "ISUI/ISToolTip"
local Clock = require "AutoMindful/Clock"
local FirstAid = require "AutoMindful/FirstAid"
local Nutrition = require "AutoMindful/Nutrition"
local Theme = require "AutoMindful/Theme"
local Treat = require "AutoMindful/Treat"
local colors = Theme.colors

AutoMindful = AutoMindful or {}
local Panel = AutoMindful.HealthPanel or {}
AutoMindful.HealthPanel = Panel
local shared = AutoMindful.healthPanelHook or {}
AutoMindful.healthPanelHook = shared

local function open(player, card)
    local window = AutoMindful.UI.open(player)
    window.focusCard = card
    window:show("body")
    window:invalidate(true)
end

local function tooltip(text)
    local tip = ISToolTip:new()
    tip:initialise()
    tip:setVisible(false)
    tip.description = text
    return tip
end

-- One line on nutrition for the strip under the body picture, longest
-- first: the line drops whole phrases to fit, never part of a word.
function Panel.summary(player)
    local s = Nutrition.read(player)
    if not s then return nil end
    local weight = string.format("%.1f kg", s.weight)
    local banded = weight .. ", " .. s.band.label:lower()
    local full = s.perDay ~= 0 and (banded .. string.format(", %s%.2f kg a day", s.perDay > 0 and "+" or "-", math.abs(s.perDay))) or banded
    return {full, banded, weight}, s.band.tone
end

local function addButton(panel)
    if panel.secondNature or not panel.fitness then return end
    local font = UIFont.Small
    local label = Theme.brand
    local button = ISButton:new(panel.fitness:getRight() + 6, panel.fitness:getY(), Theme.width(label, font) + 16, panel.fitness:getHeight(),
        label, panel, function() open(panel.character, "nutrition") end)
    button:initialise()
    button:instantiate()
    button.tooltip = "Nutrition, wounds and what is coming up, in the Second Nature window."
    panel:addChild(button)
    panel.secondNature = button
end

local tones = {good = colors.good, warn = colors.warn, bad = colors.bad, muted = colors.muted}

-- Each frame: the button right after Fitness (other mods line theirs up
-- after the last button; following them back would chase them off the
-- panel), the weight line in the bottom strip. Only the survivor's own panel.
local function decorate(panel)
    local button = panel.secondNature
    if not button then return end
    local mine = not panel.otherPlayer and panel.character and panel.character:isLocalPlayer()
    button:setVisible(mine and panel.fitness:getIsVisible())
    if not mine then return end
    button:setX(panel.fitness:getRight() + 6)
    button:setY(panel.fitness:getY())
    local texts, tone = Panel.summary(panel.character)
    button.tooltip = (texts and (texts[1] .. ". ") or "") .. "Nutrition, wounds and what is coming up, in the Second Nature window."
    if texts then
        -- Right of the game's own hint on the bottom line, never over it.
        local c = tones[tone] or colors.muted
        local line = Theme.line()
        local hint = Theme.width(getText("IGUI_health_RightClickTreatement")) + 24
        local room = panel.width - hint - 8
        for _, text in ipairs(texts) do
            if Theme.width(text) <= room then
                panel:drawTextRight(text, panel.width - 8, panel.height - line - (UI_BORDER_SPACING or 5), c.r, c.g, c.b, 0.9, UIFont.Small)
                break
            end
        end
    end
end

local function menuFor(panel, part)
    local player = panel.character
    if panel.otherPlayer or not player or not player:isLocalPlayer() then return end
    local context = getPlayerContextMenu and getPlayerContextMenu(player:getPlayerNum())
    if not context or panel.blockingMessage then return end
    local allowed, why = Treat.allowed(player)
    local plan = Treat.plan(player, part)
    local name = FirstAid.partName(part)
    local option = context:addOption(Theme.brand .. ": treat the " .. name:lower(), player, function() Treat.request(player, part) end)
    if option then
        local cost = Treat.cost(plan)
        local bleeder = Treat.bleedingElsewhere(player, part)
        if plan.count == 0 or not allowed then option.notAvailable = true end
        local text = plan.count > 0 and (cost .. ". <LINE> " .. Treat.tip(plan, bleeder and ("The bleeding " .. bleeder:lower() .. " is dressed first.") or nil))
            or (#plan.missing > 0 and ("Not found nearby: " .. table.concat(plan.missing, "; ") .. ".") or "Nothing to do for it now.")
        if not allowed then text = why .. " <LINE> " .. text end
        option.toolTip = tooltip(text)
    end
    local dressings = Treat.dressings(player)
    if (part:bandaged() or plan.count > 0) and #dressings > 0 and allowed then
        local parent = context:addOption(Theme.brand .. ": " .. (part:bandaged() and "fresh dressing" or "dress with"))
        local sub = ISContextMenu:getNew(context)
        context:addSubMenu(parent, sub)
        for _, choice in ipairs(dressings) do
            sub:addOption(choice.name .. " (" .. choice.where .. ")", player, function()
                Treat.request(player, part, {change = true, prefer = choice.item})
            end)
        end
    end
    local parts, count = player:getBodyDamage():getBodyParts(), 0
    for index = 0, parts:size() - 1 do if FirstAid.danger(player, parts:get(index)) > 0 then count = count + 1 end end
    if count > 1 then
        local all = context:addOption(Theme.brand .. ": treat all " .. count .. " wounds", player, function() Treat.request(player, nil) end)
        if all and not allowed then all.notAvailable = true; all.toolTip = tooltip(why) end
    end
    -- The game hides a menu it left empty; ours may have filled it, and a
    -- joypad needs the focus the game would have given it.
    if not context:isEmpty() and not context:getIsVisible() then
        context:setVisible(true)
        local joypad = JoypadState and JoypadState.players and JoypadState.players[player:getPlayerNum() + 1]
        if joypad and updateJoypadFocus then
            context.mouseOver, context.origin = 1, panel
            joypad.focus = context
            updateJoypadFocus(joypad)
        end
    end
end

-- Wraps a method so the game's (and other mods') version always runs
-- first, and ours runs once however many times it was wrapped since.
local function chain(class, name, after)
    if class[name] == shared[name] then return end
    local original = class[name]
    shared.depth = shared.depth or {}
    local wrapper = function(self, ...)
        local depth = shared.depth
        depth[name] = (depth[name] or 0) + 1
        local ok, err = pcall(original, self, ...)
        depth[name] = depth[name] - 1
        if not ok then error(err, 0) end
        if depth[name] == 0 then
            local done, failure = pcall(after, self, ...)
            if not done and not shared.logged then
                shared.logged = true
                print("[AutoMindful] Health panel " .. name .. " skipped: " .. tostring(failure))
            end
        end
    end
    shared[name] = wrapper
    class[name] = wrapper
end

function Panel.install()
    local class = ISHealthPanel
    if not class then return end
    chain(class, "createChildren", addButton)
    chain(class, "render", function(self)
        if not self.secondNature then addButton(self) end
        decorate(self)
    end)
    -- The game sizes the tab to its Fitness button; ours sits past it.
    chain(class, "update", function(self)
        local button = self.secondNature
        if button and button:getIsVisible() and self.setWidthAndParentWidth and button:getRight() + 8 > self.width then
            self:setWidthAndParentWidth(button:getRight() + 8)
        end
    end)
    chain(class, "doBodyPartContextMenu", menuFor)
end

return Panel
