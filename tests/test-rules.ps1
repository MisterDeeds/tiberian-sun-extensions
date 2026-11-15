# Builds the rules file for every preset and for single options and checks the values against the original files.
. (Join-Path $PSScriptRoot '..\src\tslib.ps1')
. (Join-Path $PSScriptRoot '..\src\options.ps1')
$ErrorActionPreference = 'Stop'
$fs = Open-TSFiles (Find-TSGame); $fs.UseLooseFiles = $false
$rules = [TSExt.IniFile]::Parse($fs.Read('RULES.INI')); $orig = [TSExt.IniFile]::Parse($fs.Read('FIRESTRM.INI'))
function Eff($ini, $s, $k) { $v = $ini.Get($s, $k); if ($null -eq $v) { $v = $rules.Get($s, $k) }; return $v }
function Num($v) { return [double]::Parse((($v -split ';')[0].Trim().TrimEnd('%')), [Globalization.CultureInfo]::InvariantCulture) }
$errors = 0
function Check([string]$what, [bool]$ok) { if ($ok) { "  ok   $what" } else { "  FAIL $what"; $script:errors++ } }

"defaults change nothing:"
Check 'Test-RulesChanged(defaults) is false' (-not (Test-RulesChanged (Get-DefaultSettings)))

foreach ($case in @(
        @{ k = 'cost'; v = '0.5'; s = 'MMCH'; key = 'Cost'; f = 0.5 }
        @{ k = 'buildspeed'; v = '2'; s = 'General'; key = 'BuildSpeed'; f = 0.5 }
        @{ k = 'tibvalue'; v = '3'; s = 'Riparius'; key = 'Value'; f = 3 }
        @{ k = 'harvester'; v = '2'; s = 'HARV'; key = 'Storage'; f = 2 }
        @{ k = 'power'; v = '2'; s = 'GAPOWR'; key = 'Power'; f = 2 }
        @{ k = 'veteran'; v = '2'; s = 'General'; key = 'VeteranRatio'; f = 0.5 }
        @{ k = 'superweapon'; v = '0.5'; s = 'IonCannonSpecial'; key = 'RechargeTime'; f = 0.5 }
        @{ k = 'strength'; v = '2'; s = 'MMCH'; key = 'Strength'; f = 2 }
    )) {
    $set = Get-DefaultSettings; $set[$case.k] = $case.v
    $out = [TSExt.IniFile]::Parse((New-RulesFile $fs $set))
    $before = Num (Eff $orig $case.s $case.key); $after = Num (Eff $out $case.s $case.key)
    Check ("{0}={1}: [{2}] {3} {4} -> {5}" -f $case.k, $case.v, $case.s, $case.key, $before, $after) ([math]::Abs($after - $before * $case.f) -le [math]::Max(1, $before * $case.f * 0.01))
    # everything else stays as it was
    $other = Num (Eff $out 'E1' 'Cost'); if ($case.k -ne 'cost') { Check "  E1 Cost unchanged ($other)" ($other -eq (Num (Eff $orig 'E1' 'Cost'))) }
}
$set = Get-DefaultSettings; $set['arsenal'] = '1'
$out = [TSExt.IniFile]::Parse((New-RulesFile $fs $set))
Check 'arsenal: UMAGON buildable (TechLevel 6)' ((Eff $out 'UMAGON' 'TechLevel') -eq '6')
Check 'arsenal: GHOST BuildLimit 3' ((Eff $out 'GHOST' 'BuildLimit') -eq '3')
$set = Get-DefaultSettings; $set['ai'] = '2'
$out = [TSExt.IniFile]::Parse((New-RulesFile $fs $set))
Check 'ai brutal: MultiplayerAICM' ((Eff $out 'General' 'MultiplayerAICM') -eq '600,500,400')
foreach ($pn in (Get-Presets).Keys) {
    $set = Get-DefaultSettings; foreach ($k in (Get-Presets)[$pn].Keys) { $set[$k] = (Get-Presets)[$pn][$k] }
    $b = New-RulesFile $fs $set
    $ini = [TSExt.IniFile]::Parse($b)
    Check ("preset {0}: {1} sections, starts with marker" -f $pn, $ini.Sections.Count) ($ini.Sections.Count -ge $orig.Sections.Count -and ([TSExt.IniFile]::Enc.GetString($b, 0, 60)).StartsWith('; Tiberian Sun Extensions'))
}
# game speed in a copy of SUN.INI: set and set back, the rest of the file stays byte for byte
$tmpDir = Join-Path ([IO.Path]::GetTempPath()) ('tsext-speed-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $tmpDir | Out-Null
$sunText = "[Intro]`r`nPlaySide01=no`r`n`r`n[Options]`r`nGameSpeed=0`r`nDifficulty=1`r`n`r`n[Video]`r`nScreenWidth=1920`r`n"
[IO.File]::WriteAllText((Join-Path $tmpDir 'SUN.INI'), $sunText, [Text.Encoding]::Default)
Check 'speed: read 0' ((Get-GameSpeed $tmpDir) -eq '0')
Set-GameSpeed $tmpDir '2'
$changed = [IO.File]::ReadAllText((Join-Path $tmpDir 'SUN.INI'), [Text.Encoding]::Default)
Check 'speed: set 2, line endings kept' ((Get-GameSpeed $tmpDir) -eq '2' -and $changed -eq $sunText.Replace('GameSpeed=0', 'GameSpeed=2'))
Set-GameSpeed $tmpDir 'keep'
Check 'speed: keep changes nothing' ((Get-GameSpeed $tmpDir) -eq '2')
Set-GameSpeed $tmpDir '0'
Check 'speed: set back, file identical' ([IO.File]::ReadAllText((Join-Path $tmpDir 'SUN.INI'), [Text.Encoding]::Default) -eq $sunText)
Remove-Item -Recurse -Force $tmpDir

if ($errors) { "$errors errors"; exit 1 } else { 'all rules checks ok' }
