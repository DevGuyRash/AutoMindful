require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTickBox"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "ISUI/ISRichTextPanel"
require "ISUI/ISProgressBar"
local Controller = require "AutoMindful/Controller"
local Decisions = require "AutoMindful/DecisionHistory"
local Options = require "AutoMindful/Options"
local Progress = require "AutoMindful/Progress"
local Wellness = require "AutoMindful/WellnessInfo"

AutoMindful = AutoMindful or {}
local UI = ISCollapsableWindow:derive("AutoMindfulWindow")
AutoMindful.UI = UI
UI.windows = {}

local palette = {
    background = {r=0.09, g=0.12, b=0.105, a=0.97},
    panel = {r=0.11, g=0.15, b=0.13, a=0.96},
    border = {r=0.27, g=0.32, b=0.29, a=1},
    text = {r=0.88, g=0.90, b=0.86, a=1},
    muted = {r=0.65, g=0.71, b=0.67, a=1},
    meditation = {r=0.55, g=0.74, b=0.64, a=1},
    yoga = {r=0.82, g=0.69, b=0.45, a=1},
    water = {r=0.47, g=0.69, b=0.78, a=1},
    missing = {r=0.85, g=0.47, b=0.42, a=1},
    value = {r=0.60, g=0.83, b=0.94, a=1},
    caution = {r=0.96, g=0.65, b=0.53, a=1},
    gain = {r=0.45, g=0.88, b=0.56, a=1},
}

local function preferences(player)
    local data = player:getModData()
    data.AutoMindfulPreferences = data.AutoMindfulPreferences or {}
    return data.AutoMindfulPreferences
end

local function useAdjacent(player)
    local saved = preferences(player).collectNearby
    return saved == nil or saved == true
end

local function rich(text)
    local value = tostring(text or ""):gsub("<LINE>", "\n"):gsub("<BR>", "\n")
    value = value:gsub("<RGB:[^>]*>", ""):gsub("<RED>", ""):gsub("<GREEN>", ""):gsub("<WHITE>", "")
    return value:gsub("[<>]", " "):gsub("\n", " <LINE> ")
end

local function colored(color, text)
    return string.format("<RGB:%.2f,%.2f,%.2f> %s", color.r, color.g, color.b, rich(text))
end

local ScrollPanel = ISPanel:derive("AutoMindfulScrollPanel")
function ScrollPanel:prerender()
    self:setStencilRect(0, 0, self.width, self.height)
end
function ScrollPanel:render()
    self:clearStencilRect()
end
function ScrollPanel:onMouseWheel(delta)
    self:setYScroll(self:getYScroll() - delta * 36)
    return true
end

local Frame = ISPanel:derive("AutoMindfulFrame")
function Frame:prerender()
    ISPanel.prerender(self)
    local c = palette.text
    self:drawText(self.heading, 12, 8, c.r, c.g, c.b, c.a, UIFont.Medium)
end

local SkillFrame = Frame:derive("AutoMindfulSkillFrame")
function SkillFrame:prerender()
    Frame.prerender(self)
    local now = getTimestampMs()
    for _, skill in ipairs(self.skills) do
        local flash = skill.flash
        if flash then
            local age = (now - flash.started) / 1000
            if age >= 1 then skill.flash = nil
            else
                local c = flash.positive and palette.gain or palette.missing
                self:drawTextRight(flash.text, self.width - 12, skill.labelY - math.max(0, age) * 8,
                    c.r, c.g, c.b, 1 - math.max(0, age), UIFont.Small)
            end
        end
    end
end

local Ledger = Frame:derive("AutoMindfulSupplyLedger")
local supplyRows = {
    {label="Food", field="food", nearby="nearbyFood", color=palette.meditation},
    {label="Hydration", field="water", nearby="nearbyWater", color=palette.water},
    {label="Literature", field="literature", nearby="nearbyLiterature", color=palette.yoga},
    {label="Painkillers", field="pain", nearby="nearbyPain", color=palette.meditation},
}
function Ledger:prerender()
    Frame.prerender(self)
    local line, report = self.line, self.window.report or {}
    local inventoryX, nearbyX = self.width * 0.67, self.width - 14
    local c = palette.muted
    local y = line + 20
    self:drawTextRight("Inventory", inventoryX, y, c.r, c.g, c.b, c.a, UIFont.Small)
    self:drawTextRight(report.radius and (tostring(report.radius) .. " tiles") or "Nearby", nearbyX, y, c.r, c.g, c.b, c.a, UIFont.Small)
    for index, row in ipairs(supplyRows) do
        y = line + 24 + index * (line + 6)
        local owned, nearby = report[row.field] or 0, report[row.nearby] or 0
        c = palette.text
        self:drawText(row.label, 12, y, c.r, c.g, c.b, c.a, UIFont.Small)
        c = owned > 0 and row.color or palette.missing
        self:drawTextRight(tostring(owned), inventoryX, y, c.r, c.g, c.b, c.a, UIFont.Small)
        c = nearby > 0 and ((self.window.nearby:isSelected(1) or report.walkingEnabled) and row.color or palette.yoga) or palette.muted
        self:drawTextRight(tostring(nearby), nearbyX, y, c.r, c.g, c.b, c.a, UIFont.Small)
    end
    c = palette.muted
    self:drawText(report.walkingEnabled and "Care trips: enabled" or self.window.nearby:isSelected(1)
        and "Adjacent only; care trips off" or "Collection off; known stock shown",
        12, self.height - line * 2 - 10, c.r, c.g, c.b, c.a, UIFont.Small)
    self:drawText("Known items, not days or servings", 12, self.height - line - 7, c.r, c.g, c.b, c.a, UIFont.Small)
    ISLabel.updateTooltip(self)
end

local function frame(parent, class, heading, x, y, width, height)
    local panel = class:new(x, y, width, height)
    panel.heading = heading
    panel.backgroundColor, panel.borderColor = palette.panel, palette.border
    panel:initialise()
    parent:addChild(panel)
    return panel
end

local function textPanel(parent, x, y, width, height, scroll)
    local panel = ISRichTextPanel:new(x, y, width, height)
    panel:initialise()
    panel.defaultFont = UIFont.Small
    panel.background, panel.clip = false, true
    panel.marginLeft, panel.marginRight = 0, scroll and 14 or 0
    panel.autosetheight = false
    parent:addChild(panel)
    if scroll then panel:addScrollBars() end
    return panel
end

local function setText(panel, text)
    if panel.text ~= text then panel:setText(text); panel:paginate() end
end

local function recoveryModes(mode)
    return mode == "recovery" or mode == "recoverEndurance"
end

local function endurancePercent(value)
    if type(value) == "number" and value >= 0 and value <= 1 then
        return string.format("%d%%", math.floor(value * 100))
    end
end

local function updateFooter(window)
    local code = Options.windowKey()
    local keyName = code ~= 0 and getKeyName and getKeyName(code) or nil
    local shortcut = keyName and keyName ~= "" and ("Open with " .. keyName .. "; change in Mod Options.")
        or "Shortcut: set a key in Mod Options."
    setText(window.footer, colored(palette.muted, "Close to hide. Your current mode continues.") .. " <LINE> "
        .. colored(palette.muted, shortcut))
end

local function recoveryWidths(width)
    local font, gap = getTextManager(), 6
    local primary = font:MeasureStringX(UIFont.Small, "Recovery") + 20
    local full = font:MeasureStringX(UIFont.Small, "Recover to Full Endurance") + 20
    if primary + full + gap > width then return width, width, true end
    primary = math.min(width - full - gap, math.max(primary, width * .38))
    return primary, width - primary - gap, false
end

function UI:savePreferences()
    local saved = preferences(self.player)
    saved.x, saved.y, saved.pin = self:getX(), self:getY(), self.pin
    saved.width, saved.height = self.width, self.height
    saved.collectNearby = self.nearby:isSelected(1)
end

function UI:onNearbyChanged()
    self:savePreferences()
    Controller.setCollectNearby(self.player, self.nearby:isSelected(1))
    self:checkSupplies()
end

function UI:onScoutingChanged()
    Options.setSearchNearby(self.scouting:isSelected(1))
    self:checkSupplies()
end

function UI:onCycleChanged(combo)
    Options.setCycleIndex(combo:getSelected())
    self:refresh()
end

function UI:checkSupplies()
    self.startError = nil
    self.checkedAt = getTimestampMs()
    self.nextRefresh = 0
    self.forceSupplyRefresh = true
    self:refresh()
end

function UI.startTraining(player, mode)
    local collect = mode ~= "endurance" and useAdjacent(player)
    local started, message = Controller.start(player, mode, collect)
    local window = UI.windows[player:getPlayerNum()]
    if not started then window = UI.open(player) end
    if window then
        window.startError = not started and message or nil
        window.nextRefresh = 0
        window:refresh()
    end
    return started, message
end

function UI:onStart(button)
    self:savePreferences()
    UI.startTraining(self.player, button.mode)
end

function UI:onStop(button)
    -- Both stock mouse dispatch and forceClick pass this same control. Record
    -- the callback source without claiming how it was activated.
    local source = button and button == self.stopButton and "pane-stop-control" or "pane-stop-callback"
    print("[AutoMindful] stop-request source=" .. source)
    Controller.stop(self.player, "AutoMindful received a stop request.")
    self.startError = nil
    self.nextRefresh = 0
    self:refresh()
end

local function positionGuideButton(button, frame, line)
    local labelWidth = getTextManager():MeasureStringX(UIFont.Small, button.guideLabel)
    local width = math.min(frame.width * 0.5, math.max(74, labelWidth + 16))
    button:setWidth(width)
    button:setHeight(math.max(20, line + 4))
    button:setX(frame.width - width - 10)
end

local function addGuideButton(frame, label, window, y)
    local button = ISButton:new(0, y, 88, 22, label, window, UI.toggleSkillGuide)
    button.guideLabel = label
    button.tooltip = label == "Skill Guide"
        and "Lifestyle rank effects, Mindfulness and Zen. Opening the guide does not stop training."
        or "Back to activity, progress and supplies."
    button:initialise()
    frame:addChild(button)
    return button
end

local guideThemes = {
    Meditation = palette.meditation, Mindfulness = palette.meditation,
    Yoga = palette.yoga, Zen = palette.yoga, Lessons = palette.water,
}
local guideSelected = {r=0.17, g=0.23, b=0.20, a=1}
local maxGuideTabs = 5
local guideWarnings = {["Trade-offs"]=true,["Early stops"]=true,["Multiplayer"]=true,["Version"]=true}

-- Use the actual game font width for both wrapping and drawing. The stock
-- rich-text paginator can underestimate glyph widths for colored guide rows.
local GuideText = ISPanel:derive("AutoMindfulGuideText")
function GuideText:paginate()
    local font = getTextManager()
    local lineHeight = font:getFontHeight(UIFont.Small) + 3
    if self.layoutRows == self.rows and self.layoutWidth == self.width and self.layoutHeight == lineHeight then return end
    self.layoutRows, self.layoutWidth, self.layoutHeight = self.rows, self.width, lineHeight
    local maxWidth = math.max(1, self.width - 4)
    local rendered, y = {}, 0
    local function addText(value, color, emphasize)
        local line = ""
        local function emit()
            if line ~= "" then
                local item = {text=line,color=color,y=y}
                if emphasize then
                    local first, active, startAt = true, nil, 1
                    item.runs = {}
                    local function run(stopAt)
                        if stopAt < startAt then return end
                        local prefix = line:sub(1, startAt - 1)
                        item.runs[#item.runs + 1] = {text=line:sub(startAt, stopAt),color=active,
                            x=prefix == "" and 0 or font:MeasureStringX(UIFont.Small, prefix)}
                    end
                    for at, word in line:gmatch("()(%S+)") do
                        -- Preserve the normal text color around numbers and ranges.
                        local amount = word:match("^[%+%-x]?%d") and palette.value or color
                        if first then active, first = amount, false
                        elseif active ~= amount then
                            run(at - 1)
                            startAt, active = at, amount
                        end
                    end
                    run(#line)
                end
                rendered[#rendered + 1] = item
                y = y + lineHeight
            end
            line = ""
        end
        for word in value:gmatch("%S+") do
            local nextLine = line == "" and word or (line .. " " .. word)
            if font:MeasureStringX(UIFont.Small, nextLine) <= maxWidth then line = nextLine
            else
                emit()
                if font:MeasureStringX(UIFont.Small, word) <= maxWidth then line = word
                else
                    -- Split long unbroken fallback/translated words between complete UTF-8 glyphs.
                    for glyph in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                        if font:MeasureStringX(UIFont.Small, line .. glyph) > maxWidth then emit() end
                        if font:MeasureStringX(UIFont.Small, glyph) <= maxWidth then line = line .. glyph end
                    end
                end
            end
        end
        emit()
    end
    for _, row in ipairs(self.rows or {}) do
        if row.label then addText(row.label, row.caution and palette.caution or row.accent) end
        addText(row.detail, row.numeric and palette.value or (row.label and palette.text or row.accent), row.label ~= nil and not row.numeric)
        y = y + (row.numeric and 4 or 9)
    end
    self.rendered = rendered
    self:setScrollHeight(y)
end

function GuideText:render()
    for _, line in ipairs(self.rendered or {}) do
        if line.runs then
            for _, run in ipairs(line.runs) do
                local c = run.color
                self:drawText(run.text, run.x, line.y, c.r, c.g, c.b, c.a, UIFont.Small)
            end
        else
            local c = line.color
            self:drawText(line.text, 0, line.y, c.r, c.g, c.b, c.a, UIFont.Small)
        end
    end
end

function UI:refreshSkillGuide()
    local sections = Wellness.guide(self.player, self.status and self.status.progress)
    local index = self.wellnessSection or 1
    if not sections[index] or sections[index].title ~= self.wellnessTopic then
        index = 1
        for i, section in ipairs(sections) do
            if section.title == self.wellnessTopic then index = i; break end
        end
    end
    local selected = sections[index]
    if not selected then return end
    self.wellnessSection, self.wellnessTopic = index, selected.title
    for i, button in ipairs(self.wellnessTabs) do
        local section = sections[i]
        button:setVisible(section ~= nil)
        if section then
            if button.guideLabel ~= section.title then
                button.guideLabel = section.title
                button:setTitle(section.title)
            end
            local active = i == index
            button.guideSelected = active
            local accent = guideThemes[section.title] or palette.meditation
            button.backgroundColor = active and guideSelected or palette.panel
            button.borderColor = active and accent or palette.border
            button.textColor = active and accent or palette.text
        end
    end
    local accent = guideThemes[selected.title] or palette.meditation
    self.wellnessCard.heading = selected.title
    self.wellnessCard.borderColor = accent
    local rows = {}
    if selected.subtitle then rows[#rows + 1] = {detail=selected.subtitle,accent=accent} end
    for _, value in ipairs(selected.lines) do
        local label, detail = value:match("^([^:]+):%s+(.+)$")
        if label and #label <= 44 then
            rows[#rows + 1] = {label=label,detail=detail,accent=accent,caution=guideWarnings[label],
                numeric=detail:match("^[%+%-]%d") ~= nil}
        else
            rows[#rows + 1] = {detail=value,accent=palette.text}
        end
    end
    local signature = {selected.title, selected.subtitle or "", table.concat(selected.lines, "\n")}
    local key = table.concat(signature, "\n")
    if self.wellnessText.contentKey ~= key then
        self.wellnessText.contentKey, self.wellnessText.rows = key, rows
        self.wellnessText:paginate()
    end
end

function UI:selectSkillGuideTab(button)
    if not self.wellnessOpen or not button.guideLabel or button.guideLabel == self.wellnessTopic then return end
    self.wellnessTopic = button.guideLabel
    self:refreshSkillGuide()
    self:layout()
    self.body:setYScroll(0)
end

local function layoutGuideTabs(window, width, line)
    local font = getTextManager()
    local left, top, x, y, gap = 12, line + 24, 12, line + 24, 6
    local height = math.max(24, line + 10)
    for _, button in ipairs(window.wellnessTabs) do
        if button:getIsVisible() then
            local w = math.min(width - 24, math.max(68, font:MeasureStringX(UIFont.Small, button.guideLabel) + 18))
            if x + w > width - 12 and x > left then x, y = left, y + height + gap end
            button:setX(x); button:setY(y); button:setWidth(w); button:setHeight(height)
            x = x + w + gap
        end
    end
    return math.max(top, y) + height + 10
end

function UI:toggleSkillGuide()
    local open = not self.wellnessOpen
    if open then self.trainingScroll = self.body:getYScroll()
    else self.wellnessScroll = self.body:getYScroll() end
    self.wellnessOpen = open
    for _, panel in ipairs({self.activityFrame, self.progressFrame, self.ledger, self.guideFrame}) do panel:setVisible(not open) end
    self.wellnessFrame:setVisible(open)
    self.historyFrame:setVisible(self.historyOpen and not open)
    if open then self:refreshSkillGuide()
    else self:refreshDecisionHistory(self.status and self.status.decisionRevision or 0) end
    self:layout()
    self.body:setYScroll((open and self.wellnessScroll or self.trainingScroll) or 0)
end

function UI:refreshDecisionHistory(revision)
    if not self.historyOpen or self.wellnessOpen or self.historyRevision == revision then return end
    self.historyRevision = revision
    local entries = Controller.recentDecisions and Controller.recentDecisions(self.player) or {}
    local lines = {}
    for _, entry in ipairs(entries) do
        lines[#lines + 1] = colored(palette.text, entry.label)
        if entry.reason then lines[#lines + 1] = colored(palette.muted, entry.reason) end
    end
    if #lines == 0 then lines[1] = colored(palette.muted, "No decisions recorded yet.") end
    setText(self.historyText, table.concat(lines, " <LINE> "))
end

function UI:toggleDecisionHistory()
    self.historyOpen = not self.historyOpen
    self.historyButton.guideLabel = self.historyOpen and "Hide recent" or "Recent"
    self.historyButton:setTitle(self.historyButton.guideLabel)
    self.historyFrame:setVisible(self.historyOpen and not self.wellnessOpen)
    self:refreshDecisionHistory(self.status and self.status.decisionRevision or 0)
    self:layout()
end

function UI:refresh()
    local status = Controller.status(self.player)
    local recovery = recoveryModes(status.mode)
    local recovering = status.active and recovery
    self.scouting:setSelected(1, Options.searchNearby())
    self.cycle:setSelected(Options.cycleIndex())
    self.report = Controller.prepare(self.player, self.nearby:isSelected(1), true, self.forceSupplyRefresh)
    self.forceSupplyRefresh = nil
    self.status = status
    self.recovering = recovering
    for _, button in ipairs(self.starts) do button:setEnable(not status.active) end
    self.recoveryButton:setEnable(not status.active)
    self.recoverEnduranceButton:setEnable(not status.active)
    self.stopButton:setEnable(status.active)
    self.nearby.enable = true
    local activityColor = status.active and palette.meditation or (self.startError and palette.missing or palette.text)
    local phase = status.active and (status.mode == "both" and "Training both" or status.mode == "yoga" and "Training yoga" or "Training meditation") or "Ready"
    local endurance = endurancePercent(status.endurance)
    if recovering then
        phase = status.mode == "recoverEndurance" and "Recovery until full endurance" or "Recovery on"
        if status.careWaiting then phase = phase .. " (paused for care)"
        elseif status.phase == "manual" then phase = phase .. " (yielding)" end
        activityColor = palette.water
    elseif recovery and status.phase == "complete" then
        phase, activityColor = "Recovery complete", palette.water
    else
        if status.active and status.mode == "endurance" then
            phase = "Recovering endurance" .. (endurance and " (" .. endurance .. ")" or "")
        end
        if status.phase == "practice-care" then phase = "Practice for relief"; activityColor = palette.yoga end
        if status.active and status.careWaiting then phase = "Paused for care"; activityColor = palette.yoga end
    end
    if status.phase == "stopped" then phase = "Stopped"; activityColor = palette.yoga end
    local activityMessage = status.careWaiting and status.message or self.startError or status.message
    if status.active and status.backgroundPractice and not status.careWaiting and status.phase~="practice-care" then
        phase = status.mode=="both" and "Practicing both (max rank)"
            or status.mode=="yoga" and "Practicing yoga (max rank)" or "Practicing meditation (max rank)"
    end
    local activity = colored(activityColor, phase)
    if status.decisionLabel and (not self.startError or status.careWaiting) then
        activity = activity .. " <LINE> " .. colored(palette.text, status.decisionLabel)
        local code, detail = status.decisionCode, status.decisionDetail
        if code == "water-unavailable" then
            detail = Decisions.waterDetail(self.report)
            if status.active then activityMessage = "Thirst is critical." end
        elseif status.phase == "manual" and detail then
            -- The active cause can change (e.g. map opens during a wait)
            -- without changing the controller's legacy phase message.
            activityMessage, detail = detail, nil
        end
        if detail and rich(detail) ~= rich(activityMessage) then
            activity = activity .. " <LINE> " .. colored(palette.yoga, detail)
        end
    end
    if activityMessage and activityMessage ~= status.decisionLabel then
        activity = activity .. " <LINE> " .. colored(palette.text, activityMessage)
    end
    if endurance and (recovering or (recovery and status.phase == "complete")) then
        activity = activity .. " <LINE> " .. colored(palette.water, "Endurance: " .. endurance)
    end
    if status.active and status.mode == "both" and status.cycle and (status.cycle.due == "meditation" or status.cycle.due == "yoga") then
        local kind = status.cycle.due
        local name = kind == "yoga" and "Yoga" or "Meditation"
        local gate = status.cycle.gates and status.cycle.gates[kind]
        local reason = gate and not gate.ready and gate.reason or nil
        if reason and status.decisionCode ~= kind .. "-gate" then
            activity = activity .. " <LINE> " .. colored(palette.yoga, name .. " is still next: " .. reason)
        elseif not reason and (status.cycle.bridge or status.phase ~= kind) then
            activity = activity .. " <LINE> " .. colored(palette.muted, "Next practice: " .. name)
        end
    end
    setText(self.activity, activity)
    self:refreshDecisionHistory(status.decisionRevision or 0)
    self.progressFrame.heading = recovering and "Skill reference" or "Progress"
    local now = getTimestampMs()
    for _, skill in ipairs(self.skills) do
        skill.label:setVisible(not recovering)
        skill.bar:setVisible(not recovering)
        local level = math.max(0, math.min(10, status[skill.field] or 0))
        local progress = status.progress and status.progress[skill.field]
        skill.label:setName(string.format("%s - Level %d / 10", skill.name, level))
        skill.bar:setProgress(progress and progress.fraction or 0)
        skill.bar:setText(Progress.xpText(progress))
        skill.bar.textColor = level >= 10 and palette.yoga or (level > 0 and skill.color or palette.muted)
        if recovering then skill.flash = nil end
        local change = not recovering and self.progressObserved and Progress.change(skill.sample, progress)
        if change then
            local amount = change.amount or change.levels
            local unit = change.amount and " XP" or (math.abs(amount) == 1 and " level" or " levels")
            skill.flash = {positive=change.positive, started=now,
                text=(amount > 0 and "+" or "") .. Progress.number(amount) .. unit}
        end
        skill.sample = progress
    end
    self.progressObserved = not recovering and self:getIsVisible()
    self.checked:setName(getTimestampMs() - (self.checkedAt or -10000) < 3000 and "Supplies checked just now" or "Live supply refresh")
    local tips = {}
    if status.active and status.mode == "endurance" then
        tips[#tips + 1] = colored(palette.meditation, "This session does not use supplies or scout.")
    end
    if status.returnNotice then tips[#tips + 1] = colored(palette.yoga, status.returnNotice) end
    if status.active and status.careNotice then tips[#tips + 1] = colored(palette.yoga, status.careNotice) end
    if status.active and status.painNotice then tips[#tips + 1] = colored(palette.yoga, status.painNotice) end
    if (status.pendingReturns or 0) > 0 then
        tips[#tips + 1] = colored(palette.yoga, tostring(status.pendingReturns) .. " borrowed item(s) awaiting return.")
    end
    if not self.nearby:isSelected(1) and not self.report.walkingEnabled and ((self.report.nearbyFood or 0) + (self.report.nearbyWater or 0) + (self.report.nearbyLiterature or 0) + (self.report.nearbyPain or 0)) > 0 then
        tips[#tips + 1] = colored(palette.yoga, "Enable care trips to use distant stock, or adjacent supplies for reachable stock only.")
    end
    for _, warning in ipairs(self.report.warnings or {}) do
        tips[#tips + 1] = colored(palette.yoga, "- " .. warning)
    end
    if #tips == 0 then
        local message = recovering and (status.mode == "recoverEndurance" and "Recovery stops at full endurance and yields to other actions."
                or "Recovery stays on and yields to other actions. It only steps in when needed.")
            or (status.active and "Training continues. Care breaks happen only when needed."
                or "Supplies are available. Choose training or Recovery when you are ready.")
        tips[1] = colored(recovering and palette.water or palette.meditation, message)
    end
    setText(self.guidance, table.concat(tips, " <LINE> "))
    local unread, rereads = self.report.unreadLiterature, self.report.rereadLiterature
    local literatureHelp = unread and string.format("Literature in inventory: %d unread, %d eligible rereads. ", unread, rereads or 0) or ""
    self.ledger.tooltip = "Known contents within the configured radius refresh while you move or change inventory. Uninspected/unconfirmed containers are reported separately; Check supplies never walks or remotely generates loot. Hydration includes safe drinks and hydrating food; one item can count in both food and hydration. " .. literatureHelp
        .. "A mode can start with no supplies. Missing stock matters when the survivor needs it. Unread literature is preferred, then eligible rereads. Recently read material may be on cooldown. Nearby supplies are used only when collection is enabled."
    if self.wellnessOpen then self:refreshSkillGuide() end
    updateFooter(self)
    self:layout()
end

function UI:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad, line = 12, getTextManager():getFontHeight(UIFont.Small)
    local row = math.max(28, line + 10)
    local width = self.width - pad * 2
    local bodyY = self:titleBarHeight() + 10
    local controlsHeight = row * 5 + line * 3 + 38
    self.body = ScrollPanel:new(pad, bodyY, width, self.height - bodyY - controlsHeight - 8)
    self.body:initialise()
    self:addChild(self.body)
    self.body:setScrollChildren(true)
    self.body:addScrollBars()
    local contentWidth, y = width - 15, 0
    local activity = frame(self.body, Frame, "Activity", 0, y, contentWidth, line * 4 + 20)
    self.activityFrame = activity
    self.activity = textPanel(activity, 12, line + 17, contentWidth - 24, activity.height - line - 23, false)
    self.activity.marginTop, self.activity.marginBottom = 0, 0
    self.historyButton = ISButton:new(0, 5, 88, 22, "Recent", self, UI.toggleDecisionHistory)
    self.historyButton.guideLabel = "Recent"
    self.historyButton.tooltip = "Show the six most recent decisions for this survivor. Not saved."
    self.historyButton:initialise()
    activity:addChild(self.historyButton)
    y = y + activity.height + 8
    self.historyFrame = frame(self.body, Frame, "Recent decisions", 0, y, contentWidth, line * 3 + 23)
    self.historyText = textPanel(self.historyFrame, 12, line + 18, contentWidth - 24, line * 2, false)
    self.historyText.marginTop, self.historyText.marginBottom = 0, 0
    self.historyFrame:setVisible(false)
    local progress = frame(self.body, SkillFrame, "Progress", 0, y, contentWidth, line * 5 + 32)
    self.progressFrame = progress
    self.skills = {}
    local skillY = line + 20
    for _, entry in ipairs({{"Meditation", "meditation", palette.meditation}, {"Yoga", "yoga", palette.yoga}}) do
        local label = ISLabel:new(12, skillY, line, entry[1], palette.text.r, palette.text.g, palette.text.b, 1, UIFont.Small, true)
        label:initialise()
        progress:addChild(label)
        local bar = ISProgressBar:new(12, skillY + line + 3, contentWidth - 24, line + 4, "0 / 10", UIFont.Small)
        bar:initialise()
        bar.progressColor, bar.borderColor = entry[3], palette.border
        progress:addChild(bar)
        self.skills[#self.skills + 1] = {name=entry[1], field=entry[2], label=label, labelY=skillY, bar=bar, color=entry[3]}
        skillY = skillY + line * 2 + 12
    end
    progress:setHeight(skillY + 7)
    progress.fullHeight = progress.height
    progress.skills = self.skills
    y = y + progress.height + 8
    self.ledger = frame(self.body, Ledger, "Supplies", 0, y, contentWidth, line * 8 + 64)
    self.ledger.line, self.ledger.window = line, self
    y = y + self.ledger.height + 8
    local guide = frame(self.body, Frame, "Preparation and returns", 0, y, contentWidth, line * 6 + 28)
    self.guideFrame = guide
    self.guidance = textPanel(guide, 12, line + 18, contentWidth - 24, guide.height - line - 23, true)
    self.guidance.marginTop, self.guidance.marginBottom = 0, 0
    self.body:setScrollHeight(y + guide.height + 4)
    self.skillGuideButton = addGuideButton(progress, "Skill Guide", self, 5)
    self.wellnessFrame = frame(self.body, Frame, "Skill Guide", 0, 0, contentWidth, 1)
    self.wellnessBack = addGuideButton(self.wellnessFrame, "Back", self, 5)
    self.wellnessTabs = {}
    for i = 1, maxGuideTabs do
        local tab = ISButton:new(0, 0, 80, 24, "", self, UI.selectSkillGuideTab)
        tab:initialise()
        self.wellnessFrame:addChild(tab)
        tab:setVisible(false)
        self.wellnessTabs[i] = tab
    end
    self.wellnessCard = frame(self.wellnessFrame, Frame, "Meditation", 12, line + 53, contentWidth - 24, 1)
    self.wellnessCard.backgroundColor = palette.background
    self.wellnessText = GuideText:new(12, line + 23, contentWidth - 48, 1)
    self.wellnessText:initialise()
    self.wellnessText.background = false
    self.wellnessCard:addChild(self.wellnessText)
    self.wellnessText.blockMouseWheel = true -- route wheel input to the outer guide scroll body
    self.wellnessFrame:setVisible(false)
    y = self.body:getBottom() + 6
    self.scouting = ISTickBox:new(pad, y, width * 0.53, row, Options.scoutingLabel, self, UI.onScoutingChanged)
    self.scouting:initialise()
    self.scouting:addOption(Options.scoutingLabel)
    self.scouting:setSelected(1, Options.searchNearby())
    self.scouting.tooltip = Options.scoutingHelp
    self:addChild(self.scouting)
    self.nearby = ISTickBox:new(pad + width * 0.53, y, width * 0.47, row, "Adjacent supplies", self, UI.onNearbyChanged)
    self.nearby:initialise()
    self.nearby:addOption("Use adjacent supplies")
    self.nearby:setSelected(1, useAdjacent(self.player))
    self.nearby.tooltip = "When scouting is off, allow borrowing from adjacent supplies without walking away. Scouting already includes adjacent supplies."
    self:addChild(self.nearby)
    y = y + row + 4
    self.cycleLabel = ISLabel:new(pad, y + math.floor((row - line) / 2), line,
        Options.cycleLabel, palette.text.r, palette.text.g, palette.text.b, 1, UIFont.Small, true)
    self.cycleLabel:initialise()
    self:addChild(self.cycleLabel)
    self.cycle = ISComboBox:new(pad + width * 0.46, y, width * 0.54, row, self, UI.onCycleChanged)
    self.cycle:initialise()
    for _, entry in ipairs(Options.cycleChoices()) do self.cycle:addOptionWithData(entry.label, entry.id, entry.help) end
    self.cycle:setSelected(Options.cycleIndex())
    self:addChild(self.cycle)
    y = y + row + 4
    self.starts = {}
    local labels = {{"Train both", "both"}, {"Meditation", "meditation"}, {"Yoga", "yoga"}}
    local buttonWidth = (width - 12) / 3
    for index, entry in ipairs(labels) do
        local button = ISButton:new(pad + (index - 1) * (buttonWidth + 6), y, buttonWidth, row, entry[1], self, UI.onStart)
        button:initialise()
        button.mode = entry[2]
        button.tooltip = entry[2] == "both" and "Train unfinished skills to level 10. If both are already maxed, alternate when idle."
            or "Train " .. entry[1]:lower() .. " toward level 10, or practice when idle if already maxed."
        self:addChild(button)
        self.starts[index] = button
    end
    y = y + row + 4
    self.recoveryButton = ISButton:new(pad, y, width, row, "Recovery", self, UI.onStart)
    self.recoveryButton:initialise()
    self.recoveryButton.mode = "recovery"
    self.recoveryButton.tooltip = "Stay on in the background. Handle needs and use Yoga or Meditation only when useful. Other actions take priority."
    self.recoveryButton.borderColor, self.recoveryButton.textColor = palette.water, palette.water
    self.recoveryButton.backgroundColor = {r=.13, g=.20, b=.24, a=1}
    self:addChild(self.recoveryButton)
    self.recoverEnduranceButton = ISButton:new(pad, y, width, row, "Recover to Full Endurance", self, UI.onStart)
    self.recoverEnduranceButton:initialise()
    self.recoverEnduranceButton.mode = "recoverEndurance"
    self.recoverEnduranceButton.tooltip = "Run Recovery until endurance is full, then stop. Useful care and existing supply settings still apply."
    self.recoverEnduranceButton.borderColor = palette.water
    self:addChild(self.recoverEnduranceButton)
    y = y + row + 4
    self.check = ISButton:new(pad, y, width / 2 - 3, row, "Check supplies", self, UI.checkSupplies)
    self.check:initialise()
    self.check.tooltip = "Refresh known container contents within the configured radius now. Unknown contents stay unknown; this does not move the survivor or collect items."
    self:addChild(self.check)
    self.stopButton = ISButton:new(pad + width / 2 + 3, y, width / 2 - 3, row, "Stop All", self, UI.onStop)
    self.stopButton:initialise()
    self.stopButton.borderColor = palette.missing
    self.stopButton.tooltip = "Stop only AutoMindful's mode and its own actions. Your actions and workouts from other mods keep running."
    self:addChild(self.stopButton)
    y = y + row + 6
    self.checked = ISLabel:new(pad, y, line, "Live supply refresh", palette.meditation.r, palette.meditation.g, palette.meditation.b, 1, UIFont.Small, true)
    self.checked:initialise()
    self:addChild(self.checked)
    local footer = textPanel(self, pad, y + line + 2, width, line * 2 + 4, false)
    self.footer = footer
    footer.marginTop, footer.marginBottom = 0, 0
    updateFooter(self)
    self:layout()
end

function UI:layout()
    if not self.footer then return end
    local pad, line = 12, getTextManager():getFontHeight(UIFont.Small)
    local row = math.max(28, line + 10)
    local width = self.width - pad * 2
    local recoveryWidth, fullWidth, stackRecovery = recoveryWidths(width)
    local bodyY = self:titleBarHeight() + 10
    self.footer:setWidth(width)
    self.footer:paginate()
    self.footer:setHeight(math.max(line * 2 + 4, self.footer:getScrollHeight()))
    local controlsHeight = row * 5 + line + self.footer.height + 34 + (stackRecovery and row + 4 or 0)
    self.body:setWidth(width)
    self.body:setHeight(math.max(1, self.height - bodyY - controlsHeight - 8))
    local contentWidth = width - 15
    for _, panel in ipairs({self.activityFrame, self.historyFrame, self.progressFrame, self.ledger, self.guideFrame}) do panel:setWidth(contentWidth) end
    for _, panel in ipairs({self.activity, self.historyText, self.guidance}) do
        if panel.width ~= contentWidth - 24 then
            panel:setWidth(contentWidth - 24)
            if panel.text then panel:paginate() end
        end
    end
    self.activity:setHeight(math.max(line * 2, self.activity:getScrollHeight()) + 2)
    self.activityFrame:setHeight(line + 23 + self.activity.height)
    local y = self.activityFrame:getBottom() + 8
    positionGuideButton(self.historyButton, self.activityFrame, line)
    if self.historyOpen then
        self.historyFrame:setY(y)
        self.historyText:setY(line + 18)
        self.historyText:setHeight(math.max(line, self.historyText:getScrollHeight()) + 2)
        self.historyFrame:setHeight(self.historyText:getBottom() + 8)
        y = self.historyFrame:getBottom() + 8
    end
    self.progressFrame:setY(y)
    self.progressFrame:setHeight(self.recovering and math.max(line + 22, 36) or self.progressFrame.fullHeight)
    for _, skill in ipairs(self.skills) do skill.bar:setWidth(contentWidth - 24) end
    self.ledger:setY(self.progressFrame:getBottom() + 8)
    self.guideFrame:setY(self.ledger:getBottom() + 8)
    self.guidance:setHeight(math.min(line * 6, math.max(line * 2, self.guidance:getScrollHeight())) + 2)
    self.guideFrame:setHeight(line + 24 + self.guidance.height)
    positionGuideButton(self.skillGuideButton, self.progressFrame, line)
    self.wellnessFrame:setWidth(contentWidth)
    positionGuideButton(self.wellnessBack, self.wellnessFrame, line)
    if self.wellnessOpen then
        self.wellnessCard:setWidth(contentWidth - 24)
        self.wellnessCard:setY(layoutGuideTabs(self, contentWidth, line))
        self.wellnessText:setWidth(contentWidth - 48)
        self.wellnessText:setY(line + 23)
        self.wellnessText:paginate()
        self.wellnessText:setHeight(self.wellnessText:getScrollHeight() + 4)
        self.wellnessCard:setHeight(self.wellnessText:getBottom() + 10)
        self.wellnessFrame:setHeight(self.wellnessCard:getBottom() + 10)
        self.body:setScrollHeight(self.wellnessFrame:getBottom() + 4)
    else
        self.body:setScrollHeight(self.guideFrame:getBottom() + 4)
    end
    y = self.body:getBottom() + 6
    self.scouting:setY(y)
    self.scouting:setWidth(width * 0.53)
    self.nearby:setX(pad + width * 0.53)
    self.nearby:setY(y)
    self.nearby:setWidth(width * 0.47)
    y = y + row + 4
    self.cycleLabel:setY(y + math.floor((row - line) / 2))
    self.cycle:setX(pad + width * 0.46)
    self.cycle:setY(y)
    self.cycle:setWidth(width * 0.54)
    y = y + row + 4
    local buttonWidth = (width - 12) / 3
    for index, button in ipairs(self.starts) do
        button:setX(pad + (index - 1) * (buttonWidth + 6))
        button:setY(y)
        button:setWidth(buttonWidth)
    end
    y = y + row + 4
    self.recoveryButton:setY(y)
    self.recoveryButton:setWidth(recoveryWidth)
    self.recoveryButton:setHeight(row)
    self.recoverEnduranceButton:setX(stackRecovery and pad or pad + recoveryWidth + 6)
    self.recoverEnduranceButton:setY(stackRecovery and y + row + 4 or y)
    self.recoverEnduranceButton:setWidth(fullWidth)
    self.recoverEnduranceButton:setHeight(row)
    if stackRecovery then y = y + row + 4 end
    y = y + row + 4
    self.check:setY(y)
    self.check:setWidth(width / 2 - 3)
    self.stopButton:setX(pad + width / 2 + 3)
    self.stopButton:setY(y)
    self.stopButton:setWidth(width / 2 - 3)
    y = y + row + 6
    self.checked:setY(y)
    self.footer:setY(y + line + 2)
end

function UI:onResize()
    ISCollapsableWindow.onResize(self)
    self:layout()
    if self.footer then self:savePreferences() end
end

function UI:update()
    ISCollapsableWindow.update(self)
    if not self:getIsVisible() then return end
    if self.player:isDead() then self:close(); return end
    local now = getTimestampMs()
    if now < self.nextRefresh then return end
    self.nextRefresh = now + 500
    self:refresh()
end

function UI:close()
    if self.wellnessOpen then self:toggleSkillGuide() end
    self:savePreferences()
    self.progressObserved = false
    for _, skill in ipairs(self.skills) do skill.flash, skill.sample = nil, nil end
    if self.ledger.tooltipUI then
        self.ledger.tooltipUI:setVisible(false)
        self.ledger.tooltipUI:removeFromUIManager()
    end
    self:setVisible(false)
    self:removeFromUIManager()
end

function UI.open(player)
    local index = player:getPlayerNum()
    local window = UI.windows[index]
    if window and window.player ~= player then window:close(); window = nil end
    if not window then
        local saved = preferences(player)
        local line = getTextManager():getFontHeight(UIFont.Small)
        local minimumWidth = math.min(480, getCore():getScreenWidth() - 24)
        local minimumHeight = math.min(math.max(440, line * 17 + 100), getCore():getScreenHeight() - 40)
        local width = math.min(math.max(minimumWidth, tonumber(saved.width) or 540), getCore():getScreenWidth() - 24)
        local height = math.min(math.max(minimumHeight, tonumber(saved.height) or math.max(800, line * 37 + 171)), getCore():getScreenHeight() - 40)
        local x = math.max(0, math.min(tonumber(saved.x) or 70, getCore():getScreenWidth() - width))
        local y = math.max(0, math.min(tonumber(saved.y) or 70, getCore():getScreenHeight() - height))
        window = UI:new(x, y, width, height)
        window.player, window.title = player, "AutoMindful"
        window.backgroundColor, window.borderColor = palette.background, palette.border
        window.resizable, window.pin = true, saved.pin ~= false
        window.minimumWidth, window.minimumHeight = minimumWidth, minimumHeight
        window.nextRefresh = 0
        window:initialise()
        UI.windows[index] = window
    end
    window:addToUIManager()
    window:setVisible(true)
    window:bringToTop()
    window:checkSupplies()
    return window
end

function UI.checkFor(player)
    return UI.open(player)
end

return UI
