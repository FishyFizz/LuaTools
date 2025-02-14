local Trace = {}

local function SplitStr(str, delim)
    local cachedPath = {}
    local begin = 1

    local delimPos = string.find(str, delim, begin, true)
    while delimPos do
        table.insert(cachedPath, string.sub(str, begin, delimPos-1))
        begin = delimPos + 1
        delimPos = string.find(str, delim, begin, true)
    end
    table.insert(cachedPath, string.sub(str, begin, #str))
    return cachedPath
end

local function StringTrim(str)
    return string.gmatch(str, "%s*(.*)%s*")()
end

Trace.traceTypeInfo = {
    {
        name = "func",
        pattern = "(.+%.lua):([0-9]+): in function '(.*)'", 
        captures = {
            [1] = "fileName",
            [2] = "fileLine",
            [3] = "funcName",
        },
    },

    {
        name = "lambda",
        pattern = "(.+%.lua):([0-9]+): in function <(.+%.lua):(.*)>",
        captures = {
            [1] = "fileName",
            [2] = "fileLine",
            [3] = "funcFile",
            [4] = "funcBeginLine"
        }
    },
    
    {
        name = "metamethod",
        pattern = "(.+%.lua):([0-9]+): in metamethod '(.*)'",
        captures = {
            [1] = "fileName",
            [2] = "fileLine",
            [3] = "metamethod"
        }
    },

    {
        name = "cfunc",
        pattern = "%[C%]: in function '(.*)'",
        captures = {
            [1] = "funcName"
        }
    },

    {
        name = "cunknown",
        pattern = "%[C%]: in ?",
        captures = {}
    },

    {
        name = "tailcall",
        pattern = "%(...tail calls...%)",
        captures = {}
    },

    
    {
        name = "chunk",
        pattern = "(.+%.lua):([0-9]+): in (.*) chunk",
        captures = {
            [1] = "fileName",
            [2] = "fileLine",
            [3] = "chunkName",
        }
    },

    {
        name = "other",
        pattern = "(.*)",
        captures = {
            [1] = "info"
        }
    },
}


local function PostprocessResult(lineResult)
    local function GetLastPart(str, delim)
        local tmp = SplitStr(str, delim)
        return tmp[#tmp]
    end

    local function GetShortFileName(longFileName)
        local tmp = GetLastPart(longFileName, "\\")
        return GetLastPart(tmp, "/")
    end

    if lineResult.fileName then
        lineResult.shortFileName = GetShortFileName(lineResult.fileName)
    end

    if lineResult.funcFile then
        lineResult.shortFuncFile = GetShortFileName(lineResult.funcFile)
    end

    if lineResult.funcName then
        lineResult.shortFuncName = GetLastPart(lineResult.funcName, ".")
    end

    -- 特殊处理
    if lineResult.type == "cunknown" then
        lineResult.funcName = "(cunknown)"
        lineResult.shortFuncName = "(cunknown)"
    elseif lineResult.type == "tailcall" then
        lineResult.funcName = "(tailcall)"
        lineResult.shortFuncName = "(tailcall))"
    elseif lineResult.type == "lambda" then
        lineResult.funcName = "<"..lineResult.funcFile..":"..tostring(lineResult.funcBeginLine)..">"
        lineResult.shortFuncName = "<"..lineResult.shortFuncFile..":"..(lineResult.funcBeginLine)..">"
    end

    if lineResult.fileLine then
        lineResult.fileLineStr = tostring(lineResult.fileLine)
    end

    return lineResult
end

function Trace.ProcessTraceLine(str)
    if string.find(str, "stack traceback:") ~= nil then return nil end

    str = StringTrim(str)
    for _, traceType in pairs(Trace.traceTypeInfo) do
        local captures = {string.gmatch(str, traceType.pattern)()}
        if #captures ~= 0 then
            local lineResult = {type = traceType.name}
            for captureIdx, captureName in ipairs(traceType.captures) do
                lineResult[captureName] = captures[captureIdx]
            end
            return PostprocessResult(lineResult)
        end
    end
end

function Trace.ProcessTraceInfo(str)
    local lines = SplitStr(str, "\n")
    local result = {}

    for _, line in ipairs(lines) do
        local lineResult = Trace.ProcessTraceLine(line)
        if lineResult then
            table.insert(result, lineResult)
        end
    end

    return result
end

function Trace.Trace(level)
    level = level or 0
    -- [+0]: Trace.Trace
    -- [+1]: Caller
    return Trace.ProcessTraceInfo(debug.traceback(nil, nil, level+1))
end

---Formatting options:
--- %Fl = full file name                
--- %Fs = short file name               
--- %fl = long function/lambda name    
--- %fs = short function/lambda name        
--- %L  = line number
---@param fmt string?
function Trace.Format(traceResult, fmt, maxDepth, ignoreTypes)
    fmt = fmt or "%fl %Fs %L"
    maxDepth = maxDepth or 9999
    ignoreTypes = ignoreTypes or {}

    local replaceMap = {
        ["%%Fl"] = "fileName",
        ["%%Fs"] = "shortFileName",
        ["%%fl"] = "funcName",
        ["%%fs"] = "shortFuncName",
        ["%%L"]  = "fileLineStr",
    }

    local result = ""
    local cnt = 0
    for _, info in ipairs(traceResult) do

        if ignoreTypes[info.type] == nil then
            local line = fmt
            for pattern, field in pairs(replaceMap) do
                line = string.gsub(line, pattern, info[field] or "")
            end

            if cnt > 0 then result = result .. "\n" end
            result = result .. line
            cnt = cnt + 1
        end
        
        if cnt >= maxDepth then break end
    end

    return result
end

return Trace