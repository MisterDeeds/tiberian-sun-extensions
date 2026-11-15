# Builds all missions into a temporary folder and checks them without starting the game:
# houses, owners, object types, trigger/event/action/tag consistency, teams, buildable ground under every
# building of our houses, the campaign list and the mission chain. Exit code 1 on any error.
param([string]$OutDir = (Join-Path $env:TEMP 'tsext-test-missions'))
. (Join-Path $PSScriptRoot '..\src\tslib.ps1')
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
& (Join-Path $PSScriptRoot '..\src\build-campaigns.ps1') -OutDir $OutDir -Lang de | Out-Null
$fs = Open-TSFiles (Find-TSGame); $fs.UseLooseFiles = $false
$rules = [TSExt.IniFile]::Parse($fs.Read('RULES.INI')); $fsr = [TSExt.IniFile]::Parse($fs.Read('FIRESTRM.INI'))
$art = [TSExt.IniFile]::Parse($fs.Read('ART.INI')); $artFs = [TSExt.IniFile]::Parse($fs.Read('ARTFS.INI'))
$known = @{}
foreach ($l in 'BuildingTypes', 'VehicleTypes', 'InfantryTypes', 'AircraftTypes') { foreach ($i in $rules, $fsr) { if ($i[$l]) { foreach ($t in $i[$l].Values()) { $known[$t.ToUpper()] = $l } } } }
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$m) { $errors.Add($m); Write-Host "  FAIL $m" -ForegroundColor Red }
$theaters = @{}
$maps = Get-ChildItem -LiteralPath $OutDir -Filter 'TSX*.MAP'
foreach ($f in $maps) {
    $m = [TSExt.MapFile]::Load([IO.File]::ReadAllBytes($f.FullName))
    $ini = $m.Ini; $n = $f.Name
    if (-not $theaters.ContainsKey($m.TheaterName)) { $theaters[$m.TheaterName] = [TSExt.Theater]::Load($fs, $m.TheaterName) }
    $pl = New-Object TSExt.Placement $m, $theaters[$m.TheaterName]
    $houses = @($ini['Houses'].Values())
    $player = $ini.Get('Basic', 'Player')
    if ($houses -notcontains $player) { Fail "$n player house $player missing" }
    foreach ($h in $houses) { if (-not $ini[$h]) { Fail "$n house section [$h] missing" } }
    foreach ($sec in 'Structures', 'Units', 'Infantry') {
        foreach ($v in $ini[$sec].Values()) {
            $p = $v.Split(',')
            if ($houses -notcontains $p[0]) { Fail "$n $sec owner $($p[0]) not a house" }
            if (-not $known.ContainsKey($p[1].ToUpper())) { Fail "$n $sec type $($p[1]) unknown" }
        }
    }
    # buildings of our houses on flat, buildable ground of one height
    $ours = $houses | Where-Object { $_ -notin 'Neutral', 'Special' }
    $bad = 0
    foreach ($v in $ini['Structures'].Values()) {
        $p = $v.Split(','); if ($ours -notcontains $p[0]) { continue }
        $img = $fsr.Get($p[1], 'Image'); if (-not $img) { $img = $rules.Get($p[1], 'Image') }; if (-not $img) { $img = $p[1] }
        $fd = $artFs.Get($img, 'Foundation'); if (-not $fd) { $fd = $art.Get($img, 'Foundation') }; if (-not $fd) { $fd = '1x1' }
        $wh = $fd.ToLower().Split('x'); $x = [int]$p[3]; $y = [int]$p[4]
        $lvl = $null
        for ($dx = 0; $dx -lt [int]$wh[0]; $dx++) {
            for ($dy = 0; $dy -lt [int]$wh[1]; $dy++) {
                $c = $m.Get($x + $dx, $y + $dy)
                $tc = if ($c) { $theaters[$m.TheaterName].CellOf($c.Tile, $c.Sub) } else { $null }
                if (-not $c -or $tc.Ramp -ne 0 -or $tc.Land -notin 0, 11, 12, 13, 14) { $bad++; continue }
                if ($null -eq $lvl) { $lvl = $c.Level } elseif ($c.Level -ne $lvl) { $bad++ }
            }
        }
    }
    if ($bad -gt 0) { Fail "$n $bad building cells not on flat buildable ground" }
    # triggers
    $trig = $ini['Triggers']; $tagTargets = @{}
    foreach ($t in $ini['Tags'].Pairs) { $tagTargets[$t.Value.Split(',')[2]] = $t.Key }
    foreach ($t in $trig.Pairs) {
        $id = $t.Key
        $ev = $ini.Get('Events', $id); $ac = $ini.Get('Actions', $id)
        if (-not $ev -or -not $ac) { Fail "$n trigger $id without events/actions"; continue }
        $e = $ev.Split(','); if ([int]$e[0] * 3 + 1 -ne $e.Count) { Fail "$n trigger ${id}: event count $($e[0]) vs $($e.Count) fields" }
        $a = $ac.Split(','); if ([int]$a[0] * 8 + 1 -ne $a.Count) { Fail "$n trigger ${id}: action count $($a[0]) vs $($a.Count) fields" }
        if (-not $tagTargets.ContainsKey($id)) { Fail "$n trigger $id has no tag" }
        if ($houses -notcontains $t.Value.Split(',')[0]) { Fail "$n trigger $id house unknown" }
        # house parameters of win/lose/production actions
        for ($k = 0; $k -lt [int]$a[0]; $k++) {
            $type = [int]$a[1 + $k * 8]; $par = $a[3 + $k * 8]
            if ($type -in 1, 2, 3, 6, 13, 74) { if ([int]$par -ge $houses.Count) { Fail "$n trigger $id action ${type}: house index $par" } }
            if ($type -in 7, 80) { if (-not $ini[$par]) { Fail "$n trigger ${id}: team $par missing" } }
        }
    }
    foreach ($tid in $ini['TeamTypes'].Values()) {
        $tt = $ini[$tid]
        if (-not $ini[$tt.Get('TaskForce')]) { Fail "$n team ${tid}: task force missing" }
        if (-not $ini[$tt.Get('Script')]) { Fail "$n team ${tid}: script missing" }
        if ($houses -notcontains $tt.Get('House')) { Fail "$n team ${tid}: house missing" }
    }
    # round trip
    $again = [TSExt.MapFile]::Load($m.Save())
    if ($again.Cells.Count -ne $m.Cells.Count) { Fail "$n round trip cells $($again.Cells.Count) vs $($m.Cells.Count)" }
    '{0,-11} houses={1} structures={2,3} units={3,3} infantry={4,3} triggers={5,3} teams={6,2}  ok' -f $n, $houses.Count, $ini['Structures'].Pairs.Count, $ini['Units'].Pairs.Count, $ini['Infantry'].Pairs.Count, $trig.Pairs.Count, $ini['TeamTypes'].Pairs.Count
}
# campaign list and chain
$b = [TSExt.IniFile]::Parse([IO.File]::ReadAllBytes((Join-Path $OutDir 'BATTLEX.INI')))
foreach ($c in $b['Battles'].Values()) {
    $first = $b.Get($c, 'Scenario')
    $cur = $first; $steps = 0
    while ($cur -and $steps -lt 20) {
        $p = Join-Path $OutDir $cur
        if (-not (Test-Path -LiteralPath $p)) { Fail "campaign ${c}: $cur missing"; break }
        $ini = [TSExt.IniFile]::Parse([IO.File]::ReadAllBytes($p))
        $next = $ini.Get('Basic', 'NextScenario'); $end = $ini.Get('Basic', 'EndOfGame')
        if (-not $next -and $end -ne 'yes') { Fail "${cur}: no next mission and not EndOfGame" }
        $cur = $next; $steps++
    }
    "campaign {0,-8} {1} missions, addon {2}: {3}" -f $c, $steps, $b.Get($c, 'RequiredAddon'), $b.Get($c, 'Description')
}
if ($errors.Count -gt 0) { "$($errors.Count) errors"; exit 1 }
"all $($maps.Count) missions ok"
