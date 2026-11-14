-- Upgrades a vendor buys back for nearly what they cost get their own list:
-- the best one per slot, within budget, unless the plan already buys it.
-- /pb near sets the limit, /pb near off hides the list.
local function section(title)
	local out, inside = {}, false
	for _, r in ipairs(NS.ui.rows) do
		if r.shown and not r.option then
			inside = r.title.text:find(title, 1, true) ~= nil
		elseif r.shown and inside then
			out[#out + 1] = r.option
		end
	end
	return out
end
-- Every item sells to a vendor for its AH price, so all of them are near.
-- With no budget the plan already buys the best of each, so nothing's left.
for _, m in pairs(MOCK) do
	m.sell = m.m
end
pb("all") run()
assert(#section("Near vendor price") == 0)
-- A 20s budget can't cover every slot, so the rest show up as near.
pb("20s") run()
local chosen = {}
for _, o in ipairs(section("Buy ")) do
	chosen[o.group] = o
end
local near = section("Near vendor price")
assert(#near > 0, "no near-vendor rows")
local groups = {}
for i, o in ipairs(near) do
	assert(o.net <= NS.NEAR, o.name)
	assert(chosen[o.group] ~= o, "already planned: " .. o.name)
	assert(not groups[o.group], "two for " .. o.group)
	groups[o.group] = true
	assert(i == 1 or near[i - 1].gain >= o.gain, "not sorted by gain")
end
local lines = table.concat(PawnBrokerDB.report.lines, "\n")
assert(lines:find("Near vendor price (net 5s or less):", 1, true), lines)
-- A budget keeps out anything it can't pay for up front.
pb("1s") run()
for _, o in ipairs(section("Near vendor price")) do
	assert(o.price <= 100, o.name)
end
-- The limit sticks between plans, and off hides the list.
pb("near 10s 20s") run()
assert(PawnBrokerDB.ui.near == 1000, tostring(PawnBrokerDB.ui.near))
pb("20s") run()
assert(#section("Near vendor price") > 0)
pb("near off 20s") run()
assert(PawnBrokerDB.ui.near == false)
assert(#section("Near vendor price") == 0)
pb("near lots") run()
assert(NS.ui.status.text:find("^Near vendor price"), NS.ui.status.text)
