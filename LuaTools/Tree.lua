local Set = require "LuaTools.Set"
local Filter = require "LuaTools.Filter"
local Default= require "LuaTools.Default"
local Tree = {} ---@class FishyLibs_Tree

---@alias SubTreeSortingMethod nil | string | fun(key1, key2):boolean
--- "ipairs": 遍历树的时候按ipairs枚举Tree.children中的各个子树, 首先被枚举的被认为是左子树, 最后被枚举的被认为是右子树
--- "pairs" : 遍历树的时候按pairs枚举Tree.children中的各个子树...
--- function: Tree.children中各个子树的key会被传入该小于比较函数进行排序, 结果从小到大为左子树到右子树
--- nil     : 使用内置 < 运算符对key排序

Tree.SortMethod = {
    IPAIRS = "ipairs",
    PAIRS = "pairs",
    LESS = "less",
}

---@return Tree
function Tree.Create()
    ---@class Tree
    ---@field data any
    ---@field parent Tree | nil
    ---@field sortMethod SubTreeSortingMethod
    local obj = {
        parent = nil,
        children = {}, ---@type table<any, Tree>
        sortMethod = Tree.SortMethod.IPAIRS,
        data = nil,
    }

    ---@vararg any keys
    ---@return Tree|nil
    function obj:GetNode(...)
        local path = {...}
        local node = self
        for _, key in ipairs(path) do
            node = node.children[key]
            if node == nil then return end
        end
        return node
    end

    ---@vararg any keys
    ---@return any
    function obj:GetData(...)
        local node = self:GetNode(...)
        return node and node.data or nil
    end

    return obj
end

local _DefaultTreeTemplate = Tree.Create()

---@alias TreeDefList any[] 数组第一项为树节点数据, 第二项开始是各个子树的TreeDefList

---@class IncompleteTree
---@field data any
---@field children table<any, IncompleteTree> | nil
---@field sortMethod nil | SubTreeSortingMethod

---@param list IncompleteTree
---@return Tree
function Tree.CreateByIncompleteData(list)

    ---虽然list是IncompleteTree而不是Tree, 但是因为我们遍历每个节点执行traverseFunc的时候都补齐了
    ---TraverseParentFirst所需要的字段, 所以可以直接用这个
    ---@diagnostic disable-next-line: param-type-mismatch
    Tree.TraverseParentFirst(list,
        ---@param parent Tree
        function(node, parent)
            if parent ~= nil then
                node.parent = parent
                node.sortMethod = node.sortMethod and node.sortMethod or parent.sortMethod
                Default.FillDefault(node, _DefaultTreeTemplate)
            end
            Default.FillDefault(node, _DefaultTreeTemplate)
            return node
        end
    )
    ---@diagnostic disable-next-line: return-type-mismatch
    return list
end

---@class SubTreeInfo
---@field key any
---@field tree Tree

---@param tree Tree
---@return SubTreeInfo[]
function Tree.GetSortedSubTreeInfo(tree)
    if type(tree.children) ~= "table" then return {} end

    -- 使用ipairs顺序:
    if tree.sortMethod == Tree.SortMethod.IPAIRS then
        local result = {}
        for k, subTree in ipairs(tree.children) do
            result[k] = {key = k, tree = subTree}
        end
        return result
    end

    -- 不使用ipairs顺序，先用pairs将子表枚举出来
    local result = {} ---@type SubTreeInfo[]
    for k, subTree in pairs(tree.children) do
        table.insert(result, {key = k, tree = subTree})
    end
    -- 使用pairs顺序，直接返回
    if tree.sortMethod == Tree.SortMethod.PAIRS then return result end

    local less
    if type(tree.sortMethod) == "function" then
        ---@diagnostic disable-next-line: cast-local-type
        less = tree.sortMethod
    elseif tree.sortMethod == "less" then 
        less = function(a, b) return a < b end
    end

    -- 排序
    ---@diagnostic disable-next-line: param-type-mismatch
    table.sort(result, function(a, b)
        ---@diagnostic disable-next-line: need-check-nil
        return less(a.key, b.key)
    end)

    return result
end

---@param treeNode Tree
---@param traverseFunc fun(treeNode:Tree, dataFromParent:any): dataToChild:any, bSkipNode:boolean|nil, bStopTraversal:boolean|nil bSkipNode: 跳过该子树的遍历, bStopTraversal: 结束整个遍历过程
---@return boolean bStopTraversal
function Tree.TraverseParentFirst(treeNode, traverseFunc, __dataFromParent)
    local dataToChild, bSkipNode, bStopTraversal = traverseFunc(treeNode, __dataFromParent)
    if bStopTraversal then return true end
    if bSkipNode then return false end
    local allSubTreeInfo = Tree.GetSortedSubTreeInfo(treeNode)
    for _, subTreeInfo in ipairs(allSubTreeInfo) do
        local bStopTraversal = Tree.TraverseParentFirst(subTreeInfo.tree, traverseFunc, dataToChild)
        if bStopTraversal then return true end
    end
    return false
end

---@class SubTreeTraverseData
---@field subTreeKey any
---@field data any

---@param treeNode Tree
---@param traverseFunc fun(treeNode:Tree, dataFromChildren:SubTreeTraverseData[]): dataToParent:any, bSkipBrothers:boolean|nil, bStopTraversal: boolean|nil bSkipBrothers: 跳过当前节点之后的兄弟节点遍历, bStopTraversal: 结束整个遍历过程
---@return any data, boolean|nil bSkipBrothers, boolean|nil bStopTraversal
function Tree.TraverseChildrenFirst(treeNode, traverseFunc)
    local allSubTreeInfo = Tree.GetSortedSubTreeInfo(treeNode)
    local dataFromChildren = {} ---@type SubTreeTraverseData[]
    for _, subTreeInfo in ipairs(allSubTreeInfo) do
        local data, bSkipBrothers, bStopTraversal = Tree.TraverseChildrenFirst(subTreeInfo.tree, traverseFunc)
        table.insert(dataFromChildren, {subTreeKey = subTreeInfo.key, data = data})

        if bStopTraversal then return nil, true, true end
        if bSkipBrothers then break end
    end
    return traverseFunc(treeNode, dataFromChildren)
end

---@param treeNode Tree
---@param traverseFunc fun(treeNode): bStopTraversal: boolean|nil
---@return Tree|nil lastVisitedNode
function Tree.TraverseParents(treeNode, traverseFunc)
    local node = treeNode.parent
    while true do
        if node == nil then return end
        if traverseFunc(node) then return node end
        node = node.parent
    end
end

---@param treeNode Tree
---@param predicate SimplePredicate
---@return Tree|nil foundNode
function Tree.FindFirstMatchingParent(treeNode, predicate)
    return Tree.TraverseParents(treeNode, 
                function(node)
                    local bStopTraversal = Filter.MatchSimplePredicate(node, predicate)
                    return bStopTraversal
                end
            )
end

return Tree