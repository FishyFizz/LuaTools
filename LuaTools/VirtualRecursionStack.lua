local Meta = require "LuaTools.Meta"
---@class VirtualRecursionStack
local VirtualRecursionStack = {}

function VirtualRecursionStack.New()
    ---@class VirtualRecursionStack
    local obj = {}
    setmetatable(obj, {__index = VirtualRecursionStack})
    obj:_Init()

    return obj
end

function VirtualRecursionStack:_Init()
    self.stack = {}

    Meta.IndexCombine(self, 
        function(_, localKey)
            if self.stack[#self.stack] == nil then return nil end
            return self.stack[#self.stack][localKey]
        end, 
        false)
        
    getmetatable(self).__newindex = function(_, localKey, value)
        if self.stack[#self.stack] == nil then return end
        self.stack[#self.stack][localKey] = value
    end
end

function VirtualRecursionStack:Enter()
    self.stack[#self.stack+1] = {}
end

function VirtualRecursionStack:Leave()
    self.stack[#self.stack] = nil
end

function VirtualRecursionStack:Depth()
    return #self.stack
end

return VirtualRecursionStack