local Callback = {}

local ECallbackArgRuleType = {
    Fixed = 0,
    Mapped = 1,
    Vararg = 2,
}

function Callback.fixed(data)
    return {
        __callbackRule = true,
        ruleType = ECallbackArgRuleType.Fixed,
        data = data,
    }
end

function Callback.arg(posInCallback, defaultValue)
    return {
        __callbackRule = true,
        ruleType = ECallbackArgRuleType.Mapped,
        posInCallback = posInCallback,
        default = defaultValue,
    }
end

function Callback.vararg(posInCallback, defaultValues, ...)
    return {
        __callbackRule = true,
        ruleType = ECallbackArgRuleType.Vararg,
        posInCallback = posInCallback,
        defaults = {defaultValues, ...}
    }
end

local function IsCallbackRule(t)
    return (type(t) == "table") and (t.__callbackRule == true)
end

--------------------------------------------------------------------------------------------

function Callback.MakeCallback(func, rules, ...)
    local rules = {rules, ...}
    
    local callbackInfo = {
        func = func,
        argRules = {},
    }

    for pos, rule in ipairs(rules) do
        if not IsCallbackRule(rule) then
            rule = Callback.fixed(rule)
        end
        callbackInfo.argRules[pos] = rule

        if rule.ruleType == ECallbackArgRuleType.Vararg and pos ~= #rules then
            assert(false, "Varargs rule must be the last one!")
        end
    end

    return function(...) return Callback.InvokeCallback(callbackInfo, ...) end
end

function Callback.MakeProtectedCallback(func, rules, ...)
    return Callback.MakeProtected(Callback.MakeCallback(func, rules, ...))
end

local function max(a,b) return a>b and a or b end

function Callback.InvokeCallback(callbackInfo, ...)
    local callbackArgs = {...}
    local processedArgs = {}

    for pos, rule in ipairs(callbackInfo.argRules) do
        if rule.ruleType == ECallbackArgRuleType.Fixed then
            processedArgs[pos] = rule.data
        elseif rule.ruleType == ECallbackArgRuleType.Mapped then
            processedArgs[pos] = callbackArgs[rule.posInCallback] or rule.default
        else --ECallbackArgRuleType.vararg
            local totalVarargs = max(#callbackArgs - rule.posInCallback + 1, #rule.defaults)

            local basePosFunc = pos - 1
            local basePosCallback = rule.posInCallback - 1

            for vaIdx = 1, totalVarargs do
                local posCallback = basePosCallback + vaIdx
                local posFunc = basePosFunc + vaIdx
                processedArgs[posFunc] = callbackArgs[posCallback] or rule.defaults[vaIdx]
            end
        end
    end

    return callbackInfo.func(table.unpack(processedArgs))
end

function Callback.MakeProtected(func)
    return function(...)
        local results = {pcall(func, ...)}
        if table.remove(results, 1) then
            return table.unpack(results)
        end
    end
end

function Callback.MakeSimple(func, ...)
    local rules = {...}
    rules[#rules+1] = Callback.vararg(1)
    return Callback.MakeCallback(func, table.unpack(rules))
end

return Callback