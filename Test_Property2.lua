local Property          = require "LuaTools.DataObjects.Property"
local ComputedObject    = require "LuaTools.DataObjects.ComputedObject"

local function OnNameChanged(newValue) print(string.format("Name changed to %s", newValue)) end
local function OnScoreChanged(newValue) print(string.format("Score changed to %s", newValue)) end
local function OnAverageChanged(newValue) print(string.format("AverageScore changed to %s", newValue)) end

local rawData = {
    name = "John",
    age = 25,
    scores = {
        math = 90,
        english = 85
    }
}

-- 将POD表转换为带依赖属性的表
local data = Property.PODtoComputedProperty(rawData)

-- 创建计算属性
data.averageScore = Property.ComputedProperty(function() return (data.scores.math + data.scores.english)/2 end)

-- 设置依赖属性关系
-- 从 __property__ 特殊字段访问属性[对象]而不是属性值
data.__property__.averageScore:AddInvalidatedBy({data.scores.__property__.math,data.scores.__property__.english})

-- 添加监听器
data.__property__.name:AddListener(OnNameChanged) 
data.scores.__property__.math:AddListener(OnScoreChanged)
data.scores.__property__.english:AddListener(OnScoreChanged)
data.__property__.averageScore:AddListener(OnAverageChanged)

-- 选择是否输出调试信息
debug = true
if debug then
    data.__property__.averageScore._dbgName     = "average"
    data.scores.__property__.math._dbgName      = "math"
    data.scores.__property__.english._dbgName   = "english"
end

-------------------------------------------------------------------------------------
-- 使用例

print(data.name)
print(data.age)
print(data.scores.math)
print(data.scores.english)
print(data.averageScore)    -- 使用时才计算
print("")
print("")

data.scores.math = 60       -- averageScore 仅失效，不计算
print("")
print("")

data.scores.english = 70    -- averageScore 仅失效，不计算
print("")
print("")

print(data.averageScore)    -- 使用时计算
print("")
print("")

-- 现在 averageScore 处于主动模式，失效时自动计算
data.__property__.averageScore:SetActiveMode(true)

data.scores.math    = 80       -- averageScore 失效，然后自动更新
print("")
print("")

data.scores.english = 85       -- averageScore 失效，然后自动更新
print("")
print("")

-- 避免分别更新math和english导致averageScore重复更新
local autoBatch = ComputedObject.AutoBatch()    -- 批处理支持嵌套，所以建议使用AutoBatch，仅在非Batch Scope建立一个Batch Scope。
                                                -- 如果当前代码已经运行在Batch Scope，则不会创建
    data.scores.math = 70
    print("")
    data.scores.english = 100
    print("")
autoBatch.AutoEnd()                             -- 退出当前Batch Scope (如果确实创建了的话)
print("")
print("")

print(data.averageScore) -- Cache hit
print("")
print("")