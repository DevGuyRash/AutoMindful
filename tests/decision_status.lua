-- Product Controller integration with explicit game boundaries. Test the
-- published status/decision feed, not the controller's private state.
AutoMindfulContractHarnessOnly = true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly = nil
local T, C, Q = AutoMindfulTest, AutoMindfulTest.controller, ISTimedActionQueue
local function step(p, duration)
    T.now=T.now+(duration or 250)
    C.update(p)
end
local function advance(p,predicate)
    for _=1,20 do
        step(p)
        local status=C.status(p)
        if predicate(status) then return status end
    end
    error(C.status(p).message)
end
local function latest(p) return C.recentDecisions(p)[1] end

local p=T.playerNew(); p.sitting=true
assert(C.start(p,"meditation",false))
advance(p,function(s) return s.phase=="meditation" end)
local foreign=T.action(p,"NeverDisplayForeign_NameOrToken45")
Q.add(foreign)
local state=advance(p,function(s) return s.phase=="manual" end)
assert(state.decisionCode=="current-action" and state.decisionLabel=="Waiting for your current action",
    "Display the reason without guessing what a foreign action is")
assert(latest(p).code=="current-action" and not state.decisionLabel:find("NameOrToken",1,true))
local revision=state.decisionRevision
for _=1,48 do step(p) end
assert(C.status(p).decisionRevision==revision and latest(p).code=="current-action",
    "Repeated polls never record a new event for a stable wait")
assert(not foreign.stopped and not foreign.autoMindfulOwner and Q.getTimedActionQueue(p).queue[1]==foreign)
foreign:perform()
advance(p,function(s) return s.phase=="meditation" end)
assert(latest(p).code=="meditation")
print("PASS witnessed foreign wait is generic, deduplicated, and followed by resumed practice")

p.movementInput,p.moving=true,true
step(p)
assert(C.status(p).decisionCode=="walking")
local oldMap=ISWorldMap_instance
ISWorldMap_instance={playerNum=p:getPlayerNum(),isVisible=function() return true end}
p.movementInput,p.moving=false,false
step(p)
assert(C.status(p).decisionCode=="inspection-open", "A later observed inspection is the current cause, not stale movement")
ISWorldMap_instance=oldMap
step(p)
assert(C.status(p).decisionCode=="settling-action", "A closed panel is no longer described as open")
advance(p,function(s) return s.phase=="meditation" end)
print("PASS movement, inspection, and the quiet handoff report distinct verified causes")

local origText=getText
function getText(key)
    if key=="Tooltip_Action_Exhausted" then return "<RED> Fatigue : Yoga indisponible. <LINE>" end
    if key=="Tooltip_Yoga_MissingMat" then return "<RED> Tapis de yoga requis. " end
    return origText(key)
end
local tired=T.playerNew()
tired.values.ENDURANCE,tired.nativeYogaLimit=0.25,0.60
assert(C.start(tired,"yoga",false))
local gate=advance(tired,function(s) return s.phase=="resting" end)
assert(gate.decisionCode=="yoga-gate" and gate.decisionDetail=="Fatigue : Yoga indisponible.",
    "Show the actual localized admission failure, cleaned of UI markup")
assert(latest(tired).reason==gate.decisionDetail and latest(tired).code=="yoga-gate")
assert(C.status(p).phase=="meditation" and C.recentDecisions(p)[1].code=="meditation",
    "No survivor can read a different survivor's decisions")
local missingMat=T.playerNew()
missingMat.yogaBlocked=getText("Tooltip_Yoga_MissingMat")
assert(C.start(missingMat,"yoga",false))
local stopped=advance(missingMat,function(s) return s.phase=="stopped" end)
assert(stopped.decisionDetail=="Tapis de yoga requis." and latest(missingMat).reason==stopped.decisionDetail)
getText=origText
print("PASS blocked Yoga reports native localization for both temporary and terminal admission denials")

local thirsty=T.playerNew(); thirsty.sitting=true
thirsty.values.THIRST,thirsty.thirstMoodle=.6,4
assert(C.start(thirsty,"recovery",false))
local water=advance(thirsty,function(s) return s.phase=="recovering" end)
assert(water.decisionCode=="water-unavailable", "Expose the observed lack of usable water separately from other waits")
assert(latest(thirsty).label=="No safe water confirmed" and not latest(thirsty).reason)
local blocked=T.playerNew(); blocked.sitting=true
blocked.values.THIRST,blocked.thirstMoodle,blocked.foodMoodle=.6,4,3
assert(C.start(blocked,"recovery",false))
local restriction=advance(blocked,function(s) return s.phase=="recovering" end)
assert(restriction.decisionCode=="water-restricted", "The game's refusal is not a claim about available supplies")
print("PASS a watering restriction and no confirmed safe water remain different events")

local journal=T.playerNew(); journal.sitting=true
assert(C.start(journal,"meditation",false))
advance(journal,function(s) return s.phase=="meditation" end)
local bottle=T.add(journal.inventory,T.water({thirst=-.8}))
bottle.name="PrivateFixtureBottle_721"
journal.values.THIRST,journal.thirstMoodle=.53,4
advance(journal,function(s) return s.phase=="drinking" end)
assert(latest(journal).code=="drinking" and not latest(journal).label:find("PrivateFixture",1,true))
journal.thirstMoodle=0
local q=Q.getTimedActionQueue(journal).queue
q[1]:perform()
advance(journal,function(s) return s.phase=="meditation" end)
for _=1,8 do
    local other=T.action(journal,"SecretForeignHandle")
    Q.add(other)
    advance(journal,function(s) return s.phase=="manual" end)
    other:perform()
    advance(journal,function(s) return s.phase=="meditation" end)
end
local entries=C.recentDecisions(journal)
assert(#entries==6 and entries[1].code=="meditation")
for _,entry in ipairs(entries) do
    assert(not tostring(entry.reason):find("Secret",1,true) and not tostring(entry.label):find("Private",1,true))
end
entries[1].reason="external changed copy"
assert(latest(journal).reason~="external changed copy", "UI readback cannot mutate controller evidence")
C.stop(journal,"An item name that is private: do not store it")
assert(latest(journal).code=="stopped" and not latest(journal).reason)
assert(C.start(journal,"meditation",false) and latest(journal).code=="starting", "Keep bounded recent decisions on explicit restart for the same survivor")
assert(#C.recentDecisions(journal)==6 and #C.recentDecisions(T.playerNew())==0)
print("PASS newest six meaningful decisions survive stop/start only in this survivor's runtime")
