require "ISUI/ISContextMenu"
require "ISUI/ISToolTip"
local Tiers = require "AutoMindful/TierTargets"

local Menu = {}
local actions = { meditation="meditateTo", yoga="yogaTo" }
local verbs = { meditation="Meditate to...", yoga="Do Yoga to..." }
function Menu.title(kind) return verbs[kind] end

function Menu.fill(menu, player, kind, status, launch)
    local current = Tiers.current(player, kind)
    local skill = tonumber(status[kind])
    for _, entry in ipairs(Tiers.choices(kind)) do
        if entry.tier > 0 then
            local reason
            if not Tiers.providerCompatible() then
                reason = "Numeric tier goals are not verified for this Lifestyle version."
            elseif not Tiers.wellnessEnabled() then
                reason = "Lifestyle Wellness is disabled."
            elseif current ~= nil and current >= entry.tier then
                reason = "Already at this tier or higher."
            elseif skill == nil or current == nil then
                reason = "Current skill or moodle is unavailable."
            elseif Tiers.clamp(kind,entry.tier,skill) ~= entry.tier then
                reason = "Unlocks at level " .. entry.rank .. "."
            elseif status.active then
                reason = "Stop the current AutoMindful mode before starting a tier goal."
            end
            local row = menu:addOption(entry.label, player, launch, actions[kind], entry.tier)
            if row then
                row.iconTexture, row.color = Tiers.texture(kind, entry.tier)
                row.notAvailable = reason ~= nil
                if not row.iconTexture then row.color = nil end
                local tip = ISToolTip:new()
                tip:initialise()
                tip:setName(entry.label)
                tip.description = reason or "Practice until this moodle tier is reached, then stop. Your other actions still take priority."
                tip:setContextMenu(menu)
                row.toolTip = tip
            end
        end
    end
end

return Menu
