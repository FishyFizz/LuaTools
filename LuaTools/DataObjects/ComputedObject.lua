local GraphNode = require "LuaTools.Graph.GraphNode"

---@class ComputedObject
local ComputedObject = {}

---@enum ComputeBatchChangeType
ComputedObject.ChangeType = {
    Failed = 1,
    Updated = 2,
    Invalidated = 3,
}
local ChangeType = ComputedObject.ChangeType

local changeTypeName = {
    "Failed", "Updated", "Invalidated"
}

---@alias ComputeBatchProcessChangeInfo table<ComputedObject, ComputeBatchChangeType>

ComputedObject._batchReentrantInfo = {} ---@type _ComputeBatch[]

ComputedObject.Debug = {}
ComputedObject.Debug.ShowBatchInfo  = false

local log = function(...) print("[ComputedObject] ", ...) end
local logBatch = function(...) if ComputedObject.Debug.ShowBatchInfo then log(...) end end

------------------------------------------------------------------------------
--#region ComputeBatch

---@class _ComputeBatch
local ComputeBatch = {}

function ComputeBatch.New()
    ---@class _ComputeBatch
    local obj = {
        changes = {} ---@type ComputeBatchProcessChangeInfo
    }
    setmetatable(obj, {__index = ComputeBatch})

    return obj
end

function ComputedObject.IsInBatch()
    return #ComputedObject._batchReentrantInfo > 0
end

function ComputedObject.AutoBatch()
    if  #ComputedObject._batchReentrantInfo == 0 then
        ComputedObject.StartBatch()
        return {
            AutoEnd = function() ComputedObject.EndBatch() end
        }
    else
        return {
            AutoEnd = function() end
        }
    end
end

function ComputedObject.StartBatch()
    ComputedObject._batchReentrantInfo[#ComputedObject._batchReentrantInfo+1] = ComputeBatch.New()
    logBatch("[BATCH BEGIN]---------------------------------------")
end

---@return _ComputeBatch
function ComputedObject.GetBatch(relFrameLevel)
    if relFrameLevel == nil then relFrameLevel = 0 end
    return ComputedObject._batchReentrantInfo[#ComputedObject._batchReentrantInfo + relFrameLevel]
end

function ComputedObject.EndBatch()
    if not ComputedObject.IsInBatch() then return end
    local batch = ComputedObject.GetBatch()
    logBatch("[POST BATCH]---------------------------------------")
    logBatch("[POST BATCH] Phase: process active mode objects")
    -- 先处理所有的主动模式且状态为Invalidated的缓存对象
    -- 最终这些对象都应当进入 Failed 或 Updated 状态
    -- 因为计算这些对象的代码可能也会导致新的主动模式缓存对象被Invalidate，所以这里用循环处理直到满足条件
    local bProcessedActiveObject = true
    while bProcessedActiveObject do
        bProcessedActiveObject = false
        for cacheObject, changeType in pairs(batch.changes) do
            if cacheObject._activeMode and changeType == ChangeType.Invalidated then
                cacheObject:Get()
                bProcessedActiveObject = true
            end
        end
    end

    logBatch("[POST BATCH] Phase: process Notification")
    -- 处理完毕之后再处理通知
    for cacheObject, changeType in pairs(batch.changes) do
        cacheObject:InvokeListeners()
        logBatch("[POST BATCH] object ", cacheObject._dbgName or cacheObject, " --- changeType ", changeTypeName[changeType])
    end

    -- 已经再本嵌套Batch处理且通知过的，上一层就不需要再处理了，移除
    local prevBatch = ComputedObject.GetBatch(-1)
    if prevBatch then
        for cacheObject, changeType in pairs(batch.changes) do
            prevBatch.changes[cacheObject] = nil
        end
    end

    ComputedObject._batchReentrantInfo[#ComputedObject._batchReentrantInfo] = nil
    logBatch("[BATCH END]---------------------------------------")
end

function ComputedObject.RunInBatch(fn, ...)
    ComputedObject.StartBatch()
    fn(...)
    ComputedObject.EndBatch()
end

--#endregion ComputeBatch
------------------------------------------------------------------------------

function ComputedObject.Create(optProvider)
    ---@class ComputedObject : DataObject
    local obj = {
        _data                    = nil,                     ---@type any                                 DataObject接口
        _listeners               = {},                      ---@type table<fun(data, bValid), boolean>   DataObject接口
        _dbgName                 = nil,                     ---@type string?                             DataObject接口

        _provider                = nil,                     ---@type fun(self:ComputedObject)               这个函数需要用户自己重载并通过SetProvider设置详见下方注释 
        _valid                   = false,                   ---@type boolean

        _activeMode              = false,                   ---@type boolean                             设置activeMode之后，缓存对象在被Invalidate时将会主动更新，而不是等到被访问产生Cache Miss再计算

        _relation                = GraphNode.New(),         ---@type GraphNode                           一个图节点，每一条 A->B 的边表示 A 代表的缓存对象更新会引起 B 的失效
    }
    obj._relation.data = obj
    
    setmetatable(obj, {
        __gc = obj.Destroy,
        __index = ComputedObject
    })
    obj:SetProvider(optProvider or obj._EmptyProvider)

    return obj
end

-----------------------------------------------------------------
--#region provider以及读写操作

---@param provider nil|fun(cache:ComputedObject)
function ComputedObject:SetProvider(provider)
    self._provider = provider or self._EmptyProvider
end

function ComputedObject:_EmptyProvider()
end

function ComputedObject:_InvokeProvider()
    self:_provider()
end

---@override DataObject.Get
function ComputedObject:Get(bForceUpdate)
    -- 不用更新
    if (not bForceUpdate) and self._valid then 
        if self._dbgName then log("[HIT]    ", tostring(self._dbgName)) end
        return self._data
    end

    -- 需要更新
    if self._dbgName then log("[MISS]   ", tostring(self._dbgName)) end
    local autoBatch = ComputedObject.AutoBatch()
        self:_InvokeProvider()
    autoBatch.AutoEnd()

    return self._data
end

function ComputedObject:TryUpdate()
    self:Get()
    return self._valid
end

function ComputedObject:IsValid()
    return self._valid
end

function ComputedObject:Set(data)
    -- 不用更新
    if self._valid and (self._data == data) then return end

    -- 需要更新
    local autoBatch = ComputedObject.AutoBatch()
        self._data = data
        self._valid = true
        self:_ToUpdatedState()
        if self._dbgName then 
            log("[UPDATE] ", tostring(self._dbgName))
        end
    autoBatch.AutoEnd()
end

--#endregion provider以及读写操作
-----------------------------------------------------------------

-----------------------------------------------------------------
--#region ComputedObject不同状态的转换

function ComputedObject:Invalidate()
    local autoBatch = ComputedObject.AutoBatch()
    self:_ToInvalidState()
    autoBatch.AutoEnd()
end

function ComputedObject:Fail()
    self:_ToFailedState()
end

function ComputedObject:_ToFailedState()
    self:_Invalidate(false, true)
    self:_UpdateBatchState(ChangeType.Failed)
end

function ComputedObject:_ToInvalidState()
    self:_Invalidate(false, true)
    self:_UpdateBatchState(ChangeType.Invalidated)
end

function ComputedObject:_ToUpdatedState()
    self._valid = true
    self:_Invalidate(true, true)
    self:_UpdateBatchState(ChangeType.Updated)
end

function ComputedObject:_UpdateBatchState(batchChangeType)
    local autoBatch = ComputedObject.AutoBatch()
    if self._dbgName then
        log("[CHANGE] ", self._dbgName, " state in batch:", changeTypeName[batchChangeType])
    end
    ComputedObject.GetBatch().changes[self] = batchChangeType
    autoBatch.AutoEnd()
end

function ComputedObject:_Invalidate(bChildrenOnly, bRecursive)
    if self._valid == false then return end -- 已经失效，不再处理

    if not bChildrenOnly then
        self.data = nil
        self._valid = false
        ComputedObject.GetBatch().changes[self] = ChangeType.Invalidated
    end
    
    if bRecursive then
        for _, invComputedObject in self._relation:IteNextNodes() do
            invComputedObject:_ToInvalidState()
        end
    end
end

--#endregion ComputedObject不同状态的转换
-----------------------------------------------------------------

-----------------------------------------------------------------
--#region 更新监听

---调用自己的Listeners
function ComputedObject:InvokeListeners()
    local cbCnt = 0
    for cb in pairs(self._listeners) do
        cb(self._data, self._valid)
        cbCnt = cbCnt + 1
    end
    if self._dbgName then
        if cbCnt > 0 then 
            --log("[CALLBACK]  ", tostring(self.dbgName), " Invoked", cbCnt ,"listeners") 
        end
    end
end

---@param callback fun(data:any, valid:boolean)
---@return function callbackHandle
---@override DataObject.AddListener
function ComputedObject:AddListener(callback)
    self._listeners[callback] = true
    return callback
end

---@override DataObject.RemoveListener
function ComputedObject:RemoveListener(callbackHandle)
    self._listeners[callbackHandle] = nil
end

---@override DataObject.RemoveAllListeners
function ComputedObject:RemoveAllListeners()
    self._listeners = {}
end

--#endregion 更新监听
-----------------------------------------------------------------

-----------------------------------------------------------------
--#region 缓存依赖关系

---@param others ComputedObject[]
function ComputedObject:AddInvalidateOther(others)
    for _, newChild in ipairs(others) do
        -- 添加 self -> other
        self._relation:AddEdgeTo(newChild._relation)
    end
end

function ComputedObject:RemoveInvalidates(others)
    for _, childToRemove in ipairs(others) do
        -- 添加 self -> other
        self._relation:RemoveEdgeTo(childToRemove.relation)
    end
end

function ComputedObject:AddInvalidatedBy(others)
    for _, other in ipairs(others) do
        other:AddInvalidateOther({self})
    end
end

function ComputedObject:RemoveInvalidatedBy(others)
    for _, other in ipairs(others) do
        other:RemoveInvalidates({self})
    end
end

--#endregion
-----------------------------------------------------------------

-----------------------------------------------------------------
--#region 主动模式

function ComputedObject:SetActiveMode(bActive)
    if bActive then
        self._activeMode = true
        local autoBatch = ComputedObject.AutoBatch()
        self:Get()
        autoBatch.AutoEnd()
    else
        self._activeMode = false
    end
end

--#endregion 
-----------------------------------------------------------------

-----------------------------------------------------------------
--#region 销毁(需要从依赖图中删除节点连接)

function ComputedObject:Destroy()

    for _, other in self._relation:IteNextNodes() do
        self:RemoveInvalidates(other)
    end

    for _, other in self._relation:ItePrevNodes() do
        self:RemoveInvalidatedBy(other)
    end

    self._relation.data = nil
end

--#endregion
-----------------------------------------------------------------

return ComputedObject