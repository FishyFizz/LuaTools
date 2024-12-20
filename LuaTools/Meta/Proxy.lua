local Meta = require "LuaTools.Meta.Meta"
local Proxy = {}

Proxy.Handled  = {__fake_constant = true}
Proxy.Proceed = {__fake_constant = true}

function Proxy.Override(data)
    return {__proxy_override = true, data = data}
end

function Proxy.DefaultProcessor()
    return Proxy.Proceed
end

function Proxy.Create(target, onRead, onWrite)
    local obj = {}
    local mt = getmetatable(target) and Meta.MakeForwardedMetatable(getmetatable(target)) or {}

    -- proxy被回收不应该引起target占有的资源被释放，所以__close和__gc必须置空
    mt.__close = nil
    mt.__gc = nil

    onRead = onRead or Proxy.DefaultProcessor
    onWrite = onWrite or Proxy.DefaultProcessor

    mt.__index = function(_, key)
        local result = onRead(target, key)

        if result == Proxy.Handled then
            return
        elseif result == Proxy.Proceed then
            return target[key]
        elseif type(result) == "table" and result.__proxy_override == true then
            return result.data
        else
            assert(false, "Proxy handler did not return a valid result.")
        end
    end

    mt.__newindex = function(_, key, value)
        local result = onWrite(target, key, value)
        if result == Proxy.Handled then
            return
        elseif result == Proxy.Proceed then
            target[key] = value
        elseif type(result) == "table" and result.__proxy_override == true then
            target[key] = result.data
        else
            assert(false, "Proxy handler did not return a valid result.")
        end
    end

    mt.__pairs = function()
        local baseIterator, initState, initKey = pairs(target)
        local function iterator(state, prevKey)
            local key = baseIterator(state, prevKey)
            if key ~= nil then
                return key, obj[key]  --不能直接返回pairs(target)，因为数据要从proxy读取，确保onRead触发
            else
                return nil
            end
        end
        return iterator, initState, initKey
    end

    setmetatable(obj, mt)

    return obj
end

return Proxy