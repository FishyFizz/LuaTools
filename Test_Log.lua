local Log = require "LuaTools.Log"
local Severity = Log.ELogSeverity

local function info(str) print("[INFO]  "..str) end
local function error(str) print("[ERROR] "..str) end
local logCtx = Log.CreateLogContext("[模块前缀]", info, nil, error, nil)

logCtx:Warning                          ("这是一个警告日志，我们没有警告输出实现，所以会使用Info")
logCtx:Fatal                            ("这是一个致命日志，我们没有致命输出实现，所以会使用Error")
print("")
logCtx:Info                             ("这是一个多行日志，会被自动拆分成多行！\n第二行\n第三行")
print("")
logCtx:InfoScope                        ("这是一个日志区间")
logCtx:Info                                 ("输出1")
logCtx:Info                                 ("输出2")
logCtx:InfoScope                            ("这是另一个日志区间")
logCtx:Info                                     ("输出3")
logCtx:ExitScope()                          -- 区间结束
logCtx:ExitScope()                      -- 区间结束
print("")
logCtx.minSeverity = Severity.Error
logCtx:Info                             ("这一行不会被输出，日志门槛为Error")
logCtx:Error                            ("这一行会被输出，日志门槛为Error")
print("")
logCtx:InfoScope                        ("这是Info等级的区间")
logCtx:WarningScope                         ("这是Warning等级的区间")
logCtx:Error                                    ("假设程序产生了错误")
logCtx:Error                                    ("这是一个错误日志")
logCtx:Error                                    ("因为产生了一个满足当前门槛的日志")
logCtx:Error                                    ("所以之前进入的日志区间也会被输出出来，便于追溯错误来源")
logCtx:Error                                    ("这些日志区间的严重等级和详细等级会被这一条日志覆盖，确保能够输出")
logCtx:Error                                    ("调用LogCurrentScopes可以直接显示当前所在的日志区间用于溯源")
logCtx:LogCurrentScopes(Severity.Error)     
logCtx:ExitScope()                          -- 区间结束
logCtx:ExitScope()                      -- 区间结束
logCtx:Error                            ("只要显示过进入日志区间的信息，一定会显示退出区间信息，因为它们的优先级已被提升")
print("")
logCtx:Error                            ("下面的两个日志区间不会产生任何输出")
logCtx:InfoScope                        ("这是Info等级的区间")
logCtx:WarningScope                         ("这是Warning等级的区间")
logCtx:Info                                     ("如果程序没有产生错误")
logCtx:Info                                     ("那么整个区间都不会在日志中输出")
logCtx:ExitScope()                          -- 区间结束
logCtx:ExitScope()                      -- 区间结束
logCtx:Error                            ("没有显示过进入日志区间信息，就不会显示退出区间信息")
