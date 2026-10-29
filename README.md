# Guild Census

<img src="assets/icon.png" alt="Guild Census icon" width="64" align="right">

Guild Census builds pie charts of your guild roster so you can see its makeup at a glance.
It targets WoW Forever and also builds for Retail. Type `/gcensus` to open it.

![The census window](docs/census.png)

## What it shows

- **Roles:** tanks, healers and DPS, read from your members' guild notes.
- **Professions:** read from the same notes.
- **Classes:** one slice per class, in class colours.
- **Levels:** how many members fall in each 10-level range.

## Features

- **Editable keyword lists:** the keywords used to spot roles, professions, and mains/alts are
  editable in the settings panel.
- **Alts and mains:** leave out alts, or count only members whose note says they're a main.
- **Pure-DPS classes:** warlocks, hunters, mages and rogues are always counted as DPS.
- **Logs tab:** lists contradictory notes, with each player's note, so you can tidy the notes or
  tune your keywords. Logged notes are still counted in the charts.
- **Demo mode:** `/gcensus demo` shows a fake 500-member guild, handy if you're not in a guild. It's
  built so every Finder filter has results (each dungeon has tanks, healers, DPS and online players;
  every profession is spread across roles and levels), with declared mains and alts, a few
  deliberately contradictory notes for the Logs tab, and enough members to hit the Finder's row cap.

## Install

Every push to `main` builds two zips, available as artifacts on the repository's **Actions** tab:

| Artifact | Client | Interface |
| --- | --- | --- |
| `GuildCensus-Forever-<n>` | WoW Forever | `16001` |
| `GuildCensus-Retail-<n>` | Retail | `120105` |

Download the one for your client, unzip it, and put the `GuildCensus` folder in your AddOns folder
(`.../_retail_/Interface/AddOns/`, or `_classic_beta_` for the Forever beta), then restart the client or
`/reload`. If the game still lists the addon as out of date, tick **Load out of date AddOns** in the
AddOns list. Check your client's number with `/dump select(4, GetBuildInfo())`.

To install from a clone instead, copy the `GuildCensus/` folder (not the repo root) into AddOns. The
repository's TOC uses the Forever interface number.

## Usage

| Command | Does |
| --- | --- |
| `/gcensus` (or `/guildcensus`) | Open or close the census window |
| `/gcensus roles` (or `finder`) | Open the window on the Role Finder tab |
| `/gcensus professions` | Open the window on the Profession Finder tab |
| `/gcensus logs` | Open the window on the Logs tab |
| `/gcensus config` | Open the settings panel |
| `/gcensus demo` | Toggle a 500-member fake roster |

The window has four tabs: **Census** (the four pie charts), **Role Finder**, **Profession Finder** and
**Logs**. The Logs tab
shows how many conflicts were found, for example `Logs (27)`.

## Finder

Two tabs search the guild for people who fit a need. Both update as you change a control, both have an
**Online only** checkbox (limits the search to members who are online right now), and both have a
**Clear** button that puts every control back to its default.

**Role Finder** (`/gcensus roles`) is for filling a group, for example a tank for a level 15-25 dungeon:

- **Role:** a dropdown with Any, Tank, Healer or DPS.
- **Dungeon:** pick a dungeon to fill in its level range, or choose **Custom** and type a range.
  Editing a level by hand switches the dungeon back to Custom. Ranges come from Wowhead's Forever
  dungeon guide (beta data, so they may change).
- **Level:** a minimum and/or maximum level, inclusive; leave either empty for no limit.

**Profession Finder** (`/gcensus professions`) is for finding a crafter. It only asks for a profession,
because levels and roles don't matter when you want someone's profession. **Any profession** lists
everyone with at least one profession.

Each row shows the player's name (in class colour), level, class, detected roles and professions,
highest level first. Very large guilds show the first 300 matches.

Both use exactly the same detection and settings as the charts, so warlocks, hunters, mages and rogues
always count as DPS, and your alts/mains choices apply. Members with conflicts in the Logs tab are still
listed.

## Settings

`/gcensus config` opens the settings panel, which is also under Options > AddOns.

![The settings panel](docs/settings.png)

- **Include alts** and **Include ONLY mains declared within guild notes** checkboxes. When both
  apply, a member must pass the alts checkbox and also declare a main.
- **Alt/Main, Role and Profession detection:** comma-separated keyword lists. Changes apply
  immediately, and **Reset to defaults** restores the originals.

### How detection works

Detection reads each member's **public** guild note. A keyword matches when it appears anywhere in
the note, ignoring case, so `heal` matches "healer". That also means short keywords can match inside
unrelated words (for example `ret` in "return"), so choose them with care. An emptied box matches
nothing.

Default keywords:

| Detection | Defaults |
| --- | --- |
| Main / Alt | `main` / `alt` |
| Tank | `tank, bear, prot` |
| Healer | `heal, resto, holy, disc` |
| DPS | `dps, fury, arms, ret, feral, cat, kitty, balance, moonkin, crit-chicken, enh, ele, enhance, elemental, shadow, shockadin` |
| Leatherworking | `lw, leatherworker` |
| Skinning | `skinning, skinner` |
| Mining | `mining, miner` |
| Herbalism | `herb, herbalism, herbs` |
| Enchanting | `ench, enchanting` |
| Blacksmith | `bs, blacksmith, armorsmith, weaponsmith` |
| Engineering | `engi, engineering` |
| Tailor | `tailor, tailoring` |
| Alchemy | `alch, alchemy` |

## Census logs

The Logs tab lists notes whose detection results contradict each other. Each entry shows the player,
what's wrong, the keyword that matched, and the note itself. A note is logged when it:

- is detected as both a main and an alt;
- matches more than two professions;
- matches a role the player's class can't fill (for example a mage matching "healer").

Matching all three roles is not a conflict, since some classes can do all three.

The log is informational only. Logged members are still counted in every chart, and conflicts are
reported for every guild member regardless of the alts/mains filters.

## Development

- **Tests:** `lua tests/run.lua` (Lua 5.1) runs note-parsing and census tests plus headless UI tests
  against a strict WoW widget stub (`tests/wow_stub.lua`). The stub checks logic and widget-method
  names; it does not check rendering or Forever API compatibility.
- **Builds:** `.github/workflows/build.yml` publishes the Forever and Retail artifacts and keeps the
  newest 5 of each.
- **Icon:** `tools/make_icon.py` regenerates `GuildCensus/icon.tga`. Add `--size N --jpeg PATH` (needs
  Pillow) for a larger JPEG; the repo's copies are in `assets/`.
- **Client notes:** WoW runs Lua 5.1; use `C_Spell` / `C_Item` rather than removed globals, don't
  register `COMBAT_LOG_EVENT_UNFILTERED`, and guard values with `issecretvalue`.

## License

[MIT](LICENSE). The build artifacts include the license file.
