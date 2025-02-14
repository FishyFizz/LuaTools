-- 深比较、深拷贝库
---@class FishyLibs_Deep
local Deep = {}

local Safe = require("LuaTools.Safe") ---@type FishyLibs_Safe

---深比较
---maxDepth为空时将深比较到底。
---maxDepth为0时, 相当于直接比较 x == y
---maxDepth为1时, 用默认 == 比较x和y当中的字段
---依此类推
function Deep.DeepEqual(x, y, maxDepth, __loopGuard)
    if __loopGuard == nil then __loopGuard = {} end

    -- 递归终结条件：两者类型不相等则全不相等, 非表数据返回直接比对结果
    if type(x) ~= type(y) then return false end
    if type(x) ~= "table" then return x == y end

    -- 递归终结条件：已达到最大深度, 不再深比较, 直接比较返回
    if maxDepth and maxDepth == 0 then return x == y end

    -- 递归终结条件：要比较的子表是之前遍历到过的表,存在循环引用,应该要认为是相等的
    if __loopGuard[x] == y then return true end

    -- 先把当前比对的表加入loopGuard
    __loopGuard[x] = y

    -- 对每个x的成员, 看y中对应成员是否深相等
    local setOfComparedKeys = {}
    for k, _ in pairs(x) do
        setOfComparedKeys[k] = true
        if not Deep.DeepEqual(x[k], y[k], maxDepth and (maxDepth-1) or nil, __loopGuard) then return false end
    end

    -- 对每个y的成员, 看x中对应成员是否深相等(跳过x中出现过的key, 已经比对过)
    for k, _ in pairs(y) do
        if not setOfComparedKeys[k] then --跳过已经比对过的部分
            setOfComparedKeys[k] = true
            if not Deep.DeepEqual(x[k], y[k], maxDepth and (maxDepth-1) or nil, __loopGuard) then return false end
        end
    end

    return true
end

---深拷贝一个表
---maxDepth为空时将深拷贝到底。
---maxDepth为0时, 相当于直接返回val。
---maxDepth为1时, 返回一个内容和val相同的表, 但里面的每一个子表和val中的子表是相同的引用。
---依此类推
function Deep.DeepCopy(val, maxDepth, __refRedirectTable)
    if __refRedirectTable == nil then __refRedirectTable = {} end

    -- 超过最大深拷贝层数, 即使可能是表引用, 也直接返回原值
    if maxDepth and maxDepth == 0 then
        return val
    end

    -- 不是表引用, 直接返回原值
    if type(val) ~= "table" then return val end

    -- 是表引用, 且该表已经在本次操作中被深拷贝过,则直接重定向（这可以避免循环引用导致的DeepCopy无限复制,同时保留原表结构中的引用关系）
    if __refRedirectTable[val] ~= nil then
        return __refRedirectTable[val]
    end

    -- 深拷贝流程
    local result = {}
    __refRedirectTable[val] = result
    for k, v in pairs(val) do
        result[k] = Deep.DeepCopy(v, maxDepth and (maxDepth - 1) or nil, __refRedirectTable)
    end

    return result
end

function Deep.MakeDeepCopier(maxDepth)
    return function(val)
        return Deep.DeepCopy(val, maxDepth)
    end
end

function Deep.MakeDeepEqualityTest(maxDepth)
    return function(a, b)
        return Deep.DeepEqual(a, b, maxDepth)
    end
end


---@class FieldCopyInfo
---@field path string
---@field copyMethod function|integer|nil 传入函数：使用该函数进行拷贝。传入整数或nil：使用DeepCopy, 参数代表层数

---@param copyInfos FieldCopyInfo[]
function Deep.MakeCustomCopier(copyInfos)
    local compiledCopyInfos = {}

    for i, copyInfo in ipairs(copyInfos) do
        local copyMethod = copyInfo.copyMethod
        if type(copyMethod) ~= "function" then
            copyMethod = Deep.MakeDeepCopier(copyMethod)
        end

        compiledCopyInfos[i] = {
            getter = Safe.MakeGetter(copyInfo.path),
            setter = Safe.MakeSetter(copyInfo.path),
            copyMethod = copyMethod
        }
    end
    return function(src)
        local result = {}
        for _, copyInfo in ipairs(compiledCopyInfos) do
            local data = copyInfo.getter(src)
            local copy = copyInfo.copyMethod(data)
            copyInfo.setter(result, copy, true)
        end
        return result
    end
end


---@class EqualityTestInfo
---@field path string
---@field testMethod function|integer|nil 传入函数：使用该函数进行比较。传入整数或nil：使用DeepEqual, 参数代表层数

---@param testInfos EqualityTestInfo[]
function Deep.MakeCustomEqualityTest(testInfos)
    local compiledTestInfos = {}

    for i, testInfo in ipairs(testInfos) do
        local testMethod = testInfo.testMethod
        if type(testMethod) ~= "function" then
            testMethod = Deep.MakeDeepEqualityTest(testMethod)
        end

        compiledTestInfos[i] = {
            getter = Safe.MakeGetter(testInfo.path),
            testMethod = testMethod
        }
    end
    return function(a, b)
        for _, testInfo in ipairs(compiledTestInfos) do
            local dataA = testInfo.getter(a)
            local dataB = testInfo.getter(b)
            local bEqual = testInfo.testMethod(dataA, dataB)
            if not bEqual then return false end
        end
        return true
    end
end

return Deep