local Meta = require "LuaTools.Meta.Meta"
local Proxy = require "LuaTools.Meta.Proxy"

local baseMeta = {
    __index = function(obj, key)
        print("indexing ", obj, key)
    end,

    __lt = function(obj1, obj2)
        return obj1.a < obj2.a
    end
}

local obj1 = {
    a = 111,
    b = 222,
    1,2,3,4
}
setmetatable(obj1, baseMeta)

local obj2 = {
    a = 333,
    b = 222,
    1,2,3,4
}
setmetatable(obj2, baseMeta)


print("\n\n1 ------------------------------------------------------")
print(obj1 < obj2)      -- baseMeta 实现
print(obj1.indexTest)   -- baseMeta 实现
print(#obj1)            -- lua 实现
print(obj1 == obj2)     -- lua 实现


local mt1 = Meta.MakeForwardedMetatable(baseMeta)
local mt2 = Meta.MakeForwardedMetatable(baseMeta)

-- obj1 和 obj2 的元表替换成完美转发元表
setmetatable(obj1, mt1)
setmetatable(obj2, mt2)

-- 再调用一次，行为应该完全不变
print("\n\n2 ------------------------------------------------------")
print(obj1 < obj2)       -- mt1 -> baseMeta
print(obj1.indexTest)    -- mt1 -> baseMeta
print(#obj1)             -- mt1 -> lua
print(obj1 == obj2)      -- mt1 -> lua

-- baseMeta 现在新增 __eq，由于是完美转发，也应当生效
baseMeta.__eq = function(obj1, obj2)
    return obj1.b == obj2.b
end

print("\n\n3 ------------------------------------------------------")
print(obj1 == obj2)      -- mt1 -> baseMeta

-- baseMeta 现在新增 __len 和 __reportLen，由于是完美转发，也应当生效
baseMeta.__reportLen = 12345
baseMeta.__len = function(obj)
    print("new __len called!")
    return getmetatable(obj).__reportLen
end

print(#obj1)                    -- mt1 -> baseMeta

-- 测试 pairs 仍然有效
print("\n\n4 ------------------------------------------------------")
for k, v in pairs(obj1) do      -- mt1 -> rawpairs
    print(k, v)
end

print("\n\n5 ------------------------------------------------------")
assert(pcall(function() local x = obj1 + obj2 end) == false) -- mt1/mt2/baseMeta 都没有实现 __add


print("\n\n6 ------------------------------------------------------")
-- IndexCombine 使对象 “拥有多个__index”
local inject1 = {additional = "This is an additional field injected to obj1 by IndexCombine"}
Meta.IndexCombine(obj1, inject1, true) -- 设置为true，优先级大于原有的 __index

local function inject2(obj, key) print("Indexing function injected to obj2 is called") end
Meta.IndexCombine(obj2, inject2, false) -- 设置为false，优先级小于原有的 __index

print(obj1.additional) -- 优先级大于原有的 __index，所以 indexCombine -> inject1 -> 获得additional值
print(obj2.additional) -- 优先级小于原有的 __index，所以 indexCombine -> mt2 -> baseMeta -> baseMeta.__index返回空 -> inject2 -> 输出

print("\n\n7 ------------------------------------------------------")
for k, v in pairs(obj1) do -- mt1 -> rawpairs
    print(k, v)
end


print("\n\n8 ------------------------------------------------------")
local extraPairs1 = {
    extraKey1 = "obj1.extraValue1",
    extraKey2 = "obj1.extraValue2",
    extraKey3 = "obj1.extraValue3",
    extraNum  = 111,
}
Meta.IndexCombine(obj1, extraPairs1, true)
Meta.PairsCombine(obj1, function() return pairs(extraPairs1) end)
for k, v in pairs(obj1) do
    print(k, v)
end

print()

local extraPairs2 = {
    extraKey1 = "obj2.extraValue1",
    extraKey2 = "obj2.extraValue2",
    extraKey3 = "obj2.extraValue3",
    extraNum  = 222,
}
Meta.IndexCombine(obj2, extraPairs2, true)
Meta.PairsCombine(obj2, function() return pairs(extraPairs2) end)
for k, v in pairs(obj2) do
    print(k, v)
end

print("\n\n9 ------------------------------------------------------")
-- baseMeta 的小于方法变更，由于完美转发，还会继续生效
-- 且我们修改过的元表方法还会继续提供效果(extraNum字段)
baseMeta.__lt = function(obj1, obj2)
    print("Comparing ", obj1.extraNum, obj2.extraNum)
    return obj1.extraNum < obj2.extraNum
end
print(obj1<obj2)

print("\n\n10 ------------------------------------------------------")
local proxy1 = Proxy.Create(obj1, 
    function(obj, key) print("OnRead: ", obj, key)                  return Proxy.Proceed end,
    function(obj, key, value) print("OnWrite: ", obj, key, value)   return Proxy.Proceed end
)

local proxy2 = Proxy.Create(obj2, 
    function(obj, key) print("OnRead: ", obj, key)                  return Proxy.Proceed end,
    function(obj, key, value) print("OnWrite: ", obj, key, value)   return Proxy.Proceed end
)

proxy1.sum = proxy1.extraNum + proxy2.extraNum

print("\n\n11 ------------------------------------------------------")
-- proxy 的 pairs 转发
for k, v in pairs(proxy1) do
    print(k, v)
end

print("\n\n11 ------------------------------------------------------")
-- proxy 的元表方法继承
print(proxy1 < proxy2)
