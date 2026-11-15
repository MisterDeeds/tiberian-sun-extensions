# Checks the map format assumptions against every official multiplayer map of the installation:
# template sub-tile indexing, overlay index (Y*512+X), waypoint numbers (Y*1000+X) and the visible area.
. (Join-Path $PSScriptRoot '..\src\tslib.ps1')
$game = Find-TSGame
$fs = Open-TSFiles $game
$fs.UseLooseFiles = $false
$theaters = @{}
$names = New-Object System.Collections.Generic.List[string]
foreach ($pkt in 'MISSIONS.PKT', 'MULTI01.PKT') {
    $ini = [TSExt.IniFile]::Parse($fs.Read($pkt))
    foreach ($v in $ini['MultiMaps'].Values()) { $names.Add($v) }
}
foreach ($n in $names) {
    $b = $fs.Read("$n.MAP")
    if (-not $b) { "{0,-10} not found" -f $n; continue }
    $m = [TSExt.MapFile]::Load($b)
    if (-not $theaters.ContainsKey($m.TheaterName)) { $theaters[$m.TheaterName] = [TSExt.Theater]::Load($fs, $m.TheaterName) }
    $th = $theaters[$m.TheaterName]
    $badSub = 0; $ramps = 0
    foreach ($c in $m.Cells) { $tc = $th.CellOf($c.Tile, $c.Sub); if (-not $tc.Present) { $badSub++ }; if ($tc.Ramp -ne 0) { $ramps++ } }
    $ovA = 0; $ovB = 0; $ovN = 0
    for ($i = 0; $i -lt 262144; $i++) {
        if ($m.Overlay[$i] -ne 255) {
            $ovN++
            $hi = [int][math]::Floor($i / 512); $lo = $i % 512
            # count overlays that would sit on water or cliffs under each reading (fewer = right reading)
            $ca = $m.Get($lo, $hi); if ($ca) { $l = $th.CellOf($ca.Tile, $ca.Sub).Land; if ($l -eq 9 -or $l -eq 15) { $ovA++ } }   # index = Y*512+X
            $cb = $m.Get($hi, $lo); if ($cb) { $l = $th.CellOf($cb.Tile, $cb.Sub).Land; if ($l -eq 9 -or $l -eq 15) { $ovB++ } }   # index = X*512+Y
        }
    }
    $wpA = 0; $wpB = 0; $wpN = 0; $inLocal = 0
    $pl = New-Object TSExt.Placement $m, $th
    foreach ($w in $m.Waypoints()) {
        $wpN++
        $y = [int][math]::Floor($w.Value / 1000); $x = $w.Value % 1000
        if ($m.Get($x, $y)) { $wpA++ }
        if ($m.Get($y, $x)) { $wpB++ }
        if ($w.Key -lt 8 -and $pl.InLocal($x, $y)) { $inLocal++ }
    }
    '{0,-10} {1,-9} {2,3}x{3,-3} cells={4,6} badSub={5} ramps={6,5} overlay={7,5} Y*512+X={8,5} X*512+Y={9,5} wp={10,2} Y*1000+X={11,2} X*1000+Y={12,2} startInLocal={13}' -f `
        $n, $m.TheaterName, $m.Width, $m.Height, $m.Cells.Count, $badSub, $ramps, $ovN, $ovA, $ovB, $wpN, $wpA, $wpB, $inLocal
}
foreach ($k in $theaters.Keys) { "theater $k tiles=$($theaters[$k].Tiles.Length) sets=$($theaters[$k].SetNames.Count)" }
