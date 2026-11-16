# Measures random maps saved by dev\rmg-survey.ps1 (or any .map files): terrain, cliffs, building space and Tiberium.
#   .\dev\rmg-stats.ps1 [-Dir .\analysis\rmg]
# "Building space": flat cells (no ramp) of clear / road / rough ground without overlay, trees or water, inside the
# visible area; "largest area" is the biggest connected group of such cells on one height (where one base fits).
param([string]$Dir = (Join-Path $PSScriptRoot '..\analysis\rmg'))
. (Join-Path $PSScriptRoot '..\src\tslib.ps1')
$fs = Open-TSFiles (Find-TSGame); $fs.UseLooseFiles = $false
$rules = [TSExt.IniFile]::Parse($fs.Read('RULES.INI'))
# overlay index = position in [OverlayTypes] (0-based); Tiberium overlays have Tiberium=yes
$ovTypes = @($rules['OverlayTypes'].Values())
$isTib = New-Object bool[] 256
for ($i = 0; $i -lt $ovTypes.Count -and $i -lt 256; $i++) { if ($rules.Get($ovTypes[$i], 'Tiberium') -match '^(yes|true)') { $isTib[$i] = $true } }
$theaters = @{}
foreach ($f in Get-ChildItem -LiteralPath $Dir -Filter '*.map' | Sort-Object LastWriteTime) {
    $m = [TSExt.MapFile]::Load([IO.File]::ReadAllBytes($f.FullName))
    if (-not $theaters.ContainsKey($m.TheaterName)) { $theaters[$m.TheaterName] = [TSExt.Theater]::Load($fs, $m.TheaterName) }
    $th = $theaters[$m.TheaterName]
    $pl = New-Object TSExt.Placement $m, $th
    $n = 0; $cliff = 0; $ramp = 0; $water = 0; $levels = @{}; $tibCells = 0; $tibSum = 0; $free = 0
    $buildable = New-Object 'System.Collections.Generic.Dictionary[int,int]'
    foreach ($c in $m.Cells) {
        if (-not $pl.InLocal($c.X, $c.Y)) { continue }
        $n++
        $tc = $th.CellOf($c.Tile, $c.Sub)
        if ($tc.Land -eq 15) { $cliff++ }
        if ($tc.Ramp -ne 0) { $ramp++ }
        if ($tc.Land -eq 9) { $water++ }
        $levels[[int]$c.Level] = 1 + [int]$levels[[int]$c.Level]
        $o = $m.OverlayAt($c.X, $c.Y)
        if ($o -ne 255 -and $isTib[$o]) { $tibCells++; $tibSum += 1 + $m.OverlayData[$c.Y * 512 + $c.X] }
        $lv = $pl.BuildableLevel($c.X, $c.Y)
        if ($lv -ge 0) { $free++; $buildable[[TSExt.MapFile]::Key($c.X, $c.Y)] = $lv }
    }
    # connected areas of buildable cells on one height (4 neighbours)
    $seen = New-Object 'System.Collections.Generic.HashSet[int]'
    $areas = New-Object System.Collections.Generic.List[int]
    foreach ($k in @($buildable.Keys)) {
        if ($seen.Contains($k)) { continue }
        $lv = $buildable[$k]; $size = 0
        $q = New-Object System.Collections.Generic.Queue[int]; $q.Enqueue($k); [void]$seen.Add($k)
        while ($q.Count) {
            $cur = $q.Dequeue(); $size++
            $x = $cur -band 1023; $y = $cur -shr 10
            foreach ($d in @(@(1, 0), @(-1, 0), @(0, 1), @(0, -1))) {
                $nk = [TSExt.MapFile]::Key($x + $d[0], $y + $d[1])
                if (-not $seen.Contains($nk) -and $buildable.ContainsKey($nk) -and $buildable[$nk] -eq $lv) { [void]$seen.Add($nk); $q.Enqueue($nk) }
            }
        }
        $areas.Add($size)
    }
    $sorted = @($areas | Sort-Object -Descending)
    $terrain = $m.Ini['Terrain']; $trees = 0; $tibTrees = 0
    if ($terrain) { foreach ($v in $terrain.Values()) { $trees++; if ($v -match '^TIBTRE') { $tibTrees++ } } }
    [pscustomobject]@{
        Map        = $f.BaseName
        Size       = "$($m.Width)x$($m.Height)"
        Cells      = $n
        Levels     = $levels.Count
        CliffPct   = [math]::Round(100.0 * $cliff / $n, 1)
        RampPct    = [math]::Round(100.0 * $ramp / $n, 1)
        WaterPct   = [math]::Round(100.0 * $water / $n, 1)
        BuildPct   = [math]::Round(100.0 * $free / $n, 1)
        Largest    = $(if ($sorted.Count) { $sorted[0] } else { 0 })
        Top5       = (($sorted | Select-Object -First 5) -join '/')
        TibCells   = $tibCells
        TibPct     = [math]::Round(100.0 * $tibCells / $n, 1)
        TibValue   = $tibSum
        Trees      = $trees
        TibTrees   = $tibTrees
    }
}
