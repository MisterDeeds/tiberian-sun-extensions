# Changelog

## 1.4.0 – 2026-11-22

- New terrain **perfectly flat**: the whole random map lies on one level – no cliffs, no water, no ruins, few
  trees, room for whole cities. (*flat* still had three levels with cliffs between them: the generator splits big
  areas and lifts or lowers each part; a memory patch stops that.) Measured on 225 × 225: one level, 0 % cliffs and
  water, 98 % buildable and all of it in one piece (*flat*: largest area 35,628 cells, now 97,241); also with 8 players
  on 235 × 235.
- New option **Map: whole map visible from the start** – no black, unexplored land.
- New option **Visceroids: none** – infantry killed by Tiberium no longer turns into visceroids.
- New option **Build distance**: place your buildings up to 6 or 10 cells away from your base (original: 2).
- New preset **City builder**: huge, perfectly flat, 4 × Tiberium, whole map visible, no visceroids, build
  distance 10.
- Removed: the options *Meteorites and visceroids* and *Fog of war* – the game never read them from the rules, so
  they did nothing. Meteorites and fog of war are off on random maps anyway; ion storms come only if you tick
  *Ion storm* in the random map dialog.
- Checked in the game: generated maps, a battle on a perfectly flat map, and the launcher end to end with all new
  options (whole map visible from the first frame, battle 2 minutes, everything put back afterwards).
- Launcher window a bit taller; new analysis tool `dev\run-when-idle.ps1` (runs the in-game tests only while nobody
  uses the PC and stops at the first mouse or key press).

## 1.3.2 – 2026-11-16

- Fixed: the automatic update often did not start when the launcher was opened from the **desktop shortcut**
  (Windows 11; 9 of 13 tries). The launcher started the update window and closed in the same moment, and the new
  window died with it. Now the launcher waits until the update window runs (at most 3 s) and only then closes; if
  the window does not start, it says so and *Update now* tries again. Checked: 10 of 10 updates from the desktop
  shortcut.
- For copies 1.2.0 to 1.3.1 the old launcher still does the update: if nothing happens, open the launcher from the
  **Start menu** and click *Update now* (worked at once on the test PC), or run the line from the README.

## 1.3.1 – 2026-11-16

- Preset *Everything bigger* no longer sets the game speed to 60 frames/s – the speed stays as you have it (on
  "unlimited" the Steam version runs at 120 frames/s, twice as fast as 60).
- Measured in the game: on a 235 × 235 random map with 8 players (7 computer opponents, flat, 4 × Tiberium) the
  game ran at a steady 120 frames/s for 8 minutes of heavy fighting – huge worlds do not slow it down.
- Documented: the speed can be changed during a battle (Esc → *Game controls* → *Game speed*, 7 steps from
  unlimited to 10 frames/s, takes effect at once); checked in the game at 120, 60 and 20 frames/s.
- New analysis tool `dev\speed-test.ps1` (frames per second on a huge map, screen pictures, reason if it stops).

## 1.3.0 – 2026-11-16

- New option *Random map terrain*: **flat** – hardly any hills and cliffs, little water, room for huge bases
  (measured on 225 × 225: 92 % of the map buildable instead of 59 %, largest flat area 4 to 16 times as big) – or
  **rugged** – many plateaus, hills and passes. The sliders of the random map dialog start at these values (they
  start at 0 in the original game) and can still be moved.
- New option *Random map Tiberium*: twice or 4 times as much. The generator gives a map the same amount of Tiberium
  however big it is; the option multiplies it, in the fields and next to every start position, and puts the
  Tiberium sliders to the right (measured: 4.5 times as many Tiberium cells).
- *Computer opponents strong / brutal*: they now repair **every** damaged building at once (the original repairs
  one at a time and then waits – memory patch), **never sell** their buildings, repair even with little money,
  keep more defense teams and answer attacks on their base faster and harder.
- Fixed: *Tiberium growth fast / very fast* made Tiberium grow **slower** (the game's Growth and Spread values are
  waiting times; they were multiplied instead of divided).
- Presets: *Everything bigger* now with flat terrain, 4 × Tiberium and faster growth; *Relaxed* flat with
  2 × Tiberium; *Hard test* rugged.
- New test `tests\test-patches.ps1` (every memory patch against your Game.exe) and the analysis tools
  `dev\rmg-survey.ps1`, `dev\rmg-stats.ps1` and `dev\launcher-game-test.ps1`.

## 1.2.0 – 2026-11-16

- Automatic updates: at every start the launcher asks GitHub for the newest release. If there is a newer one, it
  installs it by itself and opens again – settings stay. Check box "Automatisch aktualisieren / Update
  automatically" at the top right (on by default); without it the button "Update now" appears instead. At most one
  try per version and day, never while the game runs.
- After an update the launcher says "Updated to version x.y.z" once, with a button "What is new?" for the release
  notes.
- `get.ps1` (the one-line installer) downloads the newest tag, falls back to the release page when the GitHub API
  is not available, always installs with Windows PowerShell 5.1, waits for Enter after an error when the launcher
  started it and cleans up its temporary folder even when a virus scanner still holds the files.
- The installer writes `version.txt` (from this changelog), shows the version in the Apps entry and its closing
  lines, opens the launcher at the end (`get.ps1`, `install.cmd`) and waits for Enter when uninstalling from
  Windows Settings > Apps. The installed copy only removes, it no longer installs over itself.
- The launcher keeps all keys of `settings.json` when it saves (before, saving the options dropped everything
  else).
- Versions 1.0.0 and 1.1.0 have no update check: install 1.2.0 once with the line from the README, after that the
  extensions keep themselves up to date.

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
