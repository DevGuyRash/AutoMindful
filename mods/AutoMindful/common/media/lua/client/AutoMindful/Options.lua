require "PZAPI/ModOptions"
local Tiers = require "AutoMindful/TierTargets"
local Theme = require "AutoMindful/Theme"

local Options = {}
local settings = PZAPI.ModOptions:getOptions("AutoMindful")
if not settings then
    settings = PZAPI.ModOptions:create("AutoMindful", Theme.brand)
    settings:addDescription("The same settings are in the Second Nature window, under Settings. Closing the window does not stop the current job.")
end

-- Each setting's wording in the window, beside its definition here, so the
-- window and Options > Mods never drift apart. {label, tip}
Options.windowText = {
    generalContextMenu = {"Always in the right-click menu", "Off: it appears under Wellness, and on your survivor while a job runs."},
    defaultWindowKey = {"Use 0 when no key is set", "Only while nothing else uses 0."},
    practiceCare = {"Practise for relief", "Use Yoga or Meditation when it is the best way to ease a need."},
    strictRecoveryTier = {"Finish its moodle tier", "Keep working toward the minimum even if the need that started it clears."},
    recoveryAway = {"Away after", "Without any input. While you are away, Autopilot does everything it can."},
    cyclePolicy = {"Training both"},
    dietGoal = {"Diet goal"},
    cookTraining = {"Cooking practice", "When nobody is hungry, cooks raw food from the cupboards for Cooking XP and puts it back cold. What you carry is left alone."},
    logLevel = {"Log detail"},
}

-- Settings with a list of choices: their entries ({label, short, help}) and
-- the chosen index, for the window's menus. PZ stores the index.
local choiceSets = {}
local function choices(id, entries, index) choiceSets[id] = {entries = entries, index = index} end
function Options.choiceEntries(id) return choiceSets[id].entries end
function Options.choiceIndex(id) return choiceSets[id].index() end
function Options.choice(id) local set = choiceSets[id]; return set.entries[set.index()] end

local general = settings:getOption("generalContextMenu") or settings:addTickBox("generalContextMenu",
    "Always show Second Nature in the world context menu", false,
    "Off: it appears under Wellness, on a yoga mat, and on your survivor while a job runs. On: it is always at the bottom of the menu.")
local windowKeyLabel = "Open AutoMindful window"
local key = settings:getOption("openWindow") or settings:addKeyBind("openWindow",
    windowKeyLabel, 0,
    "Set a shortcut to open the window without starting or stopping a mode. Leave unassigned to use 0 if the default is enabled and the key is free.")
local defaultKey = settings:getOption("defaultWindowKey") or settings:addTickBox("defaultWindowKey",
    "Use 0 when the open shortcut is unassigned", true,
    "Use the number-row 0 as a fallback. Second Nature leaves the key alone if another game or mod binding uses it.")

Options.scoutingLabel = "Scout nearby for supplies"
Options.scoutingHelp = "When you need supplies, walk to a nearby source or inspect an unknown container on the same floor, then return. Danger, manual movement or Stop cancels the trip."
local search = settings:getOption("searchNearby") or settings:addTickBox("searchNearby",
    Options.scoutingLabel, true, Options.scoutingHelp)
local practice = settings:getOption("practiceCare") or settings:addTickBox("practiceCare",
    "Use Yoga or Meditation for relief when useful", true,
    "When a suitable practice is likely to help, take a bounded care break without using up a training turn. Food, water, medicine and ready reading still take priority.")
local strictRecovery = settings:getOption("strictRecoveryTier") or settings:addTickBox("strictRecoveryTier",
    "Autopilot: strict tier targets", false,
    "Once Autopilot starts a useful practice, keep its minimum tier pending even if that need clears. Your actions, urgent needs, and native requirements still take priority. This does not start a practice just to renew a buff.")
local radius = settings:getOption("searchRadius") or settings:addSlider("searchRadius",
    "Nearby search radius (tiles)", 2, 30, 1, 10,
    "Search distance from the original training spot for each care trip. Default: 10 tiles. The route itself may be longer.")

-- Recovery's own switches. Every one is safe to leave on; each is here because
-- someone will want the survivor to behave differently.
Options.awayMinutes = {1, 3, 5, 10}
local awayEntries = {}
for index, minutes in ipairs(Options.awayMinutes) do
    awayEntries[index] = {label = minutes == 1 and "1 minute" or minutes .. " minutes", short = minutes .. " min"}
end
local away = settings:getOption("recoveryAway")
if not away then
    away = settings:addComboBox("recoveryAway", "Autopilot: counts you as away after",
        "While you are away, Autopilot also walks for small needs, sleeps in bed, fills bottles and warns you out loud.")
    for _, entry in ipairs(awayEntries) do away:addItem(entry.label) end
    away:setValue(2)
end

function Options.awayIndex()
    local index = tonumber(away:getValue())
    return index and Options.awayMinutes[index] and index or 2
end

function Options.awayMs() return Options.awayMinutes[Options.awayIndex()] * 60000 end
choices("recoveryAway", awayEntries, Options.awayIndex)

local recoveryTicks = {}
-- {id, Options > Mods label, its help, window label, window tip}
for _, row in ipairs({
    {"recoveryFirstAid", "First aid", "Stops bleeding, then pulls glass and bullets, disinfects, stitches, splints and dresses wounds with what is carried or nearby, and puts borrowed supplies back. Also during training.",
        "First aid", "Stops bleeding, then pulls glass and bullets, disinfects, stitches, splints and dresses wounds with what is carried or nearby, and puts borrowed supplies back. Also during training."},
    {"recoveryBetween", "Autopilot: eat and drink between your actions", "While you or another mod keep the action queue busy, a carried bite or sip goes between two actions.",
        "Eat and drink between actions", "While you or another mod keep the queue busy, a carried bite or sip goes between two actions."},
    {"recoveryRefill", "Autopilot: keep carried bottles full", "Refills bottles you carry at clean water. The game drinks from them by itself.",
        "Keep carried bottles full", "The game drinks from carried bottles by itself, so a full one keeps the survivor going when nothing else works."},
    {"recoveryBeds", "Autopilot: sleep in a bed when one is near", "Walks to a bed within the search radius and back afterwards. Off: sleeps on the spot.",
        "Sleep in a nearby bed", "Walks there and back. Off: sleeps on the spot."},
    {"recoveryLastResort", "Autopilot: drink unsafe water rather than die", "Only after a minute of Dying of Thirst with nothing clean left. It will make the survivor ill.",
        "Unsafe water rather than death", "Only after a minute of Dying of Thirst with nothing clean left."},
    {"recoverySound", "Autopilot: sound when it needs you", "Heard only by you, not by zombies.",
        "Sound when it needs you", "Heard only by you, not by zombies."},
    {"recoveryResume", "Autopilot: carry on after loading", "If Autopilot was on when you left, it starts again when you are back in.",
        "Carry on after loading", "If Autopilot was on when you left, it starts again."},
    {"recoveryCook", "Autopilot: cook raw food on a stove", "When only raw food is left, cooks it on a powered stove nearby, takes it out once cooked and turns the stove off.",
        "Cook raw food on a stove", "When only raw food is left, cooks it on a powered stove nearby, takes it out once cooked and turns the stove off."},
    {"recoverySoup", "Autopilot: make dishes from recipes", "Soups, stews, stir fries, salads, sandwiches, burgers, pies, pasta and every other recipe the game has, from a base nearby (a pot of water, a pan, a bowl, bread) and the best ingredients for it.",
        "Make dishes from recipes", "Soups, stews, stir fries, salads, sandwiches, pies and every other recipe the game has, from what is nearby."},
    {"recoveryRotten", "Autopilot: use rotten food in recipes from Cooking 7", "The game takes rotten ingredients from Cooking 7, at a tenth to a twentieth of their value. Off: never.",
        "Rotten food in recipes from Cooking 7", "The game's own rule: a sliver of its value, and only from Cooking 7."},
}) do
    recoveryTicks[row[1]] = settings:getOption(row[1]) or settings:addTickBox(row[1], row[2], true, row[3])
    Options.windowText[row[1]] = {row[4], row[5]}
end
-- The window lists Autopilot's switches in this order.
Options.autopilotToggles = {"recoveryFirstAid", "recoveryBetween", "recoveryRefill", "recoveryCook", "recoverySoup", "recoveryRotten", "recoveryBeds",
    "recoveryLastResort", "recoverySound", "recoveryResume", "strictRecoveryTier"}
local function ticked(id) return function() return recoveryTicks[id]:getValue() == true end end
Options.firstAid = ticked("recoveryFirstAid")
Options.careBetween, Options.refill, Options.useBeds = ticked("recoveryBetween"), ticked("recoveryRefill"), ticked("recoveryBeds")
Options.lastResort, Options.alertSound, Options.resumeRecovery = ticked("recoveryLastResort"), ticked("recoverySound"), ticked("recoveryResume")
Options.cookMeals, Options.makeSoup = ticked("recoveryCook"), ticked("recoverySoup")
Options.rottenRecipes = ticked("recoveryRotten")

-- PZ stores the combo's index. Keep this order stable.
local practiceChoices = {
    {id="spoiling", label="Cook food that would spoil", short="Spoiling food", help="Raw food that would spoil within three days."},
    {id="all", label="Cook all spare raw food", short="All spare food", help="Any raw food in the cupboards, to level Cooking faster."},
    {id="off", label="Off", help="Cooks only when the survivor is hungry."},
}
local practiceOption = settings:getOption("cookTraining")
if not practiceOption then
    practiceOption = settings:addComboBox("cookTraining", "Autopilot: cooking practice",
        "When nobody is hungry, cooks raw food from the cupboards for Cooking XP and puts it back cold.")
    for _, entry in ipairs(practiceChoices) do practiceOption:addItem(entry.label) end
    practiceOption:setValue(1)
end
function Options.cookTrainingIndex()
    local index = tonumber(practiceOption:getValue())
    return index and practiceChoices[index] and index or 1
end
function Options.cookTraining() return practiceChoices[Options.cookTrainingIndex()].id end
choices("cookTraining", practiceChoices, Options.cookTrainingIndex)

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

-- PZ stores the combo's index. Keep this order stable.
local diets = {
    {id="auto", label="Auto: keep a healthy weight", help="Prefers calorie-dense food below 75 kg and lighter food above 85 kg; otherwise balanced."},
    {id="balanced", label="Balanced", help="No preference beyond what the need calls for."},
    {id="protein", label="High protein", help="Prefers protein-rich food when choices are close."},
    {id="more", label="More calories (gain weight)", help="Prefers calorie-dense food when choices are close."},
    {id="fewer", label="Fewer calories (lose weight)", help="Prefers lighter food when choices are close. The survivor may eat a little more often."},
    {id="lowcarb", label="Low carb", help="Prefers food with fewer carbohydrates when choices are close."},
    {id="lowfat", label="Low fat", help="Prefers food with less fat when choices are close."},
}
local diet = settings:getOption("dietGoal")
if not diet then
    diet = settings:addComboBox("dietGoal", "Diet goal", "What Autopilot and the kitchen prefer when several foods would do.")
    for _, entry in ipairs(diets) do diet:addItem(entry.label) end
    diet:setValue(1)
end
function Options.dietIndex()
    local index = tonumber(diet:getValue())
    return index and diets[index] and index or 1
end
choices("dietGoal", diets, Options.dietIndex)
function Options.dietGoal() return diets[Options.dietIndex()].id end

function Options.cycleIndex()
    local index = tonumber(cycle:getValue())
    return index and cycles[index] and index or 1
end
choices("cyclePolicy", cycles, Options.cycleIndex)

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

-- What the log file records. Everything is the default: a problem is usually
-- noticed after it happened, and the files rotate at a fixed size.
local logEntries = {{label = "Off"}, {label = "Decisions"}, {label = "Everything"}}
Options.logLabels = {}
for index, entry in ipairs(logEntries) do Options.logLabels[index] = entry.label end
local logOption = settings:getOption("logLevel")
if not logOption then
    logOption = settings:addComboBox("logLevel", "Diagnostics log",
        "Records decisions, actions, containers and survivor state in Zomboid/Lua/AutoMindful. Up to five files of 4 MB.")
    for _, label in ipairs(Options.logLabels) do logOption:addItem(label) end
    logOption:setValue(3)
end

function Options.logLevel()
    local value = tonumber(logOption:getValue())
    return value and Options.logLabels[value] and value or 3
end

function Options.logLabel() return Options.logLabels[Options.logLevel()] end
choices("logLevel", logEntries, Options.logLevel)

local minimums = {}
local minimumHelp = "Defaults to the highest tier and uses the highest unlocked tier at or below your choice. Select No minimum to turn this off. Safety, supplies and your other actions still take priority."
for _, group in ipairs({
    {id="recovery", label="Autopilot / relief", scope="A practice must already be useful for a need. The Autopilot strict option keeps a started target even if that need clears."},
    {id="capped", label="Capped practice", scope="Regular practice turns started at the level cap, not endurance-only rest breaks."},
    {id="rotation", label="Train Both", scope="Regular Yoga and Meditation turns in Train Both, not endurance-only rest breaks."},
}) do
    local modes = {}
    minimums[group.id] = modes
    modes.group = group
    for _, spec in ipairs({
        {kind="meditation", suffix="MindfulnessTier", label="Mindfulness"},
        {kind="yoga", suffix="YogaZenTier", label="Yoga Zen"},
    }) do
        local id = group.id .. spec.suffix
        local choices = Tiers.choices(spec.kind)
        local option = settings:getOption(id)
        if not option then
            option = settings:addComboBox(id, group.label .. ": minimum " .. spec.label, group.scope .. " " .. minimumHelp)
            for _, row in ipairs(choices) do
                local label = row.tier == 0 and row.label or Tiers.providerCompatible() and row.label .. " (level " .. row.rank .. ")" or row.label
                option:addItem(label)
            end
            option:setValue(#choices)
        end
        modes[spec.kind] = {id=id, kind=spec.kind, label=spec.label, option=option, choices=choices}
    end
end

function Options.minimumTier(group, kind)
    local item = minimums[group] and minimums[group][kind]
    if not item then return 0 end
    local index = tonumber(item.option:getValue())
    local row = index and index % 1 == 0 and item.choices[index]
    return row and row.tier or 0
end

local function minimumIndex(item)
    local index = tonumber(item.option:getValue())
    return index and item.choices[index] and index or 1
end

function Options.minimumItems(group)
    local result = {}
    for _, kind in ipairs({"meditation", "yoga"}) do
        local item = minimums[group] and minimums[group][kind]
        if item then
            result[#result + 1] = {id=item.id, kind=kind, label=item.label, choices=item.choices, index=minimumIndex(item)}
        end
    end
    return result
end

local groupText = {
    recovery={label="Relief tier", help="How far a practice started for a need should go."},
    capped={label="Tier at level 10", help="How far each practice goes once its skill is maxed."},
    rotation={label="Tier in Training both", help="How far each turn goes before switching."},
}
function Options.minimumGroups()
    local result = {}
    for _, id in ipairs({"rotation", "capped", "recovery"}) do
        local names = {}
        for _, item in ipairs(Options.minimumItems(id)) do names[#names + 1] = item.choices[item.index].label end
        result[#result + 1] = {id=id, label=groupText[id].label, help=groupText[id].help, summary=table.concat(names, " / ")}
    end
    return result
end

function Options.strictRecoveryTier()
    return strictRecovery:getValue() == true
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

local function valid(option, value)
    if option.type == "tickbox" then return type(value) == "boolean" end
    if option.type == "combobox" then return type(value) == "number" and option.values[value] ~= nil end
    if option.type == "slider" then return type(value) == "number" and value >= option.min and value <= option.max end
    return option == key and Options.bindableWindowKey(value)
end

function Options.option(id) return settings:getOption(id) end

-- One place writes a setting, whichever surface it was changed on. Stock Mod
-- Options keeps its own widget in step through setValue.
function Options.set(id, value)
    local option = settings:getOption(id)
    if not option or option.isEnabled == false or option:getValue() == value or not valid(option, value) then return false end
    if option.onChange then option:onChange(value) end
    if option.onChangeApply then option:onChangeApply(value) end
    option:setValue(value)
    local element = option == key and option.element
    if element and element.btn then
        -- PZAPI updates keyCode but not the already-built button's title.
        element.shift, element.ctrl, element.alt = nil, nil, nil
        element.btn:setTitle(getKeyName(value))
    end
    settings:apply()
    saveSettings()
    return true
end

function Options.windowKeyLabel()
    local code = Options.windowKey()
    local name = code ~= 0 and getKeyName and getKeyName(code) or nil
    return name and name ~= "" and name or "None"
end

return Options
