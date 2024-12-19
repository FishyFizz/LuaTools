local RedDotData = require "LuaTools.RedDot.RedDotData"

local ShopRedDotData = RedDotData.Create()

local function Show()
    print("Root                         ", ShopRedDotData.Root.value)
    print("Root.Merchant                ", ShopRedDotData.Root.Merchant.value)
    print("Root.Merchant[1]             ", ShopRedDotData.Root.Merchant[1].value)
    print("Root.Merchant[1].Items       ", ShopRedDotData.Root.Merchant[1].Items.value)
    print("Root.Merchant[2]             ", ShopRedDotData.Root.Merchant[2].value)
    print("Root.Merchant[2].Items       ", ShopRedDotData.Root.Merchant[2].Items.value)
    print("")
end

Show()

ShopRedDotData.Root.Merchant[1].Items[111] = true
ShopRedDotData.Root.Merchant[1].Items[222] = true
Show()

ShopRedDotData.Root.Merchant[2].Items[333] = true
ShopRedDotData.Root.Merchant[2].Items[444] = true
Show()

ShopRedDotData.Root.Merchant[1].Items = nil
Show()

ShopRedDotData.Root.Merchant[2].Items[333] = false
ShopRedDotData.Root.Merchant[2].Items[444] = false
Show()

local x = 0