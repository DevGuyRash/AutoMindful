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
        -- The label gives way to the percentage and any gain, never overlapping them.
        local room = w - (row.right and Theme.width(row.right) + 8 or 0) - (row.gain and Theme.width(row.gain) + 10 or 0)
        local label = Theme.fit(row.label, room)
        self:text(label, x, y, colors.text)
        if row.gain then self:text(row.gain, x + Theme.width(label) + 10, y, row.loss and colors.bad or colors.good) end
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

-- A card's head: title, a short status in its colour, and a chevron. A click
-- folds the card away or opens it.
kinds.card = {
    click=true,
    measure=function() return Theme.line() + pad() + 4 end,
    draw=function(self, row, x, y, w, h, hovered)
        local line = Theme.line()
        if hovered then self:drawRect(x - 4, y, w + 8, h - 2, color(colors.hover)) end
        local accent = row.color or colors.muted
        self:drawRect(x, y + 3, 3, line, color(accent))
        self:text(row.collapsed and "+" or "-", x + w - Theme.width("+"), y + 3, hovered and colors.text or colors.muted)
        local room = w - 12 - Theme.width("+") - 8
        if row.pill then
            local text = Theme.fit(row.pill.text, math.floor(room * 0.55))
            local pw = Theme.width(text) + 10
            local pc = row.pill.color or colors.muted
            local px = x + w - Theme.width("+") - 10 - pw
            self:drawRect(px, y + 2, pw, line + 2, 0.18, pc.r, pc.g, pc.b)
            self:text(text, px + 5, y + 3, pc)
            room = px - x - 20
        end
        self:text(Theme.fit(row.title, room, UIFont.Medium), x + 10, y + 3 - math.floor((Theme.line(UIFont.Medium) - line) / 2), colors.text, UIFont.Medium)
        self:drawRect(x, y + h - 3, w, 1, color(colors.line))
    end,
}

-- A big figure, a word about it in colour, and what it means in a sentence.
kinds.headline = {
    measure=function(row, w)
        row.lines = row.sub and Theme.wrap(row.sub, w) or {}
        return Theme.line(UIFont.Large) + #row.lines * Theme.line() + 4
    end,
    draw=function(self, row, x, y, w)
        local big, line = Theme.line(UIFont.Large), Theme.line()
        self:text(row.big, x, y, colors.text, UIFont.Large)
        local bx = x + Theme.width(row.big, UIFont.Large) + 10
        local base = y + big - line - 2
        if row.word then self:text(Theme.fit(row.word, x + w - bx - (row.right and Theme.width(row.right) + 10 or 0)), bx, base, row.wordColor or colors.muted) end
        if row.right then self:textRight(row.right, x + w, base, row.rightColor or colors.muted) end
        for index, value in ipairs(row.lines) do self:text(value, x, y + big + 2 + (index - 1) * line, row.subColor or colors.muted) end
    end,
}

-- One value on a scale with shaded zones (each named underneath when there is
-- room), its marker in colour, and a hollow "ghost" where it would be after
-- something (the food being hovered). zones: {from, to, color, label}.
local function scaleX(row, x, w, value)
    local span = row.high - row.low
    return x + math.floor(w * math.max(0, math.min(1, (value - row.low) / span)) + 0.5)
end

kinds.meter = {
    measure=function(row)
        local line = Theme.line()
        return line + 3 + 8 + (row.zoneLabels == false and 0 or line) + 6
    end,
    draw=function(self, row, x, y, w)
        local line = Theme.line()
        local room = w - (row.right and Theme.width(row.right) + 8 or 0)
        self:text(Theme.fit(row.label or "", room), x, y, row.labelColor or colors.text)
        if row.right then self:textRight(row.right, x + w, y, row.rightColor or colors.muted) end
        local by, bh = y + line + 3, 8
        self:drawRect(x, by, w, bh, color(colors.line))
        for _, zone in ipairs(row.zones or {}) do
            local zx, zr = scaleX(row, x, w, zone.from), scaleX(row, x, w, zone.to)
            if zr > zx then self:drawRect(zx, by, zr - zx, bh, zone.alpha or 0.32, zone.color.r, zone.color.g, zone.color.b) end
            if row.zoneLabels ~= false and zone.label then
                local label = zone.label
                if Theme.width(label) + 4 <= zr - zx then
                    self:text(label, zx + math.floor((zr - zx - Theme.width(label)) / 2), by + bh + 2, colors.faint)
                end
            end
        end
        for _, tick in ipairs(row.ticks or {}) do
            self:drawRect(scaleX(row, x, w, tick), by - 2, 1, bh + 4, 0.7, colors.muted.r, colors.muted.g, colors.muted.b)
        end
        if row.ghost then
            local gx = scaleX(row, x, w, row.ghost)
            local vx = scaleX(row, x, w, row.value)
            local lo, hi = math.min(gx, vx), math.max(gx, vx)
            if hi > lo then self:drawRect(lo, by + 2, hi - lo, bh - 4, 0.45, colors.text.r, colors.text.g, colors.text.b) end
            self:drawRectBorder(gx - 3, by - 3, 7, bh + 6, 0.9, colors.text.r, colors.text.g, colors.text.b)
        end
        local mc = row.color or colors.text
        local mx = scaleX(row, x, w, row.value)
        self:drawRect(mx - 2, by - 3, 5, bh + 6, 1, 0, 0, 0)
        self:drawRect(mx - 1, by - 2, 3, bh + 4, 1, mc.r, mc.g, mc.b)
    end,
}

-- Side by side small gauges: a label, a value, a short bar and a note each.
-- cells: {label, value, fraction, color, note, noteColor}.
kinds.gauges = {
    measure=function(row) return Theme.line() * (row.notes == false and 1 or 2) + 9 + 4 end,
    draw=function(self, row, x, y, w)
        local line, count, gap = Theme.line(), #row.cells, 10
        local each = math.floor((w - gap * (count - 1)) / count)
        for index, cell in ipairs(row.cells) do
            local cx = x + (index - 1) * (each + gap)
            local value = cell.value or ""
            self:text(Theme.fit(cell.label, each - Theme.width(value) - 6), cx, y, colors.muted)
            self:textRight(value, cx + each, y, cell.valueColor or colors.text)
            local c = cell.color or colors.muted
            self:drawRect(cx, y + line + 2, each, 4, color(colors.line))
            self:drawRect(cx, y + line + 2, each * math.max(0, math.min(1, cell.fraction or 0)), 4, 1, c.r, c.g, c.b)
            if cell.mark then self:drawRect(cx + math.floor(each * cell.mark), y + line, 1, 8, 0.8, colors.text.r, colors.text.g, colors.text.b) end
            if cell.ghost then
                local gx = cx + math.floor(each * math.max(0, math.min(1, cell.ghost)))
                self:drawRectBorder(gx - 2, y + line, 5, 8, 0.9, colors.text.r, colors.text.g, colors.text.b)
            end
            if row.notes ~= false and cell.note then
                self:text(Theme.fit(cell.note, each), cx, y + line + 8, cell.noteColor or colors.faint)
            end
        end
    end,
}

-- Something that will happen: a coloured mark, what, and when.
kinds.event = {
    measure=function(row, w)
        row.whenWidth = row.right and Theme.width(row.right) + 10 or 0
        row.lines = Theme.wrap(row.text, w - 14 - row.whenWidth)
        return math.max(1, #row.lines) * Theme.line() + 3
    end,
    draw=function(self, row, x, y, w)
        local line, c = Theme.line(), row.color or colors.muted
        self:drawRect(x + 1, y + math.floor(line / 2) - 3, 6, 6, color(c))
        for index, value in ipairs(row.lines) do self:text(value, x + 14, y + (index - 1) * line, row.textColor or colors.text) end
        if row.right then self:textRight(row.right, x + w, y, row.rightColor or colors.muted) end
    end,
}

-- A body part: its name, each condition in its own colour, a line on what
-- comes next, and buttons at the right (Treat, Dressing).
kinds.wound = {
    measure=function(row, w)
        local line = Theme.line()
        local buttons = 0
        for _, button in ipairs(row.buttons or {}) do buttons = buttons + Theme.width(button.text .. (button.menu and "  >" or "")) + 16 + 6 end
        row.buttonWidth = buttons
        local room = w - 10
        -- The tags flow like words on the lines under the name.
        local tx, rows = 0, 1
        for _, tag in ipairs(row.tags or {}) do
            local tw = Theme.width(tag.text) + 12
            if tx > 0 and tx + tw > room then tx, rows = 0, rows + 1 end
            tag.x, tag.row = tx, rows
            tx = tx + tw
        end
        row.tagRows = #(row.tags or {}) > 0 and rows or 0
        row.lines = row.sub and Theme.wrap(row.sub, room) or {}
        return line + 2 + row.tagRows * line + #row.lines * line + pad()
    end,
    zones=function(row, x, y, w)
        local zones, bx = {}, x + w
        local line = Theme.line()
        for index = #(row.buttons or {}), 1, -1 do
            local button = row.buttons[index]
            local bw = Theme.width(button.text .. (button.menu and "  >" or "")) + 16
            bx = bx - bw
            zones[#zones + 1] = {x=bx, y=y, w=bw, h=line + 4, target=button}
            bx = bx - 6
        end
        return zones
    end,
    draw=function(self, row, x, y, w, h, hovered, zones)
        local line = Theme.line()
        if hovered then self:drawRect(x - 4, y - 1, w + 8, h - 2, color(colors.raised)) end
        self:drawRect(x, y, 3, h - pad() + 2, color(row.color or colors.muted))
        local tx = x + 10
        self:text(Theme.fit(row.title, w - 10 - (row.buttonWidth or 0)), tx, y + 1, colors.text)
        for _, tag in ipairs(row.tags or {}) do
            self:text(tag.text, tx + tag.x, y + 3 + tag.row * line, tag.color or colors.muted)
        end
        local sy = y + 2 + line + row.tagRows * line
        for index, value in ipairs(row.lines) do self:text(value, tx, sy + (index - 1) * line, row.subColor or colors.muted) end
        for _, zone in ipairs(zones or {}) do
            local button = zone.target
            -- A quiet button shows only while the row is under the pointer.
            if hovered or not button.hoverOnly then
                local over = hovered and self:over(zone.x, zone.y, zone.w, zone.h)
                local live = not button.disabled
                local c = button.color or colors.recovery
                self:drawRect(zone.x, zone.y, zone.w, zone.h, color(over and live and colors.hover or colors.raised))
                self:drawRectBorder(zone.x, zone.y, zone.w, zone.h, live and 0.8 or 0.25, c.r, c.g, c.b)
                local label = button.text .. (button.menu and "  >" or "")
                self:text(label, zone.x + math.floor((zone.w - Theme.width(label)) / 2), zone.y + 2, live and colors.text or colors.faint)
            end
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
    -- A menu opened from a row has the pointer now.
    if ISContextMenu and ISContextMenu.instance and ISContextMenu.instance.visibleCheck then entry = nil end
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
