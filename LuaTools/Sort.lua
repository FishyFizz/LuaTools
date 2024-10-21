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

--- 稳定排序, 在原地排, 需要复制参考Deep模块的DeepCopy
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
function Sort.PreferencedLess(lessFuncList)
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

return Sort