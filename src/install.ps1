<#
.SYNOPSIS
  Installs (or removes) the Tiberian Sun Extensions on this PC.

.DESCRIPTION
  Copies the tool to %LOCALAPPDATA%\Programs\TSExtensions, builds the campaigns and challenges from the maps of your
  own installation (build-campaigns.ps1, in the Windows language) and copies them into the game folder (TSX*.MAP and
  BATTLEX.INI, which the game adds to its campaign list), and creates the shortcut "Tiberian Sun - Erweiterungen"
  (English Windows: "Tiberian Sun - Extensions") in the Start menu and on the desktop, plus an entry under
  Windows "Apps" for removal. No original game file is changed.
  -Remove deletes all of it again: our files in the game folder, the program folder, shortcuts, settings, the entry.
  For tests: -SandboxRoot puts every user folder (programs, settings, desktop, start menu, registry key name) and the
  mission target below that folder; the game itself is only read.
#>
param(
    [switch]$Remove,
    [string]$TargetFolder = (Join-Path $env:LOCALAPPDATA 'Programs\TSExtensions'),
    [switch]$NoShortcuts,
    [string]$GameDir = '',
    [Parameter(DontShow)][string]$SandboxRoot
)
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
. (Join-Path $src 'tslib.ps1')
. (Join-Path $src 'options.ps1')

$AppData = $env:APPDATA
$DesktopFolder = [Environment]::GetFolderPath('Desktop')
$StartMenu = [Environment]::GetFolderPath('Programs')
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TSExtensions'
if (-not $GameDir) { $GameDir = Find-TSGame }
$MissionTarget = $GameDir
if ($SandboxRoot) {
    $AppData = Join-Path $SandboxRoot 'AppData'; $DesktopFolder = Join-Path $SandboxRoot 'Desktop'; $StartMenu = Join-Path $SandboxRoot 'StartMenu'
    if (-not $PSBoundParameters.ContainsKey('TargetFolder')) { $TargetFolder = Join-Path $SandboxRoot 'Programs\TSExtensions' }
    $MissionTarget = Join-Path $SandboxRoot 'GameFolder'
    $UninstallKey = 'HKCU:\Software\TSExtensionsSandboxTest'
    foreach ($d in $AppData, $DesktopFolder, $StartMenu, $MissionTarget) { New-Item -ItemType Directory -Force $d | Out-Null }
}
$ShortcutName = (Txt 'Tiberian Sun - Extensions' 'Tiberian Sun - Erweiterungen') + '.lnk'
$AllShortcutNames = @('Tiberian Sun - Erweiterungen.lnk', 'Tiberian Sun - Extensions.lnk')
$SettingsFolder = Join-Path $AppData 'TSExtensions'
$ProgramFiles = @('TSLib.cs', 'TSProc.cs', 'TSMap.cs', 'tslib.ps1', 'options.ps1', 'patcher.ps1', 'launcher.ps1', 'build-campaigns.ps1', 'install.ps1', 'missions.json', 'README.txt', 'README.de.txt')

function Remove-OurGameFiles([string]$dir) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return 0 }
    $n = 0
    foreach ($f in Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match '^TSX[A-Z]\d\d\.MAP$' -or $_.Name -eq 'BATTLEX.INI' }) {
        Remove-Item -LiteralPath $f.FullName -Force; $n++
    }
    if (Test-OurRulesFile $dir) { Remove-OurRulesFile $dir; $n++ }
    return $n
}

if ($Remove) {
    $n = Remove-OurGameFiles $MissionTarget
    if (-not $NoShortcuts) {
        foreach ($d in $DesktopFolder, $StartMenu) { foreach ($s in $AllShortcutNames) { $p = Join-Path $d $s; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } } }
        if (Test-Path -LiteralPath $SettingsFolder) { Remove-Item -LiteralPath $SettingsFolder -Recurse -Force }
        if (Test-Path -LiteralPath $UninstallKey) { Remove-Item -LiteralPath $UninstallKey -Recurse -Force }
    }
    if (Test-Path -LiteralPath $TargetFolder) {
        # this script may run from the target folder itself: delete everything we can
        Get-ChildItem -LiteralPath $TargetFolder -Recurse -File | Where-Object { $_.FullName -ne $PSCommandPath } | Remove-Item -Force -ErrorAction SilentlyContinue
        if ($PSCommandPath -notlike "$TargetFolder*") { Remove-Item -LiteralPath $TargetFolder -Recurse -Force -ErrorAction SilentlyContinue }
    }
    (Txt "Removed. Files removed from the game folder: $n" "Entfernt. Dateien aus dem Spielordner entfernt: $n")
    return
}

if (-not $GameDir) { throw (Txt 'Tiberian Sun and Firestorm (Steam) was not found. Install it with Steam first.' 'Tiberian Sun und Feuersturm (Steam) wurde nicht gefunden. Bitte zuerst mit Steam installieren.') }
(Txt "Game: $GameDir" "Spiel: $GameDir")
. (Join-Path $src 'patcher.ps1')
if (-not (Test-GameVersion $GameDir)) { Txt 'Note: unknown Game.exe version - the random map size patch will be skipped; everything else works.' 'Hinweis: unbekannte Game.exe-Version - der Patch für die Zufallskarten-Grösse wird übersprungen, alles andere funktioniert.' }

# program files
New-Item -ItemType Directory -Force $TargetFolder | Out-Null
foreach ($f in $ProgramFiles) {
    $p = Join-Path $src $f
    if (Test-Path -LiteralPath $p) { if ((Resolve-Path $p).Path -ne (Join-Path $TargetFolder $f)) { Copy-Item -LiteralPath $p -Destination (Join-Path $TargetFolder $f) -Force } }
}
$docs = Join-Path $src '..\docs'
if (Test-Path -LiteralPath $docs) { Copy-Item -LiteralPath $docs -Destination (Join-Path $TargetFolder 'docs') -Recurse -Force }

# missions, built from the player's own maps
(Txt 'Building the campaigns from your maps ...' 'Die Kampagnen werden aus deinen Karten gebaut ...')
$missionDir = Join-Path $TargetFolder 'missions'
& (Join-Path $TargetFolder 'build-campaigns.ps1') -OutDir $missionDir -GameDir $GameDir | ForEach-Object { "  $_" }
$copied = 0
foreach ($f in Get-ChildItem -LiteralPath $missionDir -File | Where-Object { $_.Name -like 'TSX*.MAP' -or $_.Name -eq 'BATTLEX.INI' }) {
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $MissionTarget $f.Name) -Force; $copied++
}
(Txt "$copied files copied into the game folder." "$copied Dateien in den Spielordner kopiert.")

# shortcuts and the entry in Windows "Apps"
if (-not $NoShortcuts) {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $icon = Join-Path $GameDir 'Firestorm.ico'; if (-not (Test-Path -LiteralPath $icon)) { $icon = Join-Path $GameDir 'Game.exe' }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($d in $DesktopFolder, $StartMenu) {
        foreach ($s in $AllShortcutNames) { $p = Join-Path $d $s; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }
        $lnk = $shell.CreateShortcut((Join-Path $d $ShortcutName))
        $lnk.TargetPath = $ps
        $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $TargetFolder 'launcher.ps1')`""
        $lnk.WorkingDirectory = $TargetFolder
        $lnk.IconLocation = $icon
        $lnk.Description = Txt 'Tiberian Sun with bigger worlds, new campaigns and more options' 'Tiberian Sun mit grösseren Welten, neuen Kampagnen und mehr Optionen'
        $lnk.Save()
    }
    New-Item -Path $UninstallKey -Force | Out-Null
    $uninst = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $TargetFolder 'install.ps1')`" -Remove"
    foreach ($kv in @(@('DisplayName', (Txt 'Tiberian Sun - Extensions' 'Tiberian Sun - Erweiterungen')), @('DisplayVersion', '1.0.0'), @('Publisher', 'Fan project'),
            @('InstallLocation', $TargetFolder), @('UninstallString', $uninst), @('DisplayIcon', $icon), @('NoModify', 1), @('NoRepair', 1))) {
        if ($kv[1] -is [int]) { New-ItemProperty -Path $UninstallKey -Name $kv[0] -Value $kv[1] -PropertyType DWord -Force | Out-Null }
        else { New-ItemProperty -Path $UninstallKey -Name $kv[0] -Value $kv[1] -PropertyType String -Force | Out-Null }
    }
    (Txt "Shortcut created: $ShortcutName (desktop and Start menu)" "Verknüpfung erstellt: $ShortcutName (Desktop und Startmenü)")
}
(Txt 'Done.' 'Fertig.')
