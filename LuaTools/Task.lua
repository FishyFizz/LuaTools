local Task = {}

---@class TaskPrereqInfo
---@field task              Task
---@field bIsOptional       boolean | nil

---@alias TaskState                   "pending"|"done"|"failed"
---@alias TaskFailureRetryPolicy      "manual"|"automatic"
---@alias TaskExecutionPolicy         "cached"|"always"

---@class TaskDef
---@field taskId                any | nil
---@field prereq                TaskPrereqInfo[] | nil
---@field exec                  nil | fun(self:Task): (bSuccess: boolean)
---@field initialState          TaskState | nil
---@field failureRetryPolicy    TaskFailureRetryPolicy | nil
---@field executionPolicy       TaskExecutionPolicy | nil

---@class TaskInheritedInfo
---@field parentAlwaysExecuteCount  integer 该任务的直接前置需求里有多少个任务被配置为 executionPolicy = "always"

---@type TaskDef
local __defaultTaskDef = {
    taskId = nil,
    prereq = {},
    exec = function(task) return true end,
    initialState = "pending",
    failureRetryPolicy = "manual",
    executionPolicy = "cached",
}

---@param taskDef TaskDef
function Task.New(taskDef)

    for k, v in pairs(__defaultTaskDef) do
        if taskDef[k] == nil then taskDef[k] = v end
    end

    ---@class Task
    local obj = {}
    obj.taskId = taskDef.taskId
    obj.prereq = {} ---@type table<Task, TaskPrereqInfo>
    obj.followUps = {} ---@type table<Task, Task> 自指集合
    obj.exec   = taskDef.exec
    obj.state  = taskDef.initialState
    obj.failureRetryPolicy = taskDef.failureRetryPolicy
    obj.executionPolicy = taskDef.executionPolicy
    obj.inherited = {parentAlwaysExecuteCount = 0} ---@type TaskInheritedInfo

    ---@private
    function obj:_IncParentAlwaysExecuteCounter()
        --logctx:Log("+ parentAlwaysExecuteCount (", self ,")")
        self.inherited.parentAlwaysExecuteCount = self.inherited.parentAlwaysExecuteCount + 1
        --logctx:IncDepth()
        if self.inherited.parentAlwaysExecuteCount == 1 then
            for _, followup in pairs(self.followUps) do
                followup:_IncParentAlwaysExecuteCounter()
            end
        end
        --logctx:DecDepth()
    end

    ---@private
    function obj:_DecParentAlwaysExecuteCounter()
        --logctx:Log("- parentAlwaysExecuteCount (", self ,")")
        self.inherited.parentAlwaysExecuteCount = self.inherited.parentAlwaysExecuteCount - 1
        --logctx:IncDepth()
        if self.inherited.parentAlwaysExecuteCount == 0 then
            for _, followup in pairs(self.followUps) do
                followup:_DecParentAlwaysExecuteCounter()
            end
        end
        --logctx:DecDepth()
    end

    ---@private
    function obj:ShouldAlwaysExecute()
        return (self.executionPolicy == "always") or (self.inherited.parentAlwaysExecuteCount > 0)
    end

    function obj:Invalidate()
        --logctx:Log("Task "..tostring(self).." Invalidate")
        self.state = "pending"

        --logctx:IncDepth()
        for _, followUp in pairs(self.followUps) do
            followUp:Invalidate()
        end

        --logctx:DecDepth()
    end

    function obj:ResetFailState(bIncludingAllPrereq)
        --logctx:Log("Task "..tostring(self).." ResetFailState")
        if self.state == "failed" then
            self.state = "pending"
        end

        --logctx:IncDepth()
        if bIncludingAllPrereq then
            for _, prereqInfo in pairs(self.prereq) do
                prereqInfo.task:ResetFailState(true)
            end
        end
        --logctx:DecDepth()
    end

    ---@param task Task
    ---@param bIsOptional boolean
    function obj:AddPrereq(task, bIsOptional)
        --logctx:Log("Task "..tostring(self).." AddPrereq: ", tostring(task), " optional=", bIsOptional)

        self.prereq[task] = {task = task, bIsOptional = bIsOptional}
        task.followUps[self] = self

        --logctx:IncDepth()
        if task:ShouldAlwaysExecute() then
            self:_IncParentAlwaysExecuteCounter()
        end
        self:Invalidate()
        --logctx:DecDepth()
    end

    ---@param task Task
    function obj:RemovePrereq(task)
        --logctx:Log("Task "..tostring(self).." RemovePrereq: ", tostring(task))
        self.prereq[task] = nil
        task.followUps[self] = nil

        --logctx:IncDepth()
        if task:ShouldAlwaysExecute() then
            self:_DecParentAlwaysExecuteCounter()
        end
        self:Invalidate()
        --logctx:DecDepth()
    end

    ---@param execPolicy TaskExecutionPolicy
    function obj:SetExecutionPolicy(execPolicy)
        if execPolicy == self.executionPolicy then return end
        
        local oldShouldAlwaysExecute = self:ShouldAlwaysExecute()
        self.executionPolicy = execPolicy
        local newShouldAlwaysExecute = self:ShouldAlwaysExecute()

        if newShouldAlwaysExecute ~= oldShouldAlwaysExecute then
            local action
            if newShouldAlwaysExecute then
                action = "_IncParentAlwaysExecuteCounter"
            else
                action = "_DecParentAlwaysExecuteCounter"
            end

            for _, followup in pairs(self.followUps) do
                followup[action](followup)
            end
        end
    end

    ---@param retryPolicy TaskFailureRetryPolicy
    function obj:SetRetryPolicy(retryPolicy)
        self.failureRetryPolicy = retryPolicy
    end

    ---@return boolean bSuccess
    function obj:Execute(bInvalidateAndExecute)
        --logctx:Log("Task "..tostring(self).." Execute")
        --logctx:IncDepth()

        if bInvalidateAndExecute then
            self:Invalidate()
        end

        if self.state == "done" and (not self:ShouldAlwaysExecute()) then
            --logctx:Log("Cached state: DONE")
            --logctx:DecDepth()
            return true
        end
        if self.state == "failed" and self.failureRetryPolicy == "manual" then
            --logctx:Log("Cached state: FAILED")
            --logctx:DecDepth()
            return false
        end

        --logctx:Log("Prepareing prereqs")
        --logctx:IncDepth()
        local bPrereqReady = true
        for _, prereqInfo in pairs(self.prereq) do
            bPrereqReady = bPrereqReady and ((prereqInfo.task:Execute() == true) or (prereqInfo.bIsOptional == true))
        end
        --logctx:DecDepth()

        if not bPrereqReady then
            self.state = "failed"
            --logctx:Log("Prereqs FAILED")
            --logctx:DecDepth()
            return false
        end
        
        if self:exec() then
            self.state = "done"
            --logctx:Log("Task processed and DONE")
            --logctx:DecDepth()
            return true
        else
            self.state = "failed"
            --logctx:Log("Task FAILED processing")
            --logctx:DecDepth()
            return false
        end
    end

    for _, prereqInfo in pairs(taskDef.prereq) do
        obj:AddPrereq(prereqInfo.task, prereqInfo.bIsOptional)
    end

    return obj
end

return Task