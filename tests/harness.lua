-- PawnBroker under mocked WoW, Pawn and Auctionator APIs, with real scan
-- data. usage: luajit harness.lua <mockdata.lua> <gear.lua> <addon dir>
-- <scenario.lua>. Scenarios drive it with pb(), fire(), run() and the
-- mock clock, and assert on NS (the addon namespace) and PawnBrokerDB.
dofile(arg[1])
local env = {}
local chunk = assert(loadfile(arg[2]))
setfenv(chunk, env)
chunk()
local gear = env.ForeverTuneDB.gear

-- clock and timers
local now, EPOCH, timers, seq = 0, 1762689600, {}, 0
C_Timer = { After = function(d, f)
	seq = seq + 1
	timers[#timers + 1] = { t = now + d, s = seq, f = f }
end }
function run(limit)
	local steps = 0
	while #timers > 0 do
		table.sort(timers, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.s < b.s end)
		local x = table.remove(timers, 1)
		now = math.max(now, x.t)
		x.f()
		steps = steps + 1
		if limit and now >= limit then return end
		assert(steps < 200000, "runaway")
	end
end
function advanceClock(sec) now = now + sec end
function clock() return now end
function GetTime() return now end
function time() return EPOCH + math.floor(now) end
function date() return "now" end

-- frames and events
local frames = {}
local function widget()
	local w = { ev = {}, shown = true, text = "", scripts = {} }
	function w.RegisterEvent(self, e) self.ev[e] = true end
	function w.SetScript(self, name, fn)
		self.scripts[name] = fn
		if name == "OnEvent" then self.fn = fn end
	end
	function w.Show(self) self.shown = true end
	function w.Hide(self) self.shown = false end
	function w.IsShown(self) return self.shown end
	function w.SetText(self, t) self.text = t end
	function w.GetText(self) return self.text end
	function w.CreateFontString() return widget() end
	function w.CreateTexture() return widget() end
	function w.GetPortrait() return widget() end
	function w.SetEnabled(self, e) self.enabled = e end
	function w.SetChecked(self, c) self.checked = c and true or false end
	function w.GetChecked(self) return self.checked end
	return setmetatable(w, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
end
function CreateFrame(kind, name, parent, template)
	local f = widget()
	f.template = template
	frames[#frames + 1] = f
	if name then _G[name] = f end
	return f
end
UISpecialFrames = {}
GameTooltip = widget()
function GameTooltip_Hide() end
function IsModifiedClick() return false end
PawnIgnoreStatValue = -1000000
function fire(e, ...)
	for _, f in ipairs(frames) do
		if f.ev[e] and f.fn then f.fn(f, e, ...) end
	end
end

-- stats
local W = { INTELLECT = .44, SPIRIT = .066, STAMINA = .1, SPELL_POWER = 1,
	SPELL_DAMAGE_DONE = 1, FIRE_DAMAGE_DONE = .94, FROST_DAMAGE_DONE = .32,
	ARCANE_DAMAGE_DONE = .168, MANA_REGENERATION = .9, ARMOR = .005,
	AGILITY = .05 }
local function norm(stats)
	local out = {}
	for k, v in pairs(stats or {}) do
		k = k:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("RESISTANCE0_NAME", "ARMOR")
		out[k] = v
	end
	return out
end
local function weigh(stats)
	local s = 0
	for k, v in pairs(stats) do s = s + (W[k] or 0) * v end
	return s
end
local function idOf(x)
	return type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)"))
end
local function sufOf(x)
	return type(x) == "string" and tonumber(x:match("item:%d+:0:0:0:0:0:(%d+)")) or nil
end
local SUFFIX = {
	{ "of the Owl", function(k) return { INTELLECT = k, SPIRIT = k } end },
	{ "of the Eagle", function(k) return { INTELLECT = k, STAMINA = k } end },
	{ "of the Bear", function(k) return { STAMINA = k, STRENGTH = k } end },
	{ "of Intellect", function(k) return { INTELLECT = k + 1 } end },
	{ "of the Monkey", function(k) return { AGILITY = k, STAMINA = k } end },
}
local function isRandom(m)
	for k in pairs(m.stats) do
		if k ~= "ARMOR" and not k:find("RESIST") and k ~= "DAMAGE_PER_SECOND" then return false end
	end
	return not m.loc:find("WEAPON") and m.loc ~= "INVTYPE_RANGEDRIGHT" and m.loc ~= "INVTYPE_BODY"
end
local function statsOf(link)
	local m = MOCK[idOf(link)]
	local s = {}
	for k, v in pairs(m.stats) do s[k] = v end
	local suf = sufOf(link)
	if suf then
		for k, v in pairs(SUFFIX[suf][2](math.floor(m.lvl / 5) + 1)) do s[k] = (s[k] or 0) + v end
	end
	return s
end
local function nameOf(link)
	local m = MOCK[idOf(link)]
	local suf = sufOf(link)
	return suf and (m.name .. " " .. SUFFIX[suf][1]) or m.name
end
local function vlink(id, suf) return "item:" .. id .. ":0:0:0:0:0:" .. suf .. "|h[" .. nameOf("item:" .. id .. ":0:0:0:0:0:" .. suf) .. "]" end

local EQUIPPED = {}
for slot, g in pairs(gear[2]) do
	EQUIPPED[slot] = { link = "item:" .. idOf(g[1]) .. "|h[" .. (g[1]:match("%[(.-)%]") or "?") .. "]", stats = norm(g[2]) }
end
local EQUIP_LOC = { [15397] = "INVTYPE_2HWEAPON" }

ITEM_MIN_LEVEL = "Requires Level %d"
ITEM_RANDOM_ENCHANT = "<Random enchantment>"
Enum = {}
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function GetMoney() return gear[3] end
function UnitLevel() return LEVEL or gear[1] end
function UnitName() return "Tester" end
function GetRealmName() return "Test Realm" end
C_CurrencyInfo = { GetCoinTextureString = function(c) return "<" .. c .. "c>" end }
function geterrorhandler() return function(e) error("addon error: " .. tostring(e), 0) end end
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] and EQUIPPED[slot].link end
C_Item = {
	GetItemInfoInstant = function(x)
		local id = idOf(x)
		local m = MOCK[id]
		return id, nil, nil, m and m.loc or EQUIP_LOC[id] or "", 1000 + id
	end,
	GetItemInfo = function(x)
		local id = idOf(x)
		if UNLOADED[id] then return nil end
		local m = MOCK[id]
		if not m then return equippedInfo(id) end
		local link = type(x) == "string" and x or ("item:" .. id .. "|h[" .. m.name .. "]")
		-- Vendors pay a quarter of the AH price unless a scenario sets m.sell.
		return nameOf(link), link, QUALITY[id] or 2, 20, m.lvl, nil, nil, nil, m.loc, nil,
			m.sell or math.floor(m.m / 4)
	end,
	GetItemStats = function(x)
		local out = {}
		for k, v in pairs(statsOf(x)) do
			out[k == "ARMOR" and "RESISTANCE0_NAME" or ("ITEM_MOD_" .. k .. "_SHORT")] = v
		end
		return out
	end,
	IsItemDataCachedByID = function(id) return not UNLOADED[id] end,
	RequestLoadItemDataByID = function() C_Item_Requests = C_Item_Requests + 1 end,
}
-- UNLOADED[id]: the client never gets the item's data. QUALITY[id]
-- overrides the default green.
UNLOADED, QUALITY = {}, {}
Item = { CreateFromItemID = function(_, id)
	return { ContinueOnItemLoad = function() end }
end }
C_TooltipInfo = { GetHyperlink = function(link)
	local m = MOCK[idOf(link)]
	local lines = { { leftText = nameOf(link) } }
	if m.name:find("Goggles") then
		lines[#lines + 1] = { leftText = "Requires Engineering (100)", leftColor = { r = 1, g = .1, b = .1 } }
	end
	if isRandom(m) and not sufOf(link) and not NO_RANDOM_LINE then
		lines[#lines + 1] = { leftText = ITEM_RANDOM_ENCHANT }
	end
	return { lines = lines }
end }

PawnCommon = { Scales = { ['"Classic":MAGE2'] = { Values = {} } } }
function PawnIsScaleVisible() return true end
function PawnGetScaleLocalizedName() return "Mage: Fire" end
-- Like Pawn, nothing for an item without stats, such as the base version
-- of a random-suffix ring.
function PawnGetItemData(link)
	local m = MOCK[idOf(link)]
	local stats = m and statsOf(link)
	return stats and next(stats) and { stats = stats } or nil
end
-- UNREADABLE[slot] = n: the item loads after n reads. STATLESS[slot]: it
-- has loaded but has no stats, so Pawn has nothing for it either.
UNREADABLE, STATLESS = {}, {}
function PawnGetItemDataForInventorySlot(slot)
	local e = EQUIPPED[slot]
	if not e then return nil, false end
	local u = UNREADABLE[slot]
	e.loading = u and u > 0
	if e.loading then UNREADABLE[slot] = u - 1 return nil, true end
	if STATLESS[slot] then return nil, true end
	return { stats = e.stats }, true
end
function equippedInfo(id)
	for _, e in pairs(EQUIPPED) do
		if idOf(e.link) == id and not e.loading then
			return e.link:match("%[(.-)%]"), e.link, 1
		end
	end
end
function GetInventoryItemID(_, slot) return EQUIPPED[slot] and idOf(EQUIPPED[slot].link) end
C_Item_Requests = 0
function PawnGetSingleValueFromItem(item) local v = weigh(item.stats) return v, v end
function PawnIsArmorBestTypeForPlayer() return true end

local DB = {}
for id, m in pairs(MOCK) do DB[tostring(id)] = { a = m.a, h = m.h, m = m.m } end
Auctionator = { Database = { db = DB }, API = { v1 = {
	GetAuctionAgeByItemID = function(_, id)
		local newest = -1
		for d in pairs(MOCK[id].h) do newest = math.max(newest, d) end
		return MOCK_TODAY - newest
	end,
	GetAuctionPriceByItemID = function(_, id) return MOCK[id].m end,
	MultiSearch = function() SEARCHES = SEARCHES or {} SEARCHES.loose = true end,
	MultiSearchExact = function() SEARCHES = SEARCHES or {} SEARCHES.exact = true end,
	CreateShoppingList = function(_, name, terms)
		LIST = terms
	end,
} } }

-- auction house
local busyUntil, keyLoaded, results, sends = -1, {}, {}, 0
STATS = { sends = 0, more = 0, dropped = 0 }
local function listings(id)
	local m = MOCK[id]
	if id % 7 == 0 then return {} end
	local out = {}
	for suf = 1, #SUFFIX do
		for j = 1, 2 do
			out[#out + 1] = { itemLink = vlink(id, suf), buyoutAmount = math.floor(m.m * (0.6 + 0.35 * suf) * (j == 1 and 1 or 1.5)), totalQuantity = 1 }
		end
	end
	if id % 5 == 0 then out[#out + 1] = { itemLink = vlink(id, 1), buyoutAmount = 1, totalQuantity = 1, containsOwnerItem = true } end
	table.sort(out, function(a, b) return a.buyoutAmount < b.buyoutAmount end)
	return out
end
local dropped = {}
C_AuctionHouse = {
	MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
	GetItemKeyInfo = function(key)
		if KEYS_SILENT then return nil end
		if keyLoaded[key.itemID] then return { itemName = MOCK[key.itemID].name } end
		keyLoaded[key.itemID] = true
	end,
	IsThrottledMessageSystemReady = function() return now >= busyUntil end,
	SendSellSearchQuery = function(key, sorts, sep)
		assert(sorts[1].sortOrder == 4 and sep == true)
		assert(now >= busyUntil, "sent while throttled")
		STATS.sends = STATS.sends + 1
		busyUntil = now + 0.3
		if AH_SILENT then return end
		local id = key.itemID
		-- SILENT_ONE: the first item searched for never answers.
		if SILENT_ONE and not SILENT_ID then SILENT_ID = id end
		if SILENT_ONE and SILENT_ID == id then return end
		if id % 11 == 0 and not dropped[id] then dropped[id] = true STATS.dropped = STATS.dropped + 1 return end
		local all = listings(id)
		local first = (id % 3 == 0) and math.ceil(#all / 2) or #all
		results[id] = { all = all, shown = first }
		C_Timer.After(0.2, function() fire("ITEM_SEARCH_RESULTS_UPDATED", key, nil) end)
	end,
	HasSearchResults = function(key) return results[key.itemID] ~= nil end,
	HasFullItemSearchResults = function(key) local r = results[key.itemID] return r.shown >= #r.all end,
	GetNumItemSearchResults = function(key) return results[key.itemID].shown end,
	RequestMoreItemSearchResults = function(key)
		STATS.more = STATS.more + 1
		local r = results[key.itemID]
		r.shown = #r.all
		C_Timer.After(0.2, function() fire("ITEM_SEARCH_RESULTS_ADDED", key) end)
	end,
	GetItemSearchResultInfo = function(key, i) return results[key.itemID].all[i] end,
}

SlashCmdList = {}
local ns = {}
NS = ns
for _, f in ipairs({ "Core.lua", "Suffix.lua", "Plan.lua", "UI.lua", "Main.lua" }) do
	local c = assert(loadfile(arg[3] .. "/" .. f))
	c("PawnBroker", ns)
end
function pb(msg)
	if VERBOSE then print("===== /pb " .. msg) end
	SlashCmdList.PAWNBROKER(msg)
end
fire("PLAYER_LOGIN")
dofile(arg[4])

