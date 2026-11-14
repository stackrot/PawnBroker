-- Every option carries its vendor price and net cost, shown in the window
-- and the report. An item a vendor buys for at least its AH price is free.
local function shown()
	local out = {}
	for _, r in ipairs(NS.ui.rows) do
		if r.shown and r.option then
			out[#out + 1] = r
		end
	end
	return out
end
MOCK[12996].sell = MOCK[12996].m + 100	-- Band of Purification
pb("all") run()
local free
for _, r in ipairs(shown()) do
	local o = r.option
	assert(o.net == o.price - o.vendor, o.name)
	if o.name == "Band of Purification" then
		free = true
		assert(r.cells.net.text == "free", r.cells.net.text)
	else
		assert(r.cells.net.text == "<" .. o.net .. "c>", r.cells.net.text)
	end
end
assert(free, "Band of Purification not planned")
local lines = table.concat(PawnBrokerDB.report.lines, "\n")
assert(lines:find("Band of Purification [%dgsc ]+, net free,"), lines)
