-- Shared pieces: slot groups, chat output, Auctionator's scan data and the
-- tooltip checks used by both the planner and the suffix scan.

local _, ns = ...

ns.ADDON = "PawnBroker"
ns.SCAN_BELOW = 10	-- suffix scan covers items this far below your level
ns.SCAN_AHEAD = 5	-- and this far above it
ns.NEAR = 500	-- default net cost (copper) that counts as near vendor price

local PREFIX = "|cff33ff99PawnBroker|r: "
local STALL = 3	-- seconds with no item data arriving before giving up

-- Rings and trinkets compete with the weaker of their two slots, and all
-- hand-held items share one group, so a plan never buys two things that
-- can't be worn together.
ns.GROUPS = {
	INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck",
	INVTYPE_SHOULDER = "Shoulder", INVTYPE_CLOAK = "Back",
	INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest",
	INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands",
	INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet",
	INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Trinket",
	INVTYPE_2HWEAPON = "Weapon", INVTYPE_WEAPON = "Weapon",
	INVTYPE_WEAPONMAINHAND = "Weapon", INVTYPE_WEAPONOFFHAND = "Weapon",
	INVTYPE_SHIELD = "Weapon", INVTYPE_HOLDABLE = "Weapon",
	INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged",
	INVTYPE_THROWN = "Ranged",
}

-- Hand-held items that go beside a one-hander, never a two-hander.
ns.OFF_HAND = {
	INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true,
	INVTYPE_HOLDABLE = true,
}

function ns.twoHanded()
	local link = GetInventoryItemLink("player", 16)
	local loc = link and select(4, C_Item.GetItemInfoInstant(link))
	return loc == "INVTYPE_2HWEAPON"
end

-- Red tooltip text that doesn't mean "can't use".
local HARMLESS_RED = {}
for _, key in ipairs({ "ITEM_SCRAPABLE_NOT", "CANNOT_UNEQUIP_COMBAT",
		"ITEM_DISENCHANT_NOT_DISENCHANTABLE" }) do
	if _G[key] then
		HARMLESS_RED[_G[key]] = true
	end
end
local LEVEL_LINE = "^" .. (ITEM_MIN_LEVEL or "Requires Level %d")
	:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%d", "%%d+") .. "$"

function ns.say(msg)
	print(PREFIX .. msg)
end

-- Progress and results go to the window when it's open, else to chat.
function ns.status(msg)
	if ns.ui and ns.ui:IsShown() then
		ns.ui:SetStatus(msg)
	else
		ns.say(msg)
	end
end

function ns.money(copper)
	local parts = {}
	local g = math.floor(copper / 10000)
	local s = math.floor(copper / 100) % 100
	local c = copper % 100
	if g > 0 then
		parts[#parts + 1] = g .. "g"
	end
	if s > 0 then
		parts[#parts + 1] = s .. "s"
	end
	if c > 0 or #parts == 0 then
		parts[#parts + 1] = c .. "c"
	end
	return table.concat(parts, " ")
end

-- An option's net cost, written with money (ns.money or ns.coins), or
-- "free" when a vendor pays at least what the AH asks.
function ns.netText(o, money)
	if o.net <= 0 then
		return "free"
	end
	return money(o.net)
end

-- Coin icons for chat. The global GetCoinTextureString is gone on this
-- client; C_CurrencyInfo has it.
local coinText = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
	or GetCoinTextureString
function ns.coins(copper)
	return coinText and coinText(copper) or ns.money(copper)
end

-- Saved data can be from an older version or edited by hand, so anything
-- of the wrong type is dropped before the addon relies on it.
local function isNumber(v)
	return type(v) == "number" and v == v and v ~= math.huge
		and v ~= -math.huge
end

local function cleanUI(ui)
	if type(ui.budget) ~= "string" then
		ui.budget = nil
	end
	if type(ui.ahead) ~= "string" then
		ui.ahead = nil
	end
	if type(ui.net) ~= "boolean" then
		ui.net = nil
	end
	if ui.near ~= false and not (isNumber(ui.near) and ui.near >= 0) then
		ui.near = nil
	end
end

local function validVariant(v)
	return type(v) == "table" and type(v.link) == "string"
		and isNumber(v.price) and (v.count == nil or isNumber(v.count))
end

local function validEntry(e)
	if type(e) ~= "table" or not isNumber(e.time)
			or type(e.variants) ~= "table" then
		return false
	end
	for _, v in ipairs(e.variants) do
		if not validVariant(v) then
			return false
		end
	end
	return true
end

-- Removes every value in t that keep rejects.
local function filter(t, keep)
	for k, v in pairs(t) do
		if not keep(v) then
			t[k] = nil
		end
	end
end

local function clean(db)
	for _, key in ipairs({ "ui", "scans", "suffix", "report" }) do
		if db[key] ~= nil and type(db[key]) ~= "table" then
			db[key] = nil
		end
	end
	if db.ui then
		cleanUI(db.ui)
	end
	filter(db.scans or {}, function(s)
		return type(s) == "table" and isNumber(s.time) and isNumber(s.level)
	end)
	filter(db.suffix or {}, function(items)
		if type(items) ~= "table" then
			return false
		end
		filter(items, validEntry)
		return true
	end)
end

local checked	-- the PawnBrokerDB table clean() last ran on
function ns.db()
	if type(PawnBrokerDB) ~= "table" then
		PawnBrokerDB = {}
	end
	if checked ~= PawnBrokerDB then
		clean(PawnBrokerDB)
		checked = PawnBrokerDB
	end
	return PawnBrokerDB
end

function ns.realm()
	return GetRealmName()
end

function ns.character()
	return UnitName("player") .. "-" .. GetRealmName()
end

-- The first visible Pawn scale by name, plus how many are visible.
function ns.pickScale()
	local names = {}
	for name in pairs(PawnCommon.Scales) do
		if PawnIsScaleVisible(name) then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names[1], #names
end

-- Pawn's names for weapon and armour types, by item subclass.
local WEAPON_STAT = {
	[0] = "IsAxe", [1] = "Is2HAxe", [2] = "IsBow", [3] = "IsGun",
	[4] = "IsMace", [5] = "Is2HMace", [6] = "IsPolearm", [7] = "IsSword",
	[8] = "Is2HSword", [10] = "IsStaff", [13] = "IsFist",
	[15] = "IsDagger", [16] = "IsThrown", [18] = "IsCrossbow",
	[19] = "IsWand",
}
local ARMOR_STAT = {
	[1] = "IsCloth", [2] = "IsLeather", [3] = "IsMail", [4] = "IsPlate",
	[6] = "IsShield",
}
local WEAPON, ARMOR = 2, 4	-- Enum.ItemClass

-- Whether the class can use the item's type, by the scale's unusable
-- types and Pawn's armour rule, from cached-free item info. This keeps
-- items nobody will score out of the slow loading step.
function ns.wearable(id, scale)
	local _, _, _, loc, _, class, sub = C_Item.GetItemInfoInstant(id)
	local stat = class == WEAPON and WEAPON_STAT[sub]
		or class == ARMOR and ARMOR_STAT[sub]
	if not stat then
		return true
	end
	local values = PawnCommon.Scales[scale].Values
	if (values[stat] or 0) <= PawnIgnoreStatValue then
		return false
	end
	if class ~= ARMOR or sub > 4 or loc == "INVTYPE_CLOAK" then
		return true
	end
	local item = { UnenchantedStats = { [stat] = true } }
	return PawnIsArmorBestTypeForPlayer(item)
end

-- Auctionator's price table for this realm, or nil before it loads.
function ns.auctionator()
	local db = Auctionator and Auctionator.Database
		and Auctionator.Database.db
	return type(db) == "table" and db or nil
end

local PAWN_API = { "PawnGetItemData", "PawnGetSingleValueFromItem",
	"PawnGetItemDataForInventorySlot", "PawnIsArmorBestTypeForPlayer",
	"PawnIsScaleVisible" }
local AUCTIONATOR_API = { "GetAuctionPriceByItemID", "GetAuctionAgeByItemID",
	"CreateShoppingList" }

-- Why planning can't run with the Pawn and Auctionator that are loaded, or
-- nil when everything it calls is there. A later version that renames
-- something then gets a message instead of a Lua error.
function ns.missing()
	if type(PawnCommon) ~= "table" or type(PawnCommon.Scales) ~= "table"
			or type(PawnIgnoreStatValue) ~= "number" then
		return "needs Pawn loaded."
	end
	for _, name in ipairs(PAWN_API) do
		if type(_G[name]) ~= "function" then
			return "this Pawn has no " .. name .. ", so PawnBroker needs an update."
		end
	end
	local api = type(Auctionator) == "table" and Auctionator.API
		and Auctionator.API.v1
	if type(api) ~= "table" or not ns.auctionator() then
		return "needs Auctionator loaded."
	end
	for _, name in ipairs(AUCTIONATOR_API) do
		if type(api[name]) ~= "function" then
			return "this Auctionator has no API.v1." .. name
				.. ", so PawnBroker needs an update."
		end
	end
end

local function red(color)
	return color and color.r > 0.9 and color.g < 0.2 and color.b < 0.2
end

-- Green gear whose only stats are armour or weapon damage nearly always
-- gets its stats from a random suffix.
local DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
local function bare(link)
	for stat in pairs(C_Item.GetItemStats(link) or {}) do
		if stat:find("^ITEM_MOD_") and stat ~= DPS then
			return false
		end
	end
	return true
end

local function redLine(i, line)
	local text = line.leftText or ""
	if i > 1 and red(line.leftColor) and not HARMLESS_RED[text]
			and not text:find(LEVEL_LINE) then
		return true
	end
	return red(line.rightColor)
end

-- random: the stats come from a suffix, so Auctionator's one price per
-- item says nothing about any particular version.
-- unusable: red tooltip text such as a profession requirement or an
-- untrained weapon. The level line is left to the level filters.
function ns.verdict(link, quality)
	local verdict = {}
	local tip = C_TooltipInfo and C_TooltipInfo.GetHyperlink(link)
	for i, line in ipairs(tip and tip.lines or {}) do
		local text = (line.leftText or ""):lower()
		if line.leftText == ITEM_RANDOM_ENCHANT
				or text:find("random enchant") then
			verdict.random = true
		elseif redLine(i, line) then
			verdict.unusable = true
		end
	end
	if quality == 2 and not verdict.random then
		verdict.random = bare(link)
	end
	return verdict
end

-- Listings on the newest day of Auctionator's history for the item.
-- This reads Auctionator's own tables, not its API, so it checks every type
-- and gives nil if a later Auctionator stores them differently.
function ns.listed(db, id)
	local entry = db[tostring(id)]
	if type(entry) ~= "table" or type(entry.a) ~= "table" then
		return nil
	end
	local newest, count = -1, nil
	for day, n in pairs(entry.a) do
		day = tonumber(day)
		if day and day > newest and type(n) == "number" then
			newest, count = day, n
		end
	end
	return count
end

-- Days since Auctionator's last full scan by its own record, or nil. A
-- search by hand also dates the items it finds, so the newest day in the
-- price data can hold only a handful of items. Like ns.listed this reads
-- Auctionator's own tables, so it checks their types.
local function fullScanAge()
	local state = Auctionator.SavedState
	local zero = Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0
	if type(state) ~= "table" or type(zero) ~= "number" then
		return nil
	end
	local last = 0
	for _, key in ipairs({ "TimeOfLastReplicateScan",
			"TimeOfLastBrowseScan", "TimeOfLastGetAllScan" }) do
		if type(state[key]) == "number" then
			last = math.max(last, state[key])
		end
	end
	if last < zero then
		return nil
	end
	local function day(t)
		return math.floor((t - zero) / 86400)
	end
	return day(time()) - day(last)
end

-- Items the class can wear seen in or since the last full scan, and that
-- scan's age in days. Without a full scan on record, the newest day.
function ns.freshItems(db, scale)
	local api = Auctionator.API.v1
	local ids, ages, freshest = {}, {}, nil
	for key in pairs(db) do
		local id = tonumber(key)
		local loc = id and select(4, C_Item.GetItemInfoInstant(id))
		local age = loc and ns.GROUPS[loc] and ns.wearable(id, scale)
			and api.GetAuctionAgeByItemID(ns.ADDON, id)
		if age then
			ids[#ids + 1] = id
			ages[id] = age
			freshest = math.min(freshest or age, age)
		end
	end
	if not freshest then
		return {}, nil
	end
	local cutoff = math.max(fullScanAge() or freshest, freshest)
	local fresh = {}
	for _, id in ipairs(ids) do
		if ages[id] <= cutoff then
			fresh[#fresh + 1] = id
		end
	end
	return fresh, cutoff
end

-- Calls done once every item is cached, or once nothing has arrived for
-- STALL seconds. progress(loaded, total) reports along the way.
function ns.loadItems(ids, done, progress)
	local pending, called = 0, false
	local function once()
		if not called then
			called = true
			done()
		end
	end
	local cached = C_Item.IsItemDataCachedByID
	for _, id in ipairs(ids) do
		if cached and not cached(id) then
			pending = pending + 1
			Item:CreateFromItemID(id):ContinueOnItemLoad(function()
				pending = pending - 1
				if pending == 0 then
					once()
				end
			end)
		end
	end
	if pending == 0 then
		return once()
	end
	local total, last, still = pending, pending, 0
	local function check()
		if called then
			return
		end
		if progress then
			progress(total - pending, total)
		end
		still = pending < last and 0 or still + 1
		last = pending
		if still >= STALL then
			return once()
		end
		C_Timer.After(1, check)
	end
	C_Timer.After(1, check)
end

-- Runs work(item) for each item, FRAME_MS of it per frame so nothing
-- hitches, then done(). An error goes to the error handler (BugSack) and
-- to failed().
local FRAME_MS = 8
function ns.each(items, work, done, failed)
	local function from(first)
		local last = first - 1
		local ok, err = pcall(function()
			local start = debugprofilestop()
			while last < #items do
				last = last + 1
				work(items[last])
				if debugprofilestop() - start >= FRAME_MS then
					break
				end
			end
			if last == #items then
				done()
			end
		end)
		if not ok then
			failed()
			geterrorhandler()(err)
		elseif last < #items then
			C_Timer.After(0, function() from(last + 1) end)
		end
	end
	from(1)
end
