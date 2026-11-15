# Installs and removes the extensions for real, but into a sandbox folder (programs, settings, desktop, start menu,
# registry key name and the mission target are below the sandbox; the game itself is only read). Then checks the
# launcher in its self-test mode (window built, presets clicked, closed again).
$ErrorActionPreference = 'Stop'
$sandbox = Join-Path $env:TEMP 'tsext-sandbox'
if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
$install = Join-Path $PSScriptRoot '..\src\install.ps1'
$errors = 0
function Check([string]$what, [bool]$ok) { if ($ok) { "  ok   $what" } else { "  FAIL $what"; $script:errors++ } }

"install:"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $install -SandboxRoot $sandbox | ForEach-Object { "    $_" }
$prog = Join-Path $sandbox 'Programs\TSExtensions'
Check 'launcher.ps1 installed' (Test-Path -LiteralPath (Join-Path $prog 'launcher.ps1'))
Check 'missions built (15 maps)' (@(Get-ChildItem -LiteralPath (Join-Path $prog 'missions') -Filter 'TSX*.MAP').Count -eq 15)
Check 'missions copied to the (sandbox) game folder' (@(Get-ChildItem -LiteralPath (Join-Path $sandbox 'GameFolder') -Filter 'TSX*.MAP').Count -eq 15)
Check 'BATTLEX.INI copied' (Test-Path -LiteralPath (Join-Path $sandbox 'GameFolder\BATTLEX.INI'))
Check 'desktop shortcut' (@(Get-ChildItem -LiteralPath (Join-Path $sandbox 'Desktop') -Filter '*.lnk').Count -eq 1)
Check 'start menu shortcut' (@(Get-ChildItem -LiteralPath (Join-Path $sandbox 'StartMenu') -Filter '*.lnk').Count -eq 1)
Check 'uninstall entry (sandbox key)' (Test-Path 'HKCU:\Software\TSExtensionsSandboxTest')

"launcher self-test:"
$st = Join-Path $env:TEMP 'tsext-selftest.txt'
if (Test-Path -LiteralPath $st) { Remove-Item -LiteralPath $st -Force }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $prog 'launcher.ps1') -SelfTest -DryRun
Check 'self-test ran' (Test-Path -LiteralPath $st)
if (Test-Path -LiteralPath $st) { Get-Content -LiteralPath $st | ForEach-Object { "    $_" } }

"remove:"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $prog 'install.ps1') -Remove -SandboxRoot $sandbox -TargetFolder $prog | ForEach-Object { "    $_" }
Check 'missions removed from the game folder' (@(Get-ChildItem -LiteralPath (Join-Path $sandbox 'GameFolder') -Filter 'TSX*.MAP').Count -eq 0)
Check 'shortcuts removed' (@(Get-ChildItem -LiteralPath (Join-Path $sandbox 'Desktop') -Filter '*.lnk').Count -eq 0)
Check 'uninstall entry removed' (-not (Test-Path 'HKCU:\Software\TSExtensionsSandboxTest'))
Check 'program files removed' (@(Get-ChildItem -LiteralPath $prog -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'install.ps1' }).Count -eq 0)
Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
if ($errors) { "$errors errors"; exit 1 } else { 'install test ok' }
