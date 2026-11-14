-- /pb net (or the Net cost box) plans by net cost, so an item a vendor
-- buys back for most of its price fits a budget its AH price doesn't.
-- Whether the plan itself (the rows under its title) buys the item.
local function planned(name)
	for i, r in ipairs(NS.ui.rows) do
		if i > 1 and not r.option then
			break
		end
		if r.shown and r.option and r.option.name == name then
			return true
		end
	end
	return false
end
local function title()
	for _, r in ipairs(NS.ui.rows) do
		if r.shown and not r.option then
			return r.title.text
		end
	end
end
MOCK[892].sell = 2000	-- Gnoll Casting Gloves: 27s on the AH, 7s net
pb("10s") run()
assert(not planned("Gnoll Casting Gloves"), "bought over budget")
assert(not NS.ui.net.checked)
pb("10s net") run()
assert(planned("Gnoll Casting Gloves"), "net plan missed the gloves")
assert(NS.ui.net.checked)
assert(title():find(" net %(.- up front%)"), title())
assert(NS.ui.header.text:find("net budget"), NS.ui.header.text)
local lines = table.concat(PawnBrokerDB.report.lines, "\n")
assert(lines:find("Buy %d+ for .- net %(.- up front%), %+"), lines)
assert(PawnBrokerDB.ui.net == true)
-- A net plan can cost more up front than the gold carried; it says so.
pb("all net") run()
assert(NS.ui.notes.text:find("up front; you carry"), NS.ui.notes.text)
-- Leaving net out of the line unticks the box.
pb("10s") run()
assert(not NS.ui.net.checked and not planned("Gnoll Casting Gloves"))
assert(title():find("%(net .-%)"), title())
