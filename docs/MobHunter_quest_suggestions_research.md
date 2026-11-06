# MobHunter: quest-driven hunt suggestions (research, bead ajn)

Goal: read the player's quest log and suggest hunt targets: mobs named in kill objectives, and the
mobs that drop items named in item objectives (Guns of Northwatch: Theramore Medals from the
Marines and Priests; Barrens Raptor Horns: only Sunscale Scytheclaw).

Update: the QuestieDB 1.0.11 Forever zip was later supplied and decoded offline (section 7), which
settles the API shape and the two example quests. Nothing was run in the real client.

Sources: a read-only clone of github.com/Questie/Questie (Forever TOC `Questie_Forever.toc`, v12.6.2),
its `docs/`, `Database/QuestieDB.lua`, `Database/DropTables/dropDB.lua` and the Forever API
annotations under `.types/`. Nothing here was run in the real client.

## 1. What the quest log gives us

- `C_QuestLog.GetNumQuestLogEntries`, `C_QuestLog.GetInfo(index)` (header, isHidden, questID),
  `C_QuestLog.GetQuestObjectives(questID)` all exist in the Forever annotations. Questie's
  `QuestLogCache` relies on them on Forever.
- An objective row is `{ text, type, finished, numFulfilled, numRequired }`; `type` is a string
  (`monster`, `item`, `object`, `event`, ...).
- **Rows carry names only, no IDs.** A kill row reads "Sunscale Scytheclaw slain: 3/10"; an item
  row reads "Raptor Horn: 3/6". A kill row gives us the mob name directly; an item row does not say
  who drops the item.
- Rows can be empty or untyped right after login or a loading screen (Questie rejects such
  snapshots and retries). We must wait for `QUEST_LOG_UPDATE` and ignore rows with no `type`.
- Parse text with the client's own format strings (`QUEST_MONSTERS_KILLED`, `QUEST_ITEMS_NEEDED`)
  turned into patterns so it works in other locales, not hard-coded English.
- Skip `finished` rows; re-scan on `QUEST_LOG_UPDATE` / `UNIT_QUEST_LOG_CHANGED`.

## 2. How Questie maps items to mobs

- Questie keeps no entity data itself any more. Quests, NPCs, items and objects live in the
  separate **QuestieDB** addon (global `LibQuestieDB`), declared `RequiredDeps: QuestieDB` with
  `X-QuestieDB-Contract: 4`. Users of Questie for Forever already install both. QuestieDB's own
  repo was not found by search, so its API is known only from Questie's call sites.
- Questie's call sites show the shape: `LibQuestieDB.Quest/Npc/Item/Object.Get(id)`,
  `.GetAllIds()`, `Object.IdsByName(name)`. A quest row has `objectives[1]` = kill NPC ids,
  `objectives[3]` = item ids; an item row has `npcDrops` (list of NPC ids). That is exactly the
  chain we need: **questID -> item ids -> npcDrops -> NPC names.**
- Drop data comes from Wowhead (every NPC listed for the item) merged with cmangos "quest-only
  drop" data and manual corrections (`DropDB`, `QuestieItemDropCorrections`). Wowhead alone
  over-reports (it lists NPCs that drop the item outside the quest); the cmangos data is what
  narrows Raptor Horns to the Scytheclaws. Questie's `QuestieDB.GetItemDroprate(itemId, npcId)`
  exposes the rate.
- `Questie.API` (Public/) is the stable surface for other addons, but it only has icon,
  ready-callback and quest-update hooks. No objective-to-NPC call. So a bridge reads `LibQuestieDB`
  directly, which is not a stable public API.
- Licence: Questie's LICENSE.md says "all rights reserved when in doubt" for historic code, with a
  move to GPLv3 for new contributions. **Do not copy its data or code.** A runtime read of an
  installed QuestieDB is fine; bundling its tables is not.

## 3. Options for item -> mob

| Option | Pros | Cons |
| --- | --- | --- |
| A. Bridge to QuestieDB when installed | Accurate (quest-only drop data), covers every quest, no data to maintain, no licence issue | Optional dependency; `LibQuestieDB` calls are unstable and unverified; absent for users without Questie |
| B. Learn drops in game | No dependency, always correct for this client, tiny | Only knows a mob after the first drop; useless for the first kill |
| C. Bundle our own table | Works offline for everyone | Must source licensed data; large; goes stale; high maintenance |

## 4. Recommendation

Build in phases, each useful on its own:

1. **Kill objectives only, no dependency.** Quest log reader plus parsing; suggests the named mobs.
   Covers "kill N X" quests (and Guns of Northwatch only if its mobs are kill objectives, which
   needs checking: Theramore Medals are an item objective).
2. **Optional QuestieDB bridge** for item objectives (option A), guarded with `pcall` and
   `LibQuestieDB` presence checks, silently off when missing. Resolve by questID, not by item name.
3. **Learned drops** (option B) as the no-Questie fallback and as a cross-check: on loot, if the item
   matches an active item objective, remember the source mob's name in `MobHunterDB`.

Not recommended: bundling a drop table (option C).

## 5. UI

A "Quest targets" section in the Hunt window listing suggested mobs with the quest name; one click
adds a mob to the hunt list (works with multi-hunt). Options: a checkbox to show suggestions and a
checkbox to add them automatically. Drop a suggestion when its objective finishes or the quest is
abandoned; do not auto-remove mobs the user typed.

## 6. Still unverified (needs the real client)

- Exact `LibQuestieDB.Quest.Get / Item.Get / Npc.Get` signatures and return shapes (`/dump` in game).
- That `C_QuestLog.GetQuestObjectives` rows on Forever have `type` set for both examples.
- Whether Guns of Northwatch and the Raptor Horns quest resolve to the mobs expected, with and
  without Questie's quest-only filtering.
- Locale format-string patterns.

## 7. Verified against QuestieDB 1.0.11 (Forever) data

The addon ships its data as CBOR in TOC metadata (`X-Quest-<id>-10`, `X-Item-<id>-2`, ...), plus
Lua drop tables under `support/Forever/DropTables/`. Decoding them offline gives:

API (from `Types/*.t.lua`, a documented public surface, contract 4; `LibQuestieDB.RequireContract(4)`
checks support):

- `LibQuestieDB.Quest.objectives(questID)` -> `{ [1]=kill {npcId,text,..}[], [2]=objects, [3]=items {itemId,text,..}[], [5]=killCredit, ... }`
- `LibQuestieDB.Item.npcDrops(itemId)` -> npc ids; `LibQuestieDB.Item.name(itemId)`
- `LibQuestieDB.Npc.name(npcId)` (also `minLevel`, `maxLevel`, `rank`, `zoneID`)
- Reads are cached and composed with corrections; the dependency is declared `RequireContract`
  rather than a hard `## Dependencies` (the provider says independent release cycles make skew likely),
  so our bridge should check `LibQuestieDB` and `RequireContract` at runtime and `pcall` the reads.
- Licence is the same "all rights reserved when in doubt" notice as Questie: read it at runtime,
  do not copy it.

Example quests (decoded):

| Quest (id) | Objective | Mobs from the database |
| --- | --- | --- |
| The Guns of Northwatch (891) | kill Captain Fairmount, Cannoneer Whessan, Cannoneer Smythe; item: Theramore Medal | Medal drops (Wowhead rate): Theramore Marine 46%, Theramore Preserver 32%, Captain Fairmount 29%, Cannoneer Smythe 29%, Cannoneer Whessan 16%; plus Theramore Guard (npc 261485), which is in the Forever data but has no rate |
| Raptor Horns (865) | item: Intact Raptor Horn | Sunscale Scytheclaw 26%, Takk the Leaper 6.9%, Ishamuhale 1.4% |

Takeaways:

- Guns of Northwatch is **both**: the three named bosses come from the kill rows (phase 1, no
  database); the Marines and Preservers (your "Marines and Priests") come only from the item
  objective, so they need the QuestieDB bridge or learned drops.
- Raptor Horns returns **three** mobs, not only the Scytheclaws: Takk and Ishamuhale are rare
  raptors that also drop it. The cmangos quest-only correction table lists all three at 80%, so
  the data cannot narrow it further. Rank them by the Wowhead drop rate
  (`LibQuestieDB.Support.Get("QuestieClassicItemDrops")` holds the rate tables, or Questie's
  `GetItemDroprate`) and show the best first, or suggest only mobs above a rate cutoff
  (for example 10%) with the rest behind a "show rare drops" choice. Learned drops (phase 3) confirm
  which mobs the player actually saw drop it.
- Quest objective rows in the quest log carry no IDs, so match item objectives by name:
  `Item.name(itemId)` against the parsed row text. Quest.objectives order is not guaranteed to
  equal the log row order (Questie has an "Objective Order" for that), so do not match by index.
- The entity tables store sparse objectives as lists with holes, but the public `objectives()` API
  returns the documented positional tuple; always go through the API, never decode the TOC.
- Nothing is lost if QuestieDB is missing: phases 1 and 3 still work.

Still to verify in game: the quest-log row `type` and text for these two quests, and that
`LibQuestieDB.Support.Get(...)` exposes the rate tables to a third-party addon.
