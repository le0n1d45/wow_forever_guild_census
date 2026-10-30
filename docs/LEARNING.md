# Learning notes: where the WoW APIs came from

This addon was built as a learning exercise. This file records where the knowledge came from, how
much to trust each source, and which part of the code uses which API, so you can go and read the
originals.

## How much to trust what's below

- **Fetched and read** means the page was opened while building this addon.
- **Seen in search results** means a page turned up in a search and only its snippet was seen. Don't
  treat it as a source for anything in the code.
- **Wiki page names** (the `API_*` and `Widget_*` links in the tables) follow Warcraft Wiki's usual naming,
  and most were *not* fetched. They are where to look things up, not proof that each signature
  was checked. Behaviour in the real WoW Forever client is **unverified**, because it wasn't live when
  this was written (see bead `c9a`). The headless tests only prove the code agrees with
  `tests/wow_stub.lua`, which I wrote from the same understanding.

## Sources

### Fetched and read

| Source | What it gave us |
| --- | --- |
| [Warcraft Wiki: TOC format](https://warcraft.wiki.gg/wiki/TOC_format) | `.toc` fields: `## Interface`, `Title`, `Author`, `Version`, `SavedVariables`, `IconTexture`, `X-` custom fields, file load order. Also the `_Forever`/`_Camelot` style client suffixes. |
| [WoW Forever Guides: addon developers](https://wowforeverguides.com/addons/developers) | What is different about writing for WoW Forever: it runs a Mainline-style API, the Interface number is `16001`, and the client build was 1.60.1. |
| [Wowhead: Forever dungeons overview](https://www.wowhead.com/forever/guide/dungeons-overview-locations-details) | The dungeon level ranges. Wowhead's page didn't load as text, so the final data came from the chart you saved: `WoW_Forever_Dungeon_Ranges.png` (repo root). |
| [Icy Veins: Forever dungeons overview](https://www.icy-veins.com/wow-forever/dungeons-overview) and [Kami Labs](https://kami-labs.fr/en/donjons-raids-wow-forever/) | Cross-checks on dungeon lists. Kami Labs includes dungeons Wowhead's chart doesn't (Defias Prison, Demon Fall Canyon, Karazhan Crypts, Manor Mistmantle), which is why they're not in `Dungeons.LIST`. |
| [Warcraft Wiki: Getting started with writing addons](https://warcraft.wiki.gg/wiki/Getting_started_with_writing_addons) | The overall shape of an addon: folder name matches the `.toc`, files listed in the `.toc` load in order, events drive everything. |

### Seen in search results only (good places to continue)

- [Warcraft Wiki: UI beginner's guide](https://warcraft.wiki.gg/wiki/UI_beginner%27s_guide) and [AddOn programming introduction](https://warcraft.wiki.gg/wiki/AddOn_programming_introduction)
- [WoW Forever Guides: API cheatsheet](https://wowforeverguides.com/addons/api-cheatsheet)
- [WoWInterface forums](https://wowinterface.com/forums/) (long-running addon author community)
- [addonstudio.org: AddOn programming tutorial](https://www.addonstudio.org/wiki/WoW:AddOn_programming_tutorial/Introduction)
- Forever addon directories: [wow4ever.quest](https://wow4ever.quest/en/addons), [wowforevertierlist.com](https://wowforevertierlist.com/addons), [theforeverera.com](https://theforeverera.com/en/addon/), [hardcorehelper.com](https://www.hardcorehelper.com/forever/guides/addons), and [CurseForge](https://www.curseforge.com/wow/addons) (ForeverQuest is a real addon to read for style)

### Not from a web page: my own knowledge

Most of the Lua and widget calls (`CreateFrame`, `Line:SetStartPoint`, `SetScript`, and so on)
and the dropdown and Settings-panel details came from background knowledge of the Mainline UI
API, not from a page I read during this project. That is the part most likely to be subtly wrong, so
verify it against the wiki before relying on it.

## Which API is used where

| Need | API | Where | Look it up |
| --- | --- | --- | --- |
| Load code and saved data | `local addonName, ns = ...` (every file gets the addon name and a shared table), `SavedVariables: GuildCensusDB` in the `.toc` | every file, `GuildCensus.toc` | TOC format page |
| React to the game | `CreateFrame("Frame")`, `frame:RegisterEvent`, `frame:SetScript("OnEvent")`; events `ADDON_LOADED`, `GUILD_ROSTER_UPDATE` | `GuildCensus.lua` | [Events](https://warcraft.wiki.gg/wiki/Events) |
| Read the guild | `GetNumGuildMembers`, `GetGuildRosterInfo(i)` (name, rank, level, class, zone, public note, officer note, online, status, class file), `C_GuildInfo.GuildRoster()` | `Roster.lua` | [`API_GetGuildRosterInfo`](https://warcraft.wiki.gg/wiki/API_GetGuildRosterInfo) |
| Class colours | `RAID_CLASS_COLORS[classFile]` | `PieChart.lua`, `Finder.lua` | search the wiki for `RAID_CLASS_COLORS` |
| Slash commands | `SLASH_GUILDCENSUS1 = "/gcensus"`, `SlashCmdList["GUILDCENSUS"]` | `GuildCensus.lua` | [Creating a slash command](https://warcraft.wiki.gg/wiki/Creating_a_slash_command) |
| Windows and widgets | `CreateFrame` with `BasicFrameTemplateWithInset`, `FontString`, `Button`, `CheckButton`, `EditBox`, `ScrollFrame` | `UI.lua`, `Options.lua`, `Finder.lua`, `Logs.lua` | [Widget API](https://warcraft.wiki.gg/wiki/Widget_API) |
| Pie charts | 360 thin `Line` objects with `SetStartPoint`/`SetEndPoint`/`SetThickness` (no texture files needed) | `PieChart.lua` | Widget API, `Line` |
| Dropdowns | Try `WowStyle1DropdownTemplate` (`SetupMenu`, `CreateRadio`), fall back to `UIDropDownMenuTemplate`, then to a cycle button | `Finder.lua` (`createSelector`) | search "WowStyle1DropdownTemplate", "UIDropDownMenu" |
| Settings panel | `Settings.RegisterCanvasLayoutCategory` + `Settings.RegisterAddOnCategory`, with `InterfaceOptions_AddCategory` as an older fallback | `Options.lua` | [Settings API](https://warcraft.wiki.gg/wiki/Settings_API) |
| Icon in the AddOn list | `## IconTexture:` in the `.toc`, a 64x64 `.tga` | `GuildCensus.toc`, `icon.tga` | TOC format page |

## Things that behave differently from what you might expect

- **Both notes are read, the officer note only if you can see it.** The roster call always returns an
  officer note, but the client leaves it empty for members who aren't allowed to see it, and I haven't
  confirmed which ranks that includes. `Roster.CombineNotes` joins the two with ` | ` and skips anything
  that isn't non-empty text, so a hidden officer note is harmless.
- **Roster data is lazy.** The game only has what the server last sent, so the addon asks for a refresh
  and redraws on `GUILD_ROSTER_UPDATE`.
- **Names can include the realm** (`Name-Realm`), so `Roster.lua` strips it.
- **Lua 5.1, not newer Lua.** WoW embeds a patched 5.1: no `//`, no `goto`, no integer type. The tests run
  under real Lua 5.1 for this reason.
- **Each client has its own Interface number.** Forever is `16001`; Retail is `120105` (read from the wiki,
  not confirmed in a client). The GitHub Action rewrites it per flavour.

## Learning by doing

- **Run it without a game:** `lua tests/run.lua` (Lua 5.1). Read `tests/wow_stub.lua` to see which widget
  calls the addon actually makes, since the stub errors on any call it doesn't know.
- **See it with data:** `/gcensus demo` in-game fills a fake 500-member guild.
- **Read next, in this order:** `Parser.lua` (pure Lua, easiest), `Census.lua`, `Roster.lua` (the first real
  API call), `PieChart.lua`, then `Finder.lua` (the widest use of widgets).
- **Check the unverified bits yourself:** the open beads (`bd ready`) list what hasn't been confirmed in a
  real client.
