# Changelog

All notable changes to Guild Census are recorded here, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Add an entry under **Unreleased** with every
user-visible change, and move it under a version heading when that version is released (the version is
`## Version` in `GuildCensus/GuildCensus.toc`).

## [Unreleased]

### Changed
- MobHunter: a Hunt window (box, Start/Stop, status and the Target button; hidden by default, drag to move) and an options page (Options > AddOns > MobHunter, or `/mobhunt options`) with checkboxes for showing the Hunt window and for the Target button inside it, a button that creates the MobHunter macro, and a button for the minimap debug window. `/mobhunt window` toggles the window. The Target button now lives in the Hunt window instead of floating on its own.
- MobHunter: `/mobhunt button on|off` shows or hides the Target button (saved between sessions). `/mobhunt macro` creates a "MobHunter" character macro for your action bar that follows the hunt (`/target <matched name>`); `/mobhunt target` explains why a slash command itself cannot target.
- MobHunter: a "Play a sound when a hunted mob is found" checkbox in the options and in the Hunt window (on by default); `/mobhunt sound on|off` does the same.
- MobHunter: dots close together on the minimap each get an icon (before, nearby dots merged into one). A dot answers the probe within roughly 10-15 units (the radius is worked out from the data each time), so overlapping dots show up in the tooltip as repeated names; MobHunter counts those repeats and fits one dot per unexplained count (`Probe.Fit`). The area around each coarse hit is re-probed on a 4-unit grid, the coarse grid is back to 6 units, and the icon limit is 24.
- MobHunter: no alert sound for a hunted mob you already have targeted.
- MobHunter: the minimap icon is about half the size (11 px, was 20).
- MobHunter: README and `docs/MobHunter_minimap_icon.png` and `docs/MobHunter_hunt_window.png` and `docs/MobHunter_options.png` show the icon over a hunted mob's dot, the Hunt window, the nameplate marker, the Target button and the options page in the real client.
- MobHunter: the minimap probe now passes `UpdateMouseoverAtPoint` screen coordinates, `((left + x) * scale, (bottom + y) * scale)`, the way the NodeSight addon does (the earlier minimap-local values returned empty tooltips everywhere), probes every 8 units, and skips the scan in combat. `/mobhunt debug` reports the minimap's position and scale and how many points returned content.
- MobHunter: the minimap probe now reads tooltip text from `args` when `leftText` is missing, and `/mobhunt debug` also dumps the shape of the tooltips it gets back.
- MobHunter: `/mobhunt debug`, while you are hunting, also reports how many dots it fitted, the hit radius it chose and where the dots are.
- MobHunter: `/mobhunt debug` opens a window with what the minimap probe sees (which calls exist, how many points returned a tooltip, sample tooltip lines), selected so Ctrl+C copies it, and saves it to `MobHunterDB.lastDebug`.
- MobHunter: hunted mobs found among your minimap tracking dots now get MobHunter's icon drawn over the dot (up to 8), replacing the red ring.
- MobHunter: the Target button only shows while a matching mob is in targeting range, and hides when it leaves.
- MobHunter: the Target button now targets the spotted mob by its full name (e.g. "Target Prairie Stalker" after hunting "stalker") instead of the typed text, so partial matches work, and fires on both mouse-down and mouse-up so it works whichever way the "cast on key press" setting is set.
- Release tags are now `guildcensus-X.Y.Z` so other addons in this repo can version separately. The
  earlier plain `0.5.0` and `0.6.0` tags stay as they are and are the starting point for the first prefixed one.
- The release workflow is named **GuildCensus Release**.

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
- `GuildCensus/ADDON_DESCRIPTION.md` and `MobHunter/ADDON_DESCRIPTION.md`: listing text for CurseForge.
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
