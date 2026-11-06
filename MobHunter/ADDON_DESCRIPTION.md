# CurseForge listing text

Copy-paste source for the CurseForge project page. The README is for developers and GitHub; this
is for players. When features change, update this file alongside the README, then paste the new
text into CurseForge (Project > Edit > Description).

How to use it:

1. **Summary field:** paste the single line under "Summary" below (CurseForge limits it to about 250
   characters).
2. **Description field:** paste everything under "Description" below, between the two `---` lines.
3. **Screenshots:** CurseForge can't show images stored in this repo, so upload them to the project
   gallery. `docs/MobHunter_hunt_window.png` (Hunt window, nameplate marker and Target button),
   `docs/MobHunter_minimap_icon.png` (the minimap icon) and `docs/MobHunter_options.png` (the options page)
   are ready to upload. The icon is `assets/mobhunter-icon.png` (or `.jpg`) in the repo root.

## Summary

Type /mobhunt and a mob's name: get a sound and a marker when it comes into range or shows up on your minimap tracking, plus a one-press button to target it.

## Description

---

# MobHunter

**Never miss the mob you're hunting.**

Type **/mobhunt** followed by a mob's name, and MobHunter watches for it while you play. When it appears you
get a **sound**, a message on screen, and a **red marker above the mob**. If the mob is one of your **minimap
tracking dots**, MobHunter draws **its own icon over that dot** on the minimap (the game can't hide its dot, so the icon sits on top of it, a pixel larger).

## How to use it

1. Type **/mobhunt Defias Pillager** (part of a name is enough: **/mobhunt pillager**). Prefer not to type
   commands? Open the **Hunt window** (tick **Show the Hunt window** under **Options > AddOns > MobHunter**), type the
   name in its box and press **Start**.
2. Play as normal. When a match appears, MobHunter alerts you once.
3. Press the **Target** button that appears in the Hunt window, or a key you've bound to it, to target the mob.
4. Type **/mobhunt stop** (or press **Stop** in the Hunt window) when you're done.

## What it watches

- **Mobs in range:** the enemy nameplates your game is already showing. Turn enemy nameplates on
  (the **V** key, or Options > Interface > Names), or MobHunter can't see anything in range. It will remind you.
- **Minimap tracking:** if you're tracking something (such as Find Herbs or Track Beasts), MobHunter also checks
  the tracked dots for the name you're hunting.

## Commands

- `/mobhunt <name>`: start hunting
- `/mobhunt stop`: stop hunting
- `/mobhunt`: show what you're hunting
- `/mobhunt sound on` / `off`: turn the alert sound on or off (remembered between sessions)
- `/mobhunt button on` / `off`: show or hide the Target button (remembered between sessions)
- `/mobhunt window`: show or hide the Hunt window
- `/mobhunt options`: open the options page (also under **Options > AddOns > MobHunter**) with checkboxes for the Hunt window, its Target button and the alert sound, a button that creates the macro, and a debug button
- `/mobhunt macro`: creates a "MobHunter" macro for your action bar that targets the mob you're hunting
- `/mobhunt target`: explains why a slash command can't target, and points to the macro
- `/mobhunt debug`: opens a window with technical details about the minimap check, already selected so you can copy it (useful when reporting a problem)

## Setting up the Target button

- The Hunt window also has a **Play a sound when found** checkbox, the same setting as in the options.
- The **Target** button appears only while a matching mob is in targeting range (a minimap-only sighting doesn't show it), and hides again when the mob leaves. It lives in the **Hunt window**, so if that window is hidden you won't see it (the key binding and macro still work). Drag the window with the **left mouse button** to move it.
- To use a key instead, open **Options > Keybindings > AddOns > MobHunter** and bind **Target the hunted mob**.
- The button reads "Target <full mob name>" and targets that name (e.g. hunting "stalker" gives "Target Prairie Stalker"). If several matching mobs are near, it picks the nearest with that name.
- **Don't want the button?** Untick **Show the Target button in the Hunt window** in the options, or type **/mobhunt button off**. The key binding and macro below keep working.
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
- Dead mobs and other players are ignored, and a hunted mob you already have targeted doesn't make a sound.
- Available for both **WoW Forever** and **Retail**; download the file for your game version. It has been
  built for Forever first, and the minimap check is not confirmed on Retail.

## Feedback and source

Bug reports, ideas and the source code are on GitHub: https://github.com/le0n1d45/wow_forever_guild_census

Released under the MIT license.

---
