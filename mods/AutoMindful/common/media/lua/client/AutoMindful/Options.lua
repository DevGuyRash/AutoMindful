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

function Options.generalMenu()
    return general:getValue() == true
end

function Options.windowKey()
    return key:getValue()
end

return Options
