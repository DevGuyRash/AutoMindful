require "PZAPI/ModOptions"
local Tiers = require "AutoMindful/TierTargets"

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

local function saveSettings()
    local registry = PZAPI.ModOptions
    local unknown = registry.OtherOptions
    if not unknown or #unknown == 0 then return registry:save() end
    -- B42 reads unknown/disabled mods with BufferedReader:readLine but writes
    -- the raw records with writer:write. Keep their boundaries intact when
    -- AutoMindful saves, without changing stock persistence or the registry.
    local records = {}
    for i, line in ipairs(unknown) do
        local tail = line:sub(-1)
        records[i] = (tail == "\r" or tail == "\n") and line or line .. "\r\n"
    end
    registry.OtherOptions = records
    local ok, failure = pcall(registry.save, registry)
    registry.OtherOptions = unknown
    if not ok then error(failure) end
end

function Options.setCycleIndex(index)
    if not cycles[index] or cycle:getValue() == index then return end
    cycle:setValue(index)
    saveSettings()
end

local minimums = {}
local minimumHelp = "Defaults to the highest tier and uses the highest unlocked tier at or below your choice. Select No minimum to turn this off. Safety, supplies and your other actions still take priority."
for _, group in ipairs({
    {id="recovery", label="Recovery / relief"},
    {id="capped", label="Capped practice"},
    {id="rotation", label="Train Both"},
}) do
    local modes = {}
    minimums[group.id] = modes
    for _, spec in ipairs({
        {kind="meditation", suffix="MindfulnessTier", label="Mindfulness"},
        {kind="yoga", suffix="YogaZenTier", label="Yoga Zen"},
    }) do
        local id = group.id .. spec.suffix
        local choices = Tiers.choices(spec.kind)
        local option = settings:getOption(id)
        if not option then
            option = settings:addComboBox(id, group.label .. ": minimum " .. spec.label, minimumHelp)
            for _, row in ipairs(choices) do
                local label = row.tier == 0 and row.label or Tiers.providerCompatible() and row.label .. " (level " .. row.rank .. ")" or row.label
                option:addItem(label)
            end
            option:setValue(#choices)
        end
        modes[spec.kind] = {option=option, choices=choices}
    end
end

function Options.minimumTier(group, kind)
    local item = minimums[group] and minimums[group][kind]
    if not item then return 0 end
    local index = tonumber(item.option:getValue())
    local row = index and index % 1 == 0 and item.choices[index]
    return row and row.tier or 0
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
    saveSettings()
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

function Options.bindableWindowKey(code)
    return type(code) == "number" and code >= 0 and code % 1 == 0
        and (code == 0 or (not (Keyboard and code == Keyboard.KEY_ESCAPE) and not occupied(code)))
end

function Options.windowKey()
    local chosen = tonumber(key:getValue()) or 0
    if chosen == 0 and defaultKey:getValue() == true then chosen = Keyboard and Keyboard.KEY_0 or 0 end
    return Options.bindableWindowKey(chosen) and chosen or 0
end

function Options.modSettings()
    return settings
end

local function validPanelValue(option, value)
    if option.type == "tickbox" then return type(value) == "boolean" end
    if option.type == "combobox" then
        return type(value) == "number" and option.values[value] ~= nil
    end
    if option.type == "slider" then
        return type(value) == "number" and value >= option.min and value <= option.max
    end
    return option == key and Options.bindableWindowKey(value)
end

function Options.applyPanelChanges(changes)
    local changed, refreshSupplies = false, false
    for _, edit in ipairs(changes) do
        local option, value = edit.option, edit.value
        if option.id and settings:getOption(option.id) == option and option.isEnabled ~= false
                and option:getValue() ~= value and validPanelValue(option, value) then
            if option.onChange then option:onChange(value) end
            if option.onChangeApply then option:onChangeApply(value) end
            option:setValue(value) -- Updates the stock Mods page widget, if present.
            if option == key then
                local element = option.element
                if element and element.btn then
                    -- PZAPI updates keyCode but not the already-built button's title.
                    element.shift, element.ctrl, element.alt = nil, nil, nil
                    element.btn:setTitle(getKeyName(value))
                end
            end
            changed = true
            refreshSupplies = refreshSupplies or option == search or option == radius
        end
    end
    if changed then
        settings:apply()
        saveSettings()
    end
    return changed, refreshSupplies
end

return Options
