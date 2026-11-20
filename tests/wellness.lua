package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path

local locale = {
    IGUI_perks_Meditation_Description = "GENERIC <LINE> repeats every rank",
    UI_LSPerk_Meditation_3 = "o First tier <LINE><RED> o Worn bags can stay on <LINE> o First tier",
    UI_LSPerk_Meditation_10 = "o Master technique",
    UI_LSPerk_Meditation_10_mp = "o Teach meditation",
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
CharacterTrait={DISCIPLINED={}}
local data={MindfulnessMinutes=9, WasTaughtLast="Yoga", LSMoodles={
    MindfulState={Value=.4}, Zen={Value=.17,Level=1}, WasTaughtSkill={Value=.2},
}}
local reads=0
local player={
    hasModData=function() return true end,
    getModData=function() reads=reads+1;return data end,
    hasTrait=function(_,trait) assert(trait==CharacterTrait.DISCIPLINED);return true end,
}
local other={hasModData=function() return false end, getModData=function() error("Must not initialize player mod data") end}
local Info=require "AutoMindful/WellnessInfo"

local function guide(p, rank, yoga)
    local lines={}
    for _,section in ipairs(Info.guide(p,{meditation={level=rank},yoga={level=yoga}})) do
        lines[#lines+1]=section.title
        for _,line in ipairs(section.lines) do lines[#lines+1]=line end
    end
    return table.concat(lines,"\n")
end
local function has(text, literal) assert(text:find(literal,1,true), "Missing: "..literal.." in "..text) end
local function lacks(text, literal) assert(not text:find(literal,1,true), "Unexpected: "..literal.." in "..text) end

local text=guide(player,6)
has(text,"Rank 3 | Mindfulness");has(text,"Rank 6 | Localized Strong")
has(text,"Rank 10 | Perfect Mindfulness");has(text,"120 in-game min per tier")
has(text,"also reduces pain and hunger");has(text,"also restores general health")
has(text,"fade one tier at a time");has(text,"9 in-game min remaining in this tier")
has(text,"ten-minute in-game ticks");has(text,"no separate built-in countdown")
has(text,"Fitness and Nimble XP");has(text,"Zen is active")
has(text,"Yoga XP setting: x0.75");has(text,"Yoga lesson boost active")
data.MindfulnessMinutes=false;data.LSMoodles.MindfulState.Value=.6
has(guide(player,10),"Perfect Mindfulness | No current countdown available")
data.MindfulnessMinutes=9;data.LSMoodles.MindfulState.Value=.4
local localReads=reads
text=guide(other,6)
lacks(text,"Localized Strong |");lacks(text,"Zen is active")
assert(reads==localReads)
version="unknown"
text=guide(player,6)
has(text,"Exact effect and duration details are not verified")
lacks(text,"120 in-game");lacks(text,"Zen is active")
assert(reads==localReads)
version="0.4.0.3"
SandboxVars.Meditation.MindfulnessDuration=1
has(guide(player,6),"30 in-game min per tier")
SandboxVars.Meditation.MindfulnessDuration=false
has(guide(player,6),"At standard settings: 10-180 in-game min per tier")

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
local bar={perk=perk}
local a,b=class.updateTooltip(bar,2,"tag")
assert(a==7 and b=="tag" and calls==1)
assert(bar.message=="Rank 3 <LINE> Locked <LINE><LINE> - First tier <LINE> - Worn bags can stay on <LINE> - 10 in-game min per Mindfulness tier at standard settings <LINE> XP Boost: +75%")
class.updateTooltip(bar,6)
assert(bar.message=="Rank 7 <LINE> Locked <LINE><LINE> - 60 in-game min per Mindfulness tier (was 30) at standard settings <LINE> XP Boost: +75%")
mp=true
class.updateTooltip(bar,9)
has(bar.message,"- Master technique <LINE> - Teach meditation")
locale.IGUI_perks_Meditation_Description3="o Native per-rank note"
class.updateTooltip(bar,2)
has(bar.message,"- Native per-rank note");lacks(bar.message,"First tier")
bar.custom="Other provider owns this tooltip"
class.updateTooltip(bar,2)
assert(bar.message==bar.custom)
bar.custom="Foreign details <LINE><LINE> preserved <LINE><LINE> "..locale.IGUI_perks_Meditation_Description
class.updateTooltip(bar,2)
assert(bar.message==bar.custom)
bar.custom=nil
class.updateTooltip(bar,5)
has(bar.message,"Meditate while Mindfulness is active to reach Localized Strong")
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
has(details,"Completion bonus capped at 75 XP before multipliers (was 50)");has(details,"Yoga XP setting: x0.75")
details=Info.yogaTooltip(player,{capped=true},10)
has(details,"Stopping early no longer deducts Yoga XP or Zen");lacks(details,"XP setting");lacks(details,"lesson boost")
version="unknown"
details=Info.yogaTooltip(player,{capped=false},5)
lacks(details,"poses");lacks(details,"lesson boost")
-- Exact post-success duration only replaces known provider wording.
version="0.4.0.3"
local zenNotes={
    [1]={"Unlocked Zen state for a short time after performing yoga","20m to 30m"},
    [3]={"+ Zen state duration","2h 20m to 2h 30m"},
    [6]={"++ Zen state duration","4h 30m to 4h 40m"},
    [9]={"+++ Zen state duration","6h 30m to 6h 40m"},
}
for rank,row in pairs(zenNotes) do
    locale["UI_LSHS_Yoga_"..rank]="o "..row[1].." <LINE> o + pose sequence limit"
    local tip=Info.yogaTooltip(player,{capped=false},rank)
    has(tip,"Zen lasts about "..row[2].." in-game after successful Yoga started at this rank")
    lacks(tip,"- +")
end
has(guide(player,6,5),"Started at rank 5: about 2h 20m to 2h 30m in-game")
has(guide(player,6,10),"Started at rank 10: about 6h 30m to 6h 40m in-game")
lacks(guide(player,6,0),"Started at rank 0")
SandboxVars.Yoga.StrengthMultiplier=4
has(Info.yogaTooltip(player,{capped=false},6),"4h 30m to 4h 40m in-game")
locale.UI_LSHS_Yoga_6="o ++ Plus de concentration <LINE> o --- fatigue <LINE> o +++"
details=Info.yogaTooltip(player,{capped=false},6)
has(details,"Plus de concentration (further increase)")
has(details,"fatigue (stronger decrease)")
lacks(details,"- +")
lacks(details,"4h 30m")
version="unknown"
locale.UI_LSHS_Yoga_6="o +++ Zen state duration <LINE> o + pose sequence limit"
details=Info.yogaTooltip(player,{capped=false},6)
has(details,"Zen lasts longer")
has(details,"Each Yoga session targets more poses before it ends")
lacks(details,"4h 30m")
locale.UI_LSPerk_Meditation_2="o + action duration <LINE> o -- neck pain rate <LINE> o - boredom rate"
bar.perk=perk
class.updateTooltip(bar,1)
has(bar.message,"An uninterrupted meditation session can run longer");has(bar.message,"Meditation can add less neck pain when it causes any")
has(bar.message,"Meditation can add less boredom per effect tick");has(bar.message,"XP Boost: +75%")
lacks(bar.message,"- +");lacks(bar.message,"- --")
-- Real wording, no animation euphemisms or race claims; compare stock
-- uninterrupted action limits and actual world units only for a tier.
version="0.4.0.3";mp=true
bar.char=player
SandboxVars.Meditation.MindfulnessDuration=2
locale.UI_LSPerk_Meditation_4="o Unlocked new techniques <LINE> o -- neck pain rate <LINE> o ++ action duration <LINE> o -- boredom rate"
locale.UI_LSPerk_Meditation_8="o Unlocked new techniques"
locale.UI_LSPerk_Meditation_10="o Mastered the ultimate technique <LINE> o New Mindfulness level, improved state can be achieved by meditating while under the effects of the previous level <LINE> o ++++ action duration"
locale.UI_LSPerk_Meditation_10_mp="o Can teach meditation lessons"
class.updateTooltip(bar,1)
has(bar.message, "40% longer than at rank 1")
class.updateTooltip(bar,3)
has(bar.message, "about 186% longer than at rank 3")
has(bar.message, "28 in-game min per Mindfulness tier (was 20) with current settings")
has(bar.message, "Meditation can add less boredom per effect tick")
lacks(bar.message, "new techniques");lacks(bar.message,"- ++")
class.updateTooltip(bar,7)
has(bar.message, "about 67% longer than at rank 7")
class.updateTooltip(bar,9)
has(bar.message,"Meditate while Localized Strong is active to reach Perfect Mindfulness: also restores health")
has(bar.message,"50% longer than at rank 9")
has(bar.message,"Can teach Meditation to another survivor in multiplayer")
has(bar.message,"260 in-game min per Mindfulness tier (was 180) with current settings")
has(bar.message,"XP Boost: +75%")
locale.UI_LSHS_Yoga_6="o Unlocked advanced level poses <LINE> o + pose sequence limit <LINE> o ++ Zen state duration"
details=Info.yogaTooltip(player,{capped=false},6)
has(details, "Adds 7 advanced poses to the Yoga rotation")
has(details, "Targets 6 poses per session (was 4); linked poses can extend it")
has(details, "Successful poses ease more stress, pain and stiffness")
has(details, "Zen lasts about 4h 30m to 4h 40m in-game after successful Yoga started at this rank")
locale.UI_LSHS_Yoga_8="o +++ pose sequence limit"
details=Info.yogaTooltip(player,{capped=false},8)
has(details, "Targets 8 poses per session (was 6)")
has(details, "Even the hardest pose-fall roll cannot trigger")
assert(data.LSMoodles.MindfulState.Value==.4 and data.MindfulnessMinutes==9 and data.LSMoodles.WasTaughtSkill.Value==.2)
print("wellness: PASS (source notes, scoped native tooltip, per-tier minutes, safe owning player, unknown provider)")
