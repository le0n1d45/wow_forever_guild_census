# CurseForge listing text

Copy-paste source for the CurseForge project page. The README is for developers and GitHub; this
is for players. When features change, update this file alongside the README, then paste the new
text into CurseForge (Project > Edit > Description).

How to use it:

1. **Summary field:** paste the single line under "Summary" below (CurseForge limits it to about 250
   characters).
2. **Description field:** paste everything under "Description" below, between the two `---` lines.
3. **Screenshots:** CurseForge can't show images stored in this repo, so upload them to the project
   gallery instead of linking them. The best ones are in `docs/`: `GuildCensus_results_role_finder.png`,
   `GuildCensus_results_profession_finder.png`, `census.png` and `settings.png`.

## Summary

Pie charts of your guild's roles, professions, classes and levels, read from guild notes, plus finders for "who can tank this dungeon?" and "who has 260 leatherworking?"

## Description

---

# Guild Census

**See what your guild is made of, and find the right person for the job.**

Guild Census reads your guild members' **public notes** and turns them into pie charts of **roles**
(tank, healer, DPS), **professions**, **classes** and **levels**. Two finders then help you pick people:
a **Role Finder** for filling a group and a **Profession Finder** for finding a crafter.

Type **/gcensus** to open it.

## What you get

- **Census charts:** four pie charts with counts and percentages, in class colours.
- **Role Finder:** search by role (Tank, Healer, DPS) and level range, or pick a **dungeon** and it fills in the
  level range for you. "Who can tank Wailing Caverns?" is two clicks.
- **Profession Finder:** search by profession, and by **skill level** if your guild writes it in their notes
  (`LW 260`, `BS: 310`, `Mining (300)`). Results show each person's skill next to the profession.
- **Online only:** limit either finder to people who are online right now.
- **Clear:** one click puts every finder control back to its default.
- **Logs tab:** lists notes that contradict themselves (for example a member marked as both main and alt, or
  with three professions) along with the note itself, so you can tidy notes or tune the keywords. Those
  members are still counted in the charts.
- **Alts and mains:** leave alts out of the numbers, or count only members whose note says they're a main.
- **Demo mode:** `/gcensus demo` shows a fake 500-member guild so you can try everything without a guild.

## Commands

- `/gcensus` or `/guildcensus`: open or close the window
- `/gcensus roles`: open the Role Finder
- `/gcensus professions`: open the Profession Finder
- `/gcensus logs`: open the Logs tab
- `/gcensus config`: open the settings
- `/gcensus demo`: switch demo data on or off

## Writing notes that work

Guild Census only reads what is in the **public note**, and only matches **whole words** (so "herbs" is
not mistaken for "bs"). Notes like these work out of the box:

- `Tank` / `Healer` / `DPS`, or a spec such as `Prot`, `Resto`, `Holy`, `Ret`, `Feral`, `Shadow`
- `LW 260`, `Mining (300)`, `BS: 310`, `Alch-225` for professions with a skill level
- `Main` or `Alt of Bob` to mark mains and alts
- Several at once: `Tank, Engineering 150, Mining 120`

Warlocks, hunters, mages and rogues are always counted as DPS, even with an empty note, and a member who can
do all three roles is not treated as a conflict.

## Settings

Open them with `/gcensus config` or under **Options > AddOns**. Every keyword list is editable, so you can
match how *your* guild writes notes:

- **Role detection:** keywords for Tank, Healer and DPS
- **Profession detection:** keywords for all nine professions
- **Alt/Main detection:** keywords that mark alts and mains
- Checkboxes for **Include alts** and **Include ONLY mains declared within guild notes**
- **Reset to defaults** if you want to start over

Keywords are comma-separated and match whole words, so list the abbreviations *and* the full words you
want (for example `heal, healer, healing`). The defaults already cover the common ones.

## Good to know

- Characters need their profession or role written in their **public note** to be picked up. Officer
  notes are not read.
- Dungeon level ranges come from Wowhead's WoW Forever guide, which is still beta data and may change.
- The numbers come from the guild roster the game has loaded, and refresh when the game updates it.
- Available for both **WoW Forever** and **Retail**; download the file for your game version.

## Feedback and source

Bug reports, ideas and the source code are on GitHub: https://github.com/le0n1d45/wow_forever_guild_census

Released under the MIT license.

---
