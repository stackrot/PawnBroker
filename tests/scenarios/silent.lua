-- An AH that stops answering: the scan gives up after a few items instead
-- of waiting out every one, and isn't recorded.
fire("AUCTION_HOUSE_SHOW") run()
NS.ui.budget:SetText("") NS.ui.ahead:SetText("")
AH_SILENT = true
local start = clock()
pb("scan") run()
local text = NS.ui.status.text
assert(text:find("stopped answering"), text)
assert(clock() - start < 60, "took " .. (clock() - start) .. "s")
assert(not (PawnBrokerDB.scans and PawnBrokerDB.scans["Tester-Test Realm"]))

-- Item keys that never load count the same way.
AH_SILENT, KEYS_SILENT = nil, true
start = clock()
pb("scan") run()
text = NS.ui.status.text
assert(text:find("stopped answering"), text)
assert(clock() - start < 60, "took " .. (clock() - start) .. "s")

-- Once it answers again the scan finishes.
KEYS_SILENT = nil
pb("scan") run()
assert(NS.ui.status.text:find("^Suffix scan done"), NS.ui.status.text)
