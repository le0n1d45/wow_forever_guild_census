# CurseForge listing text

Copy-paste source for the CurseForge project page. The README is for developers and GitHub; this
is for players. When features change, update this file alongside the README, then paste the new
text into CurseForge (Project > Edit > Description).

How to use it:

1. **Summary field:** paste the single line under "Summary" below (CurseForge limits it to about 250
   characters).
2. **Description field:** paste everything under "Description" below, between the two `---` lines.
3. **Screenshots:** there are none yet. CurseForge can't show images stored in this repo, so take
   in-game screenshots (the alert, the nameplate marker, the minimap icon) and upload them to the project
   gallery. The icon is `assets/mobhunter-icon.png` (or `.jpg`) in the repo root.

## Summary

Type /mobhunt and a mob's name: get a sound and a marker when it comes into range or shows up on your minimap tracking, plus a one-press button to target it.

## Description

---

# MobHunter

**Never miss the mob you're hunting.**

Type **/mobhunt** followed by a mob's name, and MobHunter watches for it while you play. When it appears you
get a **sound**, a message on screen, and a **red marker above the mob**. If the mob is one of your **minimap
tracking dots**, MobHunter draws **its own icon over that dot** on the minimap (the game can't hide its dot, so the icon covers it).

## How to use it

1. Type **/mobhunt Defias Pillager** (part of a name is enough: **/mobhunt pillager**). Prefer not to type
   commands? Open **Options > AddOns > MobHunter**, type the name in the box and press **Start**.
2. Play as normal. When a match appears, MobHunter alerts you once.
3. Press the **Target** button that appears on screen, or a key you've bound to it, to target the mob.
4. Type **/mobhunt stop** (or press **Stop** in the options) when you're done.

## What it watches

- **Mobs in range:** the enemy nameplates your game is already showing. Turn enemy nameplates on
  (the **V** key, or Options > Interface > Names), or MobHunter can't see anything in range. It will remind you.
- **Minimap tracking:** if you're tracking something (such as Find Herbs or Track Beasts), MobHunter also checks
  the tracked dots for the name you're hunting.

## Commands

- `/mobhunt <name>`: start hunting
- `/mobhunt stop`: stop hunting
- `/mobhunt`: show what you're hunting
- `/mobhunt button on` / `off`: show or hide the Target button (remembered between sessions)
- `/mobhunt options`: open the options page (also under **Options > AddOns > MobHunter**). It has a box and Start/Stop buttons to hunt, the Target button checkbox, and a button that creates the macro, so you never have to type a command
- `/mobhunt macro`: creates a "MobHunter" macro for your action bar that targets the mob you're hunting
- `/mobhunt target`: explains why a slash command can't target, and points to the macro
- `/mobhunt debug`: opens a window with technical details about the minimap check, already selected so you can copy it (useful when reporting a problem)

## Setting up the Target button

- The **Target** button appears only while a matching mob is in targeting range (a minimap-only sighting doesn't show it), and hides again when the mob leaves. Drag it with the **right mouse button** to move it.
- To use a key instead, open **Options > Keybindings > AddOns > MobHunter** and bind **Target the hunted mob**.
- The button reads "Target <full mob name>" and targets that name (e.g. hunting "stalker" gives "Target Prairie Stalker"). If several matching mobs are near, it picks the nearest with that name.
- **Don't want the button?** Untick it in the options, or type **/mobhunt button off**. The key binding and macro below keep working.
- **Want it on an action bar?** Press **Create the MobHunter macro** in the options (or type **/mobhunt macro**), open **/macro** and drag the **MobHunter** macro to your bar. It keeps itself pointed at the mob you're hunting. (A **/mobhunt target** command isn't possible: the game only lets a click, key press or macro button target, never a slash command.)
- The button can't appear or disappear during combat; it updates when combat ends. Your keybind works either way.

## Why it doesn't target for you

World of Warcraft doesn't allow addons to choose your target by themselves. Targeting has to come from
you pressing something. MobHunter does everything up to that point and then leaves the final press to you,
which keeps it within Blizzard's addon rules.

## Good to know

- This is an early version. The minimap check reads the game's minimap tooltips, which the game doesn't
  officially offer to addons, so it may behave differently on some clients or stop working after a game update.
- Mobs are matched by name only, and each one alerts once while it stays in range.
- Dead mobs and other players are ignored.
- Available for both **WoW Forever** and **Retail**; download the file for your game version. It has been
  built for Forever first, and the minimap check is not confirmed on Retail.

## Feedback and source

Bug reports, ideas and the source code are on GitHub: https://github.com/le0n1d45/wow_forever_guild_census

Released under the MIT license.

---
