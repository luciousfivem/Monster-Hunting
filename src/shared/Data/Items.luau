--!strict
--[[
	Data/Items.luau

	Economy invariants enforced by the validator (so a typo cannot create an
	infinite-money loop or an untradeable-item dupe):
	  * sellPrice <= buyPrice
	  * key items are never tradeable and have no prices
	  * ball/medicine items must carry a matching `use`
]]

local Types = require(script.Parent.Parent.Types)

local items: { Types.Item } = {
	-- Capture orbs --------------------------------------------------------------
	{
		id = "orb_basic",
		name = "Tamer Orb",
		description = "A standard orb for capturing wild monsters.",
		category = "ball",
		buyPrice = 100,
		sellPrice = 50,
		stackLimit = 99,
		tradeable = true,
		consumable = true,
		use = { kind = "ball", catchMultiplier = 1 },
		iconAssetId = 0,
	},
	{
		id = "orb_great",
		name = "Tamer Orb+",
		description = "A sturdier orb with a better capture rate.",
		category = "ball",
		buyPrice = 250,
		sellPrice = 125,
		stackLimit = 99,
		tradeable = true,
		consumable = true,
		use = { kind = "ball", catchMultiplier = 1.5 },
		iconAssetId = 0,
	},
	{
		id = "orb_ultra",
		name = "Tamer Orb Elite",
		description = "A high-grade orb with an excellent capture rate.",
		category = "ball",
		buyPrice = 600,
		sellPrice = 300,
		stackLimit = 99,
		tradeable = true,
		consumable = true,
		use = { kind = "ball", catchMultiplier = 2 },
		iconAssetId = 0,
	},

	-- Medicine ------------------------------------------------------------------
	{
		id = "tonic_small",
		name = "Small Tonic",
		description = "Restores 20 HP.",
		category = "medicine",
		buyPrice = 100,
		sellPrice = 50,
		stackLimit = 99,
		tradeable = true,
		consumable = true,
		use = { kind = "healHp", hp = 20 },
		iconAssetId = 0,
	},
	{
		id = "tonic_large",
		name = "Large Tonic",
		description = "Restores 80 HP.",
		category = "medicine",
		buyPrice = 300,
		sellPrice = 150,
		stackLimit = 99,
		tradeable = true,
		consumable = true,
		use = { kind = "healHp", hp = 80 },
		iconAssetId = 0,
	},
	{
		id = "revive_charm",
		name = "Revive Charm",
		description = "Revives a fainted monster with half its HP.",
		category = "medicine",
		buyPrice = 800,
		sellPrice = 400,
		stackLimit = 99,
		tradeable = true,
		consumable = true,
		use = { kind = "revive", fraction = 0.5 },
		iconAssetId = 0,
	},
	{
		id = "antidote",
		name = "Antidote",
		description = "Cures poison.",
		category = "medicine",
		buyPrice = 80,
		sellPrice = 40,
		stackLimit = 99,
		tradeable = true,
		consumable = true,
		use = { kind = "cureStatus", statusIds = { "poison" } },
		iconAssetId = 0,
	},
	{
		id = "cure_all",
		name = "Cure-All",
		description = "Cures any status condition.",
		category = "medicine",
		buyPrice = 200,
		sellPrice = 100,
		stackLimit = 99,
		tradeable = true,
		consumable = true,
		use = { kind = "cureStatus", cureAll = true },
		iconAssetId = 0,
	},

	-- Evolution -----------------------------------------------------------------
	{
		id = "volt_shard",
		name = "Volt Shard",
		description = "A crackling crystal that triggers certain evolutions.",
		category = "evolution",
		sellPrice = 300,
		stackLimit = 99,
		tradeable = true,
		consumable = true,
		iconAssetId = 0,
	},

	-- Key items -----------------------------------------------------------------
	{
		id = "world_map",
		name = "World Map",
		description = "Shows the regions you have discovered.",
		category = "key",
		stackLimit = 1,
		tradeable = false,
		consumable = false,
		iconAssetId = 0,
	},
}

return items
