# Starts one mission in the game and reports whether it runs (game logic advances) or hangs.
# The map is copied as TSXG01.MAP (first mission of the first extension campaign); the campaign list must be installed.
#   .\dev\test-mission.ps1 -Map .\analysis\variants\v1.MAP
# Needs native resolution in SUN.INI (click positions) and takes over the screen for about 90 seconds.
param([Parameter(Mandatory)][string]$Map, [int]$CampaignIndex = 0, [string]$As = 'TSXG01.MAP', [int]$Watch = 8)
. (Join-Path $PSScriptRoot '..\src\tslib.ps1')
. (Join-Path $PSScriptRoot '..\src\patcher.ps1')
$game = Find-TSGame
Get-Process -Name game -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Copy-Item -LiteralPath (Resolve-Path $Map) -Destination (Join-Path $game $As) -Force
$psi = New-Object System.Diagnostics.ProcessStartInfo (Join-Path $game 'Game.exe')
$psi.WorkingDirectory = $game; $psi.UseShellExecute = $true
$p = [System.Diagnostics.Process]::Start($psi)
$gp = $null
try {
    Start-Sleep -Seconds 10
    $gp = New-Object TSExt.GameProcess $p
    [void](Invoke-SidebarFix $gp)
    Start-Sleep -Seconds 9
    $gw = [TSExt.Win]::TopWindows($p.Id) | Where-Object { [TSExt.Win]::ClassName($_) -eq 'Tiberian Sun' } | Select-Object -First 1
    [TSExt.Win]::Focus($gw); Start-Sleep -Milliseconds 1500
    [TSExt.Win]::RealClick(1430, 720, $false); Start-Sleep -Seconds 8      # Firestorm
    [TSExt.Win]::RealClick(1280, 678, $false); Start-Sleep -Seconds 5      # New campaign
    $done = $false
    foreach ($w in [TSExt.Win]::TopWindows($p.Id)) {
        foreach ($c in [TSExt.Win]::Children($w)) {
            if ([TSExt.Win]::GetDlgCtrlID($c) -eq 1109 -and [TSExt.Win]::IsWindowVisible($c)) {
                [void][TSExt.Win]::SendMessageA($c, 0x0186, [IntPtr]$CampaignIndex, [IntPtr]::Zero)
                [TSExt.Win]::Command([TSExt.Win]::GetParent($c), 1); $done = $true
            }
        }
    }
    if (-not $done) { 'RESULT: no campaign dialog'; return }
    Start-Sleep -Seconds 15
    [TSExt.Win]::RealKey(27); Start-Sleep -Seconds 10
    $h = $gp.ReadUInt(0x7e2284)
    $a = $gp.Read(0x7E0000, 0x30000); $c1 = $gp.ReadInt($h + 0xb4)
    Start-Sleep -Seconds $Watch
    $b = $gp.Read(0x7E0000, 0x30000); $c2 = $gp.ReadInt($h + 0xb4)
    $n = 0; for ($i = 0; $i -lt $a.Length; $i += 4) { if ([BitConverter]::ToInt32($a, $i) -ne [BitConverter]::ToInt32($b, $i)) { $n++ } }
    $state = if ($n -gt 10) { 'RUNS' } else { 'HANGS' }
    "RESULT: $state (changed globals: $n, credits $c1 -> $c2)"
    $rule = $gp.ReadUInt(0x74c488)
    "rules: BuildSpeed={0} VeteranRatio={1} VeteranCombat={2} SurvivorRate={3}" -f $gp.ReadDouble($rule + 0xee8), $gp.ReadDouble($rule + 0x398), $gp.ReadDouble($rule + 0x3a0), $gp.ReadDouble($rule + 0xc98)
    if ($state -eq 'HANGS') { $gp.StackBytes = 64; $gp.SampleThreads() | Where-Object { $_ -match 'eip 00[4-6]' } | Select-Object -First 1 }
}
finally {
    if ($gp) { $gp.Dispose() }
    if (-not $p.HasExited -and -not $env:TSEXT_KEEP) { $p.Kill() }
}


