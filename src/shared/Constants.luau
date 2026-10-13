--!strict
--[[
	Constants.luau

	Rule-level constants that are not content. Content (species, moves, ...)
	lives in Data/. Everything here is frozen: a stray `Constants.MAX_LEVEL = 999`
	elsewhere must throw, not silently change game rules.

	The string lists mirror the literal-union types in Types.luau. Luau cannot
	derive one from the other, so the validator checks data against THESE lists
	and the type checker checks code against the unions; keep them in sync.
]]

local Constants = {
	-- Progression -------------------------------------------------------------
	MIN_LEVEL = 1,
	MAX_LEVEL = 100,
	MAX_MOVES = 4,
	IV_MAX = 31,
	NATURE_PERCENT = 10, -- +10% / -10% to one stat each
	MAX_STAT_STAGE = 6,

	-- Persistence ---------------------------------------------------------------
	-- Bump when the OwnedMonster shape changes, and add a migration in Phase 2.
	MONSTER_SCHEMA_VERSION = 1,

	-- Numeric safety ------------------------------------------------------------
	MAX_SAFE_INTEGER = 9007199254740991, -- 2^53 - 1, largest exactly-representable integer
	MAX_XP = 2147483647, -- keep xp inside int32 so every consumer can hold it
	MIN_USER_ID = -2147483648, -- Studio-emulated players can have negative UserIds (unverified: check in Studio)

	-- Nicknames -----------------------------------------------------------------
	NICKNAME_MIN_LENGTH = 1,
	NICKNAME_MAX_LENGTH = 16,

	-- Closed vocabularies -------------------------------------------------------
	STAT_IDS = table.freeze({ "hp", "attack", "defense", "spAttack", "spDefense", "speed" }),
	BATTLE_STAT_IDS = table.freeze({
		"attack",
		"defense",
		"spAttack",
		"spDefense",
		"speed",
		"accuracy",
		"evasion",
	}),
	MOVE_CATEGORIES = table.freeze({ "physical", "special", "status" }),
	MOVE_TARGETS = table.freeze({ "opponent", "self" }),
	MOVE_EFFECT_KINDS = table.freeze({ "inflictStatus", "statStage", "recoil", "drain", "heal" }),
	STATUS_CATEGORIES = table.freeze({ "major", "volatile" }),
	ITEM_CATEGORIES = table.freeze({ "ball", "medicine", "evolution", "key" }),
	ITEM_USE_KINDS = table.freeze({ "healHp", "cureStatus", "revive", "ball" }),
	EVOLUTION_TRIGGERS = table.freeze({ "level", "item", "trade", "condition" }),
	TIMES_OF_DAY = table.freeze({ "day", "night" }),
	CAUGHT_METHODS = table.freeze({ "wild", "starter", "egg", "event", "gift", "admin" }),
}

return table.freeze(Constants)
