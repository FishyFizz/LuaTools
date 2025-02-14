-- 数组的React定义, 例如用于列表控件
---@class FishyLibs_ReactArray
local ReactArray = {}

local Safe = require("LuaTools.Safe") ---@type FishyLibs_Safe
local Deep = require("LuaTools.Deep") ---@type FishyLibs_Deep
local TableTrace = require("LuaTools.TableTrace") ---@type FishyLibs_TableTrace

---@class ElementChangeInfo
---@field identity number
---@field oldKey any
---@field newKey any

---@class ArrayChanges : TableDiffResult
---@field elemChanges ElementChangeInfo[]

function ReactArray.ReactEntry(getter, memberSnapshotFunc, memberIdentityFunc, memberEqualityTest)
    if not memberSnapshotFunc then memberSnapshotFunc = Deep.MakeDeepCopier(1) end
    if not memberEqualityTest then memberEqualityTest = Deep.MakeDeepEqualityTest(1) end
    if not memberIdentityFunc then memberIdentityFunc = function(x) return x end end

    local function ArraySnapshot(arr)
        local result = {}
        for i, v in ipairs(arr) do
            result[i] = memberSnapshotFunc(v)
        end
        return result
    end

    ---@return boolean, ArrayChanges
    local function ArrayEqualityTest(before, after)
        local kiMapBefore = TableTrace.MakeKeyIdentityMap(before, memberIdentityFunc)
        local kiMapAfter = TableTrace.MakeKeyIdentityMap(after, memberIdentityFunc)

        ---@type ArrayChanges
        local diff = TableTrace.Diff(kiMapBefore, kiMapAfter)

        -- 测试元素id是否一致(没有添加、删除和移动)
        local bElementsIdentityEqual = (#diff.added + #diff.moved + #diff.removed) == 0

        -- 测试元素内容是否一致
        local changedElements = {} ---@type ElementChangeInfo[]
        for _, id in pairs(kiMapBefore) do
            if kiMapAfter:HasSecond(id) then
                local oldKey = kiMapBefore:ToFirst(id)
                local newKey = kiMapAfter:ToFirst(id)
                if not memberEqualityTest(before[oldKey], after[newKey]) then
                    table.insert(changedElements,
                        {identity = id,
                         oldKey = oldKey,
                         newKey = newKey})
                end
            end
        end
        diff.elemChanges = changedElements

        local bEqual = bElementsIdentityEqual and (#diff.elemChanges == 0)
        return bEqual, (bEqual and nil or diff)
    end

    return {
        getter = getter,
        snapshot = ArraySnapshot,
        equalityTest = ArrayEqualityTest,
    }
end


---@class ArrayReactor
---@field New fun(self:ArrayReactor, idx: number, data: any)       添加新元素, data是一个memberSnapshot
---@field Put  fun(self:ArrayReactor, idx: number, data: any)      放入元素(放入之前取出的元素), data是一个memberSnapshot
---@field Delete fun(self:ArrayReactor, idx: number): any          删除元素
---@field Take fun(self:ArrayReactor, idx: number): any            取出元素(之后会重新放入), 返回一个memberSnapshot
---@field Change fun(self:ArrayReactor, idx: number, before, after) 元素内容变化, 传入前后memberSnapshot

---@param arrReactor ArrayReactor
---@return ReactSubscriber
function ReactArray.MakeArraySubscriber(arrReactor)

    ---@param diff ArrayChanges
    local function ArraySubcriber(before, after, diff)
        local moveOutActions = {} --要从数组移出的(包括删除和移动的)
        local moveInActions = {} --要移入数组的(包括添加和移动的)

        for _, removeInfo in pairs(diff.removed) do
            table.insert(moveOutActions, {bDelete = true, key = removeInfo.key})
        end

        for _, insertInfo in pairs(diff.added) do
            table.insert(moveInActions, {bNew = true, key = insertInfo.key})
        end

        for _, moveInfo in pairs(diff.moved) do
            table.insert(moveOutActions, {bDelete = false, id = moveInfo.identity, key = moveInfo.oldKey})
            table.insert(moveInActions, {bNew = false, id = moveInfo.identity, key = moveInfo.newKey})
        end

        -- 整理操作, 由于数组操作的索引移动, 移出操作从高索引到低索引, 移入操作从低索引到高索引
        table.sort(moveOutActions, function(a, b) return a.key > b.key end)
        table.sort(moveInActions, function(a, b) return a.key < b.key end)

        -- 执行操作
        local savedElements = {}
        for _, action in ipairs(moveOutActions) do
            if not action.bDelete then
                savedElements[action.id] = arrReactor:Take(action.key)
            else
                arrReactor:Delete(action.key)
            end
        end

        for _, action in ipairs(moveInActions) do
            if not action.bNew then
                local elem = savedElements[action.id]
                arrReactor:Put(action.key, elem)
            else
                arrReactor:New(action.key, after[action.key])
            end
        end

        for _, changeInfo in ipairs(diff.elemChanges) do
            arrReactor:Change(changeInfo.newKey, before[changeInfo.oldKey], after[changeInfo.newKey])
        end
        
    end

    return ArraySubcriber
end

return ReactArray