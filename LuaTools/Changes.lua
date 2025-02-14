local Deep = require "LuaTools.Deep"
local Default = require "LuaTools.Default"

local Changes = {} ---@class FishyLibs_Changes

function Changes._DefaultDiff(a, b)
    return a ~= b
end

function Changes._EmptyGetter() end

---@type Tracker
Changes._trackerDefaults = {
    getter = Changes._EmptyGetter,
    reduceFunc = Deep.MakeDeepCopier(1),
    diffFunc = Changes._DefaultDiff,
    lastReducedData = nil,
}

---@param tracker Tracker
function Changes._Diff(tracker)
    local reduced = tracker.reduceFunc(tracker.getter())
    return tracker.diffFunc(tracker.lastReducedData, reduced)
end

---@param tracker Tracker
function Changes._DiffUpdate(tracker)
    local reduced = tracker.reduceFunc(tracker.getter())
    local ret = tracker.diffFunc(tracker.lastReducedData, reduced)
    tracker.lastReducedData = reduced
    return ret
end

function Changes.MakeTracker(getter, reduceFunc, diffFunc)
    ---@class Tracker
    ---@field getter fun():any
    ---@field reduceFunc fun(data:any):any
    ---@field diffFunc fun(reducedOld:any, reducedNew:any):any
    ---@field lastReducedData any
    local obj = {}

    Default.FillDefault(obj, Changes._trackerDefaults)
    local obj = {
        getter = getter,
        reduceFunc = reduceFunc,
        diffFunc = diffFunc,
        lastReducedData = nil,
    }

    obj.Diff        = Changes._Diff
    obj.DiffUpdate  = Changes._DiffUpdate

    return obj
end

return Changes