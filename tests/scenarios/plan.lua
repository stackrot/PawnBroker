-- Plans with the gold carried, no budget, and a level lookahead.
local function names(rows)
	local out = {}
	for _, r in ipairs(rows) do
		if r.shown and r.option then
			out[#out + 1] = r.option.name
		end
	end
	return table.concat(out, ",")
end
pb("") run()
local plan = names(NS.ui.rows)
assert(plan:find("Gnoll Casting Gloves") and plan:find("Colorful Kilt"),
	plan)
assert(NS.ui.status.text == "Plan ready.", NS.ui.status.text)
assert(#PawnBrokerDB.report.lines > 5)
pb("all +2") run()
assert(NS.ui.header.text:find("items up to 20"), NS.ui.header.text)
assert(names(NS.ui.rows):find("Nightbane Staff"))
assert(NS.ui.budget.text == "all" and NS.ui.ahead.text == "2")
pb("lots") run()
assert(NS.ui.status.text:find("^Budget"), NS.ui.status.text)
pb("10s") run()
local spent = tonumber(NS.ui.rows[1].title.text:match("<(%d+)c>"))
assert(spent and spent <= 1000, NS.ui.rows[1].title.text)
