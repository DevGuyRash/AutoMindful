-- Build 42's Kahlua exposes pairs, but no global next.
next = nil
local runtime = "mods/AutoMindful/common/media/lua/client/"
package.path = runtime .. "?.lua;" .. package.path
package.loaded["AutoMindful/WaterSources"] = {scan=function() return {} end, choose=function() return nil end}
for _, name in ipairs({"TimedActions/ISTimedActionQueue", "TimedActions/ISReadABook", "TimedActions/ISDrinkFluidAction", "TimedActions/ISWaitWhileGettingUp", "ISUI/ISWorldObjectContextMenu", "ISUI/ISInventoryPaneContextMenu", "TimedActions/ISInventoryTransferUtil", "TimedActions/ISBaseTimedAction", "TimedActions/ISDropWorldItemAction", "Fluids/ISFluidContainer", "Fluids/ISFluidUtil", "Fluids/ISFluidTransferAction"}) do
    package.preload[name] = function() return true end
end
package.preload["Vehicles/TimedActions/ISPathFindAction"] = function() return true end
package.preload["TimedActions/WalkToTimedAction"] = function() return true end
for _, name in ipairs({"ISApplyBandage", "ISRemoveGlass", "ISRemoveBullet", "ISDisinfect", "ISStitch", "ISSplint", "ISCleanBurn", "ISComfreyCataplasm", "ISGarlicCataplasm", "ISPlantainCataplasm"}) do
    package.preload["TimedActions/" .. name] = function() return true end
end
package.preload["TimedActions/ISQueueActionsAction"] = function() return true end
local roaming = {enabled=false, radius=10}
-- Recovery's waiting times have their own test; here every mechanism is on and
-- prompt so a journey shows what it does rather than when.
local on = function() return true end
package.loaded["AutoMindful/Options"] = {awayMs=function() return 180000 end,careBetween=function() return false end,firstAid=on,refill=function() return false end,
    useBeds=function() return false end,cookMeals=function() return false end,makeSoup=function() return false end,rottenRecipes=function() return false end,cookTraining=function() return "off" end,dietGoal=function() return "balanced" end,lastResort=function() return false end,alertSound=on,resumeRecovery=on,cyclePolicy=function() return "alternate" end,searchNearby=function() return roaming.enabled end,
    searchRadius=function() return roaming.radius end}
local nearbyTarget, nearbyArea
package.loaded["AutoMindful/Nearby"] = {find=function(_, _, _, _, rejected)
    local target=nearbyTarget
    while target and rejected and rejected[target.key] do target=target.next end
    return target
end,
    scan=function() return nearbyArea end, invalidate=function() end,
    waterObject=function(_, target) return target.object:getMasterObject() end}
local T = {now = 0, nights = 50, client = false, sleepNeeded = true, sleepAllowed = true}
local FluidFixtures = loadTest and loadTest("fluid_fixtures.lua") or assert(loadfile("tests/fluid_fixtures.lua"))()
FluidCategory = FluidFixtures.categories
AutoMindfulTest = T
CharacterStat = {HUNGER="HUNGER", THIRST="THIRST", BOREDOM="BOREDOM", ENDURANCE="ENDURANCE", FATIGUE="FATIGUE", PAIN="PAIN", PANIC="PANIC"}
CharacterTrait = {ILLITERATE="illiterate", DISCIPLINED="disciplined", COUCHPOTATO="couchpotato"}
ItemTag = {UNINTERESTING="uninteresting", PICTUREBOOK="picturebook", PICTURE="picture"}
MoodleType = {FOOD_EATEN="food", PAIN="pain", HUNGRY="hungry", THIRST="thirst", PANIC="panic", NOXIOUS_SMELL="smell"}
Perks = {Meditation={
    getXpForLevel=function() return 100 end,
    getTotalXpForLevel=function(_, level) return level*100 end,
}, Fitness="Fitness", Nimble="Nimble"}
Fluid = {Water="Water"}
SkillBook = {Cooking=true}
SandboxVars = {Yoga={KeepBags=true}, Meditation={KeepBags=true}, LSMeditation={RemoveLevitation=false}}
Events = {}
for _, name in ipairs({"OnPlayerUpdate", "OnPlayerDeath", "OnGameStart", "OnTickEvenPaused"}) do Events[name] = {Add=function(callback) Events[name].callback=callback end} end
function getTimestampMs() return T.now end
function getGameTime() return {getNightsSurvived=function() return T.nights end} end
HaloTextHelper = {addBadText=function(player,text) player.halos[#player.halos+1]=text end}
package.preload["AutoMindful/CompletionHUD"] = function()
    PZActionCompletionHUD = {
        show=function(slot, card)
            assert(slot == T.player:getPlayerNum(), "Completion card must use the survivor's local slot")
            -- A request for help is not the end of a session.
            local list = card.title == "Autopilot needs you" and "alerts" or "cards"
            T.player[list][#T.player[list]+1] = card
        end,
        duration=function(seconds) return string.format("%ds", math.floor(seconds)) end,
    }
    return PZActionCompletionHUD
end
function isClient() return T.client end
function getServerOptions() return {getBoolean=function(_, key) return key == "SleepNeeded" and T.sleepNeeded or key == "SleepAllowed" and T.sleepAllowed end} end
function getText(key) return key end
function instanceof(item, kind)
    if not item then return false end
    if kind=="InventoryItem" then return item.kind=="InventoryItem" or item.kind=="Water" or item.kind=="Food" or item.kind=="Literature" or item.kind=="InventoryContainer" end
    if kind=="IsoObject" then return item.kind=="IsoWorldInventoryObject" end
    return item.kind == kind
end
function getPlayerInventory() return T.player and T.player.inventoryPage end
function getPlayerLoot() return T.player and T.player.lootPage end
function getPlayerContextMenu()
    local p=T.player
    if not p then return nil end
    local options=p.contextOptions or {{name="Inspect"}}
    return {options=options,numOptions=#options+1,isVisible=function() return p.contextOpen or false end,
        isReallyVisible=function() return p.contextOpen and not p.contextHidden or false end}
end
function getSpecificPlayer() return T.player end
function T.list(items)
    return {size=function() return #items end, get=function(_, index) return items[index+1] end, isEmpty=function() return #items == 0 end, contains=function(_, value) for _, item in ipairs(items) do if item == value then return true end end return false end}
end
function T.square(x,y,z)
    local square = {x=x or 0,y=y or 0,z=z or 0}
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:canReachTo(other) return not other.blocked and self.z==other:getZ() and math.abs(self.x-other:getX())<=1 and math.abs(self.y-other:getY())<=1 end
    return square
end
function T.container(x, y)
    local c = {items={},square=T.square(x,y)}
    function c:getItems() return T.list(self.items) end
    function c:getOutermostContainer() return self.root or self end
    function c:getType() return self.floor and "floor" or "container" end
    function c:hasRoomFor() return not self.full end
    function c:getSourceGrid() return self.square end
    function c:getContainingItem() return self.containingItem end
    function c:getItemById(id)
        for _, item in ipairs(self.items) do
            if item:getID()==id then return item end
            local nested = item.kind == "InventoryContainer" and item:getInventory()
            local found = nested and nested:getItemById(id)
            if found then return found end
        end
    end
    function c:contains(item) for _, candidate in ipairs(self.items) do if candidate==item then return true end end return false end
    return c
end

local nextID = 0
function T.item(kind, properties)
    nextID = nextID + 1
    local i = properties or {}
    i.kind, i.id, i.tags, i.data = kind, nextID, i.tags or {}, i.data or {}
    function i:getID() return self.id end
    function i:getFullType() return self.fullType or ("Base."..self.kind) end
    function i:getModule() return "Base" end
    function i:getOpeningRecipe() return self.openingRecipe end
    function i:getReplaceOnUseFullType() return self.replace end
    function i:getBaseHunger() return self.baseHunger or -0.5 end
    function i:getHungChange() return self:getHungerChange() end
    function i:getThirstChange() return self.thirst or 0 end
    function i:isWorn() return self.worn or false end
    function i:getScriptItem() return {isCantEat=function() return self.cantEat or false end} end
    function i:getContainer() return self.container end
    function i:getInventory() return self.inventory end
    function i:getWorldItem() return self.world end
    function i:getDisplayName() return self.name or self.kind end
    function i:getBoredomChange() return self.boredom or (self.kind == "Literature" and -20 or 0) end
    function i:getHungerChange() return self.hunger or -0.5 end
    function i:getCalories() return self.calories or 1000 end
    function i:getSkillTrained() return self.skill end
    function i:hasTag(tag) return self.tags[tag] end
    function i:hasModData() for _ in pairs(self.data) do return true end return false end
    function i:getModData() return self.data end
    function i:getFluidContainer() return self.fluid end
    function i:getRequireInHandOrInventory() return nil end
    for method, property in pairs({isRotten="rotten", isBurnt="burnt", isFrozen="frozen", isTainted="tainted", isPoison="poison", isAlcoholic="alcohol", isSealed="sealed", isbDangerousUncooked="rawDanger", isCooked="cooked"}) do
        i[method] = function(self) return self[property] or false end
    end
    function i:getPoisonPower() return self.poisonPower or 0 end
    function i:getFoodSicknessChange() return self.sickness or 0 end
    function i:getOnEat() return self.onEat end
    function i:getAge() return self.age or 0 end
    function i:getOffAgeMax() return self.rotsAt or 1000000000 end
    return i
end
function T.water(properties)
    local p = properties or {}
    local f = {amount=1, hungerRate=p.hunger or 0, thirstRate=p.thirst or -.5, calorieRate=p.calories or 0,
        components={{fluid=FluidFixtures.component({poisonous=p.poison,alcohol=p.alcohol and 1 or 0,sickness=p.sickness}),percentage=1}}}
    function f:isEmpty() return self.amount <= 0 end
    function f:canPlayerEmpty() return not p.locked end
    function f:getCapacity() return p.capacity or 1 end
    function f:getAmount() return self.amount end
    function f:isPureFluid() return not p.mixed end
    function f:isPoisonous() return p.poison or false end
    function f:isTainted() return p.tainted or false end
    function f:getProperties() return {
        getHungerChange=function() return f.hungerRate*f.amount end,
        getThirstChange=function() return f.thirstRate*f.amount end,
        getCalories=function() return f.calorieRate*f.amount end,
        getPoison=function() return p.poison and 1 or 0 end,
        getFoodSicknessChange=function() return p.sickness or 0 end,
        getAlcohol=function() return p.alcohol and 1 or 0 end,
    } end
    local item=T.item("Water", {fluid=f,worn=p.worn})
    f.owner=item
    FluidFixtures.attach(f,nil,function(current) return current.components end)
    return item
end
function T.remove(container,item)
    for index, candidate in ipairs(container.items) do if candidate==item then table.remove(container.items,index); item.container=nil; return end end
end
function T.world(square)
    return {getSquare=function() return square end,getOffX=function() return .4 end,
        getOffY=function() return .6 end,getOffZ=function() return 0 end,getFluidContainer=function() return nil end}
end

function T.add(container, item)
    container.items[#container.items+1] = item
    item.container = container
    if container.floor then
        item.world = item.world or T.world(container.square)
        item.world:getSquare().floorContainer = container
    else
        if item.world and item.world:getFluidContainer() then item.fluid=item.world:getFluidContainer() end
        item.world=nil
    end
    return item
end
-- The native cell resolves coordinates, not the previous IsoGridSquare
-- userdata. Keep mock worlds independent, even though most fixtures use 0,0,0.
local function squareKey(x,y,z) return x .. ":" .. y .. ":" .. z end
function T.loadSquare(player, square)
    player.loadedSquares[squareKey(square:getX(),square:getY(),square:getZ())] = square
end
function getCell()
    return {getGridSquare=function(_,x,y,z)
        return T.player and T.player.loadedSquares[squareKey(x,y,z)]
    end}
end
function T.playerNew()
    local p = {inventory=T.container(), values={HUNGER=0.05, THIRST=0, BOREDOM=0, ENDURANCE=1, FATIGUE=0, PAIN=0, PANIC=0}, meditation=0, xp=0, yoga={0,0,100}, hours=10, calories=2000, read={}, printRead={}, history={}, traits={}}
    p.loadedSquares = {}
    T.loadSquare(p,p.inventory:getSourceGrid())
    p.halos, p.cards, p.alerts = {}, {}, {}
    p.inventoryPage={}
    p.lootPage={refreshBackpacks=function()
        p.refreshCount=(p.refreshCount or 0)+1
        if p.available then
            p.nearby={}
            for _,container in ipairs(p.available) do
                if p:getSquare():canReachTo(container:getSourceGrid()) then p.nearby[#p.nearby+1]=container end
            end
        end
    end}
    p.data = {LSMoodles={Embarrassed={Value=0,Level=0}, MindfulState={Value=0,Level=0}, WasTaughtSkill={Value=0,Level=0}, Zen={Value=0,Level=0}}}
    function p:getModData() return self.data end
    function p:getInventory() return self.inventory end
    function p:isLocalPlayer() return true end
    function p:getPlayerNum() return self.slot or 0 end
    function p:getStats() return {get=function(_, name) return p.values[name] or 0 end, getNumVisibleZombies=function() return p.zombies or 0 end, getNumChasingZombies=function() return p.chasing or 0 end, getNumVeryCloseZombies=function() return 0 end} end
    function p:getBodyDamage() return {getOverallBodyHealth=function() return 100 end, getNumPartsBleeding=function() return 0 end} end
    function p:getNutrition() return {getCalories=function() return p.calories end} end
    function p:getMoodles() return {getMoodleLevel=function(_, kind) return kind == "pain" and p.painMoodle or kind == "food" and p.foodMoodle or kind == "hungry" and p.hungerMoodle or kind == "thirst" and p.thirstMoodle or kind == "panic" and p.panicMoodle or kind == "smell" and p.smellMoodle or 0 end} end
    function p:getPerkLevel(perk) return perk == Perks.Meditation and self.meditation or 0 end
    function p:getXp() return {getXP=function() return p.xp end} end
    function p:getHoursSurvived() return self.hours end
    function p:getLastHourSleeped() return 0 end
    function p:getSquare() return self.square or self.inventory:getSourceGrid() end
    function p:getX() return self.x or self:getSquare():getX()+0.5 end
    function p:getY() return self.y or self:getSquare():getY()+0.5 end
    function p:getZ() return self:getSquare():getZ() end
    function p:isRunning() return self.running or false end
    function p:isSprinting() return self.sprinting or false end
    function p:isSitOnGround() return self.sitting or false end
    function p:isSitting() return self.sitting or false end
    function p:reportEvent(event) self.postureEvents=(self.postureEvents or 0)+1; self.sitting = event ~= "EventGetUp" end
    function p:setVariable() end
    function p:getVariableBoolean(name,default) return name=="ExerciseEnded" end
    function p:getSleepingTabletEffect() return 0 end
    function p:tooDarkToRead() return self.dark or false end
    function p:hasTrait(trait) return self.traits[trait] end
    function p:getReadLiterature() return {get=function(_,title) local value=p.read[title]; return value==true and T.nights or value end} end
    function p:isLiteratureRead(title)
        local last=self.read[title]
        return last==true or (type(last)=="number" and T.nights < last+(SandboxVars.LiteratureCooldown or 45))
    end
    function p:getReadPrintMedia() local ids={} for id in pairs(self.printRead) do ids[#ids+1]=id end return T.list(ids) end
    function p:hasTimedActions() return #ISTimedActionQueue.getTimedActionQueue(self).queue > 0 end
    function p:getCharacterActions()
        local function values()
            local result={}
            if p.nativeHead then result[#result+1]=p.nativeHead end
            for _,action in ipairs(p.nativeAdditional or {}) do result[#result+1]=action end
            return result
        end
        return {size=function() return #values() end,
            isEmpty=function() return #values()==0 end,
            contains=function(_, action) for _,entry in ipairs(values()) do if entry==action then return true end end return false end,
            get=function(_, index) return values()[index+1] end}
    end
    function p:isPlayerDoingAction() return not self:getCharacterActions():isEmpty() end
    function p:StopAllActionQueue()
        local native=self.nativeHead
        if native and native.forceStop then native:forceStop() end
        self.nativeHead=nil
        self.nativeAdditional=nil
    end
    function p:isDead() return self.dead or false end
    function p:isOnFire() return false end
    function p:getVehicle() return nil end
    function p:isPlayerMoving() return self.moving or false end
    function p:pressedMovement(ignoreAnimationBlock) return self.movementInput or (ignoreAnimationBlock and self.rawMovementInput) or false end
    function p:pressedCancelAction() return self.cancelInput or false end
    function p:isAiming() return self.aiming or false end
    function p:pressedAim() return self.aimInput or false end
    function p:isAttacking() return self.attacking or false end
    function p:isDraggingCorpse() return false end
    function p:isAsleep() return self.asleep or false end
    function p:isSittingOnFurniture() return self.furniture or false end
    T.player = p
    return p
end
ISTimedActionQueue = {queues={}}
function ISTimedActionQueue.isPlayerDoingAction(player) return not player:getCharacterActions():isEmpty() end
function ISTimedActionQueue.getTimedActionQueue(player)
    if not ISTimedActionQueue.queues[player] then
        local q = {queue={}}
        function q:removeFromQueue(action) for index, entry in ipairs(self.queue) do if entry == action then action.removes=(action.removes or 0)+1; table.remove(self.queue,index) return end end end
        function q:onCompleted(action)
            self:removeFromQueue(action)
            if self.current==action then self.current=nil end
            local head=self.queue[1]
            if head and self.current~=head then self.current=head; head:begin() end
        end
        function q:resetQueue() self.queue={}; self.current=nil end
        function q:clearQueue() self.queue={}; self.current=nil end
        function q:isCurrentActionAddingOtherActions() return false end
        ISTimedActionQueue.queues[player] = q
    end
    return ISTimedActionQueue.queues[player]
end
function ISTimedActionQueue.add(action)
    if not action.ignoreAction then
        local q = ISTimedActionQueue.getTimedActionQueue(action.character)
        action.adds=(action.adds or 0)+1
        q.queue[#q.queue+1] = action
        action.character.history[#action.character.history+1] = action.Type
        if #q.queue==1 then q.current=action; action:begin() end
    end
end
function ISTimedActionQueue.clear(player)
    player:StopAllActionQueue()
    ISTimedActionQueue.getTimedActionQueue(player):clearQueue()
end
function T.action(player, kind, effect)
    local a = {character=player, Type=kind, effect=effect}
    function a:perform()
        if self.effect then self.effect() end
        if self.character.nativeHead==self.action then self.character.nativeHead=nil end
        ISTimedActionQueue.getTimedActionQueue(self.character):onCompleted(self)
    end
    function a:stop()
        if self.onStop then self:onStop() end
        self.stopped=true
        if self.character.nativeHead==self.action then self.character.nativeHead=nil end
        ISTimedActionQueue.getTimedActionQueue(self.character):resetQueue()
    end
    function a:forceCancel() self.cancelled=true end
    function a:isStarted() return self.action~=nil end
    function a:forceStop() if self.action then self.action:forceStop() end end
    function a:begin()
        self.begins=(self.begins or 0)+1
        self.action={forceStop=function() a.forceStopped=true; a:stop() end,
            forceComplete=function() a:perform() end}
        self.character.nativeHead=self.action
        if self.start then self:start() end
    end
    function a:isValid() return true end
    return a
end
FluidContainer = {CanTransfer=function(source,target)
    return source~=target and not source:isEmpty() and target:getFreeCapacity()>0 and not target:isInputLocked() and not target.reject
end}
ISFluidContainer = {new=function(_,fluid)
    return {getFluidObject=function() return fluid end,getFluidContainer=function() return fluid end,getOwner=function() return fluid:getOwner() end}
end}
ISFluidTransferAction = {new=function(_,player,source,sourceFluidObject,target,targetFluidObject,amount)
    local action=T.action(player,"ISFluidTransferAction",function()
        local from,to=source:getFluidContainer(),target:getFluidContainer()
        local moved=math.min(amount,from:getAmount(),to:getFreeCapacity())
        to.hungerRate,to.thirstRate,to.calorieRate=from.hungerRate,from.thirstRate,from.calorieRate
        to.components=from.components
        from.amount,to.amount=from.amount-moved,to.amount+moved
    end)
    action.source,action.target=source,target
    action.sourceFluidObject,action.targetFluidObject=sourceFluidObject,targetFluidObject
    function action:isValid() return FluidContainer.CanTransfer(sourceFluidObject,targetFluidObject) end
    return action
end}
ISReadABook = {new=function(_, p, item) return T.action(p,"read",function()
    if not p.refuseCare then
        p.values.BOREDOM=math.max(0,p.values.BOREDOM+item:getBoredomChange())
        if item.data.literatureTitle then p.read[item.data.literatureTitle]=T.nights end
    end
end) end}
ISDrinkFluidAction = {new=function(_, p, item, percentage)
    p.drinkPercentage = percentage
    local a=T.action(p,"drink",function()
        if not p.refuseCare then
            local properties=item.fluid:getProperties()
            p.values.THIRST=math.max(0,p.values.THIRST+properties:getThirstChange()*percentage)
            p.values.HUNGER=math.max(-0.1,p.values.HUNGER+properties:getHungerChange()*percentage)
            p.calories=p.calories+properties:getCalories()*percentage
            item.fluid.amount=item.fluid.amount*(1-percentage)
        end
    end)
    a.item,a.fluidContainer=item,item.fluid
    return a
end}
ISEatFoodAction = {new=function(_,p,item,fraction)
    local a=T.action(p,"eat",function()
        if not p.refuseCare then
            local remaining=-item:getHungerChange()
            local eaten=math.min(remaining,-item:getBaseHunger()*fraction)
            local ratio=eaten/remaining
            p.values.HUNGER=math.max(-0.1,p.values.HUNGER-eaten)
            p.values.THIRST=math.max(0,p.values.THIRST+item:getThirstChange()*ratio)
            p.calories=p.calories+item:getCalories()*ratio
            item.hunger=-(remaining-eaten)
            item.calories=item:getCalories()*(1-ratio)
            if item.hunger >= -0.000001 then
                T.remove(item:getContainer(),item)
                if item.replace then T.add(p.inventory,T.item("InventoryItem",{fullType=item.replace})) end
            end
        end
    end)
    a.item=item
    return a
end}
ISWaitWhileGettingUp = {new=function(_, p) return T.action(p,"stand",function() p.sitting=false; p.furniture=false end) end}
ISWearClothing = {new=function(_,p) return T.action(p,"wear") end}
ISWorldObjectContextMenu = {onSleepWalkToComplete=function() T.player.asleep=true end}
ISInventoryPaneContextMenu = {
    getEatingMask=function() return nil end,
    getContainers=function(player)
        local all={player.inventory}
        for _, container in ipairs(player.nearby or {}) do all[#all+1]=container end
        return T.list(all)
    end,
}
ISInventoryTransferUtil = {newInventoryTransferAction=function(p,item,source,target)
    local action=T.action(p,"ISInventoryTransferAction",function() T.remove(source,item); T.add(target,item) end)
    function action:isValid() return not target.reject end
    return action
end}
ISDropWorldItemAction = {new=function(_,p,item,square)
    local action=T.action(p,"ISDropWorldItemAction",function()
        T.remove(p.inventory,item)
        item.world=T.world(square)
        T.add(assert(square.floorContainer),item)
    end)
    function action:isValid() return not square.full and p:getSquare():canReachTo(square) end
    return action
end}

HiddenSkills = {getSkill=function(p) return p.yoga end, getLevel=function(p) return p.yoga[1] end}
-- Display-name stand-ins for the two upstream practice classes.
LSMeditateAction, LSYogaAction = {Type="Meditation"}, {Type="Yoga"}
ZenWellnessContextMenu = {Options={}}
for _, kind in ipairs({"Yoga", "Meditation"}) do
    ZenWellnessContextMenu.Options[kind] = {
        canPerform=function(p)
            if kind == "Yoga" then
                if p.yogaBlocked then return true,p.yogaBlocked end
                if p.nativeYogaLimit and p.values.ENDURANCE <= p.nativeYogaLimit then return true,getText("Tooltip_Action_Exhausted") end
                return false
            end
            return p.values.BOREDOM > (p.nativeMeditationBoredomLimit or 30), " <RED>" .. getText("ContextMenu_Meditate_Bored")
        end,
        onAction=function(_, _, p)
            ISTimedActionQueue.add(T.action(p,kind,function()
                if not p.noXP then if kind == "Meditation" then p.meditation=math.min(10,p.meditation+1); p.xp=p.xp+1 else p.yoga[1]=math.min(10,p.yoga[1]+1); p.yoga[2]=p.yoga[2]+1 end end
                p.values.BOREDOM = kind == "Meditation" and p.values.BOREDOM+10 or math.max(0,p.values.BOREDOM-15)
            end))
        end,
    }
end
local C = require "AutoMindful/Controller"
T.controller = C
do
    local policy = require("AutoMindful/Presence").policy
    T.presencePolicy = {}
    for key, value in pairs(policy) do T.presencePolicy[key], policy[key] = value, key == "early" and 2000 or 0 end
end
function T.tick(p, finish, gameHours)
    T.now = T.now+1000
    p.hours = p.hours+(gameHours or 0.01)
    C.update(p)
    local action = ISTimedActionQueue.getTimedActionQueue(p).queue[1]
    if finish ~= false and action then
        if action:isValid() then action:perform() else action:stop() end
    end
end
function T.run(p, limit)
    for i=1,limit or 400 do
        T.tick(p)
        local status=C.status(p)
        if not status.active or status.mode=="recovery" then return status end
    end
    error("Automation did not terminate")
end
function T.check(condition, message) assert(condition,message) end
local passed = 0
local function test(name, fn) fn(); passed=passed+1; print("PASS "..name) end
local function hasHistory(p,kind) for _, entry in ipairs(p.history) do if entry == kind then return true end end return false end
T.hasHistory = hasHistory
if AutoMindfulContractHarnessOnly then return end

test("one terminal meditation card uses observed XP, elapsed time, and the local survivor slot",function()
    local p=T.playerNew(); p.slot=1; p.meditation=9; p.xp=912; p.sitting=true
    assert(C.start(p,"meditation",false)); T.tick(p)
    assert(#p.cards==0 and C.status(p).active, "A finished native action is not a finished Second Nature session")
    T.tick(p)
    assert(C.status(p).mode=="recovery" and C.status(p).active and #p.cards==1 and #p.halos==0)
    local card=p.cards[1]
    assert(card.brand=="SECOND NATURE" and card.theme=="mindful")
    assert(card.title=="Meditation session complete" and card.detail=="2s | +1 Meditation XP")
    C.update(p); C.stop(p)
    assert(#p.cards==1, "Repeated terminal events must not generate another card")
end)
test("stopped session detail uses a font-safe ASCII separator",function()
    local p=T.playerNew(); p.sitting=true
    assert(C.start(p,"meditation",false)); T.tick(p,false)
    p.xp=p.xp+91; T.now=T.now+475000
    C.stop(p,"Stopped by you.")
    local card=p.cards[1]
    assert(card.status=="stopped" and card.detail=="476s | +91 Meditation XP")
    assert(not card.detail:find("[^%z\1-\127]"), "Duration and XP separator must be ASCII")
end)

test("yoga level caps use level changes when XP is not recoverable",function()
    local p=T.playerNew(); p.yoga={9,97,100}
    assert(C.start(p,"yoga",false)); assert(T.run(p,5).mode=="recovery")
    assert(#p.cards==1 and p.cards[1].title=="Yoga session complete")
    assert(p.cards[1].detail:find("Yoga level 9 → 10",1,true) and not p.cards[1].detail:find("XP",1,true))
end)
test("stopping does not invent XP and idle, rejected, or already-capped requests do not show cards",function()
    local p=T.playerNew()
    C.stop(p); assert(not C.start(p,"invalid",false)); C.update(p)
    p.meditation=10
    assert(C.start(p,"meditation",false)); T.tick(p)
    assert(C.status(p).active and C.status(p).backgroundPractice and #p.cards==0)
    C.stop(p)
    assert(#p.cards==0)
    p.meditation=0; p.sitting=true; p.noXP=true
    assert(C.start(p,"meditation",false)); T.tick(p)
    C.stop(p,"Stopped by you."); C.stop(p)
    local card=p.cards[1]
    assert(#p.cards==1 and #p.halos==0 and card.title=="Meditation session stopped")
    assert(card.detail=="1s" and card.note=="Stopped by you.")
end)
test("both targets reach 10 with model provisions and native boundary actions",function()
    local p=T.playerNew(); p.values.BOREDOM=40; p.values.HUNGER=0.25; p.values.THIRST=0.25
    T.add(p.inventory,T.item("Food")); T.add(p.inventory,T.water())
    for i=1,20 do T.add(p.inventory,T.item("Literature")) end
    assert(C.start(p,"both",false)); local s=T.run(p)
    assert(s.mode == "recovery" and s.active and s.meditation == 10 and s.yoga == 10)
    assert(#p.cards==1 and p.cards[1].title=="Training session complete")
    assert(hasHistory(p,"read") and hasHistory(p,"eat") and hasHistory(p,"drink"))
end)
test("single targets switch to Autopilot at 10 and leave the other skill unchanged",function()
    for _, mode in ipairs({"yoga","meditation"}) do
        local p=T.playerNew(); for i=1,20 do T.add(p.inventory,T.item("Literature")) end
        assert(C.start(p,mode,false)); local s=T.run(p)
        assert(s.mode == "recovery" and s.active)
        assert(mode == "yoga" and s.yoga == 10 and s.meditation == 0 or mode == "meditation" and s.meditation == 10 and s.yoga == 0)
    end
end)
test("low stamina allows meditation and does not interrupt its running action",function()
    for _,mode in ipairs({"meditation","both"}) do
        local p=T.playerNew(); p.values.ENDURANCE=.1; p.nativeYogaLimit=.6
        assert(C.start(p,mode,false)); T.tick(p,false); T.tick(p,false)
        local action=ISTimedActionQueue.getTimedActionQueue(p).queue[1]
        assert(action and action.Type=="Meditation" and C.status(p).phase=="meditation")
        p.values.ENDURANCE=.05
        for i=1,5 do T.tick(p,false) end
        assert(C.status(p).active and ISTimedActionQueue.getTimedActionQueue(p).queue[1]==action and not action.stopped)
        assert(not hasHistory(p,"Yoga"),"Yoga must not take over while stamina is recovering")
        C.stop(p)
    end
end)
test("yoga honors each Lifestyle stamina mode without the former extra 85 percent admission minimum",function()
    for _,rule in ipairs({{.8,.81},{.6,.61},{.3,.31},{false,.08}}) do
        local p=T.playerNew(); p.nativeYogaLimit=rule[1]; p.values.ENDURANCE=rule[2]
        p.values.PAIN=55; p.values.STRESS=1; p.values.BOREDOM=65
        assert(C.start(p,"yoga",false)); T.tick(p,false)
        local q=ISTimedActionQueue.getTimedActionQueue(p)
        assert(q.queue[1] and q.queue[1].Type=="Yoga", "Do not invent an exhaustion/pain/stress/boredom requirement")
        C.stop(p)
    end
end)
test("yoga rests at the actual Lifestyle threshold and starts once the gate opens",function()
    local p=T.playerNew(); p.values.ENDURANCE=.6; p.nativeYogaLimit=.6
    assert(C.start(p,"yoga",false)); T.tick(p,false); T.tick(p,false)
    assert(C.status(p).active and C.status(p).phase=="resting" and C.status(p).message:find("Lifestyle",1,true))
    assert(not hasHistory(p,"Yoga") and not hasHistory(p,"Meditation"))
    p.values.ENDURANCE=.61; T.tick(p); T.tick(p,false)
    assert(C.status(p).active and hasHistory(p,"Yoga") and not hasHistory(p,"Meditation"))
    C.stop(p)
end)
test("low stamina does not cut off permitted yoga; critical thirst still takes priority",function()
    local p=T.playerNew(); p.nativeYogaLimit=.6
    assert(C.start(p,"yoga",false)); T.tick(p,false)
    local q=ISTimedActionQueue.getTimedActionQueue(p)
    local yoga=q.queue[1]; assert(yoga and yoga.Type=="Yoga")
    p.values.ENDURANCE=.03
    for _=1,3 do T.tick(p,false) end
    assert(q.queue[1]==yoga and C.status(p).phase=="yoga" and not yoga.stopped)
    p.values.THIRST=.9; p.thirstMoodle=4; T.tick(p,false)
    assert(C.status(p).phase=="care" and yoga.stopped)
    T.tick(p,false)
    assert(C.status(p).active and not q.queue[1] and C.status(p).message:find("Dying of Thirst",1,true))
    C.stop(p)
end)
test("Lifestyle mat and embarrassment requirements still govern yoga",function()
    for _,reason in ipairs({"Tooltip_Yoga_MissingMat","ContextMenu_Embarrassed"}) do
        local p=T.playerNew(); p.yogaBlocked=getText(reason)
        assert(C.start(p,"yoga",false)); T.tick(p,false); T.tick(p,false)
        assert(not hasHistory(p,"Yoga"))
        if reason=="Tooltip_Yoga_MissingMat" then
            assert(not C.status(p).active and C.status(p).message==getText(reason))
        else
            assert(C.status(p).active and C.status(p).phase=="recovering")
            p.yogaBlocked=nil; T.tick(p); T.tick(p,false)
            assert(C.status(p).active and hasHistory(p,"Yoga")); C.stop(p)
        end
    end
end)
test("both mode can recover for yoga when boredom and stamina block both activities",function()
    local p=T.playerNew(); p.values.ENDURANCE=.1; p.values.BOREDOM=40; p.nativeYogaLimit=.6
    assert(C.start(p,"both",false)); T.tick(p,false); T.tick(p,false)
    assert(C.status(p).active and C.status(p).phase=="resting")
    assert(not hasHistory(p,"Yoga") and not hasHistory(p,"Meditation"))
    p.values.ENDURANCE=.61; T.tick(p); T.tick(p,false)
    assert(C.status(p).active and hasHistory(p,"Yoga"))
    C.stop(p)
end)
test("missing drink stock is not a start gate at ordinary thirst",function()
    local p=T.playerNew(); p.values.THIRST=0.3; assert(C.start(p,"both",false))
    T.tick(p); T.tick(p,false)
    assert(C.status(p).active and hasHistory(p,"Meditation") and C.status(p).careNotice)
    C.stop(p)
end)
test("empty food and drink reserves allow mild needs and low calories without interrupting an allowed session",function()
    for _, mode in ipairs({"yoga","meditation"}) do
        local p=T.playerNew(); p.values.HUNGER=.3; p.values.THIRST=.3; p.calories=100
        p.values.BOREDOM=20; p.yogaBlocked=mode=="meditation" and "mat" or nil
        assert(C.start(p,mode,false)); T.tick(p,false)
        if mode=="meditation" then T.tick(p,false) end
        local action=ISTimedActionQueue.getTimedActionQueue(p).queue[1]
        assert(action and C.status(p).active and C.status(p).careNotice)
        for i=1,4 do T.tick(p,false) end
        assert(C.status(p).active and ISTimedActionQueue.getTimedActionQueue(p).queue[1]==action and not action.stopped,
            "Optional care without usable stock must not repeatedly interrupt native training")
        C.stop(p)
    end
end)
test("native maximum hunger and thirst pause the objective while missing a safe supply",function()
    for _, kind in ipairs({"food","water"}) do
        local p=T.playerNew()
        if kind=="food" then p.values.HUNGER=.8; p.hungerMoodle=4 else p.values.THIRST=.9; p.thirstMoodle=4 end
        assert(C.start(p,"yoga",false)); T.tick(p,false)
        assert(C.status(p).active and not hasHistory(p,"Yoga"))
        assert(C.status(p).message:find(kind=="food" and "Starving to Death" or "Dying of Thirst",1,true))
        C.stop(p)
    end
end)
test("boredom alone cannot cut short an already admitted meditation; native re-entry still blocks",function()
    local p=T.playerNew(); p.values.BOREDOM=20; p.yogaBlocked="mat"
    assert(C.start(p,"meditation",false)); T.tick(p,false); T.tick(p,false)
    local q=ISTimedActionQueue.getTimedActionQueue(p)
    local action=q.queue[1]; assert(action and action.Type=="Meditation")
    p.values.BOREDOM=31
    for _=1,3 do T.tick(p,false) end
    assert(C.status(p).active and q.queue[1]==action and not action.stopped)
    action:perform(); T.tick(p,false); T.tick(p,false)
    assert(not C.status(p).active and C.status(p).message:find("boredom is too high",1,true), "Only block the next admission")
end)
test("configured upstream meditation limit drives Both fallback rather than a copied constant",function()
    local p=T.playerNew(); p.values.BOREDOM=32; p.nativeMeditationBoredomLimit=45
    assert(C.start(p,"meditation",false)); T.tick(p,false); T.tick(p,false)
    local q=ISTimedActionQueue.getTimedActionQueue(p)
    assert(q.queue[1] and q.queue[1].Type=="Meditation", "Do not duplicate an upstream boredom number")
    C.stop(p)
    p=T.playerNew(); p.values.BOREDOM=19; p.nativeMeditationBoredomLimit=18
    assert(C.start(p,"both",false)); T.tick(p,false)
    assert(hasHistory(p,"Yoga") and not hasHistory(p,"Meditation"), "Native boredom blocker may trigger Yoga fallback at a different threshold")
    C.stop(p)
end)
test("meditation only stops at its blocker instead of training available yoga",function()
    for _,boredom in ipairs({20,40}) do
        local p=T.playerNew(); p.values.BOREDOM=boredom
        assert(C.start(p,"meditation",false)); local status=T.run(p)
        assert(not status.active and status.phase=="stopped" and status.message:find("boredom is too high",1,true))
        assert(not hasHistory(p,"Yoga") and p.yoga[1]==0,"Selecting meditation must never train yoga")
        if boredom==20 then assert(hasHistory(p,"Meditation")) end
    end
end)
test("critical hunger takes priority over ordinary thirst",function()
    local p=T.playerNew(); p.values.HUNGER=.7; p.hungerMoodle=4; p.values.THIRST=.2
    T.add(p.inventory,T.water()); T.add(p.inventory,T.item("Food"))
    assert(C.start(p,"meditation",false)); T.tick(p)
    assert(p.history[1]=="eat" and not hasHistory(p,"drink"))
    C.stop(p)
end)
test("milk care finishes residual thirst from plain water before resuming",function()
    local sources=require "AutoMindful/WaterSources"
    local scan,drink=sources.scan,sources.drink
    local p=T.playerNew(); p.values.HUNGER=.15; p.values.THIRST=.2
    local milk=T.add(p.inventory,T.water({hunger=-.5,thirst=-.5}))
    local water={object={},remainingLiters=20,directDrink=true,
        description={remainingLiters=20,hungerEffect=0,thirstEffect=10,hungerRelief=0,thirstRelief=10,food=false,water=true,calories=0}}
    function water.object:getFluidAmount() return water.remainingLiters end
    local drinks=0
    sources.scan=function() return {water} end
    sources.drink=function(player)
        ISTimedActionQueue.add(T.action(player,"world-drink",function()
            water.remainingLiters=water.remainingLiters-player.values.THIRST*2
            player.values.THIRST=0; drinks=drinks+1
        end))
        return true
    end
    assert(C.start(p,"meditation",true)); T.tick(p)
    assert(math.abs(milk.fluid.amount-.7)<.000001 and math.abs(p.values.THIRST-.05)<.000001)
    for i=1,5 do T.tick(p) end
    assert(drinks==1 and math.abs(water.remainingLiters-19.9)<.000001)
    assert(p.values.HUNGER==0 and p.values.THIRST==0 and hasHistory(p,"Meditation"))
    assert(math.abs(milk.fluid.amount-.7)<.000001,"Plain water should finish thirst after hunger is restored")
    assert(#p.cards==0, "Drinking and resuming must not emit a terminal card")
    C.stop(p); sources.scan,sources.drink=scan,drink
end)
test("paired care remembers hunger even when milk restores thirst first",function()
    local p=T.playerNew(); p.values.HUNGER=.2; p.values.THIRST=.15
    local milk=T.add(p.inventory,T.water({hunger=-.5,thirst=-.5}))
    local meal=T.add(p.inventory,T.item("Food",{hunger=-.6,baseHunger=-.6}))
    assert(C.start(p,"meditation",false)); T.tick(p)
    assert(math.abs(milk.fluid.amount-.7)<.000001 and math.abs(p.values.HUNGER-.05)<.000001)
    for i=1,5 do T.tick(p) end
    assert(math.abs(p.values.HUNGER)<.000001 and math.abs(p.values.THIRST)<.000001 and hasHistory(p,"eat") and hasHistory(p,"Meditation"))
    assert(math.abs(meal:getHungerChange()+.55)<.000001,"Food care must finish the .05 hunger left after the mixed drink")
    assert(math.abs(milk.fluid.amount-.7)<.000001,"The adequate plain food should preserve the remaining milk")
    C.stop(p)
end)
test("care finishes sub-one-percent residual hunger without consuming an extra item",function()
    local p=T.playerNew(); p.values.HUNGER=.155
    local first=T.add(p.inventory,T.item("Food",{hunger=-.15,baseHunger=-.15}))
    local last=T.add(p.inventory,T.item("Food",{hunger=-.02,baseHunger=-.04}))
    local spare=T.add(p.inventory,T.item("Food",{hunger=-.001,baseHunger=-.001}))
    assert(C.start(p,"meditation",false))
    for i=1,12 do T.tick(p); if hasHistory(p,"Meditation") then break end end
    assert(math.abs(p.values.HUNGER)<.000001 and hasHistory(p,"Meditation"))
    assert(not p.inventory:contains(first) and p.inventory:contains(last))
    assert(math.abs(last:getHungerChange()+.015)<.000001, "Final bite uses only .005 remaining hunger")
    assert(p.inventory:contains(spare) and spare:getHungerChange()==-.001)
    C.stop(p)
end)
test("care finishes sub-one-percent residual thirst without another bottle",function()
    local p=T.playerNew(); p.values.THIRST=.155
    local first=T.add(p.inventory,T.water({thirst=-.15}))
    local last=T.add(p.inventory,T.water({thirst=-.02}))
    local spare=T.add(p.inventory,T.water({thirst=-.001}))
    assert(C.start(p,"meditation",false))
    for i=1,12 do T.tick(p); if hasHistory(p,"Meditation") then break end end
    assert(math.abs(p.values.THIRST)<.000001 and hasHistory(p,"Meditation"))
    assert(first.fluid.amount<.000001 and math.abs(last.fluid.amount-.75)<.000001)
    assert(spare.fluid.amount==1, "No extra bottle after thirst reaches zero")
    C.stop(p)
end)

test("confirmed final portion does not chase new metabolism with extra sips",function()
    local p=T.playerNew(); p.values.THIRST=.155
    local bottle=T.add(p.inventory,T.water({thirst=-.5}))
    assert(C.start(p,"meditation",false))
    for i=1,8 do
        T.tick(p)
        p.values.THIRST=p.values.THIRST+.0001
        if hasHistory(p,"Meditation") then break end
    end
    local drinks=0; for _, action in ipairs(p.history) do if action=="drink" then drinks=drinks+1 end end
    assert(drinks==1 and hasHistory(p,"Meditation"), "Confirmed covering sip completes care despite small new metabolism")
    assert(math.abs(bottle.fluid.amount-.69)<.000001)
    C.stop(p)
end)

test("infinite water completion uses hydration not constant advertised reserve",function()
    local sources=require "AutoMindful/WaterSources"
    local scan,drink=sources.scan,sources.drink
    local p=T.playerNew(); p.values.THIRST=.155
    local water={object={},remainingLiters=10000,directDrink=true,
        description={remainingLiters=10000,hungerEffect=0,thirstEffect=5000,hungerRelief=0,thirstRelief=5000,food=false,water=true,calories=0}}
    function water.object:getFluidAmount() return 10000 end
    function water.object:getFluidCapacity() return 10000 end
    function water.object:getUsesExternalWaterSource() return false end
    function water.object:getFluidContainer() return nil end
    local drinks=0
    sources.scan=function() return {water} end
    sources.drink=function(player)
        ISTimedActionQueue.add(T.action(player,"world-drink",function()
            player.values.THIRST=.0001; drinks=drinks+1
        end))
        return true
    end
    assert(C.start(p,"meditation",true))
    for i=1,8 do T.tick(p); if hasHistory(p,"Meditation") then break end end
    assert(drinks==1 and hasHistory(p,"Meditation"))
    C.stop(p); sources.scan,sources.drink=scan,drink
end)

test("unconfirmed fixture intake has one delayed retry and rearms on real supply change",function()
    local sources=require "AutoMindful/WaterSources"
    local scan,drink=sources.scan,sources.drink
    local p=T.playerNew(); p.values.THIRST,p.thirstMoodle=.8,4
    local amount,attempts=10000,0
    local tap={object={},remainingLiters=amount,directDrink=true,
        description={remainingLiters=amount,hungerEffect=0,thirstEffect=5000,hungerRelief=0,thirstRelief=5000,food=false,water=true,calories=0}}
    function tap.object:getFluidAmount() return amount end
    sources.scan=function() return {tap} end
    sources.drink=function(player)
        ISTimedActionQueue.add(T.action(player,"world-drink",function()
            attempts=attempts+1
            if amount<10000 then player.values.THIRST=0; player.thirstMoodle=0 end
        end))
        return true
    end
    assert(C.start(p,"recovery",true))
    for _=1,250 do T.tick(p) end -- several retry windows with no hydration
    assert(attempts==2 and C.status(p).active and p.values.THIRST==.8)
    amount=9999
    for _=1,8 do T.tick(p) end
    assert(attempts==3 and C.status(p).active and p.values.THIRST==0)
    C.stop(p); sources.scan,sources.drink=scan,drink
end)

test("water uses native fluid portions and waits for the native fullness gate",function()
    local p=T.playerNew(); p.values.THIRST=0.2; p.foodMoodle=3
    T.add(p.inventory,T.water()); assert(C.start(p,"yoga",false)); T.tick(p)
    assert(C.status(p).active and not hasHistory(p,"drink"))
    p.foodMoodle=0; T.tick(p)
    assert(hasHistory(p,"drink") and p.drinkPercentage == 0.4)
    C.stop(p)
end)
test("sleep follows server rules and resumes after waking",function()
    T.client=true; T.sleepNeeded=true; T.sleepAllowed=false
    local p=T.playerNew(); p.values.FATIGUE=0.65; assert(C.start(p,"yoga",false)); T.tick(p)
    assert(not C.status(p).active and not p.asleep)
    T.sleepAllowed=true; assert(C.start(p,"yoga",false)); T.tick(p); assert(p.asleep)
    p.asleep=false; p.values.FATIGUE=0; T.tick(p); assert(hasHistory(p,"Yoga"))
    C.stop(p); T.client=false
end)
-- What the log was told, before formatting: "event key value key value".
local Log=require "AutoMindful/Log"
local logOriginals={event=Log.event,headline=Log.headline,detail=Log.detail,state=Log.state}
function captureLog(sink)
    for name,original in pairs(logOriginals) do
        Log[name]=sink and function(player,event,...)
            local out={event}
            for i=1,select("#",...) do out[#out+1]=tostring((select(i,...))) end
            sink(table.concat(out," ").." ")
            return original(player,event,...)
        end or original
    end
end

test("foreign queued action yields training without cancelling the session",function()
    local p=T.playerNew(); assert(C.start(p,"yoga",false)); T.tick(p,false)
    local q=ISTimedActionQueue.getTimedActionQueue(p); local owned=q.queue[1]
    local foreign=T.action(p,"manual"); ISTimedActionQueue.add(foreign); T.tick(p,false)
    assert(C.status(p).active and (owned.stopped or owned.cancelled))
    assert(#q.queue == 1 and q.queue[1] == foreign and not foreign.cancelled and not foreign.stopped)
    assert(foreign.adds==1 and not foreign.removes, "Yield never removes and re-adds someone else's action")
    C.stop(p)
end)
test("refused care cannot loop indefinitely",function()
    for _, kind in ipairs({"food","water","literature"}) do
        local p=T.playerNew(); p.refuseCare=true; p.yogaBlocked="mat"
        if kind == "food" then p.values.HUNGER=0.3 elseif kind == "water" then p.values.THIRST=0.3 else p.values.BOREDOM=40 end
        for i=1,3 do T.add(p.inventory,kind == "food" and T.item("Food") or kind == "water" and T.water() or T.item("Literature")) end
        if kind=="literature" then
            assert(C.start(p,"meditation",false)); local s=T.run(p,40); assert(s.phase=="stopped")
        else
            if kind=="food" then p.hungerMoodle=4 else p.thirstMoodle=4 end
            assert(C.start(p,"meditation",false))
            for _=1,80 do T.tick(p) end
            local actionType=kind=="food" and "eat" or "drink"
            local attempts=0; for _,k in ipairs(p.history) do if k==actionType then attempts=attempts+1 end end
            assert(attempts>=3 and attempts<=6 and C.status(p).active and not ISTimedActionQueue.getTimedActionQueue(p).queue[1])
            p.refuseCare=false
            T.add(p.inventory,kind=="food" and T.item("Food") or T.water())
            for _=1,8 do T.tick(p) end
            assert(C.status(p).active and p.values[kind=="food" and "HUNGER" or "THIRST"]<.3,
                "A fourth, fresh candidate gives real native relief; three misses never disarm the session")
            C.stop(p)
        end
    end
end)
test("zero XP watchdog spans completed sessions",function()
    local p=T.playerNew(); p.noXP=true; assert(C.start(p,"yoga",false))
    -- Completing immediately in the admission tick leaves no owned practice
    -- time. The simulated game hours then elapse in the idle openings.
    for _=1,20 do T.tick(p,true,1); assert(C.status(p).active) end
    -- This time actually spend those hours in the started native action.
    for _=1,40 do
        T.tick(p,false,1)
        if ISTimedActionQueue.getTimedActionQueue(p).queue[1] then T.tick(p,true,1) end
        if not C.status(p).active then break end
    end
    assert(not C.status(p).active and C.status(p).phase == "stopped")
end)
test("embarrassment recovery resumes yoga without literature",function()
    local p=T.playerNew(); p.values.BOREDOM=40; p.yogaBlocked="ContextMenu_Embarrassed"
    assert(C.start(p,"both",false)); T.tick(p); T.tick(p); assert(C.status(p).active and not hasHistory(p,"Yoga"))
    p.yogaBlocked=nil; T.tick(p); T.tick(p); assert(hasHistory(p,"Yoga")); C.stop(p)
end)
test("supplies reject unsafe food and useless or read literature",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew()
    for _, prop in ipairs({{rotten=true},{rawDanger=true},{poison=true},{sealed=true},{alcohol=true},{frozen=true},{sickness=1}}) do T.add(p.inventory,T.item("Food",prop)) end
    local good=T.add(p.inventory,T.item("Food"))
    T.add(p.inventory,T.item("Literature",{skill="Cooking"})); T.add(p.inventory,T.item("Literature",{tags={uninteresting=true}}))
    p.read.story=true; T.add(p.inventory,T.item("Literature",{data={literatureTitle="story"}}))
    p.printRead[7]=true; T.add(p.inventory,T.item("Literature",{data={printMedia={id=7}}}))
    T.add(p.inventory,T.water({tainted=true})); T.add(p.inventory,T.water({alcohol=true})); T.add(p.inventory,T.water({capacity=5}))
    local scan=S.scan(p,false); assert(#scan.food == 1 and scan.food[1].item == good and #scan.literature == 0 and #scan.water == 0)
end)
test("nearby collection is opt-in and respects adjacent range and capacity",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew(); local near=T.container(1,0); local far=T.container(2,0)
    T.add(near,T.item("Food")); T.add(far,T.item("Food")); p.nearby={near,far}
    assert(#S.scan(p,false).food == 0 and #S.scan(p,true).food == 1)
    p.inventory.full=true; assert(not S.choose(p,"food",true,{}))
    p.inventory.full=false; assert(S.choose(p,"food",true,{}).item == near.items[1])
end)
test("nearby portable bags use their native world anchor when source grid is absent",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew()
    local source,far=T.container(1,0),T.container(2,0)
    for _,container in ipairs({source,far}) do
        local square=container.square; container.square=nil
        container.containingItem=T.item("InventoryContainer",{inventory=container,
            world={getSquare=function() return square end,getFluidContainer=function() return nil end}})
        T.add(container,T.item("Food"))
    end
    p.nearby={source,far}
    assert(S.report(p,true).nearbyFood==1)
    local item=source.items[1]; local loan=S.loan(p,item)
    T.remove(source,item); T.add(p.inventory,item)
    local action,notice=S.returnAction(p,loan)
    assert(action and not notice)
    action:perform()
    assert(source:contains(item) and not p.inventory:contains(item))
end)
test("floor provisions use each world item's square when the synthetic container has no grid",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew(); local floor=T.container(); floor.floor=true
    p.values.THIRST=.2
    function floor:getSourceGrid() return nil end
    local function ground(x, z)
        return {getSquare=function() return {getX=function() return x end, getY=function() return 0 end, getZ=function() return z end} end,
            getFluidContainer=function() return nil end}
    end
    T.add(floor,T.item("Food",{world=ground(1,0)}))
    T.add(floor,T.item("Food",{world=ground(2,0)}))
    T.add(floor,T.item("Food",{world=ground(0,1)}))
    local bottle=T.water(); local fluid=bottle.fluid; bottle.fluid=nil
    bottle.world=ground(0,0)
    function bottle.world:getFluidContainer() return fluid end
    T.add(floor,bottle)
    p.nearby={floor}
    assert(#S.scan(p,false).food == 0 and #S.scan(p,true).food == 1)
    assert(#S.scan(p,true).water == 1 and S.choose(p,"water",true,{}).item == bottle)
end)
test("missing Lifestyle rejects start but status and preparation remain usable",function()
    local upstream=ZenWellnessContextMenu; ZenWellnessContextMenu=nil
    local p=T.playerNew(); local started,message=C.start(p,"both",false)
    assert(not started and type(message) == "string" and not C.status(p).active)
    assert(type(C.prepare(p,false).message) == "string")
    ZenWellnessContextMenu=upstream
end)
test("inventory transfers pause and resume care without cancelling the training loop",function()
    local p=T.playerNew(); p.values.BOREDOM=40
    T.add(p.inventory,T.item("Literature"))
    assert(C.start(p,"meditation",false)); T.tick(p,false)
    local transfer=T.action(p,"ISInventoryTransferAction",function() T.add(p.inventory,T.item("Food")) end)
    ISTimedActionQueue.add(transfer)
    T.tick(p,false)
    assert(C.status(p).active, "Training must remain active while your inventory transfer finishes.")
    local queue=ISTimedActionQueue.getTimedActionQueue(p).queue
    assert(#queue==1 and queue[1]==transfer and not transfer.cancelled)
    transfer:perform()
    for i=1,6 do T.tick(p) end
    assert(C.status(p).active and hasHistory(p,"Meditation"),"care must resume after the manual inventory transfer")
    assert(#p.cards==0 and #p.halos==0,"allowed inventory work must not report cancellation")
    C.stop(p)
end)
test("unexplained displacement cancels once with a visible reason while context gestures do not",function()
    local p=T.playerNew(); assert(C.start(p,"yoga",false)); T.tick(p,false)
    p.aimInput=true; T.now=T.now+100; C.update(p)
    p.contextOpen=true; T.now=T.now+100; C.update(p)
    assert(C.status(p).active)
    p.aimInput=false; p.contextOpen=false
    p.moving=true; p.x=p:getX()+3; T.now=T.now+1000; C.update(p); C.update(p)
    assert(not C.status(p).active and #p.cards==1 and #p.halos==0 and p.cards[1].note:find("moved",1,true))
end)
test("live preparation reflects movement inventory changes and collection permission",function()
    local p=T.playerNew(); local shelf=T.container(5,0)
    T.add(shelf,T.item("Food")); p.available={shelf}; p.nearby={}
    assert(C.prepare(p,false,true).nearbyFood==0)
    p.square=T.square(5,0)
    local near=C.prepare(p,false,true)
    assert(near.food==0 and near.nearbyFood==1 and #near.warnings>0)
    T.add(p.inventory,T.item("Food"))
    assert(C.prepare(p,false,true).food==1)
    p.square=T.square(0,0)
    assert(C.prepare(p,false,true).nearbyFood==0)
    assert(C.start(p,"yoga",false)); T.tick(p,false)
    local action=ISTimedActionQueue.getTimedActionQueue(p).queue[1]
    C.setCollectNearby(p,true)
    assert(C.status(p).active and C.status(p).collectNearby)
    C.prepare(p,true,true)
    assert(ISTimedActionQueue.getTimedActionQueue(p).queue[1]==action and not action.stopped)
    C.stop(p)
end)
test("borrowed literature returns to its original container and meditation resumes",function()
    local p=T.playerNew(); p.values.BOREDOM=40
    local shelf=T.container(1,0)
    local book=T.add(shelf,T.item("Literature"))
    p.nearby={shelf}
    assert(C.start(p,"meditation",true)); local status=T.run(p)
    assert(status.mode=="recovery" and status.meditation==10)
    assert(shelf:contains(book) and not p.inventory:contains(book))
    assert(status.pendingReturns==0 and hasHistory(p,"read") and hasHistory(p,"Meditation"))
end)
test("borrowed resources keep their origin when native synchronization replaces the Lua item reference",function()
    local p=T.playerNew(); p.values.BOREDOM=40
    local shelf=T.container(1,0); local original=T.add(shelf,T.item("Literature"))
    p.nearby={shelf}; assert(C.start(p,"meditation",true)); T.tick(p)
    T.remove(p.inventory,original)
    local synchronized=T.item("Literature"); synchronized.id=original.id; T.add(p.inventory,synchronized)
    local status=T.run(p)
    assert(status.mode=="recovery" and shelf:contains(synchronized) and not p.inventory:contains(synchronized))
end)
test("borrowed drinks return the same partly filled bottle and preserve owned items",function()
    local p=T.playerNew(); p.values.THIRST=.25
    local shelf=T.container(1,0); local bottle=T.add(shelf,T.water())
    local owned=T.add(p.inventory,T.item("InventoryItem",{fullType="Base.EmptyBottle"}))
    p.nearby={shelf}; assert(C.start(p,"yoga",true))
    for i=1,8 do T.tick(p) end
    assert(shelf:contains(bottle) and bottle.fluid.amount==.5)
    assert(p.inventory:contains(owned) and not p.inventory:contains(bottle))
    C.stop(p)
end)
test("consuming borrowed food returns only its new native empty container",function()
    local p=T.playerNew(); p.values.HUNGER=.5
    local shelf=T.container(1,0)
    T.add(shelf,T.item("Food",{replace="Base.EmptyTinCan"}))
    local owned=T.add(p.inventory,T.item("InventoryItem",{fullType="Base.EmptyTinCan"}))
    p.nearby={shelf}; assert(C.start(p,"yoga",true))
    for i=1,8 do T.tick(p) end
    assert(#shelf.items==1 and shelf.items[1]:getFullType()=="Base.EmptyTinCan")
    assert(shelf.items[1]~=owned and p.inventory:contains(owned))
    C.stop(p)
end)
test("fully consumed borrowed food without a container settles on completion or Stop",function()
    for _,stop in ipairs({false,true}) do
        local p=T.playerNew(); p.values.HUNGER=.5
        local shelf=T.container(1,0)
        local corn=T.add(shelf,T.item("Food",{fullType="Base.Corn",hunger=-.5,baseHunger=-.5}))
        p.nearby={shelf}; assert(C.start(p,"meditation",true))
        T.tick(p); T.tick(p)
        assert(hasHistory(p,"eat") and not p.inventory:contains(corn) and not shelf:contains(corn))
        if stop then C.stop(p,"Stopped by the player.") end
        for i=1,5 do T.tick(p); if hasHistory(p,"Meditation") then break end end
        local status=C.status(p)
        assert(status.pendingReturns==0 and #shelf.items==0 and not status.returnNotice)
        if stop then assert(not status.active and not hasHistory(p,"Meditation"))
        else assert(status.active and hasHistory(p,"Meditation")); C.stop(p) end
    end
end)
test("missing declared replacement waits up to three seconds and never takes an existing can",function()
    local S=require "AutoMindful/Supplies"
    for _,arrives in ipairs({false,true}) do
        local p=T.playerNew(); local shelf=T.container(1,0)
        local used=T.add(shelf,T.item("Food",{replace="Base.EmptyTinCan"}))
        local owned=T.add(p.inventory,T.item("InventoryItem",{fullType="Base.EmptyTinCan"}))
        local loan=S.loan(p,used)
        T.remove(shelf,used); T.add(p.inventory,used); S.watchLoan(p,loan,used); T.remove(p.inventory,used)
        assert(not S.finishLoan(p,loan,1000) and not S.finishLoan(p,loan,3999))
        local replacement
        if arrives then replacement=T.add(p.inventory,T.item("InventoryItem",{fullType="Base.EmptyTinCan"})) end
        assert(S.finishLoan(p,loan,4000) and not loan.usedItem)
        if arrives then assert(loan.items[2]==replacement and not loan.notice)
        else assert(#loan.items==1 and loan.notice:find("did not confirm",1,true)) end
        assert(p.inventory:contains(owned))
    end
end)
test("cancelled borrowing keeps unreachable items and returns them when the source is reachable again",function()
    local p=T.playerNew(); p.values.BOREDOM=40
    local shelf=T.container(1,0); local book=T.add(shelf,T.item("Literature"))
    p.nearby={shelf}; assert(C.start(p,"meditation",true)); T.tick(p)
    assert(p.inventory:contains(book))
    p.square=T.square(5,0); p.moving=true; T.now=T.now+1000; C.update(p)
    p.moving=false; T.now=T.now+1000; C.update(p)
    assert(not C.status(p).active and C.status(p).pendingReturns==1 and C.status(p).returnNotice)
    assert(p.inventory:contains(book))
    p.square=T.square(0,0)
    for i=1,4 do T.tick(p) end
    assert(shelf:contains(book) and C.status(p).pendingReturns==0)
end)
test("an unavailable original container keeps the borrowed resource without stopping the loop",function()
    local p=T.playerNew(); p.values.BOREDOM=40
    local shelf=T.container(1,0); local book=T.add(shelf,T.item("Literature"))
    p.nearby={shelf}; assert(C.start(p,"meditation",true)); T.tick(p)
    shelf.reject=true
    for i=1,5 do T.tick(p) end
    assert(C.status(p).active and C.status(p).returnNotice and p.inventory:contains(book))
    shelf.reject=false
    for i=1,10 do T.tick(p); if shelf:contains(book) then break end end
    assert(shelf:contains(book))
    C.stop(p)
end)
test("rereads use native cooldown and oldest native reading dates after unread titles",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew()
    local unread=T.add(p.inventory,T.item("Literature",{data={literatureTitle="unread"}}))
    local oldest=T.add(p.inventory,T.item("Literature",{data={literatureTitle="oldest"}}))
    local newer=T.add(p.inventory,T.item("Literature",{data={literatureTitle="newer"}}))
    local recent=T.add(p.inventory,T.item("Literature",{data={literatureTitle="recent"}}))
    p.read.oldest=1; p.read.newer=2; p.read.recent=49
    local report=S.report(p,false)
    assert(report.unreadLiterature==1 and report.rereadLiterature==2 and report.cooldownLiterature==1)
    assert(S.choose(p,"literature",false,{}).item==unread)
    T.remove(p.inventory,unread)
    assert(S.choose(p,"literature",false,{}).item==oldest)
    p.read.oldest=T.nights
    assert(S.choose(p,"literature",false,{}).item==newer)
    p.read.newer=T.nights
    assert(not S.choose(p,"literature",false,{}))
    T.nights=95
    assert(S.choose(p,"literature",false,{}).item==recent,"native cooldown expiry must make the oldest title usable again")
    T.nights=50
end)
test("borrowed books return to their original floor square and carried bag",function()
    for _, floorSource in ipairs({true,false}) do
        local p=T.playerNew(); p.values.BOREDOM=40
        local source=T.container(1,0)
        if floorSource then source.floor=true; p.nearby={source}
        else
            source.root=p.inventory
            T.add(p.inventory,T.item("InventoryContainer",{inventory=source}))
        end
        local book=T.add(source,T.item("Literature"))
        assert(C.start(p,"meditation",floorSource)); local status=T.run(p)
        assert(status.mode=="recovery" and source:contains(book) and not p.inventory:contains(book))
        if floorSource then assert(book:getWorldItem():getSquare()==source.square) end
    end
end)
test("returned carried-bag items complete and manual bag moves return from the current container",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew()
    local origin, other=T.container(),T.container(); origin.root=p.inventory; other.root=p.inventory
    T.add(p.inventory,T.item("InventoryContainer",{inventory=origin}))
    T.add(p.inventory,T.item("InventoryContainer",{inventory=other}))
    local book=T.add(origin,T.item("Literature")); local loan={origin=origin,items={book}}
    local action,notice,complete=S.returnAction(p,loan)
    assert(not action and not notice and complete,"An item already in its source must not queue another return")
    T.remove(origin,book); T.add(other,book)
    action,notice,complete=S.returnAction(p,loan)
    assert(action and not notice and not complete)
    action:perform()
    assert(origin:contains(book) and not other:contains(book),"Return must use the actual current bag as source")
    action,notice,complete=S.returnAction(p,loan)
    assert(not action and complete)
end)
test("food care restores hunger without an extra calorie reserve",function()
    local p=T.playerNew(); p.values.HUNGER=.16; p.calories=0
    local meal=T.add(p.inventory,T.item("Food",{hunger=-.24,baseHunger=-.24,calories=170}))
    assert(C.start(p,"meditation",false)); T.run(p)
    assert(math.abs(p.values.HUNGER)<.000001)
    assert(math.abs(meal:getHungerChange()+.08)<.000001,"Only .16 of the .24 hunger relief should be consumed")
    local full=T.playerNew(); full.values.HUNGER=0; full.calories=0
    local untouched=T.add(full.inventory,T.item("Food",{hunger=-.24,baseHunger=-.24,calories=170}))
    assert(C.start(full,"meditation",false)); T.run(full)
    assert(untouched:getHungerChange()==-.24,"A full survivor must not eat just to fill an arbitrary calorie reserve")
end)
test("opening borrowed food returns the new empty can and borrowed opener to their exact sources",function()
    local saved={ArrayList=ArrayList,HandcraftLogic=HandcraftLogic,getScriptManager=getScriptManager,ISEntityUI=ISEntityUI,ResourceType=ResourceType,ISCraftingUI=ISCraftingUI}
    ArrayList={new=function() local values={}; local list=T.list(values); function list:add(value) values[#values+1]=value end return list end}
    ResourceType={Item="Item"}
    local output={getFullName=function() return "Base.OpenedFixtureCan" end,isCantEat=function() return false end,
        getPoisonPower=function() return 0 end,getFoodSicknessChange=function() return 0 end,isAlcoholic=function() return false end,
        isDangerousUncooked=function() return false end,getHungerChange=function() return -.5 end,getThirstChange=function() return 0 end}
    local recipe={isAnySurfaceCraft=function() return false end,isCanBeDoneFromFloor=function() return false end,
        getOutputs=function() return T.list({{getResourceType=function() return "Item" end,getItem=function() return output end}}) end}
    function getScriptManager() return {getCraftRecipe=function(_,name) return name=="OpenFixture" and recipe or nil end} end
    HandcraftLogic={new=function(player)
        local logic={player=player}
        function logic:setIsoObject() end
        function logic:findCraftSurface() return nil end
        function logic:setContainers(containers) self.containers=containers end
        function logic:setRecipeFromContextClick(_,item) self.item=item end
        function logic:tool()
            for index=0,self.containers:size()-1 do
                local items=self.containers:get(index):getItems()
                for at=0,items:size()-1 do local item=items:get(at); if item:getFullType()=="Base.FixtureOpener" then return item end end
            end
        end
        function logic:canPerformCurrentRecipe() return self:tool()~=nil end
        function logic:getRecipeData()
            local tool=self:tool()
            return {getAllInputItems=function() return T.list({self.item,tool}) end,
                getAllPutBackInputItems=function() return T.list({tool}) end}
        end
        function logic:isUsingRecipeAtHandBenefit() return false end
        function logic:startCraftAction(action) ISTimedActionQueue.add(action) end
        return logic
    end}
    ISEntityUI={HandcraftStart=function(player,logic)
        local action=T.action(player,"ISHandcraftAction",function()
            T.remove(logic.item:getContainer(),logic.item)
            T.add(player.inventory,T.item("Food",{fullType="Base.OpenedFixtureCan",replace="Base.EmptyFixtureCan",
                rotten=player.fixtureRottenOutput}))
        end)
        function action:setOnComplete() end
        return action
    end}
    ISCraftingUI={ReturnItemsToOriginalContainer=function() error("Do not rely on the native helper which skips Disorganized characters") end}
    ISInventoryPaneContextMenu.transferIfNeeded=function(player,item)
        if item:getContainer()~=player:getInventory() then
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player,item,item:getContainer(),player:getInventory()))
        end
    end
    local p=T.playerNew(); p.values.HUNGER=.5; p.traits.disorganized=true
    local pantry,toolbox=T.container(1,0),T.container(0,1)
    for _,container in ipairs({pantry,toolbox}) do
        local square=container.square; container.square=nil
        container.containingItem=T.item("InventoryContainer",{inventory=container,
            world={getSquare=function() return square end,getFluidContainer=function() return nil end}})
    end
    T.add(pantry,T.item("Food",{fullType="Base.ClosedFixtureCan",hunger=0,cantEat=true,sealed=true,openingRecipe="OpenFixture"}))
    local opener=T.add(toolbox,T.item("InventoryItem",{fullType="Base.FixtureOpener"}))
    local ownedCan=T.add(p.inventory,T.item("InventoryItem",{fullType="Base.EmptyFixtureCan"}))
    p.nearby={pantry,toolbox}
    local unavailable=C.prepare(p,false,true)
    assert(unavailable.nearbyFood==0 and unavailable.openingReason:find("opener",1,true))
    assert(C.prepare(p,true,true).nearbyFood==1)
    assert(C.start(p,"yoga",true))
    for i=1,14 do T.tick(p) end
    assert(toolbox:contains(opener) and not p.inventory:contains(opener))
    assert(#pantry.items==1 and pantry.items[1]:getFullType()=="Base.EmptyFixtureCan" and pantry.items[1]~=ownedCan)
    assert(p.inventory:contains(ownedCan) and C.status(p).pendingReturns==0)
    C.stop(p)
    local interrupted=T.playerNew(); interrupted.values.HUNGER=.3
    local foodSource,toolSource=T.container(1,0),T.container(0,1)
    local closed=T.add(foodSource,T.item("Food",{fullType="Base.ClosedFixtureCan",hunger=0,cantEat=true,sealed=true,openingRecipe="OpenFixture"}))
    local sharedOpener=T.add(toolSource,T.item("InventoryItem",{fullType="Base.FixtureOpener"}))
    interrupted.nearby={foodSource,toolSource}
    assert(C.start(interrupted,"yoga",true)); T.tick(interrupted)
    assert(C.status(interrupted).phase=="collecting" and interrupted.inventory:contains(closed))
    T.remove(toolSource,sharedOpener)
    for i=1,6 do T.tick(interrupted) end
    assert(C.status(interrupted).active and hasHistory(interrupted,"Yoga"),"Losing a shared opener must not stop noncritical training")
    assert(foodSource:contains(closed) and C.status(interrupted).pendingReturns==0,"The unopened borrowed can must return to its source")
    assert(not hasHistory(interrupted,"ISHandcraftAction") and #interrupted.halos==0)
    T.add(toolSource,sharedOpener); T.now=T.now+61000
    for i=1,14 do T.tick(interrupted) end
    assert(hasHistory(interrupted,"ISHandcraftAction") and hasHistory(interrupted,"eat"),"A usable opener permits a later retry")
    assert(C.status(interrupted).pendingReturns==0 and toolSource:contains(sharedOpener))
    C.stop(interrupted)
    local spoiled=T.playerNew(); spoiled.values.HUNGER=.3; spoiled.fixtureRottenOutput=true
    T.add(spoiled.inventory,T.item("Food",{fullType="Base.ClosedFixtureCan",hunger=0,cantEat=true,
        sealed=true,openingRecipe="OpenFixture"}))
    T.add(spoiled.inventory,T.item("InventoryItem",{fullType="Base.FixtureOpener"}))
    assert(C.start(spoiled,"yoga",false))
    for i=1,14 do T.tick(spoiled) end
    assert(hasHistory(spoiled,"ISHandcraftAction") and not hasHistory(spoiled,"eat") and spoiled.values.HUNGER==.3,
        "safe recipe metadata must not authorize its rotten produced item")
    C.stop(spoiled)
    ArrayList,HandcraftLogic,getScriptManager,ISEntityUI,ResourceType,ISCraftingUI=saved.ArrayList,saved.HandcraftLogic,saved.getScriptManager,saved.ISEntityUI,saved.ResourceType,saved.ISCraftingUI
end)
test("known bulk scouting needs current safe stock and a compatible carried or same-holder empty vessel",function()
    local p=T.playerNew(); p.values.HUNGER,p.values.THIRST=.25,.25
    local S=require "AutoMindful/Supplies"
    local shelf=T.container(6,0)
    function shelf:isExplored() return false end -- positive listed stock is valid; missing contents are not
    local bulk=T.add(shelf,T.water({capacity=5,hunger=-.5,thirst=-.5})); bulk.fluid.amount=5
    local tag={item=bulk,container=shelf,square=shelf.square}
    local function can(kind,rej)
        return S.scoutProbe(p,kind,rej or {})(tag),S.scoutedStock(p,kind,shelf,rej or {})
    end
    for _,kind in ipairs({"food","water"}) do
        local ordinary,recalled=can(kind); assert(not ordinary and not recalled)
    end
    local bag=T.container(); bag.root=p.inventory
    T.add(p.inventory,T.item("InventoryContainer",{inventory=bag}))
    local vessel=T.add(bag,T.water()); vessel.fluid.amount=0; vessel.fluid.reject=true
    assert(not can("food"),"An incompatible empty is not enough")
    vessel.fluid.reject=nil; assert(not can("food",{[vessel:getID()]=T.now+3000}))
    local normal,recalled=can("food"); assert(normal and recalled,"The actual nested carried empty qualifies for either path")
    vessel.fluid.amount=.1; assert(not can("food"),"Never dump another beverage to make a vessel")
    vessel.fluid.amount=0; T.remove(bag,vessel); T.add(shelf,vessel)
    assert(can("food"),"An observed compatible empty in the same holder is available at the destination")
    bulk.fluid.amount=0; assert(not can("food"),"A dry donor is not current food")
    bulk.fluid.amount=4; assert(can("food"),"Restocked donor gets another opportunity")
    assert(not can("food",{[bulk:getID()]=T.now+3000}))
    T.remove(shelf,bulk); assert(not can("food"),"Old positive snapshot cannot send a survivor to a moved item")
    assert(p.refreshCount==nil and #p.history==0,"No loot request/refresh, pickup or native walking during stock proof")
end)

test("bulk milk and an empty vessel return to their separate nearby origins after care",function()
    local p=T.playerNew(); p.values.HUNGER=.2; p.values.THIRST=.2
    local pantry,shelf=T.container(1,0),T.container(0,1)
    local bulk=T.add(pantry,T.water({capacity=5,hunger=-.5,thirst=-.5})); bulk.fluid.amount=5
    local vessel=T.add(shelf,T.water()); vessel.fluid.amount=0
    p.nearby={pantry,shelf}
    assert(C.start(p,"meditation",true))
    for i=1,12 do T.tick(p) end
    assert(p.values.HUNGER<.000001 and p.values.THIRST<.000001)
    assert(math.abs(bulk.fluid.amount-4.6)<.000001 and vessel.fluid.amount==0,"Pour and consume only the needed .4 liters")
    assert(pantry:contains(bulk) and shelf:contains(vessel) and C.status(p).pendingReturns==0)
    assert(hasHistory(p,"ISFluidTransferAction") and hasHistory(p,"drink") and hasHistory(p,"Meditation"))
    C.stop(p)
end)
test("a carried-bag empty vessel returns to the same bag with nearby collection disabled",function()
    local p=T.playerNew(); p.values.THIRST=.2
    local bag=T.container(); bag.root=p.inventory
    T.add(p.inventory,T.item("InventoryContainer",{inventory=bag}))
    local bulk=T.add(p.inventory,T.water({capacity=5})); bulk.fluid.amount=5
    local vessel=T.add(bag,T.water()); vessel.fluid.amount=0
    assert(C.start(p,"meditation",false))
    for i=1,12 do T.tick(p) end
    assert(p.values.THIRST<.000001 and math.abs(bulk.fluid.amount-4.6)<.000001)
    assert(bag:contains(vessel) and p.inventory:contains(bulk) and C.status(p).pendingReturns==0)
    C.stop(p)
end)
test("bulk milk does not replace an existing drink when no empty vessel is available",function()
    local p=T.playerNew(); p.values.HUNGER=.2
    local bulk=T.add(p.inventory,T.water({capacity=5,hunger=-.5})); bulk.fluid.amount=5
    local personal=T.add(p.inventory,T.water()); personal.fluid.amount=.5
    assert(C.start(p,"meditation",false))
    for i=1,5 do T.tick(p) end
    assert(bulk.fluid.amount==5 and personal.fluid.amount==.5)
    assert(not hasHistory(p,"ISFluidTransferAction") and not hasHistory(p,"drink"))
    assert(hasHistory(p,"Meditation"),"A missing vessel should not prevent noncritical training")
    C.stop(p)
end)
test("source contamination before pouring preserves both borrowed containers and all fluid",function()
    local p=T.playerNew(); p.values.HUNGER=.2
    local pantry,shelf=T.container(1,0),T.container(0,1)
    local bulk=T.add(pantry,T.water({capacity=5,hunger=-.5})); bulk.fluid.amount=5
    local vessel=T.add(shelf,T.water()); vessel.fluid.amount=0
    p.nearby={pantry,shelf}
    assert(C.start(p,"meditation",true)); T.tick(p); T.tick(p); T.tick(p,false)
    assert(C.status(p).phase=="transferring")
    bulk.fluid.components={{fluid=FluidFixtures.component({sickness=5}),percentage=.001}}
    for i=1,8 do T.tick(p) end
    assert(bulk.fluid.amount==5 and vessel.fluid.amount==0 and not hasHistory(p,"drink"))
    assert(pantry:contains(bulk) and shelf:contains(vessel) and C.status(p).pendingReturns==0)
    C.stop(p)
end)
test("contamination after pouring returns the filled vessel without drinking or dumping it",function()
    local p=T.playerNew(); p.values.HUNGER=.2
    local pantry,shelf=T.container(1,0),T.container(0,1)
    local bulk=T.add(pantry,T.water({capacity=5,hunger=-.5})); bulk.fluid.amount=5
    local vessel=T.add(shelf,T.water()); vessel.fluid.amount=0
    p.nearby={pantry,shelf}
    assert(C.start(p,"meditation",true)); T.tick(p); T.tick(p); T.tick(p)
    assert(vessel.fluid.amount>0)
    vessel.fluid.components={{fluid=FluidFixtures.component({poisonous=true}),percentage=.001}}
    for i=1,8 do T.tick(p) end
    assert(not hasHistory(p,"drink") and math.abs(vessel.fluid.amount-.4)<.000001)
    assert(math.abs(bulk.fluid.amount-4.6)<.000001 and pantry:contains(bulk) and shelf:contains(vessel))
    assert(C.status(p).pendingReturns==0)
    C.stop(p)
end)
test("an intentional run during a partial pour returns both loans without consuming the partial contents",function()
    local p=T.playerNew(); p.values.HUNGER=.2
    local pantry,shelf=T.container(1,0),T.container(0,1)
    local bulk=T.add(pantry,T.water({capacity=5,hunger=-.5})); bulk.fluid.amount=5
    local vessel=T.add(shelf,T.water()); vessel.fluid.amount=0
    p.nearby={pantry,shelf}
    assert(C.start(p,"meditation",true)); T.tick(p); T.tick(p); T.tick(p,false)
    assert(C.status(p).phase=="transferring")
    bulk.fluid.amount=4.9; vessel.fluid.amount=.1
    vessel.fluid.hungerRate=bulk.fluid.hungerRate; vessel.fluid.components=bulk.fluid.components
    p.running=true; p.rawMovementInput=true; p.x=p:getX()+3; T.tick(p,false)
    assert(not C.status(p).active and #p.cards==1 and #p.halos==0 and p.cards[1].note:find("running",1,true))
    p.running=false; p.rawMovementInput=false
    for i=1,8 do T.tick(p) end
    assert(pantry:contains(bulk) and shelf:contains(vessel) and C.status(p).pendingReturns==0)
    assert(math.abs(bulk.fluid.amount+vessel.fluid.amount-5)<.000001 and not hasHistory(p,"drink") and #p.cards==1)
end)
test("native auto drinking between pour and controller confirmation counts as successful care",function()
    local p=T.playerNew(); p.values.THIRST=.2
    local shelf=T.container(1,0)
    local bulk=T.add(p.inventory,T.water({capacity=5})); bulk.fluid.amount=5
    local vessel=T.add(shelf,T.water()); vessel.fluid.amount=0
    p.nearby={shelf}
    assert(C.start(p,"meditation",true)); T.tick(p); T.tick(p)
    assert(vessel.fluid.amount>0)
    vessel.fluid.amount=0; p.values.THIRST=0
    for i=1,7 do T.tick(p) end
    assert(shelf:contains(vessel) and C.status(p).pendingReturns==0 and hasHistory(p,"Meditation"))
    assert(not hasHistory(p,"drink"),"Do not drink twice after native auto drinking satisfied thirst")
    C.stop(p)
end)
-- Native pathfinding remains a boundary here; these tests exercise controller ownership and lifecycle.
local walkSpeed = 1
BehaviorResult = {Failed="Failed"}
function getGameSpeed() return walkSpeed end
UIManager = {getSpeedControls=function()
    return {SetCurrentGameSpeed=function(_, value) walkSpeed=value end}
end}
ISWalkToTimedAction = {new=function(_, p, square)
    local action = T.action(p, "ISWalkToTimedAction", function()
        if not p.pathBlocked then p.square = square end
    end)
    action.location = square
    function action:isValid() return walkSpeed <= 2 end -- native Build 42 walk contract
    function action:start()
        if p.pathProbe then
            p.pathProbe:pathToLocation(square:getX(), square:getY(), square:getZ())
        end
    end
    return action
end}
luautils = luautils or {}
function luautils.walkAdj(p, square, keepActions)
    assert(keepActions, "Do not clear standing or user actions when walking")
    if p.routeUnavailable then return false end
    ISTimedActionQueue.add(ISWalkToTimedAction:new(p, T.square(square:getX()-1, square:getY(), square:getZ())))
    return true
end

function luautils.walkAdjObject(p, world, diagonal, keepActions)
    assert(diagonal and keepActions, "Use the native world-drink approach without clearing the queue")
    p.objectWalk=world
    local square=world:getSquare()
    ISTimedActionQueue.add(T.action(p,"ISPathFindAction",function()
        p.square=T.square(square:getX()-1,square:getY(),square:getZ())
    end))
    return true
end

test("nearby care walks, borrows, reads, returns the book and returns home before training", function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=40; p.sitting=true
    local origin=p:getSquare(); local shelf=T.container(6,0)
    local book=T.add(shelf,T.item("Literature")); p.available={shelf}
    nearbyTarget={square=shelf.square,key="6:0:0"}
    assert(C.start(p,"meditation",false))
    for i=1,20 do T.tick(p); if hasHistory(p,"Meditation") then break end end
    assert(p:getSquare()==origin, "Training must resume at the original square")
    assert(#p.cards==0, "The outing and return are part of the same session")
    assert(shelf:contains(book), "Borrowed literature goes back before the return trip")
    assert(hasHistory(p,"read") and hasHistory(p,"Meditation"))
    C.stop(p); roaming.enabled=false; nearbyTarget=nil
end)

test("a single finite or mains drink on a scouting trip returns home and resumes meditation", function()
    local sources=require "AutoMindful/WaterSources"
    local scan, drink, choose=sources.scan, sources.drink, sources.choose
    roaming.enabled=true
    for _,initial in ipairs({5,10000}) do
        local p=T.playerNew(); p.values.THIRST=.25
        local origin, target=p:getSquare(), T.square(6,0)
        local reserve, drinks=initial, 0
        local world={getSquare=function() return target end,getMasterObject=function(self) return self end,
            getFluidAmount=function() return reserve end,getFluidCapacity=function() return initial end,
            getUsesExternalWaterSource=function() return false end,getFluidContainer=function() return nil end}
        local water={object=world,remainingLiters=initial,directDrink=true,
            description={remainingLiters=initial,hungerEffect=0,thirstEffect=initial/2,hungerRelief=0,
                thirstRelief=initial/2,food=false,water=true,calories=0}}
        nearbyTarget={square=target,key="water:6:0:0",object=world}
        sources.scan=function() return p:getSquare():canReachTo(target) and {water} or {} end
        sources.choose=function(_,_,expected)
            for _,s in ipairs(sources.scan()) do if s.object==expected then return s end end
        end
        sources.drink=function(player, source)
            assert(source.object==world and player:getSquare()~=origin and player:getSquare():canReachTo(target))
            ISTimedActionQueue.add(T.action(player,"world-drink",function()
                if initial==5 then reserve=reserve-player.values.THIRST*2 end
                drinks=drinks+1; player.values.THIRST=.0001
            end))
            return true
        end
        assert(C.start(p,"meditation",false))
        for i=1,20 do T.tick(p); if hasHistory(p,"Meditation") then break end end
        assert(p.objectWalk==world,"Scout to the object itself, as the stock Drink action does")
        assert(drinks==1 and reserve==(initial==5 and 4.5 or 10000))
        assert(C.status(p).active and p:getSquare()==origin and hasHistory(p,"Meditation"))
        C.stop(p)
    end
    sources.scan,sources.drink,sources.choose=scan,drink,choose
    roaming.enabled=false; nearbyTarget=nil
end)

test("a stale or refused scouted tap does not consume other nearby hydration", function()
    local sources=require "AutoMindful/WaterSources"
    local scan,drink,choose=sources.scan,sources.drink,sources.choose
    roaming.enabled=true
    for _,refused in ipairs({false,true}) do
        local p=T.playerNew(); p.values.THIRST=.25
        local origin, target=p:getSquare(),T.square(6,0)
        local world={getSquare=function() return target end,getMasterObject=function(self) return self end,
            getFluidAmount=function() return 5 end}
        local rival=T.container(6,0); local bottle=T.add(rival,T.water())
        p.available={rival}
        nearbyTarget={square=target,key="water:6:0:0",object=world}
        sources.scan=function() return {} end
        sources.choose=function(_,rejected,expected)
            assert(expected==world)
            if refused and not rejected[world] then return {object=world,directDrink=true} end
        end
        sources.drink=function() return false,"The game refused drinking." end
        assert(C.start(p,"meditation",false))
        for i=1,30 do T.tick(p); if hasHistory(p,"Meditation") then break end end
        assert(p.objectWalk==world and p:getSquare()==origin and C.status(p).active and hasHistory(p,"Meditation"))
        assert(rival:contains(bottle) and bottle.fluid.amount==1 and not hasHistory(p,"drink"))
        C.stop(p)
    end
    roaming.enabled=false;nearbyTarget=nil
    sources.scan,sources.drink,sources.choose=scan,drink,choose
end)

test("blocked meditation uses owned literature before scouting unknown containers", function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=40
    local book=T.add(p.inventory,T.item("Literature"))
    nearbyTarget={square=T.square(6,0),key="unknown:6:0:0",unknown=true}
    assert(C.start(p,"meditation",false))
    for i=1,20 do T.tick(p); if hasHistory(p,"Meditation") then break end end
    assert(hasHistory(p,"read") and hasHistory(p,"Meditation"))
    assert(not hasHistory(p,"ISWalkToTimedAction"), "Known usable literature avoids speculative scouting")
    C.stop(p); roaming.enabled=false; nearbyTarget=nil
end)

test("a scout checks stock again after pickup, skips failed intake and retries on refill",function()
    roaming.enabled=true
    local p=T.playerNew()
    local origin=p:getSquare()
    local shelf=T.container(6,0)
    local candidate=T.add(shelf,T.water())
    local backup=T.add(shelf,T.water())
    candidate.fluid.amount,backup.fluid.amount=.5,0
    p.available={shelf}
    p.values.THIRST=.30
    local N=require "AutoMindful/Nearby"
    local S=require "AutoMindful/Supplies"
    local initialFind=N.find
    local initialInspect=require("AutoMindful/Consumables").inspect
    local trace={}
    local probes=0
    captureLog(function(line) if line:find("^trip%.") or line:find("^supply%.") then trace[#trace+1]=line end end)
    N.find=function(player,kind,_,_,_,_,rejected)
        if kind~="water" then return end
        local probe=S.scoutProbe(player,kind,rejected)
        for _, item in ipairs({candidate,backup}) do
            local t={item=item,container=shelf,square=shelf.square,key="water:6:0:0"}
            if probe(t) then probes=probes+1; return t end
        end
    end
    local O=require "AutoMindful/Consumables"
    local refuse=true
    O.inspect=function(player,item,tools)
        if item==candidate and item:getContainer()==p.inventory and refuse then
            return {water=false,reason="Fixture: fresh pickup view has no drink"}
        end
        return initialInspect(player,item,tools)
    end
    assert(C.start(p,"yoga",false))
    local blocked
    for _=1,60 do
        T.tick(p)
        for _,line in ipairs(trace) do
            if line:find("trip.care-unconfirmed",1,true) then blocked=true end
        end
        if blocked and p:getSquare()==origin then break end
    end
    assert(blocked and p:getSquare()==origin and shelf:contains(candidate))
    assert(p.values.THIRST==.30 and not hasHistory(p,"drink"),"A failed pickup recheck must not count as drinking")
    local before=probes
    T.now=T.now+75000
    for _=1,8 do T.tick(p) end
    assert(probes==before,"An unchanged failed item cannot trigger another outbound scout")
    -- Newly observed stock in the same holder remains eligible.
    backup.fluid.amount=1
    for _=1,60 do T.tick(p); if p.values.THIRST<.01 and p:getSquare()==origin then break end end
    assert(p.values.THIRST<.01 and p:getSquare()==origin and shelf:contains(backup))
    -- New contents on the very same original item ID are eligible again.
    refuse=false; candidate.fluid.amount=1; backup.fluid.amount=0; p.values.THIRST=.25
    for _=1,60 do T.tick(p); if p.values.THIRST<.01 and p:getSquare()==origin then break end end
    assert(p.values.THIRST<.01 and p:getSquare()==origin and shelf:contains(candidate))
    local function seen(event,value)
        for _,line in ipairs(trace) do if line:find("."..event.." ",1,true) and line:find(value,1,true) then return true end end
        return false
    end
    assert(seen("stock-selected","liters=0.5") and seen("pickup-result","original-item-present")
        and seen("stock-invalid","ineligible-after-pickup") and seen("intake-requested","thirstBefore=")
        and seen("intake-result","thirstAfter=0"),"Log holder, selected item, pickup, and measured intake")
    C.stop(p); N.find=initialFind; O.inspect=initialInspect; captureLog(nil); roaming.enabled=false
end)

test("fast-forward during inspection cannot silently invalidate the native return walk", function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=25
    local origin=p:getSquare(); local shelf=T.container(6,0); p.available={shelf}
    nearbyTarget={square=shelf.square,key="unknown:6:0:0",unknown=true,container=shelf}
    local trace={}
    captureLog(function(line) if line:find("^trip%.") or line:find("^supply%.") then trace[#trace+1]=line end end)
    local rate; function getGameTime() return {setMultiplier=function(_,v) rate=v end,getNightsSurvived=function() return 0 end,getTimeOfDay=function() return 9 end,getWorldAgeHours=function() return 1 end} end
    walkSpeed=4
    assert(C.start(p,"meditation",false))
    T.tick(p,false)
    assert(walkSpeed==1, "Outbound scouting starts a valid native walk at normal speed")
    local inspected=false
    for i=1,20 do
        T.tick(p)
        if C.status(p).phase=="scouting" then inspected=true; walkSpeed=4 end
        if hasHistory(p,"Meditation") then break end
    end
    assert(inspected and p:getSquare()==origin and walkSpeed==4 and rate==40 and hasHistory(p,"Meditation"),
        "After a fruitless search the survivor gets home, resumes, and the player's fast-forward comes back")
    captureLog(nil)
    local events,at={"outbound","inspect","inspect-ended","return","home"},0
    for _,line in ipairs(trace) do
        local event=line:match("^trip%.(%S+)")
        if event==events[at+1] then
            at=at+1
            assert(line:find("leg 1 ",1,true) and line:find("need literature",1,true) and line:find("source container stock unconfirmed key unknown:6:0:0",1,true),line)
        end
    end
    assert(at==#events,"A failed probe logs every transition in order")
    C.stop(p); roaming.enabled=false; nearbyTarget=nil; walkSpeed=1
end)

test("owned walking is allowed but manual cancellation never forces a return", function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=40
    nearbyTarget={square=T.square(6,0),key="6:0:0"}
    assert(C.start(p,"meditation",false)); T.tick(p,false)
    p.moving=true; T.tick(p,false)
    assert(C.status(p).active, "Owned walk is not mistaken for user movement")
    C.stop(p,"Manual stop"); p.moving=false; T.tick(p)
    assert(#ISTimedActionQueue.getTimedActionQueue(p).queue==0 and not C.status(p).active)
    roaming.enabled=false; nearbyTarget=nil
end)

test("a failed native outbound path skips that container rather than treating residual motion as player input", function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=40
    local origin=p:getSquare(); local shelf=T.container(5,0)
    local book=T.add(shelf,T.item("Literature")); p.available={shelf}
    nearbyTarget={square=T.square(2,0),key="blocked",next={square=shelf.square,key="book"}}
    assert(C.start(p,"meditation",false)); T.tick(p,false)
    local walk=ISTimedActionQueue.getTimedActionQueue(p).queue[1]
    walk.result=BehaviorResult.Failed; walk:stop()
    p.moving=true; T.tick(p,false); p.moving=false
    for i=1,20 do T.tick(p); if hasHistory(p,"Meditation") then break end end
    assert(C.status(p).active and hasHistory(p,"read") and hasHistory(p,"Meditation"))
    assert(shelf:contains(book) and p:getSquare()==origin)
    C.stop(p); roaming.enabled=false; nearbyTarget=nil
end)

test("a player-cancelled walk does not retry or queue a return", function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=40
    nearbyTarget={square=T.square(5,0),key="shelf"}
    assert(C.start(p,"meditation",false)); T.tick(p,false)
    local walk=ISTimedActionQueue.getTimedActionQueue(p).queue[1]
    p.cancelInput=true; walk:stop(); T.tick(p,false)
    assert(not C.status(p).active and #ISTimedActionQueue.getTimedActionQueue(p).queue==0)
    roaming.enabled=false; nearbyTarget=nil
end)

test("blocked homeward path stops instead of training away from origin", function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=40
    local shelf=T.container(6,0); T.add(shelf,T.item("Literature")); p.available={shelf}
    nearbyTarget={square=shelf.square,key="6:0:0"}
    assert(C.start(p,"meditation",false))
    for i=1,15 do
        T.tick(p,false)
        local q=ISTimedActionQueue.getTimedActionQueue(p).queue
        if q[1] then
            if q[1].Type=="ISWalkToTimedAction" and hasHistory(p,"read") then
                -- Stock reports successful completion, but the survivor is
                -- on the wrong adjacent tile. Only exact arrival may resume.
                p.pathBlocked=true
                p.square=T.square(1,0)
            end
            q[1]:perform()
        end
        if not C.status(p).active then break end
    end
    assert(not C.status(p).active and C.status(p).message:find("Could not return"))
    assert(not hasHistory(p,"Meditation"))
    roaming.enabled=false; nearbyTarget=nil
end)

local function walkCount(p)
    local count=0
    for _,kind in ipairs(p.history) do if kind=="ISWalkToTimedAction" then count=count+1 end end
    return count
end

local function nextAction(p)
    return ISTimedActionQueue.getTimedActionQueue(p).queue[1]
end

local function beginBookReturn(configure)
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=40
    local anchor=T.square(2,3,1); p.square=anchor; T.loadSquare(p,anchor)
    if configure then configure(p,anchor) end
    local shelf=T.container(8,3); shelf.square=T.square(8,3,1)
    local book=T.add(shelf,T.item("Literature")); p.available={shelf}
    nearbyTarget={square=shelf.square,key="home-retry-book"}
    assert(C.start(p,"meditation",false))
    for i=1,20 do
        T.tick(p,false)
        local head=nextAction(p)
        if head and head.Type=="ISWalkToTimedAction" and hasHistory(p,"read") then
            assert(shelf:contains(book) and C.status(p).pendingReturns==0,
                "The book loan must already be settled before walking home")
            assert(head.location==anchor and p:getSquare()~=anchor and walkCount(p)==2)
            return p,anchor,shelf,book,head
        elseif head then head:perform() end
    end
    error("Scout never read, returned, and started walking home")
end

local function failHome(walk)
    walk.result=BehaviorResult.Failed
    walk:stop()
end

local function stopBookTest(p)
    if C.status(p).active then C.stop(p) end
    roaming.enabled=false; nearbyTarget=nil
end

test("one genuine native failure retries only the fresh exact training XYZ after settling",function()
    local p,anchor,shelf,book,walk=beginBookReturn()
    failHome(walk)
    p.moving=true
    T.now=T.now+749; C.update(p)
    assert(C.status(p).active and not nextAction(p) and walkCount(p)==2 and #p.cards==0,
        "The first native path failure must neither stop nor requeue before 750ms")
    p.moving=false
    local fresh=T.square(2,3,1)
    T.loadSquare(p,fresh)
    anchor.x=901 -- the old native object no longer describes the saved anchor
    T.tick(p,false)
    local retry=nextAction(p)
    assert(retry and retry.Type=="ISWalkToTimedAction" and retry.location==fresh and walkCount(p)==3,
        "Re-resolve the original XYZ, never reuse stale userdata or walk to an adjacent tile")
    assert(not hasHistory(p,"Meditation"))
    -- The observed reading already satisfied this bout of boredom. The
    -- mock's stock target remains static, unlike a newly filtered live scan.
    p.values.BOREDOM=10
    retry:perform()
    for i=1,6 do T.tick(p,false); if hasHistory(p,"Meditation") then break end end
    assert(p:getSquare()==fresh and hasHistory(p,"Meditation") and #p.cards==0 and shelf:contains(book))
    local reads=0
    for _,kind in ipairs(p.history) do if kind=="read" then reads=reads+1 end end
    assert(reads==1 and C.status(p).pendingReturns==0, "Home recovery must not re-scout or replay the book")
    stopBookTest(p)
end)

-- Simulate the exact stock native start contract: integer pathToLocation
-- sets an X/Y tile center; setting floats before update changes that target.
-- No pathfinder or collision geometry is claimed by this controller double.
local function probeHomePosition(p, anchor, options)
    local getX, getY, getZ = p.getX, p.getY, p.getZ
    local function onTile(self) return self:getSquare() == anchor end
    function p:getX() if onTile(self) then return 2 + (options.x or 0.29) end; return getX(self) end
    function p:getY() if onTile(self) then return 3 + (options.y or 0.68) end; return getY(self) end
    function p:getZ() if onTile(self) then return 1 + (options.elevation or 0) end; return getZ(self) end
    p.sitting = options.seated == true
    p.furniture = options.furniture == true
    local probe = {calls={}, homeCenters=0}
    p.pathProbe = probe
    function p:getPathFindBehavior2() return self.pathProbe end
    function probe:pathToLocation(x,y,z)
        if x == 2 and y == 3 and z == 1 then self.homeCenters = self.homeCenters + 1 end
        self.x, self.y, self.z = x + 0.5, y + 0.5, z
        if self.homeCenters == 3 and options.changed then self.x = self.x + 0.15 end
        if self.homeCenters == 3 and options.retired then
            -- A reentrant start hook ended this head, but the path object's
            -- target fields still happen to match the requested tile center.
            local q=ISTimedActionQueue.getTimedActionQueue(p)
            q:resetQueue(); p.nativeHead=nil
        end
        self.calls[#self.calls+1] = {"stock",x,y,z}
    end
    if not options.absent then
        function probe:pathToLocationF(x,y,z)
            self.x, self.y, self.z = x,y,z
            self.calls[#self.calls+1] = {"precise",x,y,z}
        end
    end
    function probe:getTargetX() return self.x end
    function probe:getTargetY() return self.y end
    function probe:getTargetZ() return self.z end
end

local function settledRetry(p)
    for i=1,6 do if nextAction(p) then break end; T.tick(p,false) end
    local walk = nextAction(p)
    assert(walk and walk.Type=="ISWalkToTimedAction")
    return walk
end

test("the last home attempt targets the saved on-tile ground position after foreign work",function()
    local p,anchor,shelf,book,walk=beginBookReturn(function(player,square)
        probeHomePosition(player,square,{seated=true})
    end)
    local probe=p.pathProbe
    assert(probe.homeCenters==1 and probe.x==2.5 and probe.y==3.5 and probe.z==1)
    failHome(walk)
    walk=settledRetry(p)
    assert(probe.homeCenters==2 and probe.x==2.5 and probe.y==3.5 and probe.z==1)
    failHome(walk)
    local foreign=T.action(p,"OtherNativeWork")
    ISTimedActionQueue.add(foreign); T.tick(p,false)
    assert(nextAction(p)==foreign and probe.homeCenters==2 and #p.cards==0)
    foreign:perform()
    local fresh=T.square(2,3,1); T.loadSquare(p,fresh)
    -- The earlier book did satisfy all remaining reading need.
    p.values.BOREDOM=10
    walk=settledRetry(p)
    assert(walk.location==fresh and walkCount(p)==4 and probe.homeCenters==3)
    local called=probe.calls[#probe.calls]
    assert(called[1]=="precise" and called[2]==2.29 and called[3]==3.68 and called[4]==1,
        "The final retry should use only the original saved same-tile point")
    assert(probe.x==2.29 and probe.y==3.68 and probe.z==1)
    walk:perform()
    for i=1,6 do T.tick(p,false); if hasHistory(p,"Meditation") then break end end
    local reads=0
    for _,kind in ipairs(p.history) do if kind=="read" then reads=reads+1 end end
    assert(p:getSquare()==fresh and hasHistory(p,"Meditation") and #p.cards==0
        and reads==1 and shelf:contains(book) and C.status(p).pendingReturns==0)
    stopBookTest(p)
end)

test("unsupported, unsafe or superseded ground coordinates keep the normal three home attempts",function()
    for _,options in ipairs({{absent=true},{changed=true},{elevation=0.2},{x=-0.01},{x=0},{x=0.5,y=0.5},{furniture=true}}) do
        local p,_,_,_,walk=beginBookReturn(function(player,square) probeHomePosition(player,square,options) end)
        for i=1,3 do
            if i>1 then walk=settledRetry(p) end
            failHome(walk)
        end
        for i=1,7 do T.tick(p,false) end
        assert(p.pathProbe.homeCenters==3 and p.pathProbe.calls[#p.pathProbe.calls][1]=="stock")
        assert(not C.status(p).active and walkCount(p)==4 and #p.cards==1 and not nextAction(p))
        stopBookTest(p)
    end
end)

test("a reentrantly retired stock head cannot retarget a matching shared native path",function()
    local p,_,_,_,walk=beginBookReturn(function(player,square) probeHomePosition(player,square,{retired=true}) end)
    failHome(walk)
    failHome(settledRetry(p))
    for i=1,6 do T.tick(p,false) end
    local last=p.pathProbe.calls[#p.pathProbe.calls]
    assert(p.pathProbe.homeCenters==3 and last[1]=="stock" and not nextAction(p))
    assert(not C.status(p).active and #p.cards==1)
    stopBookTest(p)
end)

test("a genuine saved-point failure remains the third and last attempt",function()
    local p,_,_,_,walk=beginBookReturn(function(player,square) probeHomePosition(player,square,{}) end)
    for i=1,3 do
        if i>1 then walk=settledRetry(p) end
        failHome(walk)
    end
    for i=1,7 do T.tick(p,false) end
    assert(p.pathProbe.calls[#p.pathProbe.calls][1]=="precise","Final failure must be the precise attempt")
    assert(not C.status(p).active and walkCount(p)==4 and #p.cards==1 and not nextAction(p))
    stopBookTest(p)
end)

test("native path-only return retries stop on the third failed walk",function()
    local p,_,shelf,book,walk=beginBookReturn()
    for attempt=1,3 do
        assert(walk and walk.Type=="ISWalkToTimedAction" and walkCount(p)==attempt+1)
        failHome(walk)
        T.tick(p,false)
        if attempt<3 then
            assert(C.status(p).active and #p.cards==0)
            for i=1,4 do if nextAction(p) then break end; T.tick(p,false) end
            walk=nextAction(p)
        end
    end
    for i=1,8 do T.tick(p,false) end
    assert(not C.status(p).active and not nextAction(p) and walkCount(p)==4 and #p.cards==1)
    assert(C.status(p).message:lower():find("path",1,true) and not hasHistory(p,"Meditation") and shelf:contains(book))
    stopBookTest(p)
end)

test("foreign activity pauses the home retry without consuming or resetting its retry budget",function()
    local p,_,_,_,walk=beginBookReturn()
    failHome(walk)
    local seen={}
    local foreground=T.action(p,"ForeignWorkout",function() seen[#seen+1]="workout" end)
    local nextForeign=T.action(p,"ForeignDrink",function() seen[#seen+1]="drink" end)
    -- Both actions arrive in the same native event window as the failed walk.
    ISTimedActionQueue.add(foreground); ISTimedActionQueue.add(nextForeign)
    for i=1,3 do T.tick(p,false) end
    assert(C.status(p).active and walkCount(p)==2 and #p.cards==0 and nextAction(p)==foreground)
    assert(not foreground.stopped and not nextForeign.begins and not nextForeign.stopped)
    foreground:perform(); T.tick(p,false)
    assert(nextAction(p)==nextForeign and walkCount(p)==2)
    nextForeign:perform()
    assert(table.concat(seen,",")=="workout,drink")
    for attempt=2,3 do
        for i=1,6 do if nextAction(p) then break end; T.tick(p,false) end
        walk=nextAction(p)
        assert(walk and walk.Type=="ISWalkToTimedAction" and walkCount(p)==attempt+1)
        failHome(walk); T.tick(p,false)
    end
    for i=1,6 do T.tick(p,false) end
    assert(not C.status(p).active and walkCount(p)==4 and not nextAction(p) and not hasHistory(p,"Meditation"))
    stopBookTest(p)
end)

test("a native owned walk failure does not clear queued foreign successors while Java unwinds",function()
    local p,_,_,_,walk=beginBookReturn()
    local seen={}
    local first=T.action(p,"ForeignWorkout",function() seen[#seen+1]="workout" end)
    local second=T.action(p,"ForeignDrink",function() seen[#seen+1]="drink" end)
    ISTimedActionQueue.add(first); ISTimedActionQueue.add(second)
    -- Leave the native handle live after the Lua stop callback returns.
    p.nativeAdditional={walk.action}
    failHome(walk)
    assert(not first.begins and not second.begins and not first.cancelled and not second.cancelled)
    T.tick(p,false)
    assert(walkCount(p)==2 and not first.begins and not second.begins)
    p.nativeAdditional={}
    for i=1,3 do if nextAction(p)==first then break end; T.tick(p,false) end
    assert(nextAction(p)==first and first.begins==1 and not second.begins)
    first:perform()
    assert(nextAction(p)==second and second.begins==1)
    second:perform()
    assert(table.concat(seen,",")=="workout,drink")
    for i=1,6 do if nextAction(p) then break end; T.tick(p,false) end
    assert(C.status(p).active and walkCount(p)==3 and nextAction(p).Type=="ISWalkToTimedAction")
    stopBookTest(p)
end)

test("an unacknowledged stopped native return gives stock queue handling back without forcing a foreign action",function()
    local p,_,_,_,walk=beginBookReturn()
    local q=ISTimedActionQueue.getTimedActionQueue(p)
    local previous=q.tick
    local foreign=T.action(p,"ForeignDrink",function() error("Waiter ran while native action was live") end)
    ISTimedActionQueue.add(foreign)
    p.nativeAdditional={walk.action}
    failHome(walk)
    assert(q.tick~=previous and q.autoMindfulHandoff)
    for i=1,6 do T.tick(p,false) end
    assert(C.status(p).message:find("did not settle",1,true) and not C.status(p).active and #p.cards==1)
    assert(q.tick==previous and not q.autoMindfulHandoff and q.queue[1]==walk and q.queue[2]==foreign
        and not foreign.begins and not foreign.cancelled and walkCount(p)==2)
    p.nativeAdditional={}
    stopBookTest(p)
end)

test("a return retry does not spin on an unconfirmed busy flag or override disabled scouting",function()
    for _,condition in ipairs({"stale native busy","disabled scouting"}) do
        local p,_,_,_,walk=beginBookReturn()
        failHome(walk)
        T.now=T.now+300; C.update(p)
        assert(C.status(p).active and walkCount(p)==2)
        if condition=="stale native busy" then
            p.hasTimedActions=function() return true end -- no foreign Lua/native handle
            T.tick(p,false)
            assert(C.status(p).active and walkCount(p)==2, "Wait briefly for stale busy state")
        else
            roaming.enabled=false
        end
        for i=1,10 do T.tick(p,false) end
        assert(not C.status(p).active and walkCount(p)==2 and #p.cards==1 and not nextAction(p)
            and not hasHistory(p,"Meditation"))
        stopBookTest(p)
    end
end)

test("failed return never retargets or retries if the exact origin unloads, changes floor, or becomes forbidden",function()
    local oldCell,oldSafe,oldClient=getCell,SafeHouse,T.client
    local ok,reason=pcall(function()
        for _,fault in ipairs({"unloaded","different coordinate","different floor","access denied"}) do
            local p,_,_,_,walk=beginBookReturn()
            failHome(walk)
            local resolved=0
            local replacement=T.square(fault=="different coordinate" and 3 or 2,3,fault=="different floor" and 0 or 1)
            getCell=function() return {getGridSquare=function(_,x,y,z)
                assert(x==2 and y==3 and z==1,"Home recovery may query only the original coordinates")
                resolved=resolved+1
                if fault~="unloaded" then return replacement end
            end} end
            T.client=true
            SafeHouse={isSafehouseAllowInteract=function() return fault~="access denied" end,
                isSafehouseAllowLoot=function() return true end}
            for i=1,8 do T.tick(p,false) end
            assert(resolved>0 and not C.status(p).active and walkCount(p)==2 and not nextAction(p)
                and not hasHistory(p,"Meditation"))
            getCell,SafeHouse,T.client=oldCell,oldSafe,oldClient
            stopBookTest(p)
        end
    end)
    getCell,SafeHouse,T.client=oldCell,oldSafe,oldClient
    assert(ok,reason)
end)

test("manual controls and danger cancel home retry without a new walk",function()
    local interrupts={
        function(p) C.stop(p,"Stop") end,
        function(p) p.cancelInput=true end,
        function(p) p.aiming=true end,
        function(p) p.sprinting=true; p.rawMovementInput=true end,
        function(p) p.square=T.square(7,3,0) end,
    }
    do
        local p,_,_,_,walk=beginBookReturn()
        failHome(walk)
        T.now=T.now+300; C.update(p)
        p.zombies=1
        for i=1,20 do T.tick(p,false) end
        assert(C.status(p).active and C.status(p).phase=="recovery-paused" and walkCount(p)==2 and not nextAction(p),
            "Nearby danger holds the job and starts no walk")
        stopBookTest(p)
    end
    for _,interrupt in ipairs(interrupts) do
        local p,_,_,_,walk=beginBookReturn()
        failHome(walk)
        T.now=T.now+300; C.update(p)
        assert(C.status(p).active and walkCount(p)==2)
        interrupt(p)
        for i=1,6 do T.tick(p,false) end
        assert(not C.status(p).active and walkCount(p)==2 and #p.cards==1
            and not nextAction(p) and not hasHistory(p,"Meditation"))
        stopBookTest(p)
    end
end)

test("a native return failure with only a stale sprint flag still gets its bounded retry",function()
    local p,origin,_,_,walk=beginBookReturn()
    p.sprinting=true
    failHome(walk)
    T.now=T.now+800; C.update(p)
    p.sprinting=false
    local fresh=settledRetry(p)
    assert(fresh~=walk and walkCount(p)==3 and C.status(p).active and #p.cards==0)
    p.values.BOREDOM=0
    fresh:perform()
    for _=1,6 do T.tick(p,false); if C.status(p).phase=="meditation" then break end end
    assert(C.status(p).active and C.status(p).phase=="meditation" and p:getSquare()==origin)
    stopBookTest(p)
end)

test("transient deliberate input in the native home stop is not mistaken for a retryable failure",function()
    for _,key in ipairs({"aiming","cancelInput","sprinting"}) do
        local p,_,_,_,walk=beginBookReturn()
        p[key]=true; p.rawMovementInput=key=="sprinting"
        failHome(walk)
        p[key]=false; p.rawMovementInput=false
        for i=1,7 do T.tick(p,false) end
        assert(not C.status(p).active and walkCount(p)==2 and #p.cards==1
            and not nextAction(p) and not hasHistory(p,"Meditation"))
        stopBookTest(p)
    end
end)

test("walking that interrupts a native return abandons the old route without disarming",function()
    local p,origin,_,_,walk=beginBookReturn()
    local here=T.square(6,0)
    p.movementInput=true
    failHome(walk)
    p.square=here
    p.movementInput=false -- input released before AutoMindful's next poll
    p.values.BOREDOM=0
    for i=1,10 do T.tick(p,false); if hasHistory(p,"Meditation") then break end end
    assert(C.status(p).active and p:getSquare()==here and here~=origin and walkCount(p)==2
        and hasHistory(p,"Meditation"),"Resume at the new position instead of walking back")
    stopBookTest(p)
end)

test("radius preview shows known distant stock and unknown containers without walking", function()
    local p=T.playerNew(); local shelf=T.container(7,0)
    local food=T.add(shelf,T.item("Food")); local book=T.add(shelf,T.item("Literature"))
    nearbyArea={radius=10, food={{item=food,owned=false}},water={},literature={{item=book,owned=false}},
        waterSources={},unknownTargets={{square=shelf.square}},containerCount=2,unloadedSquares=0}
    local report=C.prepare(p,false,true,true)
    assert(report.nearbyFood==1 and report.nearbyLiterature==1 and report.unknownContainers==1)
    assert(report.radius==10 and report.walkingEnabled==false)
    assert(#ISTimedActionQueue.getTimedActionQueue(p).queue==0 and shelf:contains(food))
    roaming.enabled=true
    report=C.prepare(p,false,true)
    assert(report.walkingEnabled and not report.message:find("collection is off"))
    roaming.enabled=false; nearbyArea=nil
end)

test("unknown container scouting waits for native adjacent contents then uses and returns", function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=25
    local origin=p:getSquare(); local shelf=T.container(6,0); p.available={shelf}
    nearbyTarget={square=shelf.square,key="unknown:6:0:0",unknown=true,container=shelf}
    local refresh=p.lootPage.refreshBackpacks; local appeared=false; local started=T.now
    p.lootPage.refreshBackpacks=function()
        refresh()
        if not appeared and p:getSquare():canReachTo(shelf.square) and T.now >= started+3000 then
            T.add(shelf,T.item("Literature")); appeared=true
        end
    end
    assert(C.start(p,"meditation",false))
    for i=1,20 do T.tick(p); if hasHistory(p,"Meditation") then break end end
    assert(appeared and hasHistory(p,"read") and hasHistory(p,"Meditation"))
    assert(p:getSquare()==origin and #shelf.items==1, "Borrowed book and survivor return to their own origins")
    C.stop(p); roaming.enabled=false; nearbyTarget=nil
end)

test("blocked meditation scouts unknown literature before stopping", function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=40
    local origin=p:getSquare(); local shelf=T.container(6,0); p.available={shelf}
    nearbyTarget={square=shelf.square,key="unknown:6:0:0",unknown=true,container=shelf}
    local refresh=p.lootPage.refreshBackpacks; local appeared=false; local started=T.now
    p.lootPage.refreshBackpacks=function()
        refresh()
        if not appeared and p:getSquare():canReachTo(shelf.square) and T.now >= started+3000 then
            T.add(shelf,T.item("Literature")); appeared=true
        end
    end
    assert(C.start(p,"meditation",false))
    for i=1,20 do T.tick(p); if hasHistory(p,"Meditation") then break end end
    assert(appeared and hasHistory(p,"read") and hasHistory(p,"Meditation"))
    assert(p:getSquare()==origin and #shelf.items==1, "Borrowed book and survivor return to their own origins")
    C.stop(p); roaming.enabled=false; nearbyTarget=nil
end)

test("unknown adjacent container inspection does not walk and times out with cooldown", function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=25
    local shelf=T.container(1,0); p.available={shelf}
    nearbyTarget={square=shelf.square,key="unknown:1:0:0",unknown=true,container=shelf}
    assert(C.start(p,"meditation",false))
    T.tick(p,false); assert(C.status(p).phase=="scouting")
    assert(#ISTimedActionQueue.getTimedActionQueue(p).queue==0)
    for i=1,6 do T.tick(p) end
    assert(not hasHistory(p,"ISWalkToTimedAction") and not hasHistory(p,"read"))
    assert(hasHistory(p,"Meditation"), "Unavailable optional care must not create endless scouting")
    C.stop(p); roaming.enabled=false; nearbyTarget=nil
end)

test("disabling walking during container inspection returns home without consuming", function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=25
    local origin=p:getSquare(); local shelf=T.container(6,0); p.available={shelf}
    nearbyTarget={square=shelf.square,key="unknown:6:0:0",unknown=true,container=shelf}
    assert(C.start(p,"meditation",false)); T.tick(p); T.tick(p,false)
    assert(C.status(p).phase=="scouting")
    roaming.enabled=false
    for i=1,5 do T.tick(p) end
    assert(p:getSquare()==origin and not hasHistory(p,"read"))
    C.stop(p); nearbyTarget=nil
end)

test("unknown MP stock never preempts an admissible or already running selected practice",function()
    T.client,roaming.enabled=true,true
    for _,mode in ipairs({"meditation","yoga","both"}) do
        local p=T.playerNew()
        p.sitting=mode=="meditation"
        p.values.BOREDOM,p.values.HUNGER,p.values.THIRST=24,.66,.55
        nearbyTarget={square=T.square(6,0),key="unknown:6:0:0",unknown=true}
        assert(C.start(p,mode,false))
        for i=1,8 do T.tick(p,false) end
        local q=ISTimedActionQueue.getTimedActionQueue(p).queue
        assert(q[1] and (q[1].Type=="Yoga" or q[1].Type=="Meditation") and not q[1].stopped)
        local first=q[1]; for i=1,6 do T.tick(p,false) end
        assert(q[1]==first and not hasHistory(p,"ISWalkToTimedAction"))
        C.stop(p)
    end
    -- A genuine gate is different: an unknown book case can still be inspected
    -- if Meditation is the only selected mode and cannot currently start.
    local p=T.playerNew(); p.values.BOREDOM=40
    assert(C.start(p,"meditation",false)); T.tick(p,false)
    assert(hasHistory(p,"ISWalkToTimedAction"))
    C.stop(p); T.client,roaming.enabled,nearbyTarget=false,false,nil
end)

test("first hunger and thirst moodles allow bounded opted-in discovery at the next practice boundary",function()
    local previous=SafeHouse
    SafeHouse={isSafehouseAllowInteract=function() return true end,isSafehouseAllowLoot=function() return true end}
    T.client=true
    for _,mode in ipairs({"yoga","recovery"}) do
        for _,kind in ipairs({"food","water"}) do
            roaming.enabled=true
            local p=T.playerNew(); p.meditation=0; local home=p:getSquare()
            local shelf=T.container(5,0); p.available={shelf}
            nearbyTarget={square=shelf.square,key="unknown:5:0:0",unknown=true,container=shelf}
            assert(C.start(p,mode,false)); for _=1,5 do T.tick(p,false) end
            if kind=="water" then p.values.THIRST,p.thirstMoodle=.08,1
            else p.values.HUNGER,p.hungerMoodle=.08,1 end
            if mode=="yoga" then
                for _=1,12 do T.tick(p,false) end
                assert(not hasHistory(p,"ISWalkToTimedAction"),"Never break a practice to look into an unknown container")
                T.tick(p)
            end
            for _=1,12 do T.tick(p,false); if hasHistory(p,"ISWalkToTimedAction") then break end end
            assert(hasHistory(p,"ISWalkToTimedAction") and C.status(p).active,mode..":"..kind)
            for _=1,20 do T.tick(p) end
            assert(p:getSquare()==home and not hasHistory(p,"eat") and not hasHistory(p,"drink"),
                "An empty response never becomes a meal or drink, and walking is bounded")
            C.stop(p)
            local off=T.playerNew(); roaming.enabled=false
            off.values.HUNGER,off.values.THIRST,off.hungerMoodle,off.thirstMoodle=.08,.08,1,1
            assert(C.start(off,mode,false)); for _=1,12 do T.tick(off,false) end
            assert(not hasHistory(off,"ISWalkToTimedAction"),"Moodles cannot grant new trip permissions")
            C.stop(off)
        end
    end
    T.client,roaming.enabled,nearbyTarget=false,false,nil
    SafeHouse=previous
end)

test("critical care exhausts bounded alternate known paths, never an unknown substitute",function()
    local original=luautils.walkAdj
    roaming.enabled=true
    for _,kind in ipairs({"food","water"}) do
        local p=T.playerNew(); local available=T.container(9,0)
        if kind=="food" then p.hungerMoodle,p.values.HUNGER=4,.8
        else p.thirstMoodle,p.values.THIRST=4,.8 end
        local first,last
        for i=1,6 do
            local t={square=i==6 and available.square or T.square(i+2,0),key=kind..":"..i}
            if last then last.next=t else first=t end; last=t
        end
        last.next={square=T.square(2,0),key="unknown",unknown=true}
        nearbyTarget=first
        local attempts=0
        luautils.walkAdj=function(player,square,keep)
            attempts=attempts+1
            if square==available.square then return original(player,square,keep) end
            return false
        end
        assert(C.start(p,"meditation",false)); T.tick(p,false)
        assert(C.status(p).active and attempts==4 and not hasHistory(p,"ISWalkToTimedAction"))
        T.tick(p,false)
        assert(C.status(p).active and attempts==6 and hasHistory(p,"ISWalkToTimedAction"))
        C.stop(p)
    end
    luautils.walkAdj=original; roaming.enabled=false; nearbyTarget=nil
end)

test("switching scouting off releases a pending outbound walk without consuming or stopping a foreign waiter", function()
    local p=T.playerNew(); p.values.BOREDOM=40; p.sitting=false; local home=p:getSquare()
    roaming.enabled=true; nearbyTarget={square=T.square(6,0),key="literature:6:0:0"}
    assert(C.start(p,"meditation",false)); T.tick(p,false)
    local q=ISTimedActionQueue.getTimedActionQueue(p).queue; local walk=q[1]
    assert(walk and walk.Type=="ISWalkToTimedAction")
    local foreign=T.action(p,"PlayerWork"); ISTimedActionQueue.add(foreign)
    roaming.enabled=false; C.update(p)
    assert(walk.stopped and q[1]==foreign and not foreign.stopped and p:getSquare()==home and not hasHistory(p,"read"))
    C.stop(p); nearbyTarget=nil
end)

test("an owned route ignores a 31-second pause, but times out after witnessed lack of progress",function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=40
    nearbyTarget={square=T.square(9,0),key="literature:9:0:0"}
    assert(C.start(p,"meditation",false)); T.tick(p,false)
    local walk=ISTimedActionQueue.getTimedActionQueue(p).queue[1]; assert(walk.Type=="ISWalkToTimedAction")
    T.tick(p,false)
    T.now=T.now+31000; C.update(p)
    assert(C.status(p).active and not walk.stopped,"A missing 31 seconds of sampling is not a stalled native walk")
    -- Even a long real journey is not a stall while moving.
    for i=1,40 do p.x=.5+i*.15; T.tick(p,false) end
    assert(C.status(p).active and not walk.stopped)
    walkSpeed=0
    for i=1,40 do T.now=T.now+1000; Events.OnTickEvenPaused.callback() end
    walkSpeed=1
    for i=1,28 do T.tick(p,false) end
    assert(C.status(p).active and not walk.stopped,"Paused seconds are not charged")
    for i=1,5 do T.tick(p,false) end
    assert(not C.status(p).active and walk.stopped and #p.cards==1 and not hasHistory(p,"read"))
    roaming.enabled=false; nearbyTarget=nil
end)

test("a continuously stalled known water walk releases only itself and tries the next source",function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.THIRST=.7; p.thirstMoodle=4
    local origin=p:getSquare()
    local cupboard=T.container(7,0); T.add(cupboard,T.water()); p.available={cupboard}
    nearbyTarget={square=T.square(3,0),key="water:stall",routeLayout="standing room",
        next={square=cupboard.square,key="water:cupboard",container=cupboard}}
    assert(C.start(p,"meditation",false)); T.tick(p,false)
    local stuck=ISTimedActionQueue.getTimedActionQueue(p).queue[1]; assert(stuck.Type=="ISWalkToTimedAction")
    for i=1,35 do
        T.tick(p,false)
        if stuck.stopped then break end
    end
    assert(stuck.stopped and C.status(p).active and not hasHistory(p,"drink"))
    for i=1,25 do
        T.tick(p)
        if p.values.THIRST<.7 then p.thirstMoodle=0 end -- native moodle follows actual intake
        if hasHistory(p,"Meditation") then break end
    end
    assert(hasHistory(p,"drink") and p.values.THIRST<.7 and p:getSquare()==origin and hasHistory(p,"Meditation"))
    C.stop(p); roaming.enabled=false; nearbyTarget=nil
end)

test("a critical need with nothing known looks into nearby containers, a bounded number of times", function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.HUNGER=.8; p.hungerMoodle=4
    local shelf=T.container(6,0)
    nearbyTarget={square=shelf.square,key="unknown:6:0:0",unknown=true,container=shelf}
    assert(C.start(p,"meditation",false))
    for i=1,100 do T.tick(p) end
    local walks=0
    for _,kind in ipairs(p.history) do if kind=="ISWalkToTimedAction" then walks=walks+1 end end
    assert(C.status(p).active and C.status(p).message:find("Starving"))
    assert(walks>0,"Standing still until death beside an unopened container helps nobody")
    assert(walks<=8,"Three fruitless looks, then back off: "..walks)
    C.stop(p)
    roaming.enabled=false; nearbyTarget=nil
end)


local function vehicleSource(p, id)
    local source=T.container(12,0); local area=T.square(6,0)
    local vehicle={speed=0,accessible=true}
    local part={id=id or "TruckBedOpen"}
    function vehicle:getCurrentAbsoluteSpeedKmHour() return self.speed end
    function vehicle:getSquare() return source.square end
    function vehicle:getSquareForArea() return self.movedArea or area end
    function vehicle:canAccessContainer() return self.accessible and p:getSquare()==area end
    function vehicle:getPartById() return nil end
    function part:getItemContainer() return source end
    function part:getVehicle() return vehicle end
    function part:getArea() return "TruckBed" end
    function part:getId() return self.id end
    function part:getIndex() return 0 end
    function part:isInventoryItemUninstalled() return false end
    function part:getContainerCapacity() return 50 end
    function source:getVehiclePart() return part end
    p.lootPage.refreshBackpacks=function() p.nearby=vehicle:canAccessContainer() and {source} or {} end
    return source,part,vehicle,area
end
ISPathFindAction={pathToVehicleArea=function(_, p, vehicle, areaName)
    assert(areaName=="TruckBed")
    return T.action(p,"ISPathFindAction",function()
        if not p.pathBlocked then p.square=vehicle:getSquareForArea(areaName) end
    end)
end}

test("vehicle care uses exact native interaction area and returns loan before home",function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=40
    local origin=p:getSquare(); local source,part,vehicle,area=vehicleSource(p)
    local book=T.add(source,T.item("Literature"))
    nearbyTarget={square=area,key="vehicle-book",part=part}
    assert(C.start(p,"meditation",false)); T.tick(p,false)
    p.moving=true; T.tick(p,false)
    assert(C.status(p).active,"Owned native vehicle-area path is not manual movement")
    p.moving=false
    for i=1,20 do T.tick(p); if hasHistory(p,"Meditation") then break end end
    assert(hasHistory(p,"ISPathFindAction") and hasHistory(p,"read") and source:contains(book))
    assert(p:getSquare()==origin and hasHistory(p,"Meditation"))
    C.stop(p); roaming.enabled=false; nearbyTarget=nil
end)

test("vehicle native access denial never transfers even after area arrival",function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=40
    local origin=p:getSquare(); local source,part,vehicle,area=vehicleSource(p)
    local book=T.add(source,T.item("Literature")); vehicle.accessible=false
    nearbyTarget={square=area,key="denied-vehicle",part=part,unknown=true}
    assert(C.start(p,"meditation",false))
    for i=1,15 do T.tick(p); if hasHistory(p,"Meditation") then break end end
    assert(not hasHistory(p,"read") and source:contains(book) and p:getSquare()==origin)
    C.stop(p); roaming.enabled=false; nearbyTarget=nil
end)

test("a vehicle that drives off ends that trip, not the session",function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=40
    local source,part,vehicle,area=vehicleSource(p)
    nearbyTarget={square=area,key="moving-vehicle",part=part}
    assert(C.start(p,"meditation",false)); T.tick(p,false)
    local pursuit=ISTimedActionQueue.getTimedActionQueue(p).queue[1]
    p.values.BOREDOM=5
    vehicle.speed=3; T.tick(p,false)
    assert(C.status(p).active and pursuit.stopped)
    for _=1,12 do T.tick(p); if hasHistory(p,"Meditation") then break end end
    assert(C.status(p).active and hasHistory(p,"Meditation"),"Training carries on without that source")
    C.stop(p)
    roaming.enabled=false; nearbyTarget=nil
end)
test("stationary but repositioned vehicle cannot pull a trip beyond its scanned target",function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=40
    local source,part,vehicle,area=vehicleSource(p)
    nearbyTarget={square=area,key="relocated-vehicle",part=part}
    assert(C.start(p,"meditation",false)); T.tick(p,false)
    local pursuit=ISTimedActionQueue.getTimedActionQueue(p).queue[1]
    p.values.BOREDOM=5
    vehicle.movedArea=T.square(50,0); T.tick(p,false)
    assert(C.status(p).active and pursuit.stopped)
    for _=1,12 do T.tick(p); if hasHistory(p,"Meditation") then break end end
    assert(p:getSquare()~=vehicle.movedArea and hasHistory(p,"Meditation"))
    C.stop(p)
    roaming.enabled=false; nearbyTarget=nil
end)

test("storage transfers recheck vehicle access and corpse safety while queued",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew(); local source,part,vehicle,area=vehicleSource(p)
    p.square=area; local book=T.add(source,T.item("Literature"))
    assert(S.transfer(p,book)); local q=ISTimedActionQueue.getTimedActionQueue(p).queue
    assert(q[1]:isValid()); vehicle.accessible=false; assert(not q[1]:isValid())
    ISTimedActionQueue.clear(p)
    local corpse=T.container(6,0)
    local body={kind="IsoDeadBody",reanimate=-1}
    function body:isAnimal() return false end
    function body:isFakeDead() return false end
    function body:getReanimateTime() return self.reanimate end
    function body:getSquare() return corpse.square end
    function corpse:getParent() return body end
    local corpseBook=T.add(corpse,T.item("Literature"))
    assert(S.transfer(p,corpseBook)); q=ISTimedActionQueue.getTimedActionQueue(p).queue
    assert(q[1]:isValid()); body.reanimate=0; assert(not q[1]:isValid())
    ISTimedActionQueue.clear(p)
end)

test("corpse care reads direct storage and returns its loan before going home",function()
    roaming.enabled=true
    local p=T.playerNew(); p.values.BOREDOM=25
    local origin=p:getSquare(); local corpse=T.container(6,0); p.available={corpse}
    local body={kind="IsoDeadBody"}
    function body:isAnimal() return false end
    function body:isFakeDead() return false end
    function body:getReanimateTime() return -1 end
    function body:getSquare() return corpse.square end
    function corpse:getParent() return body end
    local book=T.add(corpse,T.item("Literature"))
    nearbyTarget={square=corpse.square,key="corpse",container=corpse}
    assert(C.start(p,"meditation",false))
    for i=1,20 do T.tick(p); if hasHistory(p,"Meditation") then break end end
    assert(hasHistory(p,"read") and corpse:contains(book) and p:getSquare()==origin)
    C.stop(p); roaming.enabled=false; nearbyTarget=nil
end)

local cooperative = loadTest and loadTest("cooperative_actions.lua") or assert(loadfile("tests/cooperative_actions.lua"))()
cooperative(T, C, test, function(target) nearbyTarget=target; roaming.enabled=target~=nil end)

local resume = loadTest and loadTest("training_resume.lua") or assert(loadfile("tests/training_resume.lua"))()
resume(T, C, test)

print("CONTRACTS PASS "..passed.." cases; game boundaries are explicit doubles, not gameplay evidence")
if not loadTest then function loadTest(name) return assert(loadfile("tests/"..name))() end end
if not readReference and arg and arg[1] then
    local root=arg[1]
    function readReference(name) local f=assert(io.open(root.."/"..name,"rb")); local text=f:read("*a"); f:close(); return text end
    function loadUpstream(name) return assert(loadstring(readReference("lua/"..name),name))() end
end
if loadUpstream then loadTest("upstream.lua") end
