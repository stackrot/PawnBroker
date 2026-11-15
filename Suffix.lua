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
local GIVE_UP = 4	-- searches in a row without an answer before stopping
local KEY_WAIT = 3	-- seconds to wait for an item's AH data
local READY_WAIT = 10	-- seconds to wait for the AH to take a search
local FALLBACK = 0.2	-- seconds between checks when an AH event is late
local PREFETCH = 5	-- items ahead whose AH data is asked for early
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

-- A random-suffix item in scan range that isn't freshly cached, or nil
-- while the client has no data for the item, so it can't tell yet.
local function wanted(id, level, now)
	local _, link, quality, _, minLevel = C_Item.GetItemInfo(id)
	if not link then
		return nil
	end
	minLevel = minLevel or 0
	if minLevel > level + ns.SCAN_AHEAD
			or minLevel < level - ns.SCAN_BELOW then
		return false
	end
	local entry = cache()[id]
	if entry and now - entry.time < REUSE then
		return false
	end
	-- The armour type was already checked when the items were picked
	-- (ns.wearable), so the verdict is all that's left.
	local verdict = ns.verdict(link, quality)
	return verdict.random == true and not verdict.unusable
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

local send, advance, guarded, missed

local function fail(s)
	s.failed = s.failed + 1
	advance(s)
end

local function retry(s)
	s.tries = s.tries + 1
	if s.tries < TRIES then
		return send(s)
	end
	fail(s)
end

local function timedOut(s)
	if not missed(s) then
		retry(s)
	end
end

-- Waits TIMEOUT for an answer; a newer wait or a reply cancels this one.
local function await(s)
	local token = {}
	s.token = token
	C_Timer.After(TIMEOUT, function()
		if scan == s and s.token == token then
			guarded(timedOut, s)
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
	ns.status(string.format("Suffix scan stopped at %d/%d (%s). /pb scan picks up where it left off.", s.i - 1, #s.ids, why))
end

-- A search or wait that got nothing back. Several in a row, across items,
-- means the AH has stopped answering at all, so the scan stops rather
-- than wait out every item. True once it has stopped.
function missed(s)
	s.misses = s.misses + 1
	if s.misses >= GIVE_UP then
		stop(s, "the AH stopped answering")
		return true
	end
end

-- Runs fn(...) for a timer or event. An error ends the running scan, so it
-- can't stay stuck as running, and goes to the error handler (BugSack).
function guarded(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		if scan then
			stop(scan, "Lua error")
		end
		geterrorhandler()(err)
	end
end

-- Waits for the item key or the throttle. Their events send at once; a
-- timer checks again in case one never comes, up to limit seconds in.
local function later(s, what, limit)
	s.waitStart = s.waitStart or GetTime()
	if GetTime() - s.waitStart > limit then
		s.waitStart = nil
		if not missed(s) then
			fail(s)
		end
		return
	end
	s.waiting = what
	local token = {}
	s.waitToken = token
	C_Timer.After(FALLBACK, function()
		if scan == s and s.waitToken == token then
			guarded(send, s)
		end
	end)
end

-- The AH ignores searches for item keys the client hasn't cached, and
-- for anything sent while it's throttled, so both are waited out.
function send(s)
	if scan ~= s then
		return
	end
	if not ns.ahOpen() then
		return stop(s, "the AH closed")
	end
	s.token, s.waiting, s.waitToken = nil, nil, nil
	if not C_AuctionHouse.GetItemKeyInfo(s.key) then
		return later(s, "key", KEY_WAIT)
	end
	if not C_AuctionHouse.IsThrottledMessageSystemReady() then
		return later(s, "ready", READY_WAIT)
	end
	s.waitStart = nil
	C_AuctionHouse.SendSellSearchQuery(s.key, SORTS, true)
	await(s)
end

-- Items whose data the client never loaded couldn't be checked at all.
-- After an Auctionator full scan that can last until you log out.
local function unloadedNote(s)
	if s.unloaded == 0 then
		return ""
	end
	local items = s.unloaded == 1 and "1 item"
		or (s.unloaded .. " items")
	return string.format(" %s didn't load and couldn't be checked. Type /pb scan again, or log out and back in if it keeps happening.", items)
end

local function summary(s)
	if #s.ids == 0 and s.unloaded > 0 then
		return "nothing scanned." .. unloadedNote(s)
	end
	if #s.ids == 0 then
		return "random-suffix prices for your level are up to date."
	end
	local failed = s.failed > 0
		and (", " .. s.failed .. " didn't answer") or ""
	local again = (s.failed > 0 and s.unloaded == 0)
		and " Type /pb scan to try again." or ""
	return string.format("suffix scan done: %d items, %d versions priced%s.", #s.ids, s.found, failed) .. again .. unloadedNote(s)
end

-- With the window open the plan refreshes itself; otherwise say so.
-- A scan that couldn't price every item isn't recorded, so the window
-- keeps asking for one.
local function complete(s)
	scan = nil
	if s.unloaded == 0 and s.failed == 0 then
		scans()[ns.character()] = {
			time = time(), level = UnitLevel("player"),
			items = #s.ids, versions = s.found, empty = s.empty,
			failed = s.failed,
		}
	end
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
	s.tries, s.waitStart = 0, nil
	-- Asking for an item key starts loading it, so the next few are
	-- ready by their turn.
	for i = s.i + 1, math.min(s.i + PREFETCH, #s.ids) do
		C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(s.ids[i]))
	end
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
	s.misses = 0
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

-- 1 for items a plan can use now, 2 for off hands a two-hander rules
-- out, 3 for items above your level plus Levels above.
local function rank(id, maxLevel, twoHanded)
	local level = select(5, C_Item.GetItemInfo(id)) or 0
	if level > maxLevel then
		return 3, level
	end
	local loc = select(4, C_Item.GetItemInfoInstant(id))
	if twoHanded and ns.OFF_HAND[loc] then
		return 2, level
	end
	return 1, level
end

-- Best rank first, then closest to your level, so a scan stopped early
-- has already priced the items that matter most.
local function order(ids)
	local ahead = tonumber((ns.db().ui or {}).ahead) or 0
	local maxLevel = UnitLevel("player") + ahead
	local twoHanded = ns.twoHanded()
	local ranks, levels = {}, {}
	for _, id in ipairs(ids) do
		ranks[id], levels[id] = rank(id, maxLevel, twoHanded)
	end
	table.sort(ids, function(a, b)
		if ranks[a] ~= ranks[b] then
			return ranks[a] < ranks[b]
		end
		if levels[a] ~= levels[b] then
			return levels[a] > levels[b]
		end
		return a < b
	end)
end

local function onReady()
	if scan and scan.waiting == "ready" then
		send(scan)
	end
end

local function onKey(itemID)
	local s = scan
	if s and s.waiting == "key" and s.key.itemID == itemID then
		send(s)
	end
end

-- The AH dropped a message, maybe this scan's search, so it's sent again
-- now rather than after the timeout. That doesn't count as a try.
local function onDropped()
	if scan and scan.token then
		send(scan)
	end
end

local function begin(s)
	if scan ~= s then
		return
	end
	if #s.ids == 0 then
		return complete(s)
	end
	order(s.ids)
	ns.status(string.format("scanning %d random-suffix items. Keep the AH open; /pb stop cancels.", #s.ids))
	advance(s)
end

function ns.scan()
	if scan then
		local done = math.max(0, scan.i - 1)
		return ns.status(string.format("already scanning (%d/%d). /pb stop cancels.", done, #scan.ids))
	end
	if not ns.ahOpen() then
		return ns.status("open the AH first.")
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
	local s = {
		ids = {}, i = 0, found = 0, empty = 0, failed = 0, unloaded = 0,
		misses = 0,
	}
	scan = s
	changed()
	local level, now = UnitLevel("player"), time()
	local function pick(id)
		local want = wanted(id, level, now)
		if want == nil then
			s.unloaded = s.unloaded + 1
		elseif want then
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
	stop(scan, "cancelled")
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

local SCAN_EVENTS = {
	ITEM_SEARCH_RESULTS_UPDATED = onResults,
	ITEM_SEARCH_RESULTS_ADDED = onResults,
	AUCTION_HOUSE_THROTTLED_SYSTEM_READY = onReady,
	ITEM_KEY_ITEM_INFO_RECEIVED = onKey,
	AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED = onDropped,
}

local frame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW",
		"AUCTION_HOUSE_CLOSED" }) do
	pcall(frame.RegisterEvent, frame, event)
end
for event in pairs(SCAN_EVENTS) do
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
	elseif SCAN_EVENTS[event] then
		guarded(SCAN_EVENTS[event], ...)
	end
end)
