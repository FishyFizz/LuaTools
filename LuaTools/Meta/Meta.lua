local Meta = {}

---@alias IndexingMethod table|fun(t:table, k:any)

Meta.ForwardFunctionNames = {
    -- Arithmetics
    "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__idiv", 

    -- Bitwise
    "__band", "__bor", "__bxor", "__bnot", "__shl", "__shr",

    -- Container
    "__concat", "__len", "__pairs",

    -- Comparison
    "__eq", "__lt", "__le",

    -- Member Access
    "__index", "__newindex",

    -- Other
    "__call", "__gc", "__close",
}

-- 相当于 pairs，但是不会尝试调用 t 的元表 __pairs 实现
local function rawpairs(t)
    return next, t, nil
end

local function nop() end

-- 这些元方法即使在baseMetatable中不存在，也有默认实现
Meta.DefaulMetaFunctionImp = {
    __len       = rawlen,
    __eq        = rawequal,
    __newindex  = rawset,
    __pairs     = rawpairs,
    __gc        = nop,
    __close     = nop,
}

---元表完美转发，提供一个基础元表，构建一个新的元表，与之前的元表具有完全相同的行为
---而且原有的元表中，元方法被修改，该元表的行为也会改变与其一致，数据也通过__index继承原来的元表
---这个新的元表中的元方法可以被重写，达到选择性覆盖元方法，其余元方法透传的效果
---理论上可以一致嵌套且不影响各层的功能
function Meta.MakeForwardedMetatable(baseMetatable)
    local resultMetatable = {}
    for _, funcName in ipairs(Meta.ForwardFunctionNames) do
        resultMetatable[funcName] =
            function(...)
                if baseMetatable[funcName] then                         -- 尝试调用原来的metatable中的方法
                    return baseMetatable[funcName](...)                 
                elseif Meta.DefaulMetaFunctionImp[funcName] then        -- 如果原来的metatable没有定义该方法
                    return Meta.DefaulMetaFunctionImp[funcName](...)    -- 使用默认实现(__len/__eq/__newindex)
                else
                    assert(false,
                    "Metafunction "..funcName.." is not present in object's base metatable, operation is illegal."
                    )
                end
            end
    end

    -- __index 需要特殊处理，因为有 __index 为函数或表的情况
    resultMetatable.__index = function(obj, key)
        return Meta.IndexWith(obj, key, baseMetatable.__index)
    end

    -- 这两个会额外开销，而且__gc本来就是不允许动态变更的，所以如果baseMetatable没有提供就剔除
    if baseMetatable.__close == nil then resultMetatable.__close = nil end -- 好像基本没地方会用
    if baseMetatable.__gc == nil then resultMetatable.__gc = nil end

    setmetatable(resultMetatable, {
        __index = baseMetatable,                        -- 原本的metatable可能包含其他信息，__index透传之后以后可以访问到
        ___FishyLibsMeta___ = true,
        ___FishyLibsMeta_baseMeta___ = baseMetatable
    })

    return resultMetatable
end

---如果 mt 是一个通过 MakeForwardedMetatable 产生的，则该函数返回 mt 的 baseMetatable
function Meta.GetBaseMetatable(mt)
    local mtmt = getmetatable(mt)
    if mtmt then
        return mtmt.___FishyLibsMeta_baseMeta___
    end
end

---把 indexMethod 当作 __index，然后获取 obj[key]
function Meta.IndexWith(obj, key, indexMethod)
    if rawget(obj, key) ~= nil then
        return rawget(obj, key)
    end

    if type(indexMethod) == "function" then
        return indexMethod(obj, key)
    elseif type(indexMethod) == "table" then
        return indexMethod[key]
    else
        return nil
    end
end

---确保 t 具有一个元表，然后返回 t 的元表
function Meta.EnsureMetatable(t)
    local mt = getmetatable(t)
    if mt == nil then
        mt = {}
        setmetatable(t, mt)
    end
    return mt
end

---按顺序给出多个表或函数，返回一个符合__index定义的函数，相当于逐个尝试给出的索引方式，直到获得第一个非空值，或全部失败
---@param indexMethods IndexingMethod[]
function Meta.MakeCombinedIndexMethod(indexMethods)
    return function(obj, key)
        for _, indexMethod in ipairs(indexMethods) do
            local result = Meta.IndexWith(obj, key, indexMethod)
            if result ~= nil then return result end
        end
    end
end

---为 t 单独设置一个完美转发元表，但替换 __index 方法，使得 t 可以在原来的基础上再继承索引方式
---见 MakeCombinedIndexMethod
function Meta.IndexCombine(t, indexMethod, isBefore)
    if getmetatable(t) == nil then
        setmetatable(t, {__index = indexMethod})
        return
    end

    local mt = getmetatable(t)
    local newMt = Meta.MakeForwardedMetatable(mt)

    if isBefore then
        newMt.__index = Meta.MakeCombinedIndexMethod({indexMethod, Meta.GetBaseMetatable(newMt).__index})
    else
        newMt.__index = Meta.MakeCombinedIndexMethod({Meta.GetBaseMetatable(newMt).__index, indexMethod})
    end

    setmetatable(t, newMt)
end

---替换或新增 t 的 __index 元方法，使得 t 在原本的基础上再继承索引方式
---见 MakeCombinedIndexMethod
---会直接修改 t 的元表，确认没有共享元表的情况才能使用
function Meta.IndexCombineInPlace(t, indexMethod, isBefore)
    if getmetatable(t) == nil then
        setmetatable(t, {__index = indexMethod})
        return
    end

    local mt = getmetatable(t)
    if mt.__index == nil then
        mt.__index = indexMethod
        return
    end

    local baseIndexMethod = mt.__index
    if isBefore then
        mt.__index = Meta.MakeCombinedIndexMethod({indexMethod, baseIndexMethod})
    else
        mt.__index = Meta.MakeCombinedIndexMethod({baseIndexMethod, indexMethod})
    end
end

---按顺序给出多个符合__pairs定义的函数，将它们合并
---for k, any... in combinedPairs(obj) do ...
---相当于
---for k, any... in pairsMethods[1](obj) do ...
---for k, any... in pairsMethods[2](obj) do ...
---以此类推
function Meta.MakeCombinedPairsMethod(pairsMethods)
    return function(obj)
        local currPhase  = 1
        local currIterator, currState, initControl = pairsMethods[1](obj)
        local function iterator(_, control)
            local currControl = control
            while true do
                -- 尝试调用当前阶段的iterator
                local result = {currIterator(currState, currControl)}
                if result[1] then
                    -- 成功则直接返回结果
                    return table.unpack(result)
                else
                    -- 失败则进入下一个阶段，调用下一阶段的pairs函数获得iterator, state, control
                    currPhase = currPhase + 1
                    if pairsMethods[currPhase] == nil then return nil end -- 循环的break条件在这里: 一直找不到下一个结果，而且已经到最后一个阶段
                    currIterator, currState, currControl = pairsMethods[currPhase](obj)
                    -- 再次循环，调用新阶段的iterator尝试继续枚举数据
                end
            end
        end

        return iterator, currState, initControl
    end
end

---为 t 单独设置一个完美转发元表，但替换 __pairs 方法，使得 t 可以在原来的基础上再继承枚举方式
---见 MakeCombinedPairsMethod
function Meta.PairsCombine(t, additionalPairs)
    local basePairs
    local mt = getmetatable(t)
    local newMt

    if mt == nil then
        newMt = {}
        setmetatable(t, newMt)
        basePairs = pairs
    else
        newMt = Meta.MakeForwardedMetatable(mt)
        setmetatable(t, newMt)
        basePairs = mt.__pairs or pairs
    end

    newMt.__pairs = Meta.MakeCombinedPairsMethod({basePairs, additionalPairs})
end

---替换或新增 t 的 __index 元方法，使得 t 可以在原来的基础上再继承枚举方式
---见 MakeCombinedPairsMethod
---会直接修改 t 的元表，确认没有共享元表的情况才能使用
function Meta.PairsCombineInPlace(t, additionalPairs)
    local mt = getmetatable(t)

    if mt == nil then
        setmetatable(t, {__pairs = additionalPairs})
        return
    end

    if mt.__pairs == nil then
        mt.__pairs = additionalPairs
        return
    end

    mt.__pairs = Meta.MakeCombinedPairsMethod({mt.__pairs, additionalPairs})
end

return Meta