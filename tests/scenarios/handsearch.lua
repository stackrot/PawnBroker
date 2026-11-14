-- A search by hand the day after a full scan dates only the items it
-- finds. The plan still uses everything the full scan saw, and nothing
-- from before it.
local function names(rows)
	local out = {}
	for _, r in ipairs(rows) do
		if r.shown and r.option then
			out[#out + 1] = r.option.name
		end
	end
	return table.concat(out, ",")
end
MOCK_TODAY = 2506
local zero = time() - 2506 * 86400 - 3600
Auctionator.Constants = { SCAN_DAY_0 = zero }
Auctionator.SavedState = { TimeOfLastBrowseScan = zero + 2504 * 86400 + 7200 }
MOCK[6240].h[2505], MOCK[6240].a[2505] = 300, 30
pb("") run()
local plan = names(NS.ui.rows)
assert(plan:find("Gnoll Casting Gloves") and plan:find("Colorful Kilt"),
	plan)
assert(NS.ui.header.text:find("2%-day%-old AH scan"), NS.ui.header.text)
-- Black Pearl Ring was last listed the day before the full scan.
pb("all") run()
assert(not names(NS.ui.rows):find("Black Pearl Ring"), names(NS.ui.rows))
-- Without a full scan on record, the newest day is all there is.
Auctionator.SavedState = {}
pb("all") run()
assert(NS.ui.header.text:find("1%-day%-old AH scan"), NS.ui.header.text)
assert(not names(NS.ui.rows):find("Gnoll Casting Gloves"),
	names(NS.ui.rows))
