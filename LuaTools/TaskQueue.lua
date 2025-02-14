
local TaskQueue = {} ---@class TaskQueue
local TASKQUEUE_DELAY_CALL_IMPL = function(time, callback) end

function TaskQueue.New()
    local obj = {} ---@type TaskQueue
    setmetatable(obj, {__index = TaskQueue})
    obj:Init()
    return obj
end

local TaskQueueTask = {} ---@class TaskQueueTask

---@param owner TaskQueue
---@param handle integer
function TaskQueueTask._New(owner, handle)
    local obj = {} ---@type TaskQueueTask
    setmetatable(obj, {__index = TaskQueueTask})
    obj:Init(owner, handle)
    return obj
end

---@param owner TaskQueue
---@param handle integer
function TaskQueueTask:Init(owner, handle)
    self._owner     = owner
    self._handle    = handle
    self._isAsync   = false
    self._fTask     = nil       ---@type function
    self.userdata   = nil       ---@type any
end

function TaskQueueTask:SetFunc(func)
    self._fTask = function()
        func()
        self:Done()
    end
    self._isAsync = false
    return self
end

function TaskQueueTask:Done()
    self._owner:_Next(self._handle)
end

---@param fAsync function
---fAsync必须且必须只调用一次TaskQueueTask:Done()
function TaskQueueTask:SetAsync(fAsync)
    self._fTask = fAsync
    self._isAsync = true
    return self
end

---@param lockKeys  any[]
function TaskQueueTask:AddLocks(lockKeys)
    _ = self._fTask or self:SetFunc(function()end)

    local prevTask = self._fTask
    self._fTask = function()
        -- Check if all locks are free.
        for _, lockKey in pairs(lockKeys) do
            if not self._owner._unlock[lockKey] then
                -- Waited lock is not free. Place fTaskLocked back to the front of the queue and stop execution.
                table.insert(self._owner._queue, 1, self)
                self._owner._isExecuting = false
                self._owner._executingTask = nil
                return
            end
        end
        -- Waited lock is free. Do normal task execution.
        prevTask()
    end

    return self
end

function TaskQueueTask:AddDelay(delayTime)
    _ = self._fTask or self:SetFunc(function()end)

    local prevTask = self._fTask
    self._fTask = function()
        TASKQUEUE_DELAY_CALL_IMPL(delayTime, prevTask)
    end
    self._isAsync = true
    return self
end

function TaskQueueTask:Push(bRunImmediately)
    self._owner:PushTask(self, bRunImmediately)
end

function TaskQueueTask:Cancel()
    self._owner:CancelTask(self._handle)
end

function TaskQueueTask:SetTimeout(timeout)
    -- Timeout is for async tasks only.
    if not self._isAsync then return end

    local prevTask = self._fTask
    self._fTask = function()
        TASKQUEUE_DELAY_CALL_IMPL(timeout, function() self:Cancel() end)
        prevTask()
    end

    return self
end

-----------------------------------------------------------------------------------------------------------

function TaskQueue:Init(...)
    self._queue = {} ---@type TaskQueueTask[]
    self._isExecuting = false
    self._unlock = {}
    self._assignTaskHandle = 0
end

---@param optSynchronizedFunc nil|function
---@return TaskQueueTask task
function TaskQueue:CreateTask(optSynchronizedFunc)
    local task = TaskQueueTask._New(self, self:_MakeTaskHandle())
    if optSynchronizedFunc then
        task:SetFunc(optSynchronizedFunc)
    end
    return task
end

---@param synchronizedFunc function
---@return TaskQueueTask task
function TaskQueue:PushSynchronizedFunc(synchronizedFunc, bRunImmediately)
    return self:PushTask(self:CreateTask(synchronizedFunc), bRunImmediately)
end

---@param task  TaskQueueTask
---@return TaskQueueTask task
function TaskQueue:PushTask(task, bRunImmediately)
    table.insert(self._queue, task)
    if bRunImmediately then
        self:Start()
    end
    return task
end

---@param fTaskList TaskQueueTask[]
function TaskQueue:PushTasks(fTaskList, bRunImmediately)
    for _, fTask in ipairs(fTaskList) do
        table.insert(self._queue, fTask)
    end
    if bRunImmediately then
        self:Start()
    end
end

function TaskQueue:Start()
    -- A Task is being executed, fTask will eventually call _DoNext, so we do nothing.
    if self._isExecuting then return end
    self:_Next()
end

---@return boolean bSuccess
function TaskQueue:CancelTask(taskHandle)
    -- Only async tasks can be cancelled when current.
    -- We give up waiting for it and start process subsquent tasks.
    if self._executingTask and (taskHandle == self._executingTask._handle) then
        if self._executingTask._isAsync then
            self:_Next()
            return true
        else
            return  false
        end
    end

    -- Trivial case, removes a task from queue.
    for idx, task in ipairs(self._queue) do
        if task._handle == taskHandle then
            table.remove(self._queue, idx)
            return true
        end
    end

    return false
end

function TaskQueue:Length()
    return #self._queue
end

function TaskQueue:Unlock(lockKey, bRunImmediately)
    self._unlock[lockKey] = true

    -- Since we've released a lock, the task queue execution might be able to resume.
    if bRunImmediately then
        self:Start()
    end
end

function TaskQueue:Lock(lockKey)
    self._unlock[lockKey] = nil
end

function TaskQueue:LockAll()
    self._unlock = {}
end

function TaskQueue:_MakeTaskHandle()
    self._assignTaskHandle = self._assignTaskHandle + 1
    return self._assignTaskHandle
end

function TaskQueue:_Next(sourceTaskHandle)
    if (sourceTaskHandle ~= nil) and (self._executingTask ~= sourceTaskHandle) then
        -- The task that produced the call is not the current one, indicating that
        -- a running async task, which has been cancelled, is finally done.
        -- Since we've already moved on to subsequent tasks, nothing is done here.
        return
    end

    if self:Length() == 0 then
        self._isExecuting = false
        self._executingTask = nil
    else
        local task = self._queue[1]
        table.remove(self._queue, 1)
        self._isExecuting = true
        self._executingTask = task
        task._fTask()
    end
end

---@return TaskQueueTask[]
function TaskQueue:GetTasks()
    return self._queue
end

return TaskQueue