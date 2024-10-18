---@class FishyLibs_Set
local Set = {}

---@return Set
function Set.Create()
    ---@class Set
    local setObj = {}
    setObj.Create = Set.Create

    setObj._data = {}
    
    function setObj:Clone()
        local result = Set.Create()
        for k in pairs(self) do
            result:Insert(k)
        end
        return result
    end

    function setObj:InitByKeys(t)
        for k, _ in pairs(t) do
            self._data[k] = true
        end
        return self
    end

    function setObj:InitByValues(t)
        for _, v in pairs(t) do
            self._data[v] = true
        end
        return self
    end

    function setObj:Insert(key)
        self._data[key] = true
        return self
    end

    function setObj:Remove(key)
        self._data[key] = nil
        return self
    end

    function setObj:Has(key)
        return self._data[key]
    end

    ---@param other Set
    function setObj:Conjunction(other)
        local result = Set.Create()
        for key, _ in self:Pairs() do
            result:Insert(key)
        end
        for key, _ in other:Pairs() do
            result:Insert(key)
        end
        return result
    end

    ---@param other Set
    function setObj:Disjunction(other)
        local result = Set.Create()
        for key, _ in self:Pairs() do
            if other:Has(key) then result:Insert(key) end
        end
        return result
    end

    ---@param other Set
    function setObj:Exclude(other)
        local result = Set.Create()
        for key, _ in self:Pairs() do
            if not other:Has(key) then result:Insert(key) end
        end
        return result
    end

    ---@return any[]
    function setObj:ToArray()
        local result = {}
        for key, _ in self:Pairs() do
            table.insert(result, key)    
        end
        return result
    end

    function setObj:Len() 
        local count = 0
        for k, v in self:Pairs() do
            count = count + 1
        end
        return count
    end

    function setObj:Pairs()
        return pairs(self._data)
    end

    local mt = {
        __pairs = function(set) return set:Pairs() end,        
        __len = function(set) return set:Len() end,
    }
    setmetatable(setObj, mt)

    return setObj
end

return Set

