---@class FishyLibs_DataObject
local DataObject = {}

---DataObject调试输出选项
local log = function() end
--local log = function(...) print("[Cache] ", ...) end

function DataObject.Create(optData)
    ---@class DataObject
    local obj = {
        _data = optData,             ---@type any
        _listeners = {},     ---@type table<fun(data)>
        _dbgName = nil,              ---@type string?
        _overrideSetter = nil,       ---@type function?
        _overrideGetter = nil,       ---@type function?
    }

    function obj:Get()
        return self._overrideGetter and self._overrideGetter() or self._data
    end

    function obj:Set(data)
        if self._overrideSetter then
            self._overrideSetter(data)
            self:Notify()
        else
            self._data = data
            self:Notify()
        end
    end

    function obj:Notify()
        for callback in pairs(self._listeners) do
            callback(self:Get())
        end
    end

    function obj:AddListener(callback)
        self._listeners[callback] = true
        return callback
    end

    function obj:RemoveListener(callbackHandle)
        self._listeners[callbackHandle] = nil
    end

    function obj:RemoveAllListeners()
        self._listeners = {}
    end

    function obj:OverrideGetterAndSetter(getter, setter)
        self._overrideGetter = getter
        self._overrideSetter = setter
    end

    setmetatable(obj, {
        -- __index = function(obj, key)
        --     local data = obj:Get()
        --     if type(data) == "table" then
        --         return obj:Get().key
        --     end
        -- end
    })

    return obj
end


return DataObject