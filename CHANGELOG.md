# Changelog

All notable changes to Guild Census are recorded here, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Add an entry under **Unreleased** with every
user-visible change, and move it under a version heading when that version is released (the version is
`## Version` in `GuildCensus/GuildCensus.toc`).

## [Unreleased]

### Fixed
- Guild Census: the Profession Finder showed every profession as level 1 ("Skinning (1)"). WoW Forever's guild data reports a skill rank of 1 for every member (checked on 369 members, while the real levels were 180 and 40), and the guild trade skill API that would have the levels is switched off on the server. The placeholder ranks are now ignored, so a profession shows no level unless the player wrote one in their note ("LW 260"). Your own character's professions use your real skill levels. If the game ever reports ranks above 1, they are used again.
- MobHunter: the minimap icons over tracking dots stopped working after today's game update. Blizzard changed what the minimap tooltip probe returns (NodeSight reports the same: its minimap symbols were "patched out in today's update, on every version"). Nameplate alerts, the marker and the Target button are unaffected. `/mobhunt debug` now also tries other coordinate styles and lists the active tracking, so a future workaround can be checked.

### Added
- Guild Census: skill levels are shared between players who run the addon. The game reports no skill level for other players on WoW Forever, so each client now announces its own profession skill levels to the guild through a hidden addon message (prefix `GuildCensus`, about one small message per player every two minutes at most, on login, on a skill change and in answer to a new player's hello) and remembers what it hears, so the Profession Finder shows "Skinning (157)" for everyone running the addon (reports are kept 60 days; notes remain the fallback). A new setting, **Share my profession skill levels with other Guild Census users in my guild** (on by default), turns sending off; the addon still listens. `/gcensus comms` sends now and prints the status, and `/gcensus debug` has a section for it. Only profession names and levels are sent, not roles or notes.
- Guild Census: `/gcensus debug` opens a copyable report of what the client returns for guild professions: the full `C_Club.GetMemberInfo` fields for several members (with a count of the skill ranks seen), your own skills through every skill API, the guild trade skill window API (it tries a roster refresh, expanding and collapsing the profession headers and a recipe query, reading the rows after each step, so the report takes about 12 seconds), a list of the guild and profession APIs the client has, and which of these APIs exist. Made to find out why every profession from the game's data shows level 1. It is also saved to the SavedVariables file.
- Guild Census: two new Census charts, **Races** and **Race and class** (for example "Undead Warlock"). Race and class has a row of its own and lists every combo in the guild with its count and percentage, in as many legend columns as needed. Members whose race can't be read count as "Unknown". `GetGuildRosterInfo` has no race, so it is read from the game's guild club data (`C_Club`), falling back to the client's player cache (`GetPlayerInfoByGUID`). The Census tab is now three charts wide and the window is bigger (1160 x 690 px). The demo roster has races.

### Changed
- MobHunter: quest targets. The Hunt window lists mobs suggested by your quest log (kill objectives, and the mobs that drop an item a quest still needs) under "Quest targets"; click one to hunt it. Item drops come from the QuestieDB addon when it is installed (ranked by drop rate, rare extras hidden) and from mobs you have looted the item from. Options: "Suggest hunt targets from my quests" (default on) and "Hunt the suggested quest targets automatically" (default off). `/mobhunt quests` lists them. Findings from the real client are in `docs/MobHunter_quest_suggestions_research.md`.
- MobHunter: a Hunt window (box, Start/Stop, status and the Target button; hidden by default, drag to move) and an options page (Options > AddOns > MobHunter, or `/mobhunt options`) with checkboxes for showing the Hunt window and for the Target button inside it, a button that creates the MobHunter macro, and a button for the minimap debug window. `/mobhunt window` toggles the window. The Target button now lives in the Hunt window instead of floating on its own.
- MobHunter: `/mobhunt button on|off` shows or hides the Target button (saved between sessions). `/mobhunt macro` creates a "MobHunter" character macro for your action bar that follows the hunt (`/target <matched name>`); `/mobhunt target` explains why a slash command itself cannot target.
- MobHunter: less garbage per minimap scan (the probe grid is built once, empty probes far from any hit are not kept as tables) and a full radius search only every 30th scan, to cut the remaining small CPU spikes.
- MobHunter: hunt several mobs at once. `/mobhunt raptor, lion` (or a comma-separated list in any Hunt window box); the Hunt window has an "Add hunt" button that adds another box (up to 8, each with an x to remove it). Any match alerts, gets a marker and a minimap icon, and arms the Target button for the mob last spotted.
- MobHunter: the minimap scan no longer runs all at once (CPU spikes while hunting). It is a job advanced 30 probes per frame (and at most about 1 ms of probing per frame), the coarse grid is 8 units, and after scans that find nothing it waits longer before the next one (up to 4 s). It also stops if you enter combat.
- MobHunter: a "Play a sound when a hunted mob is found" checkbox in the options and in the Hunt window (on by default); `/mobhunt sound on|off` does the same.
- MobHunter: dots close together on the minimap each get an icon (before, nearby dots merged into one). A dot answers the probe within roughly 10-15 units (the radius is worked out from the data each time), so overlapping dots show up in the tooltip as repeated names; MobHunter counts those repeats and fits one dot per unexplained count (`Probe.Fit`). The area around each coarse hit is re-probed on a 4-unit grid, the coarse grid is back to 6 units, and the icon limit is 24.
- MobHunter: no alert sound for a hunted mob you already have targeted.
- MobHunter: the minimap icon is about half the size (11 px, was 20).
- MobHunter: README and `docs/MobHunter_minimap_icon.png` and `docs/MobHunter_hunt_window.png` and `docs/MobHunter_options.png` show the icon over a hunted mob's dot, the Hunt window, the nameplate marker, the Target button and the options page in the real client.
- MobHunter: the minimap probe now passes `UpdateMouseoverAtPoint` screen coordinates, `((left + x) * scale, (bottom + y) * scale)`, the way the NodeSight addon does (the earlier minimap-local values returned empty tooltips everywhere), probes every 8 units, and skips the scan in combat. `/mobhunt debug` reports the minimap's position and scale and how many points returned content.
- MobHunter: the minimap probe now reads tooltip text from `args` when `leftText` is missing, and `/mobhunt debug` also dumps the shape of the tooltips it gets back.
- MobHunter: `/mobhunt debug` starts with the probe revision and what you are hunting, so a report shows which files the game loaded.
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
