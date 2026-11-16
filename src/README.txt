TIBERIAN SUN - EXTENSIONS 1.2.0
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

SHARP GRAPHICS
The default is your screen resolution: the game is drawn 1:1 instead of stretched, and you see much more of the
map. The sidebar fills the whole screen height (up to 40 build rows instead of 20).
After the game the previous resolution is written back.

GAME SPEED
The game computes as many frames per second as the game speed allows; on "unlimited" that is up to 120 frames/s
with the Steam version, so everything runs eight times as fast as at 15 frames/s. The option "Game speed" sets
60, 30 or 20 frames/s. Countdowns and attack waves of the missions follow game time.

NEW CAMPAIGNS
New campaign > "Extension - GDI: Operation Dawn", "Extension - Nod: Kane's Legacy" or a "Challenge".
The difficulty sets the size and frequency of the attack waves. The missions were built at install time from the
maps of your game ("Rebuild missions" in the start window builds them again).

WHAT CHANGES WHERE
- Rules options: EXPAND99.MIX in the game folder, only while the game runs.
- Random map size and sidebar fix: only in the memory of the running game.
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


