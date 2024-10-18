-- 表成员追踪库

---@class FishyLibs_TableTrace
local TableTrace = {}

local BiMap = require("LuaTools.BiMap") ---@type FishyLibs_BiMap

-- 给定一个表tBefore和被修改过后的结果tAfter, 成员追踪器能够确定发生了如何的修改
-- 包括新增和删除的成员、已有的成员发生了怎样的移动
-- 主要还是用于数组

---@class TableDiffRemoveInfo
---@field identity number
---@field key any

---@alias TableDiffAddInfo TableDiffRemoveInfo
---@alias TableDiffInPlaceInfo TableDiffRemoveInfo

---@class TableDiffMoveInfo
---@field identity number
---@field oldKey any
---@field newKey any

---@class TableDiffResult
---@field removed       TableDiffRemoveInfo[] 被删除的元素信息
---@field added         TableDiffAddInfo[]    新增的元素信息
---@field moved         TableDiffMoveInfo[]   被移动到其他key的元素信息   
---@field inPlace       TableDiffInPlaceInfo[] 没有移动的元素信息   
---@field newKeys       any[]                  新增的key
---@field removedKeys   any[]                  被删除的key

---@class ArrayTraceResult
---@field removes   TableDiffRemoveInfo[]      先remove, 该数组保证每个key从大到小排列, 故一次遍历依次删除即可
---@field inserts   TableDiffAddInfo[]         再insert, 该数组保证每个key从小到大排列, 故一次遍历依次插入即可
---@field swaps     table<number, number>[]     再swap, 该数组保证从前往后遍历并执行swap操作即可得到结果

---为一个表创建key<->identity的双向map, 用于追踪表变更
---@return BiMap
---@param identityFunc fun(key, value):number
function TableTrace.MakeKeyIdentityMap(t, identityFunc)
    local kiMap = {}
    for k, v in pairs(t) do
        kiMap[k] = identityFunc(v)
    end
    return BiMap.Create():InitBySingleMap(kiMap)
end


---寻找两个表之间的不同, 表需要先通过IdentityFunc处理, 从 key->data 转化为 key->identity 的形式方便比较
---@param kiMapBefore BiMap
---@param kiMapAfter BiMap
---@return TableDiffResult
function TableTrace.Diff(kiMapBefore, kiMapAfter)
    local elementsBefore = kiMapBefore:SecondSet()
    local elementsAfter = kiMapAfter:SecondSet()

    local keysBefore = kiMapBefore:FirstSet()
    local keysAfter = kiMapAfter:FirstSet()

    local elementsDeleted = elementsBefore:Exclude(elementsAfter)
    local elementsAdded   = elementsAfter:Exclude(elementsBefore)
    local elementsKept    = elementsBefore:Disjunction(elementsAfter)

    local keysDeleted = keysBefore:Exclude(keysAfter)
    local keysAdded   = keysAfter:Exclude(keysBefore)
    
    local moved = {}
    local inPlace = {}
    for id in pairs(elementsKept) do
        if kiMapBefore:ToFirst(id) ~= kiMapAfter:ToFirst(id) then
            table.insert(moved, {identity = id, oldKey = kiMapBefore:ToFirst(id), newKey = kiMapAfter:ToFirst(id)})
        else
            table.insert(inPlace, {identity = id, key = kiMapBefore:ToFirst(id)})
        end
    end

    local removed = {}
    for id in pairs(elementsDeleted) do
        table.insert(removed, {identity = id, key = kiMapBefore:ToFirst(id)})
    end

    local added = {}
    for id in pairs(elementsAdded) do
        table.insert(added, {identity = id, key = kiMapAfter:ToFirst(id)})
    end

    local newKeys = keysAdded:ToArray()
    local removedKeys = keysDeleted:ToArray()

    return {
        moved       = moved,
        removed     = removed,
        added       = added,
        newKeys     = newKeys,
        removedKeys = removedKeys,
        inPlace     = inPlace,
    }
end

---构造一个追踪器
---@param identityFunc fun(key, value):number 通过key和value返回一个能唯一确定该成员身份的值用于追踪其移动、新增和删除, 比对时identity不变的成员将被视为是同一个成员
function TableTrace.MakeTracer(identityFunc)
    ---@class TableTracer
    local tableTracerObj = {
        _identityFunc = identityFunc,
        _baseKIMap = BiMap.Create()
    }

    ---传入修改过的表内容, 得到和比较基准之间的差异, 包括成员的新增、删除、key变更
    tableTracerObj.Diff = function(self, after)
        local newKIMap = TableTrace.MakeKeyIdentityMap(after, identityFunc)
        return TableTrace.Diff(self._baseKIMap, newKIMap)
    end

    ---将表的内容设置为之后用于比较的基准
    tableTracerObj.SetBase = function(self, t)
        self._baseKIMap = TableTrace.MakeKeyIdentityMap(t, identityFunc)
    end

    ---将更新过的表和之前的进行比较, 返回产生了哪些改动, 并将新表的内容设置为之后用于比较的基准
    tableTracerObj.DiffAndUpdate = function(self, new)
        local result = self:Diff(new)
        self:SetBase(new)
        return result
    end
    
    return tableTracerObj
end


return TableTrace