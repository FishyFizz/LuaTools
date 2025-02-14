local Functional = {} ---@class FishyLibs_Functional

function Functional.And(fA, fB)
    return function(...)
        return fA(...) and fB(...)
    end
end

function Functional.Equal(value)
    return function(x)
        return x == value
    end
end

function Functional.Not(f)
    return function(...)
        return not f(...)
    end
end

function Functional.Or(fA, fB)
    return function(...)
        return fA(...) or fB(...)
    end
end

--- f'(x) = fComb(fA(x), fB(x))
function Functional.Comb(fA, fB, fComb)
    return function(...)
        return fComb(fA(...), fB(...))
    end
end

--- f'(x) = fThen(fFirst(x))
function Functional.Chain(fFirst, fThen)
    return function(...)
        return fThen(fFirst(...))
    end
end


function Functional.Get(key)
    return function(obj)
        return obj[key]
    end
end

function Functional.If(fCond, optfDo, optfElse)
    return function(...)
        if fCond(...) then
            if optfDo then return optfDo(...) end
        else
            if optfElse then return opoptfElse(...) end
        end
    end
end

function Functional.Call(f, ...)
    local args = {...}
    return function()
        return f(table.unpack(args))
    end
end

return Functional