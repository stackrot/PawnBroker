-- An AH that stops answering: the scan gives up after a few items instead
-- of waiting out every one, and isn't recorded.
fire("AUCTION_HOUSE_SHOW") run()
NS.ui.budget:SetText("") NS.ui.ahead:SetText("")
AH_SILENT = true
local start = clock()
pb("scan") run()
local text = NS.ui.status.text
assert(text:find("stopped answering"), text)
assert(clock() - start < 25, "took " .. (clock() - start) .. "s")
assert(not (PawnBrokerDB.scans and PawnBrokerDB.scans["Tester-Test Realm"]))

-- Item keys that never load count the same way.
AH_SILENT, KEYS_SILENT = nil, true
start = clock()
pb("scan") run()
text = NS.ui.status.text
assert(text:find("stopped answering"), text)
assert(clock() - start < 25, "took " .. (clock() - start) .. "s")

-- One item that never answers is skipped, and the scan isn't recorded
-- as done, so the window keeps asking for another.
KEYS_SILENT, SILENT_ONE = nil, true
pb("scan") run()
text = NS.ui.status.text
assert(text:find("^Suffix scan done.*1 didn't answer"), text)
assert(not (PawnBrokerDB.scans and PawnBrokerDB.scans["Tester-Test Realm"]))

-- Once it answers the rescan picks up just that item and is recorded.
SILENT_ONE = nil
pb("scan") run()
text = NS.ui.status.text
assert(text:find("^Suffix scan done: 1 items"), text)
assert(PawnBrokerDB.scans["Tester-Test Realm"])
