require "PZAPI/ModOptions"

local Options = {}
local settings = PZAPI.ModOptions:getOptions("AutoMindful")
if not settings then
    settings = PZAPI.ModOptions:create("AutoMindful", "AutoMindful")
    settings:addDescription("Open AutoMindful for Recovery, training or supply checks. Closing the window does not stop the current mode.")
end

local general = settings:getOption("generalContextMenu") or settings:addTickBox("generalContextMenu",
    "Always show AutoMindful in the world context menu", false,
    "Adds the general AutoMindful entry even when meditation or yoga is not currently offered. The window remains available during an active session.")
local windowKeyLabel = "Open AutoMindful window"
local key = settings:getOption("openWindow") or settings:addKeyBind("openWindow",
    windowKeyLabel, 0,
    "Set a shortcut to open the window without starting or stopping a mode. Leave unassigned to use 0 if the default is enabled and the key is free.")
local defaultKey = settings:getOption("defaultWindowKey") or settings:addTickBox("defaultWindowKey",
    "Use 0 when the open shortcut is unassigned", true,
    "Use the number-row 0 as a fallback. AutoMindful leaves the key alone if another game or mod binding uses it.")

Options.scoutingLabel = "Scout nearby for supplies"
Options.scoutingHelp = "When you need supplies, walk to a nearby source or inspect an unknown container on the same floor, then return. Danger, manual movement or Stop All cancels the trip."
local search = settings:getOption("searchNearby") or settings:addTickBox("searchNearby",
    Options.scoutingLabel, true, Options.scoutingHelp)
local practice = settings:getOption("practiceCare") or settings:addTickBox("practiceCare",
    "Use Yoga or Meditation for relief when useful", true,
    "When a suitable practice is likely to help, take a bounded care break without using up a training turn. Food, water, medicine and ready reading still take priority.")
local radius = settings:getOption("searchRadius") or settings:addSlider("searchRadius",
    "Nearby search radius (tiles)", 2, 30, 1, 10,
    "Search distance from the original training spot for each care trip. Default: 10 tiles. The route itself may be longer.")

-- PZ stores the stock combo's selected index. Keep this order stable.
local cycles = {
    {id="alternate", label="Alternate", help="Switch after a completed native practice. A temporarily blocked skill retains its turn."},
    {id="lowest", label="Lowest progress first", help="Choose the lower skill level, including progress toward its next level."},
    {id="closest", label="Closest to level 10 first", help="Focus on the skill closest to level 10."},
}
Options.cycleLabel = "Train Both cycling"
Options.cycleHelp = "Choose how Train Both decides which skill is next. A change applies at the next safe decision, not during a normal practice."

local cycle = settings:getOption("cyclePolicy")
if not cycle then
    cycle = settings:addComboBox("cyclePolicy", Options.cycleLabel, Options.cycleHelp)
    for _, entry in ipairs(cycles) do cycle:addItem(entry.label) end
end

function Options.cycleChoices()
    return cycles
end

function Options.cycleIndex()
    local index = tonumber(cycle:getValue())
    return index and cycles[index] and index or 1
end

function Options.cyclePolicy()
    return cycles[Options.cycleIndex()].id
end

function Options.setCycleIndex(index)
    if not cycles[index] or cycle:getValue() == index then return end
    cycle:setValue(index)
    PZAPI.ModOptions:save()
end

function Options.practiceCare()
    return practice:getValue() == true
end

function Options.searchNearby()
    return search:getValue() == true
end

function Options.setSearchNearby(enabled)
    if search:getValue() == enabled then return end
    search:setValue(enabled)
    PZAPI.ModOptions:save()
end

function Options.searchRadius()
    return math.max(2, math.min(30, math.floor(tonumber(radius:getValue()) or 10)))
end

function Options.generalMenu()
    return general:getValue() == true
end

local function occupied(code)
    local core = getCore and getCore()
    -- Core returns an opaque Java record. Compare handles only: trying to
    -- call its record accessors logs a Lua error even inside pcall.
    if core and core.getKeyBinding then
        local registered = core:getKeyBinding(code)
        local empty = core:getKeyBinding("AutoMindful.UnregisteredBindingSentinel")
        if registered and registered ~= empty and registered ~= core:getKeyBinding(windowKeyLabel) then return true end
    end
    for _, entry in ipairs((MainOptions and MainOptions.keys) or keyBinding or {}) do
        local name = entry.value
        if type(name) == "string" and name ~= windowKeyLabel and name:sub(1, 1) ~= "[" then
            local primary = core and core.getKey and core:getKey(name) or entry.key
            local alternate = core and core.getAltKey and core:getAltKey(name) or entry.altCode or entry.alt
            if primary == code or alternate == code then return true end
        end
    end
    for _, group in ipairs(PZAPI.ModOptions.Data or {}) do
        for _, option in ipairs(group.data or {}) do
            if option ~= key and option.type == "keybind" and tonumber(option:getValue()) == code then return true end
        end
    end
    return false
end

function Options.windowKey()
    local chosen = tonumber(key:getValue()) or 0
    if chosen == 0 and defaultKey:getValue() == true then chosen = Keyboard and Keyboard.KEY_0 or 0 end
    if chosen <= 0 or chosen % 1 ~= 0 or (Keyboard and chosen == Keyboard.KEY_ESCAPE) or occupied(chosen) then return 0 end
    return chosen
end

return Options
