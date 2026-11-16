# Game speed on a huge map: starts src\launcher.ps1 with the given settings file (default: the player's own
# settings.json), lists the controls of the skirmish dialog, sets the number of computer opponents (-AiPlayers, slider
# 1298) and the players of the random map (-MapPlayers, slider 1003), starts the battle and measures frames per second
# (frame counter 0x7E4924) every -Every seconds, with a picture every -ShotEvery seconds (analysis\shots).
#   .\dev\speed-test.ps1 [-Settings file] [-AiPlayers 7 -MapPlayers 8] [-Minutes 3] [-Every 15] [-KeepRunning]
# Takes over the screen. With -KeepRunning the game stays open for more steps (dev\game-probe.ps1 -Force), e.g. the
# in-game speed slider: 'focus;rkey:27;wait:2;dlgcmd:1313;wait:2;slider:1321:5;dlgcmd:1;wait:2;dlgcmd:1653'.
param([string]$Settings = (Join-Path $env:APPDATA 'TSExtensions\settings.json'), [int]$AiPlayers = 0, [int]$MapPlayers = 0,
    [double]$Minutes = 3, [int]$Every = 15, [int]$ShotEvery = 120, [switch]$KeepRunning)
. (Join-Path $PSScriptRoot '..\src\tslib.ps1')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$ErrorActionPreference = 'Stop'
$game = Find-TSGame
function Find-Control([int]$procId, [int]$id) {
    foreach ($w in [TSExt.Win]::TopWindows($procId)) { foreach ($c in [TSExt.Win]::Children($w)) { if ([TSExt.Win]::GetDlgCtrlID($c) -eq $id -and [TSExt.Win]::IsWindowVisible($c)) { return $c } } }
    return [IntPtr]::Zero
}
function Set-Slider([int]$procId, [int]$id, [int]$pos) {
    $c = Find-Control $procId $id; if ($c -eq [IntPtr]::Zero) { throw "no slider $id" }
    [void][TSExt.Win]::SendMessageA($c, 0x0405, [IntPtr]1, [IntPtr]$pos)                       # TBM_SETPOS
    [void][TSExt.Win]::SendMessageA([TSExt.Win]::GetParent($c), 0x0114, [IntPtr]8, $c)          # WM_HSCROLL, SB_ENDSCROLL
    return [int][TSExt.Win]::SendMessageA($c, 0x0400, [IntPtr]::Zero, [IntPtr]::Zero)
}
function Send-DlgCommand([int]$procId, [int]$id) { $c = Find-Control $procId $id; if ($c -eq [IntPtr]::Zero) { return $false }; [TSExt.Win]::Command([TSExt.Win]::GetParent($c), $id); return $true }
function Send-ToDialogOf([int]$procId, [int]$owner, [int]$id) { $c = Find-Control $procId $owner; if ($c -eq [IntPtr]::Zero) { return $false }; [TSExt.Win]::Command([TSExt.Win]::GetParent($c), $id); return $true }
function Wait-For([scriptblock]$cond, [int]$seconds) { $t = Get-Date; while (((Get-Date) - $t).TotalSeconds -lt $seconds) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 500 }; return $false }
# Picture of the screen (window captures of the game are black)
function Save-Screen([string]$name) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $gr = [System.Drawing.Graphics]::FromImage($bmp); $gr.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size); $gr.Dispose()
    $bmp.Save((Join-Path $script:shots $name), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
function Show-Dialog([int]$procId, [int]$owner) {
    $c = Find-Control $procId $owner; if ($c -eq [IntPtr]::Zero) { '  (dialog not found)'; return }
    foreach ($k in [TSExt.Win]::Children([TSExt.Win]::GetParent($c))) {
        if (-not [TSExt.Win]::IsWindowVisible($k)) { continue }
        $line = '  ' + [TSExt.Win]::Describe($k)
        if ([TSExt.Win]::ClassName($k) -like '*trackbar*') {
            $line += ' range {0}..{1} pos {2}' -f [int][TSExt.Win]::SendMessageA($k, 0x0401, [IntPtr]::Zero, [IntPtr]::Zero), [int][TSExt.Win]::SendMessageA($k, 0x0402, [IntPtr]::Zero, [IntPtr]::Zero), [int][TSExt.Win]::SendMessageA($k, 0x0400, [IntPtr]::Zero, [IntPtr]::Zero)
        }
        $line
    }
}

$sun = Join-Path $game 'SUN.INI'; $sed = Join-Path $game 'RandMap.Sed'
$backup = Join-Path $PSScriptRoot '..\analysis\backup'; New-Item -ItemType Directory -Force $backup | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item -LiteralPath $sun -Destination (Join-Path $backup "SUN.INI.$stamp") -Force
if (Test-Path -LiteralPath $sed) { Copy-Item -LiteralPath $sed -Destination (Join-Path $backup "RandMap.Sed.$stamp") -Force }
"backup: analysis\backup\SUN.INI.$stamp"
"SUN.INI GameSpeed before: " + ((Select-String -LiteralPath $sun -Pattern '^GameSpeed=(\d+)').Matches[0].Groups[1].Value)

$settingsDir = Join-Path ([IO.Path]::GetTempPath()) ('tsext-speedtest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $settingsDir | Out-Null
$set = Get-Content -LiteralPath $Settings -Raw -Encoding UTF8 | ConvertFrom-Json
$set.AutoUpdate = '0'
$set | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $settingsDir 'settings.json') -Encoding UTF8
'settings: ' + (($set.PSObject.Properties | Where-Object { $_.Name -notin 'AutoUpdate', 'LastVersion', 'UpdateTried' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ')
"settings dir: $settingsDir"

Get-Process -Name game -ErrorAction SilentlyContinue | Stop-Process -Force
$env:TSEXT_NO_UPDATE_CHECK = '1'
$launcher = Start-Process -FilePath powershell.exe -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot '..\src\launcher.ps1'), '-AutoStart', '-SettingsDir', $settingsDir)
"launcher pid $($launcher.Id)"
$p = $null; $gp = $null; $ok = $false
try {
    if (-not (Wait-For { Get-Process -Name game -ErrorAction SilentlyContinue } 60)) { throw 'the launcher did not start the game' }
    $p = Get-Process -Name game | Select-Object -First 1
    "game pid $($p.Id)"
    Start-Sleep -Seconds 19
    "SUN.INI GameSpeed while running: " + ((Select-String -LiteralPath $sun -Pattern '^GameSpeed=(\d+)').Matches[0].Groups[1].Value)
    $gp = New-Object TSExt.GameProcess $p
    $gw = [TSExt.Win]::TopWindows($p.Id) | Where-Object { [TSExt.Win]::ClassName($_) -eq 'Tiberian Sun' } | Select-Object -First 1
    function Click-Game([int]$x, [int]$y) {
        if ([TSExt.Win]::GetForegroundWindow() -ne $gw) { [TSExt.Win]::Focus($gw); Start-Sleep -Milliseconds 1500 }
        if ([TSExt.Win]::GetForegroundWindow() -ne $gw) { throw 'the game is not in front - no click' }
        [TSExt.Win]::RealClick($x, $y, $false)
    }
    function Keep-Front { if ([TSExt.Win]::IsIconic($gw) -or [TSExt.Win]::GetForegroundWindow() -ne $gw) { [TSExt.Win]::Focus($gw); Start-Sleep -Milliseconds 800 } }
    $reached = $false
    for ($try = 1; $try -le 3 -and -not $reached; $try++) {
        Click-Game 1430 720; Start-Sleep -Seconds 8
        Click-Game 1279 828
        $reached = Wait-For { (Find-Control $p.Id 1450) -ne [IntPtr]::Zero } 12
    }
    if (-not $reached) { throw 'no skirmish dialog' }
    Start-Sleep -Seconds 1
    'skirmish dialog:'; Show-Dialog $p.Id 1450
    if ($AiPlayers -gt 0) { "computer opponents (slider 1298): $(Set-Slider $p.Id 1298 $AiPlayers)" }
    [void](Send-DlgCommand $p.Id 1450)
    if (-not (Wait-For { (Find-Control $p.Id 1411) -ne [IntPtr]::Zero } 15)) { throw 'no map dialog' }
    [void](Send-DlgCommand $p.Id 1411)
    if (-not (Wait-For { (Find-Control $p.Id 1016) -ne [IntPtr]::Zero } 15)) { throw 'no random map dialog' }
    Start-Sleep -Seconds 1
    foreach ($id in 1009, 1011) { $c = Find-Control $p.Id $id; [void][TSExt.Win]::SendMessageA($c, 0x014E, [IntPtr]3, [IntPtr]::Zero); [void][TSExt.Win]::SendMessageA([TSExt.Win]::GetParent($c), 0x0111, [IntPtr]($id -bor (1 -shl 16)), $c) }
    if ($MapPlayers -gt 0) { "random map players (slider 1003): $(Set-Slider $p.Id 1003 $MapPlayers)" }
    Keep-Front; [void](Send-ToDialogOf $p.Id 1016 1568)     # preview
    [void](Wait-For { Keep-Front; $false } 30)
    "map size: {0} x {1}, players {2}" -f $gp.ReadInt(0x805E10 + 0x100), $gp.ReadInt(0x805E10 + 0x104), $gp.ReadInt(0x805E10 + 0x44)
    Keep-Front; [void](Send-ToDialogOf $p.Id 1016 1); Start-Sleep -Seconds 4       # random map OK
    Keep-Front; [void](Send-ToDialogOf $p.Id 1411 1); Start-Sleep -Seconds 4       # map selection OK
    'skirmish dialog before the start:'; Show-Dialog $p.Id 1450
    Keep-Front; [void](Send-ToDialogOf $p.Id 1450 1)                               # start
    [void](Wait-For { Keep-Front; $false } 40)
    $end = (Get-Date).AddMinutes($Minutes)
    $f0 = $gp.ReadInt(0x7E4924); $t0 = Get-Date; $prevF = $f0; $prevT = $t0
    $script:shots = Join-Path $PSScriptRoot '..\analysis\shots'; New-Item -ItemType Directory -Force $script:shots | Out-Null
    $nextShot = $t0
    'battle (GameSpeed {0}): frames per second every {1} s' -f $gp.ReadInt(0x7E4720), $Every
    while ((Get-Date) -lt $end -and -not $p.HasExited) {
        [void](Wait-For { Keep-Front; $false } $Every)
        $f = $gp.ReadInt(0x7E4924); $t = Get-Date
        '  t={0,4:0}s  {1,6:0.0} frames/s' -f ($t - $t0).TotalSeconds, (($f - $prevF) / ($t - $prevT).TotalSeconds)
        if ($f -eq $prevF) {
            '  frame counter stopped - responding: {0}, foreground: {1}' -f $p.Responding, [TSExt.Win]::Describe([TSExt.Win]::GetForegroundWindow())
            foreach ($w in [TSExt.Win]::TopWindows($p.Id)) { if ([TSExt.Win]::IsWindowVisible($w)) { '    W ' + [TSExt.Win]::Describe($w); foreach ($c in [TSExt.Win]::Children($w)) { '      c ' + [TSExt.Win]::Describe($c) } } }
            Save-Screen ('speed-stop-{0:000}s.png' -f ($t - $t0).TotalSeconds)
            break
        }
        $prevF = $f; $prevT = $t
        if ($ShotEvery -gt 0 -and $t -ge $nextShot) {
            Save-Screen ('speed-{0:000}s.png' -f ($t - $t0).TotalSeconds)
            $nextShot = $t.AddSeconds($ShotEvery)
        }
    }
    'average {0:0.0} frames/s over {1:0} s' -f (($prevF - $f0) / ($prevT - $t0).TotalSeconds), ($prevT - $t0).TotalSeconds
    $ok = $true
}
catch { "  FAIL $($_.Exception.Message)" }
finally {
    if ($gp) { $gp.Dispose() }
    if (-not ($KeepRunning -and $ok)) {
        if ($p -and -not $p.HasExited) { $p.Kill() }
        [void](Wait-For { -not (Test-Path -LiteralPath (Join-Path $game 'EXPAND99.MIX')) } 60); Start-Sleep -Seconds 2
        if ($launcher -and -not $launcher.HasExited) { $launcher.Kill() }
        if (Test-Path -LiteralPath (Join-Path $backup "RandMap.Sed.$stamp")) { Copy-Item -LiteralPath (Join-Path $backup "RandMap.Sed.$stamp") -Destination $sed -Force }
        if ((Get-FileHash -LiteralPath $sun).Hash -ne (Get-FileHash -LiteralPath (Join-Path $backup "SUN.INI.$stamp")).Hash) { Copy-Item -LiteralPath (Join-Path $backup "SUN.INI.$stamp") -Destination $sun -Force; '(SUN.INI put back from analysis\backup)' }
        Remove-Item -Recurse -Force $settingsDir -ErrorAction SilentlyContinue
    }
    else { "game left running (pid $($p.Id)), launcher pid $($launcher.Id), backup stamp $stamp" }
    Remove-Item Env:\TSEXT_NO_UPDATE_CHECK -ErrorAction SilentlyContinue
}
