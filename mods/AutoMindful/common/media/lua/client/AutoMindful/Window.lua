require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISContextMenu"
local Controller = require "AutoMindful/Controller"
local Jobs = require "AutoMindful/Jobs"
local Log = require "AutoMindful/Log"
local Options = require "AutoMindful/Options"
local Preferences = require "AutoMindful/Preferences"
local Rows = require "AutoMindful/Rows"
local Theme = require "AutoMindful/Theme"
local Tiers = require "AutoMindful/TierTargets"
local Views = require "AutoMindful/Views"

AutoMindful = AutoMindful or {}
local Window = ISCollapsableWindow:derive("AutoMindfulWindow")
AutoMindful.UI = Window
Window.windows = {}

local colors = Theme.colors
local refreshMs = 500

-- A flat strip of text tabs. Settings sits at the right, apart from the content.
local Tabs = ISPanel:derive("AutoMindfulTabs")
function Tabs:onMouseMove() self.pointer = true end
function Tabs:onMouseMoveOutside() self.pointer = nil end
function Tabs:at()
    if not self.pointer then return nil end
    local x = self:getMouseX()
    for _, tab in ipairs(self.slots or {}) do if x >= tab.x and x < tab.x + tab.w then return tab end end
end
function Tabs:arrange()
    local x, gap, line = 6, 2, Theme.line()
    self.slots = {}
    for _, view in ipairs(Views.order) do
        local w = Theme.width(view.title) + line
        local slot = {id=view.id, title=view.title, w=w, x=x}
        if view.id == "settings" then slot.x = math.max(x, self.width - w - 6) end
        self.slots[#self.slots + 1] = slot
        x = slot.x + w + gap
    end
end
function Tabs:prerender()
    local line, over = Theme.line(), self:at()
    self:drawRect(0, self.height - 1, self.width, 1, colors.line.a, colors.line.r, colors.line.g, colors.line.b)
    for _, tab in ipairs(self.slots or {}) do
        local active = tab.id == self.window.view
        local c = active and colors.text or tab == over and colors.text or colors.muted
        if tab == over and not active then self:drawRect(tab.x, 0, tab.w, self.height - 1, colors.raised.a, 1, 1, 1) end
        self:drawText(tab.title, tab.x + math.floor(line / 2), math.floor((self.height - line) / 2), c.r, c.g, c.b, 1, UIFont.Small)
        if active then
            local a = colors[self.window.accent or "recovery"]
            self:drawRect(tab.x, self.height - 2, tab.w, 2, 1, a.r, a.g, a.b)
        end
    end
end
function Tabs:onMouseDown()
    local tab = self:at()
    if tab then self.window:show(tab.id) end
    return tab ~= nil
end

-- A running job reduced to one line, for leaving on screen.
local Strip = ISPanel:derive("AutoMindfulStrip")
function Strip:prerender()
    local window, line = self.window, Theme.line()
    local status = window.status or {}
    local c = colors[Jobs.colors[status.mode] or "recovery"]
    self:drawRect(0, 0, 3, self.height, 1, c.r, c.g, c.b)
    local icon = Theme.icon(Jobs.icons[status.mode] or "Mindful")
    if icon then self:drawTextureScaledAspect(icon, 8, math.floor((self.height - line) / 2), line, line, 1, 1, 1, 1) end
    local text = status.active and (Theme.plain(status.decisionLabel) or Jobs.title(status)) or "Nothing running"
    local stop = Theme.width("Stop")
    self.stopX = self.width - stop - 10
    local over = self.pointer and self:getMouseX() >= self.stopX - 4
    local tone = over and colors.bad or colors.muted
    self:drawText("Stop", self.stopX, math.floor((self.height - line) / 2), tone.r, tone.g, tone.b, 1, UIFont.Small)
    self:drawText(Theme.fit(text, self.stopX - line - 24), line + 16, math.floor((self.height - line) / 2),
        colors.text.r, colors.text.g, colors.text.b, 1, UIFont.Small)
    local kind = status.mode == "both" and status.cycle and (status.cycle.nextKind or status.cycle.due)
        or (status.mode == "yogaTo" or status.mode == "yoga") and "yoga" or "meditation"
    local progress = status.active and status.mode ~= "recovery" and status.progress and status.progress[kind]
    if progress and not progress.capped then
        self:drawRect(3, self.height - 3, (self.width - 3) * progress.fraction, 3, 0.9, c.r, c.g, c.b)
    end
end
function Strip:onMouseMove() self.pointer = true end
function Strip:onMouseMoveOutside() self.pointer = nil end
function Strip:onMouseDown()
    if not self.pointer or self:getMouseX() < (self.stopX or self.width) - 4 then return false end
    Jobs.stop(self.window.player, "strip")
    return true
end

local function clamp(value, low, high) return math.max(low, math.min(value, high)) end

function Window:metrics()
    local core, line = getCore(), Theme.line()
    local screenW, screenH = core:getScreenWidth(), core:getScreenHeight()
    return {screenW=screenW, screenH=screenH, line=line,
        minWidth=math.min(line * 15, screenW - 16), width=math.min(line * 21, screenW - 16),
        minHeight=math.min(line * 9, screenH - 30), maxHeight=math.floor(screenH * 0.82)}
end

-- Fit the content until the player chooses a size. Within one view the window
-- only grows, so a line of status appearing does not make it jump about.
function Window:fit(reset)
    local m, g = self:metrics(), self.geometry
    local top = self:titleBarHeight()
    local mini = g.mini and self.status and self.status.active
    local width = clamp(mini and math.floor(m.line * 15) or g.width or m.width, m.minWidth, m.screenW - 8)
    local height
    if mini then height = top + m.line + 12
    elseif g.height then height = clamp(g.height, m.minHeight, m.screenH - 8)
    else
        local wanted = top + self.tabs.height + self.body.contentHeight + self:resizeWidgetHeight()
        if reset then self.grown = 0 end
        self.grown = math.max(self.grown or 0, wanted)
        height = clamp(self.grown, m.minHeight, m.maxHeight)
    end
    self.fitting = true
    if self.width ~= width then self:setWidth(width) end
    if self.height ~= height then self:setHeight(height) end
    if not self.moving then -- the player has hold of it
        self:setX(clamp(g.x or 70, 0, math.max(0, m.screenW - width)))
        self:setY(clamp(g.y or 70, 0, math.max(0, m.screenH - height)))
    end
    self.fitting = nil
    self.mini = mini
    self:arrange()
end

function Window:arrange()
    if not self.body then return end
    local top, rh = self:titleBarHeight(), self:resizeWidgetHeight()
    self.tabs:setVisible(not self.mini)
    self.body:setVisible(not self.mini)
    self.strip:setVisible(self.mini == true)
    self.resizeWidget:setVisible(not self.mini)
    self.resizeWidget2:setVisible(not self.mini)
    -- Anchors only follow size changes after the first frame; this window is
    -- fitted before it.
    self.resizeWidget:setX(self.width - rh); self.resizeWidget:setY(self.height - rh)
    self.resizeWidget2:setX(0); self.resizeWidget2:setY(self.height - rh); self.resizeWidget2:setWidth(self.width - rh)
    self.tabs:setWidth(self.width)
    self.tabs:arrange()
    self.body:setWidth(self.width - 2)
    self.body:setHeight(math.max(1, self.height - top - self.tabs.height - rh))
    self.strip:setWidth(self.width)
    self.strip:setHeight(math.max(1, self.height - top))
    local size = top - 2
    self.miniButton:setX(self.width - size * 2 - 6)
    self.miniButton:setVisible(self.status ~= nil and self.status.active == true)
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top, line = self:titleBarHeight(), Theme.line()
    self.tabs = Tabs:new(0, top, self.width, line + 10)
    self.tabs.background, self.tabs.window = false, self
    self.tabs:initialise()
    self:addChild(self.tabs)
    self.body = Rows:new(1, top + self.tabs.height, self.width - 2, 10)
    self.body:initialise()
    self:addChild(self.body)
    self.strip = Strip:new(0, top, self.width, 10)
    self.strip.background, self.strip.window = false, self
    self.strip:initialise()
    self:addChild(self.strip)
    -- A child that ignores the right button would swallow it.
    for _, part in ipairs({self.tabs, self.body, self.strip}) do
        part.onRightMouseUp = function() return self:onRightMouseUp() end
    end
    local size = top - 2
    self.miniButton = ISButton:new(self.width - size * 2 - 6, 1, size, size, "_", self, Window.toggleMini)
    self.miniButton.tooltip = "Shrink to one line, or back."
    self.miniButton:initialise()
    self.miniButton.borderColor.a, self.miniButton.backgroundColor.a = 0, 0
    self:addChild(self.miniButton)
    -- The stock pin collapses a window to its title on mouse-out, which hides
    -- exactly what this one is for. It stays put; the mini strip replaces it.
    self.pin = true
    self.collapseButton:setVisible(false)
    self.pinButton:setVisible(false)
    for _, part in ipairs({self.resizeWidget, self.resizeWidget2, self.tabs, self.body, self.strip, self.miniButton}) do
        -- arrange() places every part. Letting the game move them as well puts
        -- each one a step too far, which a drag then measures itself against.
        part:setAnchorRight(false)
        part:setAnchorBottom(false)
    end
    self:bindHandle(self.resizeWidget, true)
    self:bindHandle(self.resizeWidget2, false)
end

-- A drag is measured on the screen from where the button went down. Nothing the
-- window does to itself on the way can change that.
function Window:bindHandle(widget, corner)
    local window = self
    local function release()
        local drag = window.resize
        window.resize, widget.resizing = nil, false
        widget:setCapture(false)
        if drag and drag.changed then
            Log.detail(window.player, "ui.resize", "width", window.width, "height", window.height)
            window:saveGeometry()
        end
        return true
    end
    local function drag()
        local held = window.resize
        if not held or held.widget ~= widget then return end
        local width = corner and held.width + getMouseX() - held.mouseX or nil
        local height = held.height + getMouseY() - held.mouseY
        if not held.changed and height == held.height and (width or held.width) == held.width then return end
        held.changed = true
        window:onUserResize(width, height)
    end
    widget.onMouseDown = function(control)
        if not control:getIsVisible() then return end
        window.resize = {widget=widget, mouseX=getMouseX(), mouseY=getMouseY(), width=window.width, height=window.height}
        control.resizing = true
        control:setCapture(true)
        return true
    end
    widget.onMouseMove = function(control) control.mouseOver = true; drag() end
    widget.onMouseMoveOutside = function(control) control.mouseOver = false; drag() end
    widget.onMouseUp, widget.onMouseUpOutside = release, release
    -- The game sends this instead of the second press.
    widget.onMouseDoubleClick = function()
        window:resetSize(corner)
        return true
    end
end

-- The corner sets both sizes, the bottom edge only the height.
function Window:onUserResize(width, height)
    local m, g = self:metrics(), self.geometry
    g.x, g.y = self:getX(), self:getY()
    if width then g.width = clamp(math.floor(width), m.minWidth, m.screenW - g.x) end
    g.height = clamp(math.floor(height), m.minHeight, m.screenH - g.y)
    self:fit()
    self.body:measure()
    self:fit()
end

function Window:saveGeometry()
    local g = self.geometry
    if Preferences.saveGeometry(self.player, g) then return end
    self.geometryUnsaved = true
end

function Window:finishMove()
    local origin = self.dragOrigin
    self.dragOrigin = nil
    if not origin or (origin.x == self:getX() and origin.y == self:getY()) then return end
    self.geometry.x, self.geometry.y = math.floor(self:getX()), math.floor(self:getY())
    self:saveGeometry()
end

function Window:onMouseDown(x, y)
    local result = ISCollapsableWindow.onMouseDown(self, x, y)
    if self.moving then self.dragOrigin = {x=self:getX(), y=self:getY()} end
    return result
end

function Window:onMouseUp(x, y)
    local result = ISCollapsableWindow.onMouseUp(self, x, y)
    self:finishMove()
    return result
end

function Window:onMouseUpOutside(x, y)
    local result = ISCollapsableWindow.onMouseUpOutside(self, x, y)
    self:finishMove()
    return result
end

function Window:onRightMouseUp()
    if not self.status then return false end
    local menu = self:menu()
    if self.status.active then menu:addOption("Stop", self, Window.stopFromMenu) end
    if self.geometry.height or self.geometry.width then menu:addOption("Fit window to contents", self, Window.resetSize) end
    menu:addOption("Close", self, Window.close)
    return true
end

function Window:stopFromMenu() Jobs.stop(self.player, "window-menu") end

-- Back to fitting the contents: both sizes, or only the height.
function Window:resetSize(both)
    if both ~= false then self.geometry.width = nil end
    self.geometry.height = nil
    Log.detail(self.player, "ui.fit", "width", both ~= false)
    self:saveGeometry()
    self:invalidate(true)
end

function Window:toggleMini()
    self.geometry.mini = not self.geometry.mini or nil
    Log.detail(self.player, "ui.mini", "on", self.geometry.mini == true)
    self:saveGeometry()
    self:invalidate(true)
end

function Window:menu()
    return ISContextMenu.get(self.player:getPlayerNum(), getMouseX(), getMouseY())
end

local function pick(menu, label, checked, target, callback, ...)
    local option = menu:addOption(label, target, callback, ...)
    if option and checked then menu:setOptionChecked(option, true) end
    return option
end

function Window:chooseJob(job)
    Log.event(self.player, "ui.choose", "job", job.id, "disabled", job.disabled, "reason", job.reason)
    if job.id == "tier" then
        Jobs.fillTiers(self:menu(), self.player, job.tiers)
        return
    end
    Jobs.launch(self.player, job.mode)
end

function Window:openSwitchMenu()
    local menu = self:menu()
    for _, job in ipairs((Jobs.list(self.player, self.status))) do
        if not job.running then
            local option = menu:addOption(job.title, self, Window.chooseJob, job)
            if option then
                option.iconTexture = Theme.icon(job.icon)
                option.notAvailable = job.disabled
                if job.id == "tier" then
                    local sub = ISContextMenu:getNew(menu)
                    menu:addSubMenu(option, sub)
                    option.onSelect = nil
                    Jobs.fillTiers(sub, self.player, job.tiers)
                end
            end
        end
    end
end

function Window:setRange(id)
    Preferences.setRange(self.player, id)
    Controller.setCollectNearby(self.player, Preferences.collectNearby(self.player))
    Log.event(self.player, "ui.setting", "supplyRange", id)
    self:lookAgain()
end

function Window:openRangeMenu()
    local menu, current = self:menu(), Preferences.range(self.player)
    for _, entry in ipairs(Preferences.ranges) do pick(menu, entry.label, entry.id == current, self, Window.setRange, entry.id) end
end

function Window:setOption(id, value)
    Options.set(id, value)
    Log.event(self.player, "ui.setting", id, value)
    self:lookAgain()
end

function Window:openRadiusMenu()
    local menu, current = self:menu(), Options.searchRadius()
    for _, tiles in ipairs({3, 5, 8, 10, 15, 20, 25, 30}) do
        pick(menu, tiles .. " tiles", tiles == current, self, Window.setOption, "searchRadius", tiles)
    end
end

function Window:openAwayMenu()
    local menu = self:menu()
    for index, minutes in ipairs(Options.awayMinutes) do
        pick(menu, minutes == 1 and "1 minute" or minutes .. " minutes", index == Options.awayIndex(), self, Window.setOption, "recoveryAway", index)
    end
end

function Window:openCycleMenu()
    local menu = self:menu()
    for index, entry in ipairs(Options.cycleChoices()) do
        pick(menu, entry.label, index == Options.cycleIndex(), self, Window.setOption, "cyclePolicy", index)
    end
end

function Window:openMinimumMenu(group)
    local menu = self:menu()
    for _, item in ipairs(Options.minimumItems(group)) do
        local parent = menu:addOption(item.label .. ": " .. item.choices[item.index].label, nil, nil)
        local sub = ISContextMenu:getNew(menu)
        menu:addSubMenu(parent, sub)
        for index, choice in ipairs(item.choices) do
            local option = pick(sub, choice.label, index == item.index, self, Window.setOption, item.id, index)
            if option and choice.tier > 0 then
                option.iconTexture, option.color = Tiers.texture(item.kind, choice.tier)
                if not option.iconTexture then option.color = nil end
            end
        end
    end
end

function Window:openLogMenu()
    local menu = self:menu()
    for index, label in ipairs(Options.logLabels) do
        pick(menu, label, index == Options.logLevel(), self, Window.setOption, "logLevel", index)
    end
end

function Window:copyReport()
    local ok = pcall(function() Clipboard.setClipboard(Views.report(self.player, self.status)) end)
    Log.flush()
    self.copied = ok and "Copied." or "The clipboard is not available here."
    self:invalidate()
end

function Window:beginCapture()
    self.capturing, self.keyTaken = not self.capturing or nil, nil
    self:setWantKeyEvents(self.capturing == true)
    self:invalidate()
end

function Window:onKeyRelease(key)
    if not self.capturing then return end
    self.consumed = key
    if key ~= Keyboard.KEY_ESCAPE and key ~= 0 and not Options.bindableWindowKey(key) then
        self.keyTaken = getKeyName(key)
        self:invalidate()
        return
    end
    self.capturing, self.keyTaken = nil, nil
    self:setWantKeyEvents(false)
    if key > 0 and key ~= Keyboard.KEY_ESCAPE then Options.set("openWindow", key) end
    self:invalidate()
end

function Window:isKeyConsumed(key)
    if self.consumed == key then self.consumed = nil; return true end
    return self.capturing == true
end

function Window:show(id)
    if self.view == id then return end
    Log.detail(self.player, "ui.tab", "view", id)
    self.view, self.copied = id, nil
    if self.capturing then self:beginCapture() end
    self.body:setYScroll(0)
    self.forceSupplies = id == "supplies"
    self:invalidate(true)
end

function Window:lookAgain()
    self.forceSupplies = true
    self:invalidate()
end

-- Rebuild now. `reset` also lets an unsized window shrink to the new content.
function Window:invalidate(reset)
    self.nextRefresh = 0
    if reset then self.resetFit = true end
    if self:getIsVisible() and self.body then self:refresh() end
end

local supplyViews = {now=true, supplies=true}

function Window:refresh()
    local player = self.player
    self.status = Controller.status(player)
    local now = getTimestampMs()
    -- The radius scan belongs to the views that show it, at a calm pace.
    local running = self.status.active or self.status.switching
    local mini = self.geometry.mini and self.status.active
    if supplyViews[self.view] and not mini and not (running and self.view == "now")
            and (self.forceSupplies or not self.reportAt or now < self.reportAt or now - self.reportAt >= (self.view == "supplies" and 1000 or 5000)) then
        self.report = Controller.prepare(player, Preferences.collectNearby(player), true, self.forceSupplies)
        self.reportAt, self.forceSupplies = now, nil
    end
    if self.wasRunning ~= running then self.wasRunning, self.resetFit = running, true end
    if running then self.startError = nil end
    self.accent = running and Jobs.colors[self.status.mode] or "recovery"
    self.title = self.geometry.mini and running and Jobs.title(self.status) or "AutoMindful"
    self.body:setRows(Views[self.view](self))
    local reset = self.resetFit
    self.resetFit = nil
    self:fit(reset)
    self.body:measure()
end

function Window:update()
    ISCollapsableWindow.update(self)
    if not self:getIsVisible() then return end
    if self.player:isDead() then self:close(); return end
    local now = getTimestampMs()
    if now < self.nextRefresh then return end
    self.nextRefresh = now + refreshMs
    self:refresh()
end

function Window:onResize()
    ISCollapsableWindow.onResize(self)
    if not self.fitting then self:arrange() end
end

function Window:close()
    if self.capturing then self:beginCapture() end
    self:finishMove()
    self.body:hideTip()
    Log.detail(self.player, "ui.close")
    self:setVisible(false)
    self:removeFromUIManager()
end

function Window.open(player)
    local index = player:getPlayerNum()
    local window = Window.windows[index]
    if window and window.player ~= player then window:close(); window = nil end
    if not window then
        window = Window:new(70, 70, 400, 300)
        window.player, window.title, window.view = player, "AutoMindful", "now"
        window.backgroundColor, window.borderColor = colors.window, colors.border
        window.geometry = Preferences.geometry(player)
        window.resizable, window.nextRefresh, window.grown = true, 0, 0
        window:initialise()
        Window.windows[index] = window
    end
    window:addToUIManager()
    window:setVisible(true)
    window:bringToTop()
    window.forceSupplies, window.resetFit = true, true
    window:refresh()
    Log.event(player, "ui.open", "view", window.view, "mode", window.status.mode, "active", window.status.active)
    return window
end

function Window.toggle(player)
    local window = Window.windows[player:getPlayerNum()]
    if window and window.player == player and window:getIsVisible() then window:close(); return end
    return Window.open(player)
end

return Window
