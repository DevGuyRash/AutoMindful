require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTickBox"
require "ISUI/ISRichTextPanel"
local Controller = require "AutoMindful/Controller"

AutoMindful = AutoMindful or {}
local UI = ISCollapsableWindow:derive("AutoMindfulWindow")
AutoMindful.UI = UI
UI.windows = {}

local function preferences(player)
    local data = player:getModData()
    data.AutoMindfulPreferences = data.AutoMindfulPreferences or {}
    return data.AutoMindfulPreferences
end

local function rich(text)
    return tostring(text or ""):gsub("[<>]", " "):gsub("\n", " <LINE> ")
end

function UI:savePreferences()
    local saved = preferences(self.player)
    saved.x, saved.y = self:getX(), self:getY()
    saved.collectNearby = self.nearby:isSelected(1)
end

function UI:onNearbyChanged()
    self:savePreferences()
    self:checkSupplies()
end

function UI:checkSupplies()
    local report = Controller.prepare(self.player, self.nearby:isSelected(1))
    self.checklist = report.message
    self.nextRefresh = 0
end

function UI:onStart(button)
    self:savePreferences()
    local started, message = Controller.start(self.player, button.mode, self.nearby:isSelected(1))
    self.startError = not started and message or nil
    self.nextRefresh = 0
end

function UI:onStop()
    Controller.stop(self.player, "Stopped by you.")
    self.startError = nil
    self.nextRefresh = 0
end

function UI:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad = 14
    local line = getTextManager():getFontHeight(UIFont.Small)
    local row = math.max(28, line + 10)
    local width = self.width - pad * 2
    local y = self:titleBarHeight() + 10
    self.body = ISRichTextPanel:new(pad, y, width, self.height - y - row * 3 - 62)
    self.body:initialise()
    self.body.defaultFont = UIFont.Small
    self.body.background = false
    self.body.clip = true
    self.body.marginLeft, self.body.marginRight = 4, 14
    self.body.autosetheight = false
    self.body:addScrollBars()
    self:addChild(self.body)
    y = self.body:getBottom() + 8
    self.nearby = ISTickBox:new(pad, y, width, row, "Nearby supplies", self, UI.onNearbyChanged)
    self.nearby:initialise()
    self.nearby:addOption("Use supplies in reachable adjacent containers")
    self.nearby:setSelected(1, preferences(self.player).collectNearby == true)
    self:addChild(self.nearby)
    y = y + row + 6
    self.starts = {}
    local labels = {{"Train both", "both"}, {"Meditation", "meditation"}, {"Yoga", "yoga"}}
    local buttonWidth = (width - 12) / 3
    for index, entry in ipairs(labels) do
        local button = ISButton:new(pad + (index - 1) * (buttonWidth + 6), y, buttonWidth, row, entry[1], self, UI.onStart)
        button:initialise()
        button.mode = entry[2]
        self:addChild(button)
        self.starts[index] = button
    end
    y = y + row + 6
    self.check = ISButton:new(pad, y, width / 2 - 3, row, "Check supplies", self, UI.checkSupplies)
    self.check:initialise()
    self:addChild(self.check)
    self.stopButton = ISButton:new(pad + width / 2 + 3, y, width / 2 - 3, row, "Stop training", self, UI.onStop)
    self.stopButton:initialise()
    self.stopButton.borderColor = {r=0.7, g=0.4, b=0.35, a=1}
    self:addChild(self.stopButton)
    self:checkSupplies()
end

function UI:update()
    ISCollapsableWindow.update(self)
    if self.player:isDead() then self:close(); return end
    local now = getTimestampMs()
    if now < self.nextRefresh then return end
    self.nextRefresh = now + 1000
    local status = Controller.status(self.player)
    for _, button in ipairs(self.starts) do button:setEnable(not status.active) end
    self.nearby.enable = not status.active
    self.stopButton:setEnable(status.active)
    local text = "<RGB:0.75,0.85,0.95> Meditation " .. tostring(status.meditation or 0)
        .. "/10    Yoga " .. string.format("%.1f", status.yoga or 0) .. "/10"
        .. " <BR> <RGB:1,1,1> " .. rich(self.startError or status.message)
        .. " <BR> <RGB:0.75,0.85,0.95> Preparation <LINE> <RGB:0.9,0.9,0.9> " .. rich(self.checklist)
        .. " <BR> Train both alternates skills and recovery breaks until both reach 10."
        .. " <BR> Closing this window keeps training running. Use Stop training to cancel."
    if text ~= self.body.text then
        self.body:setText(text)
        self.body:paginate()
    end
end

function UI:close()
    self:savePreferences()
    self:setVisible(false)
    self:removeFromUIManager()
end

function UI.open(player)
    local index = player:getPlayerNum()
    local window = UI.windows[index]
    if window and window.player ~= player then
        window:close()
        window = nil
    end
    if not window then
        local saved = preferences(player)
        local width = math.min(470, getCore():getScreenWidth() - 20)
        local height = math.min(540, getCore():getScreenHeight() - 40)
        local x = math.max(0, math.min(tonumber(saved.x) or 80, getCore():getScreenWidth() - width))
        local y = math.max(0, math.min(tonumber(saved.y) or 100, getCore():getScreenHeight() - height))
        window = UI:new(x, y, width, height)
        window.player = player
        window.title = "AutoMindful"
        window.resizable = false
        window.pin = true
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

return UI
