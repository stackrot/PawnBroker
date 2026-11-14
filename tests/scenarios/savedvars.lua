-- Saved data from an older version or edited by hand can hold anything.
-- The addon drops what it can't use instead of erroring, and keeps the
-- rest.
local good = { time = time(), variants = {
	{ link = "item:6541:0:0:0:0:0:1|h[Willow Gloves of the Owl]", price = 500,
		count = 2 },
} }
PawnBrokerDB = {
	ui = { budget = 5, ahead = {}, net = "yes", near = -1 },
	scans = { ["Tester-Test Realm"] = { time = "soon" }, other = 7 },
	suffix = {
		["Test Realm"] = {
			[6541] = good,
			[1] = { time = 1 },
			[2] = { time = time(), variants = { { link = 4, price = 1 } } },
			[3] = "junk",
		},
		["Bad Realm"] = 12,
	},
	report = "old",
}
fire("PLAYER_LOGIN")
pb("") run()
fire("AUCTION_HOUSE_SHOW") run()
local db = PawnBrokerDB
assert(db.ui.budget == "" and db.ui.ahead == "", "ui reset")
assert(db.ui.net == false and db.ui.near == nil, "net and near reset")
assert(db.scans["Tester-Test Realm"] == nil and db.scans.other == nil)
local realm = db.suffix["Test Realm"]
assert(realm[6541] == good, "good entry dropped")
assert(realm[1] == nil and realm[2] == nil and realm[3] == nil)
assert(db.suffix["Bad Realm"] == nil)
assert(type(db.report) == "table" and #db.report.lines > 0)
-- Not even a table.
PawnBrokerDB = "garbage"
pb("") run()
assert(type(PawnBrokerDB) == "table" and PawnBrokerDB.report)
