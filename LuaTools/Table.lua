local Table = {} ---@class FishyLibs_Table

function Table.Transform(t, funcTransform)
    local result = {}
    for k, v in pairs(t) do
        local pairsTable = funcTransform(k, v)
        for _, newPair in pairs(pairsTable) do
            if #newPair == 1 then
                table.insert(result, newPair[1])
            elseif #newPair == 2 then
                result[newPair[1]] = newPair[2]
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

return Table