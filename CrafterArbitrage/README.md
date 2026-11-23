# CrafterArbitrage

Scans the auction house and lists the crafts that make a profit: buy the reagents on the auction house,
craft, then sell the result to a vendor (or, with a checkbox, on the auction house).

**Not yet tried on the real Forever client.** The data and the maths are tested headlessly
(`lua tests/run.lua`); the game calls (auction house scan, profession skill, known recipes) follow the
documented APIs and Crafter's Journal's findings but still need an in-game check.

| Command | What it does |
| --- | --- |
| `/carb` | Open or close the window. |
| `/carb scan` | Scan the auction house (it must be open). |
| `/carb vendor` / `/carb ah` | Sell to a vendor (default) or on the auction house. |
| `/carb filter known\|learnable\|all` | Which recipes to consider. |
| `/carb neutral on\|off` | Neutral auction house: 15% cut instead of 5%. |
| `/carb status` | Show the settings and the age of the last scan. |

## How it works

- **Scan:** the Scan button asks for a full auction house scan (`C_AuctionHouse.ReplicateItems`, or
  `QueryAuctionItems` with getAll on a classic auction house) and reads it once the listing stops growing. The
  server allows one full scan per account every 15 minutes; a scan another addon (Auctionator) asked for is read
  too. Only items a recipe makes or uses are kept, as a price "ladder" per item (the saved scan is in
  `CrafterArbitrageDB.scan`).
- **Profit:** buying n crafts' worth of reagents climbs the ladder, so each next craft costs more. The addon finds how
  many crafts still pay (each next craft must earn at least 5 copper and 10% of what it costs). Reagents a vendor
  sells cost the vendor price with no limit. A reagent that is itself a recipe's product (a bolt of cloth) is crafted
  instead of bought when that is cheaper and the recipe is allowed by the filter.
- **Vendor sale:** the crafted item's vendor price, from the client tables.
- **Auction house sale:** the third-cheapest listed unit's price less 1 copper, less the 5% cut (15% neutral);
  crafts that bind when picked up are left out; the number of crafts is capped at 30% of the units already listed.
- **Recipe filters:** *Known* (the character knows it), *Learnable* (known, plus recipes a trainer of the player's
  faction teaches and the character has the skill for), *All* (every recipe, with where to get it).

## Data

Generated from the game's client tables and community databases, committed under `CrafterArbitrage/Data/`:

| Source | Gives | Script |
| --- | --- | --- |
| wago.tools (build in `tools/wago/BUILD`) | recipes, reagents, outputs, skill colours, vendor prices, which item teaches a recipe | `tools/filter_wago.py` |
| CMaNGOS classic-db (GPL-2.0 data) | trainers: price, skill needed, ranks | `tools/extract_cmangos.py` |
| QuestieDB addon data | trainer faction and location; vendors, drops and quest rewards for recipe items; reagents a vendor sells | `tools/extract_questie.py` |

`tools/gen_recipes.py` turns the trimmed CSVs in `tools/wago`, `tools/cmangos` and `tools/questie` into
`Data/*.lua`. wago.tools refuses Python's default request, so download the tables by hand
(`https://wago.tools/db2/<Table>/csv?build=<build>`: SkillLineAbility, SpellEffect, SpellReagents, SpellName,
ItemSparse, Item, ItemEffect, ItemXItemEffect) into a folder as `<Table>.csv`, then run:

```
python3 tools/filter_wago.py <folder> <build>
python3 tools/extract_cmangos.py <ClassicDB_*.sql.gz>     # github.com/cmangos/classic-db, Full_DB
python3 tools/extract_questie.py <QuestieDB-*-Forever.zip>
python3 tools/gen_recipes.py
```

Known gaps: the trainer data is Classic's (Forever may differ); QuestieDB's runtime corrections are not applied;
drop sources are capped at five mobs per recipe and have no drop rates; about 500 items are missing from the client
table (new to Forever), so the game is asked for their vendor price.

Crafter's Journal (GPLv3) was studied for the approach only; no code was copied.
