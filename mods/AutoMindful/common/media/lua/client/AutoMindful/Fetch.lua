-- Food and things found anywhere nearby: in a container, a bag, or lying on
-- the floor. Where each is, whether it is still there, and the game's own
-- action that brings it into the survivor's inventory.
local Grid = require "AutoMindful/Grid"

local Fetch = {}

-- A found thing: {item, container} or {item, world} (lying on the floor).
-- holder: the bag lying on the floor that the container belongs to.
function Fetch.entry(item, container, world, carried, holder)
    local entry = {item = item, container = container, world = world, carried = carried, holder = holder}
    local square = Fetch.square(entry)
    entry.from = carried and "carried" or (square and Grid.key(square)) or tostring(container)
    return entry
end

local function onSquare(world)
    local square = world and world:getSquare()
    local worlds = square and square.getWorldObjects and square:getWorldObjects()
    -- The square is not cleared when someone else picks it up; its list is.
    return worlds ~= nil and worlds:contains(world) and square or nil
end

function Fetch.square(entry)
    if entry.world then return onSquare(entry.world) end
    if entry.holder then return onSquare(entry.holder) end
    return entry.container and Grid.containerSquare(entry.container) or nil
end

-- Still where it was found.
function Fetch.present(entry)
    if entry.world then return onSquare(entry.world) ~= nil and entry.world:getItem() == entry.item end
    if entry.holder and not onSquare(entry.holder) then return false end
    return entry.container ~= nil and entry.container:contains(entry.item)
end

-- Queues the pickup; the survivor must already be beside it.
function Fetch.queue(player, entry)
    local inventory = player:getInventory()
    if entry.world and not isClient() then
        local menu = ISWorldObjectContextMenu
        local time = menu and menu.grabItemTime and menu.grabItemTime(player, entry.world) or 50
        return ISTimedActionQueue.add(ISGrabItemAction:new(player, entry.world, time))
    end
    local from = entry.world and entry.item:getContainer() or entry.container
    return ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player, entry.item, from, inventory))
end

-- Every item lying on a square, and the items inside bags lying there.
function Fetch.floor(square, visit)
    local worlds = square.getWorldObjects and square:getWorldObjects()
    for index = 0, worlds and worlds:size() - 1 or -1 do
        local world = worlds:get(index)
        local item = world.getItem and world:getItem()
        if item then
            visit(item, nil, world)
            if instanceof(item, "InventoryContainer") then
                local inside = item:getInventory()
                local items = inside:getItems()
                for k = 0, items:size() - 1 do visit(items:get(k), inside, nil, world) end
            end
        end
    end
end

return Fetch
