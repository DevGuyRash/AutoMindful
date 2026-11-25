-- The window and right-click menu as a player meets them, over explicit doubles
-- for the game's widgets. Rows are measured, drawn and clicked by the real code.
package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
for _, name in ipairs({"ISCollapsableWindow", "ISPanel", "ISButton", "ISContextMenu", "ISToolTip"}) do package.loaded["ISUI/" .. name] = true end
package.loaded["PZAPI/ModOptions"] = true
package.loaded["ISMeditation/ZenWellnessContextMenu"] = true
package.loaded["TimedActions/WalkToTimedAction"] = true
package.loaded["XpSystem/ISUI/ISCharacterInfo"] = true
local function passed(text) print("PASS " .. text) end

UIFont = {Small=1, Medium=2}
local charWidth, lineHeight = 7, 16
function getTextManager()
    return {getFontHeight=function(_, font) return font == UIFont.Medium and lineHeight + 4 or lineHeight end,
        MeasureStringX=function(_, font, text) return #tostring(text) * (font == UIFont.Medium and charWidth + 1 or charWidth) end}
end
local mouseX, mouseY, now = 0, 0, 1000
function getMouseX() return mouseX end
function getMouseY() return mouseY end
function getTimestampMs() return now end
local screenW, screenH = 1920, 1036

local Widget = {}
function Widget:derive(name) return setmetatable({Type=name, __index=self}, {__index=self}) end
function Widget:new(x, y, width, height)
    return setmetatable({x=x or 0, y=y or 0, width=width or 0, height=height or 0, children={}, visible=true,
        borderColor={a=1}, backgroundColor={a=1}}, {__index=self})
end
function Widget:initialise() end
function Widget:addChild(child)
    self.children[#self.children + 1] = child
    child.parent = self
    if child.createChildren and not child.created then child.created = true; child:createChildren() end
end
function Widget:addToUIManager()
    if not self.created and self.createChildren then self.created = true; self:createChildren() end
end
function Widget:removeFromUIManager() self.removed = true end
function Widget:setVisible(value) self.visible = value end
function Widget:getIsVisible() return self.visible end
function Widget:getX() return self.x end
function Widget:getY() return self.y end
function Widget:getAbsoluteX() return self.x + (self.parent and self.parent:getAbsoluteX() or 0) end
function Widget:getAbsoluteY() return self.y + (self.parent and self.parent:getAbsoluteY() or 0) end
function Widget:setAnchorRight(v) self.anchorRight = v end
function Widget:setAnchorBottom(v) self.anchorBottom = v end
function Widget:setCapture(v) self.captured = v end
function Widget:setX(v) self.x = v end
function Widget:setY(v) self.y = v end
function Widget:setWidth(v) self.width = v end
function Widget:setHeight(v) self.height = v end
function Widget:bringToTop() end
function Widget:setScrollChildren() end
function Widget:addScrollBars() self.vscroll = Widget:new() end
function Widget:setScrollHeight(v) self.scrollHeight = v end
function Widget:getYScroll() return self.scrollY or 0 end
function Widget:setYScroll(v) self.scrollY = v end
function Widget:getMouseX() return mouseX - self:getAbsoluteX() end
function Widget:getMouseY() return mouseY - self:getAbsoluteY() - self:getYScroll() end
function Widget:setStencilRect() end
function Widget:clearStencilRect() end
function Widget:drawRect() end
function Widget:drawRectBorder() end
function Widget:drawTextureScaledAspect() end
function Widget:setWantKeyEvents(v) self.wantsKeys = v end
local drawn
function Widget:drawText(text, x, y, _, _, _, _, font)
    if drawn then drawn[#drawn + 1] = {text=text, left=x, right=x + getTextManager():MeasureStringX(font, text), width=self.width} end
end
function Widget:drawTextRight(text, x, y, _, _, _, _, font)
    if drawn then drawn[#drawn + 1] = {text=text, left=x - getTextManager():MeasureStringX(font, text), right=x, width=self.width} end
end
ISPanel = Widget:derive("ISPanel")
ISButton = Widget:derive("ISButton")
function ISButton:new(x, y, w, h, title, target, callback)
    local o = Widget.new(self, x, y, w, h)
    o.title, o.target, o.callback = title, target, callback
    return o
end
ISToolTip = Widget:derive("ISToolTip")
function ISToolTip:new() return Widget.new(self) end
function ISToolTip:setOwner() end
function ISToolTip:setAlwaysOnTop() end
function ISToolTip:setDesiredPosition() end
function ISToolTip:setName(name) self.name = name end
function ISToolTip:setContextMenu(menu) self.menu = menu end
ISCollapsableWindow = ISPanel:derive("ISCollapsableWindow")
function ISCollapsableWindow:createChildren()
    local function widget() local w = Widget:new(); w.target, w.onMouseUp, w.onMouseUpOutside = self, function() end, function() end; return w end
    self.resizeWidget, self.resizeWidget2 = widget(), widget()
    self.collapseButton, self.pinButton = Widget:new(), Widget:new()
end
function ISCollapsableWindow:titleBarHeight() return lineHeight + 1 end
function ISCollapsableWindow:resizeWidgetHeight() return 12 end
function ISCollapsableWindow:update() end
function ISCollapsableWindow:onResize() end
function ISCollapsableWindow:onMouseDown() self.moving = true end
function ISCollapsableWindow:onMouseUp() self.moving = false end
function ISCollapsableWindow:onMouseUpOutside() self.moving = false end

Keyboard = {KEY_ESCAPE=1, KEY_0=11}
local boundKeys = {}
keyBinding = {}
function getCore()
    return {getScreenWidth=function() return screenW end, getScreenHeight=function() return screenH end,
        isDoingTextEntry=function() return false end, getKey=function() return 0 end, getAltKey=function() return 0 end}
end
function getKeyName(code) return code == 11 and "0" or "Key " .. code end
function getTexture(path) return {path=path, getName=function() return path end} end
function fileExists() return true end
function instanceof() return false end
local function square(x, y, objects)
    local s = {x=x, y=y}
    function s:getX() return self.x end
    function s:getY() return self.y end
    function s:getZ() return 0 end
    function s:getObjects() return {size=function() return #(objects or {}) end, get=function(_, i) return objects[i + 1] end} end
    return s
end
MoodleType = {THIRST="THIRST", HUNGRY="HUNGRY", BORED="BORED", TIRED="TIRED", ENDURANCE="ENDURANCE", PAIN="PAIN", STRESS="STRESS", UNHAPPY="UNHAPPY", PANIC="PANIC"}
local function survivor(index)
    local p = {data={}, moodles={}, index=index, square=square(10, 10)}
    function p:getModData() return self.data end
    function p:getPlayerNum() return self.index end
    function p:isDead() return self.dead == true end
    function p:getSquare() return self.square end
    function p:hasTimedActions() return self.busy == true end
    function p:getMoodles()
        return {getMoodleLevel=function(_, kind) return p.moodles[kind] or 0 end,
            getMoodleDisplayString=function(_, kind) return ({THIRST="Thirsty", HUNGRY="Peckish", BORED="Bored", PAIN="Pain"})[kind] or kind end}
    end
    return p
end
local player, player2 = survivor(0), survivor(1)
function getSpecificPlayer(index) return ({[0]=player, [1]=player2})[index] end

PZAPI = {ModOptions={settings={}, Data={}, saves=0}}
function PZAPI.ModOptions:getOptions(id) return self.settings[id] end
function PZAPI.ModOptions:save() self.saves = self.saves + 1 end
function PZAPI.ModOptions:create(id)
    local object = {options={}, data={}}
    function object:addDescription() end
    function object:apply() end
    function object:getOption(key) return self.options[key] end
    local function add(self, key, kind, value)
        local option = {id=key, type=kind, value=value}
        function option:getValue() return self.value end
        function option:setValue(v) self.value = v end
        self.options[key] = option
        self.data[#self.data + 1] = option
        return option
    end
    function object:addTickBox(key, _, value) return add(self, key, "tickbox", value) end
    function object:addSlider(key, _, low, high, step, value)
        local o = add(self, key, "slider", value); o.min, o.max, o.step = low, high, step; return o
    end
    function object:addComboBox(key)
        local o = add(self, key, "combobox", 1); o.values = {}
        function o:addItem(name) self.values[#self.values + 1] = name end
        return o
    end
    function object:addKeyBind(key, _, value) return add(self, key, "keybind", value) end
    self.settings[id] = object
    self.Data[#self.Data + 1] = object
    return object
end
local other = PZAPI.ModOptions:create("OtherMod"); other:addKeyBind("busy", "", 33)

local Controller = {}
local state = {active=false, phase="idle", message="Choose a training mode to begin.", meditation=3, yoga=5,
    progress={meditation={level=3, current=25, required=200, fraction=0.125}, yoga={level=5, current=40, required=100, fraction=0.4}}}
local gates = {meditation={ready=true, kind="ready"}, yoga={ready=true, kind="ready"}}
local launches, stops, prepares, loans, refuse = {}, {}, 0, {}, {}
function Controller.status() return state end
function Controller.gates() return gates end
function Controller.check(_, mode) return refuse[mode] == nil, refuse[mode] end
function Controller.launch(p, mode, collect, tier)
    launches[#launches + 1] = {player=p, mode=mode, collect=collect, tier=tier}
    if refuse.launch then return false, refuse.launch end
    state.active, state.mode = true, mode
    return true
end
function Controller.stop(p, reason) stops[#stops + 1] = reason; state.active = false; state.phase = "stopped"; state.message = reason end
function Controller.prepare(_, collect, _, force)
    prepares = prepares + 1
    Controller.lastPrepare = {collect=collect, force=force}
    return {food=1, water=0, literature=2, pain=0, nearbyFood=3, nearbyWater=4, nearbyLiterature=0, nearbyPain=0, radius=10,
        unknownContainers=6, warnings={"It is too dark to read here."}}
end
function Controller.setCollectNearby(_, v) Controller.collect = v end
function Controller.loans() return loans end
local outlook, awayCalls = nil, {}
function Controller.outlook() return outlook end
function Controller.setAway(_, away) awayCalls[#awayCalls + 1] = away; state.away = away end
local decisions = {}
function Controller.recentDecisions() return decisions end
package.loaded["AutoMindful/Controller"] = Controller
Controller.realTiers = require "AutoMindful/TierTargets"
local tierNow = {meditation=0, yoga=0}
Controller.realTiers.current = function(_, kind) return tierNow[kind] end

local files = {}
function getFileReader(name) if files[name] then return {readLine=function() return files[name]:match("^[^\n]*") end, close=function() end} end end
function getFileWriter(name, _, append)
    if not append then files[name] = "" end
    return {write=function(_, text) files[name] = (files[name] or "") .. text end, close=function() end}
end

local menus, lastMenu = {}, nil
ISContextMenu = {}
function ISContextMenu:new() return setmetatable({options={}}, {__index=self}) end
function ISContextMenu:addOption(name, target, callback, ...)
    local option = {name=name, target=target, onSelect=callback}
    for index = 1, select("#", ...) do option["param" .. index] = (select(index, ...)) end
    self.options[#self.options + 1] = option
    return option
end
function ISContextMenu:getNew() local m = self:new(); menus[#menus + 1] = m; m.id = #menus; return m end
function ISContextMenu.get() lastMenu = ISContextMenu:new(); return lastMenu end
function ISContextMenu:addSubMenu(option, menu) option.subOption = menu.id end
function ISContextMenu:getSubMenu(id) return menus[id] end
function ISContextMenu:setOptionChecked(option, value) option.checkMark = value end
local function choose(option) return option.onSelect(option.target, option.param1, option.param2, option.param3) end
local function named(menu, name) for _, o in ipairs(menu.options) do if o.name == name then return o end end end
local function names(menu) local out = {}; for _, o in ipairs(menu.options) do out[#out + 1] = o.name end; return table.concat(out, "|") end

ISTimedActionQueue = {queued={}, add=function(a) ISTimedActionQueue.queued[#ISTimedActionQueue.queued + 1] = a end}
ISWalkToTimedAction = {new=function(_, p, s) return {player=p, square=s, setOnComplete=function(self, f) self.done = f end} end}
local nativeYoga = {onAction=function() end}
local nativeMeditation = {onAction=function() end}
ZenWellnessContextMenu = {Options={Yoga=nativeYoga, Meditation=nativeMeditation}}
function ZenWellnessContextMenu.doBuildMenu(index, context)
    local p = getSpecificPlayer(index)
    if p.busy then return end
    local wellness = context:addOption("Wellness")
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(wellness, menu)
    local option = menu:addOption("Yoga", {}, nativeYoga.onAction, nativeYoga, p)
    option.toolTip = "native tip"
    return "native", 3
end
local function event()
    local e = {handlers={}}
    function e.Add(f) e.handlers[#e.handlers + 1] = f end
    function e.Remove(f) for i = #e.handlers, 1, -1 do if e.handlers[i] == f then table.remove(e.handlers, i) end end end
    return e
end
Events = {OnFillWorldObjectContextMenu=event(), OnKeyPressed=event(), OnGameStart=event(), OnCreatePlayer=event(), OnSave=event(), EveryOneMinute=event()}
package.loaded["AutoMindful/SkillsPane"] = {install=function() end}
local zenWatched = false
package.loaded["AutoMindful/ZenMoodle"] = {install=function() end, watch=function() zenWatched = true end, onPlayerReady=function() end}
Clipboard = {setClipboard=function(text) Clipboard.text = text end}

require "AutoMindful_Main"
assert(zenWatched, "The Zen hover watch starts when the file loads, not only when a player is created")
if not AutoMindful.UI then error("window did not load") end
local Window, WorldMenu, Options = AutoMindful.UI, AutoMindful.WorldMenu, require "AutoMindful/Options"
local Preferences = require "AutoMindful/Preferences"

local function rows(window, kind)
    local out = {}
    for _, row in ipairs(window.body.rows) do if row.kind == kind then out[#out + 1] = row end end
    return out
end
local function job(window, title) for _, row in ipairs(rows(window, "job")) do if row.title == title then return row end end end
local function setting(window, label) for _, row in ipairs(rows(window, "setting")) do if row.label == label then return row end end end
local function text(window)
    local out = {}
    for _, row in ipairs(window.body.rows) do out[#out + 1] = tostring(row.text or row.title or row.label or "") .. " " .. tostring(row.sub or "") end
    return table.concat(out, "\n")
end
-- Real hit testing: move the pointer over a row (or one of its buttons), press and release.
local function click(window, wanted)
    local body = window.body
    body:prerender()
    for _, entry in ipairs(body.layout) do
        if entry.row == wanted then
            mouseX, mouseY = body:getAbsoluteX() + entry.x + 5, body:getAbsoluteY() + entry.y + 5
        end
        for _, zone in ipairs(entry.zones or {}) do
            if zone.target == wanted then mouseX, mouseY = body:getAbsoluteX() + zone.x + 4, body:getAbsoluteY() + zone.y + 4 end
        end
    end
    body:onMouseMove()
    assert(body:onMouseDown(), "nothing to press")
    window:refresh() -- the half-second refresh can land while the button is down
    body:onMouseUp()
end
local function button(window, label)
    for _, row in ipairs(rows(window, "buttons")) do for _, b in ipairs(row.buttons) do if b.text == label then return b end end end
end

-- Idle -----------------------------------------------------------------------
files["AutoMindful/window-0.txt"] = "1 62 25 538 828 1\n"
local before
local window = Window.open(player)
assert(window:getX() == 62 and window:getY() == 25 and window.width < 400 and window.height < 420, "The old position carries over, the old size does not")
assert(job(window, "Yoga") and job(window, "Meditation") and job(window, "Yoga and Meditation") and job(window, "Recovery"))
assert(job(window, "Yoga").sub == "Level 5, 40 of 100 XP" and #rows(window, "title") == 0 and not button(window, "Stop"))
assert(job(window, "Recovery").sub:find("while you play or are away", 1, true) and #rows(window, "chips") == 0, "No need, no chips")
player.moodles.THIRST, player.moodles.BORED = 2, 1
window:invalidate()
assert(rows(window, "chips")[1].chips[1].text == "Thirsty" and job(window, "Recovery").sub == "Looks after: thirsty, bored")
passed("idle shows the jobs that apply, live needs, and nothing else")

assert(job(window, "Reach a moodle tier").sub == "Practise, then stop. Up to Mindfulness or Zen III", job(window, "Reach a moodle tier").sub)
tierNow.meditation, tierNow.yoga = 1, 3
window:invalidate()
assert(not job(window, "Reach a moodle tier"), "Nothing left to reach")
tierNow.meditation, tierNow.yoga = 0, 0
state.yoga = 10; state.progress.yoga = {level=10, capped=true, fraction=1}
window:invalidate()
assert(not job(window, "Yoga and Meditation") and job(window, "Yoga").sub:find("Level 10", 1, true) and not job(window, "Yoga").fraction,
    "Training both means nothing once one is finished")
state.yoga = 5; state.progress.yoga = {level=5, current=40, required=100, fraction=0.4}
gates.yoga = {ready=false, kind="endurance", temporary=true, reason=" <RED>Too exhausted"}
window:invalidate()
assert(job(window, "Yoga").sub:find("Rests first: Too exhausted", 1, true) and not job(window, "Yoga").disabled, "A passing blocker is information, not a refusal")
gates.yoga = {ready=true, kind="ready"}
refuse.yoga = "Not while zombies are nearby."
window:invalidate()
assert(job(window, "Yoga").disabled and job(window, "Yoga").sub == "Not while zombies are nearby.")
click(window, job(window, "Yoga"))
assert(#launches == 0, "A refused job cannot be started")
refuse.yoga = nil
gates, refuse.recovery = nil, "Enable Lifestyle: Hobbies with yoga support before starting AutoMindful."
window:invalidate()
assert(#rows(window, "job") == 0 and text(window):find("Enable Lifestyle", 1, true), "One clear sentence instead of a wall of dead buttons")
refuse.recovery, refuse.both = nil, "Lifestyle Wellness is disabled in this world."
window:invalidate()
assert(#rows(window, "job") == 1 and job(window, "Recovery") and text(window):find("Wellness is disabled", 1, true), "Recovery needs no Wellness")
gates, refuse.both = {meditation={ready=true}, yoga={ready=true}}, nil
window:invalidate()
passed("blocked, finished and unreachable jobs explain themselves or disappear")

-- Start, run, switch, stop ----------------------------------------------------
click(window, job(window, "Yoga"))
assert(#launches == 1 and launches[1].mode == "yoga" and launches[1].collect == true and launches[1].player == player)
state.decisionLabel, state.decisionDetail, state.phase = "Practicing Yoga", nil, "yoga"
state.message, state.elapsed = "Practicing yoga. Poses may fail normally.", 754000
state.startProgress = {yoga={level=5, current=10, required=100, fraction=0.1}}
window:invalidate()
assert(#rows(window, "job") == 0 and rows(window, "title")[1].text == "Yoga" and rows(window, "title")[1].right == "12m 34s")
local bar = rows(window, "bar")
assert(#bar == 1 and bar[1].label == "Yoga 5" and bar[1].gain == "+30 XP", "Only the trained skill, with what this session earned")
click(window, button(window, "Switch"))
assert(not named(lastMenu, "Yoga") and named(lastMenu, "Meditation") and named(lastMenu, "Recovery"), "Every other job")
choose(named(lastMenu, "Recovery"))
assert(launches[2].mode == "recovery")
state.mode = "yoga"
window:invalidate()
click(window, button(window, "Stop"))
assert(#stops == 1 and not state.active and job(window, "Yoga") and text(window):find("You stopped AutoMindful", 1, true))
refuse.launch = "Stop moving before training."
click(window, job(window, "Meditation"))
assert(text(window):find("Stop moving before training", 1, true), "A refusal is shown where it was clicked")
refuse.launch = nil
state.active, state.mode = true, "yoga"; window:invalidate(); before = prepares
for _ = 1, 40 do now = now + 500; window:update() end
assert(prepares == before, "A running job scans nothing the window does not show")
state.active, state.mode = false, nil; window:invalidate()
passed("start, switch and stop by clicking, with the result visible")

state.active, state.mode = true, "recovery"
click(window, job(window, "Recovery") or window.body.rows[1])
state.active, state.mode, state.phase = false, nil, "idle"
window:show("now"); window:invalidate()
click(window, job(window, "Reach a moodle tier"))
assert(named(lastMenu, "Mindfulness") and named(lastMenu, "Zen"), names(lastMenu))
local zen = lastMenu:getSubMenu(named(lastMenu, "Zen").subOption)
assert(names(zen) == "Zen I|Zen II|Zen III", names(zen))
choose(zen.options[1])
assert(launches[#launches].mode == "yogaTo" and launches[#launches].tier == 1)
state.active, state.mode = false, nil
passed("tiers open as submenus holding only what can be reached")

-- Recovery shows who it thinks is there, how long things last, what would go wrong.
outlook = {food="4 h", carriedFood="30 min", water="2 h", carriedWater="1 h", foodHours=50, carriedFoodHours=6, waterHours=22,
    carriedWaterHours=11, endlessWater=true, issues={{id="bleeding", severity=3, text="Bleeding. It will be bandaged."}}}
state.active, state.mode, state.phase = true, "recovery", "recovery-idle"
window:show("now"); window:invalidate(true)
local cells = {}
for _, row in ipairs(rows(window, "columns")) do cells[row.label] = row.cells[1].text .. "/" .. row.cells[2].text end
assert(cells.Food == "30 min/4 h" and cells.Drink == "1 h/Running tap", cells.Drink)
assert(text(window):find("It will be bandaged", 1, true))
click(window, setting(window, "Helping while you play"))
assert(awayCalls[1] == true and setting(window, "Looking after everything"))
click(window, setting(window, "Looking after everything")); assert(awayCalls[2] == false)
state.alerts = {{text="Very hungry, and there is nothing to eat within reach."}}
window:invalidate(true); assert(text(window):find("nothing to eat within reach", 1, true))
state.alerts, state.active, state.mode, state.phase = nil, false, nil, "idle"
window:invalidate(true)
assert(not setting(window, "Helping while you play"), "Nothing about being away while no Recovery runs")
passed("Recovery says who it thinks is there, how long supplies last, and what would go wrong first")

-- Other tabs -------------------------------------------------------------------
window:show("supplies")
local columns = rows(window, "columns")
assert(columns[2].label == "Food" and columns[2].cells[1].text == "1" and columns[2].cells[2].text == "3")
assert(text(window):find("6 containers have not been looked into", 1, true) and text(window):find("too dark to read", 1, true))
before = prepares
window:show("log"); now = now + 20000; window:update(); now = now + 20000; window:update()
assert(prepares == before, "Tabs that do not show supplies never scan for them")
window:show("now"); local base = prepares
for _ = 1, 8 do now = now + 500; window:update() end
assert(prepares - base <= 1, "The idle view does not rescan twice a second: " .. (prepares - base))
decisions = {{clock="08:41", code="drinking", label="Drinking", message="Using Water Bottle."}, {clock="08:40", code="stopped", label="AutoMindful stopped"}}
window:show("log")
assert(rows(window, "entry")[1].clock == "08:41" and rows(window, "entry")[1].detail == "Using Water Bottle.")
click(window, button(window, "Copy report"))
assert(Clipboard.text:find("AutoMindful report", 1, true) and Clipboard.text:find("08:41 Drinking", 1, true))
passed("supplies, log and report show live facts and scan only when looked at")

window:show("supplies")
click(window, setting(window, "Look for supplies"))
assert(#lastMenu.options == 3 and named(lastMenu, "Walk to nearby supplies").checkMark)
choose(named(lastMenu, "Only what you carry"))
assert(Preferences.range(player) == "carried" and not Options.searchNearby() and Controller.collect == false
    and not setting(window, "Search radius"), "One choice sets both stored switches; the radius only matters when walking")
click(window, setting(window, "Look for supplies")); choose(named(lastMenu, "Only what is within reach"))
assert(Preferences.range(player) == "reach" and Controller.collect == true)
click(window, setting(window, "Look for supplies")); choose(named(lastMenu, "Walk to nearby supplies"))
click(window, setting(window, "Search radius")); choose(named(lastMenu, "20 tiles"))
assert(Options.searchRadius() == 20 and PZAPI.ModOptions.saves > 0)
window:show("settings")
local relief = setting(window, "Practise for relief"); assert(relief.toggle == true)
click(window, relief); assert(Options.practiceCare() == false and setting(window, "Practise for relief").toggle == false)
click(window, setting(window, "Training both")); choose(named(lastMenu, "Lowest progress first")); assert(Options.cyclePolicy() == "lowest")
click(window, setting(window, "Relief tier"))
local mind = lastMenu:getSubMenu(lastMenu.options[1].subOption)
choose(mind.options[1]); assert(Options.minimumTier("recovery", "meditation") == 0)
click(window, setting(window, "Log detail")); choose(named(lastMenu, "Decisions")); assert(Options.logLevel() == 2)
Options.set("logLevel", 3)
local shown = 0
local addTip = ISToolTip.addToUIManager
ISToolTip.addToUIManager = function(self) shown = shown + 1; return addTip(self) end
window.body:prerender()
for _, entry in ipairs(window.body.layout) do
    if entry.row.label == "Practise for relief" then mouseX, mouseY = window.body:getAbsoluteX() + entry.x + 5, window.body:getAbsoluteY() + entry.y + 5 end
end
window.body:onMouseMove(); window.body:prerender()
assert(shown == 1 and window.body.tipUI.description:find("ease a need", 1, true), "Hovering explains a setting")
window.body:onMouseMoveOutside(); window.body:prerender()
assert(not window.body.tipUI:getIsVisible())
passed("every setting is changed in place and saved at once, and explains itself on hover")

click(window, setting(window, "Open and close key"))
assert(window.capturing and window.wantsKeys and window:isKeyConsumed(50))
window:onKeyRelease(33); assert(window.capturing and setting(window, "Open and close key").value:find("in use", 1, true), "A key another mod uses is refused, visibly")
window:onKeyRelease(50); assert(not window.capturing and Options.windowKey() == 50)
assert(window:isKeyConsumed(50) and not window:isKeyConsumed(50))
click(window, setting(window, "Open and close key")); window:onKeyRelease(Keyboard.KEY_ESCAPE)
assert(not window.capturing and Options.windowKey() == 50)
local function press(key) for _, f in ipairs(Events.OnKeyPressed.handlers) do f(key) end end
press(50); assert(not window:getIsVisible()); press(50); assert(window:getIsVisible(), "The same key opens and closes")
press(Keyboard.KEY_ESCAPE); assert(window:getIsVisible(), "Escape belongs to the game")
passed("the shortcut can be bound, refuses taken keys, and toggles the window")

-- Size and place ---------------------------------------------------------------
window:show("now")
local fitted = window.height
window:show("settings"); assert(window.height > fitted, "Fits its contents")
window:show("now"); assert(window.height == fitted, "And back")
window.dragOrigin = nil
window:onMouseDown(); window:setX(300); window:setY(200); window:onMouseUp()
assert(files["AutoMindful/window-0.txt"] == "2 300 200 - - 0\n", files["AutoMindful/window-0.txt"])
window:onMouseDown(); window:setX(420); window:invalidate(); assert(window:getX() == 420, "A refresh does not snatch it back mid-drag")
window:setX(300); window:onMouseUp()
assert(window.resizeWidget.x == window.width - 12 and window.resizeWidget.y == window.height - 12
    and window.resizeWidget2.y == window.height - 12 and window.resizeWidget2.width == window.width - 12, "The handles are where they are drawn")
do
    local corner, edge = window.resizeWidget, window.resizeWidget2
    local startW, startH = window.width, window.height
    assert(corner.anchorRight == false and corner.anchorBottom == false and edge.anchorBottom == false, "Nothing else moves the handles")
    mouseX, mouseY = 600, 400
    corner:onMouseDown(3, 3); assert(corner.captured)
    for i = 1, 40 do
        mouseX, mouseY = 600 + i * 2, 400 + i
        corner:onMouseMoveOutside(1, 1)
        assert(window.width == startW + i * 2 and window.height == startH + i, "The corner stays under the mouse")
        corner:onMouseMove(0, 0); window:invalidate()
        assert(window.width == startW + i * 2 and window.height == startH + i, "And a refresh during the drag changes nothing")
    end
    mouseX, mouseY = -4000, -4000; corner:onMouseMoveOutside(0, 0)
    local least = window.width
    mouseX, mouseY = 600, 400; corner:onMouseMoveOutside(0, 0)
    assert(least < startW and window.width == startW and window.height == startH, "Past the smallest size and back loses nothing")
    mouseX = 660; corner:onMouseMoveOutside(0, 0); corner:onMouseUpOutside(0, 0)
    assert(not corner.captured and files["AutoMindful/window-0.txt"]:find(" " .. (startW + 60) .. " ", 1, true), files["AutoMindful/window-0.txt"])
    mouseX = 900; corner:onMouseMove(0, 0); assert(window.width == startW + 60, "Let go is let go")
    mouseX, mouseY = 100, 100
    edge:onMouseDown(3, 3); mouseX, mouseY = 300, 150; edge:onMouseMoveOutside(0, 0); edge:onMouseUp(0, 0)
    assert(window.width == startW + 60 and window.height == startH + 50, "The bottom edge is height only")
    edge:onMouseDown(3, 3); edge:onMouseUp(0, 0)
    assert(window.geometry.height, "One click changes nothing")
    edge:onMouseDoubleClick(3, 3); edge:onMouseUp(0, 0)
    assert(window.width == startW + 60 and window.geometry.height == nil and window.geometry.width, "Double click the edge: height fits")
    corner:onMouseDown(3, 3); corner:onMouseUp(0, 0)
    corner:onMouseDoubleClick(3, 3); corner:onMouseUp(0, 0); corner:onMouseMove(0, 0)
    assert(window.geometry.width == nil and window.geometry.height == nil and window.width == startW, "Double click the corner: both fit")
    assert(files["AutoMindful/window-0.txt"]:find("- - 0", 1, true), files["AutoMindful/window-0.txt"])
    local fitted = window.height
    mouseX, mouseY = 600, 400
    corner:onMouseDown(0, 0); mouseX = 480; corner:onMouseMoveOutside(0, 0); corner:onMouseUp(0, 0)
    corner:onMouseDoubleClick(3, 3); window:invalidate()
    assert(window.width == startW and window.height == fitted, "From a narrow window, too: " .. window.height .. " not " .. fitted)
    corner:onMouseDown(0, 0); mouseX = 520; corner:onMouseMoveOutside(0, 0)
    window:close(); assert(not window.resize and not corner.captured, "Closing lets go")
    window = Window.open(player); startW = window.width
    mouseX = 900; corner:onMouseMove(0, 0); assert(window.width == startW)
    corner:onMouseDown(0, 0); corner:onMouseUp(0, 0); corner:onMouseDoubleClick(0, 0); window:invalidate()
    passed("resizing follows the mouse exactly, and a double click fits the contents")
end
window:onUserResize(500, 250); window:saveGeometry()
assert(window.width == 500 and window.height == 250)
window:show("settings"); assert(window.height == 250 and window.body.contentHeight > window.body.height and window.body.vscroll.visible
    and window.body.vscroll.height == window.body.height)
window.body:onMouseWheel(1); assert(window.body:getYScroll() < 0, "Scrolls when the player chose a smaller size")
window:resetSize(); assert(window.height > 250)
screenW, screenH = 800, 500
window:invalidate(true)
assert(window.x + window.width <= 800 and window.y + window.height <= 500, "Always on screen")
screenW, screenH = 1920, 1036
window:show("now")
state.active, state.mode, state.phase = true, "yoga", "yoga"
window:invalidate()
window:toggleMini(); assert(window.mini and window.height < 60 and window.strip.visible and not window.body.visible)
drawn = {}; window.strip:prerender(); assert(drawn[1].text == "Stop" and drawn[2].text == "Practicing Yoga"); drawn = nil
window.strip:onRightMouseUp(); assert(named(lastMenu, "Stop"), "Right-click reaches the window through its parts")
window.strip.pointer = true
mouseX = window.strip:getAbsoluteX() + 5; window.strip:onMouseDown(); assert(state.active)
mouseX = window.strip:getAbsoluteX() + window.strip.width - 12; window.strip:onMouseDown(); assert(not state.active, "Stop stays in reach")
state.active, state.phase = true, "yoga"; window:invalidate()
state.active = false; window:invalidate()
assert(not window.mini and window.body.visible, "Nothing to shrink while idle")
before = prepares; window:show("supplies"); click(window, button(window, "Look again"))
assert(prepares > before, "A remembered strip never hides supplies while idle")
window:show("now")
window:toggleMini()
passed("it fits its contents, remembers what the player chose, and shrinks to one line")

-- Nothing is drawn outside the window, at any font size, in any tab.
for _, font in ipairs({{5, 13}, {7, 16}, {10, 22}, {14, 30}}) do
    charWidth, lineHeight = font[1], font[2]
    for _, mode in ipairs({"none", "both", "recovery"}) do
        local active = mode ~= "none"
        state.active, state.mode = active, active and mode or nil
        for _, view in ipairs({"now", "supplies", "log", "guide", "settings"}) do
            window.view = view; window:invalidate(true)
            drawn = {}
            window.body.pointer = nil
            window.body:prerender()
            for _, item in ipairs(drawn) do
                assert(item.left >= -1 and item.right <= item.width + 1, view .. " at font " .. font[2] .. ": " .. item.text .. " " .. item.left .. ".." .. item.right .. " of " .. item.width)
            end
            assert(#drawn > 0)
            drawn = nil
        end
    end
end
charWidth, lineHeight, window.view, state.active, state.mode = 7, 16, "now", false, nil
window:invalidate(true)
passed("text stays inside the window at every font size, in every tab, idle and running")

-- Right-click menu ---------------------------------------------------------------
local function worldMenu(objects, p)
    local context = ISContextMenu:new()
    ZenWellnessContextMenu.doBuildMenu((p or player).index, context, objects)
    for _, f in ipairs(Events.OnFillWorldObjectContextMenu.handlers) do f((p or player).index, context, objects, false) end
    return context
end
local function at(x, y, sprite, partner)
    local o = {getSpriteName=function() return sprite end}
    local s = square(x, y, {o})
    if partner then s.getE = function() return square(x + 1, y, {{getSpriteName=function() return partner end}}) end end
    function o:getSquare() return s end
    return o
end
local here, far = at(10, 11), at(40, 40)
local context = worldMenu({far})
assert(names(context) == "Wellness", "Idle adds nothing at the top level: " .. names(context))
local wellness = context:getSubMenu(context.options[1].subOption)
assert(names(wellness) == "Yoga|AutoMindful", names(wellness))
local native = wellness.options[1]
assert(native.onSelect == nativeYoga.onAction and native.param1 == nativeYoga and native.toolTip == "native tip" and not native.subOption,
    "Lifestyle's own action is untouched and still one click")
local ours = wellness:getSubMenu(wellness.options[2].subOption)
assert(names(ours) == "Yoga|Meditation|Yoga and Meditation|Reach a moodle tier|Recovery|Show window", names(ours))
assert(named(ours, "Yoga").toolTip.description == "Level 5, 40 of 100 XP" and not named(ours, "Yoga").notAvailable)
refuse.meditation = "Not while zombies are nearby."
context = worldMenu({far}); wellness = context:getSubMenu(context.options[1].subOption); ours = wellness:getSubMenu(wellness.options[2].subOption)
assert(named(ours, "Meditation").notAvailable and named(ours, "Meditation").toolTip.description == "Not while zombies are nearby.")
refuse.meditation = nil
WorldMenu.attach(context, player); WorldMenu.attach(context, player)
assert(#wellness.options == 2, "Never twice")
choose(named(ours, "Yoga")); assert(launches[#launches].mode == "yoga")
passed("idle: one entry beside Lifestyle's own actions, listing what can be done now")

context = worldMenu({far})
assert(names(context) == "Wellness" and #context:getSubMenu(context.options[1].subOption).options == 1, "An idle Recovery adds no second entry")
player.busy = true
context = worldMenu({far})
assert(#context.options == 0, "Running, and you clicked somewhere else: nothing in the way")
context = worldMenu({here})
assert(names(context) == "AutoMindful: Yoga", names(context))
ours = context:getSubMenu(context.options[1].subOption)
assert(names(ours) == "Stop|Switch to|Show window", names(ours))
state.mode = "recovery"
local helping = worldMenu({here}); helping = helping:getSubMenu(helping.options[1].subOption)
assert(names(helping) == "Stop|I am going AFK|Switch to|Show window", names(helping))
choose(named(helping, "I am going AFK")); assert(awayCalls[#awayCalls] == true)
state.away, state.mode = nil, "yoga"
local switch = ours:getSubMenu(named(ours, "Switch to").subOption)
assert(not named(switch, "Yoga") and named(switch, "Recovery"))
choose(named(ours, "Stop")); assert(stops[#stops] == "You stopped AutoMindful." and not state.active)
player.busy = false
context = worldMenu({at(30, 30, "floors_rugs_01_52")}); assert(names(context) == "Wellness", "Half a mat is no place to train")
context = worldMenu({at(30, 30, "floors_rugs_01_52", "floors_rugs_01_53")})
ours = context:getSubMenu(named(context, "AutoMindful").subOption)
assert(names(ours) == "Train Yoga here|Show window", names(ours))
choose(ours.options[1])
local walk = ISTimedActionQueue.queued[1]
assert(walk and walk.square:getX() == 30, "Walk onto that mat first")
local count = #launches; walk.done(); assert(#launches == count + 1 and launches[#launches].mode == "yoga")
state.active, state.mode = false, nil
context = worldMenu({at(30, 30, "floors_rugs_01_10")}); assert(names(context) == "Wellness", "Other rugs are just rugs")
Options.set("generalContextMenu", true)
context = worldMenu({far}); assert(names(context) == "Wellness|AutoMindful")
Options.set("generalContextMenu", false)
player.dead = true; context = worldMenu({here}); assert(names(context) == "Wellness" and #context:getSubMenu(context.options[1].subOption).options == 1)
player.dead = false
passed("running: on your survivor only; on a mat: train here; elsewhere: nothing")

-- Two local players never see each other's window, menu or job.
local second = Window.open(player2)
assert(second ~= window and second.player == player2 and Window.windows[1] == second)
local replacement = survivor(0)
player = replacement
assert(Window.open(replacement) ~= window and not window:getIsVisible(), "A new survivor gets a new window")
replacement.dead = true; now = now + 5000; Window.windows[0]:update()
assert(not Window.windows[0]:getIsVisible())
passed("windows belong to one local survivor")
print("UI PASS")
