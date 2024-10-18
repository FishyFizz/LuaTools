local Default = {} ---@class FishyLibs_Default

function Default.FillDefault(receiver, template)
    for k, v in pairs(template) do
        if receiver[k] == nil then receiver[k] = v end
    end
end

return Default