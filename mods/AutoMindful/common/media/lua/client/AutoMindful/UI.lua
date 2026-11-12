require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTickBox"
require "ISUI/ISLabel"
require "ISUI/ISRichTextPanel"
require "ISUI/ISProgressBar"
local Controller = require "AutoMindful/Controller"
local Progress = require "AutoMindful/Progress"

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
    gain = {r=0.45, g=0.88, b=0.56, a=1},
}

local function preferences(player)
    local data = player:getModData()
    data.AutoMindfulPreferences = data.AutoMindfulPreferences or {}
    return data.AutoMindfulPreferences
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
}
function Ledger:prerender()
    Frame.prerender(self)
    local line, report = self.line, self.window.report or {}
    local inventoryX, nearbyX = self.width * 0.67, self.width - 14
    local c = palette.muted
    local y = line + 20
    self:drawTextRight("Inventory", inventoryX, y, c.r, c.g, c.b, c.a, UIFont.Small)
    self:drawTextRight("Nearby", nearbyX, y, c.r, c.g, c.b, c.a, UIFont.Small)
    for index, row in ipairs(supplyRows) do
        y = line + 24 + index * (line + 6)
        local owned, nearby = report[row.field] or 0, report[row.nearby] or 0
        c = palette.text
        self:drawText(row.label, 12, y, c.r, c.g, c.b, c.a, UIFont.Small)
        c = owned > 0 and row.color or palette.missing
        self:drawTextRight(tostring(owned), inventoryX, y, c.r, c.g, c.b, c.a, UIFont.Small)
        c = nearby > 0 and (self.window.nearby:isSelected(1) and row.color or palette.yoga) or palette.muted
        self:drawTextRight(tostring(nearby), nearbyX, y, c.r, c.g, c.b, c.a, UIFont.Small)
    end
    c = palette.muted
    self:drawText(self.window.nearby:isSelected(1) and "Collection: enabled" or "Collection: off; nearby stock is shown",
        12, self.height - line * 2 - 10, c.r, c.g, c.b, c.a, UIFont.Small)
    self:drawText("Usable items, not days or servings", 12, self.height - line - 7, c.r, c.g, c.b, c.a, UIFont.Small)
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

function UI:checkSupplies()
    self.startError = nil
    self.checkedAt = getTimestampMs()
    self.nextRefresh = 0
    self:refresh()
end

function UI.startTraining(player, mode)
    local started, message = Controller.start(player, mode, preferences(player).collectNearby == true)
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

function UI:onStop()
    Controller.stop(self.player, "Stopped by you.")
    self.startError = nil
    self.nextRefresh = 0
    self:refresh()
end

function UI:refresh()
    local status = Controller.status(self.player)
    self.report = Controller.prepare(self.player, self.nearby:isSelected(1), true)
    self.status = status
    for _, button in ipairs(self.starts) do button:setEnable(not status.active) end
    self.stopButton:setEnable(status.active)
    self.nearby.enable = true
    local activityColor = status.active and palette.meditation or (self.startError and palette.missing or palette.text)
    local phase = status.active and (status.mode == "both" and "Training both" or status.mode == "yoga" and "Training yoga" or "Training meditation") or "Ready"
    if status.phase == "stopped" then phase = "Stopped"; activityColor = palette.yoga end
    setText(self.activity, colored(activityColor, phase) .. " <LINE> " .. colored(palette.text, self.startError or status.message))
    local now = getTimestampMs()
    for _, skill in ipairs(self.skills) do
        local level = math.max(0, math.min(10, status[skill.field] or 0))
        local progress = status.progress and status.progress[skill.field]
        skill.label:setName(string.format("%s - Level %d / 10", skill.name, level))
        skill.bar:setProgress(progress and progress.fraction or 0)
        skill.bar:setText(Progress.xpText(progress))
        skill.bar.textColor = level >= 10 and palette.yoga or (level > 0 and skill.color or palette.muted)
        local change = self.progressObserved and Progress.change(skill.sample, progress)
        if change then
            local amount = change.amount or change.levels
            local unit = change.amount and " XP" or (math.abs(amount) == 1 and " level" or " levels")
            skill.flash = {positive=change.positive, started=now,
                text=(amount > 0 and "+" or "") .. Progress.number(amount) .. unit}
        end
        skill.sample = progress
    end
    self.progressObserved = self:getIsVisible()
    self.checked:setName(getTimestampMs() - (self.checkedAt or -10000) < 3000 and "Supplies checked just now" or "Live supply refresh")
    local tips = {}
    if status.returnNotice then tips[#tips + 1] = colored(palette.yoga, status.returnNotice) end
    if status.active and status.careNotice then tips[#tips + 1] = colored(palette.yoga, status.careNotice) end
    if (status.pendingReturns or 0) > 0 then
        tips[#tips + 1] = colored(palette.yoga, tostring(status.pendingReturns) .. " borrowed item(s) awaiting return.")
    end
    if not self.nearby:isSelected(1) and ((self.report.nearbyFood or 0) + (self.report.nearbyWater or 0) + (self.report.nearbyLiterature or 0)) > 0 then
        tips[#tips + 1] = colored(palette.yoga, "Enable adjacent supplies to use the nearby stock.")
    end
    for _, warning in ipairs(self.report.warnings or {}) do
        tips[#tips + 1] = colored(palette.yoga, "- " .. warning)
    end
    if #tips == 0 then
        tips[1] = colored(palette.meditation, status.active and "Training continues. Care breaks happen only when needed."
            or "Supplies are available. Choose a training mode when you are ready.")
    end
    setText(self.guidance, table.concat(tips, " <LINE> "))
    local unread, rereads = self.report.unreadLiterature, self.report.rereadLiterature
    local literatureHelp = unread and string.format("Literature in inventory: %d unread, %d eligible rereads. ", unread, rereads or 0) or ""
    self.ledger.tooltip = "Counts refresh while you move or change inventory. Hydration includes safe drinks and hydrating food; one item can count in both food and hydration. " .. literatureHelp
        .. "Training can start with no supplies. Missing stock becomes a stop only when the survivor's condition actually requires it. Unread literature is preferred, then eligible rereads. Recently read material can be unavailable until the game's cooldown ends. Nearby supplies are used only when collection is enabled."
    self:layout()
end

function UI:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad, line = 12, getTextManager():getFontHeight(UIFont.Small)
    local row = math.max(28, line + 10)
    local width = self.width - pad * 2
    local bodyY = self:titleBarHeight() + 10
    local controlsHeight = row * 3 + line * 3 + 30
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
    y = y + activity.height + 8
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
    progress.skills = self.skills
    y = y + progress.height + 8
    self.ledger = frame(self.body, Ledger, "Supplies", 0, y, contentWidth, line * 7 + 58)
    self.ledger.line, self.ledger.window = line, self
    y = y + self.ledger.height + 8
    local guide = frame(self.body, Frame, "Preparation and returns", 0, y, contentWidth, line * 6 + 28)
    self.guideFrame = guide
    self.guidance = textPanel(guide, 12, line + 18, contentWidth - 24, guide.height - line - 23, true)
    self.guidance.marginTop, self.guidance.marginBottom = 0, 0
    self.body:setScrollHeight(y + guide.height + 4)
    y = self.body:getBottom() + 6
    self.nearby = ISTickBox:new(pad, y, width, row, "Adjacent supplies", self, UI.onNearbyChanged)
    self.nearby:initialise()
    self.nearby:addOption("Use adjacent supplies")
    self.nearby:setSelected(1, preferences(self.player).collectNearby == true)
    self.nearby.tooltip = "Collection happens only when training needs a supply. Borrowed supplies and leftover containers return to their source when it remains reachable. This can be changed during training."
    self:addChild(self.nearby)
    y = y + row + 4
    self.starts = {}
    local labels = {{"Train both", "both"}, {"Meditation", "meditation"}, {"Yoga", "yoga"}}
    local buttonWidth = (width - 12) / 3
    for index, entry in ipairs(labels) do
        local button = ISButton:new(pad + (index - 1) * (buttonWidth + 6), y, buttonWidth, row, entry[1], self, UI.onStart)
        button:initialise()
        button.mode = entry[2]
        button.tooltip = entry[2] == "both" and "Train both skills toward level 10, with recovery breaks. Close the window while it runs."
            or "Train " .. entry[1]:lower() .. " toward level 10. AutoMindful handles care breaks and resumes."
        self:addChild(button)
        self.starts[index] = button
    end
    y = y + row + 4
    self.check = ISButton:new(pad, y, width / 2 - 3, row, "Check supplies", self, UI.checkSupplies)
    self.check:initialise()
    self.check.tooltip = "Refresh the live supply report now. This does not interrupt training or collect items immediately."
    self:addChild(self.check)
    self.stopButton = ISButton:new(pad + width / 2 + 3, y, width / 2 - 3, row, "Stop training", self, UI.onStop)
    self.stopButton:initialise()
    self.stopButton.borderColor = palette.missing
    self.stopButton.tooltip = "Cancel the training loop. Closing the window only hides it."
    self:addChild(self.stopButton)
    y = y + row + 6
    self.checked = ISLabel:new(pad, y, line, "Live supply refresh", palette.meditation.r, palette.meditation.g, palette.meditation.b, 1, UIFont.Small, true)
    self.checked:initialise()
    self:addChild(self.checked)
    local footer = textPanel(self, pad, y + line + 2, width, line * 2 + 4, false)
    self.footer = footer
    footer.marginTop, footer.marginBottom = 0, 0
    setText(footer, colored(palette.muted, "Close to hide. Training continues.") .. " <LINE> "
        .. colored(palette.muted, "Shortcut: Options > Mods > AutoMindful."))
    self:layout()
end

function UI:layout()
    if not self.footer then return end
    local pad, line = 12, getTextManager():getFontHeight(UIFont.Small)
    local row = math.max(28, line + 10)
    local width = self.width - pad * 2
    local bodyY = self:titleBarHeight() + 10
    self.footer:setWidth(width)
    self.footer:paginate()
    self.footer:setHeight(math.max(line * 2 + 4, self.footer:getScrollHeight()))
    local controlsHeight = row * 3 + line + self.footer.height + 26
    self.body:setWidth(width)
    self.body:setHeight(math.max(1, self.height - bodyY - controlsHeight - 8))
    local contentWidth = width - 15
    for _, panel in ipairs({self.activityFrame, self.progressFrame, self.ledger, self.guideFrame}) do panel:setWidth(contentWidth) end
    for _, panel in ipairs({self.activity, self.guidance}) do
        panel:setWidth(contentWidth - 24)
        if panel.text then panel:paginate() end
    end
    self.activity:setHeight(math.max(line * 2, self.activity:getScrollHeight()) + 2)
    self.activityFrame:setHeight(line + 23 + self.activity.height)
    local y = self.activityFrame:getBottom() + 8
    self.progressFrame:setY(y)
    for _, skill in ipairs(self.skills) do skill.bar:setWidth(contentWidth - 24) end
    self.ledger:setY(self.progressFrame:getBottom() + 8)
    self.guideFrame:setY(self.ledger:getBottom() + 8)
    self.guidance:setHeight(math.min(line * 6, math.max(line * 2, self.guidance:getScrollHeight())) + 2)
    self.guideFrame:setHeight(line + 24 + self.guidance.height)
    self.body:setScrollHeight(self.guideFrame:getBottom() + 4)
    y = self.body:getBottom() + 6
    self.nearby:setY(y)
    self.nearby:setWidth(width)
    y = y + row + 4
    local buttonWidth = (width - 12) / 3
    for index, button in ipairs(self.starts) do
        button:setX(pad + (index - 1) * (buttonWidth + 6))
        button:setY(y)
        button:setWidth(buttonWidth)
    end
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
