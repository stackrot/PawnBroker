-- Closing the AH, cancelling, resuming, stale prices and pruning.
NO_RANDOM_LINE = true
fire("AUCTION_HOUSE_SHOW") run()
pb("scan") run(clock() + 10)
fire("AUCTION_HOUSE_CLOSED") run()
assert(NS.ui.status.text:find("AH closed"), NS.ui.status.text)
fire("AUCTION_HOUSE_SHOW") pb("scan") run(clock() + 5)
pb("stop") run()
assert(NS.ui.status.text:find("%(cancelled%)"), NS.ui.status.text)
pb("scan") run()
assert(NS.ui.status.text:find("done"), NS.ui.status.text)
advanceClock(25 * 3600)
assert(NS.suffixNotice():find("25h old"))
LEVEL = 21
advanceClock(-24 * 3600)
assert(NS.suffixNotice():find("3 levels past"))
LEVEL = nil
advanceClock(8 * 86400)
fire("PLAYER_LOGIN")
assert(next(PawnBrokerDB.suffix["Test Realm"]) == nil)
