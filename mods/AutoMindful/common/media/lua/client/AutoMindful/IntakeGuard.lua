-- Attach only to the stock action AutoMindful just constructed. Manual actions
-- (even for the same item and player) keep their stock behavior.
local Yield = require "AutoMindful/ActionYield"
local Guard = {}

function Guard.bind(action, check, ...)
    local function safe(self)
        if self.autoMindfulIntakeBlocked then return false end
        local ok, allowed = pcall(check, self)
        if ok and allowed then return true end
        self.autoMindfulIntakeBlocked, self.autoMindfulStopped = true, true
        return false
    end
    local begin, validStart = action.begin, action.isValidStart
    if begin then
        -- Stock clears the whole queue when a waiting head fails isValidStart.
        -- Run both admission checks in begin instead, before native dispatch.
        action.isValidStart = function() return true end
        action.begin = function(self, ...)
            if safe(self) and (not validStart or validStart(self)) then return begin(self, ...) end
            self.autoMindfulStopped = true
            local timed = ISTimedActionQueue.getTimedActionQueue(self.character)
            if timed.current == self and timed.queue[1] == self then timed:onCompleted(self) end
        end
    end
    local valid, stop = action.isValid, action.stop
    action.isValid = function(self, ...) return safe(self) and valid(self, ...) end
    if stop then
        action.stop = function(self, ...)
            if not safe(self) then
                local timed = ISTimedActionQueue.getTimedActionQueue(self.character)
                if not (timed.autoMindfulHandoff and timed.autoMindfulHandoff.inStop) then
                    return Yield.nativeStop(self.character, self.autoMindfulOwner or self, self, stop, ...)
                end
            end
            return stop(self, ...)
        end
    end
    -- A stock SP cancellation can eat a fraction; drinks are consumed during
    -- updates as well as at completion. A validity poll is not an intake fence.
    for _, method in ipairs({...}) do
        local native = action[method]
        if native then action[method] = function(self, ...)
            if safe(self) then return native(self, ...) end
            return false
        end end
    end
    return action
end

return Guard
