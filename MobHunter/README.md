# MobHunter

Type `/mobhunt <mob name>` and MobHunter tells you when that mob comes into range.

| Command | What it does |
| --- | --- |
| `/mobhunt <name>` | Start hunting. Part of a name is enough: `/mobhunt pillager` finds "Defias Pillager". |
| `/mobhunt stop` | Stop hunting. |
| `/mobhunt` | Show what you're hunting. |
| `/mobhunt button on\|off` | Show or hide the Target button (saved in `MobHunterDB`; default on). |
| `/mobhunt macro` | Creates a "MobHunter" character macro (`/target <matched name>`, kept up to date) to drag onto an action bar. `/click MobHunterTargetButton` was tried first and did nothing in the client. |
| `/mobhunt debug` | Prints what the minimap probe can and can't do on this client. |
| `/mobhunt target` | Explains that a slash command can't target (protected) and points to `/mobhunt macro`. |

When a match shows up you get a **sound**, a **chat and on-screen message**, a red **marker above the mob's
nameplate**, and, if the mob is one of your minimap tracking dots, **MobHunter's icon drawn over its dot on the minimap**. A **Target
button** appears on screen only while a matching mob is in targeting range (drag it with the right mouse button) and can be bound to a key under
**Options > Keybindings > AddOns > MobHunter**. Pressing it runs `/target <the matched mob's full name>` (e.g. `/target Prairie Stalker` after `/mobhunt stalker`).

## What it looks at

1. **Mobs in range.** Enemy nameplates the game is already showing (turn on enemy nameplates, or MobHunter
   will say so). Each mob alerts once while it stays in range.
2. **Minimap tracking dots**, when you are tracking something (Find Herbs, Track Beasts, ...). The game has
   no call that lists minimap blips, so MobHunter does what the NodeSight addon does: it moves the
   minimap's soft cursor over a grid of points and reads the tooltip the game would show there. A dot
   whose tooltip names the hunted mob gets the icon. The dot itself can't be hidden by an addon, so the icon (a child frame of the minimap,
   larger than a dot) covers it.

## Why it doesn't target the mob by itself

`TargetUnit` is a protected function: addon code isn't allowed to call it, and Blizzard's design (the
secure-execution model) lets addons start a protected action only when the player presses something. So
MobHunter alerts you and gives you a one-press way to target. The button's macro text can only be changed
out of combat; if you start a hunt in combat it is armed when combat ends. The keybind works in combat once
it's armed. `/target <name>` picks the nearest match, which isn't necessarily the mob that triggered the
alert.

## Terms of service

This is a read of Blizzard's published rules, not legal advice, and I (the author's assistant) could not
read the current Terms of Use or EULA text. What I did read:

- Blizzard's **UI Add-On Development Policy** (forum thread 24534). Its eight rules cover: free of charge,
  no hidden code, no negative effect on performance or other players, no advertising or donation requests,
  content rating, compliance with the Terms of Use and EULA, and Blizzard's right to disable add-on
  functionality. Nothing in it names automation, targeting or minimap information.
- Blizzard's long-standing design: addons may display information and may start protected actions
  (targeting, casting) only through player input. Blizzard has disabled addons that automate play, such as
  one-button combat. That is why MobHunter does not auto-target.

How MobHunter fits: it only reads what the client already shows (nameplates and minimap tooltips), it does
not act for you, and a targeting action needs your own key press. The remaining risks are (a) minimap
probing runs many tooltip lookups every second, which is a performance question under rule 3, and (b) the
minimap technique is a workaround rather than a documented API, so Blizzard could restrict it, as it has
done for other information with "secret values". NodeSight, which uses the same technique, is published for
WoW Forever, which is evidence it is tolerated but not a guarantee. Re-check the policy and the in-game
EULA before publishing.

## Not verified on a real client

- `Minimap:UpdateMouseoverAtPoint` and `C_TooltipInfo.GetMinimapMouseover`: the second is on the Warcraft
  Wiki for Forever 1.60.1; the first came from NodeSight's source and has no wiki page I could read. The
  coordinate space (assumed: units from the minimap's bottom-left) is a guess.
- That tracked creatures list their name on a tooltip line, and that probing works in combat.
- That nameplate unit names are readable (they may be "secret values" in some situations; MobHunter treats
  an unreadable name as "no match").
- Anchoring a marker to a nameplate, the sound ID, and the key binding file (`Bindings.xml`).
- Performance of the minimap probe (about 1,000 tooltip lookups a second at the default grid).

## Development

`lua tests/run.lua` covers the matching logic, the minimap probe against a fake minimap, and that
`MobHunter.lua` loads and runs a hunt against a permissive fake client.
