local Property = {}
local ComputedObject    = require("LuaTools.DataObjects.ComputedObject")
local DataObject        = require("LuaTools.DataObjects.DataObject")
local Meta              = require("LuaTools.Meta.Meta")

Property.Invalidate = {} -- 占位用

-------------------------------------------------------------------------------------------------------------------------------
--#region 启用属性 / 直接新建属性(底层，平时不用)

---@enum ENewIndexPolicy 当一个对象已经启用了属性系统时，选择形如 obj.key = value 创建字段时的默认行为
Property.ENewIndexPolicy = {
    Field = 1,                  -- 直接用rawset在表中直接新建字段（默认）
    SimpleProperty = 2,         -- 新增一个简单属性（可直接读直接写、允许监听写入变更，但不支持ComputedObject功能)
    ComputedProperty = 3,         -- 新增一个缓存属性 (在Transparent的基础上支持ComputedObject功能，可以通过SetProvider将其变为一个计算缓存属性(见ComputedObject))
}
local ENewIndexPolicy = Property.ENewIndexPolicy

--- 允许obj使用属性系统，包括将 Property(...) 和 Property.ComputedProperty(...) 赋值给不存在的字段以新建属性
--- 除了__index和__newindex被替换以外，obj原有的其他元表方法将继续发挥作用...
---@param newIndexPolicy ENewIndexPolicy? 控制在写入表中原本不存在的字段时的行为，枚举值定义见ENewIndexPolicy
function Property.EnableProperty(obj, newIndexPolicy)
    if newIndexPolicy == nil then newIndexPolicy = ENewIndexPolicy.Field end

    local baseMt = Meta.EnsureMetatable(obj)
    local mt = Meta.MakeForwardedMetatable(baseMt)

    mt.getter = {}                          --每个属性的getter
    mt.setter = {}                          --每个属性的setter 
    mt.deep   = {}                          --记录哪些属性是深赋值属性
    mt.propertyExtraData = {}               --每个属性的属性对象/额外数据信息
    mt.__property_mt = true                 --用于识别对象启用属性系统
    mt.newIndexPolicy = newIndexPolicy      --启用属性系统后 obj.key = value 新建字段的行为
    function mt.__index(obj, key)
        -- 特例：允许通过 __property__ 访问属性对象或额外信息，而不是属性的值
        if key == "__property__" then
            return mt.propertyExtraData
        end

        if mt.getter[key] then                                  -- 优先访问 property getter
            return mt.getter[key](obj)
        elseif mt.oldMt and mt.oldMt.__index then               -- 其次尝试 obj 原来的元表 __index
            return Meta.IndexWith(obj, key, mt.oldMt.__index)
        else                                                    
            return rawget(obj, key)                             -- 最后 rawget
        end
    end

    function mt.__newindex(obj, key, value)
        -- 特例：允许将PropertyInitStruct赋值到一个原本为空的字段，来新建一个property
        if type(value) == "table" and value.__property_init_struct == true then
            Property.AddGetSetPropertyByInitStruct(obj, key, value)
            return
        end

        -- 特例：深赋值属性
        -- 如果 obj[key] 这个属性，是一个具有属性的表，且value也是一个表
        -- 则不应当把 obj[key] 直接替换成 value 这个表，而是拷贝 value 的字段值到 obj[key] 这个属性表当中
        if (mt.deep[key] == true) and (type(value) == "table") and (type(obj[key]) == "table") then
            for k, v in pairs(obj[key]) do
                obj[key][k] = value[k]
            end
            return
        end

        if mt.setter[key] then                                  -- 优先访问 property setter
            return mt.setter[key](obj, value)
        elseif mt.oldMt and mt.oldMt.__newindex then            -- 其次尝试 obj 原来的元表 __newindex
            return mt.oldMt.__newindex(obj, key, value)
        else
                                                                -- 最后按NewIndexPolicy描述的行为执行
            if mt.newIndexPolicy == ENewIndexPolicy.Field then
                rawset(obj, key, value)
            elseif mt.newIndexPolicy == ENewIndexPolicy.SimpleProperty then
                Property.AddGetSetPropertyByInitStruct(obj, key, Property.SimpleProperty(value))
            elseif mt.newIndexPolicy == ENewIndexPolicy.ComputedProperty then
                Property.AddGetSetPropertyByInitStruct(obj, key, Property.ComputedProperty(function()end))
                obj.key = value
            end

        end
    end

    local function PropertyPairs(obj)
        local function iterator(_, prevKey)
            local key, getter = next(mt.getter, prevKey)
            if key == nil then return nil end
            return key, getter(obj)
        end
        return iterator
    end

    mt.__pairs = Meta.MakeCombinedPairsMethod({Meta.GetBaseMetatable(mt).__pairs, PropertyPairs})

    setmetatable(obj, mt)
end

-- 判断 obj 是否已经在使用属性系统
function Property.HasPropertyMeta(obj)
    local mt = getmetatable(obj)
    if mt and mt.__property_mt == true then
        return true
    else
        return false
    end
end

---为 obj 添加一个属性(底层方法，平时用 Property.Property() 和 Property.ComputedProperty)
---@param getter                fun(obj:any):any?              应该具有这样的函数声明:  function obj:GetProperty() return propertyValue end
---@param setter                fun(obj:any, newValue:any)     应该具有这样的函数声明:  function obj:SetProperty() ... end
---@param propertyExtraData     any?                           任意值，未来可以通过 obj.\_\_property\_\_.[属性名] 来访问到 (property前后2下划线)
---【尤其注意！】setter 中禁止再写目标属性 (死递归)，禁止用rawset新建与属性有相同名称的字段 (访问无法到达__index和__newindex，属性系统失效)。属性对应的底层值应该具有另外的名称。
function Property.AddGetSetProperty(obj, key, getter, setter, propertyExtraData)
    if not Property.HasPropertyMeta(obj) then
        Property.EnableProperty(obj)
    end

    local mt = getmetatable(obj)
    mt.getter[key] = getter
    mt.setter[key] = setter
    mt.propertyExtraData[key] = propertyExtraData
end

function Property.AddGetSetPropertyByInitStruct(obj, key, initStruct)
    Property.AddGetSetProperty(obj, key, initStruct.getter, initStruct.setter, initStruct.extraData)
end

--#endregion
-------------------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------------------------
--#region 通过PropertyInitStruct新建属性(平时用)

---将该函数的返回值赋值给一个已经启用属性系统的对象的空字段，可以新建一个普通属性
---使用方法：obj.[属性名] = Property(getter, setter)
---
---obj.[属性名]         相当于 obj:getter()
---obj.[属性名] = data  相当于 obj:setter(data)
---obj.__property__.[属性名] 访问 extraData
---
---@param getter                fun(obj:any):any?              应该具有这样的函数声明:  function obj:GetProperty() return propertyValue end
---@param setter                fun(obj:any, newValue:any)     应该具有这样的函数声明:  function obj:SetProperty() ... end
---【尤其注意！】setter 中禁止再写目标属性 (死递归)，禁止用rawset新建与属性有相同名称的字段 (访问无法到达__index和__newindex，属性系统失效)。属性对应的底层值应该具有另外的名称。
function Property.Property(getter, setter, extraData)
    return {
        __property_init_struct = true,
        getter = getter,
        setter = setter,
        extraData = extraData
    }
end

---将该函数的返回值赋值给一个已经启用属性系统的对象的空字段，可以新增一个简单属性
---
---使用方法：obj.[属性名] = Property.SimpleProperty(getter, setter)
---obj.__property__.[属性名] 访问 DataObject
---
---简单属性：底层实现为DataObject，无特别的getter和setter，可直接读直接写、允许监听写入变更，但不支持ComputedObject功能
function Property.SimpleProperty(value)
    local dataObject = DataObject.Create(value)
    return {
        __property_init_struct = true,
        getter = function() return dataObject:Get() end,
        setter = function(owner, value) dataObject:Set(value) end,
        extraData = dataObject
    }
end

---将该函数的返回值赋值给一个已经启用属性系统的对象的空字段，可以新增一个缓存属性
---缓存属性：底层实现为ComputedObject，可配置为数据访问需要时才计算，或依赖数据更新时立即计算。计算后保持值直到被手动设置或刷新
---
---使用方法：obj.[缓存属性名] = Property.ComputedProperty(getter, setter)
---obj.__property__.[属性名] 访问 ComputedObject
---
---obj.[缓存属性名]                         相当于 computedObject:Get()
---obj.[缓存属性名] = data                  相当于 computedObject:Set(data)
---obj.[缓存属性名] = Property.Invalidate   相当于 computedObject:Invalidate()
---
---创建缓存属性以后，可以通过 obj.\_\_property\_\_.[缓存属性名] 访问缓存对象（详情查阅 Compute 库）
---@param fCompute  function?               该属性的值需要被计算的时候，fCompute将会被调用。fCompute应当返回一个任意值，如果计算失败应当返回 Property.Invalidate。
function Property.ComputedProperty(fCompute, ...)
    if fCompute == nil then fCompute = function() end end
    local computeArgs = {...}

    -- 缓存对象的 Provider 就是用 fCompute 计算出值，然后Set
    -- Property.Invalidate 代表缓存失效
    local function computeProvider(computedObject)
        local result = fCompute(table.unpack(computeArgs))
        if result == Property.Invalidate then
            computedObject:Fail()
        else
            computedObject:Set(result)
        end
    end

    local computedObject = ComputedObject.Create(computeProvider)

    return {
        __property_init_struct = true,
        getter = function(_) return computedObject:Get() end,
        setter = function(_, value)
            if value == Property.Invalidate then
                computedObject:Invalidate()
            else
                computedObject:Set(value)
            end
        end,

        -- 之后可以用 obj.__property__.computedPropertyKey 访问缓存对象
        extraData = computedObject,
    }
end

---Property.Property 的别名
function Property.__call_Property(_, getter, setter)
    return Property.Property(getter, setter)
end
setmetatable(Property, {__call = Property.__call_Property})

--#endregion
-------------------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------------------------
--#region 将普通字段转换为属性/普通数据表转换为属性表

---将 obj 的一个普通字段变成简单属性，保持当前的值
function Property.ToSimpleProperty(obj, key)
    local dataObject = DataObject.Create(obj[key])
    obj[key] = nil

    Property.AddGetSetProperty(obj, key, 
        function() return dataObject:Get() end, 
        function(owner, value) dataObject:Set(value) end,
        dataObject
    )
end

---将 obj 的一个字段变成缓存属性，保持当前的值
function Property.ToComputedProperty(obj, key, optComputeFunc)
    local computedObject = ComputedObject.Create(optComputeFunc or function() end) -- 默认provider不做任何操作
    if optComputeFunc then
        computedObject:Get()
    else
        computedObject:Set(obj[key])
    end
    obj[key] = nil

    Property.AddGetSetProperty(obj, key, 
        function() return computedObject:Get() end, 
        function(owner, value) computedObject:Set(value) end,
        computedObject
    )
end

---将一个POD表处理成一个拥有相同数据的对象，且该对象中的每一个字段都是缓存属性
---convertDepth 提供整数时，代表转换的深度（1: t的所有字段都变成缓存属性, 2: t和t的直接子表的所有字段都变成缓存属性...）
---convertDepth 为空时：递归转换
---注意：这个转换不改变t，而是返回一个具有相同结构和数据，但启用了缓存属性的拷贝。
---@param convertDepth integer?
function Property.PODtoComputedProperty(t, convertDepth)
    if convertDepth == 0 then return t end

    local obj = {}
    Property.EnableProperty(obj)

    for k, v in pairs(t) do
        if type(v) == "table" then
            obj[k] = Property.ComputedProperty()
            obj[k] = Property.PODtoComputedProperty(v, convertDepth and convertDepth-1 or nil)
        else
            obj[k] = Property.ComputedProperty()
            obj[k] = v
        end
    end

    return obj
end

---将一个POD表处理成一个拥有相同数据的对象，且该对象中的每一个字段都是简单属性
---convertDepth 提供整数时，代表转换的深度（1: t的所有字段都变成简单属性, 2: t和t的直接子表的所有字段都变成简单属性...）
---convertDepth 为空时：递归转换
---注意：这个转换不改变t，而是返回一个具有相同结构和数据，但启用了简单属性的拷贝。
---@param convertDepth integer?
function Property.PODtoSimpleProperty(t, convertDepth)
    if convertDepth == 0 then return t end

    local obj = {}
    Property.EnableProperty(obj, ENewIndexPolicy.SimpleProperty)

    for k, v in pairs(t) do
        if type(v) == "table" then
            obj[k] = Property.SimpleProperty()
            obj[k] = Property.PODtoSimpleProperty(v, convertDepth and convertDepth-1 or nil)
        else
            obj[k] = Property.ComputedProperty(v)
        end
    end

    return obj
end

--#endregion
-------------------------------------------------------------------------------------------------------------------------------

return Property