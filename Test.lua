local Property = require "LuaTools.Meta.Property"
local obj = {}
Property.EnableProperty(obj, Property.ENewIndexPolicy.ComputedProperty)

obj.a = 123
obj.b = 456

obj.avg = Property.ComputedProperty(function() 
    return (obj.a + obj.b) / 2 
end)

obj.__property__.avg:AddInvalidatedBy({
    obj.__property__.a, 
    obj.__property__.b
})

print(obj.avg)

