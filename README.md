# Guild Census (WoW Forever addon)

Blank scaffold targeting WoW Forever (Interface `16001`).

## Install

Copy or symlink `GuildCensus/` into the client's AddOns folder, e.g.
`World of Warcraft/_classic_beta_/Interface/AddOns/GuildCensus/`, then `/reload` or restart.

## Notes

- Verify the client's interface number with `/dump select(4, GetBuildInfo())`.
- Lua 5.1 only; use `C_Spell` / `C_Item` APIs rather than removed globals.
- Do not register `COMBAT_LOG_EVENT_UNFILTERED`; guard values with `issecretvalue`.
- Forever's TOC suffix is `_Forever` (alias `_Camelot`); only needed if you split TOCs.

## Usage

`/gcensus` (or `/guildcensus`) toggles a window with four pie charts built from the guild roster:
roles and professions (parsed from public notes), classes, and levels (10-level buckets).

`/gcensus demo` toggles an 80-member fake roster, useful for checking the UI in any client (tick
"Load out of date AddOns" if the Interface number doesn't match).

## Census logs

The **Census Logs** button on the results window lists notes whose detection conflicts, each with the
player's note and the keyword that matched, to help tune the keyword lists. Conflicts: a note detected as
both main and alt, more than two professions, and a class that can't fill a detected role (e.g. a mage
matching "healer"). Holding all three roles is not a conflict. Conflicts are computed for every guild
member, regardless of the alts/mains filters.

## Settings

`/gcensus config` opens the addon's settings panel (also under Options > AddOns):

- **Include alts** and **Include ONLY mains declared within guild notes** checkboxes.
- Editable comma-separated keyword lists for alt/main, role and profession detection. Matching is a
  case-insensitive substring search on the public note (so `heal` matches "healer").
- Warlocks, hunters, mages and rogues are always counted as DPS.

## Tests

`lua tests/run.lua` (Lua 5.1) runs note parsing/aggregation tests plus headless UI tests against a strict
WoW widget stub (`tests/wow_stub.lua`). The stub checks logic and widget-method names, not rendering or
Forever API compatibility.
