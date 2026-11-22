# Memory patches for the running game (Game.exe 2.03 TUC, Steam). Every patch checks the original bytes first and
# writes only if they match ("verify, then patch"); nothing on disk is changed, and everything is back to normal
# when the game ends. Dot-source after tslib.ps1.

# SHA-256 of the Game.exe these patches were made for (Steam, "2.03 TUC").
$script:KnownGameHashes = @('58CFDBA4134A9B5F9E7680692094720CD382BA63FC5172990C4516318AE17DB3')

function Test-GameVersion([string]$gameDir) {
    $h = (Get-FileHash -LiteralPath (Join-Path $gameDir 'Game.exe') -Algorithm SHA256).Hash
    return $script:KnownGameHashes -contains $h
}

# Random map generator: size tables (cells) per number of players 2..8, read by the generator in Game.exe
# (0x53DA7C: width = min * (1 - s) + max * s, s = map size slider). 7 ints each.
$script:RmgTables = @{
    MinW = 0x6D3F24; MaxW = 0x6D3F40; MinH = 0x6D3F5C; MaxH = 0x6D3F78
}
$script:RmgOriginal = @{
    Min = @(50, 65, 75, 85, 100, 120, 135); Max = @(100, 115, 128, 140, 160, 170, 175)
}
$script:RmgSizes = @{
    '1' = @{ Min = @(80, 95, 110, 125, 140, 155, 170); Max = @(140, 160, 180, 195, 210, 220, 220) }
    '2' = @{ Min = @(200, 205, 210, 215, 220, 225, 230); Max = @(215, 220, 225, 228, 230, 233, 235) }
}

# Sidebar: Game.exe has room for 2 x 20 build buttons (array at 0x80B950, 40 entries of 0x34 bytes). The number of rows
# is (sidebar height - 46) / 51; at 1440 pixels screen height that is 24 rows, the array overflows into the next
# object and the game crashes when a battle starts. The sidebar height (0x74C24C) is written in two places only;
# both get a hook that limits it to 46 + 20 * 51 = 1066 pixels. With this, any resolution works (sharp native pixels).
$script:SidebarMaxHeight = 1066
$script:SidebarHooks = @(
    # at, original bytes (LEA EAX,[...-0x94]; MOV [0x74C24C],EAX), the LEA to repeat in the new code
    @{ At = 0x5F275F; Orig = [byte[]](0x8D, 0x84, 0x38, 0x6C, 0xFF, 0xFF, 0xFF, 0xA3, 0x4C, 0xC2, 0x74, 0x00); Lea = [byte[]](0x8D, 0x84, 0x38, 0x6C, 0xFF, 0xFF, 0xFF) }
    @{ At = 0x5F60D0; Orig = [byte[]](0x8D, 0x84, 0x02, 0x6C, 0xFF, 0xFF, 0xFF, 0xA3, 0x4C, 0xC2, 0x74, 0x00); Lea = [byte[]](0x8D, 0x84, 0x02, 0x6C, 0xFF, 0xFF, 0xFF) }
)

function Get-SidebarCave([byte[]]$lea, [int]$max) {
    $m = [BitConverter]::GetBytes([int]$max)
    # LEA ...; CMP EAX,max; JLE +5; MOV EAX,max; MOV [0x74C24C],EAX   (jump back is added by InstallHook)
    return [byte[]]($lea + @(0x3D) + $m + @(0x7E, 0x05, 0xB8) + $m + @(0xA3, 0x4C, 0xC2, 0x74, 0x00))
}

# Full-height sidebar: the button array moves to new memory with room for 2 x 40 rows. Every place that uses the
# array holds its address in the instruction (11 places, found by a byte scan of the whole code), and every place that
# computes "row + column * 20" gets column * 40 instead (6 address computations change their scale from 4 to 8,
# and the column loop of the sidebar setup adds 40 instead of 20). All bytes are checked before anything is written.
$script:SidebarRowsExtended = 40
$script:SidebarArrayOld = 0x80B950
$script:SidebarArrayRefs = @(
    # address of the 4-byte displacement, field offset inside an entry
    @(0x5F407C, 0x0), @(0x5F4143, 0x0), @(0x5F43DC, 0x0), @(0x5F452A, 0x0), @(0x5F454A, 0x0), @(0x5F4615, 0x0),
    @(0x5F63BD, 0x0), @(0x5F63D6, 0x10), @(0x5F63DC, 0xC), @(0x5F63EF, 0x18), @(0x5F63FF, 0x14)
)
$script:SidebarStridePatches = @(
    # address, original byte, new byte
    @(0x5F406D, 0x97, 0xD7), @(0x5F4134, 0x97, 0xD7), @(0x5F43D2, 0x87, 0xC7), @(0x5F4520, 0x97, 0xD7),
    @(0x5F453B, 0x87, 0xC7), @(0x5F4606, 0x96, 0xD6), @(0x5F6452, 0x14, 0x28)
)

function Invoke-SidebarExtend($gp) {
    # already done in this process?
    $first = $gp.ReadUInt([uint32]$script:SidebarArrayRefs[0][0])
    if ($first -ne $script:SidebarArrayOld) { return 'sidebar rows: already' }
    foreach ($r in $script:SidebarArrayRefs) {
        if ($gp.ReadUInt([uint32]$r[0]) -ne [uint32]($script:SidebarArrayOld + $r[1])) { return ('sidebar rows: mismatch at 0x{0:X}' -f $r[0]) }
    }
    foreach ($s in $script:SidebarStridePatches) {
        if ($gp.ReadByte([uint32]$s[0]) -ne [byte]$s[1]) { return ('sidebar rows: mismatch at 0x{0:X}' -f $s[0]) }
    }
    $entries = 2 * $script:SidebarRowsExtended
    $entry = $gp.Read([uint32]$script:SidebarArrayOld, 0x34)     # a constructed, still unused button
    $mem = $gp.Alloc($entries * 0x34 + 0x40)
    $buf = New-Object byte[] ($entries * 0x34)
    for ($i = 0; $i -lt $entries; $i++) { [Array]::Copy($entry, 0, $buf, $i * 0x34, 0x34) }
    $gp.Write($mem, $buf)
    foreach ($r in $script:SidebarArrayRefs) { $gp.Write([uint32]$r[0], [BitConverter]::GetBytes([uint32]($mem + $r[1]))) }
    foreach ($s in $script:SidebarStridePatches) { $gp.Write([uint32]$s[0], [byte[]]@([byte]$s[2])) }
    return ('sidebar rows: {0} per column (array at 0x{1:X})' -f $script:SidebarRowsExtended, $mem)
}

function Invoke-SidebarFix($gp) {
    $log = @()
    $ext = Invoke-SidebarExtend $gp
    $log += $ext
    $rows = if ($ext -match 'per column|already') { $script:SidebarRowsExtended } else { 20 }
    $max = 46 + $rows * 51
    foreach ($h in $script:SidebarHooks) {
        $r = $gp.InstallHook([uint32]$h.At, $h.Orig, (Get-SidebarCave $h.Lea $max))
        $log += ('sidebar 0x{0:X}: {1} (max height {2})' -f $h.At, $r, $max)
    }
    return $log
}

# Random map dialog: its sliders show, and the generator uses, int fields of the generator object 0x805E10
# (FUN_0053ABB0 sets the sliders from them, FUN_0053A8C0 reads them back on OK). They are 0 when the game starts
# (players 2, Tiberium 1); RandMap.Sed is not read when the dialog opens. Setting the fields gives other start values,
# the player can still move every slider.
#   RegionSize "Klippen"/cliffs: size of the plateaus (bigger = fewer cliffs), Ruggedness "Berge": hills,
#   Accessibility "Zugänge": ramps, Tiberium "Tiberiummenge", TiberiumLayout "Tiberiumfelder": number of fields.
$script:RmgFields = [ordered]@{
    Ruggedness = 0x38; WaterAmount = 0x40; Players = 0x44; Tiberium = 0x48; TiberiumLayout = 0x4C; Vegetation = 0x50
    UrbanPresence = 0x54; Accessibility = 0x60; RegionSize = 0x64
}
$script:RmgObject = 0x805E10
$script:TerrainSliders = @{
    perfect = [ordered]@{ RegionSize = 100; Ruggedness = 0; Accessibility = 100; WaterAmount = 0; Vegetation = 10; UrbanPresence = 0 }
    flat    = [ordered]@{ RegionSize = 100; Ruggedness = 0; Accessibility = 100; WaterAmount = 5; Vegetation = 25; UrbanPresence = 10 }
    rugged  = [ordered]@{ RegionSize = 0; Ruggedness = 90; Accessibility = 30; WaterAmount = 30; Vegetation = 60; UrbanPresence = 30 }
}

# "Perfectly flat": every cell starts on level 4 (FUN_0053D950). "Making regions" (FUN_00533AD0) then splits every
# region with more cells than (RegionSize * 0.005 + 0.05) * width * height * 2 - even at RegionSize 100 the whole map
# is split two or three times - and FUN_00532580 puts each new part 4 levels above or below its neighbours: that is
# where the cliffs come from (flat maps had the levels 0, 4 and 8). Turning the JLE at 0x533CEE into a JMP marks every
# region as done without splitting it, so the map stays on one level. With WaterAmount 0 the water step
# (FUN_0053EE70, lakes in lowered ground) does not run either.
$script:NoSplitPatch = @{ At = 0x533CEE; Orig = [byte[]](0x7E, 0x0D); New = [byte[]](0xEB, 0x0D) }

# Visceroids: infantry killed by Tiberium becomes a visceroid when the map has [Basic] TiberiumDeathToVisceroid=yes
# (Scen+0x1D8F; random maps write yes). Both places that test it (infantry damage 0x4D3FEB, 0x5A38B6) jump over the
# creation when it is off; the patch makes these jumps unconditional (JZ rel32 -> NOP, JMP rel32: same target).
$script:VisceroidPatches = @(
    @{ At = 0x4D3FEB; Orig = [byte[]](0x0F, 0x84, 0xAB, 0x00, 0x00, 0x00); New = [byte[]](0x90, 0xE9, 0xAB, 0x00, 0x00, 0x00) }
    @{ At = 0x5A38B6; Orig = [byte[]](0x0F, 0x84, 0xA9, 0x00, 0x00, 0x00); New = [byte[]](0x90, 0xE9, 0xA9, 0x00, 0x00, 0x00) }
)

# Whole map visible: FUN_0051E0A0 (ECX = map 0x748348) reveals every cell for the player's house (PlayerPtr 0x7E2284)
# and sets its flag +0x114; the game calls it for the "reveal" crate, the trigger action and a defeated player.
# A hook on the frame counter of the main loop (INC [0x7E4924] at 0x50937D, once per game frame) calls it whenever
# the player's flag is clear - in the first frame of every battle, and again after a "shroud" crate.
$script:RevealHookAt = 0x50937D
$script:RevealHookOrig = [byte[]](0xFF, 0x05, 0x24, 0x49, 0x7E, 0x00)
function Get-RevealCave {
    return [byte[]]($script:RevealHookOrig + @(
            0x60,                                       # PUSHAD
            0xA1, 0x84, 0x22, 0x7E, 0x00,               # MOV EAX,[0x7E2284]      player's house
            0x85, 0xC0,                                 # TEST EAX,EAX
            0x74, 0x15,                                 # JZ done
            0x80, 0xB8, 0x14, 0x01, 0x00, 0x00, 0x00,   # CMP byte [EAX+0x114],0  map already revealed?
            0x75, 0x0C,                                 # JNZ done
            0xB9, 0x48, 0x83, 0x74, 0x00,               # MOV ECX,0x748348
            0xB8, 0xA0, 0xE0, 0x51, 0x00,               # MOV EAX,0x51E0A0
            0xFF, 0xD0,                                 # CALL EAX
            0x61))                                      # done: POPAD
}

# Writes start values of random map sliders. Checks first that the object looks like it should (players 2..8, every
# slider 0..100), otherwise writes nothing.
function Set-RmgSliders($gp, $values, [string]$name) {
    $players = $gp.ReadInt([uint32]($script:RmgObject + $script:RmgFields.Players))
    if ($players -lt 2 -or $players -gt 8) { return "RMG sliders ${name}: unexpected object (players $players)" }
    foreach ($k in $values.Keys) {
        $v = $gp.ReadInt([uint32]($script:RmgObject + $script:RmgFields[$k]))
        if ($v -lt 0 -or $v -gt 100) { return "RMG sliders ${name}: unexpected object ($k = $v)" }
    }
    foreach ($k in $values.Keys) { $gp.Write([uint32]($script:RmgObject + $script:RmgFields[$k]), [BitConverter]::GetBytes([int]$values[$k])) }
    return ("RMG sliders {0}: {1}" -f $name, (($values.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '))
}

# Random map generator, Tiberium (FUN_00546600): every Tiberium field gets
# (Tiberium slider * 30 + 2500) * players / fields cells, computed at 0x54661E .. 0x54662B
# (LEA EAX,[EAX+EAX*2]; LEA EDX,[EAX+EAX*4]; LEA EAX,[EDX+EDX*1+0x9C4]; IMUL EAX,[EBX+0x44]) - the same amount on a
# 50 x 50 map and on a 235 x 235 map. Then every player gets a field next to the start position of
# (distance term) + 500 cells (ADD EAX,0x1F4 at 0x5468AF). Both hooks multiply the amount by a factor that lives in
# memory next to the code.
$script:TibHookAt = 0x546624
$script:TibHookOrig = [byte[]](0x8D, 0x84, 0x12, 0xC4, 0x09, 0x00, 0x00)
$script:TibStartHookAt = 0x5468AF
$script:TibStartHookOrig = [byte[]](0x05, 0xF4, 0x01, 0x00, 0x00)

# Returns the result line; $script:TibFactorAddress is the address of the factor (tests change it between maps).
function Install-TiberiumFactor($gp, [int]$factor) {
    $var = $gp.Alloc(16)
    $gp.Write($var, [BitConverter]::GetBytes([int]$factor))
    $imul = [byte[]](@(0x0F, 0xAF, 0x05) + [BitConverter]::GetBytes([uint32]$var))      # IMUL EAX,dword ptr [var]
    $r1 = $gp.InstallHook([uint32]$script:TibHookAt, $script:TibHookOrig, [byte[]]($script:TibHookOrig + $imul))
    $r2 = $gp.InstallHook([uint32]$script:TibStartHookAt, $script:TibStartHookOrig, [byte[]]($script:TibStartHookOrig + $imul))
    if ($r1 -eq 'patched') { $script:TibFactorAddress = $var }
    return ('RMG Tiberium x{0}: fields {1}, start fields {2}' -f $factor, $r1, $r2)
}

# Computer opponents repair only one building at a time: BuildingClass AI (FUN_00435540) starts a repair only if the
# house flag +0x118 is clear, sets it and clears it again after a random delay. Skipping the test (JNZ at 0x4355D0)
# lets them repair every damaged building at once. Selling ([IQ] SellBack) and the money check (CreditReserve) stay
# rules values (see options.ps1).
$script:RepairPatch = @{ At = 0x4355D0; Orig = [byte[]](0x0F, 0x85, 0x4D, 0x01, 0x00, 0x00); New = [byte[]](0x90, 0x90, 0x90, 0x90, 0x90, 0x90) }

function ConvertTo-IntBytes([int[]]$values) {
    $b = New-Object byte[] ($values.Count * 4)
    for ($i = 0; $i -lt $values.Count; $i++) { [Array]::Copy([BitConverter]::GetBytes([int]$values[$i]), 0, $b, $i * 4, 4) }
    return , $b
}

# Applies the memory patches for these settings. Returns a list of result lines.
function Invoke-GamePatches($gp, $settings) {
    $log = New-Object System.Collections.Generic.List[string]
    # always: high resolutions must not crash the sidebar
    foreach ($l in (Invoke-SidebarFix $gp)) { $log.Add($l) }
    $size = [string]$settings['rmgsize']
    if ($size -and $script:RmgSizes.ContainsKey($size)) {
        $new = $script:RmgSizes[$size]
        $origMin = ConvertTo-IntBytes $script:RmgOriginal.Min; $origMax = ConvertTo-IntBytes $script:RmgOriginal.Max
        $newMin = ConvertTo-IntBytes $new.Min; $newMax = ConvertTo-IntBytes $new.Max
        foreach ($t in @(@('MinW', $origMin, $newMin), @('MinH', $origMin, $newMin), @('MaxW', $origMax, $newMax), @('MaxH', $origMax, $newMax))) {
            $r = $gp.VerifyPatch([uint32]$script:RmgTables[$t[0]], $t[1], $t[2])
            $log.Add("RMG $($t[0]): $r")
        }
    }
    $terrain = $script:TerrainSliders[[string]$settings['terrain']]
    if ($terrain) { $log.Add((Set-RmgSliders $gp $terrain ([string]$settings['terrain']))) }
    if ([string]$settings['terrain'] -eq 'perfect') {
        $log.Add(('RMG one level (no region split) 0x{0:X}: {1}' -f $script:NoSplitPatch.At, $gp.VerifyPatch([uint32]$script:NoSplitPatch.At, $script:NoSplitPatch.Orig, $script:NoSplitPatch.New)))
    }
    if ([string]$settings['visceroids'] -eq '0') {
        foreach ($v in $script:VisceroidPatches) { $log.Add(('no visceroids 0x{0:X}: {1}' -f $v.At, $gp.VerifyPatch([uint32]$v.At, $v.Orig, $v.New))) }
    }
    if ([string]$settings['reveal'] -eq '1') {
        $log.Add(('whole map visible 0x{0:X}: {1}' -f $script:RevealHookAt, $gp.InstallHook([uint32]$script:RevealHookAt, $script:RevealHookOrig, (Get-RevealCave))))
    }
    $tib = [string]$settings['tiberium']
    if ($tib -match '^\d+$' -and [int]$tib -gt 1) {
        # sliders "Tiberiummenge" and "Tiberiumfelder" to the right (they start at 1 and 0), then the factor
        $log.Add((Set-RmgSliders $gp ([ordered]@{ Tiberium = 100; TiberiumLayout = 100 }) 'Tiberium'))
        $log.Add((Install-TiberiumFactor $gp ([int]$tib)))
    }
    if ([string]$settings['ai'] -match '^[12]$') {
        $r = $gp.VerifyPatch([uint32]$script:RepairPatch.At, $script:RepairPatch.Orig, $script:RepairPatch.New)
        $log.Add("AI repair: $r")
    }
    return $log
}
