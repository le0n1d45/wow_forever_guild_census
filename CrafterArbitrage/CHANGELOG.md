# Changelog

All notable changes to CrafterArbitrage are recorded here, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Add an entry under **Unreleased** with every
user-visible change to this addon, and move it under a version heading when that version is released (the
version is `## Version` in `CrafterArbitrage/CrafterArbitrage.toc`).

## Unreleased

### Added
- First version. Scan the Auction House and see which crafts pay: buy the reagents, craft, and sell to a vendor (or, with a checkbox, on the Auction House). Reagents are priced listing by listing, so the list says how many crafts to make before the next one stops paying. Filter by recipes you know, recipes a trainer of your faction can teach you at your skill, or all recipes with where to get them. Open it with `/carb`.
- A minimap button: left-click opens the window, right-click scans the Auction House, drag moves it around the minimap. `/carb minimap on|off` shows or hides it.

### Fixed
- `/carb` did nothing on clients that do not know one of the Auction House events the addon listens for; the addon now skips an event the client rejects.
- The window's layout: the table's header now lines up with its columns, the checkboxes no longer overlap, and the window is wide enough for the "Learn from" column.
