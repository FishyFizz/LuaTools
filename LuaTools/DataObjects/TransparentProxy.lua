local TransparentProxy = {}

function TransparentProxy.CreateOn(target)
    local obj = {}
    local mt = {}
    setmetatable(obj, mt)

    function mt:__index(key)

    end

    function mt:__newindex(key, value)

    end

end








return TransparentProxy