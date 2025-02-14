local OverlapGraphNode = {} ---@class OverlapGraphNode


function OverlapGraphNode.Create()
    local obj = {} ---@class OverlapGraphNode
    setmetatable(obj, {__index = OverlapGraphNode})
    obj:Init()
    return obj
end

function OverlapGraphNode:Init()
    self.connections = {} ---@type table<any, OverlapGraphNode>
    self._revConnections = {} ---@type table<OverlapGraphNode, any> 来自其他节点的连接 _revConnections[otherNode] = key 代表 otherNode--key-->self
end

function OverlapGraphNode:AddConnection(key, peer)
    self.connections[key] = peer
    self._connectionOverlapCount[key] = 0
    peer._revConnections[self] = key
end

function OverlapGraphNode:RemoveConnection(key, peer)
    self.connections[key] = nil
    peer._revConnections[self] = nil
end

function OverlapGraphNode:ClearConnections()
    for key, peer in pairs(self.connections) do
        self:RemoveConnection(key, peer)
    end
end

function OverlapGraphNode:GetPeer(key)
    return self.connections[key]
end

function OverlapGraphNode:GetConnected()
    -- 所有访问的节点
    local results = {} ---@type table<OverlapGraphNode, true>
    results[self] = true

    -- 上一轮新增的节点
    local lastBatch = {} ---@type table<OverlapGraphNode, true>
    lastBatch[self] = true

    while next(lastBatch) ~= nil do
        -- 这一轮新增的节点
        local thisBatch = {} ---@type table<OverlapGraphNode, true>

        -- 遍历上一轮新增访问节点(node)的所有直接相邻节点(adjacent)
        for node in pairs(lastBatch) do
            for key, adjacent in pairs(node.connections) do
                thisBatch[adjacent] = ((results[adjacent] == nil) and true or nil)
                results[adjacent] = true
            end
        end

        ---------------------
        lastBatch = thisBatch
    end

    return results
end



return OverlapGraphNode