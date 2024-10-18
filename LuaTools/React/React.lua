-- React定义库
---@class FishyLibs_React
local React = {}

local Deep = require("LuaTools.Deep") ---@type FishyLibs_Deep
local Safe = require("LuaTools.Safe") ---@type FishyLibs_Safe
local Default = require("LuaTools.Default")

function React.DefaultSnapshot(val)
    return Deep.DeepCopy(val, 1)
end

function React.DefaultEqualityTest(a, b)
    return Deep.DeepEqual(a, b, 1)
end

---@class ReactEntry
---@field getter   fun():any | nil                       用于获取该值的bound getter
---@field snapshot fun(value:any):any                             用于复制该值，或能产生一个代表该值用于相等测试的值的函数          
---@field equalityTest   fun(before, after):boolean, any 旧值和新值经snapshot处理后传入该函数，相等则返回true，如果不相等返回false，可以多返回一个任意类型的值用于描述两者的区别

React._DefaultEntryTemplate = {
    getter = function() return end,
    equalityTest = React.DefaultEqualityTest,
    snapshot = React.DefaultSnapshot,
}

---@alias ReactSubscriber fun(snapshotA: any, snapshotB: any, changes: any)

---创建一个ReactEntry
---@return ReactEntry
---@param object table       绑定的变量的根，例如 t.var1.var2 的根是 t
---@param path string        绑定的变量的路径，例如 "var1.var2"
---@param optSnapshot function|nil 见ReactEntry定义，默认值为 DeepCopy(t, 1)
---@param optEqualityTest function|nil  见ReactEntry定义，默认值为DeepEqual(t, 1)
function React.ReactEntry(object, path, optSnapshot, optEqualityTest)
    if not optEqualityTest then optEqualityTest = React.DefaultEqualityTest end
    if not optSnapshot then optSnapshot = React.DefaultSnapshot end
    return {
        getter = Safe.MakeBoundGetter(object, path),
        equalityTest = optEqualityTest,
        snapshot = optSnapshot,
    }
end

---创建一个默认ReactEntry
function React.DefaultEntry()
    return Deep.DeepCopy(React._DefaultEntryTemplate)
end

function React.FillDefaultsForEntry(entry)
    Default.FillDefault(entry, React._DefaultEntryTemplate)
end

---@param optReactEntry ReactEntry|nil
function React.CreateReact(optReactEntry)
    ---@class ReactObject
    local reactObj = {
        _isReactObject = true, -- 类标识
        reactEntry = nil,  ---@type ReactEntry
        snapshot = nil,    ---@type any
        subscribers = {},  ---@type table<ReactSubscriber, ReactSubscriber> --自指Set
        subscriberInitialized = {} ---@type table<ReactSubscriber, boolean> 如果一个subscriber一次都还没有接收过更新，那么下次DoReact的时候无论EqualityTest结果如何，这个subscriber都会被调用。其他接收过数据的subscriber则不会。
    }

    function reactObj:Init(reactEntry)
        self.reactEntry = reactEntry
        React.FillDefaultsForEntry(self.reactEntry)
        self.snapshot = self.reactEntry.snapshot(self.reactEntry.getter())
        return self
    end

    ---ReactEntry不存在返回nil，数据没有发生变更返回false
    ---数据变更时返回两个整数successCount, failCount代表执行成功和失败的subscriber数量
    function reactObj:DoReact()
        if not self.reactEntry then return nil end
        local oldSnapshot = self.snapshot
        local newSnapshot = self.reactEntry.snapshot(self.reactEntry.getter())
        local equal, changes = self.reactEntry.equalityTest(oldSnapshot, newSnapshot)
        if equal then
            ---这里的处理逻辑见 subscriberInitialized 注释
            for subscriber, initialized in pairs(self.subscriberInitialized) do
                if not initialized then
                    Safe.SafeCall(subscriber, nil, nil, newSnapshot, nil)
                    self.subscriberInitialized[subscriber] = true
                end
            end

            self.snapshot = newSnapshot --虽然EqualityTest通过但是还是更新以下快照，反正都已经计算出来了
            return false, 0
        end

        local successCount = 0
        local failCount = 0
        for _, subscriber in pairs(self.subscribers) do
            local bFail = false
            local OnFail = function(err)
                print(err)
                bFail = true
            end
            
            Safe.SafeCall(subscriber, OnFail, oldSnapshot, newSnapshot, changes)
            self.subscriberInitialized[subscriber] = true

            successCount = successCount + ((not bFail) and 1 or 0)
            failCount = failCount + (bFail and 1 or 0)
        end

        self.snapshot = newSnapshot
        return successCount, failCount
    end

    function reactObj:Subscribe(subscriber, bOptUpdateNow)
        if not self.reactEntry then return self end
        self.subscribers[subscriber] = subscriber
        self.subscriberInitialized[subscriber] = false
        if bOptUpdateNow then
            Safe.SafeCall(subscriber, nil, nil, self.newSnapshot, nil)
            self.subscriberInitialized[subscriber] = true
        end
        return self
    end

    function reactObj:UnSubscribe(subscriber)
        if not self.reactEntry then return self end
        self.subscribers[subscriber] = nil
        self.subscriberInitialized[subscriber] = nil
        return self
    end

    function reactObj:UnSubscribeAll()
        if not self.reactEntry then return self end
        self.subscribers = {}
        self.subscriberInitialized = {}
        return self
    end

    if optReactEntry then
        reactObj:Init(optReactEntry)
    end
    return reactObj
end

return React