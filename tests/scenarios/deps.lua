-- A Pawn or Auctionator that's missing, or a version without something
-- PawnBroker calls, gets a message in the window rather than a Lua error.
local function status(cmd)
	pb(cmd) run()
	return NS.ui.status.text
end
local saved = PawnGetSingleValueFromItem
PawnGetSingleValueFromItem = nil
assert(status(""):find("Pawn has no PawnGetSingleValueFromItem"),
	NS.ui.status.text)
PawnGetSingleValueFromItem = saved
local api = Auctionator.API.v1
local create = api.CreateShoppingList
api.CreateShoppingList = nil
assert(status(""):find("Auctionator has no API.v1.CreateShoppingList"),
	NS.ui.status.text)
api.CreateShoppingList = create
local auctionator = Auctionator
Auctionator = nil
assert(status(""):find("[Nn]eeds Auctionator"), NS.ui.status.text)
fire("AUCTION_HOUSE_SHOW")
assert(status("scan"):find("[Nn]eeds Auctionator"), NS.ui.status.text)
Auctionator = auctionator
local common = PawnCommon
PawnCommon = nil
assert(status(""):find("[Nn]eeds Pawn"), NS.ui.status.text)
PawnCommon = common
assert(status("") == "Plan ready.", NS.ui.status.text)
-- Pawn 2.14.5 and later report an addon that breaks their tooltip reading.
PawnIsIncompatible = function() return true end
assert(status(""):find("Pawn can't score items"), NS.ui.status.text)
fire("AUCTION_HOUSE_SHOW")
assert(status("scan"):find("Pawn can't score items"), NS.ui.status.text)
PawnIsIncompatible = function() return nil end
assert(status("") == "Plan ready.", NS.ui.status.text)
