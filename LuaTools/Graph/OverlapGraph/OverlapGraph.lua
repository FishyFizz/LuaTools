local OverlapGraphNode = require("LuaTools.Graph.OverlapGraph.OverlapGraphNode")

local OverlapGraph = {} ---@class OverlapGraph

---@class OverlapGraphInternalNode: OverlapGraphNode
---@field overlapCount integer
---@field _connectionOverlapCount table<any, integer>

local function SetNudge(owner, key, delta)
    if owner[key] == nil then
        owner[key] = delta
    else
        owner[key] = owner[key] + delta
    end
    if owner[key] <= 0 then owner[key] = nil end
end

---@alias OverlapGraphPlaceMap table<OverlapGraphNode, OverlapGraphInternalNode>

function OverlapGraph.Create()
    local obj = {} ---@class OverlapGraph
    setmetatable(obj, {__index = OverlapGraph})
    obj:Init()
    return obj
end

function OverlapGraph:Init()
    self.allNodes = {} ---@type table<OverlapGraphInternalNode, true>
    self.allPlaceMap = {} ---@type OverlapGraphPlaceMap
    setmetatable(self.allPlaceMap, {__mode = "k"})
end

---@param node  OverlapGraphNode
---@return OverlapGraphPlaceMap
function OverlapGraph:_CloneSubgraphIntoInternalGraph(node)
    local connectedNodes = node:GetConnected()
    local clonedNodes = {} ---@type OverlapGraphPlaceMap

    -- 复制所有节点，和原节点一一对应
    for nodeToClone in pairs(connectedNodes) do
        local internal = self:_NewInternalNode()
        internal.overlapCount = 1
        clonedNodes[nodeToClone] = internal
        self.allPlaceMap[nodeToClone] = internal
    end

    -- 在复制的这些节点中重建原节点的连接关系
    for nodeToClone in pairs(connectedNodes) do
        for key, peer in pairs(nodeToClone.connections) do
            clonedNodes[nodeToClone]:AddConnection(key, clonedNodes[peer])
            SetNudge(clonedNodes[nodeToClone]._connectionOverlapCount, key, 1)
        end
    end

    return clonedNodes
end

---@param node  OverlapGraphNode
---@param where OverlapGraphInternalNode?
---@return OverlapGraphPlaceMap
function OverlapGraph:Place(node, where)
    if where == nil then
        return self:_CloneSubgraphIntoInternalGraph(node)
    else
        return self:_Place(node, where)
    end
end

---@return OverlapGraphInternalNode
function OverlapGraph:_NewInternalNode()
    local node = OverlapGraphNode.Create() ---@type OverlapGraphInternalNode
    self.allNodes[node] = true
    node.overlapCount = 0
    node._connectionOverlapCount = {}

    return node
end

---@param node  OverlapGraphNode
---@param where OverlapGraphInternalNode?
---@return OverlapGraphPlaceMap
function OverlapGraph:_Place(node, where)
    local placeMap = {} ---@type OverlapGraphPlaceMap
    placeMap[node] = where
    where.overlapCount = where.overlapCount + 1
    self.allPlaceMap[node] = where

    -- 所有访问的节点
    local visited = {} ---@type table<OverlapGraphNode, true>
    visited[node] = true

    -- 上一轮新增访问的节点
    local lastBatch = {} ---@type table<OverlapGraphNode, true>
    lastBatch[node] = true

    while next(lastBatch) ~= nil do
        -- 这一轮新增访问的节点
        local thisBatch = {} ---@type table<OverlapGraphNode, true>

        -- 遍历上一轮新增访问节点(node)的所有直接相邻节点(key, adjacent)
        for node in pairs(lastBatch) do
            for key, adjacent in pairs(node.connections) do
                -- 这个相邻节点不存在，则在内部创建然后建立关联，然后加入重叠映射
                -- 如果已经存在，则重叠，直接加入重叠映射
                if not visited[adjacent] then
                    thisBatch[adjacent] = true
                    visited[adjacent] = true

                    local internalAdjacent = placeMap[node]:GetPeer(key)
                    if internalAdjacent == nil then
                        internalAdjacent = self:_NewInternalNode()
                        -- 现在不添加连接，之后统一添加 placeMap[node]:AddConnection(key, internalAdjacent)
                    end
                    internalAdjacent.overlapCount = internalAdjacent.overlapCount + 1
                    placeMap[adjacent] = internalAdjacent
                    self.allPlaceMap[adjacent] = internalAdjacent
                end
            end
        end

        ---------------------
        lastBatch = thisBatch
    end

    return placeMap
end

---@param node  OverlapGraphNode
function OverlapGraph:Remove(node)
    local removeNodes = node:GetConnected()

    for node in pairs(removeNodes) do
        local internal = self.allPlaceMap[node]
        self.allPlaceMap[node] = nil

        internal.overlapCount = internal.overlapCount - 1
        if internal.overlapCount == 0 then
            internal:ClearConnections()
            self.allNodes[internal] = nil
        end
    end
end

---@param node  OverlapGraphNode
---@return      OverlapGraphInternalNode
function OverlapGraph:GetMapped(node)
    return self.allPlaceMap[node]
end

return OverlapGraph