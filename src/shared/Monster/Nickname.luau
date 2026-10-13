--!strict
--[[
	Monster/Nickname.luau

	STRUCTURAL nickname rules only. This is a safety net for data integrity, not
	moderation.

	IMPORTANT: Roblox requires user-generated text shown to other players to go
	through server-side text filtering (TextService:FilterStringAsync). That call
	is asynchronous and Roblox-specific, so it lives in a server service in a
	later phase (the rename Remote handler: normalize -> validate -> filter).
	Verify the exact filtering/storage requirements in the current Roblox docs
	before shipping rename; do not rely on this module for compliance.

	Why a tight ASCII allow-list: it removes whole classes of abuse for free
	(zero-width characters, right-to-left overrides, homoglyph impersonation,
	emoji spam, strings that overflow UI) without needing a filter round-trip
	for obviously-bad input.
]]

local Constants = require(script.Parent.Parent.Constants)

local Nickname = {}

-- Collapses whitespace runs and trims, so "  Sir   Fluff " -> "Sir Fluff".
-- Call this on raw client input BEFORE validate().
function Nickname.normalize(raw: string): string
	local collapsed = string.gsub(raw, "%s+", " ")
	local trimmed = string.match(collapsed, "^%s*(.-)%s*$")
	return trimmed or ""
end

-- Returns (true, nil) or (false, reason).
function Nickname.validate(value: any): (boolean, string?)
	if type(value) ~= "string" then
		return false, "nickname must be a string"
	end
	local text = value :: string
	if #text < Constants.NICKNAME_MIN_LENGTH or #text > Constants.NICKNAME_MAX_LENGTH then
		return false, `nickname must be {Constants.NICKNAME_MIN_LENGTH}-{Constants.NICKNAME_MAX_LENGTH} characters`
	end
	if string.find(text, "^[%w][%w '%.%-]*$") == nil then
		return false, "nickname may only contain letters, digits, spaces, apostrophes, periods and hyphens, and must start with a letter or digit"
	end
	if string.find(text, "  ", 1, true) ~= nil or string.sub(text, -1) == " " then
		return false, "nickname must not contain repeated or trailing spaces"
	end
	return true, nil
end

return table.freeze(Nickname)
