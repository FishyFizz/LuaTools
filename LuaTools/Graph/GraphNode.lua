---@class GraphNode
local GraphNode = {}

---@alias GraphNodeSet table<GraphNode, boolean> GraphNode集合，key是集合的元素，value总是true

---@param set GraphNodeSet
---@return GraphNodeSet
local function CopySet(set)
    local result = {}
    for node, _ in pairs(set) do
        result[node] = true
    end
    return result
end

---@param data any?              节点中包含的数据
---@param prev GraphNode[] | nil 创建新节点后还会创建 prev中各节点->新节点 的边
---@param next GraphNode[] | nil 创建新节点后还会创建 新节点->next中各节点 的边
---@return GraphNode
function GraphNode.New(data, prev, next)
    local obj = {} ---@type GraphNode
    setmetatable(obj, {__index = GraphNode})
    obj:Init(data, prev, next)
    return obj
end

function GraphNode:Init(data, prev, next)
    self.data = data
    self._prev = {}
    self._next = {}

    if prev ~= nil then
        for _, node in pairs(prev) do
            self:AddEdgeFrom(node)
        end
    end

    if next ~= nil then
        for _, node in pairs(next) do
            self:AddEdgeTo(node)
        end
    end

    setmetatable(self._prev, {__mode = {"k"}})
    setmetatable(self._next, {__mode = {"k"}})
end

-------------------------------------------------------------------------
--#region 边操作：添加/删除/检查

---添加边: self -> to
---@param to   GraphNode
function GraphNode:AddEdgeTo(to)
    self._next[to] = true
    to._prev[self] = true
end

---添加边: from -> self
---@param from GraphNode
function GraphNode:AddEdgeFrom(from)
    from:AddEdgeTo(self)
end

---添加边: self <-> other
---@param other GraphNode
function GraphNode:AddEdge(other)
    self:AddEdgeFrom(other)
    self:AddEdgeTo(other)
end

---删除边: self -> to
---@param to   GraphNode
function GraphNode:RemoveEdgeTo(to)
    self._next[to] = nil
    to._prev[self] = nil
end

---删除边: from -> self
---@param from   GraphNode
function GraphNode:RemoveEdgeFrom(from)
    self._prev[from] = nil
    from._next[self] = nil
end

---删除边: self <-> other
---@param other   GraphNode
function GraphNode:RemoveEdge(other)
    self:RemoveEdgeFrom(other)
    self:RemoveEdgeTo(other)
end

---删除所有从本节点触发的边
function GraphNode:RemoveAllEdgeFromThis()
    for node in pairs(self._next) do
        self:RemoveEdgeTo(node)
    end
end

---删除所有指向该节点的边
function GraphNode:RemoveAllEdgeToThis()
    for node in pairs(self._prev) do
        self:RemoveEdgeFrom(node)
    end
end

---删除所有边
function GraphNode:Disconnect()
    self:RemoveAllEdgeFromThis()
    self:RemoveAllEdgeToThis()
end

---检查边是否存在 self -> to
---@param to    GraphNode
function GraphNode:HasEdgeTo(to)
    return self._next[to] == true
end

---检查边是否存在 from -> self
---@param from   GraphNode
function GraphNode:HasEdgeFrom(from)
    return self._prev[from] == true
end

---检查边是否存在 self <-> other
---@param other   GraphNode
function GraphNode:HasBidirEdge(other)
    return (self._prev[other] == true) and (self._next[other] == true)
end

--#endregion
-------------------------------------------------------------------------

-------------------------------------------------------------------------
--#region 边计数（出边/入边/双向边）

---入边计数
function GraphNode:InCount()
    local count = 0
    for _, _ in pairs(self._prev) do
        count = count + 1
    end
    return count
end

---出边计数
function GraphNode:OutCount()
    local count = 0
    for _, _ in pairs(self._next) do
        count = count + 1
    end
    return count
end

---双向边计数
function GraphNode:BidirCount()
    local count = 0
    for other, _ in pairs(self._next) do
        if self._prev[other] == true then
            count = count + 1
        end
    end
    return count
end

--#endregion
-------------------------------------------------------------------------

-------------------------------------------------------------------------
--#region 取直接相邻节点集合

---取prev节点集合
function GraphNode:GetPrev()
    return CopySet(self._prev, 1)
end

---取next节点集合
function GraphNode:GetNext()
    return CopySet(self._next, 1)
end

--#endregion
-------------------------------------------------------------------------

-------------------------------------------------------------------------
--#region 迭代器：用for循环遍历prev/next节点

function GraphNode._MakeNodeSetIterator(nodes)
    ---@type table<GraphNode, any>
    local tmpNodes = CopySet(nodes, 1)

    ---@param curr GraphNode
    local function iterator(state, curr)
        local nextNode = next(tmpNodes, curr)
        return nextNode, nextNode and nextNode.data or nil
    end

    return iterator
end

--- for node, data in graphNode:IteNextNodes() do
function GraphNode:IteNextNodes()
    return self._MakeNodeSetIterator(self._next) ---@type fun(last:GraphNode):GraphNode, any
end

--- for node, data in graphNode:ItePrevNodes() do
function GraphNode:ItePrevNodes()
    return self._MakeNodeSetIterator(self._prev) ---@type fun(last:GraphNode):GraphNode, any
end

--#endregion
-------------------------------------------------------------------------

-------------------------------------------------------------------------
--#region 取所有间接连通节点集合

---@param direction "_prev"|"_next"
---@return GraphNodeSet
function GraphNode:_GetReachableByDirection(direction, bIncludeStartingNode)
    local reachable = {}
    local currBatch = {[self] = true}
    local nextBatch

    bIncludeStartingNode = bIncludeStartingNode or true
    local firstBatch = true

    while next(currBatch) do
        nextBatch = {}

        for reached in pairs(currBatch) do

            -- 将本批次所有节点加入 reached 集合
            if (not bIncludeStartingNode) and (firstBatch == true) then
            else
                reachable[reached] = true
            end

            for next in pairs(reached[direction]) do
                -- 将本批次所有节点的直接相邻节点加入 nextBatch 集合（除非已经访问过）
                nextBatch[next] = reached[next] and nil or true
            end
        end

        -- 重复直到没有新的节点可以继续遍历
        currBatch = nextBatch
    end

    return reachable
end

---获取从本节点开始能到达的所有节点
---@return GraphNodeSet
function GraphNode:GetReachable(bIncludeStartingNode)
    return self:_GetReachableByDirection("_next", bIncludeStartingNode)
end

---获取能到达本节点的所有节点
---@return GraphNodeSet
function GraphNode:GetReachableFrom(bIncludeStartingNode)
    return self:_GetReachableByDirection("_prev", bIncludeStartingNode)
end

---获取所有连通节点
---@return GraphNodeSet
function GraphNode:GetConnected(bIncludeStartingNode)
    local result        = self:GetReachable(bIncludeStartingNode)
    local reachableFrom = self:GetReachableFrom(bIncludeStartingNode)

    ---取交集
    for node, _ in result do
        if reachableFrom[node] == nil then
            result[node] = nil
        end
    end
    return result
end

--#endregion
-------------------------------------------------------------------------

return GraphNode