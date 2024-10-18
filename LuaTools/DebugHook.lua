local DebugHook = {}

local Deep = require("LuaTools.Deep")
local Safe = require("LuaTools.Safe")
-----------------------------------------------------------------------------------------

--#region 工具函数

local Log = function(...) print("[DebugHook]   ",...) end

local BreakpointImpl = function()end

---把一个表中的某个key的元素移动到另一个表。
---getter和setter是满足__index和__newindex定义的函数, 用于实际执行移动操作。
---默认使用rawget和rawset
local function MoveField(from, to, key, getter, setter)
    getter = getter and getter or rawget
    setter = setter and setter or rawset

    setter(to, key, getter(from, key))
    setter(from, key, nil)
end

---把一个表中满足条件的字段移动到另一个表
---要求: 字段要能够用next枚举
---@param predicate function 接收key, 返回bool决定是否移动该项
local function MoveMatchingFields(from, to, predicate, getter, setter)
    local k, v = next(from, nil)
    while k ~= nil do
        local tmpK = k
        k, v = next(from, k)
        if predicate(tmpK) then
            MoveField(from, to, tmpK, getter, setter)
            --Log("Field", tostring(tmpK), " moved from ", tostring(from), " to ", tostring(to))
        else
            --Log("Field ", tostring(tmpK), " is excluded and not moved.")
        end
    end
end

---将obj的元表替换为元表的拷贝, 使其不和任何其他对象共享元表。返回新元表。
---要求: obj的元表应当不包含运行时可变的数据
local function MakeUniqueMeta(obj)
    local mt = getmetatable(obj)
    mt = mt and mt or {}

    local mtCopy = Deep.DeepCopy(mt, 1)
    setmetatable(obj, mtCopy)
    return mtCopy
end

local function CopyAppend(t, e)
    local copy = Deep.DeepCopy(t, 1)
    table.insert(copy, e)
    return copy
end

local function CopyRange(t, i, j)
    local result = {}
    for idx = i, j do
        if t[idx] ~= nil then
           table.insert(result, t[idx]) 
        end
    end
    return result
end

--#endregion

--#region 类型定义

---@class DebugHookDefinition
---@field fieldFilter fun(key:any):boolean
---@field readHook fun(obj:any, key:any, value:any) | nil
---@field writeHook fun(obj:any, key:any, value:any) | nil
---@field subTableHookPolicies SubTableHookPolicy[] | nil

---@class SubTableHookPolicy
---@field policyMatcher fun(key:any):boolean | nil | any[] 可以是接收key返回bool的匹配函数, 可以是any[]表示可精确匹配的key, 也可以留空表示无条件匹配
---@field hookDef DebugHookDefinition | string 可以是DebugHookDefinition或字符串"inherit", 代表使用和上一层完全一致的DebugHookDefinition

---@class DebugHookInfo
---@field hookOwner table
---@field hookDef DebugHookDefinition
---@field originalIndex function
---@field originalNewindex function
---@field originalGc function
---@field hiddenFields table
---@field hookRoot table
---@field rootName string
---@field pathToRoot string[]

--#endregion

---@type table<table, DebugHookInfo>
local hookInfoTable = {}

local function TestSubPolicyMatch(key, policyMatcher)
    if policyMatcher == nil then return true end
    if type(policyMatcher) == "function" then return policyMatcher(key) end
    if type(policyMatcher) == "table" then
        for _, matchKey in pairs(policyMatcher) do
            if key == matchKey then return true end
        end
        return false
    end
    return false
end

---@param hookDef DebugHookDefinition
---@return DebugHookDefinition | nil
local function FindSubDebugHookDef(key, hookDef)
    local policyArr = hookDef.subTableHookPolicies
    if policyArr == nil then return end

    for _, policy in ipairs(policyArr) do
        if TestSubPolicyMatch(key, policy.policyMatcher) then
            if policy.hookDef == "inherit" then
                return hookDef
            else
                ---@diagnostic disable-next-line: return-type-mismatch
                return policy.hookDef
            end
        end
    end

    return nil
end

--#region 元表Hook

function DebugHook.IndexHook(obj, key)
    local hookInfo = hookInfoTable[obj]

    --Log("Field ", tostring(key), " is being indexed:")

    --该字段不属于隐藏字段, 直接用原index
    if not hookInfo.hookDef.fieldFilter(key)then
        --Log("    field is not hidden, use original index function. value = ", tostring(originalIndex(obj, key)))
        return hookInfo.originalIndex(obj, key)
    end

    local val = hookInfo.hiddenFields[key]
    --Log("    hidden value = ", tostring(val))

    if not val then
        --隐藏字段表中没有该字段, 分两种情况
        --第一种情况是该字段是存储属性, 且确实不存在, 调用originalIndex也应当返回nil, 符合预期
        --第二种情况是该字段是一个计算属性(不实际存在, 在originalIndex中计算并返回), 也应当直接调用originalIndex
        val = hookInfo.originalIndex(obj, key)
        --Log("    this might be a calculated field, try original index function. value = ", tostring(val))
    end

    if hookInfo.hookDef.readHook then hookInfo.hookDef.readHook(obj, key, val) end

    --返回给外部之前看如果取的子表符合SubTableHookPolicy, 则需要进一步hook
    if type(val) == "table" and hookInfo.hookDef.subTableHookPolicies then
        local subHookDef = FindSubDebugHookDef(key, hookInfo.hookDef)
        if subHookDef ~= nil then
            DebugHook.HookInternal(val, hookInfo.hookRoot, hookInfo.rootName, CopyAppend(hookInfo.pathToRoot, key), subHookDef)
        end
    end

    return val
end

function DebugHook.NewindexHook(obj, key, value)
    local hookInfo = hookInfoTable[obj]
    --Log("Field ", tostring(key), " is being written:")

    --该字段不属于隐藏字段, 直接用原newindex
    if not hookInfo.hookDef.fieldFilter(key) then
        hookInfo.originalNewindex(obj, key, value)
        --Log("    field is not hidden, use original newindex function. value = ", tostring(value))
        return
    end

    --这里不应该直接将value写到隐藏表中。
    --合理的方式是先调用原来的newindex, 原newindex函数可能会写入该字段, 也可能不写入而只是进行某些操作
    --只有在原newindex实际创建了该字段的情况下才将其移到隐藏表中
    hookInfo.originalNewindex(obj, key, value)
    --Log("    field is hidden, use original newindex function first, value = ", tostring(value))

    if rawget(obj, key) ~= nil then 
        --Log("    field is created by original newindex, now move it to hidden table. ")
        MoveField(obj, hookInfo.hiddenFields, key)
    else
        --Log("    field is not actually created, no further process. ")
    end

    if hookInfo.hookDef.writeHook then hookInfo.hookDef.writeHook(obj, key, value) end
end

function DebugHook.GcHook(obj)
    local hookInfo = hookInfoTable[obj]
    hookInfo.originalGc(obj)
    hookInfoTable[obj] = nil
end

function DebugHook.PairsHook(obj)
    local hookInfo = hookInfoTable[obj]

    local keysSet = {}

    --先枚举obj中的所有元素
    local k, v = next(obj, nil)
    while k ~= nil do
        keysSet[k] = true
        k, v = next(obj, k)
    end

    --再枚举所有被隐藏的元素
    local k, v = next(hookInfo.hiddenFields, nil)
    while k ~= nil do
        keysSet[k] = true
        k, v = next(hookInfo.hiddenFields, k)
    end

    local _next = function(obj, key)
        local k = next(keysSet, key)
        return k, obj[k]
    end

    return _next, obj, nil
end

--#endregion

---@param hookDef DebugHookDefinition
function DebugHook.HookInternal(obj, hookRoot, hookName, hookPath, hookDef)
    -- 禁止重复hook
    if hookInfoTable[obj] then return false end

    local mt = MakeUniqueMeta(obj)

    ---@type DebugHookInfo
    ---@diagnostic disable-next-line: missing-fields
    local hookInfo = {}
    hookInfoTable[obj] = hookInfo

    hookInfo.hookOwner = obj
    hookInfo.hookDef = hookDef
    hookInfo.originalIndex = mt.__index and mt.__index or rawget
    hookInfo.originalNewindex = mt.__newindex and mt.__newindex or rawset
    hookInfo.originalGc = mt.__gc and mt.__gc or function()end
    hookInfo.hookRoot = hookRoot
    hookInfo.rootName = hookName
    hookInfo.pathToRoot = hookPath
    hookInfo.hiddenFields = {}

    MoveMatchingFields(obj, hookInfo.hiddenFields, hookInfo.hookDef.fieldFilter)
    
    --这一部分处理子表hook
    for k, v in pairs(hookInfo.hiddenFields) do
        if type(v) == "table" then
            local subHookDef =  FindSubDebugHookDef(k, hookDef)
            if subHookDef then 
                DebugHook.HookInternal(v, obj, hookName, CopyAppend(hookPath, k), subHookDef)
            end
        end
    end

    mt.__index = DebugHook.IndexHook
    mt.__newindex = DebugHook.NewindexHook
    mt.__gc = DebugHook.GcHook
    mt.__pairs = DebugHook.PairsHook

    --因为设置了__gc所以需要重新设置元表
    setmetatable(obj, mt)

    return true
end

---@param hookDef DebugHookDefinition
function DebugHook.Hook(obj, hookName, hookDef)
    return DebugHook.HookInternal(obj, obj, hookName, {}, hookDef)
end

---返回最初被hook的表, hook根名称, 以及该表相对于最初被hook的表的路径数组
function DebugHook.GetHookedTablePathInfo(obj)
    local hookInfo = hookInfoTable[obj]
    if not hookInfo then return end
    return hookInfo.hookRoot, hookInfo.rootName, hookInfo.pathToRoot
end

---将路径数组转换成 [key1][key2]... 的形式字符串
function DebugHook.PathArrayToString(path)
    local result = ""
    for _, fieldName in ipairs(path) do
        result = result .. "["..tostring(fieldName).."]"
    end
    return result
end

---传入obj(被hook的表)和一个key, 返回从hookRoot一直到该key的路径字符串
---在readHook和writeHook里面使用比较方便
function DebugHook.QuickGetPath(obj, key)
    local hookRoot, rootName, pathToRoot = DebugHook.GetHookedTablePathInfo(obj)
    local pathStr = DebugHook.PathArrayToString(pathToRoot)

    if rootName == nil then rootName = "(anonymous hook)" end
    return rootName..pathStr.."["..tostring(key).."]"
end

function DebugHook.DataBreakpoint(targetFullPath, obj, key, value, predicate)
    local hookRoot, rootName, pathToRoot = DebugHook.GetHookedTablePathInfo(obj)

    local changedFullPath = Deep.DeepCopy(pathToRoot, 1)
    table.insert(changedFullPath, 1, hookRoot)
    table.insert(changedFullPath, key)

    ---changedFullPath要么targetFullPath相等, 要么位于targetFullPath之上的层级
    if not (#changedFullPath <= #targetFullPath) then return false end
    for i = 1, #changedFullPath do
        if not rawequal(changedFullPath[i], targetFullPath[i]) then return false end
    end

    ---获取目标值
    local targetValue
    if #changedFullPath == #targetFullPath then
        targetValue = value
    else
        local relativePath = CopyRange(targetFullPath, #changedFullPath + 1, #targetFullPath)
        targetValue = Safe.SafeGetter(value, relativePath)
    end

    ---判断条件
    local bBreak = false
    if     predicate == nil                then bBreak = true
    elseif type(predicate) == "function"   then bBreak = predicate(targetValue)
    else                                        bBreak = (predicate == targetValue)
    end

    if bBreak then
        Log("Data breakpoint triggered! ---------------------------------------")
        BreakpointImpl() ---直接在这一行加个断点, 或者调试工具允许的话在BreakpointImpl里面调用调试器触发断点的接口
    end
end


--#region 各种Hook预设, 可以直接调用

---@class DebugHook_Presets
DebugHook.Presets = {}

---@param bAlsoLogWrites boolean 开启则会额外调用默认写入hook, 打出日志
---@param bpDefs table<string, function | any | nil> 数据断点定义表, 如 { ["fieldA.fieldB.fieldC"] = function(fieldC) return fieldC == value end, ... }
function DebugHook.Presets.WriteDataBreakpoint(bAlsoLogWrites, bpDefs)
    return function(obj, key, value)
        if bAlsoLogWrites then
            DebugHook.Presets.WriteLogger(obj, key, value)
        end

        for relPath, test in pairs(bpDefs) do
            local fullPath = Safe.MakePathTable(relPath)
            table.insert(fullPath, 1, hookInfoTable[obj].hookRoot)
            DebugHook.DataBreakpoint(fullPath, obj, key, value, test)
        end
    end
end

function DebugHook.Presets.WriteLogger(obj, key, value)
    local pathStr = DebugHook.QuickGetPath(obj, key)
    Log("[DebugHook] WRITE "..pathStr.." = "..tostring(value))
end

function DebugHook.Presets.ReadLogger(obj, key, value)
    local pathStr = DebugHook.QuickGetPath(obj, key)
    Log("[DebugHook] READ "..pathStr.." = "..tostring(value))
end

function DebugHook.Presets.POD(bRecursive)
    return {
        fieldFilter = function() return true end,
        readHook = DebugHook.Presets.ReadLogger,
        writeHook = DebugHook.Presets.WriteLogger,
        subTableHookPolicies = bRecursive and {{hookDef = "inherit"}} or nil,
    }
end

---@param parentHookDef DebugHookDefinition
---@param subHookDef DebugHookDefinition
function DebugHook.HookDefAddSubTable(parentHookDef, matcher, subHookDef)
    if parentHookDef.subTableHookPolicies == nil then parentHookDef.subTableHookPolicies = {} end
    table.insert(parentHookDef.subTableHookPolicies, 1, {
        policyMatcher = matcher,
        hookDef = subHookDef
    })
end

--#endregion

return DebugHook