-- Stock B42's ISPathFindAction reports failure via onFailFunc rather than
-- assigning .result like ISWalkToTimedAction. Observe *only* an owned path.
local RouteOutcome = {}

local function ownField(object, key)
    -- Kahlua rawget may resolve class fields. Do not leave class defaults
    -- copied onto this instance after the temporary hooks are gone.
    for name, value in pairs(object) do if name == key then return value end end
end

function RouteOutcome.observe(action)
    if action.Type ~= "ISPathFindAction" or type(action.update) ~= "function"
            or type(action.forceStop) ~= "function" then return end
    local update = action.update
    function action:update(...)
        self.autoMindfulPathFailed = nil
        local prior = self.onFailFunc
        -- In stock Lua this flag only works when a callback already exists.
        -- Installing one in this otherwise contradictory case would change stop to perform.
        if not prior and self.runActionsAfterFailing then return update(self, ...) end
        local forceStop = self.forceStop
        local ownStop, ownCallback = ownField(self, "forceStop"), ownField(self, "onFailFunc")
        local notified, injectedArgs
        local function observeFail(...)
            notified = true
            if prior then return prior(...) end
        end
        local function observeStop(current, ...)
            -- Do not turn an early preferred-path notification or a success
            -- callback into a later cancellation. Stock must also request a stop
            -- in this update. The real Java stop callback arrives after update.
            if current == self and notified then self.autoMindfulPathFailed = true end
            return forceStop(current, ...)
        end
        if not prior and not self.onFailArgs then
            injectedArgs = {}
            self.onFailArgs = injectedArgs
        end
        self.onFailFunc, self.forceStop = observeFail, observeStop
        local ok, result = pcall(update, self, ...)
        if self.onFailFunc == observeFail then self.onFailFunc = ownCallback end
        if self.forceStop == observeStop then self.forceStop = ownStop end
        if injectedArgs and self.onFailArgs == injectedArgs then self.onFailArgs = nil end
        if not ok then error(result) end
        return result
    end
end

function RouteOutcome.failed(action)
    return action.autoMindfulPathFailed == true
        or (action.result ~= nil and action.result == BehaviorResult.Failed)
end

return RouteOutcome
