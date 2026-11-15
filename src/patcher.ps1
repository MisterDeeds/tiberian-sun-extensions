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
    return $log
}
