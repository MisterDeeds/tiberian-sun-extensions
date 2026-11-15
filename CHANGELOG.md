# Changelog

## 1.1.0 – 2026-11-16

- Full-height sidebar: at high resolutions the sidebar now reaches from top to bottom with up to 40 build rows per
  column instead of ending after 20 (button array moved to new memory, 11 addresses and 7 index computations
  patched).
- New option *Game speed*: 60, 30 or 20 frames per second, or unlimited (120 with the Steam version).
  Presets: *Everything bigger* 60, *Relaxed* 30. Like the resolution, the previous speed is written back to
  SUN.INI when the game ends.
- Missions fixed: attack waves came far too often (repeating triggers had a 1 in the last field, and waves were timed
  in real seconds while the game counts game time) and overran the player's base within two minutes. All mission
  times now use game time like the original missions; survival, defense and time limits run on the on-screen
  countdown. Win and lose conditions use "destroyed all" like the original missions.
- Units placed by the missions never get an empty tag (an empty tag made the path finder of a harvester hang).

## 1.0.0 – 2026-11-15

First release.

- Huge random worlds: the random map generator makes maps up to 235 × 235 cells (memory patch of its size tables).
- Sharp graphics: native screen resolution, made possible by a fix for the sidebar overflow of Game.exe at screen
  heights above 1214 pixels; the resolution is set back after the game so that a start from Steam keeps working.
- Two new campaigns (GDI *Operation Dawn*, Nod *Kane's Legacy*, 5 missions each) and five challenges, built at install
  time from the official multiplayer maps of the player's installation.
- 15 rules options and 5 presets, written as `EXPAND99.MIX` (changed copy of the player's FIRESTRM.INI) while the game
  runs.
- Start window (German / English), installer with shortcuts and an entry under Windows "Apps", one-line installer.
- Tests: missions, rules, sandbox install; analysis tools and an automatic in-game mission test.
