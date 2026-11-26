-- Runtime-only, per-survivor explanations for the Log tab. The file log holds
-- the evidence; this holds what a player would want to read.
local Decisions = {}
local limit = 60
local labels = {
    starting="Checking needs and requirements", meditation="Meditating", yoga="Practicing Yoga",
    sleeping="Sleeping", resting="Resting", recovering="Waiting for recovery", ["recovery-idle"]="Monitoring needs",
    ["practice-care"]="Practicing for relief", reading="Reading for boredom", drinking="Drinking", eating="Eating",
    paincare="Managing pain", hygiene="Taking care of hygiene", restroom="Using the restroom",
    travelling="Walking for supplies or care", scouting="Checking supplies", returning="Returning borrowed supplies",
    transferring="Preparing a drink", preparing="Opening a supply", collecting="Collecting a supply",
    sitting="Sitting down", standing="Standing up", between="Leaving an opening for other actions",
    ["restoring-mask"]="Putting the mask back on", ["return-wait"]="Waiting to retry the way back", care="Taking a care break",
    resuming="Rechecking after a pause", stopped="Second Nature stopped", complete="Mode complete",
    ["current-action"]="Waiting for your current action", walking="Waiting for movement to settle",
    ["manual-input"]="Waiting for your controls to settle", ["recovery-danger"]="Careful: not safe here",
    ["inspection-open"]="Waiting for the map or dialog to close", interrupted="Checking an interrupted action",
    ["settling-action"]="Waiting for the previous action to settle",
    ["admission-retry"]="Lifestyle did not start the practice",
    ["yoga-gate"]="Lifestyle is blocking Yoga", ["meditation-gate"]="Lifestyle is blocking Meditation",
    ["water-unavailable"]="No safe water confirmed", ["food-unavailable"]="No safe food confirmed",
    ["water-restricted"]="The game is restricting drinking", ["food-restricted"]="The game is restricting eating",
    ["care-menu"]="Care paused for an open context menu", ["care-window"]="Care paused for an open game window",
    ["care-settle"]="Care is waiting for another action",
}

local liveDetails = {
    ["current-action"]="Second Nature will resume once it finishes.",
    walking="Second Nature will resume when movement stops.",
    ["inspection-open"]="Close the window to continue. Your mode stays on.",
    interrupted="Second Nature will check before trying the action again.",
    ["settling-action"]="Second Nature will resume when the queue is clear.",
    ["manual-input"]="It resumes when you are idle.",
    ["recovery-danger"]="The job stays on and continues when it is safe.",
    setback="It stays on and tries again in a while.",
}

local function nativeText(value)
    if type(value) ~= "string" then return nil end
    local text=value:gsub("%b<>"," "):gsub("[<>%c]"," "):gsub("%s+"," "):gsub("^ ",""):gsub(" $","")
    if #text > 216 then
        -- Bound history rows without cutting a translated UTF-8 character.
        local stop=216
        while stop>0 do
            local nextByte=text:byte(stop+1)
            if not nextByte or nextByte<128 or nextByte>=192 then break end
            stop=stop-1
        end
        text=text:sub(1,stop).."..."
    end
    if text~="" then return text end
end

local function clock()
    local time=getGameTime and getGameTime()
    local ok,text=pcall(function()
        local hours=time:getTimeOfDay()
        return string.format("%02d:%02d",math.floor(hours),math.floor(hours*60)%60)
    end)
    return ok and text or nil
end

local function record(state, code, reason)
    local label=labels[code]
    if not label then return end
    local log=state.decisionLog
    if not log then log={revision=0, entries={}}; state.decisionLog=log end
    local latest=log.entries[1]
    if latest and latest.code==code and latest.reason==reason then return end
    table.insert(log.entries,1,{code=code,label=label,reason=reason,clock=clock(),
        message=not reason and nativeText(state.message)~=label and nativeText(state.message) or nil})
    if #log.entries>limit then table.remove(log.entries) end
    log.revision=log.revision+1
end

function Decisions.note(state, code)
    record(state,code,nil)
end

-- Only the stock gate receipt can supply localized free text. Repeated
-- frame samples of the same phase/cause never allocate or copy history.
function Decisions.transition(state, phase, cause, nativeReason)
    local code=cause or phase
    if cause~="yoga-gate" and cause~="meditation-gate" then nativeReason=nil end
    if state.decisionCode==code and state.decisionNative==nativeReason then return end
    local reason=nativeText(nativeReason)
    state.decisionCode,state.decisionNative,state.decisionDetail=code,nativeReason,reason
    record(state,code,reason)
end

function Decisions.current(state)
    if state.careWait then return "care-settle", "Care is paused" end
    if state.phase=="manual" and state.yielding and state.idleSince then
        return "settling-action", labels["settling-action"], liveDetails["settling-action"]
    end
    local code=state.decisionCode
    return code,labels[code],state.decisionDetail or liveDetails[code]
end

function Decisions.revision(state)
    return state and state.decisionLog and state.decisionLog.revision or 0
end

function Decisions.snapshot(state)
    local result={}
    local log=state and state.decisionLog
    for i,entry in ipairs(log and log.entries or {}) do
        result[i]={code=entry.code,label=entry.label,reason=entry.reason,clock=entry.clock,message=entry.message}
    end
    return result
end

-- A read-only supply preview may know of ineligible stock too. Describe
-- only what was checked, never assert that the area has no water.
function Decisions.waterDetail(report)
    if not report then return "No safe water confirmed in checked supplies." end
    if (report.water or 0)>0 or (report.nearbyWater or 0)>0 then
        return "Known supplies were listed, but the check did not confirm a usable drink. Check access, collection settings, or a clean vessel."
    end
    if (report.unknownContainers or 0)>0 or (report.unloadedSquares or 0)>0 then
        return "No safe water confirmed. Some nearby contents are still unknown."
    end
    if report.radius then return "No safe water found in checked supplies." end
    return "No safe water confirmed in checked supplies."
end

return Decisions
