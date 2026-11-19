-- Native game medication policy only. No effects are applied by this module.
local PainCare = {}
local function number(v) return type(v) == "number" and v == v and v >= 0 and v < math.huge end
local function read(player)
    local ok, value = pcall(function()
        local stats = player:getStats()
        return {pain=stats:get(CharacterStat.PAIN), moodle=player:getMoodles():getMoodleLevel(MoodleType.PAIN),
            effect=player:getPainEffect(), delta=player:getPainDelta(),
            intox=stats:get(CharacterStat.INTOXICATION), sedative=player:getSleepingTabletEffect()}
    end)
    if not ok then return nil end
    for _, k in ipairs({"pain", "moodle", "effect", "delta", "intox", "sedative"}) do
        if type(value[k]) ~= "number" or value[k] ~= value[k] or math.abs(value[k]) == math.huge then return nil end
        if k == "effect" or k == "sedative" then value[k]=math.max(0,value[k]) end
        if value[k] < 0 then return nil end
    end
    return value
end
local function safe(v) return v and v.effect == 0 and v.delta == 0 and v.intox == 0 and v.sedative == 0 end
local function observer(state)
    state.painCare = state.painCare or {}
    return state.painCare
end
local function guard(player)
    local ok, md = pcall(function() return player:getModData() end)
    if not ok or type(md) ~= "table" then return nil end
    md.AutoMindfulPainCare = md.AutoMindfulPainCare or {attempted=false}
    if type(md.AutoMindfulPainCare) ~= "table" then return nil end
    return md.AutoMindfulPainCare
end
function PainCare.eligible(item)
    local ok, yes = pcall(function()
        if item:getFullType() ~= "Base.Pills" or not instanceof(item, "DrainableComboItem") then return false end
        local uses = item:getCurrentUses()
        return number(uses) and uses > 0 and uses == math.floor(uses)
            and math.abs(item:getUseDelta() - 0.1) < 0.000001
            and (not item:getOnEat() or item:getOnEat() == "")
            and not item:getRequireInHandOrInventory()
    end)
    return ok and yes == true
end
function PainCare.observe(player, state, now)
    local o, g, v = observer(state), guard(player), read(player)
    if not number(now) or not g or not v then o.last=nil; o.rises=0; o.ready=false; o.clearAt=nil; return false end
    if v.effect > 0 or v.delta > 0 then g.attempted=true end
    -- Rearming requires a newly observed clear period, never an old persisted timestamp.
    if g.attempted and v.pain <= 10 and v.moodle == 0 and safe(v) then
        if not o.last or now < o.last or now-o.last > 2000 then o.clearAt=now end
        o.clearAt=o.clearAt or now
        if now-o.clearAt >= 30000 then g.attempted=false; o.clearAt=nil end
    else o.clearAt=nil end
    if not safe(v) or v.pain <= 10 or v.moodle < 1 or not o.last or now < o.last or now-o.last > 2000
        or (o.pain and v.pain < o.pain) then
        o.rises=0; o.riseAt=nil; o.ready=false; o.sampleAt=now; o.samplePain=v.pain; o.lastRise=nil
    elseif now-(o.sampleAt or now) >= 1000 then
        if v.pain > o.samplePain then
            o.rises=(o.rises or 0)+1; o.lastRise=now
        end
        o.sampleAt=now; o.samplePain=v.pain
    end
    o.ready=(o.rises or 0) >= 2 and o.lastRise ~= nil and now-o.lastRise <= 8000
    o.last=now; o.pain=v.pain
    return o.ready and not g.attempted
end
function PainCare.wanted(player, state, now)
    local o, g, v = observer(state), guard(player), read(player)
    if not g or not v or not number(now) then return false end
    if not o.ready or not o.last or now < o.last or now-o.last > 2000
        or not o.lastRise or now-o.lastRise > 8000
        or v.pain <= 10 or v.moodle < 1 or v.pain < o.pain then return false end
    if g.attempted then return false, "Already attempted this pain episode" end
    if not safe(v) then return false, "Medication or intoxication already active" end
    local ok, blocked = pcall(function()
        return ISInventoryPaneContextMenu.getEatingMask(player, false)
    end)
    if not ok or type(ISInventoryPaneContextMenu.takePill) ~= "function" then
        return false, "Native medication action unavailable"
    end
    if blocked then return false, "Protective gear blocks taking pills" end
    return true
end
function PainCare.observeForeign(player, state, queue, now)
    local g = guard(player)
    if not g then return end
    for _, action in ipairs(queue or {}) do
        -- MP effects may arrive after the foreign animation ends. Any pill
        -- action is ambiguous until a newly observed clear episode, not just
        -- the painkiller type we are permitted to select ourselves.
        if action.Type == "ISTakePillAction" then
            local o=observer(state)
            o.clearAt=nil
            if action.autoMindfulOwner ~= state then g.attempted=true; o.ready=false end
        end
    end
end
function PainCare.queue(player, state, item, now)
    local wanted, reason = PainCare.wanted(player, state, now)
    if not wanted then return false, reason end
    if not PainCare.eligible(item) then return false, "Not a plain usable painkiller" end
    local ok, idle = pcall(function()
        local q=ISTimedActionQueue.getTimedActionQueue(player)
        return #q.queue == 0 and not player:hasTimedActions()
            and player:getCharacterActions():isEmpty()
            and not ISTimedActionQueue.isPlayerDoingAction(player)
            and player:getInventory():contains(item)
            and not ISInventoryPaneContextMenu.getEatingMask(player, false)
            and type(ISInventoryPaneContextMenu.takePill) == "function"
    end)
    if not ok or not idle then return false, "Busy, inaccessible pills, or blocking gear" end
    local v, g, o = read(player), guard(player), observer(state)
    if not v or not g then return false, "Pain state unavailable" end
    g.attempted=true -- before any call that could enqueue; survives Stop/start and exceptions.
    o.ready=false; o.receipt={effect=v.effect, delta=v.delta}
    local called = pcall(function() ISInventoryPaneContextMenu.takePill(item, player:getPlayerNum()) end)
    if not called then o.receipt=nil; return false, "Native pill request could not be confirmed" end
    return true
end
-- Caller invokes only after the owned action chain has ended. MP acknowledgement may lag.
function PainCare.receipt(player, state, now)
    local o=observer(state); local r=o.receipt
    if not r then return "unconfirmed", "No pending medication receipt" end
    local v=read(player)
    if v and (v.effect > r.effect or v.delta > r.delta) then
        o.receipt=nil; return "confirmed", "Native medication effect observed"
    end
    if not number(now) then o.receipt=nil; return "unconfirmed", "Clock unavailable" end
    r.endedAt=r.endedAt or now
    if now < r.endedAt or now-r.endedAt >= 8000 then
        o.receipt=nil; return "unconfirmed", "No native medication effect confirmed"
    end
    return "pending", "Waiting for native medication acknowledgement"
end
return PainCare
