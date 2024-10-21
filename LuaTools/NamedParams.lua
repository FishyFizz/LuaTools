local BiMap = require "LuaTools.BiMap"
local Table = require "LuaTools.Table"
local Safe  = require "LuaTools.Safe"
local NamedParams = {} ---@class FishyLibs_NamedParams


---@param paramDefTable string[]
function NamedParams.CreateNamedParamFunction(fun, paramDefTable)
    local argc = #paramDefTable
    ---@param paramTable table<string, any>
    return function(paramTable)
        if paramTable == nil then paramTable = {} end
        if paramTable.varargs == nil then paramTable.varargs = {} end
        local paramPack = {}
        for pos = 1, argc do
            local paramName = paramDefTable[pos]
            paramPack[pos] = paramTable[paramName]
        end
        
        for vaidx = 1, #paramTable.varargs do
            paramPack[argc + vaidx] = paramTable.varargs[vaidx] 
        end
        local totalArgs = argc + #paramTable.varargs
        return fun(table.unpack(paramPack, 1, totalArgs))
    end
end

return NamedParams