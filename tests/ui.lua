package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
for _, name in ipairs({"ISCollapsableWindow", "ISPanel", "ISButton", "ISTickBox", "ISLabel", "ISRichTextPanel", "ISProgressBar", "ISContextMenu", "ISToolTip"}) do
    package.loaded["ISUI/" .. name] = true
end
package.loaded["PZAPI/ModOptions"] = true
package.loaded["ISMeditation/ZenWellnessContextMenu"] = true
package.loaded["XpSystem/ISUI/ISCharacterInfo"] = true

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
function ISButton:new(x,y,w,h,name,target,callback)
    local o=Widget.new(self,x,y,w,h);o.name,o.target,o.callback=name,target,callback;return o
end
function ISButton:click() if self.callback then return self.callback(self.target,self) end end
ISTickBox = Widget:derive("ISTickBox")
function ISTickBox:new(x, y, width, height, _, target, callback)
    local box = Widget.new(self, x, y, width, height)
    box.target, box.callback = target, callback
    return box
end
function ISTickBox:addOption(label) self.option = label end
function ISTickBox:setSelected(_, value) self.selected = value end
function ISTickBox:isSelected() return self.selected == true end
function ISTickBox:click()
    self:setSelected(1, not self:isSelected(1))
    self.callback(self.target, 1, self:isSelected(1))
end
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
local player2 = {data={}, getPlayerNum=function() return 1 end, isDead=player.isDead, getModData=player.getModData}
function getSpecificPlayer(index) return ({[0]=player,[1]=player2})[index] end
local textureLoads, textureHandles = {}, {}
function fileExists(path) return path:match("^media/ui/AutoMindful/%a+%.png$") ~= nil end
function getTexture(path)
    assert(path:match("^media/ui/AutoMindful/%a+%.png$"), "Icons must use their bundled texture namespace")
    textureLoads[path] = (textureLoads[path] or 0)+1
    textureHandles[path] = textureHandles[path] or {path=path}
    return textureHandles[path]
end
local function art(name) return textureHandles["media/ui/AutoMindful/" .. name .. ".png"] end

PZAPI = {ModOptions={settings={}}}
function PZAPI.ModOptions:getOptions(id) return self.settings[id] end
function PZAPI.ModOptions:save()
    self.saves = (self.saves or 0) + 1
    self.savedSearch = self:getOptions("AutoMindful"):getOption("searchNearby"):getValue()
end
function PZAPI.ModOptions:create(id)
    local object = {options={}, count=0}
    function object:addDescription() end
    function object:getOption(key) return self.options[key] end
    local function add(self, key, value)
        self.count = self.count + 1
        local option = {value=value}
        function option:getValue() return self.value end
        function option:setValue(newValue)
            self.value = newValue
            if self.element then self.element:setSelected(1, newValue) end
        end
        self.options[key] = option
        return option
    end
    function object:addTickBox(id, label, value)
        local option = add(self, id, value)
        option.name = label
        return option
    end
    function object:addSlider(id, _, minimum, maximum, step, value) return add(self, id, value) end
    function object:addKeyBind(id, _, value) return add(self, id, value) end
    self.settings[id] = object
    return object
end

local Controller = {state={active=false,phase="idle",message="Choose a mode.",meditation=2,yoga=0,
    progress={meditation={level=2,current=25,required=200,fraction=0.125,total=175},
        yoga={level=0,current=40,required=100,fraction=0.4}}},
    inventory={food=3,water=2,literature=1,nearbyFood=5,nearbyWater=4,nearbyLiterature=2,warnings={}}, stops=0, scans=0, starts=0}
function Controller.status() return Controller.state end
function Controller.prepare(_, collect, preview, force)
    Controller.scans = Controller.scans + 1
    Controller.lastScope = {collect=collect,preview=preview,force=force}
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
function ISContextMenu:calcWidth()
    local widest=0
    for _,o in ipairs(self.options) do widest=math.max(widest,#o.name) end
    return widest
end
function ISContextMenu:setWidth(w) self.width=w end

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
local search = settings:getOption("searchNearby")
assert(Options.searchNearby() and Options.searchRadius() == 10, "Scouting starts on within a 10-tile radius")
local freshBoth = UI.open(player2)
assert(freshBoth.nearby:isSelected(1) and freshBoth.scouting:isSelected(1),
    "Both supply controls start enabled on a fresh pane with unset defaults")
freshBoth:close()
UI.windows[1]=nil
assert(not Options.generalMenu() and Options.windowKey() == 0, "Idle menus and hotkeys default to opt-in")
search:setValue(false)
package.loaded["AutoMindful/Options"] = nil
require "AutoMindful/Options"
assert(settings.count == 4 and not Options.searchNearby(), "Reload reuses an existing off preference")

local context, world = ISContextMenu:new(), {"clicked square"}
local first, second, third = ZenWellnessContextMenu.doBuildMenu(0, context, world)
assert(first == "native result" and second == nil and third == 3, "Wrapping preserves native return values")
local parent = context:getSubMenu(context.options[1].subOption).options[1]
local submenu = context:getSubMenu(parent.subOption)
assert(parent.onSelect == nil and not parent.notAvailable, "A blocked native action still allows submenu navigation")
assert(parent.toolTip == nil, "Parent tooltips do not cover the quick-action submenu")
assert(submenu.options[1].name == "Open AutoMindful" and submenu.options[2].name == "Meditate to Full Endurance"
    and submenu.options[3].name == "Train meditation" and submenu.options[4].name == "Check supplies",
    "Open precedes the meditation-only endurance action and other quick actions")
assert(submenu.options[3].toolTip.description:find("25 / 200 XP",1,true), "Quick-action tooltips include progress toward the next level")
local trainQuick = submenu.options[3]
assert(trainQuick.onSelect(trainQuick.target, trainQuick.param1))
assert(Controller.state.mode == "meditation" and Controller.state.collectNearby == true and not Options.searchNearby(),
    "A fresh quick action starts with adjacent supplies enabled independently of scouting")
Controller.state.active = false
local endurance = submenu.options[2]
player.data.AutoMindfulPreferences = {collectNearby=true}
assert(endurance.onSelect(endurance.target, endurance.param1))
assert(Controller.state.mode == "endurance" and Controller.state.collectNearby == false,
    "The endurance context action bypasses the saved adjacent-supply setting")
player.data.AutoMindfulPreferences = nil
local occupiedMenu = ISContextMenu:new()
ZenWellnessContextMenu.doBuildMenu(0, occupiedMenu, world)
local occupiedWellness = occupiedMenu:getSubMenu(occupiedMenu.options[1].subOption)
assert(occupiedMenu:getSubMenu(occupiedWellness.options[1].subOption).options[2].notAvailable,
    "The endurance menu action cannot replace an active session")
Controller.state.active = false
local manual = submenu.options[5]
assert(manual.notAvailable and manual.iconTexture == "native meditation icon" and manual.toolTip, "Native availability and presentation are retained")
assert(manual.onSelect(manual.target) == "native meditation")
assert(manualCall[1] == world and manualCall[2] == meditation and manualCall[3] == player, "Manual action retains native target and arguments")
Context.attach(context, player)
assert(#submenu.options == 5 and manual.subOption == nil, "Repeated menu attachment does not nest or duplicate manual actions")
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

-- Each distinct command has a distinct silhouette, even when an upstream leaf supplies no art.
local yogaMenu = ISContextMenu:new()
local rawYoga = yogaMenu:addOption("Localized yoga", world, yoga.onAction, yoga, nil, 3,nil,5,nil,7,nil,9,10)
local rawTip = ISToolTip:new()
rawYoga.checkMark,rawYoga.toolTip=true,rawTip
local otherLeaf=yogaMenu:addOption("Someone else's entry", world, function() end)
Context.attach(yogaMenu, player)
local function expectIcons(menu, names)
    assert(#menu.options==#names,"An icon must not add a second action")
    local seen={}
    for i,name in ipairs(names) do
        assert(menu.options[i].iconTexture==art(name), menu.options[i].name .. " has wrong or missing icon: " .. name)
        assert(not seen[name],"No duplicated glyph for different actions in one menu");seen[name]=true
    end
end
assert(rawYoga.iconTexture==art("Mat") and not otherLeaf.iconTexture)
local yogaQuick=yogaMenu:getSubMenu(rawYoga.subOption)
expectIcons(yogaQuick,{"Open","Yoga","Supplies","Once"})
local once=yogaQuick.options[4]
assert(once.checkMark and once.toolTip==rawTip and rawTip.contextMenu==yogaQuick)
assert(once.onSelect(once.target)=="native yoga")
assert(manualCall[1]==world and manualCall[2]==yoga and manualCall[3]==nil and manualCall[4]==3 and manualCall[11]==10,
    "Original dispatch including nil holes and the tenth argument survives")
assert(submenu.options[1].iconTexture==art("Open") and submenu.options[2].iconTexture==art("Endurance")
    and submenu.options[3].iconTexture==art("Meditate") and submenu.options[4].iconTexture==art("Supplies")
    and parent.iconTexture=="native meditation icon" and manual.iconTexture==parent.iconTexture)
Context.attach(yogaMenu,player);expectIcons(yogaQuick,{"Open","Yoga","Supplies","Once"})

local itemMenu=ISContextMenu:new();itemMenu.player=1
local obj,originalItem={},{}
local itemLeaf=itemMenu:addOption("Localized meditation",obj,meditation.onAction,meditation,player2)
itemLeaf.itemForTexture=originalItem
Context.attach(itemMenu,player2)
local itemSub=itemMenu:getSubMenu(itemLeaf.subOption);local itemOnce=itemSub.options[#itemSub.options]
assert(not itemLeaf.iconTexture and not itemOnce.iconTexture and itemLeaf.itemForTexture==originalItem and itemOnce.itemForTexture==originalItem,
    "The renderer prefers iconTexture over itemForTexture: never shadow a native item icon")
assert(itemSub.player==1 and itemSub.options[1].target==player2 and itemSub.options[2].target==player2)
local swatch=itemMenu:addOption("Tinted native yoga",obj,yoga.onAction,yoga,player2)
swatch.iconTexture,swatch.color="actual swatch",{r=.4,g=.7,b=.2}
Context.attach(itemMenu,player2)
local sw=itemMenu:getSubMenu(swatch.subOption).options[4]
assert(sw.iconTexture==swatch.iconTexture and sw.color==swatch.color,"Preserve the native swatch and tint")
local bare=ISContextMenu:new()
local bareMed=bare:addOption("Bare meditation",world,meditation.onAction,meditation)
Context.attach(bare,player);assert(bareMed.iconTexture==art("Bowl"))
expectIcons(bare:getSubMenu(bareMed.subOption),{"Open","Endurance","Meditate","Supplies","Once"})

local again,_,last=ZenWellnessContextMenu.doBuildMenu(0,context,world)
assert(again=="native result" and last==3,"A repeated external builder retains its return values")
local addedParent=context:getSubMenu(context.options[2].subOption).options[1]
assert(not addedParent.subOption and addedParent.onSelect==meditation.onAction,"Repeat build: no second AutoMindful group, and upstream's own option is left intact")
settings:getOption("generalContextMenu"):setValue(true)
local root2=ISContextMenu:new();root2.player=1
local foreign=root2:addOption("AutoMindful",player2,function() end)
Context.generalMenu(1,root2,{},false);Context.generalMenu(1,root2,{},false)
assert(#root2.options==2 and root2.options[1]==foreign and not foreign.iconTexture)
assert(root2.options[2].iconTexture==art("Mindful") and root2.options[2].target==player2)
Controller.state.active=true;Context.generalMenu(1,root2,{},false)
assert(#root2.options==2 and root2.options[2].name=="AutoMindful (running)" and root2.width==#root2.options[2].name)
Controller.state.active=false
local reused=root2.options[2];root2.options={}  -- stock clear/alloc wipes pooled options before reuse
for k in pairs(reused) do reused[k]=nil end
reused.name="Pooled other action";root2.options[1]=reused
Context.generalMenu(1,root2,{},false)
assert(#root2.options==2 and root2.options[2]~=reused and not reused.iconTexture)
local dry=ISContextMenu:new();Context.generalMenu(0,dry,{},true);assert(#dry.options==0)
for _,n in ipairs({"Mindful","Open","Supplies","Meditate","Yoga","Endurance","Mat","Bowl","Once"}) do
    assert(textureLoads[art(n).path]==1,"Each available texture is looked up once: "..n)
end
local tut=ISContextMenu:new()
function tut:addOption() return nil end -- stock tutorial suppresses a colliding label
Context.generalMenu(0,tut,{},false);assert(#tut.options==0)
settings:getOption("generalContextMenu"):setValue(false)
local window = UI.open(player)
local scout = window.scouting
assert(search.name == scout.option and not scout:isSelected(1), "Both surfaces show the same saved setting and label")
assert(window.nearby:isSelected(1), "A fresh pane enables adjacent supplies even if global scouting was saved off")
window:onStart(window.starts[1])
assert(Controller.state.collectNearby == true, "Starting from a fresh pane keeps the adjacent default")
Controller.state.active = false
window:refresh()
window.nearby:click()
assert(not window.nearby:isSelected(1) and player.data.AutoMindfulPreferences.collectNearby == false,
    "Opting out explicitly persists false for this survivor")
assert(trainQuick.onSelect(trainQuick.target, trainQuick.param1))
assert(Controller.state.collectNearby == false, "Saved adjacent-off also applies to quick actions")
Controller.state.active = false
window:refresh()
search.element = ISTickBox:new() -- native Mods page was constructed while scouting was off
local saves = PZAPI.ModOptions.saves or 0
scout:click()
assert(Options.searchNearby() and search.element:isSelected(1) and PZAPI.ModOptions.savedSearch,
    "Clicking the pane updates both the native option and its existing widget, and persists the choice")
window:refresh()
assert(PZAPI.ModOptions.saves == saves + 1 and not window.nearby:isSelected(1),
    "Ordinary refresh neither saves the setting again nor changes the separate adjacent preference")
search.element:setSelected(1, false)
search.value = search.element:isSelected(1) -- the native Mods Apply path
PZAPI.ModOptions:save()
now = now + 600; window:update()
assert(not scout:isSelected(1) and PZAPI.ModOptions.savedSearch == false,
    "Applying a change in Mods updates an already-open training pane")
window:close()
assert(UI.open(player)==window and not scout:isSelected(1) and not window.nearby:isSelected(1),
    "Reopening the same pane does not reapply either default")
window:close()
local saved = player.data.AutoMindfulPreferences
UI.windows[0]=nil
local previousWindow = window
window=UI.open(player)
scout=window.scouting
assert(window~=previousWindow and player.data.AutoMindfulPreferences==saved
    and saved.collectNearby==false and not window.nearby:isSelected(1)
    and not scout:isSelected(1) and not Options.searchNearby(),
    "Recreated pane respects both off choices with the existing survivor modData")
local function assertFooterVisible(view)
    local footer
    for _, child in ipairs(view.children) do
        if child.text and child.text:find("Close to hide.", 1, true) then footer = child end
    end
    assert(footer and footer:getScrollHeight() <= footer.height, "Both footer instructions fit inside their clipped panel")
    assert(footer:getBottom() <= view.height, "Footer instructions remain inside the window")
    assert(view.stopButton:getBottom() <= view.checked.y and view.checked:getBottom() <= footer.y,
        "Buttons, refresh confirmation, and footer have separate visible rows")
    assert(view.body:getBottom() <= view.scouting.y and view.scouting:getBottom() <= view.nearby.y
        and view.nearby:getBottom() <= view.starts[1].y, "Both supply choices fit above the training controls")
    assert(view.starts[1]:getBottom() <= view.enduranceButton.y and view.enduranceButton:getBottom() <= view.check.y
        and view.enduranceButton.width == view.body.width, "The endurance button fits on its own visible row")
    local plain = footer.text:gsub("<LINE>", "\n"):gsub("<[^>]+>", "")
    for line in plain:gmatch("[^\n]+") do
        assert(getTextManager():MeasureStringX(UIFont.Small, line) <= footer.width, "Footer instructions fit on two unwrapped lines")
    end
end
assertFooterVisible(window)

local guideChildren = #window.body.children
local progressScroll = -17
window.body:setYScroll(progressScroll)
local stopsBefore = Controller.stops
window.skillGuideButton:click()
assert(window.wellnessOpen and window.wellnessFrame.visible and not window.progressFrame.visible
    and not window.ledger.visible and window.stopButton.visible and window.wellnessText.blockMouseWheel
    and window.wellnessText.text:find("Skill details",1,true), "Guide switches the scroll body, not the fixed controls")
assert(Controller.stops==stopsBefore and #window.body.children==guideChildren)
window.body:setYScroll(-23)
window.wellnessBack:click()
assert(not window.wellnessOpen and not window.wellnessFrame.visible and window.progressFrame.visible
    and window.body:getYScroll()==progressScroll, "Back restores the training scroll position")
window.skillGuideButton:click()
assert(window.body:getYScroll()==-23 and #window.body.children==guideChildren, "Reopening restores the help scroll without duplicate children")
window.wellnessBack:click()
local screenHeight = core.getScreenHeight
core.getScreenHeight = function() return 480 end
local shortPlayer = {data={}, getModData=player.getModData, getPlayerNum=function() return 1 end, isDead=player.isDead}
local shortWindow = UI.open(shortPlayer)
assertFooterVisible(shortWindow)

do
    local x,y=shortWindow.scouting.x,shortWindow.scouting.y
    local children=#shortWindow.body.children
    shortWindow.skillGuideButton:click()
    assert(shortWindow.body.width>0 and shortWindow.wellnessText.width>0 and shortWindow.scouting.x==x
        and shortWindow.scouting.y==y and shortWindow.wellnessFrame.visible, "Guide leaves compact fixed controls in place")
    shortWindow:setWidth(415);shortWindow:onResize()
    assert(shortWindow.wellnessBack.x+shortWindow.wellnessBack.width<=shortWindow.wellnessFrame.width)
    shortWindow:close()
    assert(not shortWindow.wellnessOpen and #shortWindow.body.children==children and not shortWindow:getIsVisible())
end
assert(shortWindow.nearby:isSelected(1) and not shortWindow.scouting:isSelected(1)
        and not window.nearby:isSelected(1),
    "A fresh split survivor gets adjacent on; the existing survivor stays off and scouting off is global")
assert(shortWindow.body.height > 0 and shortWindow.body:getScrollHeight() > shortWindow.body.height,
    "Short screens preserve the fixed controls and scroll the body")
shortWindow:close()
UI.windows[1] = nil
core.getScreenHeight = screenHeight
assert(window.enduranceButton.enable and window.enduranceButton.mode == "endurance",
    "The window offers an enabled endurance job while idle")
scout:click()
assert(Options.searchNearby() and not window.nearby:isSelected(1), "Enabling global scouting does not enable this survivor's adjacent preference")
window:onStart(window.enduranceButton)
assert(Controller.state.mode == "endurance" and not Controller.state.collectNearby and not window.enduranceButton.enable,
    "The window starts endurance without supplies and disables the button during the active session")
scout:click() -- Restore existing off preference for the remainder of the UI contracts.
Controller.state.endurance = .999
window:refresh()
assert(window.activity.text:find("Recovering endurance (99%)", 1, true),
    "Active endurance is rounded down and does not show 100% early")
Controller.state.endurance = nil
window:refresh()
assert(window.activity.text:find("Recovering endurance", 1, true) and not window.activity.text:find("99%", 1, true),
    "An unreadable stat does not claim a percentage")
Controller.state.active = false
window:refresh()
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
assert(Controller.lastScope.force == true, "Check supplies forces a fresh radius snapshot")
assert(window.report.food == 0 and Controller.state.active and Controller.stops == 0, "Checking supplies refreshes read-only during training")
Controller.state.careNotice = "Continuing while hunger is safe."
Controller.state.active = false
window:refresh()
assert(not window.guidance.text:find(Controller.state.careNotice, 1, true), "Stopped sessions must not show an old continuing-care notice")
Controller.state.active = true
window:refresh()
assert(window.guidance.text:find(Controller.state.careNotice, 1, true), "An active care notice remains visible")
Controller.state.careNotice = nil
Controller.state.painNotice = "No usable stock Painkillers found."
window:refresh()
assert(window.guidance.text:find(Controller.state.painNotice, 1, true), "A pain-care blocker is visible in the pane")
Controller.state.painNotice = nil
window.ledger:prerender()
local painRow, stockFooter
for _, draw in ipairs(window.ledger.draws) do
    if draw.text == "Painkillers" then painRow = draw.y end
    if draw.text == "Care trips: enabled" or draw.text == "Adjacent only; care trips off" then stockFooter = draw.y end
end
assert(painRow and stockFooter and painRow + window.ledger.line < stockFooter,
    "The painkiller count has its own readable row above the footer")
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
-- Fresh Lua environment with no loose asset mount (the default client-only loader).
-- Known symbolic names come from stock B42.22.2 UI/UI2 pack metadata, not another mod.
do
    local ls = {Open="Item_Clipboard", Supplies="Item_Backpack", Yoga="Item_Dumbbell",
        Meditate="Item_Candle", Endurance="Moodle_Icon_Endurance", Once="ArrowRight",
        Mat="Item_Bathtowel", Bowl="Item_Bowl", Mindful="FavoriteStar"}
    local mounted, lookup, native, poisoned = {}, {}, {}, {}
    local function path(key) return "media/ui/AutoMindful/"..key..".png" end
    for _,key in pairs(ls) do native[key]={key=key} end
    function fileExists(key) return mounted[key]~=nil end
    function getTexture(key)
        lookup[key]=(lookup[key] or 0)+1
        if key:match("^media/") then
            if not mounted[key] then poisoned[key]=true end
            if poisoned[key] then return nil end
            local t=mounted[key]
            if t=="throw" then error("unavailable texture provider") end
            return t
        end
        return native[key]
    end
    package.loaded["AutoMindful/ContextMenu"]=nil
    local tested=require "AutoMindful/ContextMenu"
    local function leaves(mode,who,verified)
        local root=ISContextMenu:new();root.player=who:getPlayerNum()
        local ref=mode=="yoga" and yoga or meditation
        local top=root:addOption(mode,{},ref.onAction,ref,who)
        if verified then top.itemForTexture=verified end
        tested.attach(root,who);tested.attach(root,who)
        local sub=root:getSubMenu(top.subOption)
        assert(#root.options==1 and #sub.options==(mode=="yoga" and 4 or 5))
        return root,top,sub
    end
    local function verifyKeys(sub,keys)
        local distinct={}
        for i,key in ipairs(keys) do
            local texture=sub.options[i].iconTexture
            assert(texture==native[ls[key]] and texture,"stock glyph required for "..key)
            assert(not distinct[texture],"duplicate stock glyph");distinct[texture]=true
        end
    end
    local ym,yt,ys=leaves("yoga",player2);verifyKeys(ys,{"Open","Yoga","Supplies","Once"})
    assert(yt.iconTexture==native[ls.Mat] and ys.player==1)
    local mm,mt,ms=leaves("meditation",player);verifyKeys(ms,{"Open","Endurance","Meditate","Supplies","Once"})
    assert(mt.iconTexture==native[ls.Bowl] and ms.options[2].param1=="endurance")
    local g=ISContextMenu:new();settings:getOption("generalContextMenu"):setValue(true)
    tested.generalMenu(0,g,{},false);tested.generalMenu(0,g,{},false)
    assert(#g.options==1 and g.options[1].iconTexture==native[ls.Mindful])
    for key in pairs(ls) do assert(not poisoned[path(key)] and not lookup[path(key)],"Do not poison native negative cache with an unmounted path") end
    -- Late legitimate mount in the same still-live pooled menu upgrades in place.
    local previouslyForeign,customOpen,customRoot={},{key="branded Open"},{key="branded root"}
    ys.options[3].iconTexture=previouslyForeign
    mounted[path("Open")]=customOpen; mounted[path("Mindful")]=customRoot
    tested.attach(ym,player2);tested.generalMenu(0,g,{},false)
    assert(ys.options[1].iconTexture==customOpen and g.options[1].iconTexture==customRoot and #ys.options==4 and #g.options==1)
    assert(ys.options[3].iconTexture==previouslyForeign,"Never overwrite newer upstream icons")
    -- A late upstream item/tint also outranks our previous provisional art.
    ys.options[4].itemForTexture={}; tested.attach(ym,player2)
    assert(not ys.options[4].iconTexture and ys.options[4].itemForTexture~=nil)
    local mis={getName=function() return "EngineErrorTexture" end}
    mounted[path("Yoga")]=mis; mounted[path("Meditate")]={isFailure=function() return true end}
    mounted[path("Endurance")]={isReady=function() return false end}
    mounted[path("Mat")]="throw";mounted[path("Bowl")]={isDestroyed=function() return true end}
    tested.attach(ym,player2);tested.attach(mm,player)
    assert(ys.options[2].iconTexture==native[ls.Yoga] and yt.iconTexture==native[ls.Mat])
    assert(ms.options[3].iconTexture==native[ls.Meditate] and ms.options[2].iconTexture==native[ls.Endurance] and mt.iconTexture==native[ls.Bowl])
    native[ls.Yoga]=nil; tested.attach(ym,player2)
    assert(not ys.options[2].iconTexture and ys.options[2].onSelect and ys.options[2].target==player2)
    local customYoga={};mounted[path("Yoga")]=customYoga; tested.attach(ym,player2)
    assert(ys.options[2].iconTexture==customYoga and #ys.options==4)
    -- No VFS API/throwing probe: stock is safe and row callbacks still exist.
    fileExists=function() error("no readable VFS") end
    local realItem={};local _,_,readable=leaves("meditation",player2,realItem)
    assert(readable.options[3].iconTexture==native[ls.Meditate] and not readable.options[5].iconTexture and readable.options[5].itemForTexture==realItem)
    fileExists=nil; native[ls.Meditate]=mis
    local _,_,degraded=leaves("meditation",player)
    assert(not degraded.options[3].iconTexture and degraded.options[3].onSelect and #degraded.options==5)
end
print("ui-contracts: PASS (including native art, default unmounted stock icons, late mount and unavailable assets)")
