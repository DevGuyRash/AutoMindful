-- Bundled by both standalone mods. They share a queue, not a dependency.
if PZActionCompletionHUD then return PZActionCompletionHUD end
local HUD = {}
PZActionCompletionHUD = HUD

local queues = {}
local lifetime = 4000
local floor, min, max = math.floor, math.min, math.max
local gold, sage = {0.92, 0.75, 0.43}, {0.67, 0.78, 0.60}
local ink, muted = {0.97, 0.96, 0.92}, {0.81, 0.84, 0.78}
local checkMark = {{-8,0,-3,5}, {-3,5,8,-7}}
local stopMark = {{-6,0,6,0}}
local mindfulMark = {{0,-10,0,-8}, {-3,-5,3,-5}, {3,-5,6,-2}, {6,-2,6,2},
    {6,2,3,5}, {3,5,-3,5}, {-3,5,-6,2}, {-6,2,-6,-2}, {-6,-2,-3,-5}, {-8,8,8,8}}

function HUD.duration(seconds)
    local n = max(0, floor(seconds))
    if n >= 3600 then return string.format("%dh %dm", floor(n / 3600), floor(n / 60) % 60) end
    if n >= 60 then return string.format("%dm %ds", floor(n / 60), n % 60) end
    return tostring(n) .. "s"
end

-- Keep whole words rather than slicing UTF-8 in the middle of an item or player name.
local function fit(text, manager, font, width, lines)
    if not text or text == "" then return {} end
    if manager:MeasureStringX(font, text) <= width then return {text} end
    local result, line = {}, ""
    for word in text:gmatch("%S+") do
        local joined = line == "" and word or line .. " " .. word
        if manager:MeasureStringX(font, joined) <= width then
            line = joined
        elseif #result + 1 == lines or line == "" then
            while line ~= "" and manager:MeasureStringX(font, line .. "...") > width do
                line = line:match("^(.*) %S+$") or ""
            end
            result[#result + 1] = line .. "..."
            return result
        else
            result[#result + 1] = line
            if manager:MeasureStringX(font, word) > width then
                result[#result + 1] = "..."
                return result
            end
            line = word
        end
    end
    if line ~= "" then result[#result + 1] = line end
    return result
end

local function layout(card, sw, sm, md, tm)
    local pad = max(8, floor(sm * 0.6))
    local width = min(sw - pad * 2, max(320, sm * 25))
    local badge = width >= 310 and sm * 2 or 0
    local inset = pad * 2 + badge + (badge > 0 and pad or 0)
    local room = width - inset - pad
    local title = fit(card.title, tm, UIFont.Medium, room, 2)
    local detail = fit(card.detail, tm, UIFont.Small, room, 2)
    local note = fit(card.note, tm, UIFont.Small, room, 2)
    return {sw=sw, sm=sm, md=md, pad=pad, width=width, inset=inset, badge=badge,
        title=title, detail=detail, note=note,
        height=pad * 2 + sm + #title * md + (#detail + #note) * sm + 8}
end

local function drawCard(num, card, age)
    local sw, sh = getPlayerScreenWidth(num), getPlayerScreenHeight(num)
    if sw < 160 or sh < 100 then return end
    local tm, sr = getTextManager(), getRenderer()
    local sm, md = tm:getFontHeight(UIFont.Small), tm:getFontHeight(UIFont.Medium)
    local l = card.layout
    if not l or sw ~= l.sw or sm ~= l.sm or md ~= l.md then
        l = layout(card, sw, sm, md, tm)
        card.layout = l
    end
    if l.height + l.pad * 2 > sh then return end
    local x = floor(getPlayerScreenLeft(num) + (sw - l.width) / 2)
    -- Clear the hotbar without drawing over the character in short split-screen viewports.
    local bottomPad = min(max(l.pad, floor(sh * 0.10)), sm * 5, sh - l.height - l.pad)
    local y = floor(getPlayerScreenTop(num) + sh - l.height - bottomPad)
    local a = min(1, age / 150, (lifetime - age) / 550)
    local color = card.theme == "mindful" and sage or gold
    local w, h = l.width, l.height
    sr:renderRect(x+2, y+3, w, h, 0.02, 0.03, 0.02, 0.48*a)
    sr:renderRect(x, y, w, h, 0.30, 0.34, 0.29, 0.96*a)
    sr:renderRect(x+1, y+1, w-2, h-2, 0.095, 0.11, 0.095, 0.98*a)
    sr:renderRect(x, y+4, 3, h-8, color[1], color[2], color[3], a)
    if l.badge > 0 then
        local size = l.badge
        local bx, by = x+l.pad+3, y+floor((h-size)/2)
        sr:renderRect(bx, by, size, size, 0.20, 0.24, 0.20, a)
        local lines = card.status == "stopped" and stopMark or (card.theme == "mindful" and mindfulMark or checkMark)
        local cx, cy, scale = bx + size/2, by + size/2, size/32
        for _, v in ipairs(lines) do
            sr:renderline(nil, floor(cx+v[1]*scale), floor(cy+v[2]*scale),
                floor(cx+v[3]*scale), floor(cy+v[4]*scale), color[1], color[2], color[3], a, max(2,scale*2))
        end
    end
    local tx, ty = x+l.inset, y+l.pad
    tm:DrawString(UIFont.Small, tx, ty, card.brand, color[1], color[2], color[3], a)
    ty = ty + sm + 2
    for _, line in ipairs(l.title) do
        tm:DrawString(UIFont.Medium, tx, ty, line, ink[1], ink[2], ink[3], a)
        ty = ty + md
    end
    ty = ty + 2
    for _, lines in ipairs({l.detail, l.note}) do
        for _, line in ipairs(lines) do
            tm:DrawString(UIFont.Small, tx, ty, line, muted[1], muted[2], muted[3], a)
            ty = ty + sm
        end
    end
    local bar = min(54, floor(w/5))
    sr:renderRect(x+w-l.pad-bar, y+h-5, bar, 2, 0.27, 0.30, 0.26, a)
    local remaining = floor(bar*(1-age/lifetime))
    if remaining > 0 then
        sr:renderRect(x+w-l.pad-bar, y+h-5, remaining, 2, color[1], color[2], color[3], a)
    end
end

local function draw()
    for num, queue in pairs(queues) do
        if getSpecificPlayer(num) ~= queue.player then
            queues[num] = nil
        else
            local now = getTimestampMs()
            if now - queue.start >= lifetime then
                table.remove(queue, 1)
                queue.start = now
            end
            if queue[1] then drawCard(num, queue[1], max(0, now - queue.start))
            else queues[num] = nil end
        end
    end
end

function HUD.show(num, card)
    if not Events or not Events.OnPostUIDraw then return end
    local player = getSpecificPlayer(num)
    if not player then return end
    local q = queues[num]
    if not q or q.player ~= player then
        q = {player=player, start=getTimestampMs()}
        queues[num] = q
    end
    q[#q + 1] = card
end

-- No UIManager element, focus, input handler or hit-test rectangle.
if Events and Events.OnPostUIDraw then Events.OnPostUIDraw.Add(draw) end
local function clear() queues = {} end
if Events and Events.OnGameStart then Events.OnGameStart.Add(clear) end
if Events and Events.OnDisconnect then Events.OnDisconnect.Add(clear) end
return HUD
