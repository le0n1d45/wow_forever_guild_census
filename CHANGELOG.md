# Changelog

All notable changes to Guild Census are recorded here, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Add an entry under **Unreleased** with every
user-visible change, and move it under a version heading when that version is released (the version is
`## Version` in `GuildCensus/GuildCensus.toc`).

## [Unreleased]

### Added
- Professions and skill levels are now also read from the game's own guild member data (`C_Club`) where
  available. Notes remain the fallback, so nothing changes for members the game has no data for, or if the
  API isn't there. The game's skill level wins over a number in the note.
- Demo members include game-reported professions, some with no profession in their note.
- A manually triggered **Release** workflow: bumps the version from the latest tag, tags the code and
  publishes a GitHub release with the Forever and Retail zips named for the new version.

## [0.5.0] - 2026-10-30

### Added
- Officer notes are read as well as public notes, when your guild rank can see them. A hidden or empty
  officer note is skipped without an error.
- `docs/LEARNING.md`: where the WoW APIs and Forever details came from, and what is still unverified.
- `ADDON_DESCRIPTION.md`: listing text for CurseForge.
- This changelog.

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
