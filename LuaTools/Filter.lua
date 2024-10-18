local Filter = {} ---@class FishyLibs_Filter

---@enum FilterCombineMethod
Filter.ECombineMethod = {DISJUNCTION = 1, CONJUNCTION = 2}

---@alias simplePredicate nil|function|Filter
---@param pred simplePredicate 一个简单条件：nil代表无条件，function代表自定义条件，Filter代表Filter作为条件
function Filter.MatchSimplePredicate(value, pred)
    -- 无条件，返回true
    if pred == nil then return true end

    -- 函数作为自定义条件，调用
    if type(pred) == "function" then return pred(value) end

    -- 条件是一个Filter，转发调用
    if type(pred) == "table" and pred.__fishylibs_filter then return pred:Match(value) end
end

function Filter.FilterSimplePredicate(list, pred)
    local result = {}
    for _, value in pairs(list) do
        if Filter.MatchSimplePredicate(value, pred) then
            table.insert(result, value)
        end
    end
    return result
end

function Filter.Create(predicate)
    ---@class Filter
    local obj = {
        __fishylibs_filter = true,
        predicate = predicate, ---@type simplePredicate | simplePredicate[]
        combineMethod = nil,   ---@type FilterCombineMethod | nil
    }

    function obj:Match(val)
        -- 简单条件，直接Match
        if not self.combineMethod then
            return Filter.MatchSimplePredicate(val, self.predicate)
        end

        -- 组合条件，predicate是simplePredicate的数组，组合方式用combineMethod
        for _, subPredicate in pairs(self.predicate) do

            -- and短路
            if self.combineMethod == Filter.ECombineMethod.DISJUNCTION 
               and Filter.MatchSimplePredicate(val, subPredicate) == false then
                return false
            end

            -- or短路
            if self.combineMethod == Filter.ECombineMethod.CONJUNCTION 
               and Filter.MatchSimplePredicate(val, subPredicate) == true then
                return true
            end
        end
        
        -- 非短路，and返回true, or返回false
        return self.combineMethod == Filter.ECombineMethod.DISJUNCTION
    end

    function obj:Filter(list)
        return Filter.FilterSimplePredicate(list, self)
    end

    return obj
end

function Filter.FirstMatch(list, pred)
    for k, v in pairs(lsit) do
        if Filter.FilterSimplePredicate(v, pred) then
            return k, v
        end
    end
    return nil
end

function Filter.AnyMatch(list, pred)
    return Filter.FirstMatch(list, pred) ~= nil
end

---Combine filters

function Filter.MakeCombinedFilter(combineMethod, predicateList)
    local result = Filter.Create(predicateList)
    result.combineMethod = combineMethod
    return result
end

function Filter.And(predicateList)
    return Filter.MakeCombinedFilter(Filter.ECombineMethod.DISJUNCTION, predicateList)
end

function Filter.Or(predicateList)
    return Filter.MakeCombinedFilter(Filter.ECombineMethod.CONJUNCTION, predicateList)
end

return Filter