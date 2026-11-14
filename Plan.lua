-- The planner: scores every wearable item in the latest Auctionator scan
-- with Pawn's visible scale, compares it with what is equipped, and picks
-- the buys (at most one per slot group) with the largest total Pawn gain
-- that fit the budget. Random-suffix items are priced per version from
-- the /pb scan cache. Results go to the window, to an Auctionator
-- shopping list and, as plain text, to PawnBrokerDB.report.

local _, ns = ...

local BUCKETS = 1000	-- budget resolution of the knapsack
local GEAR_TRIES = 20	-- half-second waits for Pawn to read your gear
local OVER_BUDGET = 5	-- out-of-budget items worth mentioning
local NEAR_MAX = 8	-- near-vendor alternatives worth mentioning

local SLOTS = {
	Head = { 1 }, Neck = { 2 }, Shoulder = { 3 }, Chest = { 5 },
	Waist = { 6 }, Legs = { 7 }, Feet = { 8 }, Wrist = { 9 },
	Hands = { 10 }, Finger = { 11, 12 }, Trinket = { 13, 14 },
	Back = { 15 }, Ranged = { 18 },
}
local OFF_HAND = {
	INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true,
	INVTYPE_HOLDABLE = true,
}

local NOTHING = "Nothing in the scan beats your gear within budget."

local busy = false

-- Pawn's unenchanted score, the figure its own upgrade arrows compare.
local function score(item, scale)
	local _, value = PawnGetSingleValueFromItem(item, scale)
	return value or 0
end

-- nil while the slot holds an item Pawn hasn't read yet.
local function slotScore(slot, scale)
	local item, had = PawnGetItemDataForInventorySlot(slot, true)
	if had and not item then
		return nil
	end
	return item and score(item, scale) or 0
end

-- Scores to beat for each slot group, plus the weapon set-up. A slot
-- Pawn can't read counts as empty and its item goes in base.unread.
local function baselines(scale)
	local base = { unread = {} }
	local function read(slot)
		local value = slotScore(slot, scale)
		if value then
			return value
		end
		table.insert(base.unread, GetInventoryItemLink("player", slot))
		return 0
	end
	for group, slots in pairs(SLOTS) do
		for _, slot in ipairs(slots) do
			local value = read(slot)
			base[group] = math.min(base[group] or value, value)
		end
	end
	base.main, base.off = read(16), read(17)
	local link = GetInventoryItemLink("player", 16)
	local loc = link and select(4, C_Item.GetItemInfoInstant(link))
	base.twoHanded = loc == "INVTYPE_2HWEAPON"
	return base
end

-- What an item of this equip location replaces, or nil when it can't be
-- worn with the current weapons (an off hand beside a two-hander).
local function baseline(base, loc)
	local group = ns.GROUPS[loc]
	if group ~= "Weapon" then
		return base[group]
	end
	if loc == "INVTYPE_2HWEAPON" then
		return base.main + base.off
	end
	if not OFF_HAND[loc] then
		return base.main
	end
	if not base.twoHanded then
		return base.off
	end
end

local function count(ctx, why)
	ctx.skipped[why] = (ctx.skipped[why] or 0) + 1
end

-- Adds o (name, link, search, price, vendor, listed) as an option when Pawn
-- rates it above what it would replace. Its net cost is what it costs once
-- it's sold back to a vendor.
local function offer(ctx, o, loc, beat, level)
	local item = PawnGetItemData(o.link)
	if not item then
		return count(ctx, "unread")
	end
	local gain = score(item, ctx.scale) - beat
	-- Pawn ignores anything less than half a percent better.
	if not PawnIsArmorBestTypeForPlayer(item) or gain <= 0
			or gain <= beat * 0.005 then
		return
	end
	o.gain, o.beat, o.level, o.group = gain, beat, level, ns.GROUPS[loc]
	o.net = o.price - o.vendor
	ctx.groups[o.group] = ctx.groups[o.group] or {}
	table.insert(ctx.groups[o.group], o)
end

local function inScanRange(ctx, level)
	return level >= ctx.level - ns.SCAN_BELOW
		and level <= ctx.level + ns.SCAN_AHEAD
end

-- Each cached version of a random-suffix item is its own option. The
-- shopping list searches the base name, which finds every version.
local function offerVariants(ctx, id, loc, beat, level, vendor)
	local variants, read = ns.variants(id)
	if not variants then
		if inScanRange(ctx, level) then
			ctx.unscanned = ctx.unscanned + 1
		end
		return
	end
	ctx.suffixRead = math.min(ctx.suffixRead or read, read)
	local base = C_Item.GetItemInfo(id)
	for _, v in ipairs(variants) do
		offer(ctx, {
			name = v.link:match("%[(.-)%]") or base, link = v.link,
			search = base, price = v.price, vendor = vendor,
			listed = v.count,
		}, loc, beat, level)
	end
end

local function consider(ctx, id)
	local name, link, quality, _, level, _, _, _, loc, _, sell =
		C_Item.GetItemInfo(id)
	if not link then
		return count(ctx, "unread")
	end
	level = level or 0
	local beat = baseline(ctx.base, loc)
	if level > ctx.maxLevel or not beat then
		return
	end
	local verdict = ns.verdict(link, quality)
	if verdict.unusable then
		return count(ctx, "unusable")
	end
	if verdict.random then
		return offerVariants(ctx, id, loc, beat, level, sell or 0)
	end
	local price = Auctionator.API.v1.GetAuctionPriceByItemID(ns.ADDON, id)
	if price then
		offer(ctx, {
			name = name, link = link, search = '"' .. name .. '"',
			price = price, vendor = sell or 0,
			listed = ns.listed(ctx.db, id),
		}, loc, beat, level)
	end
end

-- Cheapest first, dropping anything a cheaper option already beats, so
-- the strongest option is always last. Cost is the price, or the net cost
-- when planning by net cost.
local function frontier(options)
	table.sort(options, function(a, b)
		if a.cost ~= b.cost then
			return a.cost < b.cost
		end
		return a.gain > b.gain
	end)
	local kept, best = {}, 0
	for _, o in ipairs(options) do
		if o.gain > best then
			kept[#kept + 1] = o
			best = o.gain
		end
	end
	return kept
end

-- The best gain within capacity c, adding at most one of the options.
local function bestWith(best, options, c, unit)
	local gain, pick = best[c], 0
	for i, o in ipairs(options) do
		local w = math.ceil(o.cost / unit)
		if w <= c and best[c - w] + o.gain > gain then
			gain, pick = best[c - w] + o.gain, i
		end
	end
	return gain, pick
end

-- Multiple-choice knapsack: at most one option per group, total cost
-- within budget, total gain as high as possible. Costs round up to the
-- bucket size, so a plan never goes over.
local function knapsack(groups, budget)
	local unit = math.max(1, math.ceil(budget / BUCKETS))
	local cap = math.floor(budget / unit)
	local best, picks = {}, {}
	for c = 0, cap do
		best[c] = 0
	end
	for g, options in ipairs(groups) do
		local nextBest, pick = {}, {}
		for c = 0, cap do
			nextBest[c], pick[c] = bestWith(best, options, c, unit)
		end
		best, picks[g] = nextBest, pick
	end
	local chosen, c = {}, cap
	for g = #groups, 1, -1 do
		local o = groups[g][picks[g][c]]
		if o then
			chosen[#chosen + 1] = o
			c = c - math.ceil(o.cost / unit)
		end
	end
	return chosen
end

local function strongest(groups)
	local chosen = {}
	for _, options in ipairs(groups) do
		chosen[#chosen + 1] = options[#options]
	end
	return chosen
end

-- The strongest item per group when it beats what the plan bought there.
local function overBudget(groups, chosen)
	local picked, over = {}, {}
	for _, o in ipairs(chosen) do
		picked[o.group] = o
	end
	for _, best in ipairs(strongest(groups)) do
		if best ~= picked[best.group] then
			over[#over + 1] = best
		end
	end
	table.sort(over, function(a, b) return a.gain > b.gain end)
	for i = #over, OVER_BUDGET + 1, -1 do
		over[i] = nil
	end
	return over
end

-- Upgrades within the budget that cost at most ctx.near once sold to a
-- vendor: the best one per slot group, unless the plan already buys it.
local function nearVendor(ctx, chosen)
	if not ctx.near then
		return {}
	end
	local picked, near = {}, {}
	for _, o in ipairs(chosen) do
		picked[o.group] = o
	end
	for group, options in pairs(ctx.groups) do
		local best
		for _, o in ipairs(options) do
			if o.net <= ctx.near and (not ctx.budget or o.cost <= ctx.budget)
					and (not best or o.gain > best.gain) then
				best = o
			end
		end
		if best and best ~= picked[group] then
			near[#near + 1] = best
		end
	end
	table.sort(near, function(a, b) return a.gain > b.gain end)
	for i = #near, NEAR_MAX + 1, -1 do
		near[i] = nil
	end
	return near
end

-- "+454%" against what the slot holds, or "empty slot".
function ns.percent(o)
	if o.beat <= 0 then
		return "empty slot"
	end
	return string.format("+%d%%", math.floor(o.gain / o.beat * 100 + 0.5))
end

local function describe(o)
	return string.format("%s: %s %s, net %s, +%.1f Pawn (%s), req %d%s",
		o.group, o.name, ns.money(o.price), ns.netText(o, ns.money), o.gain,
		ns.percent(o), o.level,
		o.listed and (", " .. o.listed .. " listed") or "")
end

local function header(ctx)
	local scale = PawnGetScaleLocalizedName
		and PawnGetScaleLocalizedName(ctx.scale) or ctx.scale
	if ctx.visible > 1 then
		scale = scale .. " (first of " .. ctx.visible
			.. " visible scales; hide the others in Pawn to change)"
	end
	local ahead = ctx.maxLevel > ctx.level
		and (", items up to " .. ctx.maxLevel) or ""
	local budget = ctx.budget and ns.money(ctx.budget) or "unlimited"
	local age = ctx.age == 0 and "today's AH scan"
		or (ctx.age .. "-day-old AH scan")
	return string.format("%s, level %d%s, %sbudget %s, %s.", scale,
		ctx.level, ahead, ctx.net and "net " or "", budget, age)
end

local function unreadLine(base)
	local names = {}
	for _, link in ipairs(base.unread) do
		names[#names + 1] = link:match("%[(.-)%]") or link
	end
	if #names > 0 then
		local slots = #names == 1 and "that slot" or "those slots"
		return "Pawn couldn't read your " .. table.concat(names, ", ")
			.. ", so the plan treats " .. slots .. " as empty."
	end
end

local function skippedLine(skipped)
	local parts = {}
	if skipped.unusable then
		parts[#parts + 1] = skipped.unusable .. " you can't use yet"
	end
	local unread = skipped.unread
	if unread then
		parts[#parts + 1] = unread .. " that didn't load (plan again)"
	end
	if #parts > 0 then
		return "Skipped " .. table.concat(parts, ", ") .. "."
	end
end

local function suffixLine(ctx)
	if ctx.unscanned > 0 then
		return ctx.unscanned .. " random-suffix items for your level "
			.. "aren't priced yet. Scan suffixes with the AH open."
	end
	local notice = ns.suffixNotice()
	if notice or not ctx.suffixRead then
		return notice
	end
	local hours = math.floor((time() - ctx.suffixRead) / 3600)
	local age = hours < 1 and "under an hour" or ("up to " .. hours .. "h")
	return "Random-suffix prices from the suffix scan, " .. age .. " old."
end

local function shoppingList(chosen)
	local terms, seen = {}, {}
	for _, o in ipairs(chosen) do
		if not seen[o.search] then
			seen[o.search] = true
			terms[#terms + 1] = o.search
		end
	end
	Auctionator.API.v1.CreateShoppingList(ns.ADDON, ns.ADDON, terms)
end

-- "Buy 2 for 1g 40s (net 1g 5s), +24.3 Pawn", led by the net cost when the
-- plan was made by it. money is ns.money or ns.coins.
function ns.buyLine(r, money)
	local total, net = money(r.total), ns.netText({ net = r.net }, money)
	if r.byNet then
		return string.format("Buy %d for %s net (%s up front), +%.1f Pawn",
			#r.chosen, net, total, r.gain)
	end
	return string.format("Buy %d for %s (net %s), +%.1f Pawn", #r.chosen,
		total, net, r.gain)
end

-- A plain-text copy of the plan for PawnBrokerDB.report, readable from the
-- saved variables file after a /reload.
local function plainLines(r)
	local out = { r.header }
	if #r.chosen == 0 then
		out[#out + 1] = NOTHING
	else
		out[#out + 1] = ns.buyLine(r, ns.money) .. ":"
	end
	for _, o in ipairs(r.chosen) do
		out[#out + 1] = "  " .. describe(o)
	end
	if #r.over > 0 then
		out[#out + 1] = "Better, but over budget:"
	end
	for _, o in ipairs(r.over) do
		out[#out + 1] = "  " .. describe(o)
	end
	if #r.near > 0 then
		out[#out + 1] = string.format("Near vendor price (net %s or less):",
			ns.money(r.nearLimit))
	end
	for _, o in ipairs(r.near) do
		out[#out + 1] = "  " .. describe(o)
	end
	for _, note in ipairs(r.notes) do
		out[#out + 1] = note
	end
	return out
end

local function report(ctx, chosen, over)
	local r = { header = header(ctx), chosen = chosen, over = over,
		near = nearVendor(ctx, chosen), nearLimit = ctx.near,
		byNet = ctx.net, notes = {}, total = 0, net = 0, gain = 0 }
	for _, o in ipairs(chosen) do
		r.total, r.net = r.total + o.price, r.net + o.net
		r.gain = r.gain + o.gain
	end
	local function note(text)
		r.notes[#r.notes + 1] = text
	end
	if ctx.net and r.total > GetMoney() then
		note(string.format("That plan needs %s up front; you carry %s.",
			ns.money(r.total), ns.money(GetMoney())))
	end
	note(unreadLine(ctx.base))
	note(suffixLine(ctx))
	note(skippedLine(ctx.skipped))
	if #chosen > 0 then
		shoppingList(chosen)
		note('Auctionator shopping list "' .. ns.ADDON .. '" updated.')
	end
	ns.db().report = { time = date("%Y-%m-%d %H:%M"),
		lines = plainLines(r) }
	ns.ui:ShowPlan(r)
end

local function finish(ctx)
	busy = false
	local groups = {}
	for _, options in pairs(ctx.groups) do
		for _, o in ipairs(options) do
			o.cost = ctx.net and math.max(0, o.net) or o.price
		end
		groups[#groups + 1] = frontier(options)
	end
	local chosen = ctx.budget and knapsack(groups, ctx.budget)
		or strongest(groups)
	table.sort(chosen, function(a, b) return a.gain > b.gain end)
	report(ctx, chosen, overBudget(groups, chosen))
end

-- Builds the run's context, or returns nil and the reason it can't start.
local function prepare(opts)
	local missing = ns.missing()
	if missing then
		return nil, missing
	end
	local db = ns.auctionator()
	local scale, visible = ns.pickScale()
	if not scale then
		return nil, "no Pawn scale is visible. Show one in /pawn."
	end
	local ids, age = ns.freshItems(db, scale)
	if not age then
		return nil, "no AH data. Run a full Auctionator scan first."
	end
	local level = UnitLevel("player")
	return {
		db = db, scale = scale, visible = visible,
		ids = ids, age = age, level = level,
		maxLevel = level + opts.ahead, budget = opts.budget,
		near = opts.near, net = opts.net,
		groups = {}, skipped = {}, unscanned = 0,
	}
end

-- Pawn reads an item only once the client has cached it, which can lag
-- a login or a gear change, so this waits up to GEAR_TRIES half-seconds
-- before treating any slot it still can't read as empty.
local function readGear(ctx, tries, done)
	local ok, err = pcall(function()
		ctx.base = baselines(ctx.scale)
	end)
	if not ok then
		busy = false
		return geterrorhandler()(err)
	end
	if #ctx.base.unread == 0 or tries >= GEAR_TRIES then
		return done()
	end
	C_Timer.After(0.5, function() readGear(ctx, tries + 1, done) end)
end

local function loadGear()
	for slot = 1, 18 do
		local id = GetInventoryItemID("player", slot)
		if id and C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(id)
		end
	end
end

local function loading(loaded, total)
	ns.status(string.format("loading item data %d/%d...", loaded, total))
end

local function run(opts)
	if busy then
		return ns.status("still working on the last plan.")
	end
	local ctx, err = prepare(opts)
	if not ctx then
		return ns.status(err)
	end
	busy = true
	ns.status(string.format("checking %d items...", #ctx.ids))
	loadGear()
	readGear(ctx, 0, function()
		-- An error here would otherwise leave busy set until a /reload.
		local ok, e = pcall(ns.loadItems, ctx.ids, function()
			ns.each(ctx.ids, function(id) consider(ctx, id) end,
				function() finish(ctx) end,
				function() busy = false end)
		end, loading)
		if not ok then
			busy = false
			geterrorhandler()(e)
		end
	end)
end

-- "1g50s" as copper.
function ns.copper(word)
	local g = tonumber(word:match("(%d+)g")) or 0
	local s = tonumber(word:match("(%d+)s")) or 0
	local c = tonumber(word:match("(%d+)c")) or 0
	return g * 10000 + s * 100 + c
end

-- "", "1g50s", "all +2", "net": the budget defaults to the gold you carry,
-- "all" lifts it, +N includes items up to N levels above yours, and "net"
-- plans by net cost (what's left after selling the items to a vendor).
function ns.parse(msg)
	local opts = { ahead = 0, budget = GetMoney() }
	for word in msg:lower():gmatch("%S+") do
		local ahead = word:match("^%+(%d+)$")
		if ahead then
			opts.ahead = tonumber(ahead)
		elseif word == "all" then
			opts.budget = nil
		elseif word == "net" then
			opts.net = true
		elseif word:find("^[%dgsc]+$") and word:find("%d[gsc]") then
			opts.budget = ns.copper(word)
		else
			return nil
		end
	end
	return opts
end

function ns.plan(opts)
	run(opts)
end
