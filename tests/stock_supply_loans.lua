-- Stock B42 inventory transfer and merge logic. Java handles, the actual
-- inventory move, fluids, and Lifestyle are the existing controller doubles.
AutoMindfulContractHarnessOnly = true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly = nil
local T, C = AutoMindfulTest, AutoMindfulTest.controller
local S = require "AutoMindful/Supplies"
local Memory = require "AutoMindful/ScoutMemory"
local function stock(path)
    if loadUpstream then return loadUpstream(path) end
    local media = assert(arg and arg[1], "Pass the installed game media directory")
    return assert(loadfile(media .. "/lua/" .. path))()
end

local function noop() end
local function no() return false end
local function yes() return true end
local function q(p) return ISTimedActionQueue.getTimedActionQueue(p) end
local function head(p) return q(p).queue[1] end
local function transferCount(p)
    local count = 0
    for _, name in ipairs(p.history) do
        if name == "ISInventoryTransferAction" then count = count + 1 end
    end
    return count
end

function isServer() return false end
function removeItemTransaction() end
function round(n) return n end
function table.wipe(t) for k in pairs(t) do t[k] = nil end end
local vanillaInstanceof = instanceof
function instanceof(item, kind)
    return item and ((kind == "IsoObject" and item.kind == "IsoObject") or vanillaInstanceof(item, kind))
end
CharacterTrait.DEXTROUS, CharacterTrait.ALL_THUMBS = "dexterous", "all-thumbs"
ISInventoryPage = {}
ItemPicker = {updateOverlaySprite=noop}
ISBaseTimedAction = {derive = function(base, name) return setmetatable({Type=name}, {__index=base}) end}
function ISBaseTimedAction:begin()
    self.action = {setTime=noop, setLoopedAction=noop, stopTimedActionAnim=noop,
        forceStop=function() self:stop() end}
    self.character.nativeHead = self.action
end
function ISBaseTimedAction:isStarted() return self.action ~= nil end
function ISBaseTimedAction:forceStop() self:stop() end
ISBaseTimedAction.forceCancel = noop
function ISBaseTimedAction:perform()
    if self.character.nativeHead == self.action then self.character.nativeHead = nil end
    q(self.character):onCompleted(self)
end
function ISBaseTimedAction:stop()
    if self.character.nativeHead == self.action then self.character.nativeHead = nil end
    q(self.character):resetQueue()
end
for _, name in ipairs({"TimedActions/ISBaseTimedAction", "TimedActions/ISInventoryTransferAction",
        "TimedActions/ISGrabCorpseAction", "ISUI/PlayerData/ISPlayerData"}) do package.loaded[name] = true end
stock("client/TimedActions/ISInventoryTransferAction.lua")
stock("shared/TimedActions/ISInventoryTransferUtil.lua")
function ISInventoryTransferAction:getNotFullFloorSquare() return nil end
ISInventoryTransferAction.playTransferCompleteSound = noop
ISInventoryTransferAction.playSourceContainerCloseSound = noop
ISInventoryTransferAction.playDestContainerCloseSound = noop
ISInventoryTransferAction.startActionAnim, ISInventoryTransferAction.resetJobDelta = noop, noop
ISTransferAction = {transferItem=function(_, _, item, source, target)
    assert(source:contains(item), "Only the exact source item reaches the Java move")
    T.remove(source, item)
    T.add(target, item)
    return item
end}

local function holder(c)
    c.isVehicleSeat, c.isExistYet = no, yes
    function c:isInCharacterInventory(p) return self:getOutermostContainer() == p:getInventory() end
    c.isRemoveItemAllowed, c.isItemAllowed, c.isInside = yes, yes, no
    c.setDrawDirty, c.setHasBeenLooted, c.getParent = noop, noop, noop
    return c
end
local function supply(c, item)
    function item:isFavorite() return self.favorite == true end
    function item:getActualWeight() return .5 end
    item.getWeight = item.getActualWeight
    item.isHumanCorpse, item.getIsCraftingConsumed, item.setJobDelta = no, no, noop
    return T.add(c, item)
end
local function setup()
    local p = T.playerNew()
    holder(p:getInventory())
    p.isWearingAwkwardGloves, p.isTimedActionInstant = no, no
    local timed = q(p)
    function timed:indexOf(action)
        for i, queued in ipairs(self.queue) do if queued == action then return i end end
        return -1
    end
    local crate = holder(T.container(1,0))
    local square = crate:getSourceGrid()
    local o = {kind="IsoObject",getSquare=function() return square end}
    function o:getMasterObject() return self end
    function o:getContainerCount() return 1 end
    function o:getContainerByIndex(i) if i == 0 then return crate end end
    function o:getObjectName() return "Crate" end
    function o:getSprite() return {getName=function() return "test-crate" end,getProperties=noop} end
    o.getOverlaySprite = noop
    function crate:getParent() return o end
    function square:getObjects() return T.list({o}) end
    T.loadSquare(p, square)
    p.nearby = {crate}
    return p, crate
end

do
    local p, crate = setup()
    local donor = supply(crate, T.water({capacity=5,hunger=-.5,thirst=-.5}))
    local cup = supply(crate, T.water())
    local unrelated = supply(crate, T.item("InventoryItem"))
    donor.fluid.amount, cup.fluid.amount = 5, 0
    assert(Memory.supplyTarget("water", donor), "Use a crate that exercises the exact donor guard")
    p.values.HUNGER, p.values.THIRST = .2, .2
    assert(C.start(p, "meditation", true))
    T.tick(p, false)
    local pickup, second = head(p), q(p).queue[2]
    assert(pickup.item == donor and second.item == cup)
    T.tick(p)
    assert(p:getInventory():contains(donor) and head(p) == second and second:isValid(),
        "Stock must retire the donor and offer the separately guarded cup action")
    T.tick(p)
    assert(p:getInventory():contains(cup) and crate:contains(unrelated))
    for _=1,9 do T.tick(p) end
    assert(crate:contains(donor) and crate:contains(cup) and crate:contains(unrelated))
    assert(C.status(p).pendingReturns == 0 and transferCount(p) == 4)
    assert(math.abs(donor.fluid.amount - 4.6) < .000001 and cup.fluid.amount == 0)
    assert(T.hasHistory(p, "drink") and T.hasHistory(p, "Meditation"))
    C.stop(p)
    print("PASS stock same-crate milk and cup each transfer, pour, and return before training")
end

do
    local p, crate = setup()
    local first = supply(crate, T.item("InventoryItem"))
    local second = supply(crate, T.item("InventoryItem"))
    local manual = ISInventoryTransferUtil.newInventoryTransferAction(p, first, crate, p:getInventory())
    ISTimedActionQueue.add(manual)
    assert(S.transfer(p, second))
    local exact = q(p).queue[2]
    assert(not manual:canMergeAction(exact) and not exact:canMergeAction(manual))
    manual:checkQueueList()
    assert(#q(p).queue == 2 and q(p).queue[2] == exact and exact.item == second)
    print("PASS stock manual transfer cannot absorb an exact same-endpoint pickup")
end

for _, whileReturning in ipairs({false,true}) do
    local p, crate = setup()
    local book = supply(crate, T.item("Literature",{data={literatureTitle="Fixture Book"}}))
    p.values.BOREDOM = 30
    assert(C.start(p, "meditation", true))
    T.tick(p); T.tick(p)
    assert(p:getInventory():contains(book) and T.hasHistory(p,"read"))
    if whileReturning then
        T.tick(p, false)
        local returning = head(p)
        assert(returning.item == book and returning.destContainer == crate and returning:isValid())
        book.favorite = true
        assert(not returning:isValid(), "A favorite change during native restitution must block it")
        returning:perform() -- Stock validates again before its Java transfer.
    else book.favorite = true end
    local count = transferCount(p)
    for _=1,4 do T.tick(p, false) end
    local status = C.status(p)
    assert(status.active and T.hasHistory(p,"Meditation") and status.pendingReturns == 1)
    assert(status.returnNotice and status.returnNotice:find("favorite", 1, true))
    assert(p:getInventory():contains(book) and transferCount(p) == count,
        "The controller must not spend another native action trying to return the favorite")
    C.stop(p)
    for _=1,4 do T.tick(p) end
    assert(p:getInventory():contains(book) and transferCount(p) == count)
    book.favorite = false
    T.tick(p); T.tick(p)
    assert(crate:contains(book) and transferCount(p) == count + 1 and C.status(p).pendingReturns == 0)
end
print("PASS favorite before/during restitution stays put with notice; unstar returns once")

do
    local p, floor = setup()
    floor.floor = true
    local original = supply(floor, T.item("InventoryItem"))
    local loan = S.loan(p, original)
    T.remove(floor, original)
    T.add(p:getInventory(), original)
    original.favorite = true
    local output = supply(p:getInventory(), T.item("InventoryItem"))
    local unrelated = supply(p:getInventory(), T.item("InventoryItem"))
    loan.items[2] = output -- An attributed output from the original loan.
    local action = assert(S.returnAction(p, loan))
    ISTimedActionQueue.add(action)
    T.tick(p)
    assert(floor:contains(output) and p:getInventory():contains(unrelated))
    local retry, notice, complete = S.returnAction(p, loan)
    assert(not retry and not complete and notice:find("favorite", 1, true))
    assert(p:getInventory():contains(original))
    print("PASS favorite grounded loan stays put without blocking another attributed return")
end
