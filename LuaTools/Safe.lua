-- 安全操作库，包括Getter/Setter/Caller等

---@class FishyLibs_Safe
local Safe = {}

-- 安全Getter
-- 例如 SafeGetter(t, {"key1", "key2"}) 返回 t.key1.key2
-- 其中任何一层不存在都返回nil
function Safe.SafeGetter(t, pathTable)
    local val = t
    for _, key in ipairs(pathTable) do
        if type(val) ~= "table" then
            return nil
        end
        val = val[key]
    end
    return val
end

-- 安全Setter
-- 例如 SafeSetter(t, {"key1", "key2"}, 1) 代表 t.key1.key2 = 1
-- 1. 其中任何一层不存在或无法索引（比如t.key1不是一个table），都返回false
-- 2. 如果bCreatePathAlong则会创建不存在的子表
--    1. 如果t.key1不存在，则自动创建t.key1 = {}然后继续执行
--    2. 如果t.key1已存在且不是一个table，失败返回false
-- 3. 成功返回true
function Safe.SafeSetter(t, pathTable, value, bCreatePathAlong)
    if type(t) ~= "table" then return false end
    local path = t
    
    -- 先遍历到路径
    for i = 1, (#pathTable - 1) do

        -- 下一层不存在，如果允许创建路径则产生空表，否则失败
        if path[pathTable[i]] == nil then
            if bCreatePathAlong then
                path[pathTable[i]] = {}
            else
                return false
            end
        end

        path = path[pathTable[i]]

        -- 路径不是表而是值，失败
        if type(path) ~= "table" then
            return false
        end
    end

    -- 设置值
    path[pathTable[#pathTable]] = value
    return true
end

-- 安全unpack
-- 传入非表时返回nil
function Safe.SafeUnpack(t, i, j)
    if type(t) ~= "table" then return nil end
    return table.unpack(t, i, j)
end

function Safe.SafeCall(func, optErrHandler, ...)
    if not optErrHandler then optErrHandler = function(err)end end

    if type(func) ~= "function" then 
        optErrHandler("Trying to call a non-function! Actual type is: ", type(func)) 
        return 
    end

    local results = {pcall(func, ...)}
    local success = results[1]
    if success then
        table.remove(results, 1)
        return Safe.SafeUnpack(results)
    else
        optErrHandler(results[2])
    end
end

-- 安全Caller
-- 相当于SafeGetter通过pathTable获取指定函数后pcall
function Safe.SafeCaller(t, pathTable, optErrHandler, ...)
    local func = Safe.SafeGetter(t, pathTable)
    return Safe.SafeCall(func, optErrHandler, ...)
end

-- 安全成员函数Caller
function Safe.SafeMethodCaller(t, pathTable, optErrHandler, ...)
    -- 复制安全Getter，但是同时获取最后一层的值（成员函数）和其上一层的值（传入函数的self）
    local prevVal = nil
    local val = t
    for _, key in ipairs(pathTable) do
        if type(val) ~= "table" then
            return nil
        end
        prevVal = val
        val = val[key]
    end

    local func   = val
    local caller = prevVal
    return Safe.SafeCall(func, optErrHandler, caller, ...)
end

-- 从路径产生路径表，例如 "hello.world" -> {"hello", "world"}
function Safe.MakePathTable(path)
    local cachedPath = {}
    local begin = 1

    local dot = string.find(path, ".", begin, true)
    while dot do
        table.insert(cachedPath, string.sub(path, begin, dot-1))
        begin = dot + 1
        dot = string.find(path, ".", begin, true)
    end
    table.insert(cachedPath, string.sub(path, begin, #path))
    return cachedPath
end

-- 返回一个预设路径的SafeGetter
function Safe.MakeGetter(path)
    local pt = Safe.MakePathTable(path)
    return function(t) return Safe.SafeGetter(t, pt) end
end

-- 返回一个预设路径的SafeSetter
function Safe.MakeSetter(path)
    local pt = Safe.MakePathTable(path)
    return function(t, value, bCreatePathAlong) return Safe.SafeSetter(t, pt, value, bCreatePathAlong) end
end

-- 返回一个获取指定对象的指定路径值的SafeGetter
function Safe.MakeBoundGetter(obj, path)
    local pt = Safe.MakePathTable(path)
    return function()
        return Safe.SafeGetter(obj, pt)
    end
end

-- 返回一个设置指定对象的指定路径值的SafeSetter
-- 用这个可以实现lua的"强引用传递"
function Safe.MakeBoundSetter(obj, path)
    local pt = Safe.MakePathTable(path)
    return function (value, bCreatePathAlong)
        return Safe.SafeSetter(obj, pt, value, bCreatePathAlong) 
    end
end

-- 返回一个预设路径和错误处理函数的SafeCaller，用于不带self的成员函数
function Safe.MakeCaller(path, optErrHandler)
    local pt = Safe.MakePathTable(path)
    return function(t, ...) return Safe.SafeCaller(t, pt, optErrHandler, ...) end
end

-- 返回一个预设路径和错误处理函数的SafeCaller，用于带self的成员函数
function Safe.MakeMethodCaller(path, optErrHandler)
    local pt = Safe.MakePathTable(path)
    return function(t, ...) return Safe.SafeMethodCaller(t, pt, optErrHandler, ...) end
end

return Safe