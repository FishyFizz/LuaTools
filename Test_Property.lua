local Property = require("LuaTools.DataObjects.Property")

local obj = {}
Property.EnableProperty(obj)                                             -- EnableProperty 作用于一个对象之后，就可以通过向对象的字段赋值 Property() 或 Property.CachedProperty() 来新增属性

-----------------------------------------------------------------------------------------------------------------------------------------------------
-- 基础 getter/setter property用法: 配合成员方法

function obj:GetGreeting()
    return obj._greeting
end
function obj:SetGreeting(str)
    obj._greeting = str
end

obj.greeting = Property(obj.GetGreeting, obj.SetGreeting)
obj.greeting = "Hello, world!"
print(obj.greeting)

-----------------------------------------------------------------------------------------------------------------------------------------------------
-- 无 getter/setter，提供值变化监听的透明属性

obj.transparent = Property.SimpleProperty()
obj.__property__.transparent:AddListener(function(data) print("transparent property changed to ", data) end)

obj.transparent = "This is a transparent property"
print(obj.transparent)

-----------------------------------------------------------------------------------------------------------------------------------------------------
-- 已有的表字段转换为透明属性对象

obj.fieldToProperty = "This is a field"
print(obj.fieldToProperty)

Property.ConvertToProperty(obj, "fieldToProperty")

obj.__property__.fieldToProperty:AddListener(function(value) print("fieldToProperty changed to ", value) end)
obj.fieldToProperty = "This is a property"

print(obj.fieldToProperty)

-----------------------------------------------------------------------------------------------------------------------------------------------------
-- Cache 属性与 Compute on Use

local x = 123
local y = 456
function GetXPlusY() return x+y end
function PrintXPlusY(cacheData, cacheValid)
    print("x_plus_y cache is: ", cacheData, " cache is valid? ", cacheValid)
end

obj.x_plus_y = Property.CachedProperty(GetXPlusY)                        -- 创建一个叫 x_plus_y 的【带缓存】属性，并传入该缓存属性的计算函数
obj.__property__.x_plus_y:AddListener(PrintXPlusY)                       -- 获取属性对象要用 obj.__property__.x_plus_y，否则取到的是属性值而不是属性对象
                                                                         -- 并且添加一个该缓存属性更新时的回调
obj.__property__.x_plus_y.dbgName = "x_plus_y"                           -- 提供名称，将输出缓存状态追踪信息

print(obj.x_plus_y)                                                      -- obj.x_plus_y 属性被【第一次】访问，此时将发生以下事情：
                                                                         -- 1. Cache miss, 此时将调用缓存计算函数
                                                                         -- 2. 由于缓存的值被计算出来了（被更新），缓存的 Listener 将被调用 (property x+y is now ...)\
                                                                         -- 3. 最后 print 输出 579
x = 111
y = 222
print(obj.x_plus_y)                                                      -- obj.x_plus_y 被【再次】访问，Cache hit (仍然是之前的值)，输出 579

obj.x_plus_y = 9999                                                      -- 对缓存赋值，缓存属性的值将被强制设置为指定的值
                                                                         -- 由于缓存的值被更新，缓存的 Listener 将被调用 (property x+y is now ...)
print(obj.x_plus_y)                                                      -- Cache hit, 输出 9999

obj.x_plus_y = Property.Invalidate                                       -- Property.Invalidate 是一个特殊值，将其赋值给缓存属性，将使缓存属性的值变为nil，且进入invalid状态
print(obj.x_plus_y)                                                      -- Cache miss, 计算，调用Listener，然后输出 333 

                                                                         -- 这里考虑过赋值 nil 使缓存进入 invalid状态
                                                                         -- 但是因为lua语境下 "空" 很多时候也是当作一个有实际意义的值来使用的，所以采用了现在这样的设计

-----------------------------------------------------------------------------------------------------------------------------------------------------
-- 缓存依赖与缓存失效

local obj2 = {}
Property.EnableProperty(obj2)

function SquareXPlusY()
    if obj.x_plus_y == nil then return Property.Invalidate end
    return obj.x_plus_y * obj.x_plus_y
end

obj2.squared = Property.CachedProperty(SquareXPlusY)
obj2.__property__.squared:AddInvalidatedBy({obj.__property__.x_plus_y}) -- 缓存依赖条件: obj.x_plus_y (获取属性对象要用 obj.__property__.x_plus_y，否则取到的是属性值而不是属性对象)
                                                                        -- 带花括号是一次可以添加多个依赖条件
obj2.__property__.squared.dbgName = "squared"                           -- 提供名称，将输出缓存状态追踪信息

                                                                        
print(obj2.squared)                                                     -- obj2.squared 属性被【第一次】访问，Cache miss，调用计算函数，然后输出

obj.x_plus_y = 100                                                      -- 对缓存赋值，缓存属性的值将被强制设置为指定的值
                                                                        -- 此时 obj2.squared 将被 invalidate， 启用缓存状态追踪以查看更多信息

print(obj2.squared)                                                     -- Cache miss，重新计算

obj2.__property__.squared:SetActiveMode(true)                           -- 切换到Active模式
obj.x_plus_y = 11                                                       -- 缓存对象强制更新为 11，将引起 obj2.squared 被立即更新（主动模式）
print(obj2.squared)                                                     -- 已经主动更新过，Cache hit
