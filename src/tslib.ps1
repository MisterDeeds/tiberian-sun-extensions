# Loads the C# core library (TSLib.cs) and finds the game. Dot-source this file.
$ErrorActionPreference = 'Stop'

if (-not ('TSExt.MixFile' -as [type])) {
    $libSources = @((Join-Path $PSScriptRoot 'TSLib.cs'), (Join-Path $PSScriptRoot 'TSProc.cs'), (Join-Path $PSScriptRoot 'TSMap.cs')) | Where-Object { Test-Path -LiteralPath $_ }
    Add-Type -Path $libSources -ReferencedAssemblies 'System.Numerics', 'System.Drawing' -ErrorAction Stop
}

# The Steam installation of "Command & Conquer Tiberian Sun and Firestorm" (app 2229850? - read from the manifests).
function Find-TSGame {
    if ($env:TSEXT_GAMEDIR -and (Test-Path -LiteralPath (Join-Path $env:TSEXT_GAMEDIR 'Game.exe'))) { return $env:TSEXT_GAMEDIR }
    $libs = New-Object System.Collections.Generic.List[string]
    $steam = $null
    try { $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch { }
    if (-not $steam) { try { $steam = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop).InstallPath } catch { } }
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $libs.Add($steam)
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $p = $m.Groups[1].Value -replace '\\\\', '\'
                if (-not $libs.Contains($p)) { $libs.Add($p) }
            }
        }
    }
    foreach ($lib in $libs) {
        $apps = Join-Path $lib 'steamapps'
        if (-not (Test-Path -LiteralPath $apps)) { continue }
        foreach ($acf in Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue) {
            $t = Get-Content -LiteralPath $acf.FullName -Raw
            if ($t -match '"name"\s+"[^"]*Tiberian Sun[^"]*"' -and $t -match '"installdir"\s+"([^"]+)"') {
                $dir = Join-Path (Join-Path $apps 'common') $Matches[1]
                if (Test-Path -LiteralPath (Join-Path $dir 'Game.exe')) { return $dir }
            }
        }
    }
    # Registry entry written by the game's install script
    try {
        $p = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Westwood\Tiberian Sun' -ErrorAction Stop).InstallPath
        if ($p) { $d = Split-Path -Parent $p; if (Test-Path -LiteralPath (Join-Path $d 'Game.exe')) { return $d } }
    } catch { }
    return $null
}

# Opens the game's MIX files in the order the game searches them (see docs/FINDINGS.md, "MIX order").
function Open-TSFiles([string]$GameDir) {
    $fs = New-Object TSExt.GameFiles $GameDir
    foreach ($n in $script:TSMixOrder) { [void]$fs.AddFile($n) }
    foreach ($n in $script:TSNestedMixes) { [void]$fs.AddNestedAll($n) }
    return $fs
}

# Search order, highest priority first, as Game.exe registers them (FUN_004e3d20: PATCH.MIX, then EXPAND99..00,
# then TIBSUN.MIX, CACHE.MIX, LOCAL.MIX; the rest later). See docs/FINDINGS.md "MIX order".
$script:TSMixOrder = @(
    'PATCH.MIX', 'EXPAND03.MIX', 'EXPAND02.MIX', 'EXPAND01.MIX', 'ECACHE01.MIX', 'TIBSUN.MIX', 'CACHE.MIX', 'LOCAL.MIX', 'CONQUER.MIX',
    'MULTI.MIX', 'SIDECD01.MIX', 'SIDECD02.MIX', 'E01SCD01.MIX', 'E01SCD02.MIX', 'MAPS01.MIX', 'MAPS02.MIX', 'MAPS03.MIX'
)
# Theater archives (tiles), opened from every archive that has them.
$script:TSNestedMixes = @('ISOTEMP.MIX', 'ISOSNOW.MIX', 'TEMPERAT.MIX', 'SNOW.MIX')
