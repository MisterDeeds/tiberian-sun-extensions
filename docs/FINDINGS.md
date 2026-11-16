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

### Sliders, terrain and Tiberium (1.3)

- Dialog template: Language.dll, dialog 107 (Firestorm) / 101. Sliders (trackbars, range 0–100) and the fields of
  the generator object they show (FUN_0053ABB0 sets them from the fields, FUN_0053A8C0 reads them back on OK):

  | Label | Control | Field | RandMap.Sed key |
  |---|---|---|---|
  | Spieler | 1003 | `+0x44` (2–8) | NumPlayers |
  | Klippen | 1021 | `+0x64` | RegionSize |
  | Zugänge | 1020 | `+0x60` | Accessibility |
  | Berge | 1001 | `+0x38` | Ruggedness |
  | Tiberiummenge | 1016 | `+0x48` (1–100) | Tiberium |
  | Tiberiumfelder | 1015 | `+0x4C` | TiberiumLayout |
  | Gewässer | 1008 | `+0x40` | WaterAmount |
  | Vegetation | 1012 | `+0x50` | Vegetation |
  | Stadtruinen | 1013 | `+0x54` | UrbanPresence |
  | Kratermonster | 1023 | `+0xF0` (0–5) | VeinholeMonsters |

  Seed `+0x68` (the Firestorm dialog has no seed field). The fields are 0 when the game starts (players 2,
  Tiberium 1) and keep their values for the session. `RandMap.Sed` (reader 0x53C6F0, writer near 0x53C456) is written
  by the game on OK but **not** read when the dialog opens (checked: file with other values, dialog still at 0).
- "Klippen" is the region size: regions with more cells than
  `(RegionSize × 0.005 + 0.05) × [0x805F14] × [0x805F10] × 2` are split again (FUN_00533AD0, 0x533C99; borders
  between regions of different height become cliffs), so a **higher** value means **fewer** cliffs.
- Tiberium (FUN_00546600): number of fields `TiberiumLayout × 0.01 × 10 + players + 3` (FUN_005397D0); each field
  gets `(Tiberium × 30 + 2500) × players / fields` cells plus a random ±100 (0x54661E: `LEA`s, `IMUL [EBX+0x44]`,
  `IDIV`); then every player a field near the start position of `(distance term) + 500` (`ADD EAX,0x1F4` at
  0x5468AF). FUN_005468F0 grows a field of that many cells (array of `n × 0x50` bytes). None of it depends on the map
  size. `+0xF5` = Tiberium > 0.75 (blue Tiberium with Firestorm). `0x6B2330` is `__ftol`, not a random function.
- Measured (dev\rmg-survey.ps1 + dev\rmg-stats.ps1; 4 players, "Sehr groß" = 225 × 225 cells, seed 4711; the survey
  patches the OK path to write the full map to RandMap.Map: JZ 0x53A620 and JZ 0x5DE18B → NOPs; seed fixed):

  | Sliders (Klippen/Zugänge/Berge/Tib./Felder/Wasser/Veg./Ruinen), factor | Cliff | Ramp/hill | Water | Buildable | Largest flat area | Tiberium cells |
  |---|---|---|---|---|---|---|
  | 50/50/40/60/60/30/60/30 | 3.0 % | 20.9 % | 12.1 % | 58.7 % | 8,545 | 1,729 |
  | Klippen 0 | 4.9 % | 24.5 % | 12.2 % | 53.6 % | 5,046 | 1,938 |
  | Klippen 100 | 2.3 % | 24.7 % | 12.2 % | 55.8 % | 4,588 | 1,841 |
  | **flat** 100/100/0/60/60/5/25/10 | 2.2 % | 0.3 % | 1.1 % | 91.8 % | 35,628 | 1,856 |
  | rugged 0/30/90/60/60/30/60/30 | 4.9 % | 32.6 % | 12.1 % | 45.2 % | 3,554 | 2,042 |
  | Tiberium 100, Felder 100 | 3.0 % | 20.0 % | 12.2 % | 59.2 % | – | 2,349 |
  | factor 2 | 3.0 % | 21.9 % | 12.2 % | 56.4 % | – | 3,261 |
  | factor 4 | 3.0 % | 20.1 % | 12.1 % | 55.1 % | – | 6,160 |
  | flat, Tiberium 100/100, factor 4 (fields and start fields) | 2.2 % | 0.3 % | 1.1 % | 85.6 % | 34,122 | 8,576 |

  Seed 90210: usual sliders 55.5 % buildable, largest flat area 3,612; flat 91.5 %, 56,566. Each map took 5–6 s,
  the battle on the last one runs.
- Option *Random map terrain* writes the slider fields (flat: RegionSize 100, Ruggedness 0, Accessibility 100,
  WaterAmount 5, Vegetation 25, UrbanPresence 10; rugged: 0 / 90 / 30 / 30 / 60 / 30). Option *Random map
  Tiberium* (× 2, × 4) sets Tiberium and TiberiumLayout to 100 and hooks 0x546624 and 0x5468AF with
  `IMUL EAX,[factor]`.

### Tiberium growth

- FUN_00645DC0 (growth) and FUN_00645330 (spread) run for every Tiberium type when the scenario has
  `[Basic] TiberiumGrowthEnabled=yes` (`Scen+0x1D82`; random maps write yes). The next step comes after the type's
  `Growth` (`+0x70`) resp. `Spread` (`+0x64`) frames – for growth × 0.3 if `[SpecialFlags] TiberiumGrows` (bit 5 of
  `Scen+0`) is set, × 1 otherwise (random maps: not set). `GrowthPercentage` (`+0x78`) of the cells grow per step,
  5 to 50. So **smaller** Growth/Spread = faster.
- `[General] GrowthRate` (`+0xDD8`), `TiberiumGrows` and `TiberiumSpreads` are read (or not even that) but never used;
  `[MultiplayerDefaults] TiberiumGrows` (`+0xF5B`) is stored but never used.
- Versions 1.0–1.2 made *Tiberium growth: fast* slower (they multiplied Growth and Spread); 1.3 divides them.

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

### Full-height sidebar (1.1)

- A byte scan of the whole code for addresses inside the array (0x80B950 … 0x80C170) finds exactly 12 places in
  the sidebar code: the static initializer at 0x5F2294 (runs before any patch) and 11 runtime places –
  displacements at 0x5F407C, 0x5F4143, 0x5F43DC, 0x5F452A, 0x5F454A, 0x5F4615 (entry base, `LEA r,[idx*4+0x80B950]`),
  0x5F63BD (`LEA EBP,[ESI+0x80B950]`) and 0x5F63D6 / 0x5F63DC / 0x5F63EF / 0x5F63FF (fields +0x10, +0xC, +0x18, +0x14).
  0x5F45FE … 0x5F4619 is code Ghidra did not mark as a function. Other hits elsewhere are unaligned byte coincidences.
- The index is `row + column × 20`, computed as `LEA r1,[col+col*4]; LEA r2,[row+r1*4]`. Changing the SIB scale of
  the second LEA from 4 to 8 makes it `row + column × 40`: 0x5F406D, 0x5F4134, 0x5F4520 (0x97 → 0xD7),
  0x5F43D2, 0x5F453B (0x87 → 0xC7), 0x5F4606 (0x96 → 0xD6). The setup loop of FUN_005F6080 adds 20 per column at
  0x5F6450 (`ADD EDX,0x14` → `0x28`).
- The patch allocates 80 entries, fills them with a copy of the (still unused) first button, rewrites the 11
  displacements and the 7 strides, and raises the height limit to 46 + 40 × 51 = 2086 pixels.
- Checked at 2560 × 1440: 24 rows per column, buttons of both columns at the right places (column 1 x = 2416, column 2
  x = 2484, rows 51 pixels apart), linked into the gadget list; a building ordered from column 1 is built.

## Trigger timing (1.1)

- The game logic runs one step per frame. Frames per second by `[Options] GameSpeed` in SUN.INI, measured with the
  frame counter at 0x7E4924: 0 = unlimited (120 with the Steam DDrawCompat limit `FpsLimiter = msgloop(120)`),
  1 = 60, 3 = 20, 4 = 15.
- Event 13 "Elapsed time", the mission timer (actions 27/25/26, event 14) count **game time** (frames ÷ 15):
  a repeating trigger with 13 = 30 spawned a unit about every 3.7 s at 120 frames/s; a countdown set to 1200 ran
  from 18:32 to 10:31 in one real minute.
- Event 47 "Elapsed scenario time" uses the scenario's ElapsedTimer (`Scen+0x610`, started / `+0x618` accumulated),
  driven by the 60 Hz system timer (FUN_0060AB10), i.e. real time.
- Repeating triggers: tag repeat flag 2, and the last field of the trigger line 0 – every official map writes 0 there.
- Version 1.0 mixed both (waves on event 13 with values meant as real seconds, tiers and survival on event 47); at
  120 frames/s the waves came every ~27 s and overran the base in two minutes. 1.1 uses game time everywhere:
  waves on event 13, wave tiers via locals set by one-shot event-13 triggers, survival / defense / time limit on the
  countdown (event 14) together with a local that is set when the countdown starts.
- Checked in the game: "The Long Night" (survival, 20 game minutes) showed the countdown and ended with the score
  screen; mission 1 held two real minutes without anyone playing.

## Display

The Steam release ships DDrawCompat 0.5.4 (`ddraw.dll`, `DDrawCompat.ini`: point filter, FPS limit 120). The default
SUN.INI resolution 1920 × 1200 is stretched to 16:9 screens non-uniformly (× 1.333 / × 1.2), which looks blurry and
distorted. In native resolution the game is drawn 1:1. Mouse input arrives in game coordinates (real mouse;
`WM_LBUTTON*` messages are ignored by the game). The menus are real Win32 dialogs (`#32770`) and can be driven with
`WM_COMMAND`, `LB_SETCURSEL`, `CB_SETCURSEL` and `TBM_SETPOS`.

## Computer opponents (1.3)

Rules keys and where Game.exe keeps them (rules object `0x74C488`; [General] FUN_005C9630, [AI] FUN_005CCC70,
[IQ] FUN_005CDEB0). Which ones are used was checked with a scan for every instruction that reads the offset:

| Key | Offset | Used by |
|---|---|---|
| [General] MultiplayerAICM | vector at `+0xB50` | scenario start FUN_005DD290 (0x5DD42E): money of a computer house = `AICM[difficulty] × 0.01 × starting credits` – only the starting money, no income bonus |
| [General] AIAlternateProductionCreditCutoff | `+0xB4C` | house production FUN_004C9CB0 |
| [AI] ComputerBaseDefenseResponse | `+0x758` | FUN_006367D0 (0x63681C) |
| [AI] CreditReserve | `+0xEF8` | building AI FUN_00435540 |
| [IQ] RepairSell / SellBack | `+0xC1C` / `+0xC34` | building AI FUN_00435540 |
| [AI] PowerEmergency, BaseSizeAdd, PowerSurplus, RefineryLimit, BarracksLimit, WarLimit, DefenseLimit | `+0x918`, `+0x998`, `+0x99C`, `+0x98C`, `+0x988`, `+0x978`, `+0x968` | **nothing** – read and stored, never used (Red Alert relics) |

Building AI (FUN_00435540, every damaged building of a computer house with IQ ≥ RepairSell):

- Money below CreditReserve → sell the building, if it may be sold by the AI, the house IQ ≥ SellBack, a random
  0–50 is below the IQ and its health is red.
- Otherwise → start a repair, but only if the house flag `+0x118` is clear. Starting a repair sets the flag and a
  random delay (house `+0x154` frame, `+0x15C` delay); only after it the next building gets repaired. So a computer
  house repairs **one building at a time**.

What the option *Computer opponents* (strong / brutal) does:

- Rules: more starting money (AICM 350/300/200 resp. 600/500/400 %), shorter team delays, higher team caps, more
  defense teams (Minimum 5/4/3 resp. 6/5/4), faster and stronger answer to attacks on the base (BaseDefenseDelay
  0.15 / 0.08 min, ComputerBaseDefenseResponse 4 / 6), spending cutoff 1500 / 500, `CreditReserve=0` (always the
  repair branch), `[IQ] SellBack=99` (above MaxIQLevels 5: never sells).
- Memory patch: the `JNZ` at 0x4355D0 that tests the flag `+0x118` becomes six NOPs – every damaged building is
  repaired at once (repairs still cost money and stop when the money is gone).
- Checked in the game (dev\launcher-game-test.ps1, 2026-11-16): the launcher with *brutal*, *flat* and *Tiberium × 4*
  started the game; in memory the repair patch (six NOPs), both Tiberium hooks and the slider fields; the random map
  dialog opened with Klippen 100, Zugänge 100, Berge 0, Gewässer 5, Vegetation 25, Ruinen 10; in the battle the rules
  object had SellBack 99, CreditReserve 0, ComputerBaseDefenseResponse 6; the battle ran 3 minutes (frame 4643 →
  22758); afterwards SUN.INI was identical and EXPAND99.MIX gone.

## Installation and automatic updates (1.2)

Same scheme as the sister project anno1602-extensions (its version 3.3):

- `get.ps1` (one line: `irm …/main/get.ps1 | iex`) asks `api.github.com/repos/…/releases/latest` for the newest tag
  (without the API, which allows 60 requests an hour: the `Location` of `github.com/…/releases/latest`), downloads
  `archive/refs/tags/<tag>.zip`, unpacks it to `%TEMP%\tiberian-sun-extensions-setup-*` and runs `src\install.ps1
  -StartLauncher` with Windows PowerShell 5.1. Plain ASCII, because the launcher downloads it and runs it as a file,
  and PowerShell 5.1 reads a file without BOM in the ANSI code page. The temporary folder is deleted up to ten times
  0.5 s apart (a virus scanner may still hold the unpacked files).
- `install.ps1` writes `version.txt` (newest `## x.y.z` of `CHANGELOG.md`) into the program folder and the version
  into the Apps entry (`HKCU\…\Uninstall\TSExtensions`). The copy in the program folder only removes (`-Remove
  -PauseAtEnd` from the Apps entry).
- The launcher of an installed copy (`version.txt` present) asks the same API in a background runspace (8 s timeout,
  redirect as fallback) and polls the result with a WinForms timer. With *Update automatically* (`AutoUpdate` in
  `settings.json`, on unless `0`) a newer release is installed at once: download `get.ps1` to
  `%TEMP%\tiberian-sun-extensions-update.ps1`, run it with `-File` and `TSEXT_PAUSE_ON_ERROR=1`, close the launcher;
  the installer opens the new one, which deletes the downloaded script. Not while the game runs or the launcher waits
  for it; `UpdateTried` ("1.2.0 2026-11-16", saved before the start) allows one try per version and day.
- `LastVersion` in `settings.json` older than `version.txt` → "Updated to version x.y.z" once, with a button for the
  release notes of that tag.
- Saving the options used to replace `settings.json` with the option values only; since 1.2 every save keeps the
  other keys.
- Tests: `tests\test-install.ps1` (49 checks): version.txt and Apps entry, the installed copy refuses to install over
  itself, the launcher's self-test with `-PreviewUpdate` (older tag: nothing; newer tag: automatic start; same day:
  only the button; box off: only the button; after an update: the note once), `get.ps1` through `Invoke-Expression`
  with a ZIP in the layout of a tag archive into a second sandbox (files equal the repository, 15 missions, temp
  folder gone) and with a broken ZIP (message, no exception, the window goes on).
- **Real run, 2026-11-16 05:35**, after publishing release 1.2.0: the one-line installer (real download from GitHub)
  installed 1.2.0 over 1.1.0 (which has no update check) and opened the launcher "Tiberian Sun - Erweiterungen
  1.2.0"; `settings.json` kept its six option values and got `AutoUpdate=1`, `LastVersion=1.2.0`. Then
  `version.txt` set to `1.1.9` and the launcher started through the desktop shortcut at 05:35:57: it found v1.2.0
  and ran the update by itself; the installer wrote `version.txt` 1.2.0 at 05:36:02 and the missions at 05:36:04
  and opened the new launcher at 05:36:04, which showed "Aktualisiert auf Version 1.2.0." with "Was ist neu?"
  (picture: `docs/images/launcher-de.png`). Afterwards `UpdateTried=1.2.0 2026-11-16`, option values unchanged, no
  update script and no setup folder left in `%TEMP%`, SUN.INI unchanged, no EXPAND99.MIX in the game folder.
- **First real update, 2026-11-16 08:06**, right after publishing release 1.3.0: the installed 1.2.0 started through
  the desktop shortcut at 08:06:04 found v1.3.0 and updated itself; `version.txt` 1.3.0 at 08:06:08, the new launcher
  "Tiberian Sun - Erweiterungen 1.3.0" at 08:06:10 with "Aktualisiert auf Version 1.3.0." and "Was ist neu?". The
  options in `settings.json` stayed as they were (the two new options start at their defaults), `LastVersion` and
  `UpdateTried` became 1.3.0, nothing left in `%TEMP%`.

## Strings, for orientation

`RULE*.INI` 0x6FE098, `BATTLE*.INI` 0x6FDF88, `RandMap.Map` 0x701D28, `*.MPR` 0x70DE74, `MISSIONS.PKT` 0x70DEA0,
`MULTI%02d.PKT` (custom multiplayer map lists), `EXPAND%02d.MIX` 0x6FE398. "Vinifera" at 0x71113C is the tiberium
type, not the engine extension of the same name.
