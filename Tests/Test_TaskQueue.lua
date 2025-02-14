local TaskQueue = require "LuaTools.TaskQueue"

local tq = TaskQueue.New()

---@param asyncTask TaskQueueTask
function Task3CoroutineFunc(asyncTask)
    print("task 3 started in coroutine.")
    coroutine.yield()

    print("task 3 is done!")
    asyncTask:Done()
end
local task3_co = coroutine.create(Task3CoroutineFunc)

-- 1 立即完成
tq:CreateTask(function() print("task 1 is done!") end):Push()

-- 2 立即完成
tq:CreateTask(function() print("task 1 is done!") end):Push()

-- 3 需要调用coroutine.resume(task3_co)才能完成（模拟实际环境异步操作）
local asyncTask = tq:CreateTask()
asyncTask:SetAsync(function() coroutine.resume(task3_co, asyncTask) end):Push()

-- 4 等待锁 LOCK_TASK4 才能完成
tq:CreateTask(function() print("task 4 is done!") end):AddLocks({"LOCK_TASK4"}):Push()

-- 5 立即完成
tq:CreateTask(function() print("task 5 is done!") end):Push()

-----------------------------------------------------------------------------------------

tq:Start()  -- 1, 2 立即完成

print("Do something in main context to simulate waiting for an async task...")
coroutine.resume(task3_co) -- 3 结束后 4 不会执行，因为在等待 LOCK_TASK4

print("Unlocking LOCK_TASK4...")
tq:Unlock("LOCK_TASK4", true) -- 4 执行，然后 5 执行
