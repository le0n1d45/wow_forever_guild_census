# Changelog

All notable changes to Guild Census are recorded here, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Add an entry under **Unreleased** with every
user-visible change to this addon, and move it under a version heading when that version is released (the
version is `## Version` in `GuildCensus/GuildCensus.toc`).

## [Unreleased]

### Added
- Skill levels are shared between players who run the addon. The game reports no skill level for other players on WoW Forever, so each client now announces its own profession skill levels to the guild through a hidden addon message (prefix `GuildCensus`, about one small message per player every two minutes at most, on login, on a skill change and in answer to a new player's hello) and remembers what it hears, so the Profession Finder shows "Skinning (157)" for everyone running the addon (reports are kept 60 days; notes remain the fallback). A new setting, **Share my profession skill levels with other Guild Census users in my guild** (on by default), turns sending off; the addon still listens. `/gcensus comms` sends now and prints the status, and `/gcensus debug` has a section for it. Only profession names and levels are sent, not roles or notes.
- `/gcensus debug` opens a copyable report of what the client returns for guild professions: the full `C_Club.GetMemberInfo` fields for several members (with a count of the skill ranks seen), your own skills through every skill API, the guild trade skill window API (it tries a roster refresh, expanding and collapsing the profession headers and a recipe query, reading the rows after each step, so the report takes about 12 seconds), a list of the guild and profession APIs the client has, and which of these APIs exist. Made to find out why every profession from the game's data shows level 1. It is also saved to the SavedVariables file.

### Fixed
- The Profession Finder showed every profession as level 1 ("Skinning (1)"). WoW Forever's guild data reports a skill rank of 1 for every member (checked on 369 members, while the real levels were 180 and 40), and the guild trade skill API that would have the levels is switched off on the server. The placeholder ranks are now ignored, so a profession shows no level unless the player wrote one in their note ("LW 260"). Your own character's professions use your real skill levels. If the game ever reports ranks above 1, they are used again.

## [0.7.0] - 2026-11-07

### Added
- Two new Census charts, **Races** and **Race and class** (for example "Undead Warlock"). Race and class has a row of its own and lists every combo in the guild with its count and percentage, in as many legend columns as needed. Members whose race can't be read count as "Unknown". `GetGuildRosterInfo` has no race, so it is read from the game's guild club data (`C_Club`), falling back to the client's player cache (`GetPlayerInfoByGUID`). The Census tab is now three charts wide and the window is bigger (1160 x 690 px). The demo roster has races.

## [0.6.0] - 2026-10-30

### Added
- Professions and skill levels are now also read from the game's own guild member data (`C_Club`) where
  available. Notes remain the fallback, so nothing changes for members the game has no data for, or if the
  API isn't there. The game's skill level wins over a number in the note.
- Demo members include game-reported professions, some with no profession in their note.

## [0.5.0] - 2026-10-30

### Added
- Officer notes are read as well as public notes, when your guild rank can see them. A hidden or empty
  officer note is skipped without an error.

## [0.4.0] - 2026-10-29

### Added
- **Role Finder** and **Profession Finder** tabs, each with a Clear button and an online-only filter.
- Dungeon presets in the Role Finder that fill in the level range, using Forever's ranges from Wowhead's
  chart (`WoW_Forever_Dungeon_Ranges.png`).
- Profession skill levels read from notes (`LW 260`, `BS: 310`), shown in the results, with a skill-range
  filter in the Profession Finder.
- Demo mode now generates 500 members, built so every filter returns results.
- Full spellings in the default keyword lists (`leatherworking`, `healer`, `retribution`, ...), alongside the
  existing abbreviations. Saved settings that were never edited are upgraded automatically.
- Beads issue tracking.

### Changed
- Keywords now match **whole words only**, so `bs` no longer matches inside "herbs".

### Fixed
- `leatherworking` was missing from the default Leatherworking keywords.

## [0.3.0] - 2026-10-29

### Added
- Settings panel: include-alts and only-mains checkboxes, editable keyword lists for roles, professions and
  alt/main detection, and a Reset button.
- Logs tab listing contradictory notes (main and alt, more than two professions, a class that can't fill the
  role). Logged members still count in the census.
- Tabbed window (Census / Logs).
- Demo members have real names.
- Addon icon, README with screenshots, MIT license.
- Separate Forever (Interface 16001) and Retail (Interface 120105) build artifacts from GitHub Actions,
  keeping the newest 5 of each.
- Everything from the first version (2026-10-28): pie charts of roles, professions, classes and levels read
  from guild notes, and the `/gcensus` command.
