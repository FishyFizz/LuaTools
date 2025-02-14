local OverlapGraph      = require "LuaTools.Graph.OverlapGraph.OverlapGraph"
local OverlapGraphNode  = require "LuaTools.Graph.OverlapGraph.OverlapGraphNode"

Graph = OverlapGraph.Create()

Nodes = {} ---@type OverlapGraphNode[]
for i = 1, 10 do
    Nodes[i] = OverlapGraphNode.Create()
    Nodes[i]._dbgName = i
end

function Connect(from, key, to)
    Nodes[from]:AddConnection(key, Nodes[to])
end

Connect(1, "U", 4)
Connect(4, "L", 1)

Connect(1, "L", 2)
Connect(2, "U", 1)

Connect(1, "R", 3)
Connect(3, "U", 1)

Connect(5, "R", 6)
Connect(6, "U", 5)

Connect(6, "R", 7)
Connect(7, "U", 6)

Connect(10, "L", 9)
Connect(9, "U", 10)

Connect(9, "R", 8)
Connect(8, "U", 9)

Graph:Place(Nodes[1])
Graph:Place(Nodes[5], Graph:GetMapped(Nodes[3]))
Graph:Place(Nodes[10], Graph:GetMapped(Nodes[7]))

local node = Graph:GetMapped(Nodes[3])
print(Graph:GetMapped(Nodes[10]) == node:GetPeer("R"):GetPeer("R"))

Graph:Remove(Nodes[6])
print(Graph:GetMapped(Nodes[10]) == node:GetPeer("R"):GetPeer("R"))