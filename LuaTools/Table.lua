local Table = {} ---@class FishyLibs_Table

function Table.Transform(t, funcTransform)
    --[[
        funcTransform接收表t中的每个键值对，即 funcTransform(k, v)
        该函数的返回值应当是一个如下形式的数组：
        return {
            {k1, v1},       -- 变换后的表将包含 k1 = v1
            {v2},           -- v2 将被 insert 到变换后的表(即v4将拥有一个不重复的整数key)
            ...
        }
        返回值可以为空，代表该键值对被过滤，变换后的表不存在对应的内容
    ]]
    local result = {}
    for k, v in pairs(t) do
        local pairsTable = funcTransform(k, v)
        if type(pairsTable) == "table" then
            for _, newPair in pairs(pairsTable) do
                if #newPair == 1 then
                    table.insert(result, newPair[1])
                elseif #newPair == 2 then
                    result[newPair[1]] = newPair[2]
                end
            end
        end
    end
    return result
end

function Table.Concat(dst, src, i, j)
    if #src == 0 then return end
    if i == nil then i = 1 end
    if j == nil then j = #src end
    for idx = i, j do
        table.insert(dst, src[idx])
    end
end

function Table.ConcatMultiple(dst, ...)
    for _, src in ipairs({...}) do
        Table.Concat(dst, src)
    end
end

function Table.Exchange(t)
    local result = {}
    for k, v in pairs(t) do
        result[v] = k
    end
    return result
end

function Table.Keys(t)
    local keys = {}
    for k in pairs(t) do
        table.insert(keys, k)
    end
    return keys
end

function Table.Slice(t, i, j)
    if j == nil then j = #t end

    local result = {}
    for k = i, j do
        table.insert(result, t[k])
    end

    return result
end

function Table.CopyAppend(t, elem)
    local copy = {}
    for _, v in ipairs(t) do
        table.insert(copy, v)
    end
    table.insert(copy, elem)
    return copy
end

function Table.PairsCount(t)
    local count = 0
    for k, v in pairs(t) do
        count = count + 1
    end
    return count
end
return Table