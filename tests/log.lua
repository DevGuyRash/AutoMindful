-- The log as a reader gets it: the file's own text after real scheduler runs.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T,C,Q=AutoMindfulTest,AutoMindfulTest.controller,ISTimedActionQueue
local Log=require "AutoMindful/Log"
local files,console={},{}
function getFileReader(name)
    if not files[name] then return nil end
    local text=files[name]
    return {readLine=function() return text:match("^[^\n]*") end,close=function() end}
end
function getFileWriter(name,_,append)
    if not append then files[name]="" end
    return {write=function(_,text) files[name]=(files[name] or "")..text end,close=function() end}
end
local realPrint=print
print=function(line) console[#console+1]=tostring(line) end
local function passed(text) realPrint("PASS "..text) end
local function queue(p) return Q.getTimedActionQueue(p).queue end
local function step(p,n) for _=1,n or 1 do T.now=T.now+250; C.update(p) end end
local function text() Log.flush(); return files[Log.fileName()] or "" end
local function need(pattern,...)
    local nearest
    for row in text():gmatch("[^\n]+") do
        if row:find(pattern) then
            local all=true
            for _,wanted in ipairs({...}) do if not row:find(wanted,1,true) then all=false end end
            if all then return row end
            nearest=row
        end
    end
    error("no "..pattern.." with "..table.concat({...}," ").."; nearest: "..tostring(nearest),2)
end

Log.start("9.9","0.4.0.3")
local p=T.playerNew(); p.sitting=true
p.values.THIRST,p.thirstMoodle=.3,1
local shelf=T.container(1,0); p.nearby={shelf}
local bottle=T.add(shelf,T.water())
assert(C.start(p,"meditation",true))
for _=1,30 do step(p); if queue(p)[1] and queue(p)[1].Type~="Meditation" then queue(p)[1]:perform() end end
need("^Second Nature 9%.9","Lifestyle 0.4.0.3")
need(" job%.start ","mode=meditation","collect=true","scout=","radius=","policy=","me=","thirst:0.3")
need(" phase ","from=starting","to=collecting","message=")
need(" supply%.choice%.water ","chosen=","utility=","candidates=1","nearby")
need(" loan%.borrow ","item=","from=")
need(" queue ","phase=drinking","actions=")
local done=need(" action%.done ","drink","needsAtStart=","needsNow=")
assert(done:find("thirst:0.3",1,true),"Before and after in one line")
need(" supply%.intake%-result ","thirstBefore=0.3","stat-improved")
need(" loan%.settled ")
need(" schedule ","mode=meditation","next=","yogaGate=","meditationGate=")
need(" heartbeat ","phase=","tally=","queue:[")
passed("one drink can be followed from the decision through the borrowed item to the measured relief")

local yieldTo=T.action(p,"SomeoneElsesWork")
Q.add(yieldTo); step(p,2); yieldTo:perform(); step(p,10)
need(" yield ","cause=current-action","SomeoneElsesWork")
need(" resume ","waitedMs=")
need(" action%.stopped ","Meditation","by=automindful-release","ranMs=")
C.stop(p,"You stopped Second Nature.")
need(" job%.stop ","reason=","tally=","yields:1")
passed("who interrupted, what it was doing, and how the job ended")

-- Nothing known, nothing found: say what was considered and why each failed.
local t=T.playerNew(); t.sitting=true; t.values.THIRST,t.thirstMoodle=.3,1
T.add(t.inventory,T.water()); t.refuseCare=true
assert(C.start(t,"meditation",false))
for _=1,40 do step(t); if queue(t)[1] and queue(t)[1].Type=="drink" then queue(t)[1]:perform() end end
assert(text():find("no%-relief%-last%-time"),"Say why the only bottle is not chosen again")
need(" care ","outcome=","waterLevel=1")
C.stop(t)
passed("an unused supply is logged with the reason it was passed over")

-- Refusals are events too.
ZenWellnessContextMenu.Options.Kept,ZenWellnessContextMenu.Options.Yoga=ZenWellnessContextMenu.Options.Yoga,nil
assert(not C.start(t,"yoga",false))
ZenWellnessContextMenu.Options.Yoga=ZenWellnessContextMenu.Options.Kept
need(" job%.refused ","mode=yoga","reason=")
passed("a job that would not start says why")

-- The console carries only what matters when there is no file to look at.
local noisy=0
for _,row in ipairs(console) do if row:find("[AutoMindful]",1,true) and not row:find("job.",1,true) then noisy=noisy+1 end end
assert(noisy==0,"Unexpected console chatter")
passed("console.txt gets job boundaries, not the running commentary")

-- A loop is visible without drowning the file.
local before=#text()
for _=1,500 do Log.event(p,"loop.test","n",1) end
T.now=T.now+11000
Log.event(p,"loop.test","n",2)
local body=text():sub(before+1)
local _,lines=body:gsub("loop%.test n=1","")
assert(lines==60 and body:find("log%.suppressed event=loop%.test lines=440"),lines)
passed("a runaway event is capped and counted")

-- Identical decisions are not repeated; the change reports how long it held.
before=#text()
for _=1,20 do T.now=T.now+100; Log.change(p,"same.test","a","v","a") end
Log.change(p,"same.test","b","v","b")
body=text():sub(before+1)
local _,repeats=body:gsub("same%.test","")
assert(repeats==2 and body:find("v=b heldMs=2000 evaluations=20") or body:find("v=b heldMs=1900 evaluations=20"),body)
passed("an unchanged decision is one line")

-- An item that cannot be returned is one line, not one per tick.
before=#text()
local holder=T.playerNew(); holder.sitting=true; holder.values.THIRST,holder.thirstMoodle=.3,1
local box=T.container(1,0); T.add(box,T.water()); holder.nearby={box}
assert(C.start(holder,"meditation",true))
for _=1,12 do step(holder); local head=queue(holder)[1]; if head and head.Type=="drink" then box.reject=true end; if head and head.Type~="Meditation" then head:perform() end end
assert(C.status(holder).pendingReturns==1)
C.stop(holder)
for _=1,200 do T.now=T.now+250; C.update(holder) end
body=text():sub(before+1)
local _,blocked=body:gsub(" loan%.blocked ","")
assert(blocked==1,blocked)
passed("a loan that cannot be returned is reported once")

-- Files rotate through a fixed set and a new session never overwrites the last.
local first=Log.fileName()
for session=1,7 do Log.start("9.9","x"); Log.event(p,"session.test","s",session); Log.flush() end
local names=0
for name in pairs(files) do if name:find("log%-%d") then names=names+1 end end
assert(names==5 and Log.fileName()~=first,names)
local full=Log.fileName()
local chunk=("z"):rep(2500)
for _=1,36 do
    for _=1,60 do Log.event(p,"big.test","x",chunk) end
    T.now=T.now+11000
    if Log.fileName()~=full then break end
end
Log.event(p,"after.test"); Log.flush()
assert(#files[full]>4*1024*1024 and #files[full]<5*1024*1024)
assert(Log.fileName()~=full and files[Log.fileName()]:find("after.test",1,true))
passed("five files, rotated by session and by size")

-- Off means off, and a missing file system never breaks a decision.
Log.setLevelSource(function() return Log.levels.off end)
local size=#text(); Log.event(p,"off.test"); Log.headline(p,"off.test"); assert(#text()==size)
Log.setLevelSource(function() return Log.levels.decisions end)
Log.event(p,"decision.test"); Log.detail(p,"detail.test"); Log.heartbeat(p)
assert(text():find("decision.test",1,true) and not text():find("detail.test",1,true))
Log.setLevelSource(function() return Log.levels.everything end)
getFileWriter=function() error("disk full") end
for _=1,3 do T.now=T.now+2000; Log.event(p,"failing.test") end
local broken={}
setmetatable(broken,{__index=function() return function() error("native refused") end end})
assert(type(require("AutoMindful/Snapshot").item(broken))=="string")
passed("levels are honored and a failing file or object never reaches the caller")

-- Two survivors, and two sessions, never end up in one report.
local two=T.playerNew(); function two:getPlayerNum() return 1 end
Log.start("9.9","x")
Log.event(p,"mine.test"); Log.event(two,"theirs.test")
local mine=table.concat(Log.recent(p,50),"\n")
assert(mine:find("mine.test",1,true) and not mine:find("theirs.test",1,true) and not mine:find("failing.test",1,true))
assert(table.concat(Log.recent(two,50)):find("p1 job- theirs.test",1,true))
-- A write that fails once loses nothing.
local working=getFileWriter
getFileWriter=function() error("busy") end
T.now=T.now+2000; Log.event(p,"kept.test"); Log.flush()
getFileWriter=function(name,_,append)
    if not append then files[name]="" end
    return {write=function(_,s) files[name]=(files[name] or "")..s end,close=function() end}
end
Log.flush()
assert(files[Log.fileName()]:find("kept.test",1,true))
passed("reports are per survivor and per session, and a passing write failure loses nothing")

-- An error carries enough to fix it.
getFileWriter=function(name,_,append)
    if not append then files[name]="" end
    return {write=function(_,s) files[name]=(files[name] or "")..s end,close=function() end}
end
Log.start("9.9","x")
Log.error(p,"Controller.update","attempted index of nil","at line 5")
need(" error ","where=Controller.update","attempted index of nil","trace=","me=")
passed("errors record where, what, the trace and the survivor")
print=realPrint
print("LOG PASS")
