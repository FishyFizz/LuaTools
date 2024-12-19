local GraphNode = require("LuaTools.GraphNode")
local TreeNode = require("LuaTools.TreeNode")

local Root                  = TreeNode.New({name = "Root"   , sum = 0})
    local A                 = TreeNode.New({name = "A"      , sum = 0}, Root)
        local A_1           = TreeNode.New({name = "1"      , sum = 3}, A)
        local A_2           = TreeNode.New({name = "2"      , sum = 4}, A)
    local B                 = TreeNode.New({name = "B"      , sum = 0}, Root)
        local B_1           = TreeNode.New({name = "1"      , sum = 1}, B) 
        local B_2           = TreeNode.New({name = "2"      , sum = 2}, B)
    local C                 = TreeNode.New({name = "C"      , sum = 0}, Root)
        local C_1           = TreeNode.New({name = "1"      , sum = 0}, C)
            local C_1_1     = TreeNode.New({name = "1"      , sum = 123}, C_1)
            local C_1_2     = TreeNode.New({name = "2"      , sum = 456}, C_1)

-- 结构化处理测试: 自顶向下（数据从父节点传播到子节点）----------------------------------------------
print("TEST - ProcessTopDown")
--从上到下处理，把每个节点的 name 改成包含从根开始的路径
Root:ProcessTopDown(
    function(node, data, resultFromParent, control)
        local pathString

        if resultFromParent ~= nil then 
            pathString = resultFromParent.."->"..data.name
        else
            pathString = data.name
        end
        node.data.name = pathString

        return pathString
    end
)
--然后输出
Root:ProcessTopDown(
    function (node, data, resultFromParent, control)
        print(data.name)
    end
)
print("")


-- 结构化处理测试: 自底向上（数据从子节点汇总到父节点） -------------------------------------------
print("TEST - ProcessBottomUp")
--从下到上处理，把每个节点的 sum 设置为子节点的 sum 之和
Root:ProcessBottomUp(
    function (node, data, resultFromChildren, control)

        -- 如有子节点，汇总子节点的结果，否则维持设定的sum不变
        if node:ChildCount() > 0 then
            data.sum = 0
            for child, childResult in pairs(resultFromChildren) do
                data.sum = data.sum + childResult
            end
        end
        
        -- 返回自己的结果
        return data.sum
    end
)
--然后输出
Root:ProcessTopDown(
    function (node, data, resultFromParent, control)
        print(data.name, "\t\tsum = ",data.sum)
    end
)
print("")


-- 迭代器测试：子项 -----------------------------------------------------------------
print("TEST - IterateChildren")
for node, data in B:IterateChildren() do
    print(data.name)
end
print("")

-- 迭代器测试：沿父项一直到根 -----------------------------------------------------------------
print("TEST - IterateToRoot")
for node, data in C_1_2:IterateToRoot(true) do
    print(data.name)
end
print("")

-- 迭代器测试：从根到某项 -----------------------------------------------------------------
print("TEST - IterateFromRoot")
for node, data in C_1_2:IterateFromRoot(true) do
    print(data.name)
end
print("")


-- 结构化处理测试流程控制：中止-------------------------------------------
print("TEST - ProcessBottomUp-Stop")
--从下到上处理，但遇到Root->A就立刻结束
local result = Root:ProcessBottomUp(
    function (node, data, resultFromChildren, control)
        print("Process: ", data.name)
        if node == A then
            control:Stop("Bottom-up process terminated.")
        end
    end
)
print(result)
print("")

print("TEST - ProcessTopDown-Stop")
--从上到下处理，但遇到Root->A就立刻结束
local result = Root:ProcessTopDown(
    function (node, data, resultFromParent, control)
        print("Process: ", data.name)
        if node == A then
            control:Stop("Top-down process terminated.")
        end
    end
)
print(result)
print("")

-- 结构化处理测试流程控制：剪枝-------------------------------------------
print("TEST - ProcessBottomUp-Skip")
--从下到上处理，但遇到 Root->A->1 或 Root->B->1 就跳过兄弟节点
local result = Root:ProcessBottomUp( 
    function (node, data, resultFromChildren, control)
        print("Process: ", data.name)
        if node == A_1 or node == B_1 then
            control:SkipSiblings()
        end
    end
)
print("")

print("TEST - ProcessTopDown-Skip")
--从上到下处理，但遇到 Root->A 就不再向下
local result = Root:ProcessTopDown( 
    function (node, data, resultFromParent, control)
        print("Process: ", data.name)
        if node == A then
            control:SkipChildren()
        end
    end
)
print("")