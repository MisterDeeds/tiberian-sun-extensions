# Options of the Tiberian Sun Extensions: the catalog (for the launcher), the presets, and how each option
# changes the game. Rules options become a changed copy of the player's own FIRESTRM.INI inside our archive
# EXPAND99.MIX (see Write-RulesMix); the game applies FIRESTRM.INI on top of RULES.INI for every Firestorm game
# (skirmish in Firestorm mode, Firestorm missions, our campaigns). The archive is removed again when the game ends.
# Dot-source after tslib.ps1.

$script:UiGerman = if ($env:TSEXT_LANG) { $env:TSEXT_LANG -eq 'de' } else { (Get-UICulture).TwoLetterISOLanguageName -eq 'de' }
function Txt([string]$en, [string]$de) { if ($script:UiGerman) { $de } else { $en } }

$script:MarkerLine = '; Tiberian Sun Extensions - generated file, removed when the game ends. Do not edit.'

# id, group, label, choices (value + label), default value
function Get-OptionCatalog {
    $x = 'x'
    return @(
        @{ Id = 'cost'; Group = (Txt 'Economy' 'Wirtschaft'); Label = (Txt 'Build costs' 'Baukosten'); Default = '1'
            Choices = @(@('1', (Txt 'original' 'Original')), @('0.75', '× 0.75'), @('0.5', (Txt 'half' 'halb')), @('0.25', (Txt 'a quarter' 'ein Viertel'))) }
        @{ Id = 'buildspeed'; Group = (Txt 'Economy' 'Wirtschaft'); Label = (Txt 'Build speed' 'Bautempo'); Default = '1'
            Choices = @(@('1', (Txt 'original' 'Original')), @('1.5', '× 1.5'), @('2', '× 2'), @('3', '× 3'), @('5', '× 5')) }
        @{ Id = 'tibvalue'; Group = (Txt 'Economy' 'Wirtschaft'); Label = (Txt 'Tiberium value' 'Tiberium-Wert'); Default = '1'
            Choices = @(@('1', (Txt 'original' 'Original')), @('1.5', '× 1.5'), @('2', '× 2'), @('3', '× 3')) }
        @{ Id = 'harvester'; Group = (Txt 'Economy' 'Wirtschaft'); Label = (Txt 'Harvester load' 'Sammler-Ladung'); Default = '1'
            Choices = @(@('1', (Txt 'original' 'Original')), @('1.5', '× 1.5'), @('2', '× 2'), @('3', '× 3')) }
        @{ Id = 'growth'; Group = (Txt 'Economy' 'Wirtschaft'); Label = (Txt 'Tiberium growth' 'Tiberium-Wachstum'); Default = '1'
            Choices = @(@('1', (Txt 'original' 'Original')), @('2', (Txt 'fast' 'schnell')), @('5', (Txt 'very fast' 'sehr schnell'))) }
        @{ Id = 'power'; Group = (Txt 'Economy' 'Wirtschaft'); Label = (Txt 'Power plant output' 'Kraftwerksleistung'); Default = '1'
            Choices = @(@('1', (Txt 'original' 'Original')), @('1.5', '× 1.5'), @('2', '× 2')) }
        @{ Id = 'veteran'; Group = (Txt 'Combat' 'Kampf'); Label = (Txt 'Promotions' 'Beförderungen'); Default = '1'
            Choices = @(@('1', (Txt 'original' 'Original')), @('2', (Txt 'twice as fast' 'doppelt so schnell')), @('4', (Txt '4 times as fast' 'viermal so schnell'))) }
        @{ Id = 'superweapon'; Group = (Txt 'Combat' 'Kampf'); Label = (Txt 'Super weapon charge time' 'Superwaffen-Ladezeit'); Default = '1'
            Choices = @(@('1', (Txt 'original' 'Original')), @('0.5', (Txt 'half' 'halb')), @('0.25', (Txt 'a quarter' 'ein Viertel'))) }
        @{ Id = 'strength'; Group = (Txt 'Combat' 'Kampf'); Label = (Txt 'Hit points of all units' 'Lebenspunkte aller Einheiten'); Default = '1'
            Choices = @(@('1', (Txt 'original' 'Original')), @('1.5', '× 1.5'), @('2', '× 2')) }
        @{ Id = 'arsenal'; Group = (Txt 'Combat' 'Kampf'); Label = (Txt 'Extended arsenal' 'Erweitertes Arsenal'); Default = '0'
            Choices = @(@('0', (Txt 'off' 'aus')), @('1', (Txt 'on: Umagon, Chameleon spy; heroes up to 3 times' 'an: Umagon, Chamäleon-Spion; Helden bis 3-mal'))) }
        @{ Id = 'ai'; Group = (Txt 'Enemies' 'Gegner'); Label = (Txt 'Computer opponents' 'Computergegner'); Default = '0'
            Choices = @(@('0', (Txt 'original' 'Original')), @('1', (Txt 'strong: more money, attacks sooner' 'stark: mehr Geld, greifen früher an')), @('2', (Txt 'brutal: much more money, big teams' 'brutal: viel mehr Geld, grosse Teams'))) }
        @{ Id = 'chaos'; Group = (Txt 'Enemies' 'Gegner'); Label = (Txt 'Meteorites and visceroids' 'Meteoriten und Viszeroiden'); Default = '0'
            Choices = @(@('0', (Txt 'original' 'Original')), @('1', (Txt 'on' 'an'))) }
        @{ Id = 'rmgsize'; Group = (Txt 'World' 'Welt'); Label = (Txt 'Random map size' 'Zufallskarten-Grösse'); Default = '1'
            Choices = @(@('0', (Txt 'original (50-175 cells)' 'Original (50-175 Felder)')), @('1', (Txt 'large (up to 220)' 'gross (bis 220)')), @('2', (Txt 'huge (200-235)' 'riesig (200-235)'))) }
        @{ Id = 'fog'; Group = (Txt 'World' 'Welt'); Label = (Txt 'Fog of war' 'Nebel des Krieges'); Default = '0'
            Choices = @(@('0', (Txt 'original' 'Original')), @('1', (Txt 'on' 'an'))) }
        @{ Id = 'resolution'; Group = (Txt 'Display' 'Anzeige'); Label = (Txt 'Resolution' 'Auflösung'); Default = 'native'
            Choices = @(@('native', (Txt 'screen resolution: sharp, see much more of the map' 'Bildschirmauflösung: scharf, viel mehr von der Karte')), @('keep', (Txt 'unchanged (as in SUN.INI)' 'unverändert (wie in SUN.INI)')), @('1920x1080', '1920 × 1080'), @('1280x720', (Txt '1280 × 720 (big pixels)' '1280 × 720 (grosse Pixel)'))) }
    )
}

function Get-Presets {
    return [ordered]@{
        (Txt 'Original' 'Original') = @{ rmgsize = '0' }
        (Txt 'Everything bigger' 'Alles grösser') = @{ rmgsize = '2'; arsenal = '1'; ai = '1'; buildspeed = '2'; harvester = '1.5'; resolution = 'native' }
        (Txt 'Relaxed' 'Gemütlich') = @{ cost = '0.5'; buildspeed = '3'; tibvalue = '2'; harvester = '2'; power = '2'; growth = '2'; arsenal = '1' }
        (Txt 'Hard test' 'Harte Probe') = @{ ai = '2'; superweapon = '0.5'; veteran = '2'; chaos = '1'; rmgsize = '1' }
        (Txt 'Chaos' 'Chaos') = @{ chaos = '1'; fog = '1'; arsenal = '1'; superweapon = '0.25'; veteran = '4'; strength = '1.5'; rmgsize = '2' }
    }
}

function Get-DefaultSettings {
    $s = @{}
    foreach ($o in Get-OptionCatalog) { $s[$o.Id] = $o.Default }
    return $s
}

function Test-RulesChanged($settings) {
    foreach ($k in 'cost', 'buildspeed', 'tibvalue', 'harvester', 'growth', 'power', 'veteran', 'superweapon', 'strength', 'arsenal', 'ai', 'chaos', 'fog') {
        $d = (Get-OptionCatalog | Where-Object { $_.Id -eq $k }).Default
        if ($settings[$k] -and [string]$settings[$k] -ne [string]$d) { return $true }
    }
    return $false
}

$script:Inv = [Globalization.CultureInfo]::InvariantCulture
function ConvertTo-Num([string]$v) {
    if ($null -eq $v) { return $null }
    $t = ($v -split ';')[0].Trim().TrimEnd('%')
    $d = 0.0
    if ([double]::TryParse($t, [Globalization.NumberStyles]::Float, $script:Inv, [ref]$d)) { return $d }
    return $null
}
function Format-Num([double]$v, [bool]$int) { if ($int) { return [string][int][math]::Round($v) } else { return $v.ToString('0.###', $script:Inv) } }

# Builds the bytes of the loose FIRESTRM.INI for these settings (from the original FIRESTRM.INI of the installation).
function New-RulesFile($fs, $settings) {
    $rules = [TSExt.IniFile]::Parse($fs.Read('RULES.INI'))
    $orig = $fs.Read('FIRESTRM.INI')
    $out = [TSExt.IniFile]::Parse($orig)
    function Eff([string]$sec, [string]$key) { $v = $out.Get($sec, $key); if ($null -eq $v) { $v = $rules.Get($sec, $key) }; return $v }
    function Scale([string]$sec, [string]$key, [double]$f, [bool]$int, [double]$min) {
        $n = ConvertTo-Num (Eff $sec $key)
        if ($null -eq $n -or $n -le 0) { return }
        $out.Set($sec, $key, (Format-Num ([math]::Max($min, $n * $f)) $int))
    }
    $types = New-Object System.Collections.Generic.List[string]
    foreach ($list in 'BuildingTypes', 'VehicleTypes', 'InfantryTypes', 'AircraftTypes') {
        foreach ($ini in $rules, $out) { if ($ini[$list]) { foreach ($t in $ini[$list].Values()) { if (-not $types.Contains($t)) { $types.Add($t) } } } }
    }
    $num = { param($k) [double]::Parse([string]$settings[$k], $script:Inv) }

    $f = & $num 'cost'
    if ($f -ne 1) { foreach ($t in $types) { Scale $t 'Cost' $f $true 1 } }
    $f = & $num 'buildspeed'
    if ($f -ne 1) { Scale 'General' 'BuildSpeed' (1 / $f) $false 0.01 }
    $f = & $num 'tibvalue'
    if ($f -ne 1) { if ($rules['Tiberiums']) { foreach ($t in $rules['Tiberiums'].Values()) { Scale $t 'Value' $f $true 1 } } }
    $f = & $num 'harvester'
    if ($f -ne 1) { foreach ($t in 'HARV', 'WEED') { Scale $t 'Storage' $f $true 1 } }
    $f = & $num 'growth'
    if ($f -ne 1) {
        Scale 'General' 'GrowthRate' (1 / $f) $false 0.2
        $out.Set('General', 'TiberiumGrows', 'yes'); $out.Set('General', 'TiberiumSpreads', 'yes')
        if ($rules['Tiberiums']) { foreach ($t in $rules['Tiberiums'].Values()) { Scale $t 'Growth' $f $true 1; Scale $t 'Spread' $f $true 1 } }
    }
    $f = & $num 'power'
    if ($f -ne 1) { foreach ($t in $types) { $p = ConvertTo-Num (Eff $t 'Power'); if ($null -ne $p -and $p -gt 0) { $out.Set($t, 'Power', (Format-Num ($p * $f) $true)) } } }
    $f = & $num 'veteran'
    if ($f -ne 1) { Scale 'General' 'VeteranRatio' (1 / $f) $false 0.5 }
    $f = & $num 'superweapon'
    if ($f -ne 1) {
        foreach ($sw in 'ChemicalSpecial', 'MultiSpecial', 'EMPulseSpecial', 'FirestormSpecial', 'IonCannonSpecial', 'HuntSeekSpecial', 'DropPodSpecial') { Scale $sw 'RechargeTime' $f $false 0.1 }
    }
    $f = & $num 'strength'
    if ($f -ne 1) {
        foreach ($list in 'VehicleTypes', 'InfantryTypes', 'AircraftTypes') {
            foreach ($t in $types) { if ($rules[$list] -and $rules[$list].Values() -contains $t -or ($out[$list] -and $out[$list].Values() -contains $t)) { Scale $t 'Strength' $f $true 1 } }
        }
    }
    if ($settings['arsenal'] -eq '1') {
        # hidden units of the game that have pictures, build icons and voices: buildable again
        $out.Set('UMAGON', 'TechLevel', '6'); $out.Set('UMAGON', 'Owner', 'GDI'); $out.Set('UMAGON', 'Prerequisite', 'GAPILE,GARADR'); $out.Set('UMAGON', 'AllowedToStartInMultiplayer', 'no')
        $out.Set('CHAMSPY', 'TechLevel', '6'); $out.Set('CHAMSPY', 'Owner', 'Nod'); $out.Set('CHAMSPY', 'Prerequisite', 'NAHAND,NARADR'); $out.Set('CHAMSPY', 'AllowedToStartInMultiplayer', 'no')
        foreach ($h in 'GHOST', 'CYC2', 'MHIJACK', 'HMEC', 'MOBWARG', 'MOBWARN') { if (Eff $h 'BuildLimit') { $out.Set($h, 'BuildLimit', '3') } }
    }
    switch ([string]$settings['ai']) {
        '1' {
            $out.Set('General', 'MultiplayerAICM', '350,300,200')
            Scale 'AI' 'AttackInterval' 0.6 $false 0.5; Scale 'AI' 'AttackDelay' 0.5 $false 0.5
            $out.Set('General', 'TeamDelays', '1500,1800,2400'); $out.Set('General', 'TotalAITeamCap', '20,18,14')
            $out.Set('General', 'MaximumAIDefensiveTeams', '8,7,6')
        }
        '2' {
            $out.Set('General', 'MultiplayerAICM', '600,500,400')
            Scale 'AI' 'AttackInterval' 0.35 $false 0.3; Scale 'AI' 'AttackDelay' 0.25 $false 0.3
            $out.Set('General', 'TeamDelays', '900,1100,1400'); $out.Set('General', 'TotalAITeamCap', '30,26,22')
            $out.Set('General', 'MaximumAIDefensiveTeams', '10,9,8'); $out.Set('General', 'MinimumAIDefensiveTeams', '5,4,3')
            $out.Set('General', 'AIHateDelays', '2400,2000,1800')
        }
    }
    if ($settings['chaos'] -eq '1') { $out.Set('General', 'Meteorites', 'yes'); $out.Set('General', 'Visceroids', 'yes') }
    if ($settings['fog'] -eq '1') { $out.Set('General', 'FogOfWar', 'yes') }

    $text = $script:MarkerLine + "`r`n" + $out.ToText()
    return , ([TSExt.IniFile]::Enc.GetBytes($text))   # the comma keeps the byte[] in one piece
}

# The rules file goes into our own archive EXPAND99.MIX: the game searches MIX archives before loose files, and it
# registers EXPAND99..EXPAND00 in this order, so EXPAND99.MIX comes before Firestorm's EXPAND01.MIX
# (checked in the game, see docs/FINDINGS.md). The archive holds a marker file so that we only ever remove our own.
$script:RulesMixName = 'EXPAND99.MIX'
$script:RulesMixMarker = 'TSEXT.TXT'

function Write-RulesMix([string]$gameDir, [byte[]]$firestrm) {
    $files = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,byte[]]]'
    $files.Add((New-Object 'System.Collections.Generic.KeyValuePair[string,byte[]]' 'FIRESTRM.INI', $firestrm))
    $files.Add((New-Object 'System.Collections.Generic.KeyValuePair[string,byte[]]' $script:RulesMixMarker, ([Text.Encoding]::ASCII.GetBytes($script:MarkerLine))))
    [IO.File]::WriteAllBytes((Join-Path $gameDir $script:RulesMixName), [TSExt.MixWriter]::Build($files))
}

# Is the EXPAND99.MIX in the game folder ours? $null if there is none.
function Test-OurRulesFile([string]$gameDir) {
    $p = Join-Path $gameDir $script:RulesMixName
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { $m = New-Object TSExt.MixFile $p; return $m.Contains($script:RulesMixMarker) } catch { return $false }
}

function Remove-OurRulesFile([string]$gameDir) {
    if (Test-OurRulesFile $gameDir) { Remove-Item -LiteralPath (Join-Path $gameDir $script:RulesMixName) -Force }
    # older test builds wrote a loose FIRESTRM.INI
    $loose = Join-Path $gameDir 'FIRESTRM.INI'
    if ((Test-Path -LiteralPath $loose) -and (Get-Content -LiteralPath $loose -TotalCount 1) -eq $script:MarkerLine) { Remove-Item -LiteralPath $loose -Force }
}

# Highest screen height that works without the sidebar fix of patcher.ps1 (sidebar starts at y = 148 and has room
# for 20 rows of 51 pixels plus 46 pixels of top and bottom pieces): 148 + 46 + 20 * 51 = 1214.
$script:SafeHeightWithoutFix = 1214

# Resolution in SUN.INI ([Video] ScreenWidth / ScreenHeight), or $null.
function Get-GameResolution([string]$gameDir) {
    $sun = Join-Path $gameDir 'SUN.INI'
    if (-not (Test-Path -LiteralPath $sun)) { return $null }
    $ini = [TSExt.IniFile]::Parse([IO.File]::ReadAllBytes($sun))
    $w = $ini.Get('Video', 'ScreenWidth'); $h = $ini.Get('Video', 'ScreenHeight')
    if (-not $w -or -not $h) { return $null }
    return "$w" + 'x' + "$h"
}

# The resolution an option value stands for ("native" = the primary screen), e.g. "2560x1440".
function Resolve-Resolution([string]$value) {
    if (-not $value -or $value -eq 'keep') { return $null }
    if ($value -eq 'native') {
        Add-Type -AssemblyName System.Windows.Forms
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        return "$($b.Width)x$($b.Height)"
    }
    return $value
}

# Screen resolution in SUN.INI ([Video] ScreenWidth / ScreenHeight).
function Set-GameResolution([string]$gameDir, [string]$value) {
    $value = Resolve-Resolution $value
    if (-not $value) { return }
    $p = $value.Split('x'); $w = [int]$p[0]; $h = [int]$p[1]
    $sun = Join-Path $gameDir 'SUN.INI'
    $lines = if (Test-Path -LiteralPath $sun) { [System.Collections.Generic.List[string]](Get-Content -LiteralPath $sun -Encoding Default) } else { New-Object System.Collections.Generic.List[string] }
    $sec = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq '[Video]') { $sec = $i; break } }
    if ($sec -lt 0) { $lines.Add('[Video]'); $sec = $lines.Count - 1 }
    foreach ($kv in @(@('ScreenWidth', $w), @('ScreenHeight', $h), @('AllowHiResModes', 'yes'))) {
        $found = $false
        for ($i = $sec + 1; $i -lt $lines.Count -and -not $lines[$i].Trim().StartsWith('['); $i++) {
            if ($lines[$i] -match ('^\s*' + $kv[0] + '\s*=')) { $lines[$i] = $kv[0] + '=' + $kv[1]; $found = $true; break }
        }
        if (-not $found) { $lines.Insert($sec + 1, $kv[0] + '=' + $kv[1]) }
    }
    [IO.File]::WriteAllLines($sun, $lines, [Text.Encoding]::Default)
}



