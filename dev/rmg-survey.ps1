# Generates random maps in the running game with several slider settings and saves each one for dev\rmg-stats.ps1.
#   .\dev\rmg-survey.ps1 [-Seed 4711] [-Start]
# Takes over the screen for a few minutes. Needs SUN.INI at the screen resolution (the clicks into the main menu use
# 2560 x 1440 positions); SUN.INI and RandMap.Sed are saved first and put back at the end.
# For the test only, the OK path of the random map dialog is patched to write the whole generated map to RandMap.Map
# in the game folder: the game writes it only in its debug mode (flag 0x7E490A; JZ at 0x53A620 -> NOP NOP), and its
# writer FUN_005DDFE0 leaves out IsoMapPack5 and OverlayPack for a random map outside debug mode (JZ at 0x5DE18B).
# (Writing it as a normal map instead, MOV DL,1 at 0x53A638 -> 0, crashes at 0x5E0BA7.)
# The seed is fixed in memory (+0x68 of the generator object 0x805E10; the dialog's store at 0x53A9CE is skipped).
# -Start: after the last map, starts the battle on it and checks that the game logic runs.
param([int]$Seed = 4711, [switch]$Start, [string]$Only = '')
. (Join-Path $PSScriptRoot '..\src\tslib.ps1')
. (Join-Path $PSScriptRoot '..\src\options.ps1')
. (Join-Path $PSScriptRoot '..\src\patcher.ps1')
$ErrorActionPreference = 'Stop'
$game = Find-TSGame
$out = Join-Path $PSScriptRoot '..\analysis\rmg'
New-Item -ItemType Directory -Force $out | Out-Null
$out = (Resolve-Path $out).Path

# name, sliders (control id = value), Tiberium factor
# 1021 "Klippen" (RegionSize), 1020 "Zugänge" (Accessibility), 1001 "Berge" (Ruggedness), 1016 "Tiberiummenge"
# (Tiberium), 1015 "Tiberiumfelder" (TiberiumLayout), 1008 "Gewässer" (WaterAmount), 1012 "Vegetation",
# 1013 "Stadtruinen" (UrbanPresence); 1003 players
$configs = @(
    @{ Name = 'default'; S = @{ 1021 = 50; 1020 = 50; 1001 = 40; 1016 = 60; 1015 = 60; 1008 = 30; 1012 = 60; 1013 = 30 }; F = 1 }
    @{ Name = 'region0'; S = @{ 1021 = 0; 1020 = 50; 1001 = 40; 1016 = 60; 1015 = 60; 1008 = 30; 1012 = 60; 1013 = 30 }; F = 1 }
    @{ Name = 'region100'; S = @{ 1021 = 100; 1020 = 50; 1001 = 40; 1016 = 60; 1015 = 60; 1008 = 30; 1012 = 60; 1013 = 30 }; F = 1 }
    @{ Name = 'flat'; S = @{ 1021 = 100; 1020 = 100; 1001 = 0; 1016 = 60; 1015 = 60; 1008 = 5; 1012 = 25; 1013 = 10 }; F = 1 }
    @{ Name = 'tib100'; S = @{ 1021 = 50; 1020 = 50; 1001 = 40; 1016 = 100; 1015 = 100; 1008 = 30; 1012 = 60; 1013 = 30 }; F = 1 }
    @{ Name = 'tibx2'; S = @{ 1021 = 50; 1020 = 50; 1001 = 40; 1016 = 60; 1015 = 60; 1008 = 30; 1012 = 60; 1013 = 30 }; F = 2 }
    @{ Name = 'tibx4'; S = @{ 1021 = 50; 1020 = 50; 1001 = 40; 1016 = 60; 1015 = 60; 1008 = 30; 1012 = 60; 1013 = 30 }; F = 4 }
    @{ Name = 'flat-tibx4'; S = @{ 1021 = 100; 1020 = 100; 1001 = 0; 1016 = 100; 1015 = 100; 1008 = 5; 1012 = 25; 1013 = 10 }; F = 4 }
    @{ Name = 'rugged'; S = @{ 1021 = 0; 1020 = 30; 1001 = 90; 1016 = 60; 1015 = 60; 1008 = 30; 1012 = 60; 1013 = 30 }; F = 1 }
    # 1.4 "perfectly flat": the sliders plus the patch that keeps the generator from splitting regions (Flat); P = players
    @{ Name = 'flat-water0'; S = @{ 1021 = 100; 1020 = 100; 1001 = 0; 1016 = 60; 1015 = 60; 1008 = 0; 1012 = 10; 1013 = 0 }; F = 1 }
    @{ Name = 'perfect'; S = @{ 1021 = 100; 1020 = 100; 1001 = 0; 1016 = 60; 1015 = 60; 1008 = 0; 1012 = 10; 1013 = 0 }; F = 1; Flat = $true }
    @{ Name = 'perfect-8p'; S = @{ 1021 = 100; 1020 = 100; 1001 = 0; 1016 = 60; 1015 = 60; 1008 = 0; 1012 = 10; 1013 = 0 }; F = 1; Flat = $true; P = 8 }
    @{ Name = 'perfect-tibx4'; S = @{ 1021 = 100; 1020 = 100; 1001 = 0; 1016 = 100; 1015 = 100; 1008 = 0; 1012 = 10; 1013 = 0 }; F = 4; Flat = $true }
)
if ($Only) { $configs = @($configs | Where-Object { ($Only -split ',') -contains $_.Name }) }

$sun = Join-Path $game 'SUN.INI'; $sed = Join-Path $game 'RandMap.Sed'; $rmap = Join-Path $game 'RandMap.Map'
$backup = Join-Path $PSScriptRoot '..\analysis\backup'
New-Item -ItemType Directory -Force $backup | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item -LiteralPath $sun -Destination (Join-Path $backup "SUN.INI.$stamp") -Force
$sedBackup = $null
if (Test-Path -LiteralPath $sed) { $sedBackup = Join-Path $backup "RandMap.Sed.$stamp"; Copy-Item -LiteralPath $sed -Destination $sedBackup -Force }
$resBefore = Get-GameResolution $game
Set-GameResolution $game 'native'
"saved SUN.INI ($resBefore) and RandMap.Sed; resolution now $(Get-GameResolution $game)"

function Find-Control([int]$procId, [int]$id) {
    foreach ($w in [TSExt.Win]::TopWindows($procId)) {
        foreach ($c in [TSExt.Win]::Children($w)) {
            if ([TSExt.Win]::GetDlgCtrlID($c) -eq $id -and [TSExt.Win]::IsWindowVisible($c)) { return $c }
        }
    }
    return [IntPtr]::Zero
}
function Send-DlgCommand([int]$procId, [int]$id) {
    $c = Find-Control $procId $id
    if ($c -eq [IntPtr]::Zero) { return $false }
    [TSExt.Win]::Command([TSExt.Win]::GetParent($c), $id); return $true
}
# WM_COMMAND to the dialog that holds control $owner (several dialogs are open at once and all have an OK button 1)
function Send-ToDialogOf([int]$procId, [int]$owner, [int]$id) {
    $c = Find-Control $procId $owner
    if ($c -eq [IntPtr]::Zero) { return $false }
    [TSExt.Win]::Command([TSExt.Win]::GetParent($c), $id); return $true
}
function Set-Slider([int]$procId, [int]$id, [int]$v) {
    $c = Find-Control $procId $id
    if ($c -eq [IntPtr]::Zero) { throw "slider $id not found" }
    [void][TSExt.Win]::SendMessageA($c, 0x0405, [IntPtr]1, [IntPtr]$v)
    [void][TSExt.Win]::SendMessageA([TSExt.Win]::GetParent($c), 0x0114, [IntPtr]8, $c)
}
function Set-Combo([int]$procId, [int]$id, [int]$i) {
    $c = Find-Control $procId $id
    if ($c -eq [IntPtr]::Zero) { throw "combo $id not found" }
    [void][TSExt.Win]::SendMessageA($c, 0x014E, [IntPtr]$i, [IntPtr]::Zero)
    [void][TSExt.Win]::SendMessageA([TSExt.Win]::GetParent($c), 0x0111, [IntPtr]($id -bor (1 -shl 16)), $c)
}
function Set-Text([int]$procId, [int]$id, [string]$t) {
    $c = Find-Control $procId $id
    if ($c -eq [IntPtr]::Zero) { throw "edit $id not found" }
    $buf = [Runtime.InteropServices.Marshal]::StringToHGlobalAnsi($t)
    [void][TSExt.Win]::SendMessageA($c, 0x000C, [IntPtr]::Zero, $buf)
    [Runtime.InteropServices.Marshal]::FreeHGlobal($buf)
}
function Wait-For([scriptblock]$cond, [int]$seconds) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $seconds) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}

Get-Process -Name game -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
if (Test-Path -LiteralPath $rmap) { Remove-Item -LiteralPath $rmap -Force }
$psi = New-Object System.Diagnostics.ProcessStartInfo (Join-Path $game 'Game.exe')
$psi.WorkingDirectory = $game; $psi.UseShellExecute = $true
$p = [System.Diagnostics.Process]::Start($psi)
$gp = $null
try {
    Start-Sleep -Seconds 10
    # the game that runs is the one with the game window (Steam may start it again as a new process)
    [void](Wait-For { $script:gw0 = Get-Process -Name game -ErrorAction SilentlyContinue | Where-Object { [TSExt.Win]::TopWindows($_.Id) | Where-Object { [TSExt.Win]::ClassName($_) -eq 'Tiberian Sun' } } | Select-Object -First 1; $null -ne $script:gw0 } 40)
    if ($script:gw0) { $p = $script:gw0 }
    $gp = New-Object TSExt.GameProcess $p
    if (-not (Wait-For { try { [void]$gp.ReadUInt(0x5F407C); $true } catch { $false } } 30)) { throw "the game's memory cannot be read (process $($p.Id), exited: $($p.HasExited))" }
    Invoke-GamePatches $gp @{ rmgsize = '2'; tiberium = '1' } | ForEach-Object { "  $_" }
    "  " + (Install-TiberiumFactor $gp 1)
    "  RandMap.Map write: " + $gp.VerifyPatch(0x53A620, [byte[]](0x74, 0x22), [byte[]](0x90, 0x90))
    "  with terrain and overlays: " + $gp.VerifyPatch(0x5DE18B, [byte[]](0x74, 0x2C), [byte[]](0x90, 0x90))   # the writer skips IsoMapPack5 / OverlayPack for a random map outside debug mode
    "  fixed seed: " + $gp.VerifyPatch(0x53A9CE, [byte[]](0x89, 0x46, 0x68), [byte[]](0x90, 0x90, 0x90))   # the dialog would store atoi(seed field)
    Start-Sleep -Seconds 9
    $gw = [TSExt.Win]::TopWindows($p.Id) | Where-Object { [TSExt.Win]::ClassName($_) -eq 'Tiberian Sun' } | Select-Object -First 1
    function Click-Game([int]$x, [int]$y) {
        # real clicks only into the game: bring it to the front first
        if ([TSExt.Win]::GetForegroundWindow() -ne $gw) { [TSExt.Win]::Focus($gw); Start-Sleep -Milliseconds 1500 }
        if ([TSExt.Win]::GetForegroundWindow() -ne $gw) { throw 'the game is not in front - no click' }
        [TSExt.Win]::RealClick($x, $y, $false)
    }
    # the game stops working while it is minimized or in the background: keep it in front
    function Keep-Front { if ([TSExt.Win]::IsIconic($gw) -or [TSExt.Win]::GetForegroundWindow() -ne $gw) { [TSExt.Win]::Focus($gw); Start-Sleep -Milliseconds 800 } }
    $reached = $false
    for ($try = 1; $try -le 3 -and -not $reached; $try++) {
        Click-Game 1430 720; Start-Sleep -Seconds 8      # Firestorm
        Click-Game 1279 828                              # Skirmish
        $reached = Wait-For { (Find-Control $p.Id 1450) -ne [IntPtr]::Zero } 12
        if (-not $reached) { "  menu try $try`: no skirmish dialog yet" }
    }
    if (-not $reached) {
        $bmp = [TSExt.Win]::Capture($gw); $bmp.Save((Join-Path $out 'menu-fail.png'), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        throw 'no skirmish dialog (control 1450), picture: analysis\rmg\menu-fail.png'
    }
    [void](Send-DlgCommand $p.Id 1450)
    Start-Sleep -Seconds 3
    foreach ($cfg in $configs) {
        if (-not (Wait-For { Keep-Front; (Find-Control $p.Id 1411) -ne [IntPtr]::Zero } 15)) { throw 'no map dialog (control 1411)' }
        [void](Send-DlgCommand $p.Id 1411)
        if (-not (Wait-For { (Find-Control $p.Id 1016) -ne [IntPtr]::Zero } 15)) { throw 'no random map dialog' }
        Start-Sleep -Milliseconds 800
        Set-Combo $p.Id 1000 0; Set-Combo $p.Id 1009 3; Set-Combo $p.Id 1011 3
        Set-Slider $p.Id 1003 $(if ($cfg.P) { $cfg.P } else { 4 })
        $gp.Write([uint32]$script:NoSplitPatch.At, $(if ($cfg.Flat) { $script:NoSplitPatch.New } else { $script:NoSplitPatch.Orig }))
        foreach ($k in $cfg.S.Keys) { Set-Slider $p.Id ([int]$k) ([int]$cfg.S[$k]) }
        $gp.Write(0x805E78, [BitConverter]::GetBytes([int]$Seed))   # seed (+0x68; the Firestorm dialog has no seed field)
        $gp.Write([uint32]$script:TibFactorAddress, [BitConverter]::GetBytes([int]$cfg.F))
        $gp.Write(0x805F0C, [BitConverter]::GetBytes([int]0))      # "no map generated yet" -> OK generates
        if (Test-Path -LiteralPath $rmap) { Remove-Item -LiteralPath $rmap -Force }
        $t0 = Get-Date
        Keep-Front
        [void](Send-ToDialogOf $p.Id 1016 1)
        $ok = Wait-For { Keep-Front; (Test-Path -LiteralPath $rmap) -and ((Get-Date) - (Get-Item -LiteralPath $rmap).LastWriteTime).TotalSeconds -gt 2 } 180
        $secs = [int]((Get-Date) - $t0).TotalSeconds
        if (-not $ok) { "{0,-12} no RandMap.Map after {1} s" -f $cfg.Name, $secs; continue }
        $dst = Join-Path $out ($cfg.Name + '.map')
        Copy-Item -LiteralPath $rmap -Destination $dst -Force
        "{0,-12} map saved after {1,3} s ({2:N0} bytes)" -f $cfg.Name, $secs, (Get-Item -LiteralPath $dst).Length
        Start-Sleep -Seconds 2
    }
    if ($Start) {
        Keep-Front; [void](Send-ToDialogOf $p.Id 1411 1); Start-Sleep -Seconds 3      # map selection OK
        Keep-Front; [void](Send-ToDialogOf $p.Id 1450 1); Start-Sleep -Seconds 30     # start the battle
        $f1 = $gp.ReadInt(0x7E4924); Start-Sleep -Seconds 5; $f2 = $gp.ReadInt(0x7E4924)
        "battle: frame {0} -> {1} ({2})" -f $f1, $f2, $(if ($f2 -gt $f1) { 'RUNS' } else { 'HANGS' })
        $bmp = [TSExt.Win]::Capture($gw); $bmp.Save((Join-Path $out 'battle.png'), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    }
}
finally {
    if ($gp) { $gp.Dispose() }
    if (-not $p.HasExited) { $p.Kill(); Start-Sleep -Seconds 2 }
    if (Test-Path -LiteralPath $rmap) { Remove-Item -LiteralPath $rmap -Force }
    Copy-Item -LiteralPath (Join-Path $backup "SUN.INI.$stamp") -Destination $sun -Force
    if ($sedBackup) { Copy-Item -LiteralPath $sedBackup -Destination $sed -Force } elseif (Test-Path -LiteralPath $sed) { Remove-Item -LiteralPath $sed -Force }
    "restored SUN.INI ($(Get-GameResolution $game)) and RandMap.Sed"
}
