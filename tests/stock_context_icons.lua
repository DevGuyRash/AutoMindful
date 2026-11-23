-- Replay unmodified stock B42 menu allocation, decoration, pooling, and renderer dispatch.
-- The VFS, texture handles and GPU are explicit boundary doubles, not an in-game screenshot.
if loadTest then loadTest("ui.lua") else assert(loadfile("tests/ui.lua"))() end
local menuPath = "client/ISUI/ISContextMenu.lua"
if loadUpstream then loadUpstream(menuPath)
else assert(loadfile(assert(arg[1], "stock media directory required").."/lua/"..menuPath))() end
getCore().isTutorial=function() return false end
table.wipe=function(t) for k in pairs(t) do t[k]=nil end end
local function nop() end
local roots={}
local function newMenu(n)
    local m=setmetatable({options={},optionPool={},numOptions=1,player=n or 0,instanceMap={},subMenuPool={},subOptionNums=0},{__index=ISContextMenu})
    for _,key in ipairs({"instantiate","addToUIManager","setFontFromOption","setForceCursorVisible","bringToTop","setVisible","setY","setX","setHeight","setWidth","calcHeight","initialise"}) do m[key]=nop end
    m.calcWidth=function() return 100 end; m.getX=function() return 5 end; m.getY=function() return 2 end
    return m
end
function getPlayerContextMenu(n) if not roots[n] then roots[n]=newMenu(n) end;return roots[n] end
function ISContextMenu:new() return newMenu() end
local expected={["Open AutoMindful"]={"Open","Item_Clipboard"}, ["Check supplies"]={"Supplies","Item_Backpack"},
    ["Train yoga"]={"Yoga","Item_Dumbbell"},["Train meditation"]={"Meditate","Item_Candle"},
    ["Recovery"]={"Endurance","Moodle_Icon_Endurance"},
    ["Meditate to..."]={"Mindful","FavoriteStar"},["Do Yoga to..."]={"Mindful","FavoriteStar"}}
local mounted,misses,looseLoads=false,{},0
function fileExists(key) return mounted and key:match("^media/ui/AutoMindful/%a+%.png$")~=nil end
function getTexture(key)
    if key:match("^media/ui/AutoMindful/") then
        if not mounted then misses[key]=true end
        if misses[key] then return nil end
        if not loadUpstream then
            local f=assert(io.open("mods/AutoMindful/common/"..key,"rb"),key)
            assert(f:read(8)=="\137PNG\r\n\26\n");f:close()
        end
        looseLoads=looseLoads+1
        return {key=key}
    end
    for _,pair in pairs(expected) do if pair[2]==key then return {key=key} end end
end
package.loaded["AutoMindful/ContextMenu"]=nil
local c=require "AutoMindful/ContextMenu"
local items=0
ISInventoryItem={renderItemIcon=function(_,item) assert(item.native);items=items+1 end}
local function visit()
    for i,mode in ipairs({"Yoga","Meditation"}) do
        local r,p=getPlayerContextMenu(i-1),getSpecificPlayer(i-1);local spec=ZenWellnessContextMenu.Options[mode]
        r:clear()
        local row=r:addOption(mode,r,spec.onAction,spec,p);row.itemForTexture={native=true}
        c.attach(r,p);c.attach(r,p)
        local sub=r:getSubMenu(row.subOption);assert(sub.player==i-1)
        assert(#r.options==1 and #sub.options==(mode=="Yoga" and 5 or 6))
        local actual
        sub.drawTextureScaledAspect=function(_,t,x,y,w,h) assert(w==17 and h==17 and t.key);actual=t.key end
        for _,o in ipairs(sub.options) do
            actual=nil;sub:renderOptionTextureOrColor(o,1,2,17,17)
            local pair=expected[o.name]
            if pair then
                local wanted=mounted and "media/ui/AutoMindful/"..pair[1]..".png" or pair[2]
                assert(actual==wanted,mode.." / "..o.name.." expected "..wanted.."; got "..tostring(actual))
            else assert(o.name==mode.." (once)" and actual==nil and o.itemForTexture==row.itemForTexture) end
        end
        assert(row.itemForTexture.native and not row.iconTexture)
    end
end
visit()
for k in pairs(misses) do error("unmounted path poisoned native cache: "..k) end
assert(items==2 and looseLoads==0)
mounted=true;visit()
assert(items==4 and looseLoads==6)
print("Stock B42 menu rendered the right textures through its real option dispatch; Java texture loading/drawing modeled.")
