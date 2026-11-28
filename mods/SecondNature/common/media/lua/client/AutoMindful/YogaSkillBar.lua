require "XpSystem/ISUI/ISSkillProgressBar"
require "ISUI/ISToolTip"
local Progress = require "AutoMindful/Progress"
local Wellness = require "AutoMindful/WellnessInfo"

local YogaSkillBar = ISSkillProgressBar:derive("AutoMindfulYogaSkillBar")
AutoMindful = AutoMindful or {}
AutoMindful.YogaSkillBar = YogaSkillBar

local cellCount = 10
local filledPath = "media/ui/SkillPanel/SkillUnit_Fill.png"
local borderPath = "media/ui/SkillPanel/SkillUnit_Border.png"

function YogaSkillBar:sample()
    -- Follow the owning pane, including a new local survivor in the same pane.
    local ok, progress = pcall(Progress.yoga, self.parent.char)
    self.progress = ok and progress or nil
    self.level = self.progress and self.progress.level or 0
end

function YogaSkillBar:drawUnit(texture, x, width, r, g, b, border)
    if texture then
        self:drawTextureScaled(texture, x, 0, width, self.cellSize, 1, r, g, b)
    elseif border then
        self:drawRectBorder(x, 0, width, self.cellSize, 1, r, g, b)
    else
        self:drawRect(x, 0, width, self.cellSize, 1, r, g, b)
    end
end

function YogaSkillBar:renderPerkRect()
    -- Render the genuine hidden-skill sample; never send it through native perks.
    self.SkillUnitFilled = self.SkillUnitFilled or getTexture(filledPath)
    self.SkillUnitBorder = self.SkillUnitBorder or getTexture(borderPath)
    local p, size = self.progress, self.cellSize
    for i = 0, cellCount - 1 do
        local x = i * self.cellStride
        if p and i < p.level then
            self:drawUnit(self.SkillUnitFilled, x, size, 1, .89, .38)
            self:drawUnit(self.SkillUnitBorder, x, size, 1, .89, .38, true)
        elseif p and i == p.level then
            if p.fraction >= 1 then
                self:drawUnit(self.SkillUnitFilled, x, size, 1, .89, .38)
                self:drawUnit(self.SkillUnitBorder, x, size, 1, 1, 1, true)
            else
                self:drawUnit(self.SkillUnitBorder, x, size, .4, .4, .4, true)
                if p.fraction > 0 then
                    self:drawUnit(self.SkillUnitFilled, x, size * p.fraction, .4, .4, .4)
                end
            end
        else
            self:drawUnit(self.SkillUnitBorder, x, size, .2, .2, .2, true)
        end
    end
end

function YogaSkillBar:getName()
    if self.viewDescriptor and self.viewDescriptor.getName then
        local ok, label = pcall(self.viewDescriptor.getName, self.viewDescriptor)
        if ok and type(label) == "string" and label ~= "" then return label end
    end
    return "Yoga"
end

function YogaSkillBar:describe(cell)
    local p = self.progress
    local words = xpSystemText or {}
    local rank = cell + 1
    local title = self:getName() .. " " .. (words.lvl or "Level") .. " " .. rank
    if not p then return title .. " <LINE> XP unavailable" end
    local state
    if cell < p.level then
        state = words.unlocked or "Unlocked"
        if p.capped and cell == cellCount - 1 then state = state .. " <LINE> MAX" end
    elseif cell == p.level then
        state = getText("IGUI_XP_tooltipxp", Progress.number(p.current), Progress.number(p.required))
    else
        state = words.locked or "Locked"
    end
    return title .. " <LINE> " .. state .. Wellness.yogaTooltip(self.parent.char, p, rank)
end

function YogaSkillBar:updateTooltip(cell)
    self:sample()
    self.message = self:describe(math.max(0, math.min(cellCount - 1, math.floor(cell))))
end

function YogaSkillBar:onMouseMove()
    local cell = math.floor(self:getMouseX() / self.cellStride)
    if not self:isMouseOver() or cell < 0 or cell >= cellCount then
        self:onMouseMoveOutside()
        return
    end
    self.hoverCell = cell
    self:updateTooltip(cell)
end

function YogaSkillBar:removeTooltip()
    self.hoverCell = nil
    ISSkillProgressBar.removeTooltip(self)
end

function YogaSkillBar:onMouseMoveOutside()
    self:removeTooltip()
end

function YogaSkillBar:render()
    self:sample()
    self:renderPerkRect()
    local pane = self.parent
    local selected = pane.joyfocus and pane.joypadIndex and pane.progressBars
        and pane.progressBars[pane.joypadIndex] == self
    local cell = self.hoverCell
    if selected then
        cell = math.min(self.level, cellCount - 1)
    elseif not self:isMouseOver() or (self.tooltip and self.tooltip:isMouseOver()) then
        self:onMouseMoveOutside()
        return
    end
    if cell == nil then self:removeTooltip(); return end
    self.message = self:describe(cell)
    if not self.tooltip then
        self.tooltip = ISToolTip:new()
        self.tooltip:initialise()
        self.tooltip:addToUIManager()
        self.tooltip:setOwner(self)
    end
    local tip, core = self.tooltip, getCore()
    if tip.description ~= self.message then
        tip.description = self.message
        -- Stock uses an exact type check for its own bar. Measure a changed
        -- description now so the very first longer Yoga tooltip can fit.
        if tip.doLayout then tip:doLayout() end
    end
    local x, rowTop = self:getAbsoluteX(), self:getAbsoluteY()
    local pad, height = selected and 1 or 8, tip:getHeight()
    local y = rowTop + self:getHeight() + pad
    local screenHeight = core:getScreenHeight()
    if y + height > screenHeight then y = rowTop - height - pad end
    y = math.max(0, math.min(y, screenHeight - height))
    if core.getScreenWidth and tip.getWidth then
        x = math.max(0, math.min(x, core:getScreenWidth() - tip:getWidth()))
    end
    tip.followMouse = not selected
    tip:setDesiredPosition(x, y)
end

-- Both stock click and joypad A are deliberately inert for a hidden Yoga rank.
function YogaSkillBar:onMouseUp() end
function YogaSkillBar:activate() end

function YogaSkillBar:new(x, y, width, height, playerNum, viewDescriptor, parent, neighbor)
    local size, stride
    if neighbor then
        -- Stock caches its geometry at module load, and a live UI scale change
        -- can leave the current font options different from its actual bars.
        local nativeHeight, nativeWidth = neighbor:getHeight(), neighbor:getWidth()
        if type(nativeHeight) == "number" and nativeHeight > 0 and nativeHeight < math.huge
            and type(nativeWidth) == "number" and nativeWidth < math.huge
            and nativeWidth >= nativeHeight * cellCount then
            size, stride = nativeHeight, nativeWidth / cellCount
        end
    end
    if not size then
        size = math.floor((getTextManager():getFontHeight(UIFont.Small) + 6) / 2)
        stride = size + getCore():getOptionFontSizeReal()
    end
    local o = ISPanel:new(x, y, stride * cellCount, size)
    setmetatable(o, self)
    self.__index = self
    o.playerNum, o.parent, o.viewDescriptor = playerNum, parent, viewDescriptor
    o.cellSize, o.cellStride = size, stride
    o:noBackground()
    o:sample()
    return o
end

return YogaSkillBar
