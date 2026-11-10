# Changelog

All notable changes to MobHunter are recorded here, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Add an entry under **Unreleased** with every
user-visible change to this addon, and move it under a version heading when that version is released (the
version is `## Version` in `MobHunter/MobHunter.toc`).

## [0.7.0] - 2026-11-07

### Changed
- Quest targets. The Hunt window lists mobs suggested by your quest log (kill objectives, and the mobs that drop an item a quest still needs) under "Quest targets"; click one to hunt it. Item drops come from the QuestieDB addon when it is installed (ranked by drop rate, rare extras hidden) and from mobs you have looted the item from. Options: "Suggest hunt targets from my quests" (default on) and "Hunt the suggested quest targets automatically" (default off). `/mobhunt quests` lists them. Findings from the real client are in `docs/MobHunter_quest_suggestions_research.md`.

### Fixed
- The minimap icons over tracking dots stopped working after today's game update. Blizzard changed what the minimap tooltip probe returns (NodeSight reports the same: its minimap symbols were "patched out in today's update, on every version"). Nameplate alerts, the marker and the Target button are unaffected. `/mobhunt debug` now also tries other coordinate styles and lists the active tracking, so a future workaround can be checked.

## [0.6.0] - 2026-11-06

### Changed
- Hunt several mobs at once. `/mobhunt raptor, lion` (or a comma-separated list in any Hunt window box); the Hunt window has an "Add hunt" button that adds another box (up to 8, each with an x to remove it). Any match alerts, gets a marker and a minimap icon, and arms the Target button for the mob last spotted.

## [0.5.0] - 2026-11-06

### Changed
- Less garbage per minimap scan (the probe grid is built once, empty probes far from any hit are not kept as tables) and a full radius search only every 30th scan, to cut the remaining small CPU spikes.
- The minimap scan no longer runs all at once (CPU spikes while hunting). It is a job advanced 30 probes per frame (and at most about 1 ms of probing per frame), the coarse grid is 8 units, and after scans that find nothing it waits longer before the next one (up to 4 s). It also stops if you enter combat.

## [0.4.0] - 2026-11-06

### Changed
- A "Play a sound when a hunted mob is found" checkbox in the options and in the Hunt window (on by default); `/mobhunt sound on|off` does the same.
- Dots close together on the minimap each get an icon (before, nearby dots merged into one). A dot answers the probe within roughly 10-15 units (the radius is worked out from the data each time), so overlapping dots show up in the tooltip as repeated names; MobHunter counts those repeats and fits one dot per unexplained count (`Probe.Fit`). The area around each coarse hit is re-probed on a 4-unit grid, the coarse grid is back to 6 units, and the icon limit is 24.
- No alert sound for a hunted mob you already have targeted.
- `/mobhunt debug` starts with the probe revision and what you are hunting, so a report shows which files the game loaded.
- `/mobhunt debug`, while you are hunting, also reports how many dots it fitted, the hit radius it chose and where the dots are.

## [0.3.0] - 2026-11-06

### Changed
- The minimap icon is about half the size (11 px, was 20).

## [0.2.0] - 2026-11-05

### Changed
- A Hunt window (box, Start/Stop, status and the Target button; hidden by default, drag to move) and an options page (Options > AddOns > MobHunter, or `/mobhunt options`) with checkboxes for showing the Hunt window and for the Target button inside it, a button that creates the MobHunter macro, and a button for the minimap debug window. `/mobhunt window` toggles the window. The Target button now lives in the Hunt window instead of floating on its own.
- `/mobhunt button on|off` shows or hides the Target button (saved between sessions). `/mobhunt macro` creates a "MobHunter" character macro for your action bar that follows the hunt (`/target <matched name>`); `/mobhunt target` explains why a slash command itself cannot target.
- README and `docs/MobHunter_minimap_icon.png` and `docs/MobHunter_hunt_window.png` and `docs/MobHunter_options.png` show the icon over a hunted mob's dot, the Hunt window, the nameplate marker, the Target button and the options page in the real client.
- The minimap probe now passes `UpdateMouseoverAtPoint` screen coordinates, `((left + x) * scale, (bottom + y) * scale)`, the way the NodeSight addon does (the earlier minimap-local values returned empty tooltips everywhere), probes every 8 units, and skips the scan in combat. `/mobhunt debug` reports the minimap's position and scale and how many points returned content.
- The minimap probe now reads tooltip text from `args` when `leftText` is missing, and `/mobhunt debug` also dumps the shape of the tooltips it gets back.
- `/mobhunt debug` opens a window with what the minimap probe sees (which calls exist, how many points returned a tooltip, sample tooltip lines), selected so Ctrl+C copies it, and saves it to `MobHunterDB.lastDebug`.
- Hunted mobs found among your minimap tracking dots now get MobHunter's icon drawn over the dot (up to 8), replacing the red ring.
- The Target button only shows while a matching mob is in targeting range, and hides when it leaves.
- The Target button now targets the spotted mob by its full name (e.g. "Target Prairie Stalker" after hunting "stalker") instead of the typed text, so partial matches work, and fires on both mouse-down and mouse-up so it works whichever way the "cast on key press" setting is set.
