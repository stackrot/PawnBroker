-- A full suffix scan through throttling, dropped and partial replies,
-- then a plan that uses the cached versions.
pb("scan") run()
assert(NS.ui.status.text:find("auction house"), NS.ui.status.text)
fire("AUCTION_HOUSE_SHOW") run()
NS.ui.budget:SetText("") NS.ui.ahead:SetText("")
pb("scan") run(clock() + 3)
assert(NS.ui.scanButton.text == "Stop scan")
run()
local scan = PawnBrokerDB.scans["Tester-Test Realm"]
assert(scan.items == 84 and scan.versions == 345 and scan.failed == 0,
	scan.items .. " " .. scan.versions .. " " .. scan.failed)
assert(STATS.dropped > 0 and STATS.more > 0)
assert(NS.ui.scanButton.text == "Scan suffixes")
assert(NS.ui.status.text:find("^Suffix scan done"), NS.ui.status.text)
local suffixed = false
for _, r in ipairs(NS.ui.rows) do
	if r.shown and r.option and r.option.name:find(" of ") then
		suffixed = true
	end
end
assert(suffixed, "no suffix versions in the plan")
pb("scan") run()
assert(NS.ui.status.text:find("up to date"), NS.ui.status.text)
