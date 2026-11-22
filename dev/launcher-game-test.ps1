# End-to-end test through the launcher: starts src\launcher.ps1 with its own settings (perfectly flat terrain,
# 4 x Tiberium, brutal opponents, huge maps, native resolution, whole map visible, no visceroids, build distance 10),
# checks the patches and rules values in the running game, the terrain sliders in the random map dialog, generates a
# map, starts a skirmish and lets it run, ends the game and checks that the launcher put SUN.INI and the game folder
# back (RandMap.Sed, the game's own file, stays as it was).
#   .\dev\launcher-game-test.ps1 [-Minutes 3]
# Takes over the screen (run it through dev\run-when-idle.ps1 while the PC is used). Pictures go to analysis\shots.
param([double]$Minutes = 3)
. (Join-Path $PSScriptRoot '..\src\tslib.ps1')
. (Join-Path $PSScriptRoot '..\src\options.ps1')
$ErrorActionPreference = 'Stop'
$game = Find-TSGame
$shots = Join-Path $PSScriptRoot '..\analysis\shots'
New-Item -ItemType Directory -Force $shots | Out-Null
$shots = (Resolve-Path $shots).Path
$errors = 0
function Check([string]$what, [bool]$ok) { if ($ok) { "  ok   $what" } else { "  FAIL $what"; $script:errors++ } }
function Find-Control([int]$procId, [int]$id) {
    foreach ($w in [TSExt.Win]::TopWindows($procId)) { foreach ($c in [TSExt.Win]::Children($w)) { if ([TSExt.Win]::GetDlgCtrlID($c) -eq $id -and [TSExt.Win]::IsWindowVisible($c)) { return $c } } }
    return [IntPtr]::Zero
}
function Send-DlgCommand([int]$procId, [int]$id) { $c = Find-Control $procId $id; if ($c -eq [IntPtr]::Zero) { return $false }; [TSExt.Win]::Command([TSExt.Win]::GetParent($c), $id); return $true }
function Send-ToDialogOf([int]$procId, [int]$owner, [int]$id) { $c = Find-Control $procId $owner; if ($c -eq [IntPtr]::Zero) { return $false }; [TSExt.Win]::Command([TSExt.Win]::GetParent($c), $id); return $true }
function Wait-For([scriptblock]$cond, [int]$seconds) { $t = Get-Date; while (((Get-Date) - $t).TotalSeconds -lt $seconds) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 500 }; return $false }
function Get-Hash([string]$f) { if (Test-Path -LiteralPath $f) { (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash } else { 'none' } }
# pictures from the screen (window captures of the game are black)
function Save-Screen($hwnd, [string]$name) {
    Add-Type -AssemblyName System.Drawing
    $r = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $r.Width, $r.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size); $g.Dispose()
    $bmp.Save((Join-Path $shots $name), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
Add-Type -AssemblyName System.Windows.Forms

$sun = Join-Path $game 'SUN.INI'; $sed = Join-Path $game 'RandMap.Sed'
$before = @{ sun = Get-Hash $sun; sed = Get-Hash $sed; mix = Test-Path -LiteralPath (Join-Path $game 'EXPAND99.MIX') }
$backup = Join-Path $PSScriptRoot '..\analysis\backup'; New-Item -ItemType Directory -Force $backup | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item -LiteralPath $sun -Destination (Join-Path $backup "SUN.INI.$stamp") -Force
if (Test-Path -LiteralPath $sed) { Copy-Item -LiteralPath $sed -Destination (Join-Path $backup "RandMap.Sed.$stamp") -Force }

$settingsDir = Join-Path ([IO.Path]::GetTempPath()) ('tsext-gametest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $settingsDir | Out-Null
$set = Get-DefaultSettings
$testSet = [ordered]@{ terrain = 'perfect'; tiberium = '4'; ai = '2'; rmgsize = '2'; resolution = 'native'; reveal = '1'; visceroids = '0'; buildradius = '10'; AutoUpdate = '0' }
foreach ($kv in $testSet.GetEnumerator()) { $set[$kv.Key] = $kv.Value }
([pscustomobject]$set) | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $settingsDir 'settings.json') -Encoding UTF8
"settings: " + (($testSet.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')

Get-Process -Name game -ErrorAction SilentlyContinue | Stop-Process -Force
$env:TSEXT_NO_UPDATE_CHECK = '1'
$launcher = Start-Process -FilePath powershell.exe -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot '..\src\launcher.ps1'), '-AutoStart', '-SettingsDir', $settingsDir)
$p = $null; $gp = $null
try {
    if (-not (Wait-For { Get-Process -Name game -ErrorAction SilentlyContinue } 60)) { throw 'the launcher did not start the game' }
    $p = Get-Process -Name game | Select-Object -First 1
    Check 'launcher wrote EXPAND99.MIX (rules: brutal opponents)' (Test-Path -LiteralPath (Join-Path $game 'EXPAND99.MIX'))
    Start-Sleep -Seconds 19
    $gp = New-Object TSExt.GameProcess $p
    Check ('repair patch in memory at 0x4355D0: {0}' -f (($gp.Read(0x4355D0, 6) | ForEach-Object { $_.ToString('X2') }) -join ' ')) (($gp.Read(0x4355D0, 6) | Where-Object { $_ -ne 0x90 }).Count -eq 0)
    Check ('Tiberium hooks in memory at 0x546624 / 0x5468AF: {0:X2} {1:X2}' -f $gp.ReadByte(0x546624), $gp.ReadByte(0x5468AF)) ($gp.ReadByte(0x546624) -eq 0xE9 -and $gp.ReadByte(0x5468AF) -eq 0xE9)
    $fv = @{}; foreach ($kv in @{ RegionSize = 0x64; Ruggedness = 0x38; Accessibility = 0x60; Tiberium = 0x48; TiberiumLayout = 0x4C; WaterAmount = 0x40; Vegetation = 0x50; UrbanPresence = 0x54 }.GetEnumerator()) { $fv[$kv.Key] = $gp.ReadInt(0x805E10 + $kv.Value) }
    Check ('random map slider fields in memory: RegionSize {0}, Ruggedness {1}, Accessibility {2}, Tiberium {3}, TiberiumLayout {4}, WaterAmount {5}, Vegetation {6}, UrbanPresence {7}' -f $fv.RegionSize, $fv.Ruggedness, $fv.Accessibility, $fv.Tiberium, $fv.TiberiumLayout, $fv.WaterAmount, $fv.Vegetation, $fv.UrbanPresence) ($fv.RegionSize -eq 100 -and $fv.Ruggedness -eq 0 -and $fv.Accessibility -eq 100 -and $fv.Tiberium -eq 100 -and $fv.TiberiumLayout -eq 100 -and $fv.WaterAmount -eq 0 -and $fv.UrbanPresence -eq 0)
    Check ('perfectly flat: region split jump at 0x533CEE is a JMP ({0:X2})' -f $gp.ReadByte(0x533CEE)) ($gp.ReadByte(0x533CEE) -eq 0xEB)
    Check ('no visceroids: 0x4D3FEB / 0x5A38B6 = {0} / {1}' -f (($gp.Read(0x4D3FEB, 2) | ForEach-Object { $_.ToString('X2') }) -join ' '), (($gp.Read(0x5A38B6, 2) | ForEach-Object { $_.ToString('X2') }) -join ' ')) ((($gp.Read(0x4D3FEB, 2) -join ',') -eq '144,233') -and (($gp.Read(0x5A38B6, 2) -join ',') -eq '144,233'))
    Check ('whole map visible: hook at 0x50937D ({0:X2})' -f $gp.ReadByte(0x50937D)) ($gp.ReadByte(0x50937D) -eq 0xE9)
    $mixBytes = $null
    try { $fsm = New-Object IO.FileStream (Join-Path $game 'EXPAND99.MIX'), 'Open', 'Read', 'ReadWrite'; $mixBytes = New-Object byte[] $fsm.Length; [void]$fsm.Read($mixBytes, 0, $mixBytes.Length); $fsm.Dispose() } catch { }
    if ($mixBytes) {
        $fsIni = [TSExt.IniFile]::Parse((New-Object TSExt.MixFile $mixBytes, 'EXPAND99.MIX').Read('FIRESTRM.INI'))
        Check ("build distance in EXPAND99.MIX: GAPOWR Adjacent {0}, NAHAND {1}" -f $fsIni.Get('GAPOWR', 'Adjacent'), $fsIni.Get('NAHAND', 'Adjacent')) ($fsIni.Get('GAPOWR', 'Adjacent') -eq '10' -and $fsIni.Get('NAHAND', 'Adjacent') -eq '10')
    }
    else { Check 'EXPAND99.MIX readable' $false }
    $gw = [TSExt.Win]::TopWindows($p.Id) | Where-Object { [TSExt.Win]::ClassName($_) -eq 'Tiberian Sun' } | Select-Object -First 1
    function Click-Game([int]$x, [int]$y) {
        if ([TSExt.Win]::GetForegroundWindow() -ne $gw) { [TSExt.Win]::Focus($gw); Start-Sleep -Milliseconds 1500 }
        if ([TSExt.Win]::GetForegroundWindow() -ne $gw) { throw 'the game is not in front - no click' }
        [TSExt.Win]::RealClick($x, $y, $false)
    }
    # the game stops working while it is minimized or in the background: keep it in front
    function Keep-Front { if ([TSExt.Win]::IsIconic($gw) -or [TSExt.Win]::GetForegroundWindow() -ne $gw) { [TSExt.Win]::Focus($gw); Start-Sleep -Milliseconds 800 } }
    $reached = $false
    for ($try = 1; $try -le 3 -and -not $reached; $try++) {
        Click-Game 1430 720; Start-Sleep -Seconds 8
        Click-Game 1279 828
        $reached = Wait-For { (Find-Control $p.Id 1450) -ne [IntPtr]::Zero } 12
    }
    if (-not $reached) { throw 'no skirmish dialog' }
    [void](Send-DlgCommand $p.Id 1450)
    if (-not (Wait-For { (Find-Control $p.Id 1411) -ne [IntPtr]::Zero } 15)) { throw 'no map dialog' }
    [void](Send-DlgCommand $p.Id 1411)
    if (-not (Wait-For { (Find-Control $p.Id 1016) -ne [IntPtr]::Zero } 15)) { throw 'no random map dialog' }
    Start-Sleep -Seconds 1
    $pos = @{}; foreach ($id in 1021, 1020, 1001, 1008, 1012, 1013) { $pos[$id] = [int][TSExt.Win]::SendMessageA((Find-Control $p.Id $id), 0x0400, [IntPtr]::Zero, [IntPtr]::Zero) }
    Check ("random map dialog shows the perfectly flat sliders: Klippen {0}, Zugänge {1}, Berge {2}, Gewässer {3}, Vegetation {4}, Ruinen {5}" -f $pos[1021], $pos[1020], $pos[1001], $pos[1008], $pos[1012], $pos[1013]) ($pos[1021] -eq 100 -and $pos[1001] -eq 0 -and $pos[1020] -eq 100 -and $pos[1008] -eq 0 -and $pos[1013] -eq 0)
    foreach ($id in 1009, 1011) { $c = Find-Control $p.Id $id; [void][TSExt.Win]::SendMessageA($c, 0x014E, [IntPtr]3, [IntPtr]::Zero); [void][TSExt.Win]::SendMessageA([TSExt.Win]::GetParent($c), 0x0111, [IntPtr]($id -bor (1 -shl 16)), $c) }
    Keep-Front; [void](Send-ToDialogOf $p.Id 1016 1568)     # preview
    [void](Wait-For { Keep-Front; $false } 30)
    Save-Screen $gw 'gametest-rmg.png'
    "  map size: {0} x {1}" -f $gp.ReadInt(0x805E10 + 0x100), $gp.ReadInt(0x805E10 + 0x104)
    Keep-Front; [void](Send-ToDialogOf $p.Id 1016 1); Start-Sleep -Seconds 4       # random map OK
    Keep-Front; [void](Send-ToDialogOf $p.Id 1411 1); Start-Sleep -Seconds 4       # map selection OK
    Keep-Front; [void](Send-ToDialogOf $p.Id 1450 1)                               # start
    [void](Wait-For { Keep-Front; $false } 40)
    $rule = $gp.ReadUInt(0x74C488)
    Check ("rules in the battle: SellBack {0}, CreditReserve {1}, ComputerBaseDefenseResponse {2}" -f $gp.ReadInt($rule + 0xC34), $gp.ReadInt($rule + 0xEF8), $gp.ReadInt($rule + 0x758)) ($gp.ReadInt($rule + 0xC34) -eq 99 -and $gp.ReadInt($rule + 0xEF8) -eq 0 -and $gp.ReadInt($rule + 0x758) -eq 6)
    $scen = $gp.ReadUInt(0x7E2438); $flags = $gp.ReadUInt($scen)   # [SpecialFlags] of the scenario (FUN_005FCC60 reads them into +0)
    "  special flags: TiberiumGrows={0} TiberiumSpreads={1} FogOfWar={2} IonStorms={3} Meteorites={4} Visceroids={5}; TiberiumDeathToVisceroid={6}; GrowthRate {7} min" -f (($flags -shr 5) -band 1), (($flags -shr 6) -band 1), (($flags -shr 11) -band 1), (($flags -shr 16) -band 1), (($flags -shr 15) -band 1), (($flags -shr 17) -band 1), $gp.ReadByte($scen + 0x1D8F), $gp.ReadDouble($rule + 0xDD8)
    $player = $gp.ReadUInt(0x7E2284)
    Check ('whole map visible: flag +0x114 of the player house 0x{0:X} = {1}' -f $player, $gp.ReadByte($player + 0x114)) ($player -ne 0 -and $gp.ReadByte($player + 0x114) -eq 1)
    Save-Screen $gw 'gametest-battle-0.png'
    $f1 = $gp.ReadInt(0x7E4924)
    $end = (Get-Date).AddMinutes($Minutes)
    $n = 0
    while ((Get-Date) -lt $end -and -not $p.HasExited) {
        [void](Wait-For { Keep-Front; $false } 30); $n++
        Save-Screen $gw ('gametest-battle-{0}.png' -f $n)
    }
    $f2 = $gp.ReadInt(0x7E4924)
    Check "battle runs: frame $f1 -> $f2 in $Minutes min" ($f2 -gt $f1 + 100)
}
catch { "  FAIL $($_.Exception.Message)"; $errors++ }
finally {
    if ($gp) { $gp.Dispose() }
    if ($p -and -not $p.HasExited) { $p.Kill() }
    # the launcher notices the end of the game and puts everything back
    $restored = Wait-For { -not (Test-Path -LiteralPath (Join-Path $settingsDir 'restore-resolution.txt')) -and -not (Test-Path -LiteralPath (Join-Path $game 'EXPAND99.MIX')) } 60
    Start-Sleep -Seconds 2
    Check 'launcher restored after the game: SUN.INI identical' ((Get-Hash $sun) -eq $before.sun)
    Check 'launcher restored after the game: no EXPAND99.MIX' ((Test-Path -LiteralPath (Join-Path $game 'EXPAND99.MIX')) -eq $before.mix)
    "  RandMap.Sed (the game writes it itself on OK in the random map dialog): $(if ((Get-Hash $sed) -eq $before.sed) { 'unchanged' } else { 'written by the game - put back from analysis\backup' })"
    if ($launcher -and -not $launcher.HasExited) { $launcher.Kill() }
    if (Test-Path -LiteralPath (Join-Path $backup "RandMap.Sed.$stamp")) { Copy-Item -LiteralPath (Join-Path $backup "RandMap.Sed.$stamp") -Destination $sed -Force }
    elseif ($before.sed -eq 'none' -and (Test-Path -LiteralPath $sed)) { Remove-Item -LiteralPath $sed -Force }
    if (-not $restored) {
        Copy-Item -LiteralPath (Join-Path $backup "SUN.INI.$stamp") -Destination $sun -Force
        '  (restored SUN.INI from analysis\backup)'
    }
    Remove-Item -Recurse -Force $settingsDir -ErrorAction SilentlyContinue
    Remove-Item Env:\TSEXT_NO_UPDATE_CHECK -ErrorAction SilentlyContinue
}
if ($errors) { "$errors errors"; exit 1 } else { 'all game checks ok' }
