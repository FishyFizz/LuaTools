local GraphNode = require("LuaTools.Graph.GraphNode")

local TreeNode = {} ---@class TreeNode: GraphNode

---@param   data    any?        节点中包含的数据
---@param   parent  TreeNode?   创建新节点后，将其放置到parent下
---@return  TreeNode
function TreeNode.New(data, parent)
    local obj = {}
    setmetatable(obj, {
        __index = function(t, k)
            return TreeNode[k] or GraphNode[k]
        end}
    )
    GraphNode.Init(obj, data, parent and {parent} or nil)
    return obj
end

-----------------------------------------------------------------------------
--#region 父子关系编辑、查询

---@param parent TreeNode?      将该节点【包括所有子节点】转移到新parent下（parent为空则该节点成为新Root）
function TreeNode:SetParent(parent)
    self:RemoveAllEdgeToThis()
    if parent ~= nil then
        self:AddEdgeFrom(parent)
    end
end

---@return TreeNode? parent     获取父节点(自身是根节点则返回nil)
function TreeNode:GetParent()
    return next(self._prev)
end

---@param child TreeNode        child:SetParent(self)
function TreeNode:AddChild(child)
    child:SetParent(self)
end

---@param child TreeNode? 为空则返回该节点是否有子节点，不为空则检查该节点是否有某个特定子节点
function TreeNode:HasChild(child)
    if child == nil then return next(self._next)~=nil end
    return self:HasEdgeTo(child)
end

---@param child TreeNode        检查父子关系后 child:SetParent(nil)
function TreeNode:RemoveChild(child)
    assert(self:HasEdgeTo(child), "TreeNode trying to remove a child that it does not own.")
    child:SetParent(nil)
end

function TreeNode:ChildCount()
    return self:OutCount()
end

--#endregion
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
--#region 迭代器：遍历各子节点 / 沿路径遍历

---遍历该树节点的直接子节点
---for node, data in treeNode:IterateChildren() do ...
---@return fun():TreeNode, any
function TreeNode:IterateChildren()
    return self:IteNextNodes()
end

---从该树节点向上一直遍历到树根
---for node, data in treeNode:IterateToRoot() do ...
---@param bIncludeThis boolean? 设为真则遍历从本节点开始，否则从本节点的父节点开始
function TreeNode:IterateToRoot(bIncludeThis)
    local nextNode = bIncludeThis and self or next(self._prev)

    ---@return TreeNode, any
    local function iterator(state, control)
        local currNode, currData = nextNode, (nextNode and nextNode.data or nil)
        if nextNode then nextNode = next(nextNode._prev) end
        return currNode, currData
    end

    return iterator
end

---从树根遍历到该节点，相当于反向的IterateFromRoot
---@param bIncludeThis boolean? 设为真则遍历到本节点结束，否则遍历到本节点的父节点就结束
---@return fun():TreeNode, any
function TreeNode:IterateFromRoot(bIncludeThis)
    --提前遍历找出 本节点->根节点 的路径
    local path = {}
    for node, data in self:IterateToRoot(bIncludeThis) do
        table.insert(path, node)
    end

    --反向遍历
    local nextIdx = #path
    local function iterator(state, control)
        local currNode, currData = path[nextIdx], (path[nextIdx] and path[nextIdx].data or nil)
        nextIdx = nextIdx - 1
        return currNode, currData
    end

    return iterator
end

--#endregion
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
--#region 结构化处理：自顶向下或自底向上地对当前节点为根的子树进行处理

-----------------------------------------------------------------------------
--#region 流程控制Helper

function _MakeProcessState()
    return {
        result = nil,       -- 处理中止时返回最上层的值
        stop = false,       -- 是否中止
        skipChildren = {},  -- 在该集合中的节点的孩子不再被处理
    }
end

local _processControlInterfaceTemplate = {
    Stop = function(self, result)  
        self.state.result = result 
        self.state.stop = true 
    end,

    SkipSiblings = function(self)
        if self.node:GetParent() then 
            self.state.skipChildren[self.node:GetParent()] = true 
        end
    end,

    SkipChildren = function(self) 
        self.state.skipChildren[self.node] = true  
    end
}

function _MakeProcessControlInterface(processState, nodeBeingProcessed)
    local control = {
        node = nodeBeingProcessed,
        state = processState
    }
    setmetatable(control, {__index = _processControlInterfaceTemplate})
    return control
end

--#endregion
-----------------------------------------------------------------------------

---@class TreeProcessControl
---@field Stop          fun(self, result)       中止整个处理流程，并使整个处理流程返回 result
---@field SkipSiblings  fun(self)               不再处理当前节点的其他兄弟节点
---@field SkipChildren  fun(self)               不处理当前节点的子节点(从下到上处理不适用，处理到一个节点时其子节点必定已完成处理)

---从下到上处理每一个节点，处理每个节点都会产生一个数据，处理父节点时可以访问各个子节点处理得出的数据
---ProcessBottomUp返回调用节点处理得出的数据（或强制中止时传入的result）
---node                : 当前正在处理的节点
---data                : 当前正在处理节点的数据 (即node.data)
---resultFromChildren  : 处理各个子节点得到的数据，即 resultFromChildre[childNode] = resultFromChild
---control             : 控制对象，用于控制处理过程，见 TreeProcessControl
---@param processFunc       fun(node:TreeNode, data:any, resultFromChildren:table<TreeNode, any>, control:TreeProcessControl):any
---@param __internal_state  nil 递归参数，外部禁用
function TreeNode:ProcessBottomUp(processFunc, __internal_state)

    -- 对最外层递归的初始化和特殊处理
    local outermost = (__internal_state == nil)
    if outermost then
        __internal_state = _MakeProcessState()
    end
    local function retval() return outermost and __internal_state.result or nil end

    -- 先处理所有子节点，让它们返回结果
    local childrenResults = {}
    for node, data in self:IterateChildren() do
        childrenResults[node] = node:ProcessBottomUp(processFunc, __internal_state)

        -- 调用过processFunc，处理流程可能变化:
        -- 不再处理本节点的其他子节点？跳过然后处理本节点
        if __internal_state.skipChildren[self] then break end
        -- 处理中止？返回中止结果
        if __internal_state.stop then return retval() end
    end

    -- 处理本节点
    local result = processFunc(self, self.data, childrenResults, _MakeProcessControlInterface(__internal_state, self))

    -- 调用过processFunc，处理流程可能变化:
    -- 处理中止？返回中止结果
    if __internal_state.stop then return retval() end
    -- 否则返回节点处理结果
    return result
end

---从上到下处理每一个节点，处理每个节点都会产生一个数据，处理子节点时可以访问父节点处理得出的数据
---ProcessTopDown被强制中止将返回传入的result，否则没有返回值
---node                : 当前正在处理的节点
---data                : 当前正在处理节点的数据 (即node.data)
---resultFromParent    : 父节点处理得出的数据
---control             : 控制对象，用于控制处理过程，见 TreeProcessControl
---@param processFunc       fun(node:TreeNode, data:any, resultFromParent:any, control:TreeProcessControl):any
---@param __parent_result   nil 递归参数，外部禁用
---@param __internal_state  nil 递归参数，外部禁用
function TreeNode:ProcessTopDown(processFunc, __parent_result, __internal_state)

    -- 对最外层递归的初始化和特殊处理
    local outermost = (__internal_state == nil)
    if outermost then
        __internal_state = _MakeProcessState()
    end
    local function retval() return outermost and __internal_state.result or nil end

    -- 处理自身
    local result = processFunc(self, self.data, __parent_result, _MakeProcessControlInterface(__internal_state, self))

    -- 调用过processFunc，处理流程可能变化:
    -- 不再处理子节点或中止？直接返回
    if __internal_state.stop or __internal_state.skipChildren[self] == true then return retval() end

    -- 处理子节点
    for node, data in self:IterateChildren() do
        node:ProcessTopDown(processFunc, result, __internal_state)
        -- 调用过processFunc，处理流程可能变化:
        -- 中止？直接返回
        if __internal_state.stop or __internal_state.skipChildren[self] == true then return retval() end
    end

    return retval()
end

--#endregion
-----------------------------------------------------------------------------

return TreeNode