---@class FishyLibs_Sort
local Sort = {}

function Sort.LeftPartition(left, right)
    assert(right > left)
    return left, math.floor((left + right) / 2)
end

function Sort.RightPartition(left, right)
    assert(right > left)
    local _, lr = Sort.LeftPartition(left, right)
    return lr + 1, right
end

--- 稳定排序, 在原地排, 需要保留原来的数组需要先复制。参考Deep模块的DeepCopy。
---@param list any[] 被排序的数组
---@param less any   排序判断函数
---@param left any   排序区间起始位置(含)
---@param right any  排序区间结束位置(含)
function Sort.MergeSort(list, less, left, right)
    if less == nil then less = function(a, b) return a<b end end
    
    if left == nil then left = 1 end
    if right == nil then right = #list end
    if not (right > left) then return end

    local ll, lr = Sort.LeftPartition(left, right)
    local rl, rr = Sort.RightPartition(left, right)
    Sort.MergeSort(list, less, ll, lr)
    Sort.MergeSort(list, less, rl, rr)

    -- Merge
    local l = ll
    local r = rl
    while true do
        if less(list[r], list[l]) then
            local tmp = table.remove(list, r)
            table.insert(list, l, tmp)
            r = r + 1
            l = l + 1
        else
            l = l + 1
        end
        if (r > right) or (l >= r) then break end
    end

    return list
end

--- 稳定排序, 原数组保留, 返回新的排序数组，以及排序前后的索引映射关系
---@param list any[] 被排序的数组
---@param less any   排序判断函数
---@param left any   排序区间起始位置(含)
---@param right any  排序区间结束位置(含)
---@return any[]     --排序后的列表
---@return integer[] srcIdxList --索引映射: srcIdxList[idxAfterSort] = idxBeforeSort
function Sort.TrackedMergeSort(list, less, left, right)
    -- 创建代理表，将原数据和原索引合并到一起
    local proxyList = {}
    for idx, item in ipairs(list) do
        proxyList[idx] = {
            data = item,
            srcIdx = idx,
        }
    end

    -- 新的比较函数取代理的data部分进行比较
    local fLess = Sort.By(function(proxyItem) return proxyItem.data end, less)
    Sort.MergeSort(proxyList, fLess, left, right)

    -- 将结果拆成排序结果和原索引数组
    local result = {}
    local srcIdxList = {}
    for idx, proxyItem in ipairs(proxyList) do
        result[idx] = proxyItem.data
        srcIdxList[idx] = proxyItem.srcIdx
    end

    return result, srcIdxList
end

Sort.ThreeWayCompResult = {
    LESS = -1,
    EQUAL = 0,
    GREATER = 1,
}

---@param lessFunc fun(a,b):boolean
function Sort.LessTo3Way(lessFunc)
    return function(a, b)
        if lessFunc(a, b) then return Sort.ThreeWayCompResult.LESS end
        if lessFunc(b, a) then return Sort.ThreeWayCompResult.GREATER end
        return Sort.ThreeWayCompResult.EQUAL
    end
end

function Sort.ThreeWayComp(a, b)
    return Sort.LessTo3Way(function(a,b) return a<b end)
end

function Sort.ThreeWayToLess(threeWayComp)
    return function(a,b) return threeWayComp(a,b) == Sort.ThreeWayCompResult.LESS end
end

---传入按优先级排序的小于判断函数的数组, 返回一个小于判断函数
function Sort.Preferenced(lessFuncList)
    local comparators = {}
    for _, less in ipairs(lessFuncList) do
        table.insert(comparators, Sort.LessTo3Way(less))
    end
    return Sort.ThreeWayToLess(Sort.PreferencedThreeWay(comparators))
end

---传入按优先级排序的三向比较函数的数组, 返回一个三向比较函数
function Sort.PreferencedThreeWay(threeWayFuncList)
    return function (a, b)
        --从第一个条件开始比较, 只要不相等就立即返回, 相等则继续判断之后的条件
        for _, comparator in ipairs(threeWayFuncList) do
            local result = comparator(a, b)
            if result ~= Sort.ThreeWayCompResult.EQUAL then 
                return result
            end
        end
        --全部判断完还没有结果, 返回相等
        return Sort.ThreeWayCompResult.EQUAL
    end
end

local function xor(bx, by)
    if by then
        return not bx
    else
        return bx end
end

---传入一个tokenFunc，这个tokenFunc对于每个对象返回一个整数或布尔值（或任意类型...）
---返回一个小于判断函数，接收两个对象A, B，如果tokenFunc(A) < tokenFunc(B)，则认为A<B
---
---使用例:
---     fLess = Sort.TokenToLess(function(obj) obj.sortPriority end)
---     a = {sortPriority = 0}
---     b = {sortPriority = 1}
---结果:
---     fLess(a, b) = true
--- 
---@param tokenFunc         fun(x:any):integer|boolean|any              token生成函数
---@param optfTokenLess     nil|fun(token1:any, token2:any):boolean     tokenFunc如果返回非整数/布尔值，需要提供自定义的token比较函数
---@param bInvert           boolean?                                    是否将比较结果反向
function Sort.By(tokenFunc, optfTokenLess, bInvert)
    return function(x, y)
        local tokenX = tokenFunc(x)
        local tokenY = tokenFunc(y)

        if type(tokenX) == "boolean" then tokenX = tokenX and 1 or 0 end
        if type(tokenY) == "boolean" then tokenY = tokenY and 1 or 0 end

        local less = optfTokenLess and optfTokenLess(tokenX, tokenY) or (tokenX<tokenY)
        less = xor(less, bInvert)
        return less
    end
end

return Sort