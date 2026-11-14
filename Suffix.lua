-- Random-suffix prices. Auctionator keeps one price per item ID, so "Willow
-- Vest" at 5s may be the Monkey version while the Owl one costs 40s. With
-- the AH open, /pb scan runs one sell search per random-suffix item in
-- your level range (a sell search returns every suffix with full links)
-- and caches the cheapest listing of each version, per realm. /pb plans
-- from that cache, and both /pb and opening the AH ask for a rescan when
-- it gets old.

local _, ns = ...

local STALE_HOURS = 24	-- older than this, ask for a rescan
local REUSE = 3600	-- a rescan skips items read within this many seconds
local KEEP_DAYS = 7	-- cached items older than this are dropped
local LEVELS_PAST = 3	-- levels gained before asking for a rescan
local REMIND_EVERY = 3600	-- seconds between reminders on opening the AH
local TIMEOUT = 5	-- seconds to wait for a search to answer
local TRIES = 3	-- searches per item before giving up on it
local WAIT_TICKS = 100	-- 0.1 s waits for the throttle or item key
local MAX_RESULTS = 200	-- listings read per item, cheapest first

local SORTS = { {
	sortOrder = Enum.AuctionHouseSortOrder
		and Enum.AuctionHouseSortOrder.Buyout or 4,
	reverseSort = false,
} }

local scan	-- the running scan, if any
local ahOpen = false
local remindedAt = 0

local function cache()
	local db = ns.db()
	db.suffix = db.suffix or {}
	local realm = ns.realm()
	db.suffix[realm] = db.suffix[realm] or {}
	return db.suffix[realm]
end

local function scans()
	local db = ns.db()
	db.scans = db.scans or {}
	return db.scans
end

-- Cached versions of an item, cheapest first, and when they were read.
function ns.variants(id)
	local entry = cache()[id]
	if entry then
		return entry.variants, entry.time
	end
end

-- Why the cache needs refreshing, or nil while it's fine.
function ns.suffixNotice()
	local last = scans()[ns.character()]
	local how = " With the AH open, type /pb scan."
	if not last then
		return "Random-suffix gear isn't priced yet." .. how
	end
	local hours = math.floor((time() - last.time) / 3600)
	if hours >= STALE_HOURS then
		return "Random-suffix prices are " .. hours .. "h old." .. how
	end
	local gained = UnitLevel("player") - last.level
	if gained >= LEVELS_PAST then
		return "You're " .. gained
			.. " levels past the last suffix scan." .. how
	end
end

function ns.ahOpen()
	return ahOpen or (AuctionHouseFrame and AuctionHouseFrame:IsShown())
end

-- A random-suffix item in scan range that isn't freshly cached.
local function wanted(id, level, now)
	local _, link, quality, _, minLevel = C_Item.GetItemInfo(id)
	minLevel = minLevel or 0
	if not link or minLevel > level + ns.SCAN_AHEAD
			or minLevel < level - ns.SCAN_BELOW then
		return false
	end
	local entry = cache()[id]
	if entry and now - entry.time < REUSE then
		return false
	end
	local verdict = ns.verdict(link, quality)
	if not verdict.random or verdict.unusable then
		return false
	end
	local item = PawnGetItemData(link)
	return item and PawnIsArmorBestTypeForPlayer(item)
end

-- Cheapest listing of each version, by the name the suffix gives it.
local function addListing(byName, r)
	if not (r and r.itemLink and r.buyoutAmount) or r.containsOwnerItem then
		return
	end
	local name = r.itemLink:match("%[(.-)%]") or r.itemLink
	local v = byName[name]
	local n = r.totalQuantity or 1
	if not v then
		byName[name] = { link = r.itemLink, price = r.buyoutAmount }
		v = byName[name]
		v.count = 0
	end
	v.count = v.count + n
	if r.buyoutAmount < v.price then
		v.link, v.price = r.itemLink, r.buyoutAmount
	end
end

local function readVariants(key)
	local byName = {}
	local n = C_AuctionHouse.GetNumItemSearchResults(key)
	for i = 1, math.min(n, MAX_RESULTS) do
		local r = C_AuctionHouse.GetItemSearchResultInfo(key, i)
		addListing(byName, r)
	end
	local variants = {}
	for _, v in pairs(byName) do
		variants[#variants + 1] = v
	end
	table.sort(variants, function(a, b) return a.price < b.price end)
	return variants
end

local send, advance, guarded

local function retry(s)
	s.tries = s.tries + 1
	if s.tries < TRIES then
		return send(s)
	end
	s.failed = s.failed + 1
	advance(s)
end

-- Waits TIMEOUT for an answer; a newer wait or a reply cancels this one.
local function await(s)
	local token = {}
	s.token = token
	C_Timer.After(TIMEOUT, function()
		if scan == s and s.token == token then
			guarded(retry, s)
		end
	end)
end

-- Lets the window update its scan button and progress.
local function changed()
	if ns.ui then
		ns.ui:Refresh()
	end
end

function ns.scanning()
	return scan ~= nil
end

local function stop(s, why)
	if scan ~= s then
		return
	end
	scan = nil
	changed()
	ns.status(string.format("%s, scan stopped at %d/%d. /pb scan picks up "
		.. "where it left off.", why, s.i - 1, #s.ids))
end

-- Runs fn(...) for a timer or event. An error ends the running scan, so it
-- can't stay stuck as running, and goes to the error handler (BugSack).
function guarded(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		if scan then
			stop(scan, "Something went wrong")
		end
		geterrorhandler()(err)
	end
end

local function later(s)
	s.waits = s.waits + 1
	if s.waits > WAIT_TICKS then
		s.failed = s.failed + 1
		return advance(s)
	end
	C_Timer.After(0.1, function() guarded(send, s) end)
end

-- The AH ignores searches for item keys the client hasn't cached, and
-- for anything sent while it's throttled, so both are waited out.
function send(s)
	if scan ~= s then
		return
	end
	if not ns.ahOpen() then
		return stop(s, "The AH closed")
	end
	s.token = nil
	if not C_AuctionHouse.IsThrottledMessageSystemReady()
			or not C_AuctionHouse.GetItemKeyInfo(s.key) then
		return later(s)
	end
	C_AuctionHouse.SendSellSearchQuery(s.key, SORTS, true)
	await(s)
end

local function summary(s)
	if #s.ids == 0 then
		return "random-suffix prices for your level are up to date."
	end
	local failed = s.failed > 0
		and (", " .. s.failed .. " didn't answer") or ""
	return string.format("suffix scan done: %d items, %d versions "
		.. "priced%s.", #s.ids, s.found, failed)
end

-- With the window open the plan refreshes itself; otherwise say so.
local function complete(s)
	scan = nil
	scans()[ns.character()] = {
		time = time(), level = UnitLevel("player"), items = #s.ids,
		versions = s.found, empty = s.empty, failed = s.failed,
	}
	changed()
	if ns.ui and ns.ui:IsShown() then
		return ns.ui:Plan(summary(s))
	end
	ns.say(summary(s) .. " Type /pb to plan.")
end

-- Every item in the window, every quarter in chat.
local function progress(s)
	local text = string.format("scanned %d/%d", s.i - 1, #s.ids)
	if ns.ui and ns.ui:IsShown() then
		return ns.ui:SetStatus("Suffix scan: " .. text)
	end
	local step = math.max(1, math.floor(#s.ids / 4))
	if s.i > 1 and s.i <= #s.ids and (s.i - 1) % step == 0 then
		ns.say(text)
	end
end

function advance(s)
	s.i = s.i + 1
	if s.i > #s.ids then
		return complete(s)
	end
	progress(s)
	s.key = C_AuctionHouse.MakeItemKey(s.ids[s.i])
	s.tries, s.waits = 0, 0
	send(s)
end

local function save(s)
	local variants = readVariants(s.key)
	cache()[s.key.itemID] = { time = time(), variants = variants }
	s.found = s.found + #variants
	if #variants == 0 then
		s.empty = s.empty + 1
	end
	advance(s)
end

-- Results can arrive empty or in parts: an empty reply is retried, a
-- partial one asks for more until MAX_RESULTS.
local function onResults(itemKey)
	local s = scan
	if not (s and s.token and s.key and itemKey
			and itemKey.itemID == s.key.itemID) then
		return
	end
	if not C_AuctionHouse.HasSearchResults(s.key) then
		return retry(s)
	end
	local n = C_AuctionHouse.GetNumItemSearchResults(s.key)
	if C_AuctionHouse.HasFullItemSearchResults(s.key)
			or n >= MAX_RESULTS then
		return save(s)
	end
	if n == 0 then
		return retry(s)
	end
	C_AuctionHouse.RequestMoreItemSearchResults(s.key)
	await(s)
end

local function begin(s)
	if scan ~= s then
		return
	end
	if #s.ids == 0 then
		return complete(s)
	end
	ns.status(string.format("scanning %d random-suffix items. Keep "
		.. "the AH open; /pb stop cancels.", #s.ids))
	advance(s)
end

function ns.scan()
	if scan then
		local done = math.max(0, scan.i - 1)
		return ns.status(string.format("already scanning (%d/%d). "
			.. "/pb stop cancels.", done, #scan.ids))
	end
	if not ns.ahOpen() then
		return ns.status("open the auction house first.")
	end
	local missing = ns.missing()
	if missing then
		return ns.status(missing)
	end
	local adb = ns.auctionator()
	local scale = ns.pickScale()
	if not scale then
		return ns.status("no Pawn scale is visible. Show one in /pawn.")
	end
	local ids, age = ns.freshItems(adb, scale)
	if not age then
		return ns.status("no AH data. Run a full Auctionator scan.")
	end
	local s = { ids = {}, i = 0, found = 0, empty = 0, failed = 0 }
	scan = s
	changed()
	local level, now = UnitLevel("player"), time()
	local function pick(id)
		if wanted(id, level, now) then
			s.ids[#s.ids + 1] = id
		end
	end
	ns.status("preparing the suffix scan...")
	ns.loadItems(ids, function()
		ns.each(ids, pick, function() begin(s) end, function()
			scan = nil
			changed()
		end)
	end)
end

function ns.stopScan()
	if not scan then
		return ns.status("no scan running.")
	end
	stop(scan, "Cancelled")
end

local function prune()
	local cutoff = time() - KEEP_DAYS * 86400
	for _, items in pairs(ns.db().suffix or {}) do
		for id, entry in pairs(items) do
			if entry.time < cutoff then
				items[id] = nil
			end
		end
	end
end

local function remind()
	if scan or time() - remindedAt < REMIND_EVERY then
		return
	end
	local notice = ns.suffixNotice()
	if notice then
		remindedAt = time()
		ns.say(notice)
	end
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW",
		"AUCTION_HOUSE_CLOSED", "ITEM_SEARCH_RESULTS_UPDATED",
		"ITEM_SEARCH_RESULTS_ADDED" }) do
	pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		prune()
	elseif event == "AUCTION_HOUSE_SHOW" then
		ahOpen = true
		changed()
		-- After Auctionator's own messages.
		C_Timer.After(2, remind)
	elseif event == "AUCTION_HOUSE_CLOSED" then
		ahOpen = false
		changed()
	else
		guarded(onResults, ...)
	end
end)
