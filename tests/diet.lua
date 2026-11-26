-- The diet goal nudges food choice toward the survivor's goal, by a bounded
-- amount, and Auto steers back toward a healthy weight.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T=AutoMindfulTest
local Options=require "AutoMindful/Options"
local Diet=require "AutoMindful/Diet"
local Kitchen=require "AutoMindful/Kitchen"
local function passed(text) print("PASS "..text) end
local goal="auto"
Options.dietGoal=function() return goal end
local function food(p)
    local item=T.item("Food",p)
    function item:getProteins() return self.protein or 0 end
    function item:getCarbohydrates() return self.carbs or 0 end
    function item:getLipids() return 0 end
    function item:getCalories() return self.calories or 500 end
    return item
end
local function survivor(kg)
    local p=T.playerNew()
    function p:getNutrition() return {getWeight=function() return kg end} end
    return p
end

assert(Diet.goal(survivor(60))=="more" and Diet.goal(survivor(95))=="fewer" and Diet.goal(survivor(80))=="balanced",
    "Auto: gain when light, lose when heavy, balanced in between")
assert(Diet.goal(T.playerNew())=="balanced","No weight known: balanced")
passed("Auto follows the survivor's weight")

local steak=food({hunger=-.4,protein=40,calories=600,carbs=0})
local bread=food({hunger=-.4,protein=4,calories=900,carbs=120})
local salad=food({hunger=-.4,protein=2,calories=150,carbs=10})
goal="protein"; assert(Diet.score(survivor(80),steak)>Diet.score(survivor(80),bread))
goal="more"; assert(Diet.score(survivor(80),bread)>Diet.score(survivor(80),salad))
goal="fewer"; assert(Diet.score(survivor(80),salad)>Diet.score(survivor(80),bread))
goal="lowcarb"; assert(Diet.score(survivor(80),steak)>Diet.score(survivor(80),bread))
goal="balanced"; assert(Diet.score(survivor(80),steak)==0 and Diet.adjust(survivor(80),0.5,steak)==0.5)
passed("each goal prefers the food it should")

for _,g in ipairs({"protein","more","fewer","lowcarb"}) do
    goal=g
    for _,item in ipairs({steak,bread,salad,food({hunger=-.01,protein=999,calories=99999,carbs=999})}) do
        local u=Diet.adjust(survivor(80),1,item)
        assert(u>=1-Diet.nudge-1e-9 and u<=1+Diet.nudge+1e-9,"A nudge, never more: "..g.." "..u)
    end
end
goal="protein"
assert(Diet.adjust(survivor(80),-0.2,steak)>Diet.adjust(survivor(80),-0.2,bread),"Below zero the goal still moves the right way")
passed("the nudge is bounded, so the need still decides")

do
    goal="protein"
    local p=survivor(80)
    local function entry(item) return {item=item,carried=true} end
    for _,item in ipairs({steak,bread}) do
        function item:getOffAge() return 3 end
        function item:getAge() return 0 end
    end
    assert(Kitchen.choose({entry(bread),entry(steak)},p).item==steak,"High protein: the steak is cooked first")
    passed("the kitchen follows the diet goal too")
end

do
    goal="more"
    local p=survivor(80)
    local dense=food({hunger=-.1,protein=0,calories=400})
    local filling=food({hunger=-.3,protein=0,calories=60})
    for _,item in ipairs({dense,filling}) do
        function item:getOffAge() return 3 end
        function item:getAge() return 0 end
    end
    assert(Kitchen.choose({{item=dense,carried=true},{item=filling,carried=true}},p).item==filling,
        "A goal never picks a dish that fills a third as much")
    passed("the kitchen's diet preference never outweighs hunger")
end
