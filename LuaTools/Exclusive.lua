local Exclusive = {} ---@class FishyLibs_Exclusive

---@class ExclusiveChoice
---@field key any
---@field onSelect fun(prevKey, data):any data是之前选中项onDeselect函数的返回值, 这个函数的返回值就是外界调用Select的返回值
---@field onDeselect fun(newKey):any 返回值会传给新选项的onSelect

function Exclusive.Create()
    ---@class Exclusive
    local obj = {
        choices = {}, ---@type table<any, ExclusiveChoice>
        currentChoice = nil
    }

    ---@param choice ExclusiveChoice
    function obj:AddChoice(choice)
        self.choices[choice.key] = choice
    end

    function obj:RemoveChoice(key)
        if self.currentChoice == key then
            return self:Deselect()
        end
        self.choices[key] = nil
    end

    function obj:Deselect()
        if self.currentChoice ~= nil then 
            self.currentChoice = nil
            return self.choices[self.currentChoice].onDeselect()
        end
    end

    function obj:Select(key)
        -- key为空, 或选项不存在, 相当于取消选择
        if key == nil or self.choices[key] == nil then
            self:Deselect()
            return
        end
        local ret = self.choices[key].onSelect(self.currentChoice, self:Deselect())
        self.currentChoice = key
        return ret
    end

    return obj
end

return Exclusive