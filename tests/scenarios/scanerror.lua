-- An AH call that throws mid-scan (say, a game patch changed it) ends the
-- scan instead of leaving it marked as running, and reports the error.
local errors = {}
geterrorhandler = function()
	return function(e) errors[#errors + 1] = tostring(e) end
end
local info = C_AuctionHouse.GetItemSearchResultInfo
C_AuctionHouse.GetItemSearchResultInfo = function() error("changed API") end
fire("AUCTION_HOUSE_SHOW") run()
pb("scan") run()
assert(not NS.scanning(), "scan still marked as running")
assert(#errors > 0 and errors[1]:find("changed API"), "error not reported")
assert(NS.ui.status.text:find("scan stopped at %d+/%d+ %(Lua error%)"),
	NS.ui.status.text)
-- With the API back, a new scan runs to the end.
C_AuctionHouse.GetItemSearchResultInfo = info
pb("scan") run()
assert(not NS.scanning())
assert(NS.ui.status.text:find("[Ss]uffix scan done"), NS.ui.status.text)
