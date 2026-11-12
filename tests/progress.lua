package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. (package.path or "")
local Progress = require "AutoMindful/Progress"

local perk = {}
local costs = {50,100,200,500,1000,2000,3000,4000,5000,6000}
function perk:getXpForLevel(level) return assert(costs[level]) end
function perk:getTotalXpForLevel(level)
    local total=0
    for index=1,level do total=total+costs[index] end
    return total
end
Perks = {Meditation=perk}
local character = {level=2,xp=175,yoga={3,175,750},data={}}
function character:getPerkLevel(value) assert(value==perk);return self.level end
function character:getXp() return {getXP=function(_,value) assert(value==perk);return self.xp end} end
function character:getModData() return self.data end
HiddenSkills = {getSkill=function(player,name) assert(name=="Yoga");return player.yoga end}

local passed=0
local function test(name,run) run();passed=passed+1;print("PASS "..name) end
test("meditation displays XP earned inside the current native threshold",function()
    local value=Progress.snapshot(character).meditation
    assert(value.level==2 and value.current==25 and value.required==200 and value.total==175 and value.fraction==0.125)
    assert(Progress.text(value)=="Level 2 / 10 - 25 / 200 XP (12.5%)")
end)
test("yoga uses the character's current hidden-skill requirement",function()
    local value=Progress.snapshot(character).yoga
    assert(value.level==3 and value.current==175 and value.required==750 and value.fraction==175/750)
    character.yoga={3,175,900}
    assert(Progress.snapshot(character).yoga.required==900,"Changed upstream thresholds must not need an addon update")
end)
test("XP changes remain signed across meditation and single yoga level transitions",function()
    assert(Progress.change({level=2,total=177},{level=3,total=352}).amount==175)
    assert(Progress.change({level=2,total=177},{level=2,total=174}).amount==-3)
    assert(Progress.change({level=0,current=95,required=100},{level=1,current=5,required=250}).amount==10)
    assert(not Progress.change(nil,{level=1,current=5,required=250}))
    assert(not Progress.change({level=1,current=5},{level=1,current=5}))
end)
test("unknown yoga crossings use level changes instead of guessed XP totals",function()
    local changed=Progress.change({level=0,current=95,required=100},{level=3,current=5,required=750})
    assert(changed.levels==3 and changed.amount==nil and changed.positive)
    changed=Progress.change({level=3,current=20,required=750},{level=1,current=0,required=250})
    assert(changed.levels==-2 and changed.amount==nil and not changed.positive)
end)
test("maximum levels do not expose stale yoga XP or another level target",function()
    character.level,character.xp,character.yoga=10,21850,{10,8995,9000}
    local values=Progress.snapshot(character)
    for _,value in pairs(values) do assert(value.capped and value.fraction==1 and value.current==0 and value.required==0) end
    assert(Progress.xpText(values.yoga)=="MAX")
    local changed=Progress.change({level=9,current=8995,required=9000},values.yoga)
    assert(changed.levels==1 and changed.amount==nil)
    assert(not Progress.change(values.yoga,values.yoga))
end)
test("missing optional skill metadata remains readable",function()
    Perks,HiddenSkills=nil,nil
    local values=Progress.snapshot(character)
    assert(not values.meditation and not values.yoga and Progress.xpText(nil)=="XP unavailable")
    for _ in pairs(Progress.snapshot(nil)) do error("No player must yield no progress entries") end
end)

if not loadUpstream and arg and arg[1] then
    local reference=arg[1]
    function loadUpstream(name) return assert(loadfile(reference.."/lua/"..name))() end
end
if loadUpstream then
    test("actual Lifestyle awards and losses match displayed yoga progress",function()
        local noop=function() end
        function getText(value) return value end
        function getSoundManager() return {playUISound=noop} end
        function isClient() return false end
        HaloTextHelper={addTextWithArrow=noop}
        loadUpstream("client/Helper/HSMng.lua")
        local player={data={}}
        function player:getModData() return self.data end
        local first=Progress.snapshot(player).yoga
        assert(first.level==0 and first.current==0 and first.required==100)
        HiddenSkills.addXP(player,"Yoga",95,true,false)
        local before=Progress.snapshot(player).yoga
        HiddenSkills.addXP(player,"Yoga",10,true,false)
        local after=Progress.snapshot(player).yoga
        assert(after.level==1 and after.current==5 and after.required==250)
        assert(Progress.change(before,after).amount==10)
        HiddenSkills.removeXP(player,"Yoga",3)
        local loss=Progress.snapshot(player).yoga
        assert(loss.current==2 and Progress.change(after,loss).amount==-3)
        HiddenSkills.setLevel(player,"Yoga",9)
        HiddenSkills.addXP(player,"Yoga",8995,true,false)
        before=Progress.snapshot(player).yoga
        HiddenSkills.addXP(player,"Yoga",10,true,false)
        after=Progress.snapshot(player).yoga
        assert(after.capped and after.current==0 and Progress.change(before,after).levels==1)
    end)
end
print("PROGRESS PASS "..passed.." cases; native metadata and XP receiver boundaries are explicit doubles")
