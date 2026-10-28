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

## Tests

`lua tests/run.lua` (Lua 5.1) runs note parsing/aggregation tests plus headless UI tests against a strict
WoW widget stub (`tests/wow_stub.lua`). The stub checks logic and widget-method names, not rendering or
Forever API compatibility.
