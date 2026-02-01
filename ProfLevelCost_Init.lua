-- ProfLevelCost.lua
-- UI-based cost calculator + optimizer + Auctionator
-- Includes:
--   - Best/Expected/Worst crafts toggle
--   - Compact/Full details toggle (affects labels + recipe math verbosity)
--   - Recipes view + Summary view
--   - Auctionator pricing (last scanned) + fallback manual prices
--   - Candidate availability filter (rep/vendor gates) for optimizer
--   - Toggle to include/exclude DROP/AH recipes when filtering
--   - Recipes tab shows N cheapest alternatives per step (with mats)

-- =========================================================
-- Bootstrap / Globals
-- =========================================================
local ADDON_NAME = ...
local PLC = _G.ProfLevelCost or {}
_G.ProfLevelCost = PLC
PLC.ADDON_NAME = ADDON_NAME

ProfLevelCostDB = ProfLevelCostDB or {
  prices = {},
  lastPlanName = nil,
  lastView = "summary",
  optimizeMode = "exp",
  includeRepRecipes = false,      -- when false, exclude recipes that require reputation (per note)
  includeDropRecipes = false,     -- include recipes with source="drop" (Drop/AH)
  includeQuestRecipes = false,    -- include recipes with source="quest" (Quest)
  includeVendorRecipes = false,   -- include recipes with source="vendor"/"faction" (Vendor)
  showNCheapest = 2,             -- show up to N cheapest options (chosen + N-1 alternatives)
  detailsMode = "full",          -- "full" or "compact"  expandCraftedReagents = true,

}

local SKILLUP_PROB = {
  min = { yellow = 1.00, green = 1.00 },  -- Best-case: always skill-up until grey
  exp = { yellow = 0.75, green = 0.25 },  -- Expected-ish
  max = { yellow = 0.50, green = 0.10 },  -- Worst-ish
}
PLC.SKILLUP_PROB = SKILLUP_PROB

-- =========================================================
-- Shared helpers (exported on PLC so other files can use them)
-- =========================================================
function PLC.IsCompact()
  return (ProfLevelCostDB.detailsMode or "full") == "compact"
end

function PLC.DetailsLabel()
  return PLC.IsCompact() and "Compact" or "Full"
end

function PLC.MoneyToCopper(g, s, c)
  g = tonumber(g) or 0
  s = tonumber(s) or 0
  c = tonumber(c) or 0
  return g * 10000 + s * 100 + c
end

function PLC.isFinite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function PLC.CopperToString(copper)
  copper = tonumber(copper) or 0
  local g = math.floor(copper / 10000)
  copper = copper - g * 10000
  local s = math.floor(copper / 100)
  local c = copper - s * 100
  return string.format("%dg %ds %dc", g, s, c)
end

function PLC.CopyMap(t)
  local n = {}
  for k, v in pairs(t or {}) do n[k] = v end
  return n
end

function PLC.AddToMap(map, key, amt)
  if amt <= 0 then return end
  map[key] = (map[key] or 0) + amt
end

function PLC.SafeItemName(itemID)
  itemID = tonumber(itemID)
  if not itemID then return "ItemID ?" end

  local name = GetItemInfo(itemID)
  if name then return name end

  if C_Item and C_Item.RequestLoadItemDataByID then
    C_Item.RequestLoadItemDataByID(itemID)
  end

  return string.format("|Hitem:%d:::::::::|h[Item %d]|h", itemID, itemID)
end

function PLC.ModeLabel(mode)
  if mode == "min" then return "Best" end
  if mode == "max" then return "Worst" end
  return "Expected"
end

function PLC.SourceLabel(src)
  src = (src or "unknown"):lower()
  if src == "trainer" then return "Trainer" end
  if src == "quest" then return "Quest" end
  if src == "drop" then return "Drop/AH" end
  if src == "vendor" then return "Vendor" end
  if src == "faction" then return "Faction" end
  return "Unknown"
end

function PLC.FormatRecipe(label, src, note)
  if not label or label == "" then label = "Recipe" end
  local s = string.format("%s [%s]", label, PLC.SourceLabel(src))
  if note and note ~= "" then
    s = s .. string.format(" (%s)", note)
  end
  return s
end

function PLC.ClampInt(n, lo, hi, fallback)
  n = tonumber(n)
  if not n then return fallback end
  n = math.floor(n + 0.5)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end
