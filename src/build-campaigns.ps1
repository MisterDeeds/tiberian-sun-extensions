<#
.SYNOPSIS
  Builds the campaigns and challenges of the Tiberian Sun Extensions from the official multiplayer maps of your
  own installation (missions.json): terrain from the original map, plus houses, bases, units and triggers.

.DESCRIPTION
  Writes the mission maps (TSX*.MAP) and the campaign list (BATTLEX.INI) to -OutDir. The game lists every
  BATTLE*.INI of its folder in "Choose campaign" (BATTLE.INI: "Additional files that begin with BATTLE will augment
  this list"), so the installer only has to copy these files into the game folder.
  Texts in German on a German Windows, otherwise English (override: -Lang de|en or $env:TSEXT_LANG).
#>
param(
    [string]$OutDir = (Join-Path $PSScriptRoot 'missions'),
    [string]$Lang = '',
    [string]$GameDir = '',
    [string[]]$Only = @()
)
. (Join-Path $PSScriptRoot 'tslib.ps1')
$ErrorActionPreference = 'Stop'

if (-not $Lang) { $Lang = if ($env:TSEXT_LANG) { $env:TSEXT_LANG } elseif ((Get-UICulture).TwoLetterISOLanguageName -eq 'de') { 'de' } else { 'en' } }
if (-not $GameDir) { $GameDir = Find-TSGame }
if (-not $GameDir) { throw 'Tiberian Sun (Steam) not found.' }
$fs = Open-TSFiles $GameDir
$fs.UseLooseFiles = $false          # always build from the original files, never from our own loose files
New-Item -ItemType Directory -Force $OutDir | Out-Null

$catalog = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'missions.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# --- rules and art of the installation (effective values: Firestorm overrides Tiberian Sun) -------------------------
$rules = [TSExt.IniFile]::Parse($fs.Read('RULES.INI'))
$fsRules = [TSExt.IniFile]::Parse($fs.Read('FIRESTRM.INI'))
$art = [TSExt.IniFile]::Parse($fs.Read('ART.INI'))
$artFs = [TSExt.IniFile]::Parse($fs.Read('ARTFS.INI'))
function Get-RuleValue([string]$section, [string]$key) {
    $v = $fsRules.Get($section, $key); if ($null -eq $v) { $v = $rules.Get($section, $key) }; return $v
}
function Get-Foundation([string]$type) {
    $img = Get-RuleValue $type 'Image'; if (-not $img) { $img = $type }
    $f = $artFs.Get($img, 'Foundation'); if (-not $f) { $f = $art.Get($img, 'Foundation') }
    if (-not $f) { $f = '1x1' }
    $p = $f.ToLower().Split('x'); return @([int]$p[0], [int]$p[1])
}
function Get-Power([string]$type) { $p = Get-RuleValue $type 'Power'; if ($p) { return [int]$p } else { return 0 } }
$fsOnlyTypes = @{}
foreach ($list in 'BuildingTypes', 'VehicleTypes', 'InfantryTypes', 'AircraftTypes') {
    if ($fsRules[$list]) { foreach ($t in $fsRules[$list].Values()) { $fsOnlyTypes[$t.ToUpper()] = $true } }
}

# --- bases, garrisons and attack waves per side -------------------------------------------------------------------
$Bases = @{
    'GDI' = @{
        small  = @('GACNST', 'GAPOWR', 'PROC', 'GAPILE', 'GAPOWR', 'GAWEAP')
        medium = @('GACNST', 'GAPOWR', 'PROC', 'GAPILE', 'GAPOWR', 'GAWEAP', 'GARADR', 'GAPOWR', 'GAHPAD', 'GADEPT')
        large  = @('GACNST', 'GAPOWR', 'PROC', 'GAPILE', 'GAPOWR', 'GAWEAP', 'GARADR', 'GAPOWR', 'GAHPAD', 'GADEPT', 'GAPOWR', 'GATECH', 'PROC', 'GAPOWR')
    }
    'Nod' = @{
        small  = @('GACNST', 'NAPOWR', 'PROC', 'NAHAND', 'NAPOWR', 'NAWEAP')
        medium = @('GACNST', 'NAPOWR', 'PROC', 'NAHAND', 'NAPOWR', 'NAWEAP', 'NARADR', 'NAAPWR', 'NAHPAD', 'NATECH')
        large  = @('GACNST', 'NAPOWR', 'PROC', 'NAHAND', 'NAPOWR', 'NAWEAP', 'NARADR', 'NAAPWR', 'NAHPAD', 'NATECH', 'NAAPWR', 'NATMPL', 'PROC', 'NAAPWR')
    }
}
$Defenses = @{ 'GDI' = @('GACTWR:GAVULC', 'GACTWR:GAROCK'); 'Nod' = @('NALASR', 'NALASR', 'NASAM') }
$DefenseCount = @{ small = 2; medium = 5; large = 9 }
$Garrison = @{
    'GDI' = @{ small = '4,E1|2,SMECH'; medium = '6,E1|2,E2|3,SMECH|2,MMCH'; large = '8,E1|4,E2|2,JUMPJET|4,MMCH|2,HVR|2,SMECH' }
    'Nod' = @{ small = '4,E1|2,BGGY'; medium = '6,E1|2,E3|3,TTNK|2,BGGY'; large = '8,E1|4,E3|4,CYBORG|4,TTNK|2,ART2|2,STNK' }
}
$Waves = @{
    'GDI' = @('3,E1|2,E2|2,SMECH', '4,E1|2,E2|3,SMECH|2,MMCH', '4,E2|2,JUMPJET|3,MMCH|2,HVR|2,SMECH', '4,JUMPJET|4,MMCH|2,SONIC|2,HVR|2,SMECH')
    'Nod' = @('3,E1|2,E3|2,BGGY', '4,E1|2,E3|2,CYBORG|2,BIKE|2,TTNK', '4,E3|4,CYBORG|3,TTNK|2,ART2|2,STNK', '6,CYBORG|1,CYC2|4,TTNK|3,STNK|2,ART2')
}
$Colors = @{ 'GDI' = @('Gold', 'Grey', 'LightBlue', 'Green'); 'Nod' = @('DarkRed', 'Orange', 'Purple', 'DarkBlue', 'Red', 'Green') }
$Harvester = 'HARV'

function Get-Text($obj) { if ($obj.$Lang) { return [string]$obj.$Lang } else { return [string]$obj.en } }

# Splits a briefing into lines of at most 70 characters (the @@ paragraph marks stay).
function Split-Briefing([string]$text) {
    $lines = New-Object System.Collections.Generic.List[string]
    $cur = ''
    foreach ($w in ($text -split ' ')) {
        if ($cur.Length -gt 0 -and ($cur.Length + 1 + $w.Length) -gt 70) { $lines.Add($cur); $cur = $w }
        elseif ($cur.Length -gt 0) { $cur += ' ' + $w } else { $cur = $w }
    }
    if ($cur) { $lines.Add($cur) }
    return $lines
}

function Get-Units([string]$spec) {
    $r = @()
    if (-not $spec) { return $r }
    foreach ($part in $spec.Split('|')) {
        $p = $part.Split(','); $n = [int]$p[0]; $t = $p[1].Trim().ToUpper()
        for ($i = 0; $i -lt $n; $i++) { $r += $t }
    }
    return $r
}

function Test-Infantry([string]$type) { return $rules['InfantryTypes'].Values() -contains $type -or ($fsRules['InfantryTypes'] -and $fsRules['InfantryTypes'].Values() -contains $type) }

# Places units of a list around a cell; infantry three per cell.
function Add-Force($mb, $pl, [string]$house, [string]$spec, [int]$cx, [int]$cy, [string]$mission, [int]$veteran) {
    $sub = 2
    $ix = -1; $iy = -1
    foreach ($t in (Get-Units $spec)) {
        $x = 0; $y = 0
        if (Test-Infantry $t) {
            if ($ix -lt 0 -or $sub -gt 4) {
                if (-not $pl.FindFreeCell($cx, $cy, 25, [ref]$x, [ref]$y)) { continue }
                $pl.Block($x, $y); $ix = $x; $iy = $y; $sub = 2
            }
            $mb.AddInfantry($house, $t, $ix, $iy, $sub, $mission, $null, $veteran); $sub++
        }
        else {
            if (-not $pl.FindFreeCell($cx, $cy, 25, [ref]$x, [ref]$y)) { continue }
            $pl.Block($x, $y)
            $mb.AddUnit($house, $t, $x, $y, 64 * (Get-Random -Maximum 4), $mission, $null, $veteran)
        }
    }
}

# Builds a base around a start point; returns the list of placed buildings (type, x, y).
function Add-Base($mb, $pl, [string]$house, [string]$side, [string]$size, [int]$cx, [int]$cy, [bool]$aiNodes, [string[]]$extra, [int]$towardX, [int]$towardY) {
    $placed = @()
    $types = @($Bases[$side][$size]) + @($extra | Where-Object { $_ })
    # enough power for everything
    $sum = 0; foreach ($t in $types) { $sum += (Get-Power $t) }
    $plant = if ($side -eq 'GDI') { 'GAPOWR' } else { 'NAPOWR' }
    while ($sum -lt 50) { $types += $plant; $sum += (Get-Power $plant) }
    $first = $true
    foreach ($t in $types) {
        $f = Get-Foundation $t; $x = 0; $y = 0
        $radius = if ($first) { 10 } else { 22 }
        if (-not $pl.FindSpot($cx - [int]($f[0] / 2), $cy - [int]($f[1] / 2), $f[0], $f[1], 1, $radius, [ref]$x, [ref]$y)) {
            if (-not $pl.FindSpot($cx, $cy, $f[0], $f[1], 0, $radius + 8, [ref]$x, [ref]$y)) { Write-Verbose "no room for $t"; continue }
        }
        $pl.Occupy($x, $y, $f[0], $f[1])
        $mb.AddStructure($house, $t, $x, $y, 0, $null, $false, $aiNodes, $null)
        if ($aiNodes) { $mb.AddBaseNode($house, $t, $x, $y) }
        $placed += [pscustomobject]@{ Type = $t; X = $x; Y = $y; W = $f[0]; H = $f[1]; Index = $mb.Map.Ini['Structures'].Pairs.Count - 1 }
        if ($t -eq 'PROC') {
            $hx = 0; $hy = 0
            if ($pl.FindFreeCell($x + $f[0], $y + $f[1], 8, [ref]$hx, [ref]$hy)) { $pl.Block($hx, $hy); $mb.AddUnit($house, $Harvester, $hx, $hy, 0, 'Harvest', $null, 0) }
        }
        if ($first) { $cx = $x + 1; $cy = $y + 1; $first = $false }
    }
    # defenses towards the given point (the player), at 7..12 cells from the base center
    if ($DefenseCount.ContainsKey($size)) {
        $n = $DefenseCount[$size]; $defs = $Defenses[$side]
        $ang = [math]::Atan2($towardY - $cy, $towardX - $cx)
        for ($i = 0; $i -lt $n; $i++) {
            $spread = (($i % 5) - 2) * 0.35 + ([math]::Floor($i / 5)) * 0.15
            $r = 8 + ($i % 3) * 2
            $dx = [int]($cx + [math]::Cos($ang + $spread) * $r); $dy = [int]($cy + [math]::Sin($ang + $spread) * $r)
            $x = 0; $y = 0
            $def = $defs[$i % $defs.Count].Split(':')
            $f = Get-Foundation $def[0]
            if (-not $pl.FindSpot($dx, $dy, $f[0], $f[1], 0, 5, [ref]$x, [ref]$y)) { continue }
            $pl.Occupy($x, $y, $f[0], $f[1])
            $up = if ($def.Count -gt 1) { $def[1] } else { $null }
            $mb.AddStructure($house, $def[0], $x, $y, 0, $null, $false, $aiNodes, $up)
            if ($aiNodes) { $mb.AddBaseNode($house, $def[0], $x, $y) }
        }
    }
    return $placed
}

function Get-StartPoints($map, $pl) {
    $r = @()
    foreach ($w in $map.Waypoints()) {
        if ($w.Key -ge 8) { continue }
        $x = $w.Value % 1000; $y = [int][math]::Floor($w.Value / 1000)
        if ($pl.InLocal($x, $y)) { $r += [pscustomobject]@{ No = $w.Key; X = $x; Y = $y } }
    }
    return $r
}

$theaters = @{}
$built = @()
foreach ($camp in $catalog.campaigns) {
    $missions = @($camp.missions)
    for ($mi = 0; $mi -lt $missions.Count; $mi++) {
        $ms = $missions[$mi]
        if ($Only.Count -gt 0 -and $Only -notcontains $ms.file) { continue }
        $src = $fs.Read("$($ms.map).MAP")
        if (-not $src) { Write-Warning "map $($ms.map) not found - $($ms.file) skipped"; continue }
        $map = [TSExt.MapFile]::Load($src)
        if (-not $theaters.ContainsKey($map.TheaterName)) { $theaters[$map.TheaterName] = [TSExt.Theater]::Load($fs, $map.TheaterName) }
        $pl = New-Object TSExt.Placement $map, $theaters[$map.TheaterName]
        $mb = New-Object TSExt.MissionBuilder $map
        $seed = [math]::Abs($ms.file.GetHashCode()); $null = Get-Random -SetSeed $seed

        $side = [string]$ms.side; $enemySide = if ($side -eq 'GDI') { 'Nod' } else { 'GDI' }
        $starts = @(Get-StartPoints $map $pl)
        $enemies = @($ms.enemies); $allies = @($ms.allies)
        if ($starts.Count -lt 1 + $enemies.Count + $allies.Count) { Write-Warning "$($ms.file): only $($starts.Count) start points"; }
        $me = $starts[0]
        $rest = @($starts | Select-Object -Skip 1 | Sort-Object { - ([math]::Pow($_.X - $me.X, 2) + [math]::Pow($_.Y - $me.Y, 2)) })
        $enemyStarts = @($rest | Select-Object -First $enemies.Count)
        $allyStarts = @($rest | Select-Object -Skip $enemies.Count | Sort-Object { ([math]::Pow($_.X - $me.X, 2) + [math]::Pow($_.Y - $me.Y, 2)) } | Select-Object -First $allies.Count)

        # houses: player first, then allies, enemies, neutral, special
        $playerHouse = $side
        $allyHouses = @(); for ($i = 0; $i -lt $allies.Count; $i++) { $allyHouses += ($side + 'A' + ($i + 1)) }
        $enemyHouses = @(); for ($i = 0; $i -lt $enemies.Count; $i++) { $enemyHouses += $(if ($i -eq 0) { $enemySide } else { $enemySide + ($i + 1) }) }
        $friends = (@($playerHouse) + $allyHouses + @('Neutral')) -join ','
        $foes = (@($enemyHouses) + @('Neutral')) -join ','
        $credits = [int]$ms.player.credits
        [void]$mb.AddHouse($playerHouse, $side, $Colors[$side][0], $friends, $credits, 0, $true, 10, 'West')
        for ($i = 0; $i -lt $allyHouses.Count; $i++) { [void]$mb.AddHouse($allyHouses[$i], $side, $Colors[$side][1 + $i % 3], $friends, 200, 5, $false, 10, 'West') }
        for ($i = 0; $i -lt $enemyHouses.Count; $i++) { [void]$mb.AddHouse($enemyHouses[$i], $enemySide, $Colors[$enemySide][$i % $Colors[$enemySide].Count], $foes, 300, 5, $false, 10, 'North') }
        [void]$mb.AddHouse('Neutral', 'Civilian', 'Grey', 'Neutral', 0, 0, $false, 10, 'North')
        [void]$mb.AddHouse('Special', 'Mutant', 'Grey', 'Special', 0, 0, $false, 10, 'North')
        $pIdx = $mb.HouseIndex($playerHouse)

        # player
        $playerExtra = @(); if ($ms.protect) { $playerExtra += [string]$ms.protect }
        $protectTag = $null
        $playerBase = @()
        if ($ms.player.base -ne 'none') { $playerBase = Add-Base $mb $pl $playerHouse $side ([string]$ms.player.base) $me.X $me.Y $false $playerExtra $map.Width $map.Width }
        Add-Force $mb $pl $playerHouse ([string]$ms.player.units) ($me.X + 2) ($me.Y + 2) 'Guard' 0
        $null = $mb.AddWaypoint($me.X, $me.Y)
        $map.Ini['Waypoints'].Set('98', [TSExt.MapFile]::CellNumber($me.X, $me.Y).ToString())

        # allies
        for ($i = 0; $i -lt $allyHouses.Count; $i++) {
            $s = $allyStarts[$i]; if (-not $s) { break }
            $null = Add-Base $mb $pl $allyHouses[$i] $side ([string]$allies[$i].strength) $s.X $s.Y $true @() $me.X $me.Y
            Add-Force $mb $pl $allyHouses[$i] $Garrison[$side][[string]$allies[$i].strength] $s.X $s.Y 'Area Guard' 0
            $hi = $mb.HouseIndex($allyHouses[$i])
            $mb.AddTrigger("Ally $($i+1) AI", $allyHouses[$i], 0, @([TSExt.MissionBuilder]::Ev(47, 2)),
                @([TSExt.MissionBuilder]::Act(3, $hi), [TSExt.MissionBuilder]::Act(74, $hi), [TSExt.MissionBuilder]::Act(13, $hi), [TSExt.MissionBuilder]::Act(30, 1))) | Out-Null
        }

        # enemies
        $targetTagged = $false
        $winEvents = @()
        for ($i = 0; $i -lt $enemyHouses.Count; $i++) {
            $s = $enemyStarts[$i]; if (-not $s) { break }
            $h = $enemyHouses[$i]; $hi = $mb.HouseIndex($h); $strength = [string]$enemies[$i].strength
            $wp = $mb.AddWaypoint($s.X, $s.Y)
            if ($strength -ne 'waves') {
                $extra = @(); if ($ms.target -and -not $targetTagged) { $extra += [string]$ms.target }
                $placed = Add-Base $mb $pl $h $enemySide $strength $s.X $s.Y $true $extra $me.X $me.Y
                Add-Force $mb $pl $h $Garrison[$enemySide][$strength] $s.X $s.Y 'Area Guard' 0
                $mb.AddTrigger("$h AI", $h, 0, @([TSExt.MissionBuilder]::Ev(47, 3)),
                    @([TSExt.MissionBuilder]::Act(3, $hi), [TSExt.MissionBuilder]::Act(74, $hi), [TSExt.MissionBuilder]::Act(13, $hi), [TSExt.MissionBuilder]::Act(30, 1))) | Out-Null
                $winEvents += [TSExt.MissionBuilder]::Ev(10, $hi)
                if ($ms.target -and -not $targetTagged) {
                    $tgt = $placed | Where-Object { $_.Type -eq [string]$ms.target } | Select-Object -First 1
                    if ($tgt) {
                        $tid = $mb.AddTrigger('Target destroyed', $playerHouse, 0, @([TSExt.MissionBuilder]::Ev(48, 0)), @([TSExt.MissionBuilder]::Act(1, $pIdx)))
                        $mb.AttachTag($tgt.Index, $mb.TagOf($tid))
                        $targetTagged = $true
                    }
                }
            }
            # attack waves: four tiers, one set per difficulty (Easy / Normal / Hard)
            $tierStart = @(0, 360, 720, 1200)
            $interval = if ($strength -eq 'waves') { @(150, 110, 75) } else { @(300, 220, 160) }
            $script = $mb.AddScript("Hunt", [string[]]@('0,2', '11,14'))
            for ($t = 0; $t -lt 4; $t++) {
                $tf = $mb.AddTaskForce("$h wave $($t+1)", [string[]]($Waves[$enemySide][$t].Split('|')))
                $team = $mb.AddTeam("$h wave $($t+1)", $h, $tf, $script, $wp, $(if ($t -ge 2) { 2 } else { 1 }), $false, 0, 5)
                for ($d = 0; $d -lt 3; $d++) {
                    if ($d -eq 0 -and $t -eq 3) { continue }   # no last tier on Easy
                    $evs = @([TSExt.MissionBuilder]::Ev(13, $interval[$d] + 30 * $t))
                    if ($tierStart[$t] -gt 0) { $evs += [TSExt.MissionBuilder]::Ev(47, $tierStart[$t]) }
                    $mb.AddTriggerDiff("$h wave $($t+1) d$d", $h, 2, $evs, @([TSExt.MissionBuilder]::ActTeamAt(80, $team, $wp)), $d) | Out-Null
                }
            }
        }

        # victory and defeat
        $minutes = if ($ms.minutes) { [int]$ms.minutes } else { 0 }
        switch ([string]$ms.type) {
            'survival' {
                $mb.AddTrigger('Survived', $playerHouse, 0, @([TSExt.MissionBuilder]::Ev(47, $minutes * 60)), @([TSExt.MissionBuilder]::Act(1, $pIdx))) | Out-Null
            }
            'defense' {
                $mb.AddTrigger('Held out', $playerHouse, 0, @([TSExt.MissionBuilder]::Ev(47, $minutes * 60)), @([TSExt.MissionBuilder]::Act(1, $pIdx))) | Out-Null
                $prot = $playerBase | Where-Object { $_.Type -eq [string]$ms.protect } | Select-Object -First 1
                if ($prot) {
                    $tid = $mb.AddTrigger('Protected building lost', $playerHouse, 0, @([TSExt.MissionBuilder]::Ev(48, 0)), @([TSExt.MissionBuilder]::Act(2, $pIdx)))
                    $mb.AttachTag($prot.Index, $mb.TagOf($tid))
                }
            }
            'economy' {
                $mb.AddTrigger('Rich', $playerHouse, 0, @([TSExt.MissionBuilder]::Ev(12, [int]$ms.goalCredits)), @([TSExt.MissionBuilder]::Act(1, $pIdx))) | Out-Null
                if ($winEvents.Count -gt 0) { $mb.AddTrigger('Enemies destroyed', $playerHouse, 0, $winEvents, @([TSExt.MissionBuilder]::Act(1, $pIdx))) | Out-Null }
            }
            'commando' { }
            default {
                if ($winEvents.Count -gt 0) { $mb.AddTrigger('Enemies destroyed', $playerHouse, 0, $winEvents, @([TSExt.MissionBuilder]::Act(1, $pIdx))) | Out-Null }
            }
        }
        if ($ms.player.base -eq 'none') {
            $mb.AddTrigger('Strike team lost', $playerHouse, 0, @([TSExt.MissionBuilder]::Ev(9, $pIdx)), @([TSExt.MissionBuilder]::Act(2, $pIdx))) | Out-Null
        }
        else {
            $mb.AddTrigger('Player destroyed', $playerHouse, 0, @([TSExt.MissionBuilder]::Ev(10, $pIdx)), @([TSExt.MissionBuilder]::Act(2, $pIdx))) | Out-Null
        }
        $timer = if ($ms.timeLimit) { [int]$ms.timeLimit } else { $minutes }
        if ($ms.timeLimit) {
            $mb.AddTrigger('Time is up', $playerHouse, 0, @([TSExt.MissionBuilder]::Ev(47, [int]$ms.timeLimit * 60)), @([TSExt.MissionBuilder]::Act(2, $pIdx))) | Out-Null
        }
        if ($timer -gt 0) {
            # on-screen countdown (mission timer, in seconds)
            $mb.AddTrigger('Countdown', $playerHouse, 0, @([TSExt.MissionBuilder]::Ev(47, 1)), @([TSExt.MissionBuilder]::Act(27, $timer * 60), [TSExt.MissionBuilder]::Act(23, 0))) | Out-Null
        }

        # basic settings
        $b = $map.Ini.GetOrAdd('Basic')
        $next = if ($mi + 1 -lt $missions.Count) { "$($missions[$mi + 1].file).MAP" } else { '' }
        $usesFs = $false
        foreach ($sec in 'Structures', 'Units', 'Infantry') { foreach ($v in $map.Ini[$sec].Values()) { if ($fsOnlyTypes.ContainsKey($v.Split(',')[1].ToUpper())) { $usesFs = $true } } }
        foreach ($k in @{ Name = (Get-Text $ms.name); Player = $playerHouse; NextScenario = $next; AltNextScenario = $next; EndOfGame = $(if ($next) { 'no' } else { 'yes' });
                SkipScore = 'no'; SkipMapSelect = 'yes'; Official = 'no'; MultiplayerOnly = '0'; IgnoreGlobalAITriggers = 'no'; OneTimeOnly = 'no';
                TruckCrate = 'no'; TrainCrate = 'no'; Percent = '0'; Intro = '<none>'; Brief = '<none>'; Win = '<none>'; Lose = '<none>'; Action = '<none>';
                PostScore = '<none>'; PreMapSelect = '<none>'; CarryOverMoney = '0.000000'; CarryOverCap = '0'; TimerInherit = 'no'; FillSilos = 'no';
                HomeCell = '98'; AltHomeCell = '98'; NewINIFormat = '4'; RequiredAddOn = '1'; FreeRadar = 'no'; InitTime = '10000'
            }.GetEnumerator()) { $b.Set($k.Key, [string]$k.Value) }
        $sf = $map.Ini.GetOrAdd('SpecialFlags')
        $sf.Set('MCVDeploy', 'yes'); $sf.Set('DestroyableBridges', 'yes'); $sf.Set('IonStorms', $(if ($ms.ionStorms) { 'yes' } else { 'no' }))
        if ($ms.night) {
            $lt = $map.Ini.GetOrAdd('Lighting')
            $amb = 1.0; [double]::TryParse(($lt.Get('Ambient') -replace ',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$amb) | Out-Null
            $lt.Set('Ambient', ($amb * 0.55).ToString('0.000000', [Globalization.CultureInfo]::InvariantCulture))
            $lt.Set('Red', '0.850000'); $lt.Set('Green', '0.950000'); $lt.Set('Blue', '1.350000')
        }
        $brief = $map.Ini.GetOrAdd('Briefing'); $brief.Pairs.Clear()
        $n = 1; foreach ($line in (Split-Briefing (Get-Text $ms.briefing))) { $brief.Set(($n++).ToString(), $line) }
        [void]$map.Ini.RemoveSection('Preview'); [void]$map.Ini.RemoveSection('PreviewPack')

        $outFile = Join-Path $OutDir "$($ms.file).MAP"
        [IO.File]::WriteAllBytes($outFile, $map.Save())
        $built += [pscustomobject]@{ Campaign = $camp.id; File = "$($ms.file).MAP"; Name = (Get-Text $ms.name); UsesFS = $usesFs; Map = $ms.map }
        "built $($ms.file).MAP  ($($ms.map), $($ms.type), $($enemies.Count) enemies, FS units: $usesFs)"
    }
}

# Campaign list, Firestorm mode only: the game applies the Firestorm rules (and our rules options) only to
# scenarios with RequiredAddOn=1 (checked in the game: VeteranRatio 5 vs. 10), so every mission is a Firestorm mission.
$bi = New-Object TSExt.IniFile
$no = 1
foreach ($camp in $catalog.campaigns) {
    $first = @($camp.missions)[0].file
    $mine = @($built | Where-Object { $_.Campaign -eq $camp.id })
    if ($mine.Count -eq 0) { continue }
    $bi.Set('Battles', ($no++).ToString(), $camp.id)
    $bi.Set($camp.id, 'Description', (Get-Text $camp.name)); $bi.Set($camp.id, 'Scenario', "$first.MAP"); $bi.Set($camp.id, 'CD', '-1'); $bi.Set($camp.id, 'RequiredAddon', '1'); $bi.Set($camp.id, 'FinalMovie', '<none>')
}
[IO.File]::WriteAllBytes((Join-Path $OutDir 'BATTLEX.INI'), $bi.ToBytes())
$built | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutDir 'missions-built.json') -Encoding UTF8
"campaign list: BATTLEX.INI ($($no - 1) entries), $($built.Count) missions in $OutDir"

