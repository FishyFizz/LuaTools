local TreeNode = require "LuaTools.Graph.TreeNode"
local Proxy    = require "LuaTools.Meta.Proxy"

local RedDotData = {}

local function CBool(x)
    return x~=nil and x~=false and x~=0
end

---@class RedDotDataTreeNodeData
---@field children table<any, RedDotDataTreeNode>

---@class RedDotDataTreeNode :TreeNode
---@field data RedDotDataTreeNodeData

---创建一个根节点，返回其proxy
function RedDotData.Create()
    ---@type RedDotDataTreeNode
    local node = TreeNode.New(nil, nil)

    ---@class RedDotDataTreeNodeData
    node.data = {
        children = {},
        value = 0,
    }

    local proxy = Proxy.Create(node, RedDotData.OnRedDotTreeNodeRead, RedDotData.OnRedDotTreeNodeWrite)
    return proxy, node
end

---返回一个子节点的proxy
---@param node RedDotDataTreeNode
function RedDotData.OnRedDotTreeNodeRead(node, key)
    if key == "value" then
        return Proxy.Override(node.data.value)
    end

    local childNode = node.data.children[key]
    if childNode == nil then
        local childProxy
        childProxy, childNode = RedDotData.Create()
        node:AddChild(childNode)
        node.data.children[key] = childNode
    end
    local childProxy = Proxy.Create(childNode, RedDotData.OnRedDotTreeNodeRead, RedDotData.OnRedDotTreeNodeWrite)
    return Proxy.Override(childProxy)
end

---设置一个子节点的值/新建一个子节点/删除子节点
---@param node RedDotDataTreeNode
function RedDotData.OnRedDotTreeNodeWrite(node, key, value)
    local childNode = node.data.children[key]

    -- 删除子节点
    if value == nil then
        if childNode == nil then return end
        RedDotData.RedDotTreeNodeDestroy(childNode)
        return Proxy.Handled
    end

    -- 新增子节点
    if childNode == nil and value ~= nil then
        local childProxy
        childProxy, childNode = RedDotData.Create()
        node:AddChild(childNode)
        node.data.children[key] = childNode
        -- 不要返回，fall through 到设置子节点值的 case
    end

    -- 尝试设置子节点的值
    RedDotData.RedDotTreeNodeUpdateValue(childNode, value, true)
    
    return Proxy.Handled
end

---@param node RedDotDataTreeNode
function RedDotData.RedDotTreeNodeUpdateValue(node, newValue, bPropagate, __bInternal)
    -- 如果节点拥有子节点则拒绝设置，有子节点的节点值永远等于激活的直接子节点数量
    if node:HasChild() and (not __bInternal) then return end

    local oldValue = node.data.value
    local oldState = CBool(node.data.value)
    node.data.value = newValue
    local newState = CBool(newValue)

    if bPropagate then
        local parent = node:GetParent() ---@type RedDotDataTreeNode
        if parent == nil then return end
        if oldState ~= newState then
            if newState == false then
                RedDotData.RedDotTreeNodeUpdateValue(parent, parent.data.value - 1, true, true)
            else
                RedDotData.RedDotTreeNodeUpdateValue(parent, parent.data.value + 1, true, true)
            end
        end
    end
end

---@param node RedDotDataTreeNode
function RedDotData.RedDotTreeNodeDestroy(node)
    -- 先使自身数据为0 并通知父级
    RedDotData.RedDotTreeNodeUpdateValue(node, 0, true, true)

    -- 自底向上删除所有父子关系并设置值为0
    node:ProcessBottomUp(
        function (node, data, resultFromChildren, control)
            data.value = 0
            node:RemoveAllEdgeFromThis()
        end
    )

    -- 将自身从父级断开
    local parent = node:GetParent() ---@type RedDotDataTreeNode
    if parent == nil then return end
    parent.data.children[node] = nil
    parent:RemoveChild(node)
end

return RedDotData