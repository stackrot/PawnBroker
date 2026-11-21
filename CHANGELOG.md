# Changelog

## 0.1.1

- If Pawn reports an addon it can't work with, `/pb` tells you to check `/pawn` instead of planning with wrong scores. Pawn added this check in 2.14.5.
- Suffix prices are now saved per realm and faction, because each faction has its own AH. Run Scan suffixes again on each character. Prices saved by 0.1.0 aren't used any more and are cleared after 7 days.

## 0.1.0

First public version.

- `/pb` plans the upgrades with the most Pawn gain that fit your budget, from your latest Auctionator scan.
- Each upgrade shows its net cost: the AH price minus what a vendor pays for it.
- Upgrades that sell to a vendor for nearly what they cost get their own list. `/pb near 10s` changes the limit from the default 5s, and `/pb near off` hides the list.
- `/pb net`, or the Net cost box, plans by net cost instead of AH price.
- `/pb scan` prices each version of random-suffix items with the AH open.
