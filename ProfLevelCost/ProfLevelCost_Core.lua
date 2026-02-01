-- ProfLevelCost_Core.lua
-- Core logic: pricing, filters, optimizer, report builders.
-- Split from the original monolithic ProfLevelCost.lua to keep the UI separate.

local PLC = _G.ProfLevelCost

-- Shared helpers (from ProfLevelCost_Init.lua)
local isCompact      = PLC.IsCompact
local detailsLabel   = PLC.DetailsLabel
local moneyToCopper  = PLC.MoneyToCopper
local copperToString = PLC.CopperToString
local copyMap        = PLC.CopyMap
local addToMap       = PLC.AddToMap
local safeItemName   = PLC.SafeItemName
local modeLabel      = PLC.ModeLabel
local formatRecipe   = PLC.FormatRecipe
local clampInt       = PLC.ClampInt

local SKILLUP_PROB   = PLC.SKILLUP_PROB

-- Price Provider (Auctionator + fallback)
-- =========================================================
local CALLER_ID = PLC.CALLER_ID or "ProfLevelCost"
PLC.CALLER_ID = CALLER_ID

local function AuctionatorReady()
  return Auctionator and Auctionator.API and Auctionator.API.v1
     and type(Auctionator.API.v1.GetAuctionPriceByItemID) == "function"
end

local function getUnitPrice(itemID)
  itemID = tonumber(itemID)
  if not itemID then return nil, "none" end

  if AuctionatorReady() then
    local p = Auctionator.API.v1.GetAuctionPriceByItemID(CALLER_ID, itemID)
    if p and p > 0 then return p, "auctionator" end

    if type(Auctionator.API.v1.GetVendorPriceByItemID) == "function" then
      local vp = Auctionator.API.v1.GetVendorPriceByItemID(CALLER_ID, itemID)
      if vp and vp > 0 then return vp, "auctionator_vendor" end
    end
  end

  local fp = ProfLevelCostDB and ProfLevelCostDB.prices and ProfLevelCostDB.prices[itemID]
  if fp and fp > 0 then return fp, "fallback" end

  return nil, "none"
end

-- =========================================================
-- Availability filter (rep / vendor gates + drop toggle)
-- =========================================================

local function normalizeRepFactionName(noteFaction)
  if not noteFaction then return nil end
  noteFaction = noteFaction:gsub("^%s+", ""):gsub("%s+$", "")

  if noteFaction:find("Honor Hold/Thrallmar", 1, true) then
    local playerFaction = UnitFactionGroup("player")
    if playerFaction == "Alliance" then
      return "Honor Hold"
    elseif playerFaction == "Horde" then
      return "Thrallmar"
    end
    return "Honor Hold"
  end

  return noteFaction
end

local function stripColorCodes(s)
  if not s then return "" end
  -- Remove WoW color codes like |cffaabbcc and reset |r
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return s
end

local function parseRepRequirementFromNote(note)
  if not note or note == "" then return nil end
  note = stripColorCodes(note)

  -- If the note contains parentheses, prefer the INNER text (usually "Faction - Honored")
  -- but keep a list of candidates to try (inner(s) + full note).
  local candidates = {}
  for inner in note:gmatch("%(([^%)]-)%)") do
    inner = inner and inner:gsub("^%s+", ""):gsub("%s+$", "")
    if inner and inner ~= "" then table.insert(candidates, inner) end
  end
  table.insert(candidates, note)

  -- Accept multiple formats:
  --  1) "Faction - Standing"
  --  2) "Standing - Faction"
  --  3) "Faction (Standing)"  (handled because standing is within parentheses)
  --  Also accept different dash characters.
  local standingPattern = "(Hated|Hostile|Unfriendly|Neutral|Friendly|Honored|Revered|Exalted)"
  local dashPattern = "%s*[%-%–%—]%s*"

  for _, text in ipairs(candidates) do
    text = text:gsub("^%s+", ""):gsub("%s+$", "")

    local a, standing = text:match("(.+)" .. dashPattern .. standingPattern .. "$")
    if a and standing then
      local faction = normalizeRepFactionName(a:gsub("^%s+", ""):gsub("%s+$", ""))
      local req = STANDING[standing]
      if faction and req then return faction, req end
    end

    local standing2, b = text:match("^" .. standingPattern .. dashPattern .. "(.+)$")
    if standing2 and b then
      local faction = normalizeRepFactionName(b:gsub("^%s+", ""):gsub("%s+$", ""))
      local req = STANDING[standing2]
      if faction and req then return faction, req end
    end

    -- "Requires Honored with Timbermaw Hold"
    local standing3, faction3 = text:match("Requires%s+" .. standingPattern .. "%s+with%s+(.+)")
    if standing3 and faction3 then
      local faction = normalizeRepFactionName(faction3:gsub("^%s+", ""):gsub("%s+$", ""))
      local req = STANDING[standing3]
      if faction and req then return faction, req end
    end
  end

  return nil
end

local function noteLooksLikeRep(note)
  if not note or note == "" then return false end
  note = stripColorCodes(note)
  return note:find("Hated") or note:find("Hostile") or note:find("Unfriendly")
      or note:find("Neutral") or note:find("Friendly") or note:find("Honored")
      or note:find("Revered") or note:find("Exalted")
end

local function isCandidateUsable(candidate)
  -- "Usable" is now ONLY about the user's global include/exclude toggles:
  --  - Drop/AH (source=drop)
  --  - Quest (source=quest)
  --  - Reputation-gated (detected from note)
  --
  -- We do NOT check the player's current reputation standing here.

  if not candidate then return true, nil end
  local src = (candidate.source or "unknown"):lower()
  local note = candidate.note or ""

  if src == "drop" and not (ProfLevelCostDB.includeDropRecipes == true) then
    return false, "Drop/AH recipes excluded"
  end

  if src == "quest" and not (ProfLevelCostDB.includeQuestRecipes == true) then
    return false, "Quest recipes excluded"
  end

  if (src == "vendor" or src == "faction") and not (ProfLevelCostDB.includeVendorRecipes == true) then
    return false, "Vendor recipes excluded"
  end

  -- Reputation detection: prefer structured parse, but fall back to keywords.
  local faction, reqStanding = parseRepRequirementFromNote(note)
  local isRep = (faction ~= nil and reqStanding ~= nil) or noteLooksLikeRep(note)

  if isRep and not (ProfLevelCostDB.includeRepRecipes == true) then
    return false, "Reputation recipes excluded"
  end

  return true, nil
end



-- =========================================================
-- Cheaper-crafted reagents (Option 2): expand into base mats
-- =========================================================
-- When enabled, the cost engine will compare buying a reagent vs crafting it
-- (using recipes from the same pool(s) as the current plan, if provided).
-- If crafting is cheaper (or reduces missing-price items), we "expand" that reagent
-- into its own reagents recursively, so optimizer + reports use the effective base mats.
--
-- Toggle: ProfLevelCostDB.expandCraftedReagents (default true)

local _CraftIndexByItem = nil

-- Allows LoadOnDemand data addons to reset the craft index when new pools are loaded.
function PLC.InvalidateCraftIndex()
  _CraftIndexByItem = nil
end

local function _EnsureCraftIndex()
  if _CraftIndexByItem then return end
  _CraftIndexByItem = {}

  for poolKey, pool in pairs(ProfLevelCostRecipePools or {}) do
    if pool and type(pool.recipes) == "table" then
      for _, rec in ipairs(pool.recipes) do
        local produces = rec and rec.produces
        if type(produces) == "table" then
          for _, p in ipairs(produces) do
            local pid = tonumber(p.id)
            local pqty = tonumber(p.qty) or 1
            if pid and pqty > 0 then
              _CraftIndexByItem[pid] = _CraftIndexByItem[pid] or {}
              table.insert(_CraftIndexByItem[pid], { poolKey = poolKey, recipe = rec, outQty = pqty })
            end
          end
        end
      end
    end
  end
end

local function _PoolAllowed(allowedPools, poolKey)
  if not allowedPools then return true end
  if type(allowedPools) ~= "table" then return true end
  for _, k in ipairs(allowedPools) do
    if k == poolKey then return true end
  end
  return false
end

local function _MissingCounts(missMap)
  local items, qty = 0, 0
  for _, q in pairs(missMap or {}) do
    items = items + 1
    qty = qty + (tonumber(q) or 0)
  end
  return items, qty
end

local function _MergeQtyMap(dst, src)
  if not dst or not src then return end
  for id, q in pairs(src) do
    dst[id] = (dst[id] or 0) + (tonumber(q) or 0)
  end
end

local function _CompareCostTriples(aCost, aMissMap, bCost, bMissMap)
  local aItems, aQty = _MissingCounts(aMissMap)
  local bItems, bQty = _MissingCounts(bMissMap)

  if aItems ~= bItems then return aItems < bItems end
  if aQty ~= bQty then return aQty < bQty end
  return (tonumber(aCost) or 0) < (tonumber(bCost) or 0)
end

-- Simulate acquiring `qty` of `itemID` at a given `skill`, consuming/producing from `inventory`.
-- Returns:
--   pricedCost (copper, excluding missing-priced items),
--   purchasesMap[itemID]=qtyToBuy (base mats to acquire),
--   missingMap[itemID]=qtyMissingPrice
local function _SimAcquire(itemID, qty, skill, inventory, allowedPools, visited, craftListOut)
  itemID = tonumber(itemID)
  qty = tonumber(qty) or 0
  skill = tonumber(skill) or 0
  if not itemID or qty <= 0 then
    return 0, {}, {}
  end

  visited = visited or {}
  if visited[itemID] then
    -- cycle protection: force "buy"
    local unit = getUnitPrice(itemID)
    local cost = (unit and unit > 0) and (unit * qty) or 0
    local purchases, miss = {}, {}
    purchases[itemID] = qty
    if not unit or unit <= 0 then miss[itemID] = qty end
    return cost, purchases, miss
  end
  visited[itemID] = true

  -- Use intermediates already in inventory first.
  local have = inventory[itemID] or 0
  local use = math.min(have, qty)
  if use > 0 then
    inventory[itemID] = have - use
  end
  local remain = qty - use
  if remain <= 0 then
    visited[itemID] = nil
    return 0, {}, {}
  end

  -- BUY option
  local buyUnit = getUnitPrice(itemID)
  local buyCost = (buyUnit and buyUnit > 0) and (buyUnit * remain) or 0
  local buyPurch, buyMiss = {}, {}
  buyPurch[itemID] = remain
  if not buyUnit or buyUnit <= 0 then
    buyMiss[itemID] = remain
  end

  -- CRAFT option
  local bestCost, bestPurch, bestMiss = math.huge, nil, nil
  local bestRec, bestCrafts, bestOutQty = nil, nil, nil
  local bestInvSim = nil

  if ProfLevelCostDB.expandCraftedReagents ~= false then
    _EnsureCraftIndex()
    local options = _CraftIndexByItem[itemID]
    if type(options) == "table" then
      for _, opt in ipairs(options) do
        local rec = opt.recipe
        local outQty = tonumber(opt.outQty) or 1
        if rec and outQty > 0 and _PoolAllowed(allowedPools, opt.poolKey) then
          local req = tonumber(rec.reqSkill) or 0
          if skill >= req then
            local usable = true
            if type(isCandidateUsable) == "function" then
              usable = select(1, isCandidateUsable(rec))
            end
            if usable then
              local crafts = math.ceil(remain / outQty)
              local invSim = copyMap(inventory)
              local purchSim, missSim = {}, {}
              local costSim = 0

              local cycleGuard = copyMap(visited)
              for _, rr in ipairs(rec.reagents or {}) do
                local rid = tonumber(rr.id)
                local rq = (tonumber(rr.qty) or 0) * crafts
                if rid and rq > 0 then
                  local cCost, cPurch, cMiss = _SimAcquire(rid, rq, skill, invSim, allowedPools, cycleGuard, craftListOut)
                  costSim = costSim + (tonumber(cCost) or 0)
                  _MergeQtyMap(purchSim, cPurch)
                  _MergeQtyMap(missSim, cMiss)
                end
              end

              -- leftover production goes into inventory for later steps
              local produced = crafts * outQty
              local leftover = produced - remain
              if leftover > 0 then
                invSim[itemID] = (invSim[itemID] or 0) + leftover
              end

              if _CompareCostTriples(costSim, missSim, bestCost, bestMiss or {}) then
                bestCost, bestPurch, bestMiss = costSim, purchSim, missSim
                bestRec, bestCrafts, bestOutQty = rec, crafts, outQty
                bestInvSim = invSim
              end
            end
          end
        end
      end
    end
  end

  local finalCost, finalPurch, finalMiss = buyCost, buyPurch, buyMiss
  if bestPurch and bestCost < math.huge and _CompareCostTriples(bestCost, bestMiss or {}, buyCost, buyMiss or {}) then
    -- Apply inventory changes from chosen craft simulation.
    for k in pairs(inventory) do inventory[k] = nil end
    for k, v in pairs(bestInvSim or {}) do inventory[k] = v end

    finalCost, finalPurch, finalMiss = bestCost, bestPurch or {}, bestMiss or {}

    if craftListOut and bestRec then
      table.insert(craftListOut, {
        itemID = itemID,
        qty = remain,
        crafts = bestCrafts,
        recipeLabel = bestRec.label,
        recipeSource = bestRec.source,
        recipeNote = bestRec.note,
      })
    end
  end

  visited[itemID] = nil
  return (finalCost or 0), (finalPurch or {}), (finalMiss or {})
end


-- =========================================================
-- Core helpers
-- =========================================================
local function evalReagentsCostOnly(reagents, crafts, inventory, skill, allowedPools)
  local inv = copyMap(inventory)
  local cost = 0
  local missingMap = {}

  skill = tonumber(skill) or 0

  for _, r in ipairs(reagents or {}) do
    local id = tonumber(r.id)
    local qty = (tonumber(r.qty) or 0) * crafts
    if id and qty > 0 then
      local cCost, _, cMiss = _SimAcquire(id, qty, skill, inv, allowedPools, nil, nil)
      cost = cost + (tonumber(cCost) or 0)
      _MergeQtyMap(missingMap, cMiss)
    end
  end

  local missItems, missQty = _MissingCounts(missingMap)
  return cost, missItems, missQty
end

local function applyReagents(reagents, crafts, inventory, neededOut, missingPriceOut, skill, allowedPools, craftedOut)
  local cost = 0
  skill = tonumber(skill) or 0

  for _, r in ipairs(reagents or {}) do
    local id = tonumber(r.id)
    local qty = (tonumber(r.qty) or 0) * crafts
    if id and qty > 0 then
      local craftList = craftedOut
      local cCost, purchases, miss = _SimAcquire(id, qty, skill, inventory, allowedPools, nil, craftList)
      cost = cost + (tonumber(cCost) or 0)

      for pid, pqty in pairs(purchases or {}) do
        addToMap(neededOut, pid, pqty)
      end
      for mid in pairs(miss or {}) do
        missingPriceOut[mid] = true
      end
    end
  end

  return cost
end

local function applyProduces(produces, crafts, inventory)
  for _, p in ipairs(produces or {}) do
    local id = tonumber(p.id)
    local qty = (tonumber(p.qty) or 0) * crafts
    if id and qty > 0 then
      inventory[id] = (inventory[id] or 0) + qty
    end
  end
end

local function buildCandidateBreakdown(reagents, crafts, inventoryStart, missingPriceOut)
  local inv = copyMap(inventoryStart)
  local breakdown, stepCost = {}, 0

  for _, r in ipairs(reagents or {}) do
    local id = tonumber(r.id)
    local per = tonumber(r.qty) or 0
    if id and per > 0 then
      local totalNeed = per * crafts
      local have = inv[id] or 0
      local fromInv = math.min(have, totalNeed)
      local toBuy = totalNeed - fromInv
      if fromInv > 0 then inv[id] = have - fromInv end

      local unit = (getUnitPrice(id))
      local cost = 0
      if toBuy > 0 and unit and unit > 0 then
        cost = toBuy * unit
        stepCost = stepCost + cost
      elseif toBuy > 0 and (not unit or unit <= 0) and missingPriceOut then
        missingPriceOut[id] = true
      end

      table.insert(breakdown, {
        id=id, per=per, crafts=crafts, total=totalNeed,
        fromInv=fromInv, toBuy=toBuy, unit=unit, cost=cost
      })
    end
  end

  table.sort(breakdown, function(a,b) return a.id < b.id end)
  return breakdown, stepCost
end

-- =========================================================
-- Optimizer (mode-sensitive re-pick + usability filter)
-- =========================================================
-- =========================================================
-- Pool-based plans (no brackets stored; we generate chunks)
-- =========================================================

local function isPoolPlan(plan)
  return plan and plan.poolKey ~= nil
end

-- poolKey can be:
--   "BS_PRE"
--   {"BS_PRE", "BS_TBC", ...}
local function getPoolRecipes(poolKey)
  if not poolKey then return {} end

  local keys = {}
  if type(poolKey) == "table" then
    for _, k in ipairs(poolKey) do
      if type(k) == "string" and k ~= "" then table.insert(keys, k) end
    end
  elseif type(poolKey) == "string" then
    keys[1] = poolKey
  end


  if PLC and PLC.EnsurePoolsLoaded then
    PLC.EnsurePoolsLoaded(keys)
  end

  -- Pools are defined by the data addons; if none are loaded (or load failed), return empty.
  if not ProfLevelCostRecipePools then return {} end

  local out = {}
  local seen = {}

  local function recipeKey(r)
    if not r then return nil end
    -- Prefer stable IDs if present
    if r.spellID then return "spell:" .. tostring(r.spellID) end
    if r.recipeID then return "recipe:" .. tostring(r.recipeID) end
    -- Otherwise, try output item id
    if type(r.produces) == "table" and r.produces[1] and r.produces[1].id then
      return "out:" .. tostring(r.produces[1].id) .. ":req:" .. tostring(r.reqSkill or 0)
    end
    -- Last resort: label+reqSkill+reagents signature
    local sig = (r.label or "??") .. "|req:" .. tostring(r.reqSkill or 0)
    if type(r.reagents) == "table" then
      for i = 1, math.min(#r.reagents, 12) do
        local rr = r.reagents[i]
        sig = sig .. "|" .. tostring(rr.id) .. "x" .. tostring(rr.qty)
      end
    end
    return "sig:" .. sig
  end

  for _, k in ipairs(keys) do
    local pool = ProfLevelCostRecipePools[k]
    if pool and type(pool.recipes) == "table" then
      for _, r in ipairs(pool.recipes) do
        local key = recipeKey(r)
        if key and not seen[key] then
          seen[key] = true
          table.insert(out, r)
        end
      end
    end
  end

  return out
end


local function candidateViableAtSkill(cand, skill)
  if not cand then return false end
  local req = tonumber(cand.reqSkill) or 0
  if skill < req then return false end

  local colors = cand.colors
  if type(colors) ~= "table" then
    return true -- unknown, treat as possibly viable
  end

  local grey = tonumber(colors.gray) or tonumber(colors.grey)
  if not grey then
    return true
  end

  return skill < grey
end

local function buildVirtualBracketsFromPool(plan)
  local fromSkill = tonumber(plan.from) or 0
  local toSkill   = tonumber(plan.to) or fromSkill
  local chunk     = tonumber(plan.chunk) or 5
  local firstChunk = tonumber(plan.firstChunk) -- nil if not set
  if chunk <= 0 then chunk = 5 end
  if firstChunk and firstChunk <= 0 then firstChunk = nil end

  local recipes = getPoolRecipes(plan.poolKey)
  local brackets = {}

  local s = fromSkill
  local isFirst = true

  while s < toSkill do
    local step = chunk
    if isFirst and firstChunk then
      step = firstChunk
    end
    isFirst = false

    local e = math.min(s + step, toSkill)
    local candidates = {}

    for _, r in ipairs(recipes) do
      if candidateViableAtSkill(r, s) then
        table.insert(candidates, r)
      end
    end

    if #candidates == 0 then
      for _, r in ipairs(recipes) do
        local req = tonumber(r.reqSkill) or 0
        if req <= s then
          table.insert(candidates, r)
        end
      end
    end

    table.insert(brackets, {
      from = s,
      to = e,
      label = string.format("%d-%d", s, e),
      candidates = candidates,
      _poolKeys = (type(plan.poolKey) == "table" and plan.poolKey) or (plan.poolKey and { plan.poolKey }) or nil,
    })

    s = e
  end

  return brackets
end


local function skillupChanceLinear(Y, G, X)
  -- Orange or earlier => always skill up
  if X < Y then return 1.0 end
  -- Gray => no skill ups
  if X >= G then return 0.0 end

  local denom = (G - Y)
  if denom <= 0 then
    -- Degenerate data: treat as always skill-up until gray
    return 1.0
  end

  local p = (G - X) / denom
  if p < 0 then p = 0 end
  if p > 1 then p = 1 end
  return p
end

local function applyModeToChance(p, mode)
  -- p is the base probability from the linear formula.
  -- Best: luckier (scaled up), Expected: base, Worst: scaled down.
  if p < 1.0 then 
    if mode == "min" then
      local pb = p * 1.25
      if pb > 1.0 then pb = 1.0 end
      return pb
    elseif mode == "max" then
      local pw = p * 0.75
      if pw < 0.01 then pw = 0.01 end  -- floor to prevent insane/infinite crafts near gray
      return pw
    end
  end

  -- Expected
  if p < 0.01 then p = 0.01 end  -- optional: keeps expected finite too (remove if you want true blow-up)
  return p
end

local function estimateCraftsForRange(fromSkill, toSkill, cand, mode)
  fromSkill = tonumber(fromSkill) or 0
  toSkill   = tonumber(toSkill) or 0
  if toSkill <= fromSkill then return 0 end

  local req = tonumber(cand.reqSkill)
  if req and fromSkill < req then
    return math.huge, ("Requires skill " .. req)
  end

  local colors = cand.colors
  if type(colors) ~= "table" then
    return math.huge, "No color data"
  end

  -- Only need Y (yellow) and G (gray) for the formula
  local Y = tonumber(colors.yellow) or tonumber(colors.yellowSkill)
  local G = tonumber(colors.gray) or tonumber(colors.grey) or tonumber(colors.graySkill)

  if not Y or not G then
    return math.huge, "Missing yellow/gray"
  end

  -- If already gray at bracket start, cannot progress
  if fromSkill >= G then
    return math.huge, "Already gray"
  end

  local crafts = 0

  -- Expected crafts per skill point at skill X is 1/p(X)
  -- We model each skill point separately.
  for X = fromSkill, (toSkill - 1) do
    local p = skillupChanceLinear(Y, G, X)
    p = applyModeToChance(p, mode)

    if p <= 0 then
      return math.huge, "No skillups"
    end

    crafts = crafts + (1.0 / p)
  end

  return math.ceil(crafts - 1e-9)
end


local function estimateCraftVariants(bracket, cand)
  local fromSkill = tonumber(bracket.from) or 0
  local toSkill   = tonumber(bracket.to)   or 0

  -- If candidate has explicit crafts table, keep old behavior
  if type(cand.crafts) == "table" then
    local base = tonumber(bracket.crafts) or 0
    local minv = tonumber(cand.crafts.min) or base
    local expv = tonumber(cand.crafts.exp) or base
    local maxv = tonumber(cand.crafts.max) or base
    return minv, expv, maxv, nil
  end

  -- Otherwise compute from reqSkill + colors with the new formula
  local minC, minReason = estimateCraftsForRange(fromSkill, toSkill, cand, "min")
  local expC, expReason = estimateCraftsForRange(fromSkill, toSkill, cand, "exp")
  local maxC, maxReason = estimateCraftsForRange(fromSkill, toSkill, cand, "max")

  if not minC then minC = math.huge; minReason = minReason or "No data" end
  if not expC then expC = math.huge; expReason = expReason or "No data" end
  if not maxC then maxC = math.huge; maxReason = maxReason or "No data" end

  local reason = minReason or expReason or maxReason
  return minC, expC, maxC, reason
end



local function craftsForMode(bracket, cand, mode)
  local minC, expC, maxC, reason = estimateCraftVariants(bracket, cand)

  -- If recipe is unusable (reqSkill not met / grey), minC/expC/maxC may be huge
  local pick
  if mode == "min" then pick = minC
  elseif mode == "max" then pick = maxC
  else pick = expC end

  return pick, minC, expC, maxC, reason
end

local function isOptimizerPlan(plan)
  return plan and ((plan.brackets and #plan.brackets > 0) or plan.poolKey ~= nil)
end

local function pickCandidateForBracket(bracket, inventory, mode)
  local bestIdx = nil
  local bestKey = nil -- {missingItems, missingQty, pricedCost}
  local comparisons = {}
  local skill = tonumber(bracket.from) or 0
  local allowedPools = bracket._poolKeys

  local function betterThan(keyA, keyB)
    if not keyB then return true end
    if keyA[1] ~= keyB[1] then return keyA[1] < keyB[1] end
    if keyA[2] ~= keyB[2] then return keyA[2] < keyB[2] end
    if keyA[3] ~= keyB[3] then return keyA[3] < keyB[3] end
    return false
  end

  for ci, cand in ipairs(bracket.candidates or {}) do
    local crafts, minC, expC, maxC, craftReason = craftsForMode(bracket, cand, mode)
    local usable, reason = isCandidateUsable(cand)

    -- Hard reject anything that yields non-finite crafts (inf/nan) or <= 0
    if not PLC.isFinite(crafts) or crafts <= 0 then
      usable = false
      reason = craftReason or reason or "Not usable in bracket"
    end

    -- IMPORTANT: even if filtering is OFF, do NOT consider unusable candidates
    local considered = usable

    local pricedCost, missingItems, missingQty, missingList
    if considered then
      pricedCost, missingItems, missingQty, missingList = evalReagentsCostOnly(cand.reagents or {}, crafts, inventory, skill, allowedPools)
    else
      pricedCost, missingItems, missingQty, missingList = math.huge, 0, 0, nil
    end

    table.insert(comparisons, {
      idx = ci,
      label = cand.label or ("Candidate " .. ci),
      source = cand.source,
      note = cand.note,
      crafts = crafts,
      craftsMin = minC,
      craftsExp = expC,
      craftsMax = maxC,

      cost = pricedCost, -- priced reagents only
      missingItems = missingItems or 0,
      missingQty = missingQty or 0,
      missingList = missingList,

      usable = usable,
      usableReason = reason,
      considered = considered,
      reagents = cand.reagents,
      produces = cand.produces,
    })

    if considered then
      local key = { missingItems or 0, missingQty or 0, pricedCost or math.huge }
      if betterThan(key, bestKey) then
        bestKey = key
        bestIdx = ci
      end
    end
  end

  if not bestIdx then
    table.sort(comparisons, function(a, b) return (a.idx or 0) < (b.idx or 0) end)
    return nil, nil, comparisons
  end

  -- Sort candidates list for display / alternative picking:
  --   considered first, then fewer missing prices, then cheaper
  table.sort(comparisons, function(a, b)
    if a.considered ~= b.considered then
      return a.considered and not b.considered
    end
    local am = a.missingItems or 0
    local bm = b.missingItems or 0
    if am ~= bm then return am < bm end

    local aq = a.missingQty or 0
    local bq = b.missingQty or 0
    if aq ~= bq then return aq < bq end

    local ac = a.cost or math.huge
    local bc = b.cost or math.huge
    if ac == bc then return (a.idx or 0) < (b.idx or 0) end
    return ac < bc
  end)

  return bracket.candidates[bestIdx], bestIdx, comparisons
end

local function buildOptimizerSteps(rawPlan, mode)
  mode = mode or "exp"
  local steps = {}
  local inventory = {}

  for bi, br in ipairs(rawPlan.brackets or {}) do
    if br.candidates and #br.candidates > 0 then
      local invStart = copyMap(inventory) -- snapshot at bracket start
      local chosen, chosenIdx, comparisons = pickCandidateForBracket(br, inventory, mode)

      if chosen then
        local crafts, minC, expC, maxC = craftsForMode(br, chosen, mode)

        table.insert(steps, {
          label = string.format("%s - %s", (br.label or ("Bracket " .. bi)), formatRecipe(chosen.label, chosen.source, chosen.note)),
          crafts = crafts,
          reagents = chosen.reagents,
          produces = chosen.produces,

          _bracketLabel = br.label,
          _bracketFrom = br.from,
          _bracketTo = br.to,
          _poolKeys = br._poolKeys,
          _chosenLabel = chosen.label,
          _chosenSource = chosen.source,
          _chosenNote = chosen.note,
          _chosenIdx = chosenIdx,
          _craftsMin = minC,
          _craftsExp = expC,
          _craftsMax = maxC,
          _optimizerComparisons = comparisons,
          _filterUsable = (ProfLevelCostDB.includeRepRecipes == true),
          _invStart = invStart,
        })

        local neededDummy, missingDummy = {}, {}
        applyReagents(chosen.reagents or {}, crafts, inventory, neededDummy, missingDummy, br.from, br._poolKeys, nil)
        applyProduces(chosen.produces or {}, crafts, inventory)
      else
        table.insert(steps, {
          label = string.format("%s - |cffff3333No usable recipe found|r", (br.label or ("Bracket " .. bi))),
          crafts = 0,
          reagents = {},
          produces = {},
          _bracketLabel = br.label,
          _bracketFrom = br.from,
          _bracketTo = br.to,
          _poolKeys = br._poolKeys,
          _chosenLabel = nil,
          _optimizerComparisons = comparisons,
          _filterUsable = (ProfLevelCostDB.includeRepRecipes == true),
          _invStart = invStart,
        })
      end
    end
  end

  return steps
end

local function normalizePlan(rawPlan)
  if isPoolPlan(rawPlan) then
    local virtual = {
      name = rawPlan.name,
      brackets = buildVirtualBracketsFromPool(rawPlan),
    }

    local mode = ProfLevelCostDB.optimizeMode or "exp"
    return {
      name = rawPlan.name,
      steps = buildOptimizerSteps(virtual, mode),
      _isOptimizer = true,
      _optimizerMode = mode,
      _filterUsable = (ProfLevelCostDB.includeRepRecipes == true),
    }
  end

  -- existing behavior for bracket-based plans...
  if isOptimizerPlan(rawPlan) and rawPlan.brackets then
    local mode = ProfLevelCostDB.optimizeMode or "exp"
    return {
      name = rawPlan.name,
      steps = buildOptimizerSteps(rawPlan, mode),
      _isOptimizer = true,
      _optimizerMode = mode,
      _filterUsable = (ProfLevelCostDB.includeRepRecipes == true),
    }
  end

  return rawPlan
end

function PLC.ComputePlanDetailed(rawPlan)
  local plan = normalizePlan(rawPlan)

  local inventory, needed, missingPrice = {}, {}, {}
  local total, chosen, stepDetails = 0, {}, {}

  for si, step in ipairs(plan.steps or {}) do
    local crafts = tonumber(step.crafts) or 0
    if crafts > 0 then
      local reagents = step.reagents

      if step._chosenLabel then
        chosen[si] = string.format("%s -> %s",
          step._bracketLabel or ("Step " .. si),
          formatRecipe(step._chosenLabel, step._chosenSource, step._chosenNote)
        )
      end

      local breakdown, stepCost = {}, 0
      for _, r in ipairs(reagents or {}) do
        local id = tonumber(r.id)
        local per = tonumber(r.qty) or 0
        if id and per > 0 then
          local totalNeed = per * crafts
          local have = inventory[id] or 0
          local fromInv = math.min(have, totalNeed)
          local toBuy = totalNeed - fromInv

          local unit = (getUnitPrice(id))
          local cost = 0
          if toBuy > 0 and unit and unit > 0 then
            cost = toBuy * unit
            stepCost = stepCost + cost
          elseif toBuy > 0 and (not unit or unit <= 0) then
            missingPrice[id] = true
          end

          table.insert(breakdown, {
            id=id, per=per, crafts=crafts, total=totalNeed,
            fromInv=fromInv, toBuy=toBuy, unit=unit, cost=cost
          })
        end
      end

      local craftedStep = {}

      total = total + applyReagents(reagents or {}, crafts, inventory, needed, missingPrice, step._bracketFrom, step._poolKeys, craftedStep)
      applyProduces(step.produces or {}, crafts, inventory)

      local produces = {}
      for _, p in ipairs(step.produces or {}) do
        local id = tonumber(p.id)
        local per = tonumber(p.qty) or 0
        if id and per > 0 then
          table.insert(produces, { id=id, total=per*crafts })
        end
      end

      table.insert(stepDetails, {
        index=si,
        label=step.label or ("Step " .. si),
        crafts=crafts,
        craftsMin=step._craftsMin,
        craftsExp=step._craftsExp,
        craftsMax=step._craftsMax,
        option=step._chosenLabel,
        optionSource=step._chosenSource,
        optionNote=step._chosenNote,
        reagents=breakdown,
        produces=produces,
        craftedReagents=craftedStep,
        stepCost=stepCost,
        optimizerComparisons = step._optimizerComparisons,
        chosenIdx = step._chosenIdx,
        bracketLabel = step._bracketLabel,
        bracketFrom = step._bracketFrom,
        bracketTo = step._bracketTo,
        filterUsable = step._filterUsable == true,
        invStart = step._invStart,
      })
    else
      table.insert(stepDetails, {
        index=si,
        label=step.label or ("Step " .. si),
        crafts=0,
        optimizerComparisons = step._optimizerComparisons,
        bracketLabel = step._bracketLabel,
        bracketFrom = step._bracketFrom,
        bracketTo = step._bracketTo,
        filterUsable = step._filterUsable == true,
        invStart = step._invStart,
      })
    end
  end

  return total, needed, missingPrice, chosen, stepDetails, plan
end

-- =========================================================
-- Plan helpers
-- =========================================================
local function getPlans() return ProfLevelCostPlans or {} end

local function findPlanByName(name)
  if not name then return nil end
  name = name:lower()
  for _, p in ipairs(getPlans()) do
    if (p.name or ""):lower() == name then return p end
  end
  return nil
end

local function listPlanNamesSorted()
  local names = {}
  for _, p in ipairs(getPlans()) do
    if p.name then table.insert(names, p.name) end
  end
  table.sort(names)
  return names
end

-- =========================================================
-- Reports
-- =========================================================
local function buildSummaryReport(rawPlan)
  local total, needed, missingPrice, _, _, normPlan = PLC.ComputePlanDetailed(rawPlan)

  local lines = {}
  table.insert(lines, "Plan: " .. (normPlan.name or "Unknown"))
  table.insert(lines, "Price source: " .. (AuctionatorReady() and "Auctionator (last scanned)" or "Fallback only (Auctionator not ready)"))
  table.insert(lines, "Details: " .. detailsLabel())
  table.insert(lines, "Expand crafted reagents: " .. ((ProfLevelCostDB.expandCraftedReagents ~= false) and "On" or "Off"))
  table.insert(lines, "")
  if normPlan._isOptimizer then
    table.insert(lines, "Route: Optimized (recipes re-picked for this mode)")
    table.insert(lines, "Optimize using: " .. modeLabel(normPlan._optimizerMode or "exp"))
    table.insert(lines, "Include reputation recipes: " .. ((ProfLevelCostDB.includeRepRecipes == true) and "Yes" or "No"))
    table.insert(lines, "Include Drop/AH: " .. ((ProfLevelCostDB.includeDropRecipes == true) and "Yes" or "No"))
    table.insert(lines, "Include Quest: " .. ((ProfLevelCostDB.includeQuestRecipes == true) and "Yes" or "No"))
    table.insert(lines, "Include Vendor: " .. ((ProfLevelCostDB.includeVendorRecipes == true) and "Yes" or "No"))
    table.insert(lines, "")
  else
    table.insert(lines, "")
  end

  table.insert(lines, "TOTAL (priced items only): " .. copperToString(total))
  table.insert(lines, "")

  local items = {}
  for id, qty in pairs(needed) do
    local unit = (getUnitPrice(id))
    local cost = unit and (unit * qty) or nil
    table.insert(items, { id=id, qty=qty, unit=unit, cost=cost })
  end
  table.sort(items, function(a, b)
    local ac = a.cost or -1
    local bc = b.cost or -1
    if ac == bc then return a.qty > b.qty end
    return ac > bc
  end)

  table.insert(lines, "Materials needed (net, after intermediates):")
  local limit = #items
  for i = 1, limit do
    local it = items[i]
    local name = safeItemName(it.id)
    if it.unit then
      table.insert(lines, string.format("  - %s x%d  @ %s  = %s",
        name, it.qty, copperToString(it.unit), copperToString(it.cost)))
    else
      table.insert(lines, string.format("  - %s x%d  = NO PRICE", name, it.qty))
    end
  end

  local missingCount = 0
  for _ in pairs(missingPrice) do missingCount = missingCount + 1 end
  if missingCount > 0 then
    table.insert(lines, "")
    table.insert(lines, string.format("Missing prices for %d item(s):", missingCount))
    local miss = {}
    for id in pairs(missingPrice) do table.insert(miss, id) end
    table.sort(miss)
    for _, id in ipairs(miss) do
      table.insert(lines, string.format("  - %s (%d)", safeItemName(id), id))
    end
  end

  return table.concat(lines, "\n")
end

local function buildRecipesReport(rawPlan)
  local total, _, missingPrice, _, stepDetails, normPlan = PLC.ComputePlanDetailed(rawPlan)

  local showN = clampInt(ProfLevelCostDB.showNCheapest or 2, 1, 10, 2)
  local showAlternatives = math.max(0, showN - 1)
  local compact = isCompact()

  local lines = {}
  table.insert(lines, "Plan: " .. (normPlan.name or "Unknown"))
  table.insert(lines, "View: Recipes (step-by-step)")
  table.insert(lines, "Price source: " .. (AuctionatorReady() and "Auctionator (last scanned)" or "Fallback only (Auctionator not ready)"))
  table.insert(lines, "Details: " .. detailsLabel())
  table.insert(lines, "Expand crafted reagents: " .. ((ProfLevelCostDB.expandCraftedReagents ~= false) and "On" or "Off"))
  table.insert(lines, "")
  if normPlan._isOptimizer then
    table.insert(lines, "Optimize using: " .. modeLabel(normPlan._optimizerMode or "exp"))
    table.insert(lines, "Include reputation recipes: " .. ((ProfLevelCostDB.includeRepRecipes == true) and "Yes" or "No"))
    table.insert(lines, "Include Drop/AH: " .. ((ProfLevelCostDB.includeDropRecipes == true) and "Yes" or "No"))
    table.insert(lines, "Include Quest: " .. ((ProfLevelCostDB.includeQuestRecipes == true) and "Yes" or "No"))
    table.insert(lines, "Include Vendor: " .. ((ProfLevelCostDB.includeVendorRecipes == true) and "Yes" or "No"))
    table.insert(lines, string.format("Show N cheapest options: %d (chosen + %d alternative%s)",
      showN, showAlternatives, showAlternatives == 1 and "" or "s"))
    table.insert(lines, "")
  else
    table.insert(lines, string.format("Show N cheapest options: %d (chosen + %d alternative%s)",
      showN, showAlternatives, showAlternatives == 1 and "" or "s"))
    table.insert(lines, "")
  end

  table.insert(lines, "TOTAL (priced items only): " .. copperToString(total))
  table.insert(lines, "")

  -- Collapse consecutive steps that pick the same chosen recipe.
  -- We keep the original member steps so we can do "accurate" alternatives per-member,
  -- then collapse those too for display.
  local function collapseChosen(details)
    local out = {}
    local cur = nil

    local function sameChoice(a, b)
      return a and b
        and a.option == b.option
        and (a.optionSource or "") == (b.optionSource or "")
        and (a.optionNote or "") == (b.optionNote or "")
    end

    local function pushCur()
      if cur then table.insert(out, cur) end
      cur = nil
    end

    for _, sd in ipairs(details or {}) do
      local canCollapse = (sd and (sd.crafts or 0) > 0 and sd.option)

      if not canCollapse then
        pushCur()
        table.insert(out, sd)
      else
        if cur and cur._collapsed and sameChoice(cur, sd) then
          cur._rangeTo = sd.bracketTo or cur._rangeTo
          cur.crafts = (cur.crafts or 0) + (sd.crafts or 0)
          cur.stepCost = (cur.stepCost or 0) + (sd.stepCost or 0)
          cur.craftsMin = (cur.craftsMin or 0) + (sd.craftsMin or 0)
          cur.craftsExp = (cur.craftsExp or 0) + (sd.craftsExp or 0)
          cur.craftsMax = (cur.craftsMax or 0) + (sd.craftsMax or 0)

          -- Track members (for accurate alternative collapsing)
          table.insert(cur._members, sd)

          -- Aggregate reagent needs (total quantity, not per-craft)
          local map = cur._reagentTotals
          for _, r in ipairs(sd.reagents or {}) do
            local id = tonumber(r.id)
            local per = tonumber(r.per) or 0
            if id and per > 0 then
              map[id] = (map[id] or 0) + (per * (sd.crafts or 0))
            end
          end

          cur._lastIndex = sd.index or cur._lastIndex
        else
          pushCur()

          cur = sd
          cur._collapsed = true
          cur._rangeFrom = sd.bracketFrom
          cur._rangeTo   = sd.bracketTo
          cur._lastIndex = sd.index
          cur._members   = { sd }

          cur.craftsMin = sd.craftsMin
          cur.craftsExp = sd.craftsExp
          cur.craftsMax = sd.craftsMax

          cur._reagentTotals = {}

          -- Carry crafted-reagent decisions into the collapsed group
          cur.craftedReagents = {}
          if sd.craftedReagents and #sd.craftedReagents > 0 then
            for _, cr in ipairs(sd.craftedReagents) do
              table.insert(cur.craftedReagents, cr)
            end
          end

          for _, r in ipairs(sd.reagents or {}) do
            local id = tonumber(r.id)
            local per = tonumber(r.per) or 0
            if id and per > 0 then
              cur._reagentTotals[id] = (cur._reagentTotals[id] or 0) + (per * (sd.crafts or 0))
            end
          end
        end
      end
    end

    pushCur()
    return out
  end

  local function compactMatsFromTotals(totals)
    local rows = {}
    for id, qty in pairs(totals or {}) do
      qty = tonumber(qty) or 0
      if qty > 0 then table.insert(rows, { id=id, qty=qty }) end
    end
    table.sort(rows, function(a,b) return a.id < b.id end)

    if #rows == 0 then
      return "Mats: (none)"
    end

    local parts = {}
    local maxParts = math.min(#rows, 8)
    for i = 1, maxParts do
      local r = rows[i]
      table.insert(parts, string.format("%s x%d", safeItemName(r.id), r.qty))
    end
    local out = table.concat(parts, ", ")
    if #rows > maxParts then out = out .. ", …" end
    return "Mats: " .. out
  end

  local function totalsToFullBreakdown(totals)
    local tmp = {}
    for id, qty in pairs(totals or {}) do
      qty = tonumber(qty) or 0
      if qty > 0 then
        local unit = getUnitPrice(id)
        local cost = unit and (unit * qty) or nil
        table.insert(tmp, {
          id = tonumber(id),
          per = 0,
          crafts = 0,
          total = qty,
          fromInv = 0,
          toBuy = qty,
          unit = unit,
          cost = cost,
        })
      end
    end
    table.sort(tmp, function(a,b) return a.id < b.id end)
    return tmp
  end

  local function totalsHasMissingPrices(totals)
    for id, qty in pairs(totals or {}) do
      qty = tonumber(qty) or 0
      if qty > 0 then
        local unit = getUnitPrice(id)
        if not unit then
          return true
        end
      end
    end
    return false
  end


  local function pickAltForMember(member, rank)
    local comps = member and member.optimizerComparisons
    if not comps or #comps == 0 then return nil end

    local alts = {}
    for _, c in ipairs(comps) do
      if c.considered and c.idx ~= member.chosenIdx and c.cost and c.cost < math.huge then
        table.insert(alts, c)
      end
    end
    if #alts == 0 then return nil end

table.sort(alts, function(a,b)
  local am = a.missingItems or 0
  local bm = b.missingItems or 0
  if am ~= bm then return am < bm end
  local aq = a.missingQty or 0
  local bq = b.missingQty or 0
  if aq ~= bq then return aq < bq end
  local ac = a.cost or math.huge
  local bc = b.cost or math.huge
  if ac == bc then return (a.idx or 0) < (b.idx or 0) end
  return ac < bc
end)

    return alts[rank]
  end

  local function sameAlt(a, b)
    return a and b
      and (a.label or "") == (b.label or "")
      and (a.source or "") == (b.source or "")
      and (a.note or "") == (b.note or "")
  end

  local function buildAltSegments(members, rank)
    local segments = {}
    local cur = nil

    local function pushCur()
      if cur then table.insert(segments, cur) end
      cur = nil
    end

    for _, m in ipairs(members or {}) do
      local alt = pickAltForMember(m, rank)
      if alt then
        if cur and sameAlt(cur.alt, alt) then
          cur.to = m.bracketTo or cur.to
          cur.crafts = (cur.crafts or 0) + (alt.crafts or 0)
          cur.cost = (cur.cost or 0) + (alt.cost or 0)
          table.insert(cur._members, { member=m, alt=alt })
        else
          pushCur()
          cur = {
            from = m.bracketFrom,
            to = m.bracketTo,
            alt = alt,
            crafts = alt.crafts or 0,
            cost = alt.cost or 0,
            _members = { { member=m, alt=alt } },
          }
        end
      else
        -- break segments if this member has no alternative at this rank
        pushCur()
      end
    end

    pushCur()
    return segments
  end

  local function computeAltTotalsForSegment(seg)
    local totals = {}
    local missing = {}
    local cost = 0

    for _, pair in ipairs(seg._members or {}) do
      local member = pair.member
      local alt = pair.alt
      local invStart = member and member.invStart or {}

      local miss = {}
      local breakdown, stepCost = buildCandidateBreakdown(alt.reagents or {}, alt.crafts or 0, invStart, miss)
      cost = cost + (stepCost or 0)

      for _, r in ipairs(breakdown or {}) do
        local toBuy = tonumber(r.toBuy) or 0
        if toBuy > 0 then
          totals[r.id] = (totals[r.id] or 0) + toBuy
        end
      end
      for id in pairs(miss) do
        missing[id] = true
      end
    end

    return totals, missing, cost
  end

  local collapsed = collapseChosen(stepDetails or {})
  local displayIndex = 0

  for _, entry in ipairs(collapsed) do
    if (entry.crafts or 0) <= 0 then
      table.insert(lines, string.format("%d) %s", entry.index or 0, entry.label or ""))
      local comps = entry.optimizerComparisons
      if comps and #comps > 0 then
        table.insert(lines, "   Candidates:")
        for _, c in ipairs(comps) do
          local name = formatRecipe(c.label, c.source, c.note)
          if (ProfLevelCostDB.includeRepRecipes == true) and (not c.usable) then
            table.insert(lines, string.format("     - %s: |cffff3333UNAVAILABLE|r (%s)", name, c.usableReason or "gated"))
          else
            table.insert(lines, string.format("     - %s", name))
          end
        end
      end
      table.insert(lines, "")
    else
      displayIndex = displayIndex + 1

      local rangeFrom = entry._rangeFrom or entry.bracketFrom
      local rangeTo   = entry._rangeTo   or entry.bracketTo
      local rangeText = (rangeFrom and rangeTo) and string.format("%d-%d", rangeFrom, rangeTo) or (entry.bracketLabel or "")

      local header = string.format("%d) %s  (crafts: %d)", displayIndex, rangeText, entry.crafts or 0)
      if entry.option then
        header = header .. string.format("  |cff66ff66[%s]|r", formatRecipe(entry.option, entry.optionSource, entry.optionNote))
      end
      if entry.craftsMin and entry.craftsExp and entry.craftsMax then
        header = header .. string.format("  |cffaaaaaa[range %d/%d/%d]|r", entry.craftsMin, entry.craftsExp, entry.craftsMax)
      end
      table.insert(lines, header)

      -- Chosen mats display
      local invStart = entry.invStart or {}
      if compact then
        local totals = entry._reagentTotals or {}
        table.insert(lines, "   " .. compactMatsFromTotals(totals))
        do
        local missing = totalsHasMissingPrices(totals)
        local base = entry.stepCost or 0
        local costStr = missing and "|cffff3333N/A (missing prices)|r" or copperToString(base)
        local suffix = missing and "  |cffff3333(+ missing prices)|r" or ""
        table.insert(lines, string.format("   Step cost (chosen, priced items only): %s%s", costStr, suffix))

		if entry.craftedReagents and #entry.craftedReagents > 0 then
          table.insert(lines, "   Crafted reagents (cheaper than buying):")
          local agg = {}
		  for _, cr in ipairs(entry.craftedReagents) do
            local key = tostring(cr.itemID or 0) .. "|" .. tostring(cr.recipeLabel or "")
            local a = agg[key]
            if not a then
              a = {
                itemID = cr.itemID,
                qty = 0,
                crafts = 0,
                recipeLabel = cr.recipeLabel,
                recipeSource = cr.recipeSource,
                recipeNote = cr.recipeNote,
              }
              agg[key] = a
            end
            a.qty = (a.qty or 0) + (tonumber(cr.qty) or 0)
            a.crafts = (a.crafts or 0) + (tonumber(cr.crafts) or 0)
          end
          local rows = {}
          for _, a in pairs(agg) do table.insert(rows, a) end
          table.sort(rows, function(x, y)
            if (x.itemID or 0) == (y.itemID or 0) then
              return tostring(x.recipeLabel or "") < tostring(y.recipeLabel or "")
            end
            return (x.itemID or 0) < (y.itemID or 0)
          end)
          for _, a in ipairs(rows) do
            table.insert(lines, string.format("     - %s x%d via %s",
              safeItemName(a.itemID), a.qty, formatRecipe(a.recipeLabel, a.recipeSource, a.recipeNote)))
          end
        end

      end
      else
        table.insert(lines, "   Reagents (chosen):")
        local totals = entry._reagentTotals or {}
        local bd = totalsToFullBreakdown(totals)
        -- For full breakdown we prefer showing totals (buy list) since inventory is already accounted for in totals
        for _, r in ipairs(bd) do
          local nm = safeItemName(r.id)
          local line = string.format("     - %s: x%d", nm, r.toBuy or 0)
          if r.unit then
            line = line .. string.format("  @ %s = %s", copperToString(r.unit), copperToString(r.cost))
          else
            line = line .. "  = |cffff3333NO PRICE|r"
          end
          table.insert(lines, line)
        end
        do
        local missing = totalsHasMissingPrices(totals)
        local base = entry.stepCost or 0
        local costStr = (missing and base == 0) and "N/A" or copperToString(base)
        local suffix = missing and "  |cffff3333(+ missing prices)|r" or ""
        table.insert(lines, string.format("   Step cost (chosen, priced items only): %s%s", costStr, suffix))

		if entry.craftedReagents and #entry.craftedReagents > 0 then
          table.insert(lines, "   Crafted reagents (cheaper than buying):")
          local agg = {}
		  for _, cr in ipairs(entry.craftedReagents) do
            local key = tostring(cr.itemID or 0) .. "|" .. tostring(cr.recipeLabel or "")
            local a = agg[key]
            if not a then
              a = {
                itemID = cr.itemID,
                qty = 0,
                crafts = 0,
                recipeLabel = cr.recipeLabel,
                recipeSource = cr.recipeSource,
                recipeNote = cr.recipeNote,
              }
              agg[key] = a
            end
            a.qty = (a.qty or 0) + (tonumber(cr.qty) or 0)
            a.crafts = (a.crafts or 0) + (tonumber(cr.crafts) or 0)
          end
          local rows = {}
          for _, a in pairs(agg) do table.insert(rows, a) end
          table.sort(rows, function(x, y)
            if (x.itemID or 0) == (y.itemID or 0) then
              return tostring(x.recipeLabel or "") < tostring(y.recipeLabel or "")
            end
            return (x.itemID or 0) < (y.itemID or 0)
          end)
          for _, a in ipairs(rows) do
            table.insert(lines, string.format("     - %s x%d via %s",
              safeItemName(a.itemID), a.qty, formatRecipe(a.recipeLabel, a.recipeSource, a.recipeNote)))
          end
        end

      end
      end

      -- Alternatives (accurate): compute per-member, then collapse consecutive same-alt runs
      if showAlternatives > 0 and entry._members and #entry._members > 0 then
        for rank = 1, showAlternatives do
          local segments = buildAltSegments(entry._members, rank)
          for si, seg in ipairs(segments) do
            local totals, miss, segCost = computeAltTotalsForSegment(seg)

            table.insert(lines, "")
            local segRange = (seg.from and seg.to) and string.format("%d-%d", seg.from, seg.to) or rangeText
local hasMissing = (miss and next(miss) ~= nil) or false
local costStr = hasMissing and "N/A" or copperToString(segCost or 0)
local costSuffix = hasMissing and "  |cffff3333(+ missing prices)|r" or ""

table.insert(lines, string.format("   Alternative #%d%s: |cff66ccff%s|r  (%s)  (est: %s)%s",
  rank,
  (#segments > 1) and ("." .. si) or "",
  formatRecipe(seg.alt.label, seg.alt.source, seg.alt.note),
  segRange,
  costStr,
  costSuffix
))

            if compact then
              table.insert(lines, "   " .. compactMatsFromTotals(totals))
            else
              table.insert(lines, "   Reagents (alternative):")
              local bd = totalsToFullBreakdown(totals)
              for _, r in ipairs(bd) do
                local nm = safeItemName(r.id)
                local line = string.format("     - %s: x%d", nm, r.toBuy or 0)
                if r.unit then
                  line = line .. string.format("  @ %s = %s", copperToString(r.unit), copperToString(r.cost))
                else
                  line = line .. "  = |cffff3333NO PRICE|r"
                end
                table.insert(lines, line)
              end
			  local missing = (miss and next(miss) ~= nil)
			  local base = segCost or 0
			  local costStr = missing and "N/A" or copperToString(base)
			  local suffix = missing and "  |cffff3333(+ missing prices)|r" or ""
			  table.insert(lines, string.format("   Step cost (alternative, priced items only): %s%s", costStr, suffix))

              local missCount = 0
              for _ in pairs(miss or {}) do missCount = missCount + 1 end
              if missCount > 0 then
                table.insert(lines, string.format("   |cffff3333Alternative missing prices for %d item(s).|r", missCount))
              end
            end
          end
        end
      end

      table.insert(lines, "")
    end
  end

  local missingCount = 0
  for _ in pairs(missingPrice) do missingCount = missingCount + 1 end
  if missingCount > 0 then
    table.insert(lines, "Missing prices overall:")
    local miss = {}
    for id in pairs(missingPrice) do table.insert(miss, id) end
    table.sort(miss)
    for _, id in ipairs(miss) do
      table.insert(lines, string.format("  - %s (%d)", safeItemName(id), id))
    end
  end

  return table.concat(lines, "\n")
end
-- =========================================================

-- =========================================================
-- Exports used by the UI / Events modules
-- =========================================================
PLC.AuctionatorReady     = AuctionatorReady
PLC.GetUnitPrice         = getUnitPrice
PLC.IsOptimizerPlan      = isOptimizerPlan
PLC.FindPlanByName       = findPlanByName
PLC.ListPlanNamesSorted  = listPlanNamesSorted
PLC.BuildSummaryReport   = buildSummaryReport
PLC.BuildRecipesReport   = buildRecipesReport
