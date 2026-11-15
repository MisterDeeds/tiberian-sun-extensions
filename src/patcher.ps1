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

function Invoke-SidebarFix($gp) {
    $log = @()
    foreach ($h in $script:SidebarHooks) {
        $r = $gp.InstallHook([uint32]$h.At, $h.Orig, (Get-SidebarCave $h.Lea $script:SidebarMaxHeight))
        $log += ('sidebar 0x{0:X}: {1}' -f $h.At, $r)
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
