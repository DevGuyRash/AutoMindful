-- The same right-click menus over the game's unmodified ISContextMenu: option
-- pooling, submenu allocation per player and checkmarks are the stock code's.
if loadTest then loadTest("ui.lua") else assert(loadfile("tests/ui.lua"))() end
local path = "client/ISUI/ISContextMenu.lua"
if loadUpstream then loadUpstream(path) else assert(loadfile(assert(arg[1], "stock media directory required") .. "/lua/" .. path))() end
getCore().isTutorial = function() return false end
local core = getCore
function getCore() local c = core(); c.isTutorial = function() return false end; return c end
table.wipe = function(t) for k in pairs(t) do t[k] = nil end end
local function nop() end
local roots = {}
local function newMenu(player)
    local m = setmetatable({options={}, optionPool={}, numOptions=1, player=player or 0, instanceMap={}, subMenuPool={}, subOptionNums=0}, {__index=ISContextMenu})
    for _, key in ipairs({"instantiate", "addToUIManager", "setFontFromOption", "setForceCursorVisible", "bringToTop", "setVisible",
        "setY", "setX", "setHeight", "setWidth", "calcHeight", "initialise"}) do m[key] = nop end
    m.calcWidth = function() return 100 end
    return m
end
function getPlayerContextMenu(n) roots[n] = roots[n] or newMenu(n); return roots[n] end
function ISContextMenu:new() return newMenu() end
local WorldMenu = AutoMindful.WorldMenu
local function build(index, objects)
    local root, p = getPlayerContextMenu(index), getSpecificPlayer(index)
    root:clear()
    local wellness = root:addOption("Wellness", nil, nil)
    local menu = ISContextMenu:getNew(root)
    root:addSubMenu(wellness, menu)
    local yoga = ZenWellnessContextMenu.Options.Yoga
    menu:addOption("Yoga", {}, yoga.onAction, yoga, p)
    WorldMenu.attach(root, p); WorldMenu.attach(root, p)
    return root, menu
end
for round = 1, 3 do
    for index = 0, 1 do
        local p = getSpecificPlayer(index)
        p.dead = false
        local root, wellness = build(index)
        local entry = wellness:getOptionFromName("Second Nature")
        assert(#wellness.options == 2 and entry and entry.subOption, "One entry, with a submenu, round " .. round)
        local ours = wellness:getSubMenu(entry.subOption)
        assert(ours.player == index and ours:getOptionFromName("Yoga") and ours:getOptionFromName("Show window"))
        local tier = ours:getOptionFromName("Reach a moodle tier")
        local tiers = ours:getSubMenu(tier.subOption)
        assert(tier.onSelect == nil and tiers.player == index and tiers:getOptionFromName("Zen").subOption)
        for _, option in ipairs(ours.options) do
            if option.name ~= "Show window" then assert(option.iconTexture, option.name .. " has an icon") end
        end
        -- Pooled options must not leak our marks into the next menu.
        root:clear()
        for _, option in ipairs(root.options) do assert(not option.autoMindful) end
    end
end
local root, player = getPlayerContextMenu(0), getSpecificPlayer(0)
root:clear()
for _ = 1, 3 do assert(root:addOption("Anything", nil, nil).autoMindful == nil, "A reused option starts clean") end
print("STOCK MENU PASS")
