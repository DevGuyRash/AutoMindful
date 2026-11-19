package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
local moduleName = "AutoMindful/CompletionHUD"
-- Observe only screen output and event registrations. No window/input API is mocked.
local now, width, sm = 1000, 640, 16
local players = {[0]={}, [1]={}}
local drawn, blocks, strokes, handlers = {}, {}, {}, {}
Events = {}
for _, name in ipairs({"OnPostUIDraw", "OnGameStart", "OnDisconnect"}) do
    local key = name
    Events[key] = {Add=function(fn)
        assert(not handlers[key], "duplicate event subscription: " .. key)
        handlers[key] = fn
    end}
end
UIFont = {Small=1, Medium=2}
function getSpecificPlayer(n) return players[n] end
function getTimestampMs() return now end
function getPlayerScreenLeft(n) return n * width end
function getPlayerScreenTop() return 50 end
function getPlayerScreenWidth() return width end
function getPlayerScreenHeight() return 460 end
local tm = {}
function tm:getFontHeight(f) return f == UIFont.Medium and sm + 6 or sm end
function tm:MeasureStringX(f, s) return #s * (f == UIFont.Small and 7 or 9) end
function tm:DrawString(f,x,y,s,r,g,b,a)
    drawn[#drawn+1] = {font=f,x=x,y=y,text=s,alpha=a}
end
local sr = {}
function sr:renderRect(x,y,w,h,r,g,b,a)
    assert(w >= 0 and h >= 0 and a >= 0 and a <= 1)
    blocks[#blocks+1] = {x=x,y=y,w=w,h=h,r=r,g=g,b=b,a=a}
end
function sr:renderline(_,x,y,x2,y2,r,g,b,a,t)
    assert(a >= 0 and a <= 1 and t > 0)
    strokes[#strokes+1] = {x=x,y=y,x2=x2,y2=y2,r=r,g=g,b=b,a=a}
end
function getTextManager() return tm end
function getRenderer() return sr end

local hud = require(moduleName)
assert(PZActionCompletionHUD == hud)
package.loaded[moduleName] = nil
assert(require(moduleName) == hud, "loading a second bundled copy must reuse the same queue")
assert(hud.duration(384.9) == "6m 24s" and hud.duration(18) == "18s")
assert(hud.duration(-1) == "0s" and hud.duration(3720) == "1h 2m")
local function paint(ms)
    now, drawn, blocks, strokes = ms, {}, {}, {}
    handlers.OnPostUIDraw()
end
local function card(brand,title,detail,status,note)
    return {brand=brand,theme=brand == "LOOTBOX" and "loot" or "mindful",title=title,detail=detail,status=status,note=note}
end
local function find(name)
    for _, line in ipairs(drawn) do if line.text == name then return line end end
end
hud.show(0,card("LOOTBOX","Loot run complete","12 items moved"))
hud.show(0,card("AUTOMINDFUL","Meditation session complete","6m 24s"))
paint(1150)
assert(find("LOOTBOX") and find("Loot run complete").alpha == 1 and find("12 items moved"))
assert(not find("AUTOMINDFUL") and #strokes == 2)
local fullBar = blocks[#blocks].w
paint(3000)
assert(blocks[#blocks].w < fullBar and find("12 items moved").alpha == 1)
paint(4750)
assert(find("12 items moved").alpha > 0 and find("12 items moved").alpha < 1)
paint(5000); paint(5160)
assert(not find("LOOTBOX") and find("Meditation session complete").alpha == 1 and #strokes > 2)
hud.show(1,card("LOOTBOX","Loot run cancelled","0 items moved","stopped","Cancelled by you."))
paint(5320)
assert(find("AUTOMINDFUL").x < width and find("Cancelled by you.").x >= width)
assert(find("Cancelled by you.").y + sm <= 510)
print("PASS: per-survivor FIFO, distinct badges, four-second clock, meter and fade")
-- Exercise wrap on a resized split viewport and at a larger font size.
width, sm = 285, 21
paint(5350)
for _, line in ipairs(drawn) do
    local right = line.x < width and width or 2*width
    assert(line.x + tm:MeasureStringX(line.font, line.text) <= right)
    assert(line.y >= 50 and line.y + tm:getFontHeight(line.font) <= 510)
end
for _, rect in ipairs(blocks) do assert(rect.x >= 0 and rect.x+rect.w <= 2*width) end
players[1] = {}
paint(5400)
assert(not find("LOOTBOX"), "a replacement survivor must not inherit the previous card")
paint(9001)
assert(#drawn == 0 and #blocks == 0)
hud.show(0,card("LOOTBOX","Other job",""))
handlers.OnDisconnect(); paint(9020); assert(#drawn == 0)
hud.show(0,card("AUTOMINDFUL","Other session",""))
handlers.OnGameStart(); paint(9050); assert(#drawn == 0)
hud.show(3,card("LOOTBOX","Missing player",""))
paint(9110); assert(#drawn == 0)
print("PASS: resizes, dead slot cleanup, reconnect/world reset and click-through with no UI element")

-- Stop is a filled square, not a font glyph or a one-pixel horizontal stroke.
players[0]={}; width=640
for _,fontSize in ipairs({16,21}) do
    sm=fontSize
    for _,brand in ipairs({"AUTOMINDFUL","LOOTBOX"}) do
        handlers.OnGameStart()
        hud.show(0,card(brand,"Session stopped","7m 56s | +91 Meditation XP","stopped"))
        paint(now+160)
        assert(find("7m 56s | +91 Meditation XP") and #strokes==0)
        local badge,mark=blocks[5],blocks[6]
        assert(badge and mark and badge.w==badge.h)
        assert(mark.w==mark.h and mark.w>=6 and mark.w<badge.w)
        assert(math.abs(mark.x+mark.w/2-(badge.x+badge.w/2))<=0.5)
        assert(math.abs(mark.y+mark.h/2-(badge.y+badge.h/2))<=0.5)
        assert(mark.a==1 and mark.r>badge.r and mark.g>badge.g and mark.b>badge.b)
    end
end
print("PASS: stopped cards use centered filled squares at both tested font scales and ASCII detail")
