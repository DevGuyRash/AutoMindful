-- Reads native medication state only. The stock pill action owns every effect.
local PainCare = {}
local THRESHOLD, SAMPLE_GAP, WORN_OFF_MS, CLEAN_EPISODE_MS, ACK_MS = 10, 2000, 1000, 30000, 8000
local phases = {initial=true, submitted=true, active=true, wornOff=true, legacy=true, uncertain=true}

local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function number(v) return finite(v) and v >= 0 end
local function read(player)
    local ok, pain, effect, delta, intox, sedative = pcall(function()
        local stats = player:getStats()
        return stats:get(CharacterStat.PAIN), player:getPainEffect(), player:getPainDelta(),
            stats:get(CharacterStat.INTOXICATION), player:getSleepingTabletEffect()
    end)
    if not ok or not number(pain) or pain > 100 or not finite(effect) or not number(delta)
        or not number(intox) or not finite(sedative) then return nil end
    -- Stock decrements the timers past zero. The analgesic *delta* is
    -- separately zeroed; a positive residual still counts as active.
    return {pain=pain, effect=math.max(0,effect), delta=delta, intox=intox, sedative=math.max(0,sedative)}
end
local function effectActive(v) return v.effect > 0 or v.delta > 0 end
local function mixBlocked(v) return v.intox > 0 or v.sedative > 0 end
local function observer(state)
    state.painCare = state.painCare or {}
    return state.painCare
end
local function phase(g, value)
    g.phase = value
    -- Preserve the previous latch for rolling back to an older module.
    g.attempted = value ~= "initial"
end
local function guard(player)
    local ok, md = pcall(function() return player:getModData() end)
    if not ok or type(md) ~= "table" then return nil end
    if md.AutoMindfulPainCare == nil then md.AutoMindfulPainCare = {attempted=false} end
    local g = md.AutoMindfulPainCare
    if type(g) ~= "table" then return nil end
    if g.phase == nil then
        -- Old versions did not persist whether the attempt genuinely applied.
        phase(g, g.attempted == false and "initial" or g.attempted == true and "legacy" or "uncertain")
    end
    if phases[g.phase] then return g end
end

local function plainStock(item, fullType, useDelta)
    if item:getFullType() ~= fullType or not instanceof(item, "DrainableComboItem") then return false end
    local callback = item:getOnEat()
    return math.abs(item:getUseDelta() - useDelta) < 0.000001
        and (not callback or callback == "") and not item:getRequireInHandOrInventory()
end

function PainCare.eligible(item)
    local ok, yes = pcall(function()
        if not plainStock(item, "Base.Pills", 0.1) then return false end
        local uses = item:getCurrentUses()
        return number(uses) and uses > 0 and uses == math.floor(uses)
    end)
    return ok and yes == true
end

local function plainVitamins(item)
    -- B42 BodyDamage.JustTookPill changes fatigue (and common stress) for
    -- stock vitamins, not pain timers. A custom callback is not this case.
    local ok, yes = pcall(plainStock, item, "Base.PillsVitamins", 0.2)
    return ok and yes == true
end

local function witnessed(r, state)
    return r.action.autoMindfulOwner == state and r.action.autoMindfulFinished == true
        and not r.action.autoMindfulStopped
end

local function confirm(g, o, state, v, now)
    local r = o.receipt
    if not r or not witnessed(r, state) then return end
    r.endedAt = r.endedAt or now
    if g.phase == "submitted" and not o.foreignPill and v.effect > 0 and v.delta > 0
        and now >= r.endedAt and now-r.endedAt < ACK_MS then
        -- Normal completion alone proves nothing. Both native fields must
        -- reflect the stock effect after this exact admitted pill action.
        r.confirmed = true
        phase(g, "active")
    end
end

local function settleReceipt(g, o, state, v, now)
    local r = o.receipt
    if not r or not g then return "unconfirmed", "No pending medication receipt" end
    local function unknown(reason)
        if g.phase == "submitted" then phase(g, "uncertain") end
        o.receipt = nil
        return "unconfirmed", reason
    end
    if not number(now) then return unknown("Clock unavailable") end
    r.endedAt = r.endedAt or now
    if now < r.endedAt then return unknown("Clock changed during medication acknowledgement") end
    if v then confirm(g, o, state, v, now) end
    if r.confirmed then o.receipt=nil; return "confirmed", "Native medication effect observed" end
    if not witnessed(r, state) or now-r.endedAt >= ACK_MS then
        return unknown("No native medication effect confirmed; no automatic retry")
    end
    return "pending", "Waiting for native medication acknowledgement"
end

local function desire(g, o, v)
    if v.pain < THRESHOLD or (g.phase == "wornOff" and v.pain <= THRESHOLD) then return false end
    if effectActive(v) or mixBlocked(v) then return false, "Medication or intoxication already active" end
    if g.phase == "uncertain" or g.phase == "legacy" then
        return false, "Previous pills were unconfirmed; no automatic retry during this pain episode"
    end
    if g.phase == "submitted" or o.receipt then return false, "Waiting for native medication acknowledgement" end
    if g.phase == "active" then return false, "Checking that the previous Painkiller effect has worn off" end
    if o.pillInQueue then return false, "Another pill action is queued" end
    return g.phase == "initial" or g.phase == "wornOff"
end

function PainCare.observe(player, state, now)
    local o, g, v = observer(state), guard(player), read(player)
    if not number(now) or not g or not v then
        o.last, o.clearAt, o.cleanAt = nil, nil, nil
        if g and o.receipt and o.receipt.detached then settleReceipt(g, o, state, nil, now) end
        return false
    end
    if not o.last or now < o.last or now-o.last > SAMPLE_GAP then
        o.clearAt, o.cleanAt = nil, nil
    end
    o.last = now
    if g.phase == "submitted" and not o.receipt then
        -- Stop/restart discarded the exact local action. Do not retry blindly.
        phase(g, "uncertain")
    end
    if o.receipt and o.receipt.detached then
        settleReceipt(g, o, state, v, now)
    else
        confirm(g, o, state, v, now)
    end
    if (g.phase == "initial" or g.phase == "wornOff") and effectActive(v) then phase(g, "active") end
    -- A lone old latch is not proof of either consumption or expiry. Unlike a
    -- new uncertain dispatch, it may be rehabilitated by an actually observed
    -- positive native timer AND delta, and then the same verified wear-off.
    -- observeForeign runs first; an ambiguous pill must never rehabilitate it.
    if g.phase == "legacy" and not o.pillInQueue and v.effect > 0 and v.delta > 0 then phase(g, "active") end
    local clear = not effectActive(v) and not mixBlocked(v) and not o.pillInQueue
    if g.phase == "active" and clear then
        o.clearAt = o.clearAt or now
        if now-o.clearAt >= WORN_OFF_MS then phase(g, "wornOff"); o.clearAt=nil end
    else o.clearAt=nil end
    if (g.phase == "uncertain" or g.phase == "legacy" or g.phase == "wornOff")
        and not o.receipt and clear and v.pain < THRESHOLD then
        -- A distinctly new episode may use the inclusive initial threshold.
        -- Brief dips and a plateau at exactly 10 never rearm the initial rule.
        o.cleanAt = o.cleanAt or now
        if now-o.cleanAt >= CLEAN_EPISODE_MS then phase(g, "initial"); o.cleanAt=nil end
    else o.cleanAt=nil end
    return desire(g, o, v)
end

function PainCare.wanted(player, state, now)
    local o, g, v = observer(state), guard(player), read(player)
    if not g or not v or not number(now) or not o.last or now < o.last or now-o.last > SAMPLE_GAP then return false end
    local wanted, reason = desire(g, o, v)
    if not wanted then return false, reason end
    local ok, blocked = pcall(function() return ISInventoryPaneContextMenu.getEatingMask(player, false) end)
    if not ok or type(ISInventoryPaneContextMenu.takePill) ~= "function" then
        return false, "Native medication action unavailable"
    end
    if blocked then return false, "Protective gear blocks taking pills" end
    return true
end

function PainCare.observeForeign(player, state, queue, _now)
    local g, o = guard(player), observer(state)
    if not g then return end
    o.pillInQueue, o.foreignPill = false, false
    for _, action in ipairs(queue or {}) do
        if action.Type == "ISTakePillAction" then
            o.pillInQueue = true
            if action.autoMindfulOwner ~= state and not plainVitamins(action.item) then o.foreignPill = true end
        end
    end
    if o.pillInQueue then o.clearAt, o.cleanAt = nil, nil end
    if o.foreignPill then
        -- An unfamiliar pill or a delayed second action can be ambiguous on
        -- MP. No overlap or retry until a genuinely new pain episode.
        phase(g, "uncertain")
        o.receipt = nil
    end
end

function PainCare.queue(player, state, item, now)
    local wanted, reason = PainCare.wanted(player, state, now)
    if not wanted then return false, reason end
    if not PainCare.eligible(item) then return false, "Not a plain usable painkiller" end
    local ok, q = pcall(function()
        local queue = ISTimedActionQueue.getTimedActionQueue(player)
        if not queue.current and #queue.queue == 0 and not player:hasTimedActions()
            and player:getCharacterActions():isEmpty() and not ISTimedActionQueue.isPlayerDoingAction(player)
            and player:getInventory():contains(item) and not ISInventoryPaneContextMenu.getEatingMask(player, false)
            and type(ISInventoryPaneContextMenu.takePill) == "function" then return queue end
    end)
    if not ok or not q then return false, "Busy, inaccessible pills, or blocking gear" end
    local v, g, o = read(player), guard(player), observer(state)
    if not v or not g or not desire(g, o, v) then return false, "Pain state changed before native dispatch" end
    phase(g, "submitted") -- Latch before the possibly side-effecting native call.
    o.clearAt, o.cleanAt = nil, nil
    local called, action = pcall(function()
        ISInventoryPaneContextMenu.takePill(item, player:getPlayerNum())
        local found
        for _, candidate in ipairs(q.queue) do
            if candidate.Type == "ISTakePillAction" then
                if found or candidate.character ~= player or candidate.item ~= item then return nil end
                found = candidate
            end
        end
        return found
    end)
    if not called or not action then
        phase(g, "uncertain")
        return false, "Native pill request could not be confirmed"
    end
    o.receipt = {action=action}
    return true
end

-- Caller invokes only after the owned native chain has ended, not at animation
-- start or based on bottle use count. An MP effect may be replicated later.
function PainCare.receipt(player, state, now)
    return settleReceipt(guard(player), observer(state), state, read(player), now)
end

-- The scheduler has given up the care batch, not the exact dose witness.
-- Retire a terminal receipt now, or observe its remaining acknowledgement
-- window without delaying or touching the player's successor action.
function PainCare.detach(player, state, now)
    local o = state.painCare
    if not o or not o.receipt then return end
    o.receipt.detached = true
    settleReceipt(guard(player), o, state, read(player), now)
end

return PainCare
