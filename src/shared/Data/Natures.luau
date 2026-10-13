--!strict
--[[
	Data/Natures.luau

	A nature raises one non-HP stat by 10% and lowers another by 10%.
	Five neutral natures leave all stats unchanged. See Constants.NATURE_PERCENT.
]]

local Types = require(script.Parent.Parent.Types)

local natures: { Types.Nature } = {
	-- Neutral
	{ id = "even", name = "Even" },
	{ id = "steady", name = "Steady" },
	{ id = "placid", name = "Placid" },
	{ id = "poised", name = "Poised" },
	{ id = "mellow", name = "Mellow" },

	-- +attack
	{ id = "brash", name = "Brash", increased = "attack", decreased = "defense" },
	{ id = "rowdy", name = "Rowdy", increased = "attack", decreased = "spAttack" },
	{ id = "reckless", name = "Reckless", increased = "attack", decreased = "spDefense" },
	{ id = "plodding", name = "Plodding", increased = "attack", decreased = "speed" },

	-- +defense
	{ id = "sturdy", name = "Sturdy", increased = "defense", decreased = "attack" },
	{ id = "stalwart", name = "Stalwart", increased = "defense", decreased = "spAttack" },
	{ id = "gruff", name = "Gruff", increased = "defense", decreased = "spDefense" },
	{ id = "steadfast", name = "Steadfast", increased = "defense", decreased = "speed" },

	-- +spAttack
	{ id = "clever", name = "Clever", increased = "spAttack", decreased = "attack" },
	{ id = "cunning", name = "Cunning", increased = "spAttack", decreased = "defense" },
	{ id = "fervent", name = "Fervent", increased = "spAttack", decreased = "spDefense" },
	{ id = "studious", name = "Studious", increased = "spAttack", decreased = "speed" },

	-- +spDefense
	{ id = "serene", name = "Serene", increased = "spDefense", decreased = "attack" },
	{ id = "gentle", name = "Gentle", increased = "spDefense", decreased = "defense" },
	{ id = "devout", name = "Devout", increased = "spDefense", decreased = "spAttack" },
	{ id = "patient", name = "Patient", increased = "spDefense", decreased = "speed" },

	-- +speed
	{ id = "nimble", name = "Nimble", increased = "speed", decreased = "attack" },
	{ id = "zippy", name = "Zippy", increased = "speed", decreased = "defense" },
	{ id = "flighty", name = "Flighty", increased = "speed", decreased = "spAttack" },
	{ id = "eager", name = "Eager", increased = "speed", decreased = "spDefense" },
}

return natures
