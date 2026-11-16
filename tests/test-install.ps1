# Installs and removes the extensions for real, but into a sandbox folder (programs, settings, desktop, start menu,
# registry key name and the mission target are below the sandbox; the game itself is only read). Then checks:
# - the launcher in its self-test mode (window built, presets clicked, closed again), including the update logic with
#   a newer release as if GitHub had reported it (notice, automatic start, once per day, off, note after an update);
# - the removal by the installed copy;
# - get.ps1 (the one-line installer) through Invoke-Expression with a ZIP in the layout of a GitHub release, into a
#   second sandbox, and with a broken ZIP.
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sandbox = Join-Path $env:TEMP 'tsext-sandbox'
$sandbox2 = Join-Path $env:TEMP 'tsext-sandbox-get'
$stage = Join-Path $env:TEMP 'tsext-sandbox-zip'
foreach ($d in $sandbox, $sandbox2, $stage) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
$install = Join-Path $repoRoot 'src\install.ps1'
$appsKey = 'HKCU:\Software\TSExtensionsSandboxTest'
$version = (Select-String -LiteralPath (Join-Path $repoRoot 'CHANGELOG.md') -Pattern '^## (\d+\.\d+\.\d+)' | Select-Object -First 1).Matches[0].Groups[1].Value
$today = Get-Date -Format 'yyyy-MM-dd'
$errors = 0
function Check([string]$what, [bool]$ok) { if ($ok) { "  ok   $what" } else { "  FAIL $what"; $script:errors++ } }
function Get-SetupFolders { @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'tiberian-sun-extensions-setup-*' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }

"install (version $version):"
$out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $install -SandboxRoot $sandbox -StartLauncher)
$exit = $LASTEXITCODE
$out | ForEach-Object { "    $_" }
$prog = Join-Path $sandbox 'Programs\TSExtensions'
Check 'installer exit code 0' ($exit -eq 0)
Check 'launcher.ps1 installed' (Test-Path -LiteralPath (Join-Path $prog 'launcher.ps1'))
Check "version.txt = $version" ((Test-Path -LiteralPath (Join-Path $prog 'version.txt')) -and (Get-Content -LiteralPath (Join-Path $prog 'version.txt') -Raw).Trim() -eq $version)
Check 'missions built (15 maps)' (@(Get-ChildItem -LiteralPath (Join-Path $prog 'missions') -Filter 'TSX*.MAP').Count -eq 15)
Check 'missions copied to the (sandbox) game folder' (@(Get-ChildItem -LiteralPath (Join-Path $sandbox 'GameFolder') -Filter 'TSX*.MAP').Count -eq 15)
Check 'BATTLEX.INI copied' (Test-Path -LiteralPath (Join-Path $sandbox 'GameFolder\BATTLEX.INI'))
Check 'desktop shortcut' (@(Get-ChildItem -LiteralPath (Join-Path $sandbox 'Desktop') -Filter '*.lnk').Count -eq 1)
Check 'start menu shortcut' (@(Get-ChildItem -LiteralPath (Join-Path $sandbox 'StartMenu') -Filter '*.lnk').Count -eq 1)
Check 'Apps entry (sandbox key)' (Test-Path $appsKey)
$entry = Get-ItemProperty $appsKey -ErrorAction SilentlyContinue
Check "Apps entry shows version $version" ($entry -and $entry.DisplayVersion -eq $version)
Check 'Apps entry removes with -Remove -PauseAtEnd' ($entry -and $entry.UninstallString -match ' -Remove -PauseAtEnd$')
Check 'launcher opened at the end (-StartLauncher, printed in the sandbox)' (@($out | Where-Object { $_ -like 'START *launcher.ps1*' }).Count -eq 1)

"installed copy without -Remove:"
$out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $prog 'install.ps1') -SandboxRoot $sandbox)
$out | ForEach-Object { "    $_" }
Check 'refuses to install over itself' (($out -join ' ') -match 'installed copy|installierte Kopie')
Check 'version.txt still there' (Test-Path -LiteralPath (Join-Path $prog 'version.txt'))

"launcher self-test and updates:"
$settingsDir = Join-Path $sandbox 'AppData\TSExtensions'
$settingsFile = Join-Path $settingsDir 'settings.json'
$selfTestFile = Join-Path $env:TEMP 'tsext-selftest.txt'
function Invoke-SelfTest([string]$what, [string[]]$more = @()) {
    if (Test-Path -LiteralPath $selfTestFile) { Remove-Item -LiteralPath $selfTestFile -Force }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $prog 'launcher.ps1') -SelfTest -DryRun -SettingsDir $settingsDir @more
    $r = @(); if (Test-Path -LiteralPath $selfTestFile) { $r = @(Get-Content -LiteralPath $selfTestFile -Encoding UTF8) }
    "  [$what]"; $r | Where-Object { $_ -match '^(version|update row|tabs):' } | ForEach-Object { "    $_" }
    $script:last = $r -join "`n"
}
function Get-Saved { $h = @{}; if (Test-Path -LiteralPath $settingsFile) { $j = Get-Content -LiteralPath $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $h[$p.Name] = [string]$p.Value } }; $h }
function Set-Saved($h) { New-Item -ItemType Directory -Force $settingsDir | Out-Null; ([pscustomobject]$h) | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8 }

Set-Saved @{ speed = '2'; resolution = 'native' }
Invoke-SelfTest 'first start, no newer release'
Check 'self-test ran' ($last -match 'tabs: 3')
Check "version $version, installed copy, box shown and on" ($last -match "version: $([regex]::Escape($version)), installed: True, auto update: True \(box shown: True\)")
Check 'no update row' ($last -match 'update row: shown=False')
Check 'LastVersion saved' ((Get-Saved)['LastVersion'] -eq $version)
Check 'other settings kept (speed=2, resolution=native)' ((Get-Saved)['speed'] -eq '2' -and (Get-Saved)['resolution'] -eq 'native')

Invoke-SelfTest 'older release v1.0.0' @('-PreviewUpdate', 'v1.0.0')
Check 'older release: no update row' ($last -match 'update row: shown=False')

Invoke-SelfTest 'newer release v9.9.9, automatic' @('-PreviewUpdate', 'v9.9.9')
Check 'notice for 9.9.9' ($last -match 'update row: shown=True text=\[[^\]]*9\.9\.9')
Check 'update started by itself (get.ps1 from main)' ($last -match 'started=\[download https://raw\.githubusercontent\.com/MisterDeeds/tiberian-sun-extensions/main/get\.ps1\]')
Check "UpdateTried = 9.9.9 $today" ((Get-Saved)['UpdateTried'] -eq "9.9.9 $today")
Check 'other settings still kept' ((Get-Saved)['speed'] -eq '2')

Invoke-SelfTest 'same release again the same day' @('-PreviewUpdate', 'v9.9.9')
Check 'not started twice the same day' ($last -match 'started=\[\]')
Check 'button "Update now" instead' ($last -match 'update button=True')

$h = Get-Saved; $h['AutoUpdate'] = '0'; $h.Remove('UpdateTried'); Set-Saved $h
Invoke-SelfTest 'automatic update switched off' @('-PreviewUpdate', 'v9.9.9')
Check 'box off' ($last -match 'auto update: False')
Check 'notice with button, nothing started' ($last -match 'update row: shown=True' -and $last -match 'update button=True' -and $last -match 'started=\[\]')

$h = Get-Saved; $h['AutoUpdate'] = '1'; $h['LastVersion'] = '1.0.0'; Set-Saved $h
Invoke-SelfTest 'first start after an update from 1.0.0'
Check "note 'updated to $version' with the button for the release notes" ($last -match "update row: shown=True text=\[[^\]]*$([regex]::Escape($version))\.\]" -and $last -match 'news button=True' -and $last -match 'update button=False')
Check 'LastVersion now saved' ((Get-Saved)['LastVersion'] -eq $version)
Invoke-SelfTest 'next start'
Check 'note only once' ($last -match 'update row: shown=False')

"remove:"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $prog 'install.ps1') -Remove -SandboxRoot $sandbox -TargetFolder $prog | ForEach-Object { "    $_" }
Check 'missions removed from the game folder' (@(Get-ChildItem -LiteralPath (Join-Path $sandbox 'GameFolder') -Filter 'TSX*.MAP').Count -eq 0)
Check 'shortcuts removed' (@(Get-ChildItem -LiteralPath (Join-Path $sandbox 'Desktop') -Filter '*.lnk').Count -eq 0)
Check 'settings removed' (-not (Test-Path -LiteralPath $settingsDir))
Check 'Apps entry removed' (-not (Test-Path $appsKey))
Check 'program files removed' (@(Get-ChildItem -LiteralPath $prog -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'install.ps1' }).Count -eq 0)

"get.ps1 through Invoke-Expression, ZIP in the layout of a GitHub release:"
# The tracked files of the working tree in one folder tiberian-sun-extensions-<version>, like the ZIP of a tag.
$top = Join-Path $stage "tiberian-sun-extensions-$version"
foreach ($f in @(& git -C $repoRoot ls-files)) {
    $from = Join-Path $repoRoot $f; $to = Join-Path $top $f
    if (-not (Test-Path -LiteralPath $from)) { continue }
    New-Item -ItemType Directory -Force (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to
}
$zip = Join-Path $stage 'release.zip'
Compress-Archive -Path $top -DestinationPath $zip
$setupBefore = Get-SetupFolders
$getScript = Join-Path $repoRoot 'get.ps1'
$env:TSEXT_SOURCE = $zip; $env:TSEXT_SANDBOX = $sandbox2
$out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '$getScript' -Raw | Invoke-Expression" 2>&1 | ForEach-Object { [string]$_ })
$out | ForEach-Object { "    $_" }
$prog2 = Join-Path $sandbox2 'Programs\TSExtensions'
Check 'installed from the ZIP' (Test-Path -LiteralPath (Join-Path $prog2 'launcher.ps1'))
Check "version.txt = $version" ((Test-Path -LiteralPath (Join-Path $prog2 'version.txt')) -and (Get-Content -LiteralPath (Join-Path $prog2 'version.txt') -Raw).Trim() -eq $version)
Check 'program files equal the repository' (@(@('launcher.ps1', 'install.ps1', 'options.ps1', 'patcher.ps1') | Where-Object { (Get-FileHash (Join-Path $prog2 $_)).Hash -ne (Get-FileHash (Join-Path $repoRoot "src\$_")).Hash }).Count -eq 0)
Check '15 missions in the (sandbox) game folder' (@(Get-ChildItem -LiteralPath (Join-Path $sandbox2 'GameFolder') -Filter 'TSX*.MAP').Count -eq 15)
Check 'shortcuts' (@(Get-ChildItem -LiteralPath (Join-Path $sandbox2 'Desktop') -Filter '*.lnk').Count -eq 1)
Check 'Apps entry' (Test-Path $appsKey)
Check 'launcher opened at the end' (@($out | Where-Object { $_ -like 'START *launcher.ps1*' }).Count -eq 1)
Check 'temporary folder removed' (@(Get-SetupFolders | Where-Object { $_ -notin $setupBefore }).Count -eq 0)
Check 'no error' (-not (($out -join ' ') -match 'unchanged|unveraendert'))

"get.ps1 with a broken ZIP:"
$broken = Join-Path $stage 'broken.zip'
[IO.File]::WriteAllText($broken, 'this is not a zip')
$env:TSEXT_SOURCE = $broken
$out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '$getScript' -Raw | Invoke-Expression; 'AFTER'" 2>&1 | ForEach-Object { [string]$_ })
$out | ForEach-Object { "    $_" }
Check 'message that the game files are unchanged' (($out -join ' ') -match 'unchanged|unveraendert')
Check 'no exception, the window goes on (AFTER printed)' ($out[-1] -eq 'AFTER')
Check 'temporary folder removed' (@(Get-SetupFolders | Where-Object { $_ -notin $setupBefore }).Count -eq 0)
Remove-Item Env:TSEXT_SOURCE, Env:TSEXT_SANDBOX -ErrorAction SilentlyContinue

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $prog2 'install.ps1') -Remove -SandboxRoot $sandbox2 | Out-Null
Check 'second sandbox removed again (Apps entry gone)' (-not (Test-Path $appsKey))
foreach ($d in $sandbox, $sandbox2, $stage) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path -LiteralPath $selfTestFile) { Remove-Item -LiteralPath $selfTestFile -Force }
if ($errors) { "$errors errors"; exit 1 } else { 'install test ok' }
