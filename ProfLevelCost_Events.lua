-- ProfLevelCost_Events.lua
-- Events + Auctionator callbacks + slash commands.
-- Depends on ProfLevelCost_Init.lua + ProfLevelCost_Core.lua + ProfLevelCost_UI.lua.

local PLC = _G.ProfLevelCost
local ADDON_NAME = PLC.ADDON_NAME
local CALLER_ID = PLC.CALLER_ID or "ProfLevelCost"

-- Shared helpers
local moneyToCopper  = PLC.MoneyToCopper
local copperToString = PLC.CopperToString
local safeItemName   = PLC.SafeItemName

-- Events
-- =========================================================
local function OnPricesUpdated()
  if PLC.UI and PLC.UI.frame and PLC.UI.frame:IsShown() then
    PLC.UI_UpdateStatus()
    PLC.UI_Recalculate()
  end
end

local function TryRegisterAuctionatorCallback()
  if Auctionator and Auctionator.API and Auctionator.API.v1 and type(Auctionator.API.v1.RegisterForDBUpdate) == "function" then
    Auctionator.API.v1.RegisterForDBUpdate(CALLER_ID, OnPricesUpdated)
    return true
  end
  return false
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON_NAME or arg1 == "Auctionator" then
      TryRegisterAuctionatorCallback()
      if PLC.UI then PLC.UI_UpdateStatus() end
    end
  elseif event == "ITEM_DATA_LOAD_RESULT" then
    if PLC.UI and PLC.UI.frame and PLC.UI.frame:IsShown() then
      PLC.UI_Recalculate()
    end
  end
end)

TryRegisterAuctionatorCallback()

-- =========================================================
-- Slash commands
-- =========================================================
SLASH_PROFLEVELCOST1 = "/plc"
SlashCmdList["PROFLEVELCOST"] = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  cmd = cmd and cmd:lower() or ""

  if cmd == "" then
    PLC.UI_Toggle()
    return
  end

  if cmd == "help" then
    print("|cffffd200ProfLevelCost|r commands:")
    print("  /plc                 (toggle UI)")
    print("  /plc help")
    print("  /plc setprice <itemID> <g> <s> <c>   (fallback)")
    print("  /plc clearprice <itemID>")
    return
  end

  if cmd == "setprice" then
    local id, g, s, c = rest:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
    id = tonumber(id)
    if not id then
      print("|cffff3333Usage|r: /plc setprice <itemID> <g> <s> <c>")
      return
    end
    ProfLevelCostDB.prices[id] = moneyToCopper(g, s, c)
    print(string.format("|cffffd200ProfLevelCost|r: Fallback set %s (%d) = %s",
      safeItemName(id), id, copperToString(ProfLevelCostDB.prices[id])))
    if PLC.UI and PLC.UI.frame and PLC.UI.frame:IsShown() then PLC.UI_Recalculate() end
    return
  end

  if cmd == "clearprice" then
    local id = tonumber(rest)
    if not id then
      print("|cffff3333Usage|r: /plc clearprice <itemID>")
      return
    end
    ProfLevelCostDB.prices[id] = nil
    print(string.format("|cffffd200ProfLevelCost|r: Cleared fallback price for %d", id))
    if PLC.UI and PLC.UI.frame and PLC.UI.frame:IsShown() then PLC.UI_Recalculate() end
    return
  end

  print("|cffff3333Unknown command.|r Use /plc help")
end
