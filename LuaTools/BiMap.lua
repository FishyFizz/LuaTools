-- 双向映射库
---@class FishyLibs_BiMap
local BiMap = {}

local Set   = require("LuaTools.Set") ---@type FishyLibs_Set

---@param fromDataName any | nil
---@param toDataName any | nil
function BiMap.Create(fromDataName, toDataName)
    ---@class BiMap
    local biMapObj = {
        forwardMap  = {},
        reversedMap = {},
        Create = BiMap.Create,
    }
    function biMapObj:Clone()
        local result = BiMap.Create()
        for first, second in self:ForwardPairs() do
            result:Add(first, second)
        end
        return result
    end

    function biMapObj:RemoveByFirst(first)
        if not self.forwardMap[first] then return end
        self.reversedMap[self.forwardMap[first]] = nil
        self.forwardMap[first] = nil
    end

    function biMapObj:RemoveBySecond(second)
        if not self.reversedMap[second] then return end
        self.forwardMap[self.reversedMap[second]] = nil
        self.reversedMap[second] = nil
    end

    function biMapObj:Add(first, second)
        self:RemoveByFirst(first)
        self:RemoveBySecond(second)
        self.forwardMap[first] = second
        self.reversedMap[second] = first
    end

    function biMapObj:ToSecond(first)
        return self.forwardMap[first]
    end

    function biMapObj:ToFirst(second)
        return self.reversedMap[second]
    end

    function biMapObj:HasFirst(first)
        return self:ToSecond(first) ~= nil
    end

    function biMapObj:HasSecond(second)
        return self:ToFirst(second) ~= nil
    end

    ---@param map table 要建立双映射的单映射表，表的所有权将会被转移给BiMap!
    ---@param bReversed bool | nil 默认false，表示提供的map内容是first->second，使用bReversed表示提供map的内容是second->first
    ---@return BiMap
    function biMapObj:InitBySingleMap(map, bReversed)
        self.forwardMap = map
        self.reversedMap = {}

        for k, v in pairs(self.forwardMap) do
            self.reversedMap[v] = k
        end

        if bReversed then
            self.forwardMap, self.reversedMap = self.reversedMap, self.forwardMap
        end

        return self
    end

    --返回一个所有First值的集合
    ---@return Set
    function biMapObj:FirstSet()
        local set = Set.Create()
        set:InitByKeys(self.forwardMap)
        return set
    end

    --返回一个所有Second值的集合
    ---@return Set
    function biMapObj:SecondSet()
        local set = Set.Create()
        set:InitByKeys(self.reversedMap)
        return set
    end

    -- 添加别名增强外层可读性
    function biMapObj:AddAlias(aliasForFirst, aliasForSecond)
        if not (aliasForFirst and aliasForSecond) then return end
        self["RemoveBy"..aliasForFirst]  = self.RemoveByFirst
        self["RemoveBy"..aliasForSecond] = self.RemoveBySecond
        self["To"..aliasForFirst]        = self.ToFirst
        self["To"..aliasForSecond]       = self.ToSecond
    end

    function biMapObj:ForwardPairs()
        return pairs(self.forwardMap)
    end

    function biMapObj:ReversedPairs()
        return pairs(self.reversedMap)
    end

    function biMapObj:Len()
        local count = 0
        for k, v in self:ForwardPairs() do
            count = count + 1
        end
        return count
    end
    

    local mt = {
        __pairs = function(bimap) return bimap:ForwardPairs() end,        
        __len = function(bimap) return bimap:Len() end,
    }
    setmetatable(biMapObj, mt)

    return biMapObj
end

return BiMap