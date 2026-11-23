-- Installed B42 Lua widgets and PZAPI, with UIElement graphics and profile-file
-- boundaries doubled. Run on a disposable in-memory file, not a save/profile.
package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
local media = arg and arg[1]
if not loadUpstream and media then
    function loadUpstream(path) return assert(loadfile(media .. "/lua/" .. path))() end
end
if not loadUpstream then
    print("SKIP scoped settings native widgets (requires --game)")
    return
end

UIFont = {Small=1, Medium=2}
Keyboard = {KEY_ESCAPE=1,KEY_0=11,KEY_H=35,KEY_J=36,KEY_K=37}
local fontHeight, screenW, screenH = 17, 1280, 900
local bindings, doubles = {}, {opened=0,closed=0}
keyBinding = {}
function getCore()
    return {getScreenWidth=function() return screenW end,getScreenHeight=function() return screenH end,
        getOptionFontSizeReal=function() return 3 end,
        getKey=function(_, name) return bindings[name] or 0 end}
end
function getText(value) return value end
function getTextManager()
    return {getFontHeight=function() return fontHeight end, MeasureStringX=function(_, _, text)
        local longest = 0
        for line in text:gmatch("[^\n]+") do longest = math.max(longest, #line) end
        return longest * (fontHeight >= 23 and 9 or 7)
    end}
end
function getKeyName(code) return ({[0]="None",[11]="0",[35]="H",[36]="J",[37]="K"})[code] or "Unknown" end
function getTexture(name) return {name=name} end
function getSoundManager() return {playUISound=function() end} end
UITransition = {new=function() return {} end}

local disk, saves, failWrite = "", 0, false
function getFileWriter(name, create, append)
    assert(name=="ModOptions.ini" and create and not append, "Use only the existing stock profile file")
    if failWrite then error("simulated native writer failure") end
    disk, saves = "", saves+1
    return {write=function(_, bytes) disk=disk..bytes end,close=function() end}
end
function getFileReader(name, create)
    assert(name=="ModOptions.ini" and create)
    local i=1
    return {readLine=function()
        if i > #disk then return nil end
        local eol=disk:find("[\r\n]",i)
        local line=disk:sub(i,(eol or (#disk+1))-1)
        i=(eol or #disk)+1
        if eol and disk:sub(eol,i)=="\r\n" then i=i+1 end
        return line
    end,close=function() end}
end
luautils = {split=function(line, sep)
    local out={}
    for part in line:gmatch("[^"..sep.."]+") do out[#out+1]=part end
    return out
end}

ISUIElement = {}
function ISUIElement:derive(kind)
    return setmetatable({Type=kind}, {__index=self})
end
function ISUIElement:new(x,y,w,h)
    return setmetatable({x=x,y=y,width=w,height=h,children={},visible=true}, {__index=self})
end
function ISUIElement:initialise() end
function ISUIElement:instantiate()
    if self.constructed then return end
    self.constructed = true
    if self.createChildren then self:createChildren() end
end
function ISUIElement:addChild(child)
    child:instantiate()
    child.parent = self
    self.children[#self.children+1] = child
end
function ISUIElement:addToUIManager()
    self:instantiate()
    self.inManager=true
    doubles.opened=doubles.opened+1
end
function ISUIElement:removeFromUIManager()
    self.inManager=false
    doubles.closed=doubles.closed+1
end
function ISUIElement:setVisible(visible) self.visible=visible end
function ISUIElement:getIsVisible() return self.visible end
function ISUIElement:isMouseOver() return false end
function ISUIElement:setWantKeyEvents(value) self.wantsKeys=value end
function ISUIElement:setX(x) self.x=x end
function ISUIElement:setY(y) self.y=y end
function ISUIElement:setWidth(w) self.width=w end
function ISUIElement:setHeight(h) self.height=h end
function ISUIElement:getX() return self.x end
function ISUIElement:getY() return self.y end
function ISUIElement:getWidth() return self.width end
function ISUIElement:getHeight() return self.height end
function ISUIElement:setScrollChildren(value) self.scrollChildren=value end
function ISUIElement:addScrollBars() self.vscroll={native=true} end
function ISUIElement:setScrollHeight(h) self.scrollHeight=h end
function ISUIElement:getScrollHeight() return self.scrollHeight or 0 end
function ISUIElement:setYScroll(y) self.scrollY=math.max(math.min(0,y), math.min(0,self.height-self:getScrollHeight())) end
function ISUIElement:getYScroll() return self.scrollY or 0 end
function ISUIElement:bringToTop() end
ISResizeWidget=ISUIElement:derive("ISResizeWidget") -- real resize widget not needed in non-resizable popup
ISScrollingListBox=ISUIElement:derive("ISScrollingListBox")
ISTextEntryBox=ISUIElement:derive("ISTextEntryBox")
for _, name in ipairs({"ISUI/ISUIElement","ISUI/ISInventoryPane","ISUI/ISResizeWidget","ISUI/ISMouseDrag","defines",
        "ISUI/ISScrollingListBox","ISUI/ISTextEntryBox","ISUI/ISContextMenu","ISUI/ISToolTip"}) do
    package.loaded[name]=true
end
-- Only the rooted combo popup's window/paint is doubled. Constructors,
-- dropdown selection, input dispatch and close behavior use installed Lua.
local function load(name)
    loadUpstream("client/" .. name .. ".lua")
    package.loaded[name]=true
end
for _, name in ipairs({"PZAPI/ModOptions","ISUI/ISPanel","ISUI/ISButton","ISUI/ISLabel","ISUI/ISTickBox","ISUI/ISComboBox",
        "ISUI/ISCollapsableWindow","RadioCom/ISUIRadio/ISSliderPanel"}) do load(name) end
local sharedPopup=ISUIElement:new(0,0,1,1)
ISComboBox.SharedPopup=sharedPopup
function sharedPopup:setFont() end
function sharedPopup:setComboBox(owner) self.parentCombo=owner end

local Options=require "AutoMindful/Options"
local Settings=require "AutoMindful/SettingsPanel"
local Tiers=require "AutoMindful/TierMenu"
assert(Tiers.title("meditation")=="Meditate to..." and Tiers.title("yoga")=="Do Yoga to...", "ASCII labels in both menu and panel")
local stock=PZAPI.ModOptions
local group=assert(stock:getOptions("AutoMindful"))
assert(Options.modSettings()==group)
local outsider=stock:create("NotAutoMindful","Untouched"):addTickBox("unrelated","Unrelated checkbox",true)
local unknown1="tickbox|UnknownMod|unloaded|false"
local unknown2="textentry|AnotherUnknownMod|note|value with intact spaces "
disk=unknown1.."\r\n"..unknown2.."\n"
stock:load()
local originalUnknown=stock.OtherOptions
assert(#originalUnknown==2 and originalUnknown[1]==unknown1 and originalUnknown[2]==unknown2)
local currentY=450
local owner={width=540,refreshes=0,mode="both",
    getX=function() return 720 end,getY=function() return currentY end,getIsVisible=function() return true end}
function owner:refresh() self.refreshes=self.refreshes+1 end
local otherOwner={width=465, getX=function() return 50 end, getY=function() return 20 end, getIsVisible=owner.getIsVisible,refresh=owner.refresh,refreshes=0}
local scout=group:getOption("searchNearby")
local cycle=group:getOption("cyclePolicy")
local radius=group:getOption("searchRadius")
local key=group:getOption("openWindow")
local tier=group:getOption("rotationYogaZenTier")
local stockScout=ISTickBox:new(0,0,25,25,"")
stockScout:addOption("")
stockScout:setSelected(1,true)
scout.element=stockScout
local stockCycle=ISComboBox:new(0,0,200,25)
cycle.element=stockCycle
local stockRadius=ISSliderPanel:new(0,0,200,25)
stockRadius:setValues(radius.min,radius.max,radius.step,radius.step,true)
radius.element=stockRadius
local stockKey=ISButton:new(0,0,90,25,"None")
key.element={btn=stockKey,keyCode=0,shift=true}
local stockApplies=0
function group:apply() stockApplies=stockApplies+1 end
local appliedScout
function scout:onChangeApply(value) appliedScout=value end
local function rows(pane)
    local result={}
    for _, row in ipairs(pane.rows) do
        assert(not result[row.option.id],"Each live option is mapped only once")
        result[row.option.id]=row
    end
    return result
end
local pane=assert(Settings.toggle(owner))
assert(pane.title=="AutoMindful Settings" and owner.settingsWindow==pane and pane.inManager)
assert(pane.x>=0 and pane.y>=0 and pane.x+pane.width<=screenW and pane.y+pane.height<=screenH)
local r=rows(pane)
local count=0
for _, option in ipairs(group.data) do
    if option.id then count=count+1;assert(r[option.id].option==option and r[option.id].label.tooltip==option.tooltip) end
end
assert(#pane.rows==count and r.unrelated==nil and not r.searchNearby.control.expanded)
assert(r.searchNearby.control~=stockScout and scout.element==stockScout and cycle.element==stockCycle)
assert(pane.body.vscroll and not pane.body:onMouseWheel(-1), "No scroll consumes input on a roomy screen")
local stale=pane
r.searchNearby.control:forceClick()
r.searchRadius.control:setCurrentValue(18)
r.cyclePolicy.control:setSelected(2)
r.rotationYogaZenTier.control:setSelected(2)
assert(r.strictRecoveryTier and not Options.strictRecoveryTier())
r.strictRecoveryTier.control:forceClick()
assert(Options.searchNearby() and Options.searchRadius()==10 and Options.cyclePolicy()=="alternate"
    and Options.minimumTier("rotation","yoga")==4 and not Options.strictRecoveryTier() and saves==0,"Draft edits do not mutate the game or disk")
-- Simulate the native UI manager's callback-before-isKeyConsumed ordering.
r.openWindow.control:forceClick()
assert(pane.wantsKeys and pane:isKeyConsumed(Keyboard.KEY_J) and key:getValue()==0)
bindings["Forward"]=Keyboard.KEY_J
keyBinding[1]={value="Forward",key=Keyboard.KEY_J}
pane:onKeyRelease(Keyboard.KEY_J)
assert(pane.wantsKeys and pane:isKeyConsumed(Keyboard.KEY_J) and r.openWindow.control:getTitle()=="Key in use")
pane:onKeyRelease(Keyboard.KEY_ESCAPE)
assert(pane:isKeyConsumed(Keyboard.KEY_ESCAPE) and not pane:isKeyConsumed(Keyboard.KEY_ESCAPE) and not pane.wantsKeys)
r.openWindow.control:forceClick()
pane:onKeyRelease(Keyboard.KEY_K)
assert(pane:isKeyConsumed(Keyboard.KEY_K) and not pane.wantsKeys and r.openWindow.control.keyCode==Keyboard.KEY_K)
-- An untouched row must not roll back a simultaneous outside change.
local practice=group:getOption("practiceCare")
practice:setValue(false)
r.cyclePolicy.control.expanded=true
r.cyclePolicy.control:showPopup()
assert(sharedPopup.inManager and sharedPopup.parentCombo==r.cyclePolicy.control)
local tip=ISUIElement:new(0,0,1,1)
tip:addToUIManager()
pane.saveButton.tooltipUI=tip
pane.saveButton:forceClick()
assert(not sharedPopup.inManager and not r.cyclePolicy.control.expanded and not tip.inManager,
    "Closing retires only the popup's owned combo and tooltip")
assert(not pane.inManager and owner.settingsWindow==nil and not pane.wantsKeys and owner.mode=="both")
assert(saves==1 and stockApplies==1 and owner.refreshes==1 and owner.forceSupplyRefresh and owner.nextRefresh==0)
assert(Options.searchNearby()==false and not stockScout:isSelected(1) and appliedScout==false)
assert(Options.searchRadius()==18 and stockRadius:getCurrentValue()==18)
assert(Options.cyclePolicy()=="lowest" and stockCycle:getSelected()==2)
assert(Options.minimumTier("rotation","yoga")==1 and not Options.practiceCare() and Options.strictRecoveryTier())
assert(Options.windowKey()==Keyboard.KEY_K and key.element.keyCode==Keyboard.KEY_K and stockKey:getTitle()=="K" and not key.element.shift)
assert(outsider:getValue()==true and scout.element==stockScout and cycle.element==stockCycle)
assert(disk:find("slider|AutoMindful|searchRadius|18",1,true)
    and disk:find("keybind|AutoMindful|openWindow|37",1,true)
    and disk:find("tickbox|NotAutoMindful|unrelated|true",1,true))
assert(stock.OtherOptions==originalUnknown and originalUnknown[1]==unknown1 and originalUnknown[2]==unknown2,
    "An AutoMindful save leaves the stock registry's original unknown table untouched")
assert(disk:find(unknown1.."\r\n"..unknown2.."\r\n",1,true),
    "A stock Save initiated by AutoMindful must preserve separate disabled-mod INI records byte for byte")
-- Re-read with exactly the same PZAPI loader the global Mods tab uses.
scout:setValue(true)
cycle:setValue(3)
radius:setValue(4)
group:getOption("strictRecoveryTier"):setValue(false)
stock:load()
assert(not Options.searchNearby() and Options.cyclePolicy()=="lowest" and Options.searchRadius()==18 and Options.strictRecoveryTier())
assert(#stock.OtherOptions==2 and stock.OtherOptions[1]==unknown1 and stock.OtherOptions[2]==unknown2,
    "Reloading the saved INI keeps both disabled-mod records")
local reloaded=stock.OtherOptions
local exactDisk=disk
failWrite=true
local success,failure=pcall(Options.setCycleIndex,3)
failWrite=false
assert(not success and tostring(failure):find("simulated native writer failure",1,true))
assert(stock.OtherOptions==reloaded and reloaded[1]==unknown1 and reloaded[2]==unknown2 and disk==exactDisk,
    "The original registry table is restored even when the stock save throws")
stock:load()

pane=Settings.toggle(owner)
r=rows(pane)
assert(pane~=stale and r.searchRadius.control:getCurrentValue()==18 and not r.searchNearby.control:isSelected(1))
r.searchNearby.control:forceClick()
r.openWindow.control:forceClick()
pane.cancelButton:forceClick()
assert(not Options.searchNearby() and not pane.wantsKeys and saves==1 and owner.refreshes==1)
pane=Settings.toggle(owner)
pane.saveButton:forceClick()
assert(saves==1 and owner.refreshes==1,"Saving unchanged does not rewrite the registry")
pane=Settings.toggle(owner)
r=rows(pane)
-- Clicking the header gear again and replacing it with another split-screen
-- owner's settings both release capture; a foreign native popup stays alone.
r.openWindow.control:forceClick()
assert(Settings.toggle(owner)==nil and not pane.wantsKeys and not pane.inManager)
pane=Settings.toggle(owner)
r=rows(pane)
local foreignPopupOwner=ISComboBox:new(0,0,100,20)
sharedPopup.parentCombo=foreignPopupOwner
sharedPopup:addToUIManager()
r.cyclePolicy.control.expanded=true -- stale state distinct from actual shared owner
local replacement=Settings.toggle(otherOwner)
assert(not pane.inManager and replacement.inManager and sharedPopup.inManager and sharedPopup.parentCombo==foreignPopupOwner)
Settings.close(owner)
assert(replacement.inManager)
Settings.close(otherOwner)
assert(not replacement.inManager and otherOwner.settingsWindow==nil)
sharedPopup:removeFromUIManager()
assert(saves==1)

screenW,screenH,fontHeight,currentY=354,396,23,2000
pane=Settings.toggle(owner)
assert(pane.x>=0 and pane.y>=0 and pane.x+pane.width<=screenW and pane.y+pane.height<=screenH)
assert(pane.body:getScrollHeight()>pane.body.height and pane.body:onMouseWheel(1) and pane.body:getYScroll()==-32)
assert(pane.body.y+pane.body.height<pane.saveButton.y and pane.saveButton.y+pane.saveButton.height<=pane.height)
for _, row in ipairs(pane.rows) do
    local control, label = row.control, row.label
    assert(control.x>=0 and control.x+control.width<=pane.body.width)
    assert(label.x+label.width<=pane.body.width)
    assert(label.x+label.width < control.x or label.y+label.height <= control.y,
        "Row text never overlaps its control at a narrow width with a large game font: "..row.option.id)
end
Settings.close(owner)
assert(saves==1,"Opening, scrolling and closing does not save player settings")
print("PASS scoped AutoMindful settings: stock widgets and ModOptions; game/profile boundaries doubled")
