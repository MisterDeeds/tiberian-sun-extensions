# Draws a map as a picture (for checking generated missions without starting the game):
# terrain by land type and height, overlay (tiberium) green, trees dark green, structures as boxes in house colors,
# units and infantry as dots, waypoints as numbers.
#   .\dev\show-map.ps1 -Map .\analysis\build-test\TSXG01.MAP -Out .\analysis\shots\TSXG01.png
param([Parameter(Mandatory)][string]$Map, [string]$Out = '', [int]$Scale = 4)
. (Join-Path $PSScriptRoot '..\src\tslib.ps1')
Add-Type -AssemblyName System.Drawing
$fs = Open-TSFiles (Find-TSGame); $fs.UseLooseFiles = $false
$m = [TSExt.MapFile]::Load([IO.File]::ReadAllBytes((Resolve-Path $Map)))
$th = [TSExt.Theater]::Load($fs, $m.TheaterName)
if (-not $Out) { $Out = [IO.Path]::ChangeExtension((Resolve-Path $Map).Path, '.png') }
$W = 2 * $m.Width + 2; $H = 2 * $m.Height + 4
$bmp = New-Object System.Drawing.Bitmap ($W * $Scale), ($H * $Scale)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Black)
function ToScreen([int]$x, [int]$y) { return @(($x - $y + $m.Width), ($x + $y - $m.Width)) }
foreach ($c in $m.Cells) {
    $tc = $th.CellOf($c.Tile, $c.Sub)
    $v = [math]::Min(255, 60 + $c.Level * 12)
    $col = switch ($tc.Land) {
        9 { [System.Drawing.Color]::FromArgb(20, 40, 120) }
        15 { [System.Drawing.Color]::FromArgb(90, 70, 50) }
        { $_ -in 7, 8 } { [System.Drawing.Color]::FromArgb(110, 110, 110) }
        { $_ -in 11, 12 } { [System.Drawing.Color]::FromArgb($v, $v, $v) }
        { $_ -in 1, 2, 3, 4 } { [System.Drawing.Color]::FromArgb(180, 200, 230) }
        default { [System.Drawing.Color]::FromArgb([int]($v * 0.8), [int]($v * 0.7), [int]($v * 0.45)) }
    }
    if ($tc.Ramp -ne 0) { $col = [System.Drawing.Color]::FromArgb([int]($col.R * 0.7), [int]($col.G * 0.7), [int]($col.B * 0.7)) }
    if ($m.OverlayAt($c.X, $c.Y) -ne 255) { $col = [System.Drawing.Color]::FromArgb(40, 200, 40) }
    $p = ToScreen $c.X $c.Y
    $b = New-Object System.Drawing.SolidBrush $col
    $g.FillRectangle($b, $p[0] * $Scale, $p[1] * $Scale, 2 * $Scale, $Scale); $b.Dispose()
}
$houseColors = @{}
$palette = @([System.Drawing.Color]::Gold, [System.Drawing.Color]::Red, [System.Drawing.Color]::Orange, [System.Drawing.Color]::Magenta, [System.Drawing.Color]::Cyan, [System.Drawing.Color]::DeepSkyBlue, [System.Drawing.Color]::White, [System.Drawing.Color]::LightGreen, [System.Drawing.Color]::Pink)
$hs = $m.Ini['Houses']; $i = 0
if ($hs) { foreach ($h in $hs.Values()) { $houseColors[$h] = $palette[$i % $palette.Count]; $i++ } }
$font = New-Object System.Drawing.Font 'Arial', ([math]::Max(7, $Scale * 2))
foreach ($kv in $m.Ini['Structures'].Pairs) {
    $f = $kv.Value.Split(','); $x = [int]$f[3]; $y = [int]$f[4]
    $col = if ($houseColors.ContainsKey($f[0])) { $houseColors[$f[0]] } else { [System.Drawing.Color]::Gray }
    $pen = New-Object System.Drawing.Pen $col, 2
    $p = ToScreen $x $y
    $g.DrawRectangle($pen, $p[0] * $Scale - 2, $p[1] * $Scale - 2, 5 * $Scale, 3 * $Scale); $pen.Dispose()
}
foreach ($sec in 'Units', 'Infantry') {
    if (-not $m.Ini[$sec]) { continue }
    foreach ($kv in $m.Ini[$sec].Pairs) {
        $f = $kv.Value.Split(','); $x = [int]$f[3]; $y = [int]$f[4]
        $col = if ($houseColors.ContainsKey($f[0])) { $houseColors[$f[0]] } else { [System.Drawing.Color]::Gray }
        $b = New-Object System.Drawing.SolidBrush $col
        $p = ToScreen $x $y
        $g.FillEllipse($b, $p[0] * $Scale, $p[1] * $Scale, $Scale + 1, $Scale + 1); $b.Dispose()
    }
}
foreach ($w in $m.Waypoints()) {
    $x = $w.Value % 1000; $y = [int][math]::Floor($w.Value / 1000)
    $p = ToScreen $x $y
    $g.DrawString([string]$w.Key, $font, [System.Drawing.Brushes]::White, $p[0] * $Scale, $p[1] * $Scale)
}
$y0 = 4
foreach ($h in $houseColors.Keys) { $b = New-Object System.Drawing.SolidBrush $houseColors[$h]; $g.DrawString($h, $font, $b, 4, $y0); $y0 += $font.Height; $b.Dispose() }
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"saved $Out"
