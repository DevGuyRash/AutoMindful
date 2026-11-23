package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
local stock = arg and arg[1]
if not loadUpstream and stock then
    function loadUpstream(name) return assert(loadfile(stock .. "/lua/" .. name))() end
end
function getText(value) return value end
local disk = {}
function getFileWriter(name, create, append)
    assert(name == "ModOptions.ini" and create and not append)
    disk = {}
    return {write=function(_, line) disk[#disk+1] = line:gsub("\r?\n$", "") end, close=function() end}
end
function getFileReader(name, create)
    assert(name == "ModOptions.ini" and create)
    local index = 0
    return {readLine=function() index=index+1;return disk[index] end, close=function() end}
end
luautils={split=function(line, separator)
    local out={}
    for part in line:gmatch("[^" .. separator .. "]+") do out[#out+1]=part end
    return out
end}
if loadUpstream then
    loadUpstream("client/PZAPI/ModOptions.lua")
else
    local records={}
    PZAPI={ModOptions={}}
    function PZAPI.ModOptions:getOptions(id) return records[id] end
    function PZAPI.ModOptions:create(id)
        local options={dict={}}
        records[id]=options
        function options:getOption(key) return self.dict[key] end
        function options:addDescription() end
        function options:addSlider(key,_,_,_,_,value) self.dict[key]={value=value};return self.dict[key] end
        function options:addTickBox(key,_,value) self.dict[key]={value=value};return self.dict[key] end
        options.addKeyBind=options.addTickBox
        function options:addComboBox(key, name, tooltip)
            local option={id=key,name=name,tooltip=tooltip,values={},selected=1}
            function option:addItem(label) self.values[#self.values+1]=label end
            function option:getValue() return self.selected end
            function option:setValue(value) self.selected=value end
            self.dict[key]=option
            return option
        end
        return options
    end
end
package.loaded["PZAPI/ModOptions"]=true
local Options=require "AutoMindful/Options"
local modes=PZAPI.ModOptions:getOptions("AutoMindful")
local groups={
    {"recovery","Recovery / relief"},
    {"capped","Capped practice"},
    {"rotation","Train Both"},
}
local function rows(kind)
    if kind=="meditation" then
        return "MindfulnessTier","Mindfulness", {"No minimum","Mindfulness (level 3)","Strong Mindfulness (level 6)","Perfect Mindfulness (level 10)"}
    end
    return "YogaZenTier","Yoga Zen", {"No minimum","Zen I (level 1)","Zen II (level 3)","Zen III (level 3)","Zen IV (level 6)"}
end
for _, group in ipairs(groups) do
    for _, kind in ipairs({"meditation","yoga"}) do
        local suffix, label, expected=rows(kind)
        local option=assert(modes:getOption(group[1]..suffix))
        assert(option.name == group[2] .. ": minimum " .. label)
        assert(option.tooltip:find("highest unlocked tier",1,true))
        assert(#option.values==#expected)
        for i,value in ipairs(expected) do assert(option.values[i]==value) end
        assert(Options.minimumTier(group[1],kind)==#expected-1)
    end
end
modes:getOption("recoveryMindfulnessTier"):setValue(3)
modes:getOption("cappedYogaZenTier"):setValue(2)
modes:getOption("cappedMindfulnessTier"):setValue(1)
modes:getOption("rotationYogaZenTier"):setValue(5)
assert(Options.minimumTier("recovery","meditation")==2 and Options.minimumTier("recovery","yoga")==4)
assert(Options.minimumTier("capped","meditation")==0 and Options.minimumTier("capped","yoga")==1)
assert(Options.minimumTier("rotation","meditation")==3 and Options.minimumTier("rotation","yoga")==4)
assert(Options.minimumTier("invalid","yoga")==0 and Options.minimumTier("rotation","invalid")==0)
if loadUpstream then
    PZAPI.ModOptions:save()
    local saved=table.concat(disk,"\n")
    assert(saved:find("combobox|AutoMindful|recoveryMindfulnessTier|3",1,true))
    assert(saved:find("combobox|AutoMindful|cappedYogaZenTier|2",1,true))
    assert(saved:find("combobox|AutoMindful|rotationYogaZenTier|5",1,true))
    modes:getOption("recoveryMindfulnessTier"):setValue(1)
    modes:getOption("cappedYogaZenTier"):setValue(1)
    modes:getOption("rotationYogaZenTier"):setValue(1)
    modes:getOption("cappedMindfulnessTier"):setValue(4)
    PZAPI.ModOptions:load()
    assert(Options.minimumTier("capped","meditation")==0, "an explicitly saved No minimum overrides the default")
    assert(Options.minimumTier("recovery","meditation")==2 and Options.minimumTier("capped","yoga")==1)
    assert(Options.minimumTier("rotation","yoga")==4)
    print("PASS installed stock Mod Options round-trip (in-memory, never writes player settings)")
end
for _, invalid in ipairs({false,0,-1,5.9,99,"missing",0/0,math.huge}) do
    modes:getOption("rotationYogaZenTier"):setValue(invalid)
    assert(Options.minimumTier("rotation","yoga")==0, "bad stored value must switch off")
end
print("PASS six separate native combo definitions, stable ordering and highest-tier defaults that preserve explicit No minimum")
