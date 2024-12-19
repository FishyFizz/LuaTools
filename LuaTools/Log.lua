local Log = {} ---@class LuaTools_Log
local LogContext = {} ---@class LogContext

---@alias LogOutputImpl fun(outStr:string)

---@enum ELogSeverity
Log.ELogSeverity = {
    Info        = 1,
    Warning     = 2,
    Error       = 3,
    Fatal       = 4,
}

---@class LogScopeData 
---@field severity      ELogSeverity
---@field verbosity     integer
---@field scopeStr      string
---@field outputDone    boolean

function Log.ArgsToString(...)
    local logText = ""
    local logArgs = {...}

    for _, item in ipairs(logArgs) do
        logText = logText..tostring(item)
    end

    return logText
end

function Log.Indent(str, n, bMultiline)
    n = n or 0
    bMultiline = bMultiline == nil and true or bMultiline

    str = string.rep("    ", n) .. str
    if bMultiline then
        str = string.gsub(str, "\n", "\n    ")
    end
    return str
end

function Log.StrSplit(str, delim)
    local result = {}
    local begin = 1

    local delimPos = string.find(str, delim, begin, true)
    while delimPos do
        table.insert(result, string.sub(str, begin, delimPos-1))
        begin = delimPos + 1
        delimPos = string.find(str, delim, begin, true)
    end
    table.insert(result, string.sub(str, begin, #str))
    return result
end

---@param prefix            string?
---@param infoImpl          LogOutputImpl
---@param optWarningImpl    nil|LogOutputImpl
---@param optErrorImpl      nil|LogOutputImpl
---@param optFatalImpl      nil|LogOutputImpl
---@return LogContext
function Log.CreateLogContext(prefix, infoImpl, optWarningImpl, optErrorImpl, optFatalImpl)
    ---@type LogContext
    local obj = {}
    setmetatable(obj, {__index = LogContext})
    obj:Init(prefix, {infoImpl, optWarningImpl, optErrorImpl, optFatalImpl})
    return obj
end

---@param prefix                string?
---@param logSeverityImplTable  LogOutputImpl[]
function LogContext:Init(prefix, logSeverityImplTable)
    assert(logSeverityImplTable[1], "Log implementation for ELogSeverity.Info MUST be provided.")

    ---@type table<ELogSeverity, LogOutputImpl> 
    self.logSeverityImpl    = logSeverityImplTable      -- 不同严重程度的日志输出实现
    self.prefix             = prefix or ""              -- 日志前缀，代表代码模块等
    self.maxVerbosity       = math.maxinteger           -- 过滤，输出日志的最高 Verbosity (含)
    self.minSeverity        = Log.ELogSeverity.Info     -- 过滤，输出日志的最低 Severity (含)
    self.shouldSplitLines   = true                      -- 日志中的 \n 是否要被替换成多次输出单行日志

    self.indentDepth        = 0                         -- 当前日志的输出缩进层数
    self.logScopes          = {}                        ---@type LogScopeData[]
end

---@param  severity ELogSeverity
---@return LogOutputImpl 
function LogContext:FindImplOfSeverity(severity)
    -- 不一定每个严重等级都提供了输出实现
    -- 向下查找到第一个可用的

    -- 例：只提供了 Info 和 Error 级别的实现
    -- 尝试输出 Fatal 日志会调用 Error实现
    -- 尝试输出 Warning 日志会调用 Info 实现

    for i = severity, 1, -1 do
        if self.logSeverityImpl[i] ~= nil then
            return self.logSeverityImpl[i]
        end
    end
    return self.logSeverityImpl[1]
end

---@param severity  ELogSeverity?
---@param verbosity integer?
---@param ... any
function LogContext:_DoLog(severity, verbosity, ...)
    -- 过滤条件检查
    severity = severity or Log.ELogSeverity.Info
    verbosity = verbosity or 0
    if severity < self.minSeverity then return end
    if verbosity > self.maxVerbosity then return end

    local logImpl   = self:FindImplOfSeverity(severity)
    local logString = Log.ArgsToString(...)
    local logLines  = self.shouldSplitLines and Log.StrSplit(logString, "\n") or {logString}

    for i, line in ipairs(logLines) do
        if i < #logLines then
            logImpl(self.prefix.." "..Log.Indent(line, self.indentDepth).." (...)") -- 只要不是最后一行就在行尾添加 (...) 提示这是接续的日志
        else
            logImpl(self.prefix.." "..Log.Indent(line, self.indentDepth))
        end
    end
end

function LogContext:Log(severity, verbosity, ...)
    self:OutputSavedScopes(severity, verbosity)
    self:_DoLog(severity, verbosity, ...)
end

function LogContext:OutputSavedScopes(severity, verbosity)
    -- 过滤条件检查
    severity = severity or Log.ELogSeverity.Info
    verbosity = verbosity or 0
    if severity < self.minSeverity then return end
    if verbosity > self.maxVerbosity then return end

    -- 找到要从哪里开始输出Scope信息
    local lastOutputDoneScope = 0
    for i = #self.logScopes, 1, -1 do
        local scopeInfo = self.logScopes[i]
        if scopeInfo.outputDone then
            lastOutputDoneScope = i
            break
        end
    end

    -- 输出Scope信息
    for i = lastOutputDoneScope + 1, #self.logScopes do
        local scopeInfo = self.logScopes[i]
        -- 由于该Scope内出现高优先级日志输出，所以输出等级覆盖为这个等级，这样也确保Scope结束信息会被输出
        scopeInfo.severity = severity
        scopeInfo.verbosity = verbosity
        self:_DoLog(severity, verbosity, "[LOG SCOPE] ", scopeInfo.scopeStr)
        scopeInfo.outputDone = true
        self.indentDepth = self.indentDepth + 1
    end
end

function LogContext:EnterScope(severity, verbosity, ...)

    -- 不管是否满足过滤条件都要进入Scope，如果Scope内产生了满足过滤条件的日志，将把之前的Scope全都重新输出
    local scopeStr
    if #{...} == 0 then
        scopeStr = ""
    else
        scopeStr = Log.ArgsToString(...)
    end

    local scopeInfo = {
        severity    = severity,
        verbosity   = verbosity,
        scopeStr    = scopeStr,
        outputDone  = false,
    }

    table.insert(self.logScopes, scopeInfo)

    local handle = {
        ExitScope = function()
            self:ExitScope()
        end,
    }
    -- setmetatable(handle, {__close = handle.Exit}) Lua5.4 以后将返回值标记为<close>就不用手动Exit了

    -- 过滤条件检查
    severity = severity or Log.ELogSeverity.Info
    verbosity = verbosity or 0
    if severity < self.minSeverity then return end
    if verbosity > self.maxVerbosity then return end
    
    -- 满足过滤条件就立即输出
    self:OutputSavedScopes(severity, verbosity)

    return handle
end

function LogContext:ExitScope()
    if #self.logScopes == 0 then return end

    local scopeInfo = table.remove(self.logScopes, #self.logScopes) ---@type LogScopeData
    if scopeInfo.outputDone then -- 没有输出过进入Scope信息，那就也不要输出退出信息，确保配对
        self.indentDepth = self.indentDepth - 1
        self:Log(scopeInfo.severity, scopeInfo.verbosity, "[LOG EXIT] ", scopeInfo.scopeStr)
    end
end

function LogContext:LogCurrentScopes(severity, verbosity)
    -- 过滤条件检查
    severity = severity or Log.ELogSeverity.Info
    verbosity = verbosity or 0
    if severity < self.minSeverity then return end
    if verbosity > self.maxVerbosity then return end

    self:Log(severity, verbosity, "[SHOWING LOG SCOPES]")
    for idx, scopeInfo in ipairs(self.logScopes) do
        self:Log(severity, verbosity, "|\t "..tostring(idx).."."..(scopeInfo.scopeStr ~= "" and scopeInfo.scopeStr or "(anonymous scope)"))
    end
    self:Log(severity, verbosity, "[END LOG SCOPES]")
end

-----------------------------------------------------------------------
--#region 不需要填写 severity 和 verbosity 的快捷方式

function LogContext:Info(...)
    self:Log(Log.ELogSeverity.Info, 1, ...)
end

function LogContext:Warning(...)
    self:Log(Log.ELogSeverity.Warning, 1, ...)
end

function LogContext:Error(...)
    self:Log(Log.ELogSeverity.Error, 1, ...)
end

function LogContext:Fatal(...)
    self:Log(Log.ELogSeverity.Fatal, 1, ...)
end

function LogContext:InfoScope(...)
    self:EnterScope(Log.ELogSeverity.Info, 1, ...)
end

function LogContext:WarningScope(...)
    self:EnterScope(Log.ELogSeverity.Warning, 1, ...)
end

function LogContext:ErrorScope(...)
    self:EnterScope(Log.ELogSeverity.Error, 1, ...)
end

function LogContext:FatalScope(...)
    self:EnterScope(Log.ELogSeverity.Fatal, 1, ...)
end

function LogContext:MakeLogFunc(severity, verbosity)
    return function(...)
        self:Log(severity, verbosity, ...)
    end
end

function LogContext:MakeScopeFunc(severity, verbosity)
    return function (...)
        self:EnterScope(severity, verbosity, ...)
    end
end

--#endregion
-----------------------------------------------------------------------


return Log