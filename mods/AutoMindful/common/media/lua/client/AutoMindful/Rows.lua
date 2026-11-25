-- A scrolling list of declarative rows. A view describes what to show; this
-- measures, draws, scrolls, hovers and clicks it. There are no child widgets to
-- keep in sync, so a row that is not relevant simply is not in the list.
require "ISUI/ISPanel"
require "ISUI/ISToolTip"
local Theme = require "AutoMindful/Theme"

local Rows = ISPanel:derive("AutoMindfulRows")
local colors = Theme.colors

local function color(c, alpha) return alpha or c.a, c.r, c.g, c.b end

function Rows:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.rows, o.layout, o.contentHeight = {}, {}, 0
    return o
end

function Rows:createChildren()
    self:setScrollChildren(true)
    self:addScrollBars()
end

function Rows:text(value, x, y, c, font, alpha)
    self:drawText(value, x, y, c.r, c.g, c.b, alpha or c.a, font or UIFont.Small)
end

function Rows:textRight(value, x, y, c, font)
    self:drawTextRight(value, x, y, c.r, c.g, c.b, c.a, font or UIFont.Small)
end

local function pad() return math.floor(Theme.line() * 0.55) end

-- The scroll track overlaps the right edge only while there is something to scroll.
function Rows:innerWidth()
    return self.width - pad() * 2 - (self.contentHeight > self.height and 10 or 0)
end

-- Each kind returns its height from measure and draws itself at (x, y). A kind
-- with more than one target also says where each of them is.
local kinds = {}

kinds.gap = {measure=function(row) return row.height or pad() end, draw=function() end}

kinds.head = {
    measure=function() return Theme.line() + pad() end,
    draw=function(self, row, x, y, w)
        local line = Theme.line()
        self:text(row.text, x, y + 2, colors.muted)
        if row.right then self:textRight(row.right, x + w, y + 2, colors.faint) end
        self:drawRect(x, y + line + 4, w, 1, color(colors.line))
    end,
}

kinds.title = {
    measure=function(row, w)
        local line, medium = Theme.line(), Theme.line(UIFont.Medium)
        row.lines = row.sub and Theme.wrap(row.sub, w - line * 2.6 - (row.right and Theme.width(row.right) + 8 or 0)) or {}
        return math.max(line * 2.2, medium + 2 + #row.lines * line)
    end,
    draw=function(self, row, x, y, w, h)
        local line, medium = Theme.line(), Theme.line(UIFont.Medium)
        local size = math.floor(line * 2.1)
        self:drawRect(x, y, 3, h, color(row.color))
        if row.icon then self:drawTextureScaledAspect(row.icon, x + 9, y + math.floor((h - size) / 2), size, size, 1, 1, 1, 1) end
        local tx = x + 9 + size + 8
        local room = w - (tx - x) - (row.right and Theme.width(row.right) + 8 or 0)
        self:text(Theme.fit(row.text, room, UIFont.Medium), tx, y, colors.text, UIFont.Medium)
        if row.right then self:textRight(row.right, x + w, y + math.floor((medium - line) / 2), colors.faint) end
        for index, value in ipairs(row.lines) do self:text(value, tx, y + medium + 2 + (index - 1) * line, row.tone or colors.muted) end
    end,
}

kinds.text = {
    measure=function(row, w)
        row.lines = Theme.wrap(row.text, w - (row.indent or 0) - (row.bullet and 12 or 0))
        return math.max(1, #row.lines) * Theme.line() + (row.tight and 0 or 3)
    end,
    draw=function(self, row, x, y)
        local tx = x + (row.indent or 0)
        if row.bullet then
            self:drawRect(tx + 1, y + math.floor(Theme.line() / 2) - 2, 4, 4, color(row.color or colors.muted))
            tx = tx + 12
        end
        for index, value in ipairs(row.lines) do self:text(value, tx, y + (index - 1) * Theme.line(), row.color or colors.text) end
    end,
}

kinds.job = {
    click=true,
    measure=function(row, w)
        local line = Theme.line()
        row.lines = Theme.wrap(row.sub or "", w - line * 2.6 - 24)
        return Theme.line(UIFont.Medium) + math.max(1, #row.lines) * line + pad() + (row.fraction and 6 or 0)
    end,
    draw=function(self, row, x, y, w, h, hovered)
        local line, medium = Theme.line(), Theme.line(UIFont.Medium)
        local live = not row.disabled
        self:drawRect(x, y, w, h - 4, color(hovered and live and colors.hover or colors.raised))
        self:drawRect(x, y, 3, h - 4, color(row.color, live and 1 or 0.35))
        local size = math.floor(line * 1.9)
        if row.icon then
            self:drawTextureScaledAspect(row.icon, x + 10, y + math.floor((h - 4 - size) / 2), size, size, live and 1 or 0.35, 1, 1, 1)
        end
        local tx, top = x + 10 + size + 9, y + math.floor(pad() / 2) - 1
        self:text(row.title, tx, top, live and colors.text or colors.muted, UIFont.Medium)
        for index, value in ipairs(row.lines) do
            self:text(value, tx, top + medium + (index - 1) * line, row.tone or colors.muted)
        end
        if row.menu then self:textRight(">", x + w - 8, top + math.floor((medium - line) / 2), live and colors.muted or colors.faint)
        elseif hovered and live then self:textRight("Start", x + w - 8, top + math.floor((medium - line) / 2), row.color) end
        if row.fraction then
            local by = y + h - 11
            self:drawRect(tx, by, w - (tx - x) - 8, 3, color(colors.line))
            self:drawRect(tx, by, (w - (tx - x) - 8) * math.max(0, math.min(1, row.fraction)), 3, color(row.color))
        end
    end,
}

kinds.bar = {
    measure=function() return Theme.line() + 14 end,
    draw=function(self, row, x, y, w)
        local line = Theme.line()
        self:text(row.label, x, y, colors.text)
        if row.gain then self:text(row.gain, x + Theme.width(row.label) + 10, y, row.loss and colors.bad or colors.good) end
        self:textRight(row.right or "", x + w, y, colors.muted)
        self:drawRect(x, y + line + 2, w, 5, color(colors.line))
        self:drawRect(x, y + line + 2, w * math.max(0, math.min(1, row.fraction or 0)), 5, color(row.color))
    end,
}

kinds.columns = {
    measure=function() return Theme.line() + 5 end,
    draw=function(self, row, x, y, w)
        self:text(row.label, x, y, row.color or colors.text)
        for index, cell in ipairs(row.cells) do
            self:textRight(cell.text, x + w * (0.72 + 0.28 * (index - 1)), y, cell.color or colors.muted)
        end
    end,
}

kinds.chips = {
    measure=function(row, w)
        local line, x, rows = Theme.line(), 0, 1
        for _, chip in ipairs(row.chips) do
            chip.width = Theme.width(chip.text) + (chip.icon and line + 14 or 12)
            if x > 0 and x + chip.width > w then x, rows = 0, rows + 1 end
            chip.x, chip.row = x, rows - 1
            x = x + chip.width + 6
        end
        return rows * (line + 10)
    end,
    draw=function(self, row, x, y)
        local line = Theme.line()
        for _, chip in ipairs(row.chips) do
            local cx, cy = x + chip.x, y + chip.row * (line + 10)
            self:drawRect(cx, cy, chip.width, line + 6, color(colors.raised))
            self:drawRect(cx, cy + line + 5, chip.width, 1, color(chip.color, 0.8))
            local tx = cx + 6
            if chip.icon then
                self:drawTextureScaledAspect(chip.icon, cx + 4, cy + 2, line + 2, line + 2, 1, 1, 1, 1)
                tx = cx + line + 10
            end
            self:text(chip.text, tx, cy + 3, colors.text)
        end
    end,
}

kinds.buttons = {
    measure=function() return Theme.line() + 14 end,
    zones=function(row, x, y, w, h)
        local count, gap, zones = #row.buttons, 6, {}
        local each = math.floor((w - gap * (count - 1)) / count)
        for index, button in ipairs(row.buttons) do
            zones[index] = {x=x + (index - 1) * (each + gap), y=y, w=each, h=h - 6, target=button}
        end
        return zones
    end,
    draw=function(self, row, x, y, w, h, hovered, zones)
        for _, zone in ipairs(zones) do
            local button, bx, each = zone.target, zone.x, zone.w
            local live = not button.disabled
            local over = hovered and self:over(bx, y, each, h - 6)
            local c = button.color or colors.muted
            self:drawRect(bx, y, each, h - 6, color(over and live and colors.hover or colors.raised))
            self:drawRectBorder(bx, y, each, h - 6, live and 0.85 or 0.25, c.r, c.g, c.b)
            local label = Theme.fit(button.text .. (button.menu and "  >" or ""), each - 10)
            self:text(label, bx + math.floor((each - Theme.width(label)) / 2), y + 4, live and colors.text or colors.faint)
        end
    end,
}

-- Settings rows: the label explains, the right side shows the current value.
kinds.setting = {
    click=true,
    measure=function()
        return Theme.line() + 8
    end,
    draw=function(self, row, x, y, w, h, hovered)
        if hovered and not row.disabled then self:drawRect(x - 4, y, w + 8, h - 2, color(colors.hover)) end
        local line = Theme.line()
        local right = row.value or ""
        if row.toggle ~= nil then
            local box = line - 2
            self:drawRectBorder(x + w - box, y + 4, box, box, 1, colors.border.r, colors.border.g, colors.border.b)
            if row.toggle then self:drawRect(x + w - box + 3, y + 7, box - 6, box - 6, color(row.color or colors.good)) end
        else
            self:textRight(Theme.fit(right, w * 0.55) .. (row.menu and "  >" or ""), x + w, y + 3, row.valueColor or colors.recovery)
        end
        self:text(Theme.fit(row.label, w * (row.toggle ~= nil and 0.9 or 0.45)), x, y + 3, row.disabled and colors.faint or colors.text)
    end,
}

kinds.entry = {
    measure=function(row, w)
        local line = Theme.line()
        row.clockWidth = Theme.width(row.clock or "") + 10
        row.lines = Theme.wrap(row.text, w - row.clockWidth)
        row.details = row.detail and Theme.wrap(row.detail, w - row.clockWidth) or {}
        return (#row.lines + #row.details) * line + 5
    end,
    draw=function(self, row, x, y)
        local line = Theme.line()
        self:text(row.clock or "", x, y, colors.faint)
        for index, value in ipairs(row.lines) do self:text(value, x + row.clockWidth, y + (index - 1) * line, row.color or colors.text) end
        for index, value in ipairs(row.details) do
            self:text(value, x + row.clockWidth, y + (#row.lines + index - 1) * line, colors.muted)
        end
    end,
}

function Rows:over(x, y, w, h)
    local mx, my = self:getMouseX(), self:getMouseY()
    return mx >= x and mx < x + w and my >= y and my < y + h
end

function Rows:measure()
    local x, y = pad(), pad()
    -- Width depends on whether the track shows, which depends on the height.
    for _ = 1, 2 do
        y, self.layout = pad(), {}
        local w = self:innerWidth()
        for index, row in ipairs(self.rows) do
            local h = kinds[row.kind].measure(row, w)
            local kind = kinds[row.kind]
            self.layout[index] = {row=row, x=x, y=y, w=w, h=h, zones=kind.zones and kind.zones(row, x, y, w, h) or nil}
            y = y + h
        end
        self.contentHeight = y + pad()
    end
    self:setScrollHeight(self.contentHeight)
    if self:getYScroll() < -math.max(0, self.contentHeight - self.height) then
        self:setYScroll(-math.max(0, self.contentHeight - self.height))
    end
    if self.vscroll then
        self.vscroll:setAnchorRight(false)
        self.vscroll:setAnchorBottom(false)
        self.vscroll:setX(self.width - self.vscroll.width)
        self.vscroll:setHeight(self.height)
        self.vscroll:setVisible(self.contentHeight > self.height)
    end
end

function Rows:setRows(rows)
    self.rows = rows
    self:measure()
end

-- Only react to the pointer when no other window is in front of it.
function Rows:onMouseMove() self.pointer = true end
function Rows:onMouseMoveOutside() self.pointer = nil end

function Rows:hoveredEntry()
    if not self.pointer then return nil end
    for _, entry in ipairs(self.layout) do
        if self:over(0, entry.y, self.width, entry.h) then return entry end
    end
end

function Rows:prerender()
    -- The scroll track is a child drawn after this; a stencil over it hides it.
    local track = self.vscroll and self.contentHeight > self.height and self.vscroll:getX() + 3
    self:setStencilRect(0, 0, track or self.width, self.height)
    local hovered = self:hoveredEntry()
    local top, bottom = -self:getYScroll(), -self:getYScroll() + self.height
    for _, entry in ipairs(self.layout) do
        if entry.y + entry.h >= top and entry.y <= bottom then
            kinds[entry.row.kind].draw(self, entry.row, entry.x, entry.y, entry.w, entry.h, hovered == entry, entry.zones)
        end
    end
    self:clearStencilRect()
    self:updateTip(hovered)
end

local function targetAt(self, entry)
    if not entry then return nil end
    for index, zone in ipairs(entry.zones or {}) do
        if self:over(zone.x, zone.y, zone.w, zone.h) then return zone.target, "button" .. index end
    end
    if kinds[entry.row.kind].click then return entry.row, "row" end
end

-- Rows are rebuilt while the pointer is down. The same thing in the same place
-- is the same target, even when it is a new table.
local function identity(self)
    local entry = self:hoveredEntry()
    local target, part = targetAt(self, entry)
    if not target then return nil end
    return part .. ":" .. tostring(target.text or target.title or target.label), target
end

function Rows:updateTip(entry)
    local target = targetAt(self, entry) or (entry and entry.row)
    local tip = target and target.tip
    if tip then
        if not self.tipUI then
            self.tipUI = ISToolTip:new()
            self.tipUI:initialise()
            self.tipUI:setOwner(self)
            self.tipUI:setAlwaysOnTop(true)
            self.tipUI:setVisible(false)
        end
        if not self.tipUI:getIsVisible() then
            self.tipUI:addToUIManager()
            self.tipUI:setVisible(true)
        end
        self.tipUI.description = tip
        self.tipUI:setDesiredPosition(getMouseX() + 22, getMouseY() + 22)
    else self:hideTip() end
end

function Rows:hideTip()
    if self.tipUI and self.tipUI:getIsVisible() then
        self.tipUI:setVisible(false)
        self.tipUI:removeFromUIManager()
    end
end

function Rows:onMouseDown()
    self.pressed = identity(self)
    return self.pressed ~= nil
end

function Rows:onMouseUp()
    local pressed = self.pressed
    self.pressed = nil
    local id, target = identity(self)
    if pressed and id == pressed and target.onClick and not target.disabled then
        if getSoundManager then getSoundManager():playUISound("UIActivateButton") end
        target.onClick(target)
        return true
    end
    return false
end

function Rows:onMouseUpOutside() self.pressed = nil end

function Rows:onMouseWheel(delta)
    if self.contentHeight <= self.height then return false end
    self:setYScroll(math.max(-(self.contentHeight - self.height), math.min(0, self:getYScroll() - delta * Theme.line() * 2)))
    return true
end

return Rows
