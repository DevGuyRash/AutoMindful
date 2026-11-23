require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTickBox"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "RadioCom/ISUIRadio/ISSliderPanel"
local Options = require "AutoMindful/Options"

local Settings = {}
local Pane = ISCollapsableWindow:derive("AutoMindfulSettings")
local Scroll = ISPanel:derive("AutoMindfulSettingsScroll")
local active
local pad, gap = 10, 5

function Scroll:prerender()
    self:setStencilRect(0, 0, self.width, self.height)
end

function Scroll:render()
    self:clearStencilRect()
end

function Scroll:onMouseWheel(delta)
    if self:getScrollHeight() <= self.height then return false end
    self:setYScroll(self:getYScroll() - delta * 32)
    return true
end

local function translated(text)
    if not text then return nil end
    return (getText and getText(text)) or text
end

local function keyTitle(code)
    return code ~= 0 and getKeyName(code) or "Unassigned"
end

local function label(parent, x, y, height, title, tooltip)
    local item = ISLabel:new(x, y, height, title, .88, .90, .88, 1, UIFont.Small, true)
    item.tooltip = tooltip
    item:initialise()
    parent:addChild(item)
    return item
end

local function wrap(title, width)
    local font, lines, line = getTextManager(), {}, nil
    for word in title:gmatch("%S+") do
        local candidate = line and (line .. " " .. word) or word
        if line and font:MeasureStringX(UIFont.Small, candidate) > width then
            lines[#lines + 1], line = line, word
        else
            line = candidate
        end
    end
    if line then lines[#lines + 1] = line end
    return table.concat(lines, "\n"), math.max(1, #lines)
end

local function button(parent, x, y, w, h, title, target, callback)
    local item = ISButton:new(x, y, w, h, title, target, callback)
    item:initialise()
    parent:addChild(item)
    return item
end

local function selected(option)
    local value = tonumber(option:getValue())
    return (value and option.values[value]) and value or 1
end

local function sliderLabel(_, value, widget)
    widget.valueLabel:setName(tostring(value))
end

local function clearTip(control)
    local tooltip = control and control.tooltipUI
    if tooltip and tooltip:getIsVisible() then
        tooltip:setVisible(false)
        tooltip:removeFromUIManager()
    end
end

function Pane:close()
    if active ~= self then return end
    active, self.owner.settingsWindow = nil, nil
    self.captureRow = nil
    self:setWantKeyEvents(false)
    for _, row in ipairs(self.rows) do
        local control = row.control
        if row.option.type == "combobox" and control.expanded
                and control.popup and control.popup.parentCombo == control then
            control.expanded = false
            control:hidePopup() -- Never dismiss a shared popup owned by another UI.
        end
        clearTip(control)
        clearTip(row.label)
        if row.option.type == "slider" then
            clearTip(control.valueLabel)
            if control.deactivateToolTip then control:deactivateToolTip() end
        end
    end
    clearTip(self.saveButton)
    self:setVisible(false)
    self:removeFromUIManager()
end

function Pane:finishKeys()
    local row = self.captureRow
    if row then row.control:setTitle(keyTitle(row.control.keyCode)) end
    self.captureRow = nil
    self:setWantKeyEvents(false)
end

function Pane:beginKey(button)
    if self.captureRow == button.setting then
        self:finishKeys()
        return
    end
    self.captureRow = button.setting
    button:setTitle("Press a key")
    self:setWantKeyEvents(true)
    self:bringToTop()
end

function Pane:clearKey(button)
    self:finishKeys()
    local control = button.setting.control
    control.keyCode = 0
    control:setTitle(keyTitle(0))
end

function Pane:onKeyRelease(key)
    local row = self.captureRow
    if not row then return end
    -- The native UI tests isKeyConsumed after dispatching this callback.
    self.consumedRelease = key
    if key ~= Keyboard.KEY_ESCAPE and key ~= 0 and not Options.bindableWindowKey(key) then
        row.control:setTitle("Key in use")
        return
    end
    if key > 0 and key ~= Keyboard.KEY_ESCAPE then row.control.keyCode = key end
    self:finishKeys()
end

function Pane:isKeyConsumed(key)
    if self.consumedRelease == key then
        self.consumedRelease = nil
        return true
    end
    return self.captureRow ~= nil
end

function Pane:save()
    if active ~= self then return end
    self:finishKeys()
    local changes = {}
    for _, row in ipairs(self.rows) do
        local kind, control, value = row.option.type, row.control
        if kind == "tickbox" then value = control:isSelected(1)
        elseif kind == "combobox" then value = control:getSelected()
        elseif kind == "slider" then value = control:getCurrentValue()
        elseif kind == "keybind" then value = control.keyCode end
        -- Untouched controls must not revert changes made on another surface
        -- after the popup opened.
        if value ~= row.initial then changes[#changes + 1] = {option=row.option,value=value} end
    end
    local changed, refreshSupplies = Options.applyPanelChanges(changes)
    local owner = self.owner
    self:close()
    if changed and owner:getIsVisible() then
        owner.nextRefresh = 0
        if refreshSupplies then owner.forceSupplyRefresh = true end
        owner:refresh()
    end
end

function Pane:createChildren()
    ISCollapsableWindow.createChildren(self)
    -- Unlike the training panel, the short settings popup cannot auto-collapse.
    if self.collapseButton then self.collapseButton:setVisible(false) end
    local font, line = getTextManager(), getTextManager():getFontHeight(UIFont.Small)
    local rowHeight, top = line + 6, self:titleBarHeight() + pad
    local scroll = Scroll:new(pad, top, self.width - 2 * pad, 1)
    scroll:initialise()
    self:addChild(scroll)
    scroll:setScrollChildren(true)
    scroll:addScrollBars()
    self.body, self.rows = scroll, {}
    local entries = Options.modSettings().data
    local width = scroll.width - 16 -- reserve the native scroll track
    local controlW = 142
    for _, option in ipairs(entries) do
        if option.type == "combobox" then
            for _, value in ipairs(option.values) do
                controlW = math.max(controlW, font:MeasureStringX(UIFont.Small, value) + 31)
            end
        end
    end
    controlW = math.min(width, controlW)
    local y = 0
    for _, option in ipairs(entries) do
        local kind = option.type
        if kind == "tickbox" or kind == "combobox" or kind == "slider" or kind == "keybind" then
            local title, tip = translated(option.name), translated(option.tooltip)
            local size = kind == "tickbox" and rowHeight or controlW
            local right = width - size
            local separate = kind ~= "tickbox" and font:MeasureStringX(UIFont.Small, title) > right - gap
            local caption, lines = wrap(title, separate and width or right - gap)
            local labelHeight = lines * line
            local bodyHeight = math.max(labelHeight, rowHeight)
            local row = {option=option}
            row.label = label(scroll, 0, separate and y or y + math.floor((bodyHeight - labelHeight) / 2), labelHeight, caption, tip)
            local inputY = separate and y + labelHeight + 2 or y + math.floor((bodyHeight - rowHeight) / 2)
            local control
            if kind == "tickbox" then
                control = ISTickBox:new(right, inputY, size, rowHeight, "")
                control:initialise()
                control.tooltip = tip
                scroll:addChild(control)
                control:addOption("")
                control:setSelected(1, option:getValue() == true)
                control.enable = option.isEnabled ~= false
                row.initial = control:isSelected(1)
            elseif kind == "combobox" then
                control = ISComboBox:new(right, inputY, size, rowHeight)
                control:initialise()
                scroll:addChild(control)
                for index, value in ipairs(option.values) do control:addOptionWithData(value, index, tip) end
                control:setSelected(selected(option))
                control.disabled = option.isEnabled == false
                row.initial = control:getSelected()
            elseif kind == "slider" then
                local numberW = font:MeasureStringX(UIFont.Small, tostring(option.max)) + gap
                local value = tonumber(option:getValue()) or option.min
                local slider = ISSliderPanel:new(right + numberW, inputY, size - numberW, rowHeight, self, sliderLabel)
                slider:initialise()
                scroll:addChild(slider)
                slider:setValues(option.min, option.max, option.step, option.step, true)
                slider:setCurrentValue(value, true)
                slider.disabled = option.isEnabled == false
                slider.valueLabel = label(scroll, right, inputY, rowHeight, tostring(slider:getCurrentValue()), tip)
                control, row.initial = slider, slider:getCurrentValue()
            else
                local clearW = font:MeasureStringX(UIFont.Small, "Clear") + 14
                local value = tonumber(option:getValue()) or 0
                control = button(scroll, right, inputY, size - clearW - gap, rowHeight, keyTitle(value), self, Pane.beginKey)
                control.keyCode, control.setting = value, row
                control.tooltip = (tip or "") .. " Press Esc to cancel key selection."
                control:setEnable(option.isEnabled ~= false)
                local clear = button(scroll, width - clearW, inputY, clearW, rowHeight, "Clear", self, Pane.clearKey)
                clear.setting = row
                clear:setEnable(option.isEnabled ~= false)
                row.initial = value
            end
            row.control = control
            self.rows[#self.rows + 1] = row
            y = y + (separate and labelHeight + 2 + rowHeight or bodyHeight) + gap
        end
    end
    local height = math.min(self.height, top + y + pad * 3 + rowHeight)
    self:setHeight(height)
    scroll:setHeight(math.max(1, height - top - rowHeight - pad * 3))
    scroll:setScrollHeight(y)
    local footerY = height - rowHeight - pad
    local w = math.min(98, math.floor((self.width - pad * 2 - gap) / 2))
    self.cancelButton = button(self, self.width - pad - w * 2 - gap, footerY, w, rowHeight, "Cancel", self, Pane.close)
    self.saveButton = button(self, self.width - pad - w, footerY, w, rowHeight, "Save", self, Pane.save)
    self.saveButton.tooltip = "Apply and save only the AutoMindful settings you changed."
end

function Settings.toggle(owner)
    if active and active.owner == owner then active:close(); return end
    if active then active:close() end
    local core = getCore()
    local screenW, screenH = core:getScreenWidth(), core:getScreenHeight()
    local width, height = math.min(548, screenW - 16), math.min(560, screenH - 22)
    local x = owner:getX() + owner.width + 7
    if x + width > screenW then x = owner:getX() - width - 7 end
    if x < 0 then x = math.floor((screenW - width) / 2) end
    x = math.max(0, math.min(x, screenW - width))
    local y = math.max(0, math.min(owner:getY(), screenH - height))
    local pane = Pane:new(x, y, width, height)
    pane.owner, pane.title, pane.resizable = owner, "AutoMindful Settings", false
    pane.backgroundColor = {r=.09,g=.12,b=.105,a=.99}
    pane.borderColor = {r=.27,g=.32,b=.29,a=1}
    active, owner.settingsWindow = pane, pane
    pane:initialise()
    pane:addToUIManager()
    pane:setVisible(true)
    pane:bringToTop()
    return pane
end

function Settings.close(owner)
    if active and active.owner == owner then active:close() end
end

return Settings
