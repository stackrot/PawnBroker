-- Item data that never loads: the scan says so instead of reporting
-- prices up to date, and isn't recorded, so the window keeps asking.
fire("AUCTION_HOUSE_SHOW") run()
NS.ui.budget:SetText("") NS.ui.ahead:SetText("")
for id in pairs(MOCK) do UNLOADED[id] = true end
pb("scan") run()
local text = NS.ui.status.text
assert(text:find("didn't load") and not text:find("up to date"), text)
assert(not (PawnBrokerDB.scans and PawnBrokerDB.scans["Tester-Test Realm"]))

-- Some items load: those are scanned, the rest are still reported.
UNLOADED = {}
for id in pairs(MOCK) do
	if id % 3 == 0 then UNLOADED[id] = true end
end
pb("scan") run()
text = NS.ui.status.text
assert(text:find("^Suffix scan done") and text:find("didn't load"), text)
assert(not PawnBrokerDB.scans["Tester-Test Realm"])

-- Once everything loads the scan finishes and is recorded.
UNLOADED = {}
pb("scan") run()
text = NS.ui.status.text
assert(text:find("^Suffix scan done") and not text:find("didn't load"), text)
assert(PawnBrokerDB.scans["Tester-Test Realm"])
