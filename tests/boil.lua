-- Boiling water to sterilize dressings, step by step, over doubles of the
-- kitchen's shared drivers. The game's rules it must keep: DisinfectBandage
-- takes 0.5 l of water in a container hotter than 1.6 (recipes_medical.txt,
-- RecipeCodeOnTest.hotFluidContainer); the heat is never left on.
package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
for _, name in ipairs({"ISApplyBandage", "ISRemoveGlass", "ISRemoveBullet", "ISDisinfect", "ISStitch", "ISSplint",
        "ISCleanBurn", "ISComfreyCataplasm", "ISGarlicCataplasm", "ISPlantainCataplasm"}) do
    package.loaded["TimedActions/" .. name] = true
end
package.loaded["AutoMindful/Fluids"] = {isWater = function() return true end}
package.loaded["AutoMindful/Log"] = {event = function() end}
package.loaded["AutoMindful/Snapshot"] = {item = tostring, object = tostring}
package.loaded["AutoMindful/Alerts"] = {raise = function() end}
package.loaded["AutoMindful/Supplies"] = {transfer = function() return true end}
package.loaded["AutoMindful/Fire"] = {plan = function() return nil end}
function getTimestampMs() return 0 end
function instanceof(value, kind) return type(value) == "table" and value.kind == kind end
ItemTag, ComponentType, Perks, Fluid = {COOKABLE = "cookable", PETROL = "petrol"}, {FluidContainer = "fluid"}, {}, {Water = "water"}
local queued = {}
ISTimedActionQueue = {add = function(action) queued[#queued + 1] = action end}
ISInventoryTransferUtil = {newInventoryTransferAction = function(_, item, from, to) return {Type = "move", item = item, from = from, to = to} end}
ISTakeWaterAction = {new = function(_, _, item) return {Type = "fill", item = item} end}
luautils = {walkAdj = function() queued[#queued + 1] = {Type = "walk"}; return true end}

local Boil = require "AutoMindful/Boil"
local Dressings = require "AutoMindful/Dressings"

local function container()
    local c = {items = {}}
    function c:getItemById(id) for _, it in ipairs(self.items) do if it.id == id then return it end end end
    function c:getItems() local items = self.items; return {size = function() return #items end, get = function(_, i) return items[i + 1] end} end
    function c:add(it) self.items[#self.items + 1] = it; it.container = self end
    function c:remove(it) for i, x in ipairs(self.items) do if x == it then table.remove(self.items, i) end end end
    function c:contains(it) for _, x in ipairs(self.items) do if x == it then return true end end return false end
    function c:getSourceGrid() return nil end
    function c:getContainingItem() return nil end
    function c:getFirstTypeRecurse(kind) for _, it in ipairs(self.items) do if it.type == kind then return it end end end
    return c
end
local inventory, grill = container(), container()
local square = {getX = function() return 1 end, getY = function() return 0 end, getZ = function() return 0 end}
local pot = {id = 7, type = "Pot", heat = 1, water = 0}
function pot:getItemHeat() return self.heat end
function pot:getDisplayName() return "Pot" end
function pot:getWorldItem() return nil end
function pot:getID() return self.id end
function pot:getContainer() return self.container end
function pot:getFluidContainer()
    local p = self
    return {getAmount = function() return p.water end, getCapacity = function() return 1.5 end, isEmpty = function() return p.water == 0 end,
        isPureFluid = function() return true end}
end
local on, lit = false, false
local stove = {getContainer = function() return grill end, getSquare = function() return square end}
local ledger
local K = {ledger = function() return ledger end, write = function(_, entry) ledger = entry end,
    accepts = function() return true end, heatKind = function() return "grill" end, fueled = function() return false end,
    isOn = function() return on end, canHeat = function() return true end, shared = function() return false end,
    heatName = function() return "grill" end, isTap = function() return true end, stoveAt = function() return stove end,
    toggle = function(_, _, state) queued[#queued + 1] = {Type = state and "light" or "out"} end,
    scan = function() return {stoves = {{object = stove, square = square}}, taps = {{object = {}, square = square}}} end}
local phases = {}
local P = {loanFor = function(_, state) local loan = {}; state.loans[#state.loans + 1] = loan; return loan end,
    ownBatch = function(_, _, _, message, add) phases[#phases + 1] = message; add(); return true end,
    setPhase = function(_, _, message) phases[#phases + 1] = message end}
Boil.bind(K, P)
local player = {getInventory = function() return inventory end, getSquare = function() return square end}
Grid = nil
package.loaded["AutoMindful/Grid"].reachable = function() return true end
getCell = function() return {getGridSquare = function() return {getObjects = function()
    return {size = function() return 1 end, get = function() return {} end} end} end} end
local crafted = 0
Dressings.logic = function(_, name, anchor, extra)
    assert(name == "DisinfectBandage" and extra and extra[1] == grill, "sterilized with the pot still on the heat")
    return pot.heat > 1.6 and pot.water >= 0.5 and {anchor = anchor} or nil
end
Dressings.craft = function(_, logic) crafted = crafted + 1; inventory:remove(logic.anchor); pot.water = pot.water - 0.5 end

local state = {rejected = {}, loans = {}}
local function step() queued = {}; return Boil.step(player, state, 0, ledger, stove) end
local function settle() Boil.settle(player, state, 0, false) end
local function rag() local r = {id = 100 + #inventory.items, type = "RippedSheets"}; function r:getID() return self.id end
    function r:getDisplayName() return "Rag" end; inventory:add(r); return r end

rag(); rag()
local floor = container(); floor:add(pot)
assert(Boil.start(player, state, 0, 2, {{item = pot, entry = {item = pot, container = floor, from = "floor"}}}))
assert(ledger.stage == "boil-fetch" and ledger.count == 2)
-- The pot is borrowed, and held through any yield while the boiling goes on.
step()
assert(#state.loans == 1 and state.loans[1].held and state.loans[1].defer)
floor:remove(pot); inventory:add(pot); settle(); step()
-- Then filled for both dressings and a little over.
assert(ledger.stage == "boil-fill" and queued[1].Type == "fill")
pot.water = 1.5; settle(); step()
-- On the heat, lit: it is ours to turn off.
assert(ledger.stage == "boil-place" and queued[1].Type == "move" and queued[2].Type == "light")
inventory:remove(pot); grill:add(pot); on = true; settle()
assert(ledger.stage == "boil-heat" and ledger.lit and Boil.hot(ledger.stage))
-- Not hot yet: watched, nothing made.
pot.heat = 1.3; assert(step() == false and crafted == 0, "watching water leaves room for other care")
-- Hot: both dressings, the pot still on the heat.
pot.heat = 1.8; step(); settle(); step(); settle()
assert(crafted == 2 and ledger.made == 2)
-- Done: the heat goes off and the pot comes away; the ledger is cleared.
step()
assert(ledger.stage == "boil-off" and queued[1].Type == "out" and queued[2].Type == "move")
grill:remove(pot); inventory:add(pot); on = false; settle(); step()
assert(ledger == nil and #state.loans == 1 and state.loans[1].aidReturn and not state.loans[1].held and not state.loans[1].defer,
    "the pot goes home once it is all over")
print("PASS water filled, heated, used on the heat, the heat off and the pot away")

do
    -- Never hot (out of propane, too slow): the heat off, and a while before trying again.
    ledger, crafted = nil, 0
    rag()
    pot.water, pot.heat = 1, 1
    assert(Boil.start(player, state, 0, 1, {{item = pot, entry = {item = pot}}}))
    step(); step()
    inventory:remove(pot); grill:add(pot); on = true; settle()
    on = false; step()
    assert(ledger.stage == "boil-off" and ledger.after == "cold")
    grill:remove(pot); inventory:add(pot); settle(); step()
    assert(ledger == nil and crafted == 0 and state.kitchenSkip.boil > 0)
    assert(not Boil.start(player, state, 0, 1, {{item = pot, entry = {item = pot}}}), "not again at once")
end
print("PASS water that will not heat is given up, the heat off")

do
    -- Someone takes the pot while our heat is on: the ledger stands until the heat is off.
    ledger, crafted, state.kitchenSkip = nil, 0, nil
    rag(); pot.water, pot.heat = 1, 1.2
    assert(Boil.start(player, state, 0, 1, {{item = pot, entry = {item = pot}}}))
    step(); step()
    inventory:remove(pot); grill:add(pot); on = true; settle()
    grill:remove(pot)
    step()
    assert(ledger and ledger.stage == "boil-off" and queued[1].Type == "out", "the heat goes off before giving up")
    on = false; settle(); step()
    assert(ledger == nil)
    -- Stop with the pot on the heat: off and away, and the ledger kept until the job is closed.
    state.kitchenSkip = nil
    rag(); pot.water, pot.heat = 1, 1.2; inventory:add(pot)
    assert(Boil.start(player, state, 0, 1, {{item = pot, entry = {item = pot}}}))
    step(); step()
    inventory:remove(pot); grill:add(pot); on = true; settle()
    queued = {}
    function player:isDead() return false end
    local said = Boil.ended(player, ledger, stove)
    assert(said and ledger.stage == "boil-off" and queued[1].Type == "out" and queued[2].Type == "move")
end
print("PASS the ledger is never cleared with our heat still on")
