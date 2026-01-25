-- ProfLevelCost_UI.lua
-- UI only: frame, controls, rendering.
-- Depends on ProfLevelCost_Init.lua + ProfLevelCost_Core.lua.

local PLC = _G.ProfLevelCost

-- Imports from other modules
local clampInt         = PLC.ClampInt
local isCompact        = PLC.IsCompact
local detailsLabel     = PLC.DetailsLabel
local modeLabel        = PLC.ModeLabel
local formatRecipe     = PLC.FormatRecipe
local isOptimizerPlan  = PLC.IsOptimizerPlan
local findPlanByName   = PLC.FindPlanByName
local listPlanNamesSorted = PLC.ListPlanNamesSorted
local AuctionatorReady = PLC.AuctionatorReady
local buildSummaryReport = PLC.BuildSummaryReport
local buildRecipesReport = PLC.BuildRecipesReport

-- UI
-- =========================================================
local UI = {
  frame=nil, planLabel=nil, statusLabel=nil, outputBox=nil,
  selectedPlanName=nil, view=nil, btnSummary=nil, btnRecipes=nil,
  optDropdown=nil, optDropdownText=nil,
  filterCheck=nil, filterText=nil,
  dropCheck=nil, dropText=nil,
  questCheck=nil, questText=nil,
  vendorCheck=nil, vendorText=nil,
  craftReagentCheck=nil, craftReagentText=nil,
  nDropdown=nil, nDropdownText=nil,
  detailsBtn=nil,
}

local function UI_SetOutput(text)
  if not UI.outputBox then return end
  UI.outputBox:SetText(text or "")
  UI.outputBox:SetCursorPosition(0)
end

local function UI_UpdateStatus()
  if not UI.statusLabel then return end
  if AuctionatorReady() then
    UI.statusLabel:SetText("Price source: Auctionator (last scanned)  |cff66ff66READY|r")
  else
    UI.statusLabel:SetText("Price source: Auctionator  |cffff6666NOT READY|r (install/enable Auctionator)")
  end
end

local function UI_SetView(view)
  view = view or "summary"
  UI.view = view
  ProfLevelCostDB.lastView = view

  if UI.btnSummary and UI.btnRecipes then
    if view == "summary" then
      UI.btnSummary:SetEnabled(false)
      UI.btnRecipes:SetEnabled(true)
    else
      UI.btnSummary:SetEnabled(true)
      UI.btnRecipes:SetEnabled(false)
    end
  end
end

local function UI_SelectPlan(name)
  UI.selectedPlanName = name
  ProfLevelCostDB.lastPlanName = name
  if UI.planLabel then UI.planLabel:SetText(name or "(none)") end
end

local function UI_GetSelectedPlan()
  local planName = UI.selectedPlanName or ProfLevelCostDB.lastPlanName
  if not planName or planName == "" then return nil end
  return findPlanByName(planName)
end

local function UI_UpdateOptimizeControl()
  local plan = UI_GetSelectedPlan()
  local enabled = isOptimizerPlan(plan)

  if UI.optDropdown then
    if enabled then
      UIDropDownMenu_EnableDropDown(UI.optDropdown)
      if UI.optDropdownText then UI.optDropdownText:SetTextColor(1,1,1) end
    else
      UIDropDownMenu_DisableDropDown(UI.optDropdown)
      if UI.optDropdownText then UI.optDropdownText:SetTextColor(0.6,0.6,0.6) end
    end
    UIDropDownMenu_SetText(UI.optDropdown, modeLabel(ProfLevelCostDB.optimizeMode or "exp"))
  end

  if UI.filterCheck and UI.filterText then
    UI.filterCheck:SetChecked(ProfLevelCostDB.includeRepRecipes == true)
    if enabled then
      UI.filterCheck:Enable()
      UI.filterText:SetTextColor(1,1,1)
    else
      UI.filterCheck:Disable()
      UI.filterText:SetTextColor(0.6,0.6,0.6)
    end
  end

  local dropEnabled = enabled
  if UI.dropCheck and UI.dropText then
    UI.dropCheck:SetChecked(ProfLevelCostDB.includeDropRecipes == true)
    if dropEnabled then
      UI.dropCheck:Enable()
      UI.dropText:SetTextColor(1,1,1)
    else
      UI.dropCheck:Disable()
      UI.dropText:SetTextColor(0.6,0.6,0.6)
    end
  end

  local questEnabled = enabled
  if UI.questCheck and UI.questText then
    UI.questCheck:SetChecked(ProfLevelCostDB.includeQuestRecipes == true)
    if questEnabled then
      UI.questCheck:Enable()
      UI.questText:SetTextColor(1,1,1)
    else
      UI.questCheck:Disable()
      UI.questText:SetTextColor(0.6,0.6,0.6)
    end

  if UI.vendorCheck and UI.vendorText then
    UI.vendorCheck:SetChecked(ProfLevelCostDB.includeVendorRecipes == true)
    if enabled then
      UI.vendorCheck:Enable()
      UI.vendorText:SetTextColor(1,1,1)
    else
      UI.vendorCheck:Disable()
      UI.vendorText:SetTextColor(0.6,0.6,0.6)
    end

  if UI.craftReagentCheck and UI.craftReagentText then
    UI.craftReagentCheck:SetChecked(ProfLevelCostDB.expandCraftedReagents ~= false)
    UI.craftReagentCheck:Enable()
    UI.craftReagentText:SetTextColor(1,1,1)
    UI.craftReagentText:SetText(isCompact() and "Craft mats" or "Expand cheaper-crafted reagents")
  end

  end
  end

  if UI.nDropdown then
    if enabled then
      UIDropDownMenu_EnableDropDown(UI.nDropdown)
      if UI.nDropdownText then UI.nDropdownText:SetTextColor(1,1,1) end
    else
      UIDropDownMenu_DisableDropDown(UI.nDropdown)
      if UI.nDropdownText then UI.nDropdownText:SetTextColor(0.6,0.6,0.6) end
    end
    local n = clampInt(ProfLevelCostDB.showNCheapest or 2, 1, 10, 2)
    UIDropDownMenu_SetText(UI.nDropdown, tostring(n))
  end

  if UI.detailsBtn then
    UI.detailsBtn:SetText(detailsLabel())
  end

    if UI.filterText then
    UI.filterText:SetText(isCompact() and "Rep" or "Include reputation recipes")
  end
  if UI.dropText then
    UI.dropText:SetText(isCompact() and "Drops" or "Include Drop/AH recipes")
  end
  if UI.questText then
    UI.questText:SetText(isCompact() and "Quests" or "Include Quest recipes")
  end
  if UI.vendorText then
    UI.vendorText:SetText(isCompact() and "Vendors" or "Include Vendor recipes")
  end
end

local function UI_Recalculate()
  local plan = UI_GetSelectedPlan()
  if not plan then
    UI_SetOutput("Pick a plan first.")
    UI_UpdateOptimizeControl()
    return
  end

  UI_UpdateOptimizeControl()

  local view = UI.view or ProfLevelCostDB.lastView or "summary"
  local report = (view == "recipes") and buildRecipesReport(plan) or buildSummaryReport(plan)
  UI_SetOutput(report)
end

local function UI_Create()
  if UI.frame then return end

  local f = CreateFrame("Frame", "ProfLevelCostFrame", UIParent, "BackdropTemplate")
  f:SetSize(740, 620)
  f:SetPoint("CENTER")
  f:SetBackdrop({
    bgFile="Interface/Tooltips/UI-Tooltip-Background",
    edgeFile="Interface/Tooltips/UI-Tooltip-Border",
    tile=true, tileSize=16, edgeSize=16,
    insets={left=4, right=4, top=4, bottom=4},
  })
  f:SetBackdropColor(0, 0, 0, 0.92)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -12)
  title:SetText("ProfLevelCost")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", 16, -36)
  status:SetJustifyH("LEFT")
  UI.statusLabel = status

  local btnSummary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnSummary:SetSize(120, 22)
  btnSummary:SetPoint("TOPLEFT", 16, -58)
  btnSummary:SetText("Summary")
  btnSummary:SetScript("OnClick", function()
    UI_SetView("summary")
    UI_Recalculate()
  end)
  UI.btnSummary = btnSummary

  local btnRecipes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btnRecipes:SetSize(120, 22)
  btnRecipes:SetPoint("LEFT", btnSummary, "RIGHT", 8, 0)
  btnRecipes:SetText("Recipes")
  btnRecipes:SetScript("OnClick", function()
    UI_SetView("recipes")
    UI_Recalculate()
  end)
  UI.btnRecipes = btnRecipes

  -- OPTIONS BAR (two-row layout: never overlaps even with full labels)
  local optionsBar = CreateFrame("Frame", nil, f)
  optionsBar:SetPoint("TOPLEFT", btnSummary, "BOTTOMLEFT", 0, -6)
  optionsBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, 0)
  optionsBar:SetHeight(82)

  -- Row 1: Left = Optimize, Right = Details + Show N
  local row1 = CreateFrame("Frame", nil, optionsBar)
  row1:SetPoint("TOPLEFT", optionsBar, "TOPLEFT", 0, 0)
  row1:SetPoint("TOPRIGHT", optionsBar, "TOPRIGHT", 0, 0)
  row1:SetHeight(26)

  local row2 = CreateFrame("Frame", nil, optionsBar)
  row2:SetPoint("TOPLEFT", row1, "BOTTOMLEFT", 0, -2)
  row2:SetPoint("TOPRIGHT", row1, "BOTTOMRIGHT", 0, -2)
  row2:SetHeight(26)

  local row3 = CreateFrame("Frame", nil, optionsBar)
  row3:SetPoint("TOPLEFT", row2, "BOTTOMLEFT", 0, -2)
  row3:SetPoint("TOPRIGHT", row2, "BOTTOMRIGHT", 0, -2)
  row3:SetHeight(26)

  -- RIGHT group on Row 1
  local rightGroup = CreateFrame("Frame", nil, row1)
  rightGroup:SetPoint("RIGHT", row1, "RIGHT", 0, 0)
  rightGroup:SetSize(250, 26)

  -- Show N label
  local nText = rightGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nText:SetPoint("RIGHT", rightGroup, "RIGHT", -92, 0)
  nText:SetText("Show N:")
  UI.nDropdownText = nText

  -- Show N dropdown (right-anchored)
  local nDD = CreateFrame("Frame", "ProfLevelCostShowNDropdown", rightGroup, "UIDropDownMenuTemplate")
  nDD:SetPoint("RIGHT", rightGroup, "RIGHT", 18, -2) -- template padding
  UIDropDownMenu_SetWidth(nDD, 50)
  UI.nDropdown = nDD

  local function setShowN(n)
    ProfLevelCostDB.showNCheapest = clampInt(n, 1, 10, 2)
    UIDropDownMenu_SetText(nDD, tostring(ProfLevelCostDB.showNCheapest))
    UI_Recalculate()
  end

  UIDropDownMenu_Initialize(nDD, function(_, level)
    local info = UIDropDownMenu_CreateInfo()
    info.func = function(selfArg) setShowN(selfArg.value) end
    for _, v in ipairs({1,2,3,4,5}) do
      info.text = tostring(v)
      info.value = v
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  UIDropDownMenu_SetText(nDD, tostring(clampInt(ProfLevelCostDB.showNCheapest or 2, 1, 10, 2)))

  -- Details toggle button (to the left of Show N)
  local detailsBtn = CreateFrame("Button", nil, rightGroup, "UIPanelButtonTemplate")
  detailsBtn:SetSize(64, 20)
  detailsBtn:SetPoint("RIGHT", nText, "LEFT", -10, 0)
  detailsBtn:SetText(detailsLabel())
  detailsBtn:SetScript("OnClick", function()
    ProfLevelCostDB.detailsMode = isCompact() and "full" or "compact"
    UI_UpdateOptimizeControl()
    UI_Recalculate()
  end)
  UI.detailsBtn = detailsBtn

  detailsBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(detailsBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Details mode", 1, 1, 1)
    GameTooltip:AddLine("Full: per-item pricing math.\nCompact: short mats list per step.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  detailsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- LEFT group on Row 1 (Optimize)
  local leftGroup = CreateFrame("Frame", nil, row1)
  leftGroup:SetPoint("LEFT", row1, "LEFT", 0, 0)
  leftGroup:SetPoint("RIGHT", rightGroup, "LEFT", -10, 0)
  leftGroup:SetHeight(26)

  local optText = leftGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  optText:SetPoint("LEFT", leftGroup, "LEFT", 0, 0)
  optText:SetText("Optimize:")
  UI.optDropdownText = optText

  local optDD = CreateFrame("Frame", "ProfLevelCostOptimizeDropdown", leftGroup, "UIDropDownMenuTemplate")
  optDD:SetPoint("LEFT", optText, "RIGHT", 6, -2)
  UIDropDownMenu_SetWidth(optDD, 115)
  UI.optDropdown = optDD

  local function setMode(mode)
    ProfLevelCostDB.optimizeMode = mode
    UIDropDownMenu_SetText(optDD, modeLabel(mode))
    UI_Recalculate()
  end

  UIDropDownMenu_Initialize(optDD, function(_, level)
    local info = UIDropDownMenu_CreateInfo()
    info.func = function(selfArg) setMode(selfArg.value) end
    info.text, info.value = "Best", "min"; UIDropDownMenu_AddButton(info, level)
    info.text, info.value = "Expected", "exp"; UIDropDownMenu_AddButton(info, level)
    info.text, info.value = "Worst", "max"; UIDropDownMenu_AddButton(info, level)
  end)
  UIDropDownMenu_SetText(optDD, modeLabel(ProfLevelCostDB.optimizeMode or "exp"))

  -- Row 2: Checkboxes (full labels allowed, no overlap)
  local filter = CreateFrame("CheckButton", nil, row2, "UICheckButtonTemplate")
  filter:SetPoint("LEFT", row2, "LEFT", 0, 0)
  filter:SetSize(24, 24)
  filter:SetChecked(ProfLevelCostDB.includeRepRecipes == true)
  filter:SetScript("OnClick", function(self)
    ProfLevelCostDB.includeRepRecipes = self:GetChecked() and true or false
    UI_Recalculate()
  end)
  UI.filterCheck = filter

  local filterText = row2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  filterText:SetPoint("LEFT", filter, "RIGHT", 2, 0)
  filterText:SetJustifyH("LEFT")
  filterText:SetWordWrap(false)
  UI.filterText = filterText

  local drop = CreateFrame("CheckButton", nil, row2, "UICheckButtonTemplate")
  drop:SetPoint("LEFT", filterText, "RIGHT", 18, 0)
  drop:SetSize(24, 24)
  drop:SetChecked(ProfLevelCostDB.includeDropRecipes == true)
  drop:SetScript("OnClick", function(self)
    ProfLevelCostDB.includeDropRecipes = self:GetChecked() and true or false
    UI_Recalculate()
  end)
  UI.dropCheck = drop

  local dropText = row2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  dropText:SetPoint("LEFT", drop, "RIGHT", 2, 0)
  dropText:SetJustifyH("LEFT")
  dropText:SetWordWrap(false)
  UI.dropText = dropText

  local quest = CreateFrame("CheckButton", nil, row2, "UICheckButtonTemplate")
  quest:SetPoint("LEFT", dropText, "RIGHT", 18, 0)
  quest:SetSize(24, 24)
  quest:SetChecked(ProfLevelCostDB.includeQuestRecipes == true)
  quest:SetScript("OnClick", function(self)
    ProfLevelCostDB.includeQuestRecipes = self:GetChecked() and true or false
    UI_Recalculate()
  end)
  UI.questCheck = quest

  local questText = row2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  questText:SetPoint("LEFT", quest, "RIGHT", 2, 0)
  questText:SetJustifyH("LEFT")
  questText:SetWordWrap(false)
  UI.questText = questText

  -- Vendor recipes toggle (separate row to avoid overlap)
  local vendor = CreateFrame("CheckButton", nil, row3, "UICheckButtonTemplate")
  vendor:SetPoint("LEFT", row3, "LEFT", 0, 0)
  vendor:SetSize(24, 24)
  vendor:SetChecked(ProfLevelCostDB.includeVendorRecipes == true)
  vendor:SetScript("OnClick", function(self)
    ProfLevelCostDB.includeVendorRecipes = self:GetChecked() and true or false
    UI_Recalculate()
  end)
  UI.vendorCheck = vendor

  local vendorText = row3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  vendorText:SetPoint("LEFT", vendor, "RIGHT", 2, 0)
  vendorText:SetJustifyH("LEFT")
  vendorText:SetWordWrap(false)
  UI.vendorText = vendorText

  -- Expand cheaper-crafted reagents toggle
  local craftR = CreateFrame("CheckButton", nil, row3, "UICheckButtonTemplate")
  craftR:SetPoint("LEFT", vendorText, "RIGHT", 18, 0)
  craftR:SetSize(24, 24)
  craftR:SetChecked(ProfLevelCostDB.expandCraftedReagents ~= false)
  craftR:SetScript("OnClick", function(self)
    ProfLevelCostDB.expandCraftedReagents = self:GetChecked() and true or false
    UI_Recalculate()
  end)
  UI.craftReagentCheck = craftR

  local craftRText = row3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  craftRText:SetPoint("LEFT", craftR, "RIGHT", 2, 0)
  craftRText:SetJustifyH("LEFT")
  craftRText:SetWordWrap(false)
  UI.craftReagentText = craftRText

  craftR:SetScript("OnEnter", function()
    GameTooltip:SetOwner(craftR, "ANCHOR_RIGHT")
    GameTooltip:SetText("Cheaper-crafted reagents", 1, 1, 1)
    GameTooltip:AddLine("If a reagent can be crafted (from this profession) for less than buying it,\nwe expand it into its base mats for cost + optimizer.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  craftR:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Tooltips
  filter:SetScript("OnEnter", function()
    GameTooltip:SetOwner(filter, "ANCHOR_RIGHT")
    GameTooltip:SetText("Include reputation recipes", 1, 1, 1)
    GameTooltip:AddLine("Include recipes that require reputation, only works if vendor recipes are allowed", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  filter:SetScript("OnLeave", function() GameTooltip:Hide() end)

  drop:SetScript("OnEnter", function()
    GameTooltip:SetOwner(drop, "ANCHOR_RIGHT")
    GameTooltip:SetText("Include Drop/AH recipes", 1, 1, 1)
    GameTooltip:AddLine("When filtering usable recipes, allow recipes marked Drop/AH.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  drop:SetScript("OnLeave", function() GameTooltip:Hide() end)

  quest:SetScript("OnEnter", function()
    GameTooltip:SetOwner(quest, "ANCHOR_RIGHT")
    GameTooltip:SetText("Include Quest recipes", 1, 1, 1)
    GameTooltip:AddLine("When filtering usable recipes, allow recipes marked Quest.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  quest:SetScript("OnLeave", function() GameTooltip:Hide() end)

  vendor:SetScript("OnEnter", function()
    GameTooltip:SetOwner(vendor, "ANCHOR_RIGHT")
    GameTooltip:SetText("Include Vendor recipes", 1, 1, 1)
    GameTooltip:AddLine("Include recipes that come from vendors", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  vendor:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Apply initial label mode (short vs long labels)
  UI.filterText:SetText(isCompact() and "Rep" or "Include reputation recipes")
  UI.dropText:SetText(isCompact() and "Drops" or "Include Drop/AH recipes")


  -- Tooltips for checkboxes
  filter:SetScript("OnEnter", function()
    GameTooltip:SetOwner(filter, "ANCHOR_RIGHT")
    GameTooltip:SetText("Include reputation recipes", 1, 1, 1)
    GameTooltip:AddLine("Exclude recipes that require reputation (per note text).", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  filter:SetScript("OnLeave", function() GameTooltip:Hide() end)

  drop:SetScript("OnEnter", function()
    GameTooltip:SetOwner(drop, "ANCHOR_RIGHT")
    GameTooltip:SetText("Include Drop/AH recipes", 1, 1, 1)
    GameTooltip:AddLine("When filtering usable recipes, allow recipes marked Drop/AH.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  drop:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Set initial texts (compact/full)
  UI.filterText:SetText(isCompact() and "Rep" or "Include reputation recipes")
  UI.dropText:SetText(isCompact() and "Drops" or "Include Drop/AH recipes")

  UIDropDownMenu_SetText(nDD, tostring(clampInt(ProfLevelCostDB.showNCheapest or 2, 1, 10, 2)))

  -- Tooltips
  filter:SetScript("OnEnter", function()
    GameTooltip:SetOwner(filter, "ANCHOR_RIGHT")
    GameTooltip:SetText("Include reputation recipes", 1, 1, 1)
    GameTooltip:AddLine("Exclude recipes that require reputation (per note text).", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  filter:SetScript("OnLeave", function() GameTooltip:Hide() end)

  drop:SetScript("OnEnter", function()
    GameTooltip:SetOwner(drop, "ANCHOR_RIGHT")
    GameTooltip:SetText("Include Drop/AH recipes", 1, 1, 1)
    GameTooltip:AddLine("When filtering usable recipes, allow recipes marked Drop/AH.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  drop:SetScript("OnLeave", function() GameTooltip:Hide() end)

  detailsBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(detailsBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Details mode", 1, 1, 1)
    GameTooltip:AddLine("Full: per-item pricing math.\nCompact: short mats list per step.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  detailsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- PLAN ROW (anchored under optionsBar)
  local planText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  planText:SetPoint("TOPLEFT", optionsBar, "BOTTOMLEFT", 0, -10)
  planText:SetText("Plan:")

  local planValue = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  planValue:SetPoint("LEFT", planText, "RIGHT", 6, 0)
  planValue:SetText("(none)")
  UI.planLabel = planValue

  local dd = CreateFrame("Frame", "ProfLevelCostPlanDropdown", f, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", planText, "BOTTOMLEFT", -2, -6)
  UIDropDownMenu_SetWidth(dd, 520)
  UIDropDownMenu_SetText(dd, "Select a plan...")

  local function dropdownOnClick(selfArg)
    UI_SelectPlan(selfArg.value)
    UIDropDownMenu_SetText(dd, selfArg.value)
    UI_Recalculate()
  end

  UIDropDownMenu_Initialize(dd, function(_, level)
    local info = UIDropDownMenu_CreateInfo()
    info.func = dropdownOnClick
    for _, name in ipairs(listPlanNamesSorted()) do
      info.text = name
      info.value = name
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  local calcBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  calcBtn:SetSize(140, 24)
  calcBtn:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 2, -8)
  calcBtn:SetText("Calculate")
  calcBtn:SetScript("OnClick", function() UI_Recalculate() end)

  local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  refreshBtn:SetSize(140, 24)
  refreshBtn:SetPoint("LEFT", calcBtn, "RIGHT", 10, 0)
  refreshBtn:SetText("Refresh Status")
  refreshBtn:SetScript("OnClick", function() UI_UpdateStatus() end)

  local scrollFrame = CreateFrame("ScrollFrame", "ProfLevelCostScrollFrame", f, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", calcBtn, "BOTTOMLEFT", 0, -10)
  scrollFrame:SetPoint("BOTTOMRIGHT", -30, 16)

  local out = CreateFrame("EditBox", nil, scrollFrame)
  out:SetMultiLine(true)
  out:SetAutoFocus(false)
  out:EnableMouse(true)
  out:SetFontObject(ChatFontNormal)
  out:SetWidth(670)
  out:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  out:SetText("Pick a plan, then click Calculate.")
  scrollFrame:SetScrollChild(out)
  UI.outputBox = out

  UI.frame = f

  if ProfLevelCostDB.lastPlanName then
    UI_SelectPlan(ProfLevelCostDB.lastPlanName)
    UIDropDownMenu_SetText(dd, ProfLevelCostDB.lastPlanName)
  end

  UI_SetView(ProfLevelCostDB.lastView or "summary")
  UI_UpdateStatus()
  UI_UpdateOptimizeControl()
end

local function UI_Toggle()
  UI_Create()
  if UI.frame:IsShown() then
    UI.frame:Hide()
  else
    UI_UpdateStatus()
    UI.frame:Show()
    UI_Recalculate()
  end
end

-- =========================================================

-- =========================================================
-- UI exports (used by Events / Slash commands)
-- =========================================================
PLC.UI = UI
PLC.UI_Recalculate = UI_Recalculate
PLC.UI_UpdateStatus = UI_UpdateStatus
PLC.UI_Toggle = UI_Toggle
PLC.UI_Create = UI_Create
