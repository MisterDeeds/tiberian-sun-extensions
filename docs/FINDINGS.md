# Findings – Tiberian Sun 2.03 TUC (Steam)

Reverse-engineering notes behind the Tiberian Sun Extensions. Target: `Game.exe` of the Steam release
"Command & Conquer Tiberian Sun and Firestorm" (app 2229880), file version "2.03 TUC", 3,860,528 bytes,
SHA-256 `58CFDBA4134A9B5F9E7680692094720CD382BA63FC5172990C4516318AE17DB3`. Image base 0x400000; sections:
`.text` 0x401000, `.rdata` 0x6CA000, `.data` 0x6EE000, `.rsrc` 0x869000. Analysed with Ghidra 12 (headless, scripts in
`dev/ghidra_scripts`), checked in the running game with `dev/game-probe.ps1` and `dev/test-mission.ps1`.

## Files and archives

### MIX archives

- New format: `uint32 flags` (first two bytes 0), `0x20000` = header encrypted, `0x10000` = SHA-1 at the end.
- Encrypted header: 80 bytes key source after the flags, decrypted with Westwood's public RSA key
  (`AihRvNoIbTn85FZRYNZRcT+i6KpU+maCsEqr3Q5q+LDB5tH7Tz2qQ38V`, exponent 0x10001) in two blocks of 40 → 39 bytes;
  the first 56 bytes are a Blowfish key. Blowfish is standard (big-endian halves). Index: `ushort count`,
  `uint size`, then `count` × (`uint id`, `uint offset`, `uint size`), sorted by id as signed int.
- File id: CRC-32 of the upper-case name; if the length is not a multiple of 4, append `len % 4` as a byte and fill
  with the character at the last multiple of 4.
- Blowfish tables are not stored in this project; they are the hexadecimal digits of pi and are computed
  (`TSLib.cs`, Machin formula with `BigInteger`).

### Search order (FUN_004E3D20)

`PATCH.MIX`, `PCACHE.MIX`, `EXPAND99.MIX` … `EXPAND00.MIX`, `ECACHE99.MIX` … `ECACHE00.MIX`, `TIBSUN.MIX`, `CACHE.MIX`,
`LOCAL.MIX`, later the rest. The first registered archive wins. Archives are searched **before** loose files (like
`CCFileClass::Open` in Westwood's released sources): a loose `FIRESTRM.INI` is ignored, a loose file whose name exists
in no archive (`BATTLEX.INI`, `TSXG01.MAP`) is used.

Checked in the game: `EXPAND99.MIX` containing a changed `FIRESTRM.INI` (BuildSpeed 0.4) → `Rule+0xEE8` = 0.4 in a
Firestorm mission.

### Where the INI files are

| File | Archives (search order) |
|---|---|
| RULES.INI | PATCH.MIX, EXPAND01.MIX, LOCAL.MIX |
| FIRESTRM.INI | EXPAND01.MIX |
| ART.INI / ARTFS.INI | PATCH, EXPAND01, LOCAL / EXPAND01 |
| BATTLE.INI / BATTLEFS.INI | LOCAL / EXPAND01 |
| MISSIONS.PKT, MULTI01.PKT | LOCAL, EXPAND01 |
| TEMPERAT.INI, SNOW.INI | EXPAND01, LOCAL |
| Tiles (*.tem, *.sno) | ISOTEMP.MIX / ISOSNOW.MIX / TEMPERAT.MIX / SNOW.MIX inside EXPAND01 and TIBSUN |

## Rules

- FUN_004E0E80 loads `RULE*.INI` (FindFirstFile; several files → a selection dialog), ART.INI, ARTFS.INI,
  FIRESTRM.INI (if Firestorm is installed), LANGRULE.INI, AI.INI, AIFS.INI.
- Rules object: pointer at `0x74C488`. [General] is read by FUN_005C9630, e.g. VeteranRatio `+0x398`,
  VeteranCombat `+0x3A0`, SurvivorRate `+0xC98`, GrowthRate `+0xDD8`, RefundPercent `+0xED8`, BuildSpeed `+0xEE8`
  (doubles).
- The values are set when a scenario starts. FIRESTRM.INI is applied only to scenarios with `RequiredAddOn=1`
  (measured: VeteranRatio 10 in a map without it, 5 in one with it). Therefore all our missions are Firestorm
  missions.
- Firestorm installed/enabled: `0x6F2638` (installed addons, bit 1 = Firestorm), `0x6F263C` (enabled, set by the TUC
  selection screen). FUN_00407120 / FUN_00407150 test them.

## Campaigns

- FUN_004E0C20 reads every `BATTLE*.INI` of the game folder plus BATTLE.INI / BATTLEFS.INI from the archives
  ("Additional files that begin with BATTLE will augment this list" – BATTLE.INI).
- Campaign objects: vector data `0x7E2234`, count `0x7E2240`; object `+0x14` name, `+0x60` CD, `+0x64` Scenario,
  `+0x264` FinalMovie, `+0x268` Description, `+0x2E8` RequiredAddon (FUN_00448B80).
- "Choose campaign" dialog (FUN_004E3200, list box 0x455 = 1109, difficulty slider 0x50F): with Firestorm enabled only
  campaigns with `RequiredAddon=1` are listed, otherwise only those with 0.
- Checked: with our BATTLEX.INI the game has 13 campaigns (4 + 9 in an early build), the dialog lists our entries with
  umlauts.

## Maps

- `[IsoMapPack5]`: base64 of chunks (`ushort packed`, `ushort unpacked`, LZO1X data). Cells of 11 bytes:
  `ushort x, ushort y, int tile (0xFFFF = clear), byte subtile, byte level, byte ice`, then 4 bytes at the end.
- `[OverlayPack]`, `[OverlayDataPack]`: same chunks with LCW ("format 80"), 512 × 512 bytes, index `y * 512 + x`
  (checked on all 39 official multiplayer maps: overlays on water/cliffs 0–62 with this reading, 35–517 with x/y
  swapped).
- Waypoints and cell numbers: `y * 1000 + x`.
- Sub-tile = index into the template grid including empty positions (no cell of the 39 maps points to an empty one).
- TMP (tile template) header: `int width, height, blockWidth, blockHeight`, then `width × height` offsets; each tile
  header has at +40 height, +41 terrain type (0 clear, 7/8 rock, 9 water, 10 beach, 11/12 road, 13 clear, 14 rough,
  15 cliff), +42 ramp type (0 = flat).
- `[Houses]` Credits are hundreds (FUN_004C2F10: `Credits * 100`).
- Object lines: `[Structures]` house, type, health, x, y, facing, tag, AI sellable, AI rebuild, powered, upgrades,
  spotlight, upgrade 1–3, AI repairable, nominal. `[Units]` house, type, health, x, y, facing, mission, tag,
  veterancy, group, on bridge, follows, auto-no, auto-yes. `[Infantry]` like units with sub-cell after y.
- **A unit with an empty tag field hangs the game**: a harvester with `…,Harvest,,0,…` sends the path finder
  (FUN_0041D070, called from FUN_004A0730 → FUN_00498EF0 → FUN_0041D6E0) into an endless search in the first frame.
  Always write `None`.
- Triggers (FinalSun's FSData.ini lists the TS events and actions): event 47 "Elapsed scenario time" in seconds
  (an official trigger "8 min elapse" uses 480); action 3 production begins, 74 AI triggers begin, 13 autocreate begins,
  30 auto base building (the house builds like in skirmish), 80 reinforcement at waypoint (p1 = 1, team id).
  Script action `11,14` = do mission "Hunt" (the official "Hunt" scripts).

## Random map generator

- Object at `0x805E10` (dialog FUN_0053A8C0 reads the controls; generator FUN_0053CE70, setup FUN_0053D950).
- Map size (0x53DA7C): `width = minW[p] * (1 - s) + maxW[p] * s`, same for the height; `p = players - 2`, `s` from the
  size combo box ("Klein" … "Sehr groß"). Tables of 7 ints: minW `0x6D3F24`, maxW `0x6D3F40`, minH `0x6D3F5C`,
  maxH `0x6D3F78`; original min 50/65/75/85/100/120/135, max 100/115/128/140/160/170/175.
  `[Map] Size` becomes `width + 4, height + 12`, LocalSize `2, 5, width, height`.
- Result in `0x805E10 + 0x100` (width) and `+0x104` (height). Checked: with the patched tables and 4 players,
  "Sehr groß" gives 225 × 225, the battle starts and runs.

## Sidebar and high resolutions

- Sidebar rectangle `0x74C240` x, `0x74C244` y, `0x74C248` width (168), `0x74C24C` height (= screen height − 148).
- Build buttons: array at `0x80B950`, 40 entries of 0x34 bytes (FUN_005F2290), 2 columns × 20 rows
  (FUN_005F42A0: entry = row + column × 20). Rows = (height − top − bottom) / 51 with top 25, bottom 21
  (shapes at `0x80C3A8`, `0x80C3B0`, button shape `0x80C3AC`).
- At 2560 × 1440: height 1292 → 24 rows → the array overflows into the object at `0x80C1C8` (a sidebar tab), whose
  vtable becomes 0xDC (the value FUN_005F42A0 writes to `+0x24` of an entry) → access violation at 0x4B955A when a
  battle starts (`except.txt`: "Access address: 00000100").
- The height is written only at 0x5F2766 (FUN_005F2720) and 0x5F60D7 (FUN_005F6080), both as
  `LEA EAX,[...-0x94]; MOV [0x74C24C],EAX`. The fix hooks both (12 bytes each) and limits the height to
  46 + 20 × 51 = 1066. Without the fix the highest safe screen is 148 + 1066 = 1214 pixels.
- Checked: 2560 × 1440 skirmish on a 225 × 225 map and campaign missions run with the fix.

## Display

The Steam release ships DDrawCompat 0.5.4 (`ddraw.dll`, `DDrawCompat.ini`: point filter, FPS limit 120). The default
SUN.INI resolution 1920 × 1200 is stretched to 16:9 screens non-uniformly (× 1.333 / × 1.2), which looks blurry and
distorted. In native resolution the game is drawn 1:1. Mouse input arrives in game coordinates (real mouse;
`WM_LBUTTON*` messages are ignored by the game). The menus are real Win32 dialogs (`#32770`) and can be driven with
`WM_COMMAND`, `LB_SETCURSEL`, `CB_SETCURSEL` and `TBM_SETPOS`.

## Strings, for orientation

`RULE*.INI` 0x6FE098, `BATTLE*.INI` 0x6FDF88, `RandMap.Map` 0x701D28, `*.MPR` 0x70DE74, `MISSIONS.PKT` 0x70DEA0,
`MULTI%02d.PKT` (custom multiplayer map lists), `EXPAND%02d.MIX` 0x6FE398. "Vinifera" at 0x71113C is the tiberium
type, not the engine extension of the same name.
