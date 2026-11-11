package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
for _, name in ipairs({"ISCollapsableWindow", "ISPanel", "ISButton", "ISTickBox", "ISLabel", "ISRichTextPanel", "ISProgressBar", "ISContextMenu", "ISToolTip"}) do
    package.loaded["ISUI/" .. name] = true
end
package.loaded["PZAPI/ModOptions"] = true
package.loaded["ISMeditation/ZenWellnessContextMenu"] = true

local Widget = {}
function Widget:derive(name) return setmetatable({Type=name, __index=self}, {__index=self}) end
function Widget:new(x, y, width, height)
    local object = {x=x or 0, y=y or 0, width=width or 0, height=height or 0, children={}, visible=true, draws={}}
    return setmetatable(object, {__index=self})
end
function Widget:initialise() end
function Widget:addChild(child) self.children[#self.children + 1] = child end
function Widget:addToUIManager()
    if not self.created and self.createChildren then self.created = true; self:createChildren() end
    self.visible = true
end
function Widget:removeFromUIManager() self.removed = true end
function Widget:setVisible(value) self.visible = value end
function Widget:getIsVisible() return self.visible end
function Widget:getX() return self.x end
function Widget:getY() return self.y end
function Widget:setX(value) self.x = value end
function Widget:setY(value) self.y = value end
function Widget:setWidth(value) self.width = value end
function Widget:getBottom() return self.y + self.height end
function Widget:setHeight(value) self.height = value end
function Widget:setEnable(value) self.enable = value end
function Widget:bringToTop() end
function Widget:setScrollChildren(value) self.scrollChildren = value end
function Widget:addScrollBars() self.hasScrollbars = true end
function Widget:setScrollHeight(value) self.scrollHeight = value end
function Widget:getScrollHeight() return self.scrollHeight or 0 end
function Widget:setYScroll(value) self.scrollY = value end
function Widget:getYScroll() return self.scrollY or 0 end
function Widget:setStencilRect() end
function Widget:clearStencilRect() end
function Widget:drawText(text, x, y, r, g, b, a) self.draws[#self.draws + 1] = {text=text,x=x,y=y,r=r,g=g,b=b,a=a} end
Widget.drawTextRight = Widget.drawText
ISPanel = Widget:derive("ISPanel")
function ISPanel:prerender() end
ISCollapsableWindow = ISPanel:derive("ISCollapsableWindow")
function ISCollapsableWindow:createChildren() end
function ISCollapsableWindow:update() end
function ISCollapsableWindow:onResize() end
function ISCollapsableWindow:titleBarHeight() return 24 end
ISButton = Widget:derive("ISButton")
ISTickBox = Widget:derive("ISTickBox")
function ISTickBox:addOption(label) self.option = label end
function ISTickBox:setSelected(_, value) self.selected = value end
function ISTickBox:isSelected() return self.selected == true end
ISLabel = Widget:derive("ISLabel")
function ISLabel:new(x, y, height, name)
    local label = Widget.new(self, x, y, 100, height)
    label.name = name
    return label
end
function ISLabel:setName(name) self.name = name end
function ISLabel.updateTooltip() end
ISRichTextPanel = Widget:derive("ISRichTextPanel")
function ISRichTextPanel:new(x, y, width, height)
    local panel = Widget.new(self, x, y, width, height)
    panel.marginTop, panel.marginBottom = 10, 10
    return panel
end
function ISRichTextPanel:setText(text) self.text = text end
function ISRichTextPanel:paginate()
    self.paginated = (self.paginated or 0) + 1
    local _, breaks = self.text:gsub("<LINE>", "")
    self:setScrollHeight(self.marginTop + (breaks + 1) * getTextManager():getFontHeight(self.defaultFont) + self.marginBottom)
end
ISProgressBar = Widget:derive("ISProgressBar")
function ISProgressBar:setProgress(value) self.progress = value end
function ISProgressBar:setText(text) self.text = text end
ISToolTip = Widget:derive("ISToolTip")
function ISToolTip:setName(name) self.name = name end
function ISToolTip:setContextMenu(context) self.contextMenu = context end

UIFont = {Small=1, Medium=2}
Keyboard = {KEY_ESCAPE=1}
local now, textEntry = 100, false
local core = {getScreenWidth=function() return 1280 end, getScreenHeight=function() return 900 end,
    isDoingTextEntry=function() return textEntry end}
function getCore() return core end
function getTimestampMs() return now end
function getTextManager() return {getFontHeight=function() return 17 end, MeasureStringX=function(_, _, text) return #text * 7 end} end
local player = {data={}}
function player:getModData() return self.data end
function player:getPlayerNum() return 0 end
function player:isDead() return false end
function getSpecificPlayer(index) assert(index == 0); return player end

PZAPI = {ModOptions={settings={}}}
function PZAPI.ModOptions:getOptions(id) return self.settings[id] end
function PZAPI.ModOptions:create(id)
    local object = {options={}, count=0}
    function object:addDescription() end
    function object:getOption(key) return self.options[key] end
    local function add(self, key, value)
        self.count = self.count + 1
        local option = {value=value}
        function option:getValue() return self.value end
        function option:setValue(newValue) self.value = newValue end
        self.options[key] = option
        return option
    end
    function object:addTickBox(id, _, value) return add(self, id, value) end
    function object:addKeyBind(id, _, value) return add(self, id, value) end
    self.settings[id] = object
    return object
end

local Controller = {state={active=false,phase="idle",message="Choose a mode.",meditation=2,yoga=0,
    progress={meditation={level=2,current=25,required=200,fraction=0.125,total=175},
        yoga={level=0,current=40,required=100,fraction=0.4}}},
    inventory={food=3,water=2,literature=1,nearbyFood=5,nearbyWater=4,nearbyLiterature=2,warnings={}}, stops=0, scans=0, starts=0}
function Controller.status() return Controller.state end
function Controller.prepare(_, collect, preview)
    Controller.scans = Controller.scans + 1
    Controller.lastScope = {collect=collect,preview=preview}
    local copy = {}
    for key, value in pairs(Controller.inventory) do copy[key] = value end
    return copy
end
function Controller.start(_, mode, collect)
    Controller.starts = Controller.starts + 1
    if Controller.failure then return false, Controller.failure end
    Controller.state.active, Controller.state.mode = true, mode
    Controller.state.collectNearby = collect
    return true, "Started"
end
function Controller.stop() Controller.stops = Controller.stops + 1; Controller.state.active = false end
function Controller.setCollectNearby(_, value) Controller.state.collectNearby = value; Controller.lastNearby = value end
package.loaded["AutoMindful/Controller"] = Controller

local menus, nextMenu = {}, 0
ISContextMenu = {}
function ISContextMenu:new()
    return setmetatable({options={},player=0}, {__index=self})
end
function ISContextMenu:addOption(name, target, callback, ...)
    local option = {name=name,target=target,onSelect=callback}
    for index = 1, select("#", ...) do option["param" .. index] = select(index, ...) end
    self.options[#self.options + 1] = option
    return option
end
function ISContextMenu:addOptionOnTop(...)
    local option = self:addOption(...)
    table.remove(self.options)
    table.insert(self.options, 1, option)
    return option
end
function ISContextMenu:getNew(parent)
    nextMenu = nextMenu + 1
    local menu = self:new()
    menu.subOptionNums, menu.player = nextMenu, parent.player
    menus[nextMenu] = menu
    return menu
end
function ISContextMenu:addSubMenu(option, submenu) option.subOption = submenu.subOptionNums end
function ISContextMenu:getSubMenu(id) return menus[id] end

local manualCall
local meditation = {onAction=function(...) manualCall = {...}; return "native meditation" end}
local yoga = {onAction=function(...) manualCall = {...}; return "native yoga" end}
local blocked = true
ZenWellnessContextMenu = {Options={Meditation=meditation,Yoga=yoga}}
function ZenWellnessContextMenu.doBuildMenu(index, context, objects)
    local wellness = context:addOption("Localized wellness")
    local submenu = ISContextMenu:getNew(context)
    context:addSubMenu(wellness, submenu)
    local option = submenu:addOption("Localized meditation", objects, meditation.onAction, meditation, getSpecificPlayer(index))
    option.notAvailable, option.iconTexture = blocked, "native meditation icon"
    option.toolTip = ISToolTip:new()
    return "native result", nil, 3
end
local function event()
    local result = {handlers={}}
    function result.Add(handler) result.handlers[#result.handlers + 1] = handler end
    function result.Remove(handler)
        for index = #result.handlers, 1, -1 do if result.handlers[index] == handler then table.remove(result.handlers, index) end end
    end
    return result
end
Events = {OnFillWorldObjectContextMenu=event(),OnKeyPressed=event(),OnGameStart=event()}

local UI = require "AutoMindful/UI"
local Options = require "AutoMindful/Options"
local Context = require "AutoMindful/ContextMenu"
local settings = PZAPI.ModOptions:getOptions("AutoMindful")
assert(not Options.generalMenu() and Options.windowKey() == 0, "Idle menus and hotkeys default to opt-in")
package.loaded["AutoMindful/Options"] = nil
require "AutoMindful/Options"
assert(settings.count == 2, "Reload reuses the same native options")

local context, world = ISContextMenu:new(), {"clicked square"}
local first, second, third = ZenWellnessContextMenu.doBuildMenu(0, context, world)
assert(first == "native result" and second == nil and third == 3, "Wrapping preserves native return values")
local parent = context:getSubMenu(context.options[1].subOption).options[1]
local submenu = context:getSubMenu(parent.subOption)
assert(parent.onSelect == nil and not parent.notAvailable, "A blocked native action still allows submenu navigation")
assert(parent.toolTip == nil, "Parent tooltips do not cover the quick-action submenu")
assert(submenu.options[1].name == "Open AutoMindful" and submenu.options[2].name == "Train meditation"
    and submenu.options[3].name == "Check supplies", "Open window precedes the mode-specific quick actions")
assert(submenu.options[2].toolTip.description:find("25 / 200 XP",1,true), "Quick-action tooltips include progress toward the next level")
local manual = submenu.options[4]
assert(manual.notAvailable and manual.iconTexture == "native meditation icon" and manual.toolTip, "Native availability and presentation are retained")
assert(manual.onSelect(manual.target) == "native meditation")
assert(manualCall[1] == world and manualCall[2] == meditation and manualCall[3] == player, "Manual action retains native target and arguments")
Context.attach(context, player)
assert(#submenu.options == 4 and manual.subOption == nil, "Repeated menu attachment does not nest or duplicate manual actions")
local wrapper = ZenWellnessContextMenu.doBuildMenu
Context.install()
assert(ZenWellnessContextMenu.doBuildMenu == wrapper, "Repeated installation is a no-op")

local idle = ISContextMenu:new()
Context.generalMenu(0, idle, {}, false)
assert(#idle.options == 0, "Idle world menus remain clean by default")
Controller.state.active = true
local active = ISContextMenu:new()
Context.generalMenu(0, active, {}, false)
assert(#active.options == 1, "A running session can reopen its window without a configured key")
Controller.state.active, Controller.state.pendingReturns = false, 1
local returning = ISContextMenu:new()
Context.generalMenu(0, returning, {}, false)
assert(#returning.options == 1, "Pending borrowed items retain a window entry")
Controller.state.pendingReturns = 0
settings:getOption("generalContextMenu"):setValue(true)
local general = ISContextMenu:new()
Context.generalMenu(0, general, {}, false)
assert(#general.options == 1, "The general context entry can be enabled")
settings:getOption("generalContextMenu"):setValue(false)

local window = UI.open(player)
local function assertFooterVisible(view)
    local footer
    for _, child in ipairs(view.children) do
        if child.text and child.text:find("Close to hide.", 1, true) then footer = child end
    end
    assert(footer and footer:getScrollHeight() <= footer.height, "Both footer instructions fit inside their clipped panel")
    assert(footer:getBottom() <= view.height, "Footer instructions remain inside the window")
    assert(view.stopButton:getBottom() <= view.checked.y and view.checked:getBottom() <= footer.y,
        "Buttons, refresh confirmation, and footer have separate visible rows")
    local plain = footer.text:gsub("<LINE>", "\n"):gsub("<[^>]+>", "")
    for line in plain:gmatch("[^\n]+") do
        assert(getTextManager():MeasureStringX(UIFont.Small, line) <= footer.width, "Footer instructions fit on two unwrapped lines")
    end
end
assertFooterVisible(window)
local screenHeight = core.getScreenHeight
core.getScreenHeight = function() return 480 end
local shortPlayer = {data={}, getModData=player.getModData, getPlayerNum=function() return 1 end, isDead=player.isDead}
local shortWindow = UI.open(shortPlayer)
assertFooterVisible(shortWindow)
assert(shortWindow.body.height > 0 and shortWindow.body:getScrollHeight() > shortWindow.body.height,
    "Short screens preserve the fixed controls and scroll the body")
shortWindow:close()
UI.windows[1] = nil
core.getScreenHeight = screenHeight
assert(Controller.lastScope.collect == false and Controller.lastScope.preview == true, "Preview uses the actual collection setting")
assert(window.report.food == 3 and window.report.nearbyFood == 5)
assert(window.skills[1].bar.progress == 0.125 and window.skills[2].bar.progress == 0.4, "Skill bars represent XP within the current level")
assert(window.skills[1].label.name=="Meditation - Level 2 / 10" and window.skills[1].bar.text=="25 / 200 XP (12.5%)")
assert(not window.skills[1].flash and not window.skills[2].flash, "The first sample must not invent XP gains")
assert(not window.activity.hasScrollbars and window.activity:getScrollHeight() <= window.activity.height,
    "Ordinary activity text fits without an inner scrollbox")
assert(window.resizable and window.body:getScrollHeight() <= window.body.height,
    "The ordinary window fits its content and exposes native resizing")
Controller.state.progress.meditation={level=2,current=30,required=200,fraction=0.15,total=180}
now=now+200; window:refresh()
local flash=window.skills[1].flash
assert(flash and flash.text=="+5 XP" and flash.positive)
window.progressFrame.draws={}; window.progressFrame:prerender()
local startDraw=window.progressFrame.draws[#window.progressFrame.draws]
assert(startDraw.text=="+5 XP" and startDraw.g>startDraw.r and startDraw.a==1)
now=now+500; window.progressFrame.draws={}; window.progressFrame:prerender()
local laterDraw=window.progressFrame.draws[#window.progressFrame.draws]
assert(laterDraw.y<startDraw.y and laterDraw.a==0.5,"The one-second XP indication rises and fades")
Controller.state.progress.meditation={level=2,current=27,required=200,fraction=0.135,total=177}
now=now+100; window:refresh(); window.progressFrame.draws={}; window.progressFrame:prerender()
local loss=window.progressFrame.draws[#window.progressFrame.draws]
assert(loss.text=="-3 XP" and loss.r>loss.g,"XP losses show the amount in red")
now=now+1001; window.progressFrame:prerender()
assert(not window.skills[1].flash,"XP indication expires after one second")
Controller.state.meditation=3
Controller.state.progress.meditation={level=3,current=2,required=500,fraction=0.004,total=352}
window:refresh()
assert(window.skills[1].flash.text=="+175 XP" and window.skills[1].bar.progress==0.004,
    "Level transitions retain the actual cumulative XP change")
Controller.state.yoga=1
Controller.state.progress.yoga={level=1,current=5,required=250,fraction=0.02}
window:refresh()
assert(window.skills[2].flash.text=="+65 XP","A Yoga level transition counts the previous threshold and new progress")
Controller.state.yoga=9
Controller.state.progress.yoga={level=9,current=8995,required=9000,fraction=8995/9000}
window:refresh()
Controller.state.yoga=10
Controller.state.progress.yoga={level=10,current=0,required=0,fraction=1,capped=true}
window:refresh()
assert(window.skills[2].bar.text=="MAX" and window.skills[2].bar.progress==1 and window.skills[2].flash.text=="+1 level",
    "Yoga cap uses an honest level indication when upstream does not retain the exact XP award")
window:setWidth(760); window:setHeight(850); window:onResize()
assert(window.body.width==736 and window.ledger.width==721 and window.starts[1].width==(736-12)/3)
assert(window.body:getScrollHeight()<=window.body.height and window.player.data.AutoMindfulPreferences.width==760
    and window.player.data.AutoMindfulPreferences.height==850,"Resizing reflows content and remembers the chosen dimensions")
assertFooterVisible(window)
Controller.state.message="First line\nSecond line\nThird line\nFourth line"
window:refresh()
assert(window.activity:getScrollHeight()<=window.activity.height and not window.activity.hasScrollbars,
    "Long activity text grows its frame instead of hiding status behind an inner scrollbar")
Controller.state.message="Choose a mode."
Controller.inventory.warnings={}
for index=1,12 do Controller.inventory.warnings[index]="Supply warning "..index end
window:refresh()
assert(window.guidance.hasScrollbars and window.guidance:getScrollHeight()>window.guidance.height,
    "Long preparation details remain accessible through their own scroll area")
Controller.inventory.warnings={};window:refresh()
assert(window.checked.name == "Supplies checked just now")
Controller.inventory.food = 7
now = now + 600
window:update()
assert(window.report.food == 7, "Visible supply counts update without reopening")
Controller.state.active, Controller.state.mode = true, "meditation"
window.nearby:setSelected(1, true)
window:onNearbyChanged()
assert(Controller.lastNearby == true and Controller.state.active and Controller.stops == 0, "Collection can change during training without cancellation")
assert(Controller.lastScope.collect == true and Controller.lastScope.preview == true)
Controller.inventory.food = 0
window:checkSupplies()
assert(window.report.food == 0 and Controller.state.active and Controller.stops == 0, "Checking supplies refreshes read-only during training")
Controller.state.careNotice = "Continuing while hunger is safe."
Controller.state.active = false
window:refresh()
assert(not window.guidance.text:find(Controller.state.careNotice, 1, true), "Stopped sessions must not show an old continuing-care notice")
Controller.state.active = true
window:refresh()
assert(window.guidance.text:find(Controller.state.careNotice, 1, true), "An active care notice remains visible")
Controller.state.careNotice = nil
window.ledger:prerender()
local foodY
for _, draw in ipairs(window.ledger.draws) do if draw.text == "Food" then foodY = draw.y end end
local zero
for _, draw in ipairs(window.ledger.draws) do if draw.y == foodY and draw.text == "0" then zero = draw end end
assert(zero and zero.r > zero.g, "Missing supply quantities are visibly distinguished")
window.x, window.y = 120, 130
window.ledger.tooltipUI = Widget:new()
window:close()
assert(not window.ledger.tooltipUI:getIsVisible() and window.ledger.tooltipUI.removed, "Closing resets tooltip visibility so it can appear after reopening")
local scans = Controller.scans
now = now + 600
Controller.state.progress.meditation={level=3,current=52,required=500,fraction=0.104,total=402}
window:update()
assert(Controller.scans == scans and Controller.state.active and Controller.stops == 0, "Closing hides the view without ending the loop")
assert(UI.open(player) == window and window.x == 120 and window.y == 130 and window.nearby:isSelected(1), "Reopening preserves position and collection preference")
assert(window.width==760 and window.height==850 and not window.skills[1].flash and not window.skills[2].flash,
    "Reopening preserves geometry and establishes a fresh XP baseline without replaying hidden gains")

require "AutoMindful_Main"
settings:getOption("openWindow"):setValue(66)
local opens, open = 0, UI.open
UI.open = function(...) opens = opens + 1; return open(...) end
textEntry = true
AutoMindful.uiEvents.key(66)
textEntry, ISChat = false, {focused=true}
AutoMindful.uiEvents.key(66)
assert(opens == 0, "The shortcut does not fire into text entry or chat")
ISChat.focused = false
AutoMindful.uiEvents.key(66)
assert(opens == 1, "A configured shortcut opens the window")
AutoMindful.uiEvents.key(Keyboard.KEY_ESCAPE)
assert(not window:getIsVisible() and Controller.state.active and Controller.stops == 0, "Escape hides the window without stopping training")
package.loaded.AutoMindful_Main = nil
require "AutoMindful_Main"
assert(#Events.OnKeyPressed.handlers == 1 and #Events.OnFillWorldObjectContextMenu.handlers == 1, "Reload does not duplicate input handlers")
print("ui-contracts: PASS")
