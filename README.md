# Tiberian Sun – Extensions

*[Deutsche Version](README.de.md)*

A fan project for **Command & Conquer Tiberian Sun and Firestorm** (Steam, Game.exe 2.03 TUC): huge random worlds,
sharp graphics in your screen's native resolution, 15 new missions in two campaigns and five challenges, and
16 options for rules, world and display, all in one start window.

No original game file is changed. The extensions work through files the game reads in addition to its own (an extra
archive and new mission files) and through the memory of the running game. When the game ends, everything is as
before; a game started from Steam is always the original. Single player only.

<p align="center">
  <img src="docs/images/giant-random-map.png" alt="A huge random map in 2560 x 1440 with the full-height sidebar" width="80%">
</p>

## What it does

| Feature | What you get |
|---|---|
| **Huge random worlds** | The game's own random map generator makes maps up to **235 × 235 cells** (original: at most 175 × 175, and only with 8 players; 128 × 128 with 4 players) – with rivers, cliffs, tiberium, forests and ruins. |
| **Sharp graphics** | The game runs in your screen's native resolution (e.g. 2560 × 1440) – no more stretched, blurry pixels, and you see much more of the battlefield. The sidebar fills the whole screen height with up to 40 build rows (original: 20 – more rows crashed the game). |
| **Game speed** | 60, 30 or 20 frames per second, or unlimited. On "unlimited" the Steam version runs at 120 frames/s – eight times the classic speed. |
| **New campaigns** | *Operation Dawn* (GDI, 5 missions) and *Kane's Legacy* (Nod, 5 missions): conquest, survival, commando, defense and economy missions with enemy bases that build and attack like the skirmish AI, attack waves that grow with time and difficulty. |
| **Challenges** | The Flood (survive 30 min), All Against One (5 enemies), Blitz (25 min), Economic Miracle (100,000 credits), Ice Desert (huge map, 6 enemies). |
| **Rules options** | Build costs, build speed, tiberium value and growth, harvester load, power output, promotions, super weapon charge time, unit hit points, extended arsenal (Umagon, Chameleon spy, heroes up to 3 times), stronger or brutal computer opponents, meteorites and visceroids, fog of war. |
| **Presets** | Original, Everything bigger, Relaxed, Hard test, Chaos. |

<p align="center">
  <img src="docs/images/launcher-de.png" alt="Start window" width="48%">
  <img src="docs/images/campaign-list.png" alt="The new campaigns in the game's campaign list" width="48%">
</p>

## Install

You need **Command & Conquer Tiberian Sun and Firestorm** from Steam and Windows 10/11.

**One line** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/MisterDeeds/tiberian-sun-extensions/main/get.ps1 | iex
```

**Or** download the [latest release](https://github.com/MisterDeeds/tiberian-sun-extensions/releases/latest),
unpack it and double-click `install.cmd`.

The installer copies the tool to `%LOCALAPPDATA%\Programs\TSExtensions`, builds the missions from the maps of *your*
installation (in German on a German Windows, otherwise in English), copies them into the game folder, and creates the
shortcut **Tiberian Sun - Extensions** on the desktop and in the Start menu. Remove it again with `uninstall.cmd` or
under Windows *Settings > Apps*.

## Play

1. Start **Tiberian Sun - Extensions**, pick a preset or your own options, click **Start game**.
2. In the game, click **Firestorm** on the first screen.
3. **Huge worlds:** Skirmish > Multiplayer map > Random map, set map width and height to *Very large*
   (with the option *huge*: 200–235 cells per side; *large*: up to 220).
4. **New campaigns:** New campaign > choose an entry starting with *Extension* or *Challenge*.
   The difficulty slider sets the size and frequency of the enemy attack waves.

## How it works

Everything was found by reverse engineering the Steam `Game.exe` (2.03 TUC) with Ghidra; addresses, file formats and
in-game measurements are in [docs/FINDINGS.md](docs/FINDINGS.md).

- **Random map size** – the generator computes the map size from four tables (7 entries each, for 2–8 players).
  The tool writes larger values into these tables in the memory of the running game (checked first: only if the
  original values are there).
- **Native resolution and full-height sidebar** – the sidebar has room for 2 × 20 build buttons. At more than about
  1214 pixels screen height the game computes more rows, overflows the array and crashes when a battle starts. The tool
  moves the button array to new memory with room for 2 × 40 rows: it rewrites the 11 instructions that hold its
  address, doubles the column stride in the 7 places that compute "row + column × 20", and limits the sidebar
  height to 40 rows. Then any resolution up to 2160 pixels height works with a sidebar from top to bottom.
- **Mission timing** – waves, countdowns and time limits use game time (game frames ÷ 15), like the original
  missions, so they follow the game speed.
- **Rules options** – a changed copy of your own `FIRESTRM.INI` goes into the archive `EXPAND99.MIX`. The game searches
  archives before loose files and loads `EXPAND99` before Firestorm's `EXPAND01`, so the copy wins. The archive is
  removed when the game ends.
- **Campaigns** – the game adds every `BATTLE*.INI` of its folder to the campaign list. The missions (`TSX*.MAP`) are
  built at install time from the official multiplayer maps of your installation: terrain from the original map,
  plus houses, bases on flat buildable ground (checked against the tile templates of the theater), units, triggers,
  teams and attack waves.

Nothing of the game is in this repository – only code and documentation. The game is read from your installation.

## Notes

- Only for the Steam version with `Game.exe` 2.03 TUC (SHA-256 `58CFDBA4…AE17DB3`). With another version the memory
  patches are skipped (the tool then stays at a resolution that works without them); options and campaigns still work.
- The rules options apply to Firestorm games: skirmish in Firestorm mode, Firestorm missions and the new campaigns.
- Missions count in game time: at 120 frames/s a "20 minute" countdown takes 2.5 real minutes. Pick 60 or 30
  frames/s under *Game speed* for a calmer pace.
- Huge maps need more computing power; with 8 players on 235 × 235 the game can get slower late in the battle.
- Single player only. Online and LAN games are not touched when you start the game without this tool.

## Development

`tests\test-missions.ps1`, `tests\test-rules.ps1` and `tests\test-install.ps1` check the missions, the rules file and
a complete install/remove in a sandbox. `dev\` has the analysis tools (Ghidra scripts, map renderer, game probe and an
automatic mission test that starts the game, clicks through the menus and checks that the game logic runs).

Fan project, not affiliated with Electronic Arts. Command & Conquer, Tiberian Sun and Firestorm are trademarks of
Electronic Arts Inc. MIT license.
