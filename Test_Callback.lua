local Callback = require "LuaTools.Callback"
local arg       = Callback.arg
local vararg    = Callback.vararg

local function Test(a, b, c, d)
    if d == 0 then assert(false) end
    print(a, b, c, d)
    return a, b, c, d
end

local Callback1 = Callback.MakeCallback(Test, 1, 2, 3, 4) 
Callback1()
print()

local Callback2 = Callback.MakeCallback(Test, 1, arg(1, 2), arg(2, 3) , 4)
Callback2()
Callback2(222, 333)
print()

local Callback3 = Callback.MakeCallback(Test, vararg(1, 1, 2, 3, 4))
Callback3()
Callback3(111, nil, 333, nil)
print()

local Callback4 = Callback.MakeCallback(Test, arg(4, 1), arg(3, 2), arg(2, 3), arg(1, 4))
Callback4()
Callback4(1, 2, 3, 4)
print()

local Callback5 = Callback.MakeSimple(Test, 1, 2)
Callback5(333, 444)
print()

local Protected = Callback.MakeProtected(Callback5)
local a, b, c, d = Protected(0, 0)
print(a, b, c, d)
print()

local a, b, c, d = Protected(333, 444)
print(a, b, c, d)