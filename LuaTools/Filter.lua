local Filter = {} ---@class FishyLibs_Filter

---@enum FilterCombineMethod
Filter.ECombineMethod = {DISJUNCTION = 1, CONJUNCTION = 2}

function Filter.Always() return true end
function Filter.Never() return false end

---@alias SimplePredicate nil|function|Filter
---@param pred SimplePredicate 一个简单条件：nil代表无条件, function代表自定义条件, Filter代表Filter作为条件
function Filter.Match(value, pred)
    -- 无条件, 返回true
    if pred == nil then return true end

    -- 函数作为自定义条件, 调用
    if type(pred) == "function" then return pred(value) end

    -- 条件是一个Filter, 转发调用
    if type(pred) == "table" and pred.__fishylibs_filter then return pred:Match(value) end
end

function Filter.Filter(list, pred)
    local result = {}
    for _, value in pairs(list) do
        if Filter.Match(value, pred) then
            table.insert(result, value)
        end
    end
    return result
end

function Filter.Create(predicate)
    ---@class Filter
    local obj = {
        __fishylibs_filter = true,
        predicate = predicate, ---@type SimplePredicate | SimplePredicate[]
        combineMethod = nil,   ---@type FilterCombineMethod | nil
    }

    function obj:Match(val)
        -- 简单条件, 直接Match
        if not self.combineMethod then
            return Filter.Match(val, self.predicate)
        end

        -- 组合条件, predicate是simplePredicate的数组, 组合方式用combineMethod
        ---@diagnostic disable-next-line: param-type-mismatch
        for _, subPredicate in pairs(self.predicate) do
            local matchResult = Filter.Match(val, subPredicate)

            -- and短路
            if self.combineMethod == Filter.ECombineMethod.DISJUNCTION 
               and matchResult == false then
                return false
            end

            -- or短路
            if self.combineMethod == Filter.ECombineMethod.CONJUNCTION 
               and matchResult == true then
                return true
            end
        end
        
        -- 非短路, and返回true, or返回false
        return self.combineMethod == Filter.ECombineMethod.DISJUNCTION
    end

    function obj:Filter(list)
        return Filter.Filter(list, self)
    end

    return obj
end

---@return any? key
---@return any? value
function Filter.FirstMatch(list, pred)
    for k, v in pairs(list) do
        if Filter.Match(v, pred) then
            return k, v
        end
    end
    return nil
end

---@return any? key
---@return any? value
function Filter.AnyMatch(list, pred)
    return Filter.FirstMatch(list, pred) ~= nil
end

---Combine filters
function Filter.CombineFilter(combineMethod, predicateList)
    local result = Filter.Create(predicateList)
    ---@diagnostic disable-next-line: inject-field
    result.combineMethod = combineMethod
    return result
end

function Filter.And(predicateList)
    return Filter.CombineFilter(Filter.ECombineMethod.DISJUNCTION, predicateList)
end

function Filter.Or(predicateList)
    return Filter.CombineFilter(Filter.ECombineMethod.CONJUNCTION, predicateList)
end

return Filter