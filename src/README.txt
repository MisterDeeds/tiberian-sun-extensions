TIBERIAN SUN - EXTENSIONS 1.3.1
===============================

Fan project for Command & Conquer Tiberian Sun and Firestorm (Steam).
https://github.com/MisterDeeds/tiberian-sun-extensions

PLAY
1. Start "Tiberian Sun - Extensions" (desktop or Start menu).
2. Pick a preset or your own options, click "Start game".
3. In the game, click "Firestorm" on the first screen.

HUGE WORLDS
Skirmish > Multiplayer map > Random map. Set map width and height to "Very large".
With the option "Random map size: huge" maps are 200 to 235 cells wide and high, with "large" up to 220
(original: at most 175, with 4 players 128).
"Random map terrain: flat" - hardly any hills and cliffs, little water: room for huge bases (92 % of the map
buildable instead of 59 %); "rugged" - many plateaus, hills and passes.
"Random map Tiberium: twice / 4 times as much" - the generator gives a map the same amount of Tiberium however
big it is; the option multiplies it, in the fields and next to every start position.
The sliders of the random map dialog start at these values; you can still move them.

TOUGHER OPPONENTS
"Computer opponents: strong / brutal" - more money, earlier and bigger attacks, a fierce defense of their base;
they repair every damaged building at once (the original repairs one at a time) and never sell their buildings.

SHARP GRAPHICS
The default is your screen resolution: the game is drawn 1:1 instead of stretched, and you see much more of the
map. The sidebar fills the whole screen height (up to 40 build rows instead of 20).
After the game the previous resolution is written back.

GAME SPEED
The game computes as many frames per second as the game speed allows; on "unlimited" that is up to 120 frames/s
with the Steam version, so everything runs eight times as fast as at 15 frames/s. The option "Game speed" sets
60, 30 or 20 frames/s; "unchanged" (default, also with the presets "Everything bigger" and "Original") leaves
the speed as you have it. During a battle: Esc > "Game controls" > "Game speed" - far right is unlimited, each
step to the left slower (60, 30, 20, 15 ... frames/s), at once. Huge maps do not slow the game down (measured:
235 x 235 with 8 players, steady 120 frames/s). Countdowns and attack waves of the missions follow game time.

NEW CAMPAIGNS
New campaign > "Extension - GDI: Operation Dawn", "Extension - Nod: Kane's Legacy" or a "Challenge".
The difficulty sets the size and frequency of the attack waves. The missions were built at install time from the
maps of your game ("Rebuild missions" in the start window builds them again).

WHAT CHANGES WHERE
- Rules options: EXPAND99.MIX in the game folder, only while the game runs.
- Random maps (size, terrain sliders, Tiberium), repairs of the computer opponents and sidebar fix: only in the
  memory of the running game.
- Campaigns: TSX*.MAP and BATTLEX.INI in the game folder.
- Resolution and game speed: [Video] and [Options] in SUN.INI, set back after the game.
No original file is changed. A start from Steam is always the original.

UPDATES
At every start the launcher asks GitHub for the newest version. With "Update automatically" (top right, on by
default) a newer one is installed at once and the launcher opens again; your settings stay. Never while the game
runs, at most one try per version and day. Without the check box the button "Update now" appears instead.
Updating by hand: run the line from the README again.

REMOVE
Windows Settings > Apps > "Tiberian Sun - Extensions", or uninstall.cmd from the download.

NOTES
- Tested with Game.exe 2.03 TUC (Steam). With another version the memory patches are skipped.
- The rules options apply to Firestorm games (skirmish in Firestorm mode, Firestorm missions, the new campaigns).
- Single player only.
- Technical details: docs\FINDINGS.md


