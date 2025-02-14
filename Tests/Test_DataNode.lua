---@class DataNode2
local DataNode = {}

function DataNode.Create()
    ---@class DataNode2
    local obj = {}
    setmetatable(obj, {__index = DataNode})
end

function DataNode:Init()
    self.connectionPoints = {}
end


return DataNode