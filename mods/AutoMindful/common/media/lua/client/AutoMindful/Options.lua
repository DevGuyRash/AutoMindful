require "PZAPI/ModOptions"

local Options = {}
local settings = PZAPI.ModOptions:getOptions("AutoMindful")
if not settings then
    settings = PZAPI.ModOptions:create("AutoMindful", "AutoMindful")
    settings:addDescription("Open AutoMindful from Lifestyle's meditation and yoga menus. The window can be closed while training continues.")
end

local general = settings:getOption("generalContextMenu") or settings:addTickBox("generalContextMenu",
    "Always show AutoMindful in the world context menu", false,
    "Adds the general AutoMindful entry even when meditation or yoga is not currently offered. The training window remains available during an active session.")
local key = settings:getOption("openWindow") or settings:addKeyBind("openWindow",
    "Open AutoMindful window", 0,
    "Choose a shortcut to open the training and supply window. Opening or closing the window does not stop training. Unassigned by default.")

local search = settings:getOption("searchNearby") or settings:addTickBox("searchNearby",
    "Walk to nearby food, water and entertainment", false,
    "Opt in to care trips and scouting actual uninspected containers on the same floor, then return to the training spot. Native paths and access rules apply. Danger, manual movement or Stop cancels instead of forcing a return.")
local radius = settings:getOption("searchRadius") or settings:addSlider("searchRadius",
    "Nearby search radius (tiles)", 2, 30, 1, 10,
    "Search distance from the original training spot for each care trip. Default: 10 tiles. The route itself may be longer.")

function Options.searchNearby()
    return search:getValue() == true
end

function Options.searchRadius()
    return math.max(2, math.min(30, math.floor(tonumber(radius:getValue()) or 10)))
end

function Options.generalMenu()
    return general:getValue() == true
end

function Options.windowKey()
    return key:getValue()
end

return Options
