local Property = {}
local ComputedObject    = require("LuaTools.DataObjects.ComputedObject")
local DataObject        = require("LuaTools.DataObjects.DataObject")
local Meta              = require("LuaTools.Meta.Meta")

-------------------------------------------------------------------------------------------------------------------------------
--#region 启用属性 / 直接新建属性(底层，平时不用)

---@enum ENewIndexPolicy 当一个对象已经启用了属性系统时，选择形如 obj.key = value 创建字段时的默认行为
Property.ENewIndexPolicy = {
    Field = 1,                  -- 直接用rawset在表中直接新建字段（默认）
    DataProperty = 2,         -- 新增一个简单属性（可直接读直接写、允许监听写入变更，但不支持ComputedObject功能)
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

    mt.properties = {}                      --各个属性对象
    mt.deep   = {}                          --记录哪些属性是深赋值属性

    mt.__property_mt = true                 --用于识别对象启用属性系统
    mt.newIndexPolicy = newIndexPolicy      --启用属性系统后 obj.key = value 新建字段的行为

    function mt.__index(obj, key)
        -- 特例：允许通过 __property__ 访问属性对象或额外信息，而不是属性的值
        if key == "__property__" then
            return mt.properties
        end

        if mt.properties[key] then                                  -- 优先访问 property getter
            return mt.properties[key]:Get()
        elseif mt.oldMt and mt.oldMt.__index then               -- 其次尝试 obj 原来的元表 __index
            return Meta.IndexWith(obj, key, mt.oldMt.__index)
        else                                                    
            return rawget(obj, key)                             -- 最后 rawget
        end
    end

    function mt.__newindex(obj, key, value)
        -- 特例：允许将一个实现了属性接口，并标记了 __property_interface 的对象赋值到一个原本为空的字段，来新建一个property
        if type(value) == "table" and value.__property_interface == true then
            mt.properties[key] = value
            return
        end

        -- 特例：深赋值属性
        -- 如果 obj[key] 这个属性是深赋值属性...
        if (mt.deep[key] == true) then
            local processedKeys = {}
            for k, v in pairs(obj[key]) do
                obj[key][k] = value[k]
                processedKeys[k] = true
            end
            for k, v in pairs(value) do
                if processedKeys[k] == nil then
                    obj[key][k] = v
                end
            end
            return
        end

        if mt.properties[key] then                                        -- 优先访问 property setter
            return mt.properties[key]:Set(value)
        elseif mt.oldMt and mt.oldMt.__newindex then                    -- 其次尝试 obj 原来的元表 __newindex
            return mt.oldMt.__newindex(obj, key, value)
        else
                                                                        -- 最后按NewIndexPolicy描述的行为执行
            if mt.newIndexPolicy == ENewIndexPolicy.Field then
                rawset(obj, key, value)
            elseif mt.newIndexPolicy == ENewIndexPolicy.DataProperty then
                Property.AddProperty(obj, key, DataObject.Create(value))
            elseif mt.newIndexPolicy == ENewIndexPolicy.ComputedProperty then
                local propertyObject = ComputedObject.Create(function()end)
                propertyObject:Set(value)
                Property.AddProperty(obj, key, propertyObject)
            end
        end
    end

    local function PropertyPairs()
        local function iterator(_, prevKey)
            local key, propertyObject = next(mt.properties, prevKey)
            if key == nil then return nil end
            return key, propertyObject:Get()
        end
        return iterator
    end
    mt.__pairs = Meta.MakeCombinedPairsMethod({Meta.GetBaseMetatable(mt).__pairs or Meta.rawpairs, PropertyPairs})

    local function PropertyLen()
        local maxIntKey = -1
        for k in pairs(obj) do
            if type(k) == "number" and math.floor(k) == k and maxIntKey < k then
                maxIntKey = k
            end
        end
        return (maxIntKey <= 0) and 0 or maxIntKey
    end
    mt.__len = PropertyLen

    setmetatable(obj, mt)
    return obj
end

function Property.SetDeepAssignment(obj, propertyKey, bDeepAssignment)
    if not Property.HasPropertyMeta(obj) then return end
    local mt = getmetatable(obj)
    mt.deep[propertyKey] = bDeepAssignment and true or nil
end

function Property.SetDefaultNewIndexPolicy(obj, newIndexPolicy)
    if Property.HasPropertyMeta(obj) then
        getmetatable(obj).newIndexPolicy = newIndexPolicy
    end
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

-- 为 obj 新增一个属性
function Property.AddProperty(obj, key, propertyObject)
    if not Property.HasPropertyMeta(obj) then
        Property.EnableProperty(obj)
    end

    local mt = getmetatable(obj)
    mt.properties[key] = propertyObject
end

-- 从 obj 删除一个属性
function Property.RemoveProperty(obj, key)
    if not Property.HasPropertyMeta(obj) then return end
    local mt = getmetatable(obj)
    mt.properties[key] = nil
    obj[key] = nil
end

--#endregion
-------------------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------------------------
--#region 基础属性

---将该函数的返回值赋值给一个已经启用属性系统的对象的空字段，可以新建一个普通属性
---使用方法：obj.[属性名] = Property(getter, setter)
---
---obj.[属性名]         相当于 obj:getter()
---obj.[属性名] = data  相当于 obj:setter(data)
---obj.__property__.[属性名] 访问 extraData
---
---@param getter fun():any?
---@param setter fun(newValue:any)
---【尤其注意！】setter 中禁止再写目标属性 (死递归)，禁止用rawset新建与属性有相同名称的字段 (访问无法到达__index和__newindex，属性系统失效)。属性对应的底层值应该具有另外的名称。
function Property.Property(getter, setter, extraData)
    return {
        __property_interface = true,
        Get = function(self) return getter() end,
        Set = function(self, value) setter(value) end,
        extraData = extraData
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
function Property.ToDataProperty(obj, key)
    local dataObject = DataObject.Create(obj[key])
    Property.RemoveProperty(obj, key)
    obj[key] = dataObject
end

---将 obj 的一个字段变成计算属性，保持当前的值
function Property.ToComputedProperty(obj, key, optComputeFunc)
    local computedObject
    if optComputeFunc then
        computedObject = ComputedObject.Create(optComputeFunc)
    else
        computedObject = ComputedObject.CreateWithData(obj[key])
    end
    Property.RemoveProperty(obj, key)
    obj[key] = computedObject
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
            obj[k] = ComputedObject.CreateWithData(Property.PODtoComputedProperty(v, convertDepth and convertDepth-1 or nil))
        else
            obj[k] = ComputedObject.CreateWithData(v)
        end
    end

    return obj
end

---将一个POD表处理成一个拥有相同数据的对象，且该对象中的每一个字段都是简单属性
---convertDepth 提供整数时，代表转换的深度（1: t的所有字段都变成简单属性, 2: t和t的直接子表的所有字段都变成简单属性...）
---convertDepth 为空时：递归转换
---注意：这个转换不改变t，而是返回一个具有相同结构和数据，但启用了简单属性的拷贝。
---@param convertDepth integer?
function Property.PODtoDataProperty(t, convertDepth)
    if convertDepth == 0 then return t end

    local obj = {}
    Property.EnableProperty(obj, ENewIndexPolicy.DataProperty)

    for k, v in pairs(t) do
        if type(v) == "table" then
            obj[k] = DataObject.Create(Property.PODtoDataProperty(v, convertDepth and convertDepth-1 or nil))
        else
            obj[k] = DataObject.Create(v)
        end
    end

    return obj
end

--#endregion
-------------------------------------------------------------------------------------------------------------------------------

function Property.EmptyObject()
    return Property.EnableProperty({})
end

return Property