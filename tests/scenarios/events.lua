-- The scan acts on the AH's events instead of waiting on timers, and still
-- finishes on the timers alone when the events never come.
fire("AUCTION_HOUSE_SHOW") run()
NS.ui.budget:SetText("") NS.ui.ahead:SetText("")
NO_AH_EVENTS = true
local start = clock()
pb("scan") run()
local slow = clock() - start
assert(NS.ui.status.text:find("^Suffix scan done"), NS.ui.status.text)

PawnBrokerDB.suffix = {}
resetAH()
NO_AH_EVENTS = nil
start = clock()
pb("scan") run()
local fast = clock() - start
assert(NS.ui.status.text:find("^Suffix scan done"), NS.ui.status.text)
print(string.format("timers %.1fs, events %.1fs", slow, fast))
assert(fast < slow * 0.8, string.format("%.1fs with events, %.1fs without", fast, slow))
