local Property = require("LuaTools.Meta.Property")
local DataObject = require("LuaTools.DataObjects.DataObject")
local ComputedObject = require("LuaTools.DataObjects.ComputedObject")

local obj = {}
Property.EnableProperty(obj)                                             -- EnableProperty 作用于一个对象之后，就可以通过向对象的字段赋值 Property() 或 Property.CachedProperty() 来新增属性

-----------------------------------------------------------------------------------------------------------------------------------------------------
-- 基础 getter/setter property
obj.greeting = Property(function() return obj._greeting end, function(value) obj._greeting = value end)
obj.greeting = "Hello, world!"
print(obj.greeting)

-----------------------------------------------------------------------------------------------------------------------------------------------------
-- 无 getter/setter，提供值变化监听的透明属性

obj.transparent = DataObject.Create()
obj.__property__.transparent:AddListener(function(data) print("transparent property changed to ", data) end)

obj.transparent = "This is a transparent property"
print(obj.transparent)

-----------------------------------------------------------------------------------------------------------------------------------------------------
-- 已有的表字段转换为透明属性对象

obj.fieldToProperty = "This is a field"
print(obj.fieldToProperty)

Property.ToDataProperty(obj, "fieldToProperty")

obj.__property__.fieldToProperty:AddListener(function(value) print("fieldToProperty changed to ", value) end)
obj.fieldToProperty = "This is a property"

print(obj.fieldToProperty)

-----------------------------------------------------------------------------------------------------------------------------------------------------
-- Cache 属性与 Compute on Use

local x = 123
local y = 456

function PrintXPlusY(cacheData, cacheValid)
    print("x_plus_y cache is: ", cacheData, " cache is valid? ", cacheValid)
end

obj.x_plus_y = ComputedObject.Create(function() obj.x_plus_y = x + y end)   -- 创建一个叫 x_plus_y 的【带缓存】属性，并传入该缓存属性的计算函数
obj.__property__.x_plus_y:AddListener(PrintXPlusY)                          -- 获取属性对象要用 obj.__property__.x_plus_y，否则取到的是属性值而不是属性对象
                                                                            -- 并且添加一个该缓存属性更新时的回调
                                                                            
obj.__property__.x_plus_y.dbgName = "x_plus_y"                              -- 提供名称，将输出缓存状态追踪信息

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

obj.x_plus_y = ComputedObject.INVALID                                    -- Property.Invalidate 是一个特殊值，将其赋值给缓存属性，将使缓存属性的值变为nil，且进入invalid状态
print(obj.x_plus_y)                                                      -- Cache miss, 计算，调用Listener，然后输出 333 

                                                                         -- 这里考虑过赋值 nil 使缓存进入 invalid状态
                                                                         -- 但是因为lua语境下 "空" 很多时候也是当作一个有实际意义的值来使用的，所以采用了现在这样的设计

-----------------------------------------------------------------------------------------------------------------------------------------------------
-- 缓存依赖与缓存失效

local obj2 = {}
Property.EnableProperty(obj2)

obj2.squared = ComputedObject.Create(function()
    if obj.x_plus_y then 
        obj2.squared = obj.x_plus_y * obj.x_plus_y
    else
        obj2.squared = 0
    end
end)

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

-----------------------------------------------------------------------------------------------------------------------------------------------------
-- 自定义符合Property接口的属性对象

local propertyObject = {
    __property_interface = true, -- 用于属性元表识别的接口
    Get = function(self) print("Get is called") end,
    Set = function(self, value) print("Set is called with ", value) end
}
obj2.customProperty = propertyObject -- 创建属性

obj2.customProperty = 10000
print(obj2.customProperty)

-----------------------------------------------------------------------------------------------------------------------------------------------------
-- 属性深赋值
print("\n\n")

local student = {
    firstYear = {
        math = 70,
        english = 80,
        fees = {
            books = 100,
            food = 200,
        }
    },
    secondYear = {
        math = 80,
        english = 90,
        fees = {
            books = 130,
            food = 180,
        }
    }
}
student = Property.PODtoComputedProperty(student)

student.firstYear.average = ComputedObject.Create(
    function() student.firstYear.average = 
        (student.firstYear.math + student.firstYear.english)/2
    end)

    
student.firstYear.totalFees = ComputedObject.Create(function() student.firstYear.totalFees = student.firstYear.fees.books + student.firstYear.fees.food end)
student.firstYear.__property__.average:AddInvalidatedBy({student.firstYear.__property__.math, student.firstYear.__property__.english})
student.firstYear.__property__.totalFees:AddInvalidatedBy({student.firstYear.fees.__property__.books, student.firstYear.fees.__property__.food})

student.secondYear.average = ComputedObject.Create(function() student.secondYear.average = (student.secondYear.math + student.secondYear.english)/2 end)
student.secondYear.totalFees = ComputedObject.Create(function() student.secondYear.totalFees = student.secondYear.fees.books + student.secondYear.fees.food end)
student.secondYear.__property__.average:AddInvalidatedBy({student.secondYear.__property__.math, student.secondYear.__property__.english})
student.secondYear.__property__.totalFees:AddInvalidatedBy({student.secondYear.fees.__property__.books, student.secondYear.fees.__property__.food})

Property.SetDeepAssignment(student, "firstYear", true)
Property.SetDeepAssignment(student.firstYear, "fees", true)

--Property.SetDeepAssignment(obj, "secondYear", true)  用于对比

print(student.firstYear.average)
print(student.secondYear.average)

student.firstYear = {
    math = 65,
    english = 85,
    fees = {
        books = 300,
        food = 150,
    }
}

print(student.firstYear.average) --启用深赋值，一切正常
print(student.firstYear.totalFees) --启用深赋值，一切正常

student.secondYear = {
    math = 76,
    english = 98,
    fees = {
        books = 200,
        food = 120,
    }
}
print(student.secondYear.average)
print(student.secondYear.totalFees)


