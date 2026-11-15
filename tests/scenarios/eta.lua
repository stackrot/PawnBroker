-- Scan progress says about how long is left once a few items are done.
fire("AUCTION_HOUSE_SHOW") run()
NS.ui.budget:SetText("") NS.ui.ahead:SetText("")
pb("scan") run(clock() + 1)
local text = NS.ui.status.text
assert(text:find("^Suffix scan: scanned %d+/%d+$"), text)
run(clock() + 10)
text = NS.ui.status.text
assert(text:find("^Suffix scan: scanned %d+/%d+, about %d+ %a+ left$"), text)
run()
assert(NS.ui.status.text:find("^Suffix scan done"), NS.ui.status.text)
