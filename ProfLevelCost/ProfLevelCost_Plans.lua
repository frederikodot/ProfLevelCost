-- ProfLevelCost_Plans.lua
-- Plan definitions (fast to load). Data pools live in LoadOnDemand data addons.

ProfLevelCostPlans = ProfLevelCostPlans or {}

-- === AL plans (extracted from AL_Pools.lua) ===
table.insert(ProfLevelCostPlans, {
	name = "Alchemy Optimizer 1-300 (TBC) - Pool Based",
	poolKey = { "AL_PRE" },
	from = 1,
	to = 300,
	chunk = 1,
	firstChunk = 1,
})

table.insert(ProfLevelCostPlans, {
	name = "Alchemy Optimizer 300-375 (TBC) - Pool Based",
	poolKey = { "AL_PRE", "AL_OUT" },
	from = 300,
	to = 375,
	chunk = 1,
})

-- === BS plans (extracted from BS_Pools.lua) ===
-- Optional: pool-based plans (remove if you already define plans elsewhere)
table.insert(ProfLevelCostPlans, {
	name = "Blacksmithing Optimizer 1-300 (TBC) - Pool Based",
	poolKey = { "BS_PRE" },
	from = 1,
	to = 300,
	chunk = 1,
	firstChunk = 1, -- your request: first chunk 4 so the rest line up
})

table.insert(ProfLevelCostPlans, {
	name = "Blacksmithing Optimizer 300-375 (TBC) - Pool Based",
	poolKey = { "BS_PRE", "BS_OUTLAND" },
	from = 300,
	to = 375,
	chunk = 1,
})

-- === EN plans (extracted from EN_Pools.lua) ===
-- Pool-based plans (requires ProfLevelCost Core that supports poolKey as a list)
table.insert(ProfLevelCostPlans, {
	name = "Engineering Optimizer 1-300 (Pre-Outland / Prepatch) - Pool Based",
	poolKey = { "EN_PRE" },
	from = 1,
	to = 300,
	chunk = 1,
	firstChunk = 1,
})

table.insert(ProfLevelCostPlans, {
	name = "Engineering Optimizer 300-375 (Outland / Prepatch) - Pool Based",
	poolKey = { "EN_PRE", "EN_OUT" }, -- allow any pre recipes that still skill past 300
	from = 300,
	to = 375,
	chunk = 1,
})

-- === JC plans (extracted from JC_Pools.lua) ===
-- Pool-based plans (requires ProfLevelCost Core that supports poolKey as a list)
table.insert(ProfLevelCostPlans, {
	name = "Jewelcrafting Optimizer 1-300 (Pre-Outland / Prepatch) - Pool Based",
	poolKey = { "JC_PRE" },
	from = 1,
	to = 300,
	chunk = 1,
	firstChunk = 1,
})

table.insert(ProfLevelCostPlans, {
	name = "Jewelcrafting Optimizer 300-375 (Outland / Prepatch) - Pool Based",
	poolKey = { "JC_PRE", "JC_OUT" }, -- allow any pre recipes that still skill past 300
	from = 300,
	to = 375,
	chunk = 1,
})

-- === LW plans (extracted from LW_Pools.lua) ===
-- Pool-based plans (requires ProfLevelCost Core that supports poolKey as a list)
table.insert(ProfLevelCostPlans, {
	name = "Leatherworking Optimizer 1-300 (Pre-Outland / Prepatch) - Pool Based",
	poolKey = { "LW_PRE" },
	from = 1,
	to = 300,
	chunk = 1,
	firstChunk = 1,
})

table.insert(ProfLevelCostPlans, {
	name = "Leatherworking Optimizer 300-375 (Outland / Prepatch) - Pool Based",
	poolKey = { "LW_PRE", "LW_OUT" }, -- allow any pre recipes that still skill past 300
	from = 300,
	to = 375,
	chunk = 1,
})

-- === TL plans (extracted from TL_Pools.lua) ===
table.insert(ProfLevelCostPlans, {
	name = "Tailoring Optimizer 1-300 (Pre-Outland / Prepatch) - Pool Based",
	poolKey = { "TL_PRE" },
	from = 1,
	to = 300,
	chunk = 1,
	firstChunk = 1,
})

table.insert(ProfLevelCostPlans, {
	name = "Tailoring Optimizer 300-375 (Outland / Prepatch) - Pool Based",
	poolKey = { "TL_PRE", "TL_OUT" }, 
	from = 300,
	to = 375,
	chunk = 1,
})

