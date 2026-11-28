package.path = "mods/SecondNature/common/media/lua/client/?.lua;" .. package.path

local locale = {
    IGUI_perks_Meditation_Description = "GENERIC <LINE> repeats every rank",
    UI_LSPerk_Meditation_3 = "o Unlocked Mindfulness state, achieved during long meditative sessions, can grant a variety of bonuses <LINE><RED> o Can meditate while wearing backpack and bags",
    UI_LSPerk_Meditation_10 = "o Mastered the ultimate technique",
    UI_LSPerk_Meditation_10_mp = "o Can teach meditation lessons",
    UI_LSHS_Yoga_3 = "o Intermediate note",
    Moodles_MindfulState_L2 = "Localized Strong",
}
function getTextOrNull(key) return locale[key] end
local mp=false
function isClient() return mp end
local version="0.4.0.3"
function getModInfoByID(id)
    assert(id=="LifestyleHobbies")
    return {getModVersion=function() return version end}
end
SandboxVars={Meditation={MindfulnessDuration=3},Yoga={YogaXPMultiplier=.75}}
CharacterTrait={DISCIPLINED={}, COUCHPOTATO={}}
local dayMinutes, disciplined, couch, instant=120,true,false,false
function getGameTime() return {getMinutesPerDay=function() return dayMinutes end} end
local data={MindfulnessMinutes=9, WasTaughtLast="Yoga", LSMoodles={
    MindfulState={Value=.4}, Zen={Value=.17,Level=1}, WasTaughtSkill={Value=.2},
}}
local reads=0
local player={
    hasModData=function() return true end,
    getModData=function() reads=reads+1;return data end,
    hasTrait=function(_,trait) return (trait==CharacterTrait.DISCIPLINED and disciplined) or (trait==CharacterTrait.COUCHPOTATO and couch) end,
    isTimedActionInstant=function() return instant end,
}
local other={hasModData=function() return false end, getModData=function() error("Must not initialize player mod data") end}
local Info=require "AutoMindful/WellnessInfo"

local function guide(p, rank, yoga)
    local lines={}
    for _,section in ipairs(Info.guide(p,{meditation={level=rank},yoga={level=yoga}})) do
        lines[#lines+1]=section.title
        if section.subtitle then lines[#lines+1]=section.subtitle end
        for _,line in ipairs(section.lines) do lines[#lines+1]=line end
    end
    return table.concat(lines,"\n")
end
local function has(text, literal) assert(text:find(literal,1,true), "Missing: "..literal.." in "..text) end
local function lacks(text, literal) assert(not text:find(literal,1,true), "Unexpected: "..literal.." in "..text) end
local function once(text, literal)
    local _, last=text:find(literal,1,true)
    assert(last and not text:find(literal,last+1,true), "Expected exactly one: "..literal.." in "..text)
end

local text=guide(player,6)
has(text,"Rank 3 | Mindfulness");has(text,"Rank 6 | Localized Strong")
has(text,"Rank 10 | Perfect Mindfulness");has(text,"Current duration: 2h00m in-game per tier at rank 6")
has(text,"Direct relief: Reduces stress");has(text,"can also ease unhappiness")
has(text,"Boredom above 30/100 blocks starting");has(text,"Autopilot makes room for normal rest");has(text,"does not directly refill endurance")
has(text,"Meditate with Mindfulness active");has(text,"also reduces pain and hunger, without adding calories or hydration")
has(text,"Meditate with Localized Strong active");has(text,"also restores general health")
has(text,"fade one tier at a time");has(text,"9m in-game left in this tier")
has(text,"every 10 in-game minutes");has(text,"no separate built-in countdown")
has(text,"Fitness and Nimble XP");has(text,"Active now: Zen tier 1 | Meditation XP x1.1 | Yoga pose XP factor +1")
has(text,"x1.1, x2.2, x3.3 or x4.4");has(text,"Zen tiers 1-4 add 1, 1, 2, 2 to the pose")
has(text,"already-loaded value, so extra workout XP is not guaranteed")
has(text,"Successful poses can award Yoga, Fitness and Nimble XP. This is not a general multiplier")
has(text,"Yoga XP setting: x0.75 (current sandbox");has(text,"Active now: Yoga lesson boost")
has(text,"Rates per in-game minute");has(text,"These are rates, not totals")
has(text,"Rank 3 | Mindfulness: Relief per in-game minute\nStress and nicotine withdrawal: -6 percentage points each")
has(text,"Rank 6 | Localized Strong: Relief per in-game minute\nStress and nicotine withdrawal: -11 percentage points each")
has(text,"Pain: -11 points on the 0-100 scale\nHunger: -0.88 percentage points")
has(text,"Rank 10 | Perfect Mindfulness: Relief per in-game minute\nStress and nicotine withdrawal: -17.5 percentage points each")
has(text,"Healing: +12 health points shared");has(text,"Active effects: Relief per in-game minute")
lacks(text, " pp ");lacks(text, "×");lacks(text, "−");lacks(text, "–")
disciplined=false
local standard=guide(player,6)
has(standard,"Stress and nicotine withdrawal: -5 percentage points each")
has(standard,"Pain: -9 points on the 0-100 scale\nHunger: -0.72 percentage points")
has(standard,"Pain: -15 points on the 0-100 scale\nHunger: -1.2 percentage points\nHealing: +8 health points")
SandboxVars.Meditation.EffectMultiplier=3; SandboxVars.Meditation.HealFactor=3
local custom=guide(player,6)
has(custom,"Stress and nicotine withdrawal: -18 percentage points each")
has(custom,"Pain: -18 points on the 0-100 scale\nHunger: -1.44 percentage points")
has(custom,"Pain: -30 points on the 0-100 scale\nHunger: -2.4 percentage points\nHealing: +12 health points")
SandboxVars.Meditation.EffectMultiplier=nil; SandboxVars.Meditation.HealFactor=nil; disciplined=true
local sections=Info.guide(player,{meditation={level=6},yoga={level=6}})
for i,title in ipairs({"Meditation","Mindfulness","Yoga","Zen","Lessons"}) do
    assert(sections[i].title==title and #sections[i].subtitle>0 and #sections[i].lines>0,"Keep five labeled, ordered guide cards")
    for _,line in ipairs(sections[i].lines) do assert(line:match("^[^:]+: "),"Unlabeled guide row: "..line) end
end
data.LSMoodles.Zen.Level=4
has(guide(player,6),"Active now: Zen tier 4 | Meditation XP x4.4 | Yoga pose XP factor +2")
data.LSMoodles.Zen.Level=1
data.MindfulnessMinutes=false;data.LSMoodles.MindfulState.Value=.6
has(guide(player,10),"Perfect Mindfulness | No current countdown available")
data.MindfulnessMinutes=9;data.LSMoodles.MindfulState.Value=.4
local localReads=reads
text=guide(other,6)
lacks(text,"Localized Strong |");lacks(text,"Active now: Zen")
assert(reads==localReads)
version="unknown"
text=guide(player,6)
has(text,"Exact effect and duration details are not verified")
lacks(text,"Current duration");lacks(text,"x4.4");lacks(text,"Active now: Zen")
assert(reads==localReads)
version="0.4.0.3"
SandboxVars.Meditation.MindfulnessDuration=1
has(guide(player,6),"30m in-game per tier")
SandboxVars.Meditation.MindfulnessDuration=false
has(guide(player,6),"Standard duration: 10m-3h00m in-game per tier")
SandboxVars.Text={DividerMeditationNew=false}; SandboxVars.Meditation.KeepBags=true
text=guide(player,6)
has(text,"Mindfulness mood effects are disabled");lacks(text,"Active now: Localized Strong");lacks(text,"Rates per in-game minute")
has(text,"Your settings keep worn bags on at all ranks")
SandboxVars.Text=nil; SandboxVars.Meditation.KeepBags=nil

local perk={getId=function() return "Meditation" end}
local foreign={getId=function() return "Cooking" end}
local class={}
local calls=0
function class.updateTooltip(bar, cell, reason)
    calls=calls+1
    if bar.custom then bar.message=bar.custom
    else
        local body=locale.IGUI_perks_Meditation_Description
        local rank=locale["IGUI_perks_Meditation_Description"..(cell+1)]
        bar.message="Rank "..(cell+1).." <LINE> Locked <LINE><LINE> "..body
            .. (rank and (" <LINE><LINE> "..rank) or "") .. " <LINE> XP Boost: +75%"
    end
    return 7, reason
end
local stockUpdateTooltip=class.updateTooltip
Info.installMeditationTooltip(class)
local first=class.updateTooltip
Info.installMeditationTooltip(class)
assert(first==class.updateTooltip)
local bar={perk=perk,char=player}
local a,b=class.updateTooltip(bar,2,"tag")
assert(a==7 and b=="tag" and calls==1)
has(bar.message,"Rank 3 <LINE> Locked <LINE><LINE> - Unlocks Mindfulness: eases stress, panic and nicotine withdrawal")
has(bar.message,"Mindfulness duration: locked to 20m in-game per tier (default setting)")
once(bar.message,"Worn bags")
has(bar.message," <LINE> XP Boost: +75%")
class.updateTooltip(bar,6)
has(bar.message,"Mindfulness duration: 1h00m to 1h30m in-game per tier (default setting)")
mp=true
class.updateTooltip(bar,9)
once(bar.message,"Can teach Meditation to another survivor in multiplayer")
lacks(bar.message,"ultimate technique")
locale.IGUI_perks_Meditation_Description3="o Native per-rank note"
class.updateTooltip(bar,2)
has(bar.message,"- Native per-rank note");once(bar.message,"Unlocks Mindfulness")
bar.custom="Other provider owns this tooltip"
class.updateTooltip(bar,2)
assert(bar.message==bar.custom)
bar.custom="Foreign details <LINE><LINE> preserved <LINE><LINE> "..locale.IGUI_perks_Meditation_Description
class.updateTooltip(bar,2)
assert(bar.message==bar.custom)
bar.custom=nil
class.updateTooltip(bar,5)
has(bar.message,"Unlocks Localized Strong: meditate with Mindfulness active; also eases pain and hunger")
version="unverified";class.updateTooltip(bar,5)
has(bar.message,"GENERIC <LINE> repeats every rank")
version="0.4.0.3"
bar.perk=foreign
class.updateTooltip(bar,2)
has(bar.message,"GENERIC <LINE> repeats every rank")


-- A foreign wrapper can add a title percentage and a trailing note either
-- before or after ours. Stock-derived compaction must leave both alone.
for _, oursFirst in ipairs({true,false}) do
    local mixed={updateTooltip=stockUpdateTooltip}
    local function installForeign()
        local prior=mixed.updateTooltip
        mixed.updateTooltip=function(row, cell, ...)
            local function finish(...)
                row.message=row.message:gsub("^Rank (%d+)", "Rank %1 (effective 75%%)")
                    .. " <LINE> Other provider note"
                return ...
            end
            return finish(prior(row,cell,...))
        end
    end
    if oursFirst then Info.installMeditationTooltip(mixed) else installForeign() end
    if oursFirst then installForeign() else Info.installMeditationTooltip(mixed) end
    local row={perk=perk}
    mixed.updateTooltip(row,2)
    has(row.message,"Rank 3 (effective 75%)")
    has(row.message,"- Native per-rank note")
    has(row.message,"XP Boost: +75% <LINE> Other provider note")
    lacks(row.message,"GENERIC")
end

local details=Info.yogaTooltip(player,{capped=false},5)
has(details,"Completion bonus cap: 50 to 75 base XP");has(details,"Yoga XP setting: x0.75")
details=Info.yogaTooltip(player,{capped=true},10)
has(details,"Early-stop penalty: Yoga XP and Zen deductions to none")
has(details,"Completion bonus cap: 250 to 50 base XP (Fitness/Nimble only at rank 10)")
once(details,"Can teach Yoga to another survivor in multiplayer");lacks(details,"XP setting");lacks(details,"lesson boost")
version="unknown"
details=Info.yogaTooltip(player,{capped=false},5)
lacks(details,"poses");lacks(details,"lesson boost")
-- Exact post-success duration only replaces known provider wording.
version="0.4.0.3"
local zenNotes={
    [1]={"Unlocked Zen state for a short time after performing yoga","locked to 20m-30m"},
    [3]={"+ Zen state duration","20m-30m to 2h20m-2h30m"},
    [6]={"++ Zen state duration","2h20m-2h30m to 4h30m-4h40m"},
    [9]={"+++ Zen state duration","4h30m-4h40m to 6h30m-6h40m"},
}
for rank,row in pairs(zenNotes) do
    locale["UI_LSHS_Yoga_"..rank]="o "..row[1].." <LINE> o + pose sequence limit"
    local tip=Info.yogaTooltip(player,{capped=false},rank)
    has(tip,"Zen duration: "..row[2].." in-game")
    once(tip,"Zen duration")
    lacks(tip,"- +")
end
has(guide(player,6,5),"Started at rank 5: about 2h 20m to 2h 30m in-game")
has(guide(player,6,10),"Started at rank 10: about 6h 30m to 6h 40m in-game")
lacks(guide(player,6,0),"Started at rank 0")
SandboxVars.Yoga.StrengthMultiplier=4
details=Info.yogaTooltip(player,{capped=false},6)
has(details,"4h30m-4h40m in-game")
has(details,"Relief per pose (no aids): stress 2% to 3%, pain 30 to 45, stiffness 12 to 18")
locale.UI_LSHS_Yoga_6="o ++ Plus de concentration <LINE> o --- fatigue <LINE> o +++"
details=Info.yogaTooltip(player,{capped=false},6)
has(details,"Plus de concentration (further increase)")
has(details,"fatigue (stronger decrease)")
lacks(details,"- +")
has(details,"4h30m-4h40m")
version="unknown"
locale.UI_LSHS_Yoga_6="o +++ Zen state duration <LINE> o + pose sequence limit"
details=Info.yogaTooltip(player,{capped=false},6)
has(details,"Zen lasts longer")
has(details,"Each Yoga session targets more poses before it ends")
lacks(details,"4h30m");lacks(details,"base XP")
locale.UI_LSPerk_Meditation_2="o + action duration <LINE> o -- neck pain rate <LINE> o - boredom rate"
bar.perk=perk
class.updateTooltip(bar,1)
has(bar.message,"An uninterrupted meditation session can run longer");has(bar.message,"Meditation can add less neck pain when it causes any")
has(bar.message,"Meditation can add less boredom per effect tick");has(bar.message,"XP Boost: +75%")
lacks(bar.message,"- +");lacks(bar.message,"- --")
-- Real stock action units and a distinct in-game buff duration; the
-- day length affects session time, not the selected tier's game minutes.
version="0.4.0.3";mp=true
bar.char=player
SandboxVars.Meditation.MindfulnessDuration=2
locale.UI_LSPerk_Meditation_4="o Unlocked new techniques <LINE> o -- neck pain rate <LINE> o ++ action duration <LINE> o -- boredom rate"
locale.UI_LSPerk_Meditation_8="o Unlocked new techniques"
locale.UI_LSPerk_Meditation_10="o Mastered the ultimate technique <LINE> o New Mindfulness level, improved state can be achieved by meditating while under the effects of the previous level <LINE> o ++++ action duration"
locale.UI_LSPerk_Meditation_10_mp="o Can teach meditation lessons"
class.updateTooltip(bar,1)
has(bar.message, "Base session limit (approx): 8m to 12m in-game")
has(bar.message, "Early stress relief (boredom at most 5): 3.63% to 3.75% per tick")
class.updateTooltip(bar,3)
has(bar.message, "Base session limit (approx): 12m to 33m in-game")
has(bar.message, "Mindfulness duration: 20m to 28m in-game per tier")
has(bar.message, "Mindfulness stress/panic relief: 6 to 9 points per in-game minute")
lacks(bar.message, "new techniques");lacks(bar.message,"- ++")
class.updateTooltip(bar,7)
has(bar.message, "Base session limit (approx): 50m to 1h23m in-game")
class.updateTooltip(bar,9)
has(bar.message,"Unlocks Perfect Mindfulness: meditate with Localized Strong active; also restores health")
has(bar.message,"Base session limit (approx): 1h23m to 2h05m in-game")
once(bar.message,"Can teach Meditation to another survivor in multiplayer")
has(bar.message,"Mindfulness duration: 3h00m to 4h20m in-game per tier")
has(bar.message,"XP Boost: +75%")
assert(bar.message:sub(-#" <LINE> XP Boost: +75%") == " <LINE> XP Boost: +75%")
dayMinutes=60
class.updateTooltip(bar,5)
has(bar.message,"Base session limit (approx): 1h07m to 1h40m in-game")
has(bar.message,"Mindfulness duration: 40m to 1h00m in-game per tier")
has(bar.message,"Strong relief per in-game minute: pain 0 to 11, hunger 0% to 0.88%")
disciplined=false; SandboxVars.Meditation.MindfulnessDuration=1; SandboxVars.Meditation.EffectMultiplier=3
class.updateTooltip(bar,5)
has(bar.message,"Mindfulness duration: 10m to 15m in-game per tier")
has(bar.message,"Strong relief per in-game minute: pain 0 to 18, hunger 0% to 1.44%")
dayMinutes=nil
class.updateTooltip(bar,5)
has(bar.message,"Base session limit: 8000 to 12000 action ticks")
instant=true
class.updateTooltip(bar,5)
lacks(bar.message,"Base session limit")
instant=false
SandboxVars.Text={DividerMeditationNew=false}
SandboxVars.Meditation.KeepBags=true
class.updateTooltip(bar,2)
lacks(bar.message,"Mindfulness duration");lacks(bar.message,"Unlocks Mindfulness");lacks(bar.message,"Worn bags")
has(bar.message,"Early stress relief")
SandboxVars.Text.DividerMeditationNew=true
SandboxVars.Meditation.KeepBags=false
mp=false
class.updateTooltip(bar,9)
lacks(bar.message,"Can teach")
locale.UI_LSHS_Yoga_6="o Unlocked advanced level poses <LINE> o + pose sequence limit <LINE> o ++ Zen state duration"
details=Info.yogaTooltip(player,{capped=false},6)
has(details, "Pose pool: 22 to 29 (+7 Advanced)")
has(details, "Pose target per session: 4 to 6")
has(details, "Completion bonus cap: 75 to 100 base XP")
has(details, "Zen duration: 2h20m-2h30m to 4h30m-4h40m in-game")
once(details,"Pose pool");once(details,"Zen duration");once(details,"Completion bonus cap")
SandboxVars.Yoga.FailChance=6
details=Info.yogaTooltip(player,{capped=false},7)
has(details, "Max fall chance per roll: 20% to 0% (new sessions: zero on every setting)")
SandboxVars.Yoga.FailChance=1
details=Info.yogaTooltip(player,{capped=false},2)
has(details, "Max fall chance per roll: 45% to 25%") -- stock `false or 1` fallback
locale.UI_LSHS_Yoga_8="o +++ pose sequence limit"
details=Info.yogaTooltip(player,{capped=false},8)
has(details, "Pose target per session: 6 to 8")
has(details, "Completion bonus cap: 150 to 200 base XP")
for rank=1,10 do
    class.updateTooltip(bar,rank-1)
    has(bar.message," to ");has(bar.message,"XP Boost: +75%")
    has(Info.yogaTooltip(player,{capped=false},rank)," to ")
end
assert(data.LSMoodles.MindfulState.Value==.4 and data.MindfulnessMinutes==9 and data.LSMoodles.WasTaughtSkill.Value==.2)
SandboxVars.Text={DividerMeditationNew=false}
assert(not Info.activeStrong(player), "Server-disabled Mindfulness is not care")
SandboxVars.Text.DividerMeditationNew=true
assert(Info.activeStrong(player) and not Info.activeStrong(other))
data.LSMoodles.MindfulState.Value=.2
assert(not Info.activeStrong(player), "Ordinary Mindfulness cannot relieve pain or hunger")
data.LSMoodles.MindfulState.Value=.6
data.MindfulnessMinutes=0
assert(Info.activeStrong(player), "Expiry and effects are separate; do not infer receipt from a timer")
version="unknown"
assert(not Info.activeStrong(player), "Keep optional care off under an unknown provider")
print("wellness: PASS (paired ranks, scoped stock XP, world time, live settings/traits, native dedupe, unknown provider)")
