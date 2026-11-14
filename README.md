# PawnBroker

PawnBroker works out which gear to buy from the auction house. It scores
everything in your last Auctionator scan with your Pawn scale, compares it
with what you're wearing, and picks the set of upgrades that adds the most
Pawn score within your budget.

Built for WoW: Forever.

## Requirements

- [Pawn](https://www.curseforge.com/wow/addons/pawn), with one scale visible
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator), with a
  full scan from the last few days

## Using it

Type `/pb` to open the window and plan. The plan lists:

- Buy: the upgrades to get, at most one per slot, that fit the budget
- Better, but over budget: stronger items you can't afford yet
- Near vendor price: upgrades that a vendor buys back for nearly what
  they cost, so they're close to free once you outgrow them

Each row shows the AH price, the net cost (the price minus what a vendor
pays for it), the Pawn gain over what you wear now, the required level and
how many are listed. Hover a row for the item tooltip, click it to search
the AH, or shift-click to link it in chat. The plan also replaces the
Auctionator shopping list "PawnBroker".

| Command | What it does |
|---|---|
| `/pb` | Plan with the gold you carry |
| `/pb 1g50s` | Plan with a budget of 1g 50s |
| `/pb all` | No budget: the best item for each slot |
| `/pb +2` | Include items up to 2 levels above you |
| `/pb net` | Plan by net cost instead of AH price |
| `/pb near 10s` | Count anything with a net cost of 10s or less as near vendor price (default 5s) |
| `/pb near off` | Hide the near vendor price list |
| `/pb scan` | Price random-suffix items (needs the AH open) |
| `/pb stop` | Stop a suffix scan |

Options combine, for example `/pb 1g net +1`. The window has the same
controls: a budget box, a levels-above box, a Net cost box, Plan, and Scan
suffixes.

### Net cost

With Net cost ticked, the budget caps the net total rather than what you
pay up front. That lets a plan include an item that's over budget at AH
price but sells back for most of it. The plan shows both totals and warns
when the up-front cost is more than the gold you carry.

### Random-suffix items

Auctionator keeps one price per item, the cheapest version, so it can't
tell "Willow Vest of the Owl" from "Willow Vest of the Monkey". With the
AH open, Scan suffixes runs one search per random-suffix item from 10
levels below you to 5 above and caches the cheapest listing of each
version for that realm. The plan then prices each version on its own. The
window asks for a rescan when the cache is over a day old or you've gained
3 levels since.

## How it plans

- Only items your class can wear, at or below your level (or the levels
  above you asked for), with no red text in the tooltip, such as a
  profession requirement.
- Rings and trinkets are compared with the weaker of your two.
- A two-hander is compared with your main hand and off hand together, and
  off hands are skipped while you wear a two-hander.
- Gains under 0.5% are ignored, as Pawn does.
- The plan is a knapsack: one item per slot at most, the most total Pawn
  gain for the budget.

## Limits

- One ring, one trinket and one hand-held item per plan. Plan again after
  equipping to fill the second slot.
- Unique-equipped items and weapon skills aren't checked beyond what turns
  tooltip text red.
- Prices are only as fresh as your last Auctionator scan.

## Development

The tests run the addon against mocked game, Pawn and Auctionator APIs with
real scan data. They need [LuaJIT](https://luajit.org) and run the same on
Windows, macOS and Linux:

```
luajit tests/run.lua       # all scenarios
luajit tests/run.lua -v    # with chat output
```

Releases are built by the
[BigWigs packager](https://github.com/BigWigsMods/packager) from
`.pkgmeta`, which leaves the tests and this README out of the package.

## Licence

MIT
