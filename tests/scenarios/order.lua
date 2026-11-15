-- The scan prices what a plan can use first: items up to your level, then
-- off hands beside a two-hander, then the ones above your level.
fire("AUCTION_HOUSE_SHOW") run()
NS.ui.budget:SetText("") NS.ui.ahead:SetText("")
pb("scan") run()
assert(NS.ui.status.text:find("^Suffix scan done"), NS.ui.status.text)
local level, two = UnitLevel(), NS.twoHanded()
local function rank(id)
	local m = MOCK[id]
	if m.lvl > level then return 3 end
	if two and NS.OFF_HAND[m.loc] then return 2 end
	return 1
end
local last, seen = 0, {}
for _, id in ipairs(SENT) do
	if not seen[id] then
		seen[id] = true
		assert(rank(id) >= last, "item " .. id .. " searched out of order")
		last = rank(id)
	end
end
assert(last == 3, "no items above your level were scanned")
