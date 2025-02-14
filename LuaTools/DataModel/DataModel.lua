local ComputedObject = require "LuaTools.DataObjects.ComputedObject"
local TreeNode       = require "LuaTools.Graph.TreeNode"
local Safe           = require "LuaTools.Safe"
local MultiMap       = require "LuaTools.MultiMap"
local Table          = require "LuaTools.Table"
local DataModelObject = {} ---@class DataModelObject

function DataModelObject.Create()
    local obj = {} ---@class DataModelObject
    setmetatable(obj, {__index = DataModelObject})
    obj:Init()
    return obj
end

function DataModelObject:Init()
    self.__dataModelObject = true
    self.fields = {} ---@type table<any, ComputedObject>

    self.dependencyTree = {}
    self.invalidateMap = MultiMap.Create()
    self.pathMap = {}
    self.objectMap = {}

    setmetatable(self.invalidateMap, {__mode = "k"})
    setmetatable(self.pathMap, {__mode = "k"})
    setmetatable(self.objectMap, {__mode = "kv"})
end

function DataModelObject:Set(key, value)
    if self.fields[key] then
        self.fields[key]:Set(value)
        
        local node = self.dependencyTree[key]
        local invalidatedNodes = self.invalidateMap:Get(key, nil)
        for invNode in pairs(invalidatedNodes) do
            local path = self.pathMap[invNode]

            local invObject = self
            for _, key in ipairs(path) do
                if (not invObject.__dataModelObject) or (not invObject.fields[key]) then
                    invObject = nil
                    break
                end
                invObject = invObject.fields[key]:Get()
            end

            if invObject then
                invObject:Invalidate()
            end
        end
    else
        self.fields[key] = ComputedObject.CreateWithData(value)
    end
end

function DataModelObject:InvalidateByPath(fullPath)

end

function DataModelObject:Get(key)
    if self.fields[key] then
        return self.fields[key]:Get()
    end
end

function DataModelObject:_EnsureDependencyTreeNodeExist(fullPath)
    local tmp = Safe.SafeGetter(self.dependencyTree, fullPath)
    if tmp == nil then
        local node = {}
        Safe.SafeSetter(self.dependencyTree, fullPath, node, true)
        self.pathMap[node] = fullPath
        return node
    else
        return tmp
    end
end

function DataModelObject:AddInvalidateRule(invalidates, invalidated)
    local invalidatesPath = Safe.ExpandAbbrevPathTable(invalidates)
    local invalidatedPath = Safe.ExpandAbbrevPathTable(invalidated)

    local invalidatesNode = self:_EnsureDependencyTreeNodeExist(invalidatesPath)
    local invalidatedNode = self:_EnsureDependencyTreeNodeExist(invalidatedPath)

    self.invalidateMap:Add(invalidatesNode, invalidatedNode)
end

