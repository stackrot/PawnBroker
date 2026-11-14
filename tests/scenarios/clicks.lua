-- Row clicks search the AH (exact for normal items, base name for
-- suffix ones) and say so when the AH is closed.
fire("AUCTION_HOUSE_SHOW") run()
pb("scan") run()
SEARCHES = {}
for _, r in ipairs(NS.ui.rows) do
	if r.shown and r.option then
		r.scripts.OnEnter(r)
		r.scripts.OnClick(r)
	end
end
assert(SEARCHES.exact and SEARCHES.loose, "both search kinds")
fire("AUCTION_HOUSE_CLOSED")
for _, r in ipairs(NS.ui.rows) do
	if r.shown and r.option then
		r.scripts.OnClick(r)
		break
	end
end
assert(NS.ui.status.text:find("Open the AH"), NS.ui.status.text)
