-- Unmodified pinned B42 pane AND native skill-bar code; only game/UI boundaries doubled.
AutoMindfulSkillsHarnessOnly=true
local H=loadTest and loadTest("skills_pane.lua") or assert(loadfile("tests/skills_pane.lua"))()
AutoMindfulSkillsHarnessOnly=nil
local function stock(path)
 if loadUpstream then return loadUpstream(path)end
 return assert(loadfile(assert(arg[1],"Pass game media root").."/lua/"..path))()
end
stock("client/XpSystem/ISUI/ISSkillProgressBar.lua")
stock("client/XpSystem/ISUI/ISCharacterInfo.lua")
H.run()
