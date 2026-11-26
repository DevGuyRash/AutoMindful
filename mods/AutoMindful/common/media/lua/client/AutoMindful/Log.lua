-- One event per line: when, which job, what happened, why, and the state the
-- decision was made from. Everything goes to Zomboid/Lua/AutoMindful/log-N.txt;
-- console.txt only gets the few lines that matter without the file.
--
-- Reading a line:  12:04:33.218 w9d08:41 #142 job3 trip.outbound need=water ... | me=...
--   w = world day and clock, # = event number, job = session started by the player
local Snap = require "AutoMindful/Snapshot"

local Log = {}
local OFF, DECISIONS, EVERYTHING = 1, 2, 3
Log.levels = {off=OFF, decisions=DECISIONS, everything=EVERYTHING}

local slots, slotLimit = 5, 4*1024*1024
local windowMs, windowLines = 10000, 60
local flushMs, flushLines = 1000, 200
local heartbeatMs, valueLimit = 30000, 2000

local level = function() return EVERYTHING end
local buffer, sequence = {}, 0
local ring, ringLimit = {}, 200
local slot, written, opened, lastFlush, header
local rates, contexts = {}, {}

function Log.setLevelSource(source) level = source end

function Log.enabled(minimum)
    return (level() or EVERYTHING) >= (minimum or DECISIONS)
end

local function indexFile() return "AutoMindful/log-index.txt" end
function Log.fileName(number) return "AutoMindful/log-" .. tostring(number or slot or 1) .. ".txt" end

local function readSlot()
    if not getFileReader then return 0 end
    local ok, value = pcall(function()
        local reader = getFileReader(indexFile(), false)
        if not reader then return 0 end
        local line = reader:readLine()
        reader:close()
        return tonumber(line) or 0
    end)
    return ok and value or 0
end

local function write(name, text, append)
    if not getFileWriter then return false end
    local ok, done = pcall(function()
        local writer = getFileWriter(name, true, append)
        if not writer then return false end
        writer:write(text)
        writer:close()
        return true
    end)
    return ok and done == true
end

-- A new game session, or a full file, takes the oldest slot. Nothing grows
-- without a bound and a crash never loses the previous session's evidence.
local function rotate()
    slot = readSlot() % slots + 1
    written = 0
    write(indexFile(), tostring(slot) .. "\n", false)
    opened = write(Log.fileName(), (header or "") .. "\n", false)
end

local function clock()
    local now = getTimestampMs()
    local ok, text = pcall(function() return os.date("%H:%M:%S") end)
    return string.format("%s.%03d", ok and text or "--:--:--", now % 1000)
end

local function world()
    local time = getGameTime and getGameTime()
    if not time or not time.getWorldAgeHours then return "w?" end
    local ok, text = pcall(function()
        local hours = time:getTimeOfDay()
        return string.format("w%dd%02d:%02d", time:getNightsSurvived(), math.floor(hours), math.floor(hours * 60) % 60)
    end)
    return ok and text or "w?"
end

local function value(v)
    local kind = type(v)
    if kind == "number" then
        if v == math.floor(v) and math.abs(v) < 1e12 then return string.format("%d", v) end
        return (string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", ""))
    end
    local text = tostring(v)
    if #text > valueLimit then text = text:sub(1, valueLimit) .. "..." end
    text = text:gsub("[%c]+", " ")
    if text == "" or text:find("[%s=|\"]") then return '"' .. text:gsub('"', "'") .. '"' end
    return text
end

-- fields is an ordered list {"key", value, ...}; a nil value is skipped, so
-- callers can pass optional evidence without building the list conditionally.
local function encode(fields, count)
    local out = {}
    for index = 1, count, 2 do
        if fields[index + 1] ~= nil then out[#out + 1] = tostring(fields[index]) .. "=" .. value(fields[index + 1]) end
    end
    return table.concat(out, " ")
end

local function context(player)
    local key = player and player.getPlayerNum and player:getPlayerNum() or -1
    local entry = contexts[key]
    if not entry then entry = {jobs=0, slot=key}; contexts[key] = entry end
    return entry
end

function Log.beginJob(player)
    local entry = context(player)
    entry.jobs = entry.jobs + 1
    entry.job = entry.jobs
    return entry.job
end

function Log.endJob(player) context(player).job = nil end

function Log.flush()
    if #buffer == 0 then return end
    if not slot or written > slotLimit then rotate() end
    lastFlush = getTimestampMs()
    opened = opened or write(Log.fileName(), (header or "") .. "\n", false)
    local text = table.concat(buffer, "\n") .. "\n"
    if opened and write(Log.fileName(), text, true) then
        buffer = {}
        written = written + #text
        return
    end
    -- Keep what a passing failure would lose, within reason.
    while #buffer > flushLines * 2 do table.remove(buffer, 1) end
end

-- A runaway loop must be visible without becoming the log. Past the budget,
-- lines are counted and the count is reported when the window closes.
local function admitted(name, now)
    local rate = rates[name]
    if not rate or now < rate.at or now - rate.at >= windowMs then
        if rate and rate.dropped > 0 then
            sequence = sequence + 1
            buffer[#buffer + 1] = string.format("%s %s #%d log.suppressed event=%s lines=%d windowMs=%d",
                clock(), world(), sequence, name, rate.dropped, windowMs)
        end
        rate = {at=now, lines=0, dropped=0}
        rates[name] = rate
    end
    rate.lines = rate.lines + 1
    if rate.lines <= windowLines then return true end
    rate.dropped = rate.dropped + 1
    return false
end

local function emit(player, name, options, fields, count)
    local minimum = options.minimum or DECISIONS
    if not Log.enabled(minimum) then return end
    local now = getTimestampMs()
    if not admitted(name, now) then return end
    sequence = sequence + 1
    local entry = context(player)
    local body = name
    local encoded = encode(fields, count)
    if encoded ~= "" then body = body .. " " .. encoded end
    if options.me and player then
        -- Several events can describe one instant. Say so instead of repeating it.
        local me = Snap.player(player)
        if entry.me == me and entry.meAt == now then body = body .. " | me=#" .. entry.meSequence
        else
            body = body .. " | me=" .. me
            entry.me, entry.meAt, entry.meSequence = me, now, sequence
        end
    end
    local line = string.format("%s %s #%d %sjob%s %s", clock(), world(), sequence, entry.slot > 0 and ("p" .. entry.slot .. " ") or "",
        tostring(entry.job or "-"), body)
    buffer[#buffer + 1] = line
    ring[#ring + 1] = {slot=entry.slot, line=line}
    if #ring > ringLimit then table.remove(ring, 1) end
    if options.console then print("[AutoMindful] " .. name .. (encoded ~= "" and (" " .. encoded) or "")) end
    if options.urgent or #buffer >= flushLines or not lastFlush or now < lastFlush or now - lastFlush >= flushMs then
        Log.flush()
    end
end

-- The four severities callers use. `me` means "attach the full survivor
-- state": the question a reader asks is always what the survivor was like.
function Log.event(player, name, ...) emit(player, name, {me=true}, {...}, select("#", ...)) end
function Log.detail(player, name, ...) emit(player, name, {minimum=EVERYTHING}, {...}, select("#", ...)) end
function Log.state(player, name, ...) emit(player, name, {minimum=EVERYTHING, me=true}, {...}, select("#", ...)) end
function Log.headline(player, name, ...) emit(player, name, {me=true, console=true, urgent=true}, {...}, select("#", ...)) end

-- Repeating the same decision is not news. Only a changed signature is
-- logged; the previous one reports how long it held and how often it recurred.
function Log.change(player, name, signature, ...)
    if not Log.enabled(DECISIONS) then return false end
    local entry = context(player)
    entry.last = entry.last or {}
    local now, previous = getTimestampMs(), entry.last[name]
    if previous and previous.signature == signature then
        previous.count = previous.count + 1
        return false
    end
    entry.last[name] = {signature=signature, at=now, count=1}
    local fields, count = {...}, select("#", ...)
    if previous then
        fields[count + 1], fields[count + 2] = "heldMs", now - previous.at
        fields[count + 3], fields[count + 4] = "evaluations", previous.count
        count = count + 4
    end
    emit(player, name, {me=true}, fields, count)
    return true
end

function Log.heartbeat(player, ...)
    if not Log.enabled(EVERYTHING) then return end
    local entry, now = context(player), getTimestampMs()
    if entry.beat and now >= entry.beat and now - entry.beat < heartbeatMs then return end
    entry.beat = now
    emit(player, "heartbeat", {minimum=EVERYTHING, me=true}, {...}, select("#", ...))
end

function Log.error(player, where, message, trace)
    print("[AutoMindful] ERROR in " .. tostring(where) .. ": " .. tostring(message))
    emit(player, "error", {me=true, urgent=true}, {"where", where, "message", message, "trace", trace}, 6)
end

-- This survivor's lines from this session, oldest first.
function Log.recent(player, count)
    local slotNumber, result = context(player).slot, {}
    for _, entry in ipairs(ring) do
        if entry.slot == slotNumber then result[#result + 1] = entry.line end
    end
    while #result > (count or 80) do table.remove(result, 1) end
    return result
end

function Log.start(version, lifestyle)
    Log.flush()
    header = string.format("Second Nature %s | Lifestyle %s | game %s | %s", tostring(version or "?"), tostring(lifestyle or "none"),
        getCore and getCore().getVersionNumber and tostring(getCore():getVersionNumber()) or "?",
        isClient and isClient() and "multiplayer client" or "singleplayer")
    contexts, rates, ring, slot = {}, {}, {}, nil
end

return Log
