-- Each faction has its own AH on Forever, so suffix prices are kept per
-- realm and faction. Realm-only prices from before go unused and expire.
-- Suffix versions search the AH by base name, everything else by exact
-- quoted name.
local function suffixRows()
	local n = 0
	for _, r in ipairs(NS.ui.rows) do
		if r.shown and r.option and r.option.search:sub(1, 1) ~= '"' then
			n = n + 1
		end
	end
	return n
end

fire("AUCTION_HOUSE_SHOW") run()
pb("scan") run()
local db = PawnBrokerDB
local alliance = db.suffix["Test Realm Alliance"]
assert(alliance and next(alliance), "nothing cached for Alliance")
assert(suffixRows() > 0, "no suffix versions in the Alliance plan")

-- A realm-only entry for every item, far cheaper than anything listed.
local old = {}
for id, entry in pairs(alliance) do
	old[id] = { time = time(), variants = {} }
	for _, v in ipairs(entry.variants) do
		table.insert(old[id].variants, { link = v.link, price = 1 })
	end
end
db.suffix["Test Realm"] = old

FACTION = "Horde"
pb("") run()
assert(suffixRows() == 0, "Horde plan used another market's prices")
assert(NS.ui.notes.text:find("aren't priced yet"), NS.ui.notes.text)
assert(db.suffix["Test Realm Horde"] == nil
	or next(db.suffix["Test Realm Horde"]) == nil)

FACTION = nil
pb("") run()
for _, r in ipairs(NS.ui.rows) do
	assert(not (r.shown and r.option and r.option.price == 1),
		"plan used a realm-only price")
end

advanceClock(8 * 86400)
fire("PLAYER_LOGIN")
assert(db.suffix["Test Realm"] == nil, "realm-only prices kept")
