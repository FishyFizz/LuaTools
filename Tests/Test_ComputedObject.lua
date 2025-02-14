local ComputedObject = require("LuaTools.DataObjects.ComputedObject")

function SetCacheToRandom(ComputedObject)
    ComputedObject:Set(math.random(1,100))
end

local a = ComputedObject.Create(SetCacheToRandom)
local b = ComputedObject.Create(SetCacheToRandom)
local c = ComputedObject.Create(SetCacheToRandom)
local d = ComputedObject.Create(SetCacheToRandom)

local ab   = ComputedObject.Create(function(ab)    ab  :Set(a :Get()  + b :Get()) end)
local cd   = ComputedObject.Create(function(cd)    cd  :Set(c :Get()  + d :Get()) end)
local abcd = ComputedObject.Create(function(abcd)  abcd:Set(ab:Get()  + cd:Get()) end)

a._dbgName       = "a"
b._dbgName       = "b"
c._dbgName       = "c"
d._dbgName       = "d"
ab._dbgName      = "ab"
cd._dbgName      = "cd"
abcd._dbgName    = "abcd"

ab  :AddInvalidatedBy({a , b })
cd  :AddInvalidatedBy({c , d })
abcd:AddInvalidatedBy({ab, cd})

abcd:AddListener(function(data, valid) print("value of abcd = ", data, ", cache valid: ", valid)  end)

print("普通缓存模式")
print("----------------------------------------------------------")
print(abcd:Get())
print()
print()

-- 开启主动模式
for _, cache in ipairs({abcd}) do
    cache:SetActiveMode(true)
end

print("主动模式，无批处理")
print("----------------------------------------------------------")
print("强制刷新 a")
a:Set(1)
print("强制刷新 b")
b:Set(2)
print("强制刷新 c")
c:Set(3)
print("强制刷新 d")
d:Set(4)
print(abcd:Get())
print()
print()

print("主动模式，批处理")
print("----------------------------------------------------------")
ComputedObject.StartBatch()
print("强制刷新 a")
a:Set(5)

ComputedObject.StartBatch()
print("强制刷新 b")
b:Set(6)
print("强制刷新 c")
c:Set(7)
ComputedObject.EndBatch()


print("强制刷新 d")
d:Set(8)
ComputedObject.EndBatch()
print(abcd:Get())
print()
print()