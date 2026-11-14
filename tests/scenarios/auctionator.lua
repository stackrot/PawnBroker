-- PawnBroker reads a few of Auctionator's own tables, not just its API.
-- If a later Auctionator stores them differently, planning still works:
-- the listing counts and full-scan date just go missing.
Auctionator.SavedState = { TimeOfLastBrowseScan = "yesterday" }
Auctionator.Constants = { SCAN_DAY_0 = {} }
for _, entry in pairs(Auctionator.Database.db) do
	entry.a = "compressed"
end
pb("all") run()
local planned = 0
for _, r in ipairs(NS.ui.rows) do
	if r.shown and r.option then
		planned = planned + 1
		assert(r.option.listed == nil, r.option.name)
	end
end
assert(planned > 0, "nothing planned")
