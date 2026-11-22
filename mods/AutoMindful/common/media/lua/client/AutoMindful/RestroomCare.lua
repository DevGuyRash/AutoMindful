-- Lifestyle 0.4.0.3 client adapter. Scouting is read-only; ONLY dispatch builds
-- an option for the exact fixture/current player. Never write needs or apply effects.
local Storage = require "AutoMindful/Storage"
local Restroom = {}
AutoMindful = AutoMindful or {}
AutoMindful.RestroomCare = Restroom

local function enabled()
    return SandboxVars and SandboxVars.Text and SandboxVars.Text.DividerHygiene == true
        and SandboxVars.LSHygiene and LSUtil and LSHygiene and LSHygiene.DS and LSHygiene.TF
        and ToiletContextMenu and ToiletContextMenu.doBuildMenu and ToiletContextMenu.onAction
        and ToiletGroundContextMenu and ToiletGroundContextMenu.doBuildMenu
end

local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function read(player)
    if not enabled() or not player or not player:hasModData() then return end
    local d = player:getModData()
    local m = d.LSMoodles and d.LSMoodles.BladderNeed
    if not m or not finite(m.Value) or not finite(d.bathroomNeed) or not finite(d.hygieneNeed) then return end
    return m.Value, d.bathroomNeed, d.IsDoingToilet
end
local function protected(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
end
local function need(player)
    local value, raw = read(player)
    -- Native menu gates on Value, while raw may hit zero before the next moodle update.
    return value and value >= 0.2 and raw > 0 and value or 0
end
function Restroom.need(player) return protected(need, player) or 0 end

local function permitted(player, square)
    return square and (not isClient() or SafeHouse.isSafehouseAllowInteract(square, player))
end
local function safeHere(player, privacy)
    local sq = player:getSquare()
    if not permitted(player, sq) or sq:haveFire() or player:isDead() or player:isAsleep()
            or player:getVehicle() or player:isOnFire() or player:isRunning() or player:isSprinting()
            or player:isAttacking() or player:isAiming() then return false end
    local stats = player:getStats()
    if stats:getNumVisibleZombies() > 0 or stats:getNumChasingZombies() > 0
            or stats:getNumVeryCloseZombies() > 0 then return false end
    -- Same proximity used by Lifestyle before its involuntary full-bladder animation.
    -- Not an alleged native menu threshold: it is our safety preflight.
    if #LSMovObjs.getMovingObjects(sq, "IsoZombie", 8) > 0 then return false end
    return SandboxVars.LSHygiene.NotEmbarrassed == true or not LSUtil.canSeeOtherPlayers(player, privacy)
end
local function groundAllowed(player)
    return need(player) >= 0.4 and safeHere(player, 4)
end
function Restroom.groundAllowed(player) return protected(groundAllowed, player) == true end

local kinds = {Fancy=true, Low=true, Hanging=true, Chemical=true, Wooden=true}
local function occupied(square, fixture, player)
    local moving = square:getMovingObjects()
    for i=0,moving:size()-1 do
        local other = moving:get(i)
        if other ~= player and instanceof(other, "IsoPlayer") and other:getSitOnFurnitureObject() == fixture then return true end
    end
    return false
end
local function inspect(player, obj)
    if not enabled() or not obj then return end
    local sprite = obj:getSprite()
    local name = sprite and sprite:getName()
    if not name or not LSHygiene.DS.Toilets[name] then return end
    local prop = sprite:getProperties()
    local group = prop:get("GroupName")
    if prop:get("CustomName") ~= "Toilet" or not kinds[group] or (group == "Hanging" and player:isFemale()) then return end
    local square = obj:getSquare()
    local front = square and square:getAdjacentSquare(IsoDirections[prop:get("Facing")])
    local here = player:getSquare()
    if not here or not permitted(player, square) or not permitted(player, front) or here:getZ() ~= square:getZ()
            or not LSUtil.isObjOnSqr(obj) or (instanceof(obj, "IsoThumpable") and obj:isLockedToCharacter(player))
            or square:haveFire() or front:haveFire() or not AdjacentFreeTileFinder.privTrySquare(square, front)
            or occupied(square,obj,player) or occupied(front,obj,player) then return end
    local water = LSHygiene.TF.getWaterUsage(group)
    if water and not LSUtil.objHasWater(obj, water) then return end
    -- Never call getModData on a fresh fixture during discovery, initialize uses,
    -- refresh the overlay or transmit. The stock builder handles all of that on arrival.
    local data = obj:hasModData() and obj:getModData().movableData
    local uses = data and data.uses
    local clog = data and data.isClogged
    if (clog and (not finite(clog) or clog >= 0)) or (uses and (not finite(uses) or uses <= 0)) then return end
    if group == "Wooden" and (not uses or uses == 100)
            and LSHygiene.TF.isInOuthouseArea(square:getX(), square:getY()) then return end
    return {object=obj, square=square, front=front, sprite=name, group=group}
end
function Restroom.inspect(player, obj) return protected(inspect, player, obj) end

local function accessible(player, entry)
    local c = entry and (entry.care or entry)
    local exact = c and inspect(player, c.object)
    return exact and (not entry.object or entry.object == c.object)
        and exact.square == c.square and exact.front == c.front and exact.sprite == c.sprite and exact.group == c.group
        and player:getSquare() == c.front and safeHere(player, 8) or false
end
function Restroom.accessible(player, entry) return protected(accessible, player, entry) == true end

local function idle(player)
    local queue = ISTimedActionQueue.getTimedActionQueue(player).queue
    return not queue[1] and not player:hasTimedActions() and player:getCharacterActions():isEmpty()
        and not ISTimedActionQueue.isPlayerDoingAction(player)
end
local function standing(player)
    return not player:getModData().IsDoingToilet and not LSUtil.isCharBusy(player)
        and not LSUtil.isCharSitting(player) and idle(player)
end

-- Read the option put there by the native builder, including its private ground
-- callback and best paper. No world-menu broadcast or real ISContextMenu (its
-- getNew registers UI with a global pool). A pre-existing object submenu is how
-- ToiletContextMenu itself appends to another mod's or the game's object menu.
local function optionSink()
    local sink = { options={} }
    function sink:addOption(name, target, callback, a,b,c,d,e,f)
        local o = {name=name,target=target,callback=callback,a=a,b=b,c=c,d=d,e=e,f=f}
        self.options[#self.options+1] = o
        return o
    end
    sink.addOptionOnTop = sink.addOption
    sink.getNew = optionSink
    function sink:addSubMenu(option, sub) option.subOption = sub end
    function sink:getSubMenu(sub) return sub end
    return sink
end

local function wipeAllowed(player, item)
    if not item then return true end -- no paper is legal
    local container = item:getContainer()
    if not container or not container:contains(item) then return false end
    if container:isInCharacterInventory(player) then return true end
    local outer = container:getOutermostContainer() or container
    local obj = outer:getParent()
    if obj and instanceof(obj, "IsoThumpable") and obj:isLockedToCharacter(player) then return false end
    local part = Storage.partFor(container)
    if part then return Storage.vehicleAccessible(player, part) end
    local world = item:getWorldItem()
    local square = (world and world:getSquare()) or (obj and obj:getSquare()) or outer:getSourceGrid()
    local here = player:getSquare()
    return Storage.permitted(player, square) and here and here:getZ() == square:getZ()
        and math.abs(here:getX()-square:getX()) <= 1 and math.abs(here:getY()-square:getY()) <= 1
        and Storage.containerReachable(player, container, here == square or here:canReachTo(square))
end

-- Bind receipts to the actual instance emitted by the stock click. A seated
-- toilet is created immediately but delivered later by ActionHelper.onRestPathFound;
-- its ISPathFindAction.onCompleteArgs[3] is exactly that not-yet-queued instance.
local pending = {}
local function snapshot(player)
    local value, raw, doing = read(player)
    if not value or value < 0.2 or raw <= 0 or doing then return end
    local before = {player=player, raw=raw}
    pending[player] = before
    return before
end
function Restroom.snapshot(player) return protected(snapshot, player) end
-- Observe just this already selected action; original callbacks run once, with
-- their native arguments and return values. A panic accident or another action
-- can also zero bathroomNeed: only the transition INSIDE this update counts.
local function watch(player, before, action)
    if type(action.update) ~= "function" or type(action.perform) ~= "function" then return end
    before.action = action
    local update, perform = action.update, action.perform
    action.update = function(self, ...)
        local d = player:getModData()
        local from = d.IsDoingToilet and d.bathroomNeed
        local result = update(self, ...)
        if from and from > 0 and d.bathroomNeed <= 0 and not self.wasDisturbedBy then before.drained=true end
        return result
    end
    action.perform = function(self, ...)
        local d = player:getModData()
        local empty = d.IsDoingToilet and d.bathroomNeed <= 0 and not self.wasDisturbedBy
        local result = perform(self, ...)
        before.finished = empty and not d.IsDoingToilet
        return result
    end
end
local function dispatch(player, opt, kind, fixture)
    local before = pending[player]
    pending[player] = nil
    -- The installed menu gives nil on success. Actual additions, not its return
    -- value, acknowledge the request. Never call twice if a nested callback fails.
    pcall(opt.callback, opt.target, opt.a,opt.b,opt.c,opt.d,opt.e,opt.f)
    local q = ISTimedActionQueue.getTimedActionQueue(player).queue
    if before and not before.action then
        for _, queued in ipairs(q) do
            local action = queued
            if queued.Type == "ISPathFindAction" and queued.goal and queued.goal[1] == "SitOnFurniture"
                    and queued.goal[2] == fixture and queued.onCompleteArgs then action = queued.onCompleteArgs[3] end
            if action and action.character == player and action.Type == kind
                    and (not fixture or action.toiletObject == fixture) then watch(player, before, action); break end
        end
    end
    -- Even partial dispatch can leave a real walk. Caller must wait and resolve
    -- that attempt via receipt/rejection rather than issuing a second native click.
    return q[1] ~= nil
end

local function queueToilet(player, entry)
    if need(player) <= 0 or not standing(player) or not accessible(player,entry) then return false end
    local c = entry.care or entry
    local _, label = LSUtil.getObjTexAndText(c.sprite)
    if not label then return false end
    local menu, sink = optionSink(), optionSink()
    menu:addSubMenu(menu:addOption(label), sink)
    ToiletContextMenu.doBuildMenu(player:getPlayerNum(), menu, {c.object}, c.object, c.sprite,"Toilet",c.group)
    for _, o in ipairs(sink.options) do
        if o.name == getText("ContextMenu_Toilet_Use") and not o.notAvailable and not o.isDisabled
                and o.callback == ToiletContextMenu.onAction and o.target == player
                and o.a == c.object and o.b == c.group and o.c == c.sprite and type(o.e) == "table"
                and (o.f == "IsUse" or o.f == "IsFlushAndUse") and wipeAllowed(player, o.e[4]) then
            return dispatch(player,o,"LSUseToilet",c.object)
        end
    end
    return false
end
function Restroom.queueToilet(player, entry) return protected(queueToilet,player,entry) == true end

local function queueGround(player)
    if not groundAllowed(player) or not standing(player) or not player:getSquare():canStand() then return false end
    local menu, world = optionSink(), {}
    ToiletGroundContextMenu.doBuildMenu(player:getPlayerNum(), menu, world)
    for _, o in ipairs(menu.options) do
        if o.name == getText("ContextMenu_Toilet_Ground") and not o.notAvailable and not o.isDisabled
                and type(o.callback) == "function" and o.target == world and o.a == player and wipeAllowed(player,o.b) then
            return dispatch(player,o,"LSUseToiletGround")
        end
    end
    return false
end
function Restroom.queueGround(player) return protected(queueGround, player) == true end

local function receipt(player, before)
    if not before or before.player ~= player or not before.action or before.action.wasDisturbedBy then return false end
    local _, raw, doing = read(player)
    -- The native second may fall between our ticks. A tiny new need after
    -- flushing is harmless; never credit only a lower moodle or an empty queue.
    return before.drained == true and before.finished == true and raw and raw < before.raw
        and not doing and idle(player)
end
function Restroom.receipt(player, before) return protected(receipt, player, before) == true end
return Restroom
