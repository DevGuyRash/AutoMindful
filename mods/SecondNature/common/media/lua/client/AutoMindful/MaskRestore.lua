-- The native eating/drinking entry points (and WaterSources) load the stock
-- wear action before there can be a mask receipt to restore.
local MaskRestore = {}
local acknowledgementMs, maxRestoreAttempts = 5000, 2

local function snapshot(player)
    local ok, items = pcall(function()
        local worn, result = player:getWornItems(), {}
        for i = 0, worn:size()-1 do
            local entry = worn:get(i)
            local item = entry:getItem()
            result[item:getID()] = {slot=entry:getLocation(), fullType=item:getFullType()}
        end
        return result
    end)
    if ok then return items end
end

local function same(a, b)
    return a and b and a.slot == b.slot and a.fullType == b.fullType
end

local function stable(receipt, current)
    if not current then return false end
    for id, entry in pairs(receipt.worn) do
        if id ~= receipt.id and not same(entry, current[id]) then return false end
    end
    for id, entry in pairs(current) do
        if not same(entry, receipt.worn[id]) then return false end
    end
    return true
end

local function binding(item)
    if item:hasTag(ItemTag.REPLACE_PRIMARY) then return nil end
    local wearable = instanceof(item, "InventoryContainer") or item:hasTag(ItemTag.WEARABLE)
    if wearable and item:canBeEquipped() ~= "" then return item:canBeEquipped() end
    if item:getCategory() == "Clothing" or item:getCategory() == "AlarmClock" then return item:getBodyLocation() end
end

function MaskRestore.capture(player)
    local ok, receipt = pcall(function()
        local item = ISInventoryPaneContextMenu.getEatingMask(player, false)
        if not item then return nil end
        local worn, id = snapshot(player), item:getID()
        if worn and worn[id] and worn[id].slot == binding(item) then
            return {worn=worn, id=id, slot=worn[id].slot, fullType=item:getFullType(), attempts=0}
        end
    end)
    if ok then return receipt end
end

local function exactItem(receipt, item)
    local kind = type(item)
    return (kind == "userdata" or kind == "table") and item.getID and item.getFullType
        and item:getID() == receipt.id and item:getFullType() == receipt.fullType
end

local function carriedMask(player, receipt)
    local inventory = player:getInventory()
    local item = inventory:getItemById(receipt.id)
    if exactItem(receipt, item) and item:getContainer() == inventory and binding(item) == receipt.slot then return item end
end

local function gearIntent(receipt, queue)
    for _, action in ipairs(queue) do
        if action ~= receipt.removal and action ~= receipt.plannedWear and action ~= receipt.restoring then
            -- Also respect moving/dropping the specific mask without a wear
            -- action. Ordinary workouts, maps and inventory jobs can finish.
            if action.clothingAction or action.Type == "ISWearClothing" or action.Type == "ISUnequipAction"
                    or exactItem(receipt, action.item) then return true end
        end
    end
    return false
end

local function guardWear(action, receipt)
    local native = action.isValid
    action.isValid = function(self, ...)
        local player = self.character
        if receipt.changed or not stable(receipt, snapshot(player)) or not carriedMask(player, receipt)
                or gearIntent(receipt, ISTimedActionQueue.getTimedActionQueue(player).queue) then return false end
        return native(self, ...)
    end
end

function MaskRestore.track(receipt, batch)
    if not receipt then return end
    for _, action in ipairs(batch) do
        if action.Type == "ISUnequipAction" and exactItem(receipt, action.item) then
            if receipt.removal then return end
            receipt.removal = action
        elseif receipt.removal and action.Type == "ISWearClothing" and exactItem(receipt, action.item) then
            if receipt.plannedWear then return end
            receipt.plannedWear = action
        end
    end
    if not receipt.removal then return end
    if receipt.plannedWear then guardWear(receipt.plannedWear, receipt) end
    return receipt
end

function MaskRestore.observe(player, receipt, queue)
    if not receipt or receipt.done then return end
    local worn = snapshot(player)
    if not stable(receipt, worn) or gearIntent(receipt, queue) then
        receipt.changed = true
        return
    end
    if worn[receipt.id] then
        if receipt.removed then receipt.done = true end
    elseif receipt.removal.autoMindfulFinished and not receipt.removal.autoMindfulStopped then
        -- The native animation alone is not enough on MP: also observe the
        -- survivor's actual worn state, and never write that state ourselves.
        receipt.removed = true
    end
end

-- Called only at a quiet, safe queue boundary, after the meal or manual work.
function MaskRestore.next(player, receipt, now)
    if receipt.done then return "done" end
    local worn = snapshot(player)
    local mask = worn and worn[receipt.id]
    if receipt.changed or not stable(receipt, worn) then return mask and "done" or "manual" end
    if not receipt.removal.autoMindfulFinished or receipt.removal.autoMindfulStopped then
        return mask and "done" or "manual"
    end
    local lastWear = receipt.restoring or receipt.plannedWear
    local wearFinished = lastWear and lastWear.autoMindfulFinished and not lastWear.autoMindfulStopped
    if mask or wearFinished then
        if mask and (wearFinished or not isClient()) then return "done" end
        if isClient() then
            -- A server may apply the unequip or rewear after client perform.
            -- Wait once rather than dispatch a duplicate stock wear action.
            if not receipt.waitAt or now < receipt.waitAt then receipt.waitAt = now end
            if now-receipt.waitAt < acknowledgementMs then return "wait" end
        end
        return mask and "done" or "manual"
    end
    if not receipt.removed or receipt.attempts >= maxRestoreAttempts then return "manual" end
    local item = carriedMask(player, receipt)
    if not item then return "manual" end
    local action = ISWearClothing:new(player, item, 50)
    guardWear(action, receipt)
    if not action:isValid() then return "manual" end
    receipt.waitAt, receipt.restoring, receipt.attempts = nil, action, receipt.attempts + 1
    return "wear", action
end

return MaskRestore
