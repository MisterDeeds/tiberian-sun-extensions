<#
.SYNOPSIS
  Start window of the Tiberian Sun Extensions: choose options, start the game, see the campaigns.

.DESCRIPTION
  "Start game" writes the rules options as EXPAND99.MIX into the game folder (a changed copy of your own
  FIRESTRM.INI), sets the resolution in SUN.INI if wanted, starts Game.exe, applies the memory patches (random map
  size, terrain sliders and Tiberium, repairs of the computer opponents) and puts everything back when the game ends. "Start original" starts the game without any change.
  -DryRun: everything except starting the game. -SelfTest: builds the window, clicks through the presets and tabs,
  checks the generated rules file and closes again (for tests/test-install.ps1).
  Updates (installed copy only, version.txt): at every start a background request asks GitHub for the newest release;
  if it is newer, "Update automatically" (on by default) downloads get.ps1 and runs it at once - at most once per
  version and day, never while the game runs - otherwise the button "Update now" does. The installer opens the new
  launcher, which then says "Updated to version x.y.z" once, with a button for the release notes.
#>
param(
    [switch]$DryRun,
    [switch]$SelfTest,
    [string]$GameDir = '',
    [Parameter(DontShow)][switch]$AutoStart,
    # For tests: newest release as if GitHub had reported it ("v9.9.9"), and a settings folder of their own.
    [Parameter(DontShow)][string]$PreviewUpdate = '',
    [Parameter(DontShow)][string]$PreviewImage = '',   # with -SelfTest: picture of the window (README screenshots)
    [Parameter(DontShow)][string]$SettingsDir = (Join-Path $env:APPDATA 'TSExtensions')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tslib.ps1')
. (Join-Path $PSScriptRoot 'options.ps1')
. (Join-Path $PSScriptRoot 'patcher.ps1')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Repo = 'MisterDeeds/tiberian-sun-extensions'
# Version: version.txt of the installed copy (written by install.ps1) or, in the repository, ..\CHANGELOG.md. Only an
# installed copy looks for updates.
$Version = ''
$Installed = $false
try { $v = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'version.txt') -Raw -ErrorAction Stop).Trim(); if ($v -match '^\d+\.\d+\.\d+$') { $Version = $v; $Installed = $true } } catch { }
if (-not $Version) { try { $m = Select-String -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'CHANGELOG.md') -Pattern '^## (\d+\.\d+\.\d+)' -ErrorAction Stop | Select-Object -First 1; if ($m) { $Version = $m.Matches[0].Groups[1].Value } } catch { } }
if (-not $GameDir) { $GameDir = Find-TSGame }
$SettingsFile = Join-Path $SettingsDir 'settings.json'
$BuiltList = Join-Path $PSScriptRoot 'missions\missions-built.json'

function Read-SettingsFile {
    $s = [ordered]@{}
    if (Test-Path -LiteralPath $SettingsFile) {
        try { $j = Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $s[$p.Name] = [string]$p.Value } } catch { }
    }
    return $s
}
function Get-Settings {
    $s = Get-DefaultSettings
    $f = Read-SettingsFile
    foreach ($k in $f.Keys) { $s[$k] = $f[$k] }
    return $s
}
# Writes the given values and keeps the others (options, AutoUpdate, LastVersion, UpdateTried).
function Save-Settings($s) {
    $all = Read-SettingsFile
    foreach ($k in $s.Keys) { $all[$k] = [string]$s[$k] }
    New-Item -ItemType Directory -Force $SettingsDir | Out-Null
    ([pscustomobject]$all) | ConvertTo-Json | Set-Content -LiteralPath $SettingsFile -Encoding UTF8
}
$RestoreFile = Join-Path $SettingsDir 'restore-resolution.txt'
$SpeedRestoreFile = Join-Path $SettingsDir 'restore-speed.txt'

# After the game: rules file away, resolution back to what it was (a game started from Steam must not use a
# resolution that needs our sidebar fix).
function Restore-AfterGame {
    Remove-OurRulesFile $GameDir
    if (Test-Path -LiteralPath $RestoreFile) {
        $r = (Get-Content -LiteralPath $RestoreFile -TotalCount 1).Trim()
        if ($r -match '^\d+x\d+$') { Set-GameResolution $GameDir $r }
        Remove-Item -LiteralPath $RestoreFile -Force
    }
    if (Test-Path -LiteralPath $SpeedRestoreFile) {
        $v = (Get-Content -LiteralPath $SpeedRestoreFile -TotalCount 1).Trim()
        if ($v -match '^\d+$') { Set-GameSpeed $GameDir $v }
        Remove-Item -LiteralPath $SpeedRestoreFile -Force
    }
}

function Get-GameProcess {
    Get-Process -Name 'game' -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -and $_.Path.StartsWith($GameDir, [StringComparison]::OrdinalIgnoreCase) } catch { $false } } | Select-Object -First 1
}

# --- colors and fonts --------------------------------------------------------------------------------------------
$cBack = [System.Drawing.Color]::FromArgb(24, 28, 24)
$cPanel = [System.Drawing.Color]::FromArgb(34, 40, 34)
$cText = [System.Drawing.Color]::FromArgb(222, 230, 214)
$cDim = [System.Drawing.Color]::FromArgb(150, 165, 140)
$cAccent = [System.Drawing.Color]::FromArgb(122, 196, 74)
$cGold = [System.Drawing.Color]::FromArgb(222, 180, 70)
$fBase = New-Object System.Drawing.Font 'Segoe UI', 9.5
$fBold = New-Object System.Drawing.Font 'Segoe UI', 9.5, ([System.Drawing.FontStyle]::Bold)
$fTitle = New-Object System.Drawing.Font 'Segoe UI', 17, ([System.Drawing.FontStyle]::Bold)
$fGroup = New-Object System.Drawing.Font 'Segoe UI', 10.5, ([System.Drawing.FontStyle]::Bold)

$form = New-Object System.Windows.Forms.Form
$form.Text = (Txt 'Tiberian Sun - Extensions' 'Tiberian Sun - Erweiterungen') + " $Version"
$form.Size = New-Object System.Drawing.Size 860, 760
$form.MinimumSize = New-Object System.Drawing.Size 760, 640
$form.StartPosition = 'CenterScreen'
$form.BackColor = $cBack; $form.ForeColor = $cText; $form.Font = $fBase

$title = New-Object System.Windows.Forms.Label
$title.Text = Txt 'Tiberian Sun - Extensions' 'Tiberian Sun - Erweiterungen'
$title.Font = $fTitle; $title.ForeColor = $cAccent; $title.AutoSize = $true; $title.Location = New-Object System.Drawing.Point 18, 12
$form.Controls.Add($title)
$sub = New-Object System.Windows.Forms.Label
$sub.AutoSize = $false; $sub.UseMnemonic = $false; $sub.Size = New-Object System.Drawing.Size 600, 22; $sub.Location = New-Object System.Drawing.Point 20, 50; $sub.ForeColor = $cDim
$sub.Anchor = 'Top, Left, Right'
$form.Controls.Add($sub)

# --- updates (top right) -----------------------------------------------------------------------------------------
# Hidden until there is something to say: a newer release on GitHub (installed at once with "Update automatically",
# otherwise with the button) or, after an update, the new version with a button for its release notes.
$updateLabel = New-Object System.Windows.Forms.Label
$updateLabel.AutoSize = $false; $updateLabel.UseMnemonic = $false; $updateLabel.TextAlign = 'MiddleRight'
$updateLabel.Size = New-Object System.Drawing.Size 300, 40; $updateLabel.Location = New-Object System.Drawing.Point 390, 8
$updateLabel.Anchor = 'Top, Right'; $updateLabel.ForeColor = $cGold; $updateLabel.Visible = $false
$form.Controls.Add($updateLabel)
$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = Txt 'Update now' 'Jetzt aktualisieren'
$btnUpdate.Size = New-Object System.Drawing.Size 130, 32; $btnUpdate.Location = New-Object System.Drawing.Point 700, 12
$btnUpdate.Anchor = 'Top, Right'; $btnUpdate.FlatStyle = 'Flat'; $btnUpdate.ForeColor = $cGold; $btnUpdate.Visible = $false
$form.Controls.Add($btnUpdate)
$btnNews = New-Object System.Windows.Forms.Button
$btnNews.Text = Txt 'What is new?' 'Was ist neu?'
$btnNews.Size = $btnUpdate.Size; $btnNews.Location = $btnUpdate.Location
$btnNews.Anchor = 'Top, Right'; $btnNews.FlatStyle = 'Flat'; $btnNews.ForeColor = $cGold; $btnNews.Visible = $false
$form.Controls.Add($btnNews)
# Install new versions by themselves (settings.json AutoUpdate, on unless "0"; only for an installed copy).
$chkAutoUpdate = New-Object System.Windows.Forms.CheckBox
$chkAutoUpdate.Text = Txt 'Update automatically' 'Automatisch aktualisieren'
$chkAutoUpdate.Size = New-Object System.Drawing.Size 200, 22; $chkAutoUpdate.Location = New-Object System.Drawing.Point 630, 50
$chkAutoUpdate.Anchor = 'Top, Right'; $chkAutoUpdate.ForeColor = $cDim; $chkAutoUpdate.CheckAlign = 'MiddleRight'; $chkAutoUpdate.TextAlign = 'MiddleRight'
$chkAutoUpdate.Visible = $Installed
$form.Controls.Add($chkAutoUpdate)
$updateTips = New-Object System.Windows.Forms.ToolTip
$updateTips.AutoPopDelay = 20000
$updateTips.SetToolTip($chkAutoUpdate, (Txt 'At every start the launcher asks GitHub for the newest version. A newer one is installed at once (your settings stay) and the launcher opens again.' 'Bei jedem Start fragt der Starter GitHub nach der neusten Version. Eine neuere wird gleich installiert (deine Einstellungen bleiben) und der Starter öffnet sich wieder.'))

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point 14, 78; $tabs.Size = New-Object System.Drawing.Size 816, 560
$tabs.Anchor = 'Top, Bottom, Left, Right'
$form.Controls.Add($tabs)

$status = New-Object System.Windows.Forms.Label
$status.AutoSize = $false; $status.Size = New-Object System.Drawing.Size 520, 44; $status.Location = New-Object System.Drawing.Point 18, 650
$status.Anchor = 'Bottom, Left, Right'; $status.ForeColor = $cDim
$form.Controls.Add($status)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = Txt 'Start game' 'Spiel starten'
$btnStart.Size = New-Object System.Drawing.Size 160, 42; $btnStart.Location = New-Object System.Drawing.Point 670, 648
$btnStart.Anchor = 'Bottom, Right'; $btnStart.FlatStyle = 'Flat'; $btnStart.BackColor = $cAccent; $btnStart.ForeColor = [System.Drawing.Color]::Black; $btnStart.Font = $fBold
$form.Controls.Add($btnStart)
$btnOriginal = New-Object System.Windows.Forms.Button
$btnOriginal.Text = Txt 'Start original' 'Original starten'
$btnOriginal.Size = New-Object System.Drawing.Size 130, 42; $btnOriginal.Location = New-Object System.Drawing.Point 530, 648
$btnOriginal.Anchor = 'Bottom, Right'; $btnOriginal.FlatStyle = 'Flat'; $btnOriginal.ForeColor = $cText
$form.Controls.Add($btnOriginal)

function New-Tab([string]$text) {
    $p = New-Object System.Windows.Forms.TabPage
    $p.Text = $text; $p.BackColor = $cPanel; $p.ForeColor = $cText; $p.AutoScroll = $true
    $tabs.TabPages.Add($p); return $p
}

# --- tab 1: play -------------------------------------------------------------------------------------------------
$tabPlay = New-Tab (Txt 'Play' 'Spielen')
$settings = Get-Settings
$combos = @{}
$y = 12
$lp = New-Object System.Windows.Forms.Label
$lp.Text = Txt 'Presets:' 'Vorlagen:'; $lp.Font = $fBold; $lp.AutoSize = $true; $lp.Location = New-Object System.Drawing.Point 14, ($y + 6)
$tabPlay.Controls.Add($lp)
$x = 90
$presetButtons = @()
foreach ($pn in (Get-Presets).Keys) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $pn; $b.AutoSize = $true; $b.FlatStyle = 'Flat'; $b.ForeColor = $cGold
    $b.Location = New-Object System.Drawing.Point $x, $y
    $b.Tag = $pn
    $b.Add_Click({
            $p = (Get-Presets)[$this.Tag]
            foreach ($o in Get-OptionCatalog) {
                $v = if ($p.ContainsKey($o.Id)) { $p[$o.Id] } else { $o.Default }
                $cb = $combos[$o.Id]
                for ($i = 0; $i -lt $cb.Items.Count; $i++) { if ($cb.Tag[$i] -eq $v) { $cb.SelectedIndex = $i } }
            }
            $status.Text = (Txt 'Preset: ' 'Vorlage: ') + $this.Tag
        })
    $tabPlay.Controls.Add($b); $presetButtons += $b
    $x += [System.Windows.Forms.TextRenderer]::MeasureText($pn, $fBase).Width + 30
}
$y += 46
$group = ''
$col = 0
$colX = @(14, 410)
$rowY = @($y, $y)
foreach ($o in Get-OptionCatalog) {
    if ($o.Group -ne $group) {
        $group = $o.Group
        # groups: Economy left, Combat + Enemies right, World + Display left/right
        $col = switch -regex ($group) { '^(Economy|Wirtschaft)$' { 0 } '^(Combat|Kampf|Enemies|Gegner)$' { 1 } '^(World|Welt)$' { 0 } default { 1 } }
        $g = New-Object System.Windows.Forms.Label
        $g.Text = $group; $g.Font = $fGroup; $g.ForeColor = $cAccent; $g.AutoSize = $true
        $g.Location = New-Object System.Drawing.Point $colX[$col], ($rowY[$col] + 6)
        $tabPlay.Controls.Add($g); $rowY[$col] += 32
    }
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $o.Label; $l.AutoSize = $false; $l.UseMnemonic = $false; $l.Size = New-Object System.Drawing.Size 186, 22
    $l.Location = New-Object System.Drawing.Point $colX[$col], ($rowY[$col] + 3)
    $tabPlay.Controls.Add($l)
    $cb = New-Object System.Windows.Forms.ComboBox
    $cb.DropDownStyle = 'DropDownList'; $cb.Size = New-Object System.Drawing.Size 192, 24; $cb.DropDownWidth = 360
    $cb.Location = New-Object System.Drawing.Point ($colX[$col] + 188), $rowY[$col]
    $vals = @()
    foreach ($c in $o.Choices) { [void]$cb.Items.Add($c[1]); $vals += $c[0] }
    $cb.Tag = $vals
    $cur = if ($settings.ContainsKey($o.Id)) { [string]$settings[$o.Id] } else { $o.Default }
    $idx = [array]::IndexOf($vals, $cur); if ($idx -lt 0) { $idx = [array]::IndexOf($vals, $o.Default) }
    $cb.SelectedIndex = [math]::Max(0, $idx)
    $tabPlay.Controls.Add($cb)
    $combos[$o.Id] = $cb
    $rowY[$col] += 30
}
$hint = New-Object System.Windows.Forms.Label
$hint.AutoSize = $false; $hint.Size = New-Object System.Drawing.Size 770, 64
$hint.Location = New-Object System.Drawing.Point 14, ([math]::Max($rowY[0], $rowY[1]) + 12)
$hint.ForeColor = $cDim
$hint.Text = Txt 'In the game, click "Firestorm" on the first screen. Huge worlds: Skirmish > Multiplayer map > Random map, map width and height "Very large" (up to 235 x 235 cells with "huge"; terrain and Tiberium as chosen above, the sliders there can still be moved). The options apply to skirmish games and campaigns; everything is undone when the game ends, so a game started from Steam is always the original.' 'Im Spiel auf dem ersten Bildschirm "Feuersturm" anklicken. Riesige Welten: Gefecht > Mehrspieler-Karte > Zufallskarte, Kartenbreite und -höhe "Sehr groß" (mit "riesig" bis 235 × 235 Felder; Gelände und Tiberium wie oben gewählt, die Regler dort lassen sich weiter verschieben). Die Optionen gelten für Gefechte und Kampagnen; nach dem Spiel ist alles wieder wie vorher, ein Start über Steam ist immer das Original.'
$tabPlay.Controls.Add($hint)

function Get-UiSettings {
    $s = @{}
    foreach ($k in $combos.Keys) { $cb = $combos[$k]; $s[$k] = [string]$cb.Tag[$cb.SelectedIndex] }
    return $s
}

# --- tab 2: campaigns --------------------------------------------------------------------------------------------
$tabCamp = New-Tab (Txt 'Campaigns and missions' 'Kampagnen und Missionen')
$ci = New-Object System.Windows.Forms.Label
$ci.AutoSize = $false; $ci.Size = New-Object System.Drawing.Size 770, 62; $ci.Location = New-Object System.Drawing.Point 14, 10
$ci.Text = Txt 'New campaigns and challenges, built from the maps of your own game. In the game: Firestorm > New campaign > choose one of the entries starting with "Extension" or "Challenge". Difficulty (easy / normal / hard) changes the size and frequency of the enemy attack waves.' 'Neue Kampagnen und Herausforderungen, gebaut aus den Karten deines eigenen Spiels. Im Spiel: Feuersturm > Neue Kampagne > einen Eintrag mit "Erweiterung" oder "Herausforderung" wählen. Der Schwierigkeitsgrad (leicht / normal / schwer) bestimmt Grösse und Häufigkeit der feindlichen Angriffswellen.'
$tabCamp.Controls.Add($ci)
$lv = New-Object System.Windows.Forms.ListView
$lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.Location = New-Object System.Drawing.Point 14, 78; $lv.Size = New-Object System.Drawing.Size 770, 400
$lv.Anchor = 'Top, Bottom, Left, Right'; $lv.BackColor = $cBack; $lv.ForeColor = $cText
[void]$lv.Columns.Add((Txt 'Campaign' 'Kampagne'), 300); [void]$lv.Columns.Add((Txt 'Mission' 'Mission'), 180); [void]$lv.Columns.Add((Txt 'Map' 'Karte'), 120); [void]$lv.Columns.Add((Txt 'File' 'Datei'), 110)
$tabCamp.Controls.Add($lv)
function Update-CampaignList {
    $lv.Items.Clear()
    $cat = $null
    try { $cat = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'missions.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    $built = @(); if (Test-Path -LiteralPath $BuiltList) { $built = @(Get-Content -LiteralPath $BuiltList -Raw -Encoding UTF8 | ConvertFrom-Json) }
    $lang = if ($script:UiGerman) { 'de' } else { 'en' }
    if ($cat) {
        foreach ($c in $cat.campaigns) {
            foreach ($m in $c.missions) {
                $it = New-Object System.Windows.Forms.ListViewItem ([string]$c.name.$lang)
                [void]$it.SubItems.Add([string]$m.name.$lang); [void]$it.SubItems.Add([string]$m.map); [void]$it.SubItems.Add("$($m.file).MAP")
                $inGame = $GameDir -and (Test-Path -LiteralPath (Join-Path $GameDir "$($m.file).MAP"))
                if (-not $inGame) { $it.ForeColor = $cDim }
                [void]$lv.Items.Add($it)
            }
        }
    }
}
$btnRebuild = New-Object System.Windows.Forms.Button
$btnRebuild.Text = Txt 'Rebuild missions' 'Missionen neu bauen'; $btnRebuild.AutoSize = $true; $btnRebuild.FlatStyle = 'Flat'
$btnRebuild.Location = New-Object System.Drawing.Point 14, 486; $btnRebuild.Anchor = 'Bottom, Left'
$btnRebuild.Add_Click({
        $status.Text = Txt 'Building missions ...' 'Missionen werden gebaut ...'; $form.Refresh()
        try { Install-Missions; $status.Text = Txt 'Missions rebuilt and copied into the game folder.' 'Missionen neu gebaut und in den Spielordner kopiert.' }
        catch { $status.Text = (Txt 'Error: ' 'Fehler: ') + $_.Exception.Message }
        Update-CampaignList
    })
$tabCamp.Controls.Add($btnRebuild)

# Builds the missions into the program folder and copies them into the game folder.
function Install-Missions {
    $out = Join-Path $PSScriptRoot 'missions'
    & (Join-Path $PSScriptRoot 'build-campaigns.ps1') -OutDir $out -GameDir $GameDir | Out-Null
    foreach ($f in Get-ChildItem -LiteralPath $out -File | Where-Object { $_.Name -like 'TSX*.MAP' -or $_.Name -eq 'BATTLEX.INI' }) {
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $GameDir $f.Name) -Force
    }
}

# --- tab 3: info -------------------------------------------------------------------------------------------------
$tabInfo = New-Tab 'Info'
$info = New-Object System.Windows.Forms.TextBox
$info.Multiline = $true; $info.ReadOnly = $true; $info.ScrollBars = 'Vertical'; $info.BackColor = $cBack; $info.ForeColor = $cText
$info.Location = New-Object System.Drawing.Point 14, 14; $info.Size = New-Object System.Drawing.Size 770, 420; $info.Anchor = 'Top, Bottom, Left, Right'
$tabInfo.Controls.Add($info)
$btnReadme = New-Object System.Windows.Forms.Button
$btnReadme.Text = Txt 'Open README' 'README öffnen'; $btnReadme.AutoSize = $true; $btnReadme.FlatStyle = 'Flat'
$btnReadme.Location = New-Object System.Drawing.Point 14, 446; $btnReadme.Anchor = 'Bottom, Left'
$btnReadme.Add_Click({ $r = Join-Path $PSScriptRoot $(if ($script:UiGerman) { 'README.de.txt' } else { 'README.txt' }); if (Test-Path -LiteralPath $r) { Start-Process notepad.exe -ArgumentList "`"$r`"" } })
$tabInfo.Controls.Add($btnReadme)
$btnFolder = New-Object System.Windows.Forms.Button
$btnFolder.Text = Txt 'Open game folder' 'Spielordner öffnen'; $btnFolder.AutoSize = $true; $btnFolder.FlatStyle = 'Flat'
$btnFolder.Location = New-Object System.Drawing.Point 150, 446; $btnFolder.Anchor = 'Bottom, Left'
$btnFolder.Add_Click({ if ($GameDir) { Start-Process explorer.exe -ArgumentList "`"$GameDir`"" } })
$tabInfo.Controls.Add($btnFolder)

$versionOk = $false
if ($GameDir) { try { $versionOk = Test-GameVersion $GameDir } catch { } }
$info.Text = @(
    (Txt 'Tiberian Sun - Extensions' 'Tiberian Sun - Erweiterungen') + " $Version"
    ''
    (Txt 'Game folder: ' 'Spielordner: ') + $(if ($GameDir) { $GameDir } else { Txt 'not found' 'nicht gefunden' })
    'Game.exe: ' + $(if ($versionOk) { Txt '2.03 TUC (Steam) - memory patches available' '2.03 TUC (Steam) - Speicher-Patches verfügbar' } else { Txt 'unknown version - memory patches (random map size) are skipped' 'unbekannte Version - Speicher-Patches (Zufallskarten-Grösse) werden übersprungen' })
    (Txt 'Settings: ' 'Einstellungen: ') + $SettingsFile
    ''
    (Txt 'What changes where:' 'Was wo geändert wird:')
    (Txt '- Rules options: EXPAND99.MIX in the game folder while the game runs (a changed copy of your FIRESTRM.INI; Firestorm mode).' '- Regel-Optionen: EXPAND99.MIX im Spielordner, solange das Spiel läuft (geänderte Kopie deiner FIRESTRM.INI; Feuersturm-Modus).')
    (Txt '- Random maps (size, terrain sliders, Tiberium), repairs of the computer opponents: memory of the running game only.' '- Zufallskarten (Grösse, Gelände-Regler, Tiberium), Reparaturen der Computergegner: nur der Arbeitsspeicher des laufenden Spiels.')
    (Txt '- Campaigns: TSX*.MAP and BATTLEX.INI in the game folder (removed by the uninstaller).' '- Kampagnen: TSX*.MAP und BATTLEX.INI im Spielordner (der Deinstaller entfernt sie).')
    (Txt '- Resolution and game speed: [Video] and [Options] in SUN.INI, only if you choose it, set back after the game.' '- Auflösung und Spieltempo: [Video] und [Options] in SUN.INI, nur wenn du es wählst, nach dem Spiel zurückgestellt.')
    ''
    (Txt 'Updates: at every start the launcher asks GitHub for the newest version and, with "Update automatically", installs it by itself (never while the game runs; your settings stay).' 'Updates: Bei jedem Start fragt der Starter GitHub nach der neusten Version und installiert sie mit "Automatisch aktualisieren" von selbst (nie während das Spiel läuft; deine Einstellungen bleiben).')
    ''
    (Txt 'Single player only. Online and LAN games stay untouched when started without this tool.' 'Nur für das Einzelspiel. Online- und LAN-Spiele bleiben unberührt, wenn sie ohne dieses Werkzeug gestartet werden.')
) -join "`r`n"

# --- start the game ----------------------------------------------------------------------------------------------
$script:watch = $null
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$script:patched = $false
$script:started = $null
$script:runSettings = $null
$timer.Add_Tick({
        $p = Get-GameProcess
        if ($p) {
            if (-not $script:patched -and $versionOk -and ((Get-Date) - $script:started).TotalSeconds -gt 3) {
                try {
                    $gp = New-Object TSExt.GameProcess $p
                    $res = Invoke-GamePatches $gp $script:runSettings
                    $gp.Dispose()
                    $script:patched = $true
                    if ($res.Count -gt 0) { $status.Text = (Txt 'Game running. Patches: ' 'Spiel läuft. Patches: ') + ($res -join ', ') }
                }
                catch { $status.Text = (Txt 'Patch failed: ' 'Patch fehlgeschlagen: ') + $_.Exception.Message; $script:patched = $true }
            }
            return
        }
        if (((Get-Date) - $script:started).TotalSeconds -lt 20) { return }   # still starting
        $timer.Stop()
        Restore-AfterGame
        $form.WindowState = 'Normal'; $form.Show(); $form.Activate()
        $status.Text = Txt 'Game ended. The rules file has been removed again.' 'Spiel beendet. Die Regeldatei ist wieder entfernt.'
        $btnStart.Enabled = $true; $btnOriginal.Enabled = $true
    })

function Start-TheGame([bool]$withExtensions) {
    if (-not $GameDir) { [System.Windows.Forms.MessageBox]::Show((Txt 'Tiberian Sun was not found (Steam).' 'Tiberian Sun wurde nicht gefunden (Steam).')) | Out-Null; return }
    if (Get-GameProcess) { $status.Text = Txt 'The game is already running.' 'Das Spiel läuft bereits.'; return }
    $s = Get-UiSettings
    Save-Settings $s
    Remove-OurRulesFile $GameDir
    if ($withExtensions) {
        if (Test-RulesChanged $s) {
            if ($null -ne (Test-OurRulesFile $GameDir) -and -not (Test-OurRulesFile $GameDir)) {
                $status.Text = Txt 'There is an EXPAND99.MIX of another mod in the game folder - rules options skipped.' 'Im Spielordner liegt eine EXPAND99.MIX eines anderen Mods - Regel-Optionen übersprungen.'
            }
            else {
                $files = Open-TSFiles $GameDir; $files.UseLooseFiles = $false
                Write-RulesMix $GameDir (New-RulesFile $files $s)
            }
        }
        $speedBefore = Get-GameSpeed $GameDir
        if ($s['speed'] -and $s['speed'] -ne 'keep' -and $speedBefore -ne $s['speed']) {
            if ($speedBefore) {
                New-Item -ItemType Directory -Force $SettingsDir | Out-Null
                Set-Content -LiteralPath $SpeedRestoreFile -Value $speedBefore -Encoding ASCII   # back to this when the game ends
            }
            Set-GameSpeed $GameDir $s['speed']
        }
        $target = Resolve-Resolution $s['resolution']
        if ($target) {
            # Without our sidebar fix (unknown Game.exe) high screens crash the game: stay at a safe resolution.
            if (-not $versionOk -and [int]$target.Split('x')[1] -gt $script:SafeHeightWithoutFix) { $target = '1920x1080' }
            $before = Get-GameResolution $GameDir
            if ($before -and $before -ne $target) {
                Set-Content -LiteralPath $RestoreFile -Value $before -Encoding ASCII   # back to this when the game ends
                Set-GameResolution $GameDir $target
            }
        }
    }
    $script:runSettings = if ($withExtensions) { $s } else { @{} }
    $script:patched = $false
    if ($DryRun) { $status.Text = 'DryRun: ' + (Txt 'files prepared, game not started.' 'Dateien vorbereitet, Spiel nicht gestartet.'); Restore-AfterGame; return }
    $psi = New-Object System.Diagnostics.ProcessStartInfo (Join-Path $GameDir 'Game.exe')
    $psi.WorkingDirectory = $GameDir; $psi.UseShellExecute = $false
    [void][System.Diagnostics.Process]::Start($psi)
    $script:started = Get-Date
    $btnStart.Enabled = $false; $btnOriginal.Enabled = $false
    $status.Text = Txt 'Game starting ... (click "Firestorm" in the game)' 'Spiel startet ... (im Spiel "Feuersturm" anklicken)'
    $form.WindowState = 'Minimized'
    $timer.Start()
}
$btnStart.Add_Click({ Start-TheGame $true })
$btnOriginal.Add_Click({ Start-TheGame $false })

# --- updates -----------------------------------------------------------------------------------------------------
$script:saved = Read-SettingsFile
$chkAutoUpdate.Checked = ($script:saved['AutoUpdate'] -ne '0')
$GetScriptUrl = "https://raw.githubusercontent.com/$Repo/main/get.ps1"
$UpdateFile = Join-Path ([IO.Path]::GetTempPath()) 'tiberian-sun-extensions-update.ps1'
# Version and day of the last automatic update ("1.2.0 2026-11-16"): at most one try per version and day, so that a
# failing update cannot run again and again.
$script:UpdateTried = [string]$script:saved['UpdateTried']
$script:UpdateLog = New-Object System.Collections.Generic.List[string]   # what the self-test would have started

function Save-UpdateState {
    $u = @{ AutoUpdate = $(if ($chkAutoUpdate.Checked) { '1' } else { '0' }) }
    if ($Installed) { $u['LastVersion'] = $Version }
    if ($script:UpdateTried) { $u['UpdateTried'] = $script:UpdateTried }
    try { Save-Settings $u } catch { }
}
# Downloads get.ps1 and runs it as a file in a window of its own (it waits for Enter only after an error), then closes
# the launcher once that window really runs; the installer opens the new one. Settings stay in %APPDATA%\TSExtensions.
function Start-Update {
    Save-UpdateState
    if ($SelfTest) { $script:UpdateLog.Add("download $GetScriptUrl"); return }
    try {
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $GetScriptUrl -OutFile $UpdateFile -UseBasicParsing -Headers @{ 'User-Agent' = 'tiberian-sun-extensions-launcher' } -TimeoutSec 30
    }
    catch {
        $updateLabel.Text = (Txt 'The update could not be downloaded: {0}' 'Das Update konnte nicht geladen werden: {0}') -f $_.Exception.Message
        $btnUpdate.Visible = $true
        return
    }
    $env:TSEXT_PAUSE_ON_ERROR = '1'
    # Close only once the update window runs: started from the desktop shortcut, the new window often died when the
    # launcher closed in the same moment (Windows 11, 2026-11-16: 9 of 13 tries); with 3 s of waiting all tries worked.
    $updater = $null
    try { $updater = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$UpdateFile`"") -PassThru } catch { }
    $until = (Get-Date).AddSeconds(3)
    while ($updater -and -not $updater.HasExited -and (Get-Date) -lt $until) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
    # ended within the 3 s: fine if it installed already (version.txt changed), otherwise it did not run
    $now = ''
    try { $now = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'version.txt') -Raw -ErrorAction Stop).Trim() } catch { }
    if (-not $updater -or ($updater.HasExited -and $now -eq $Version)) {
        $updateLabel.Text = Txt 'The update window did not start - "Update now" tries again.' 'Das Update-Fenster ist nicht gestartet – „Jetzt aktualisieren“ versucht es nochmals.'
        $btnUpdate.Visible = $true
        return
    }
    $form.Close()
}
# Called with the newest release ("v1.2.0"): nothing if it is not newer than this version; otherwise the notice, and
# with "Update automatically" the update itself - not while the game runs, at most once per version and day.
function Show-UpdateNotice([string]$tag) {
    if (-not $Installed -or $tag -notmatch '^v?(\d+\.\d+\.\d+)$') { return }
    $newest = [version]$Matches[1]
    if ($newest -le [version]$Version) { return }
    $updateLabel.Text = (Txt 'Version {0} is out.' 'Version {0} ist da.') -f $newest
    $updateLabel.Visible = $true; $btnUpdate.Visible = $true; $btnNews.Visible = $false
    $attempt = '{0} {1}' -f $newest, (Get-Date -Format 'yyyy-MM-dd')
    if ($chkAutoUpdate.Checked -and $script:UpdateTried -ne $attempt -and -not $timer.Enabled -and -not (Get-GameProcess)) {
        $script:UpdateTried = $attempt
        $updateLabel.Text = (Txt 'Version {0} is out and is being installed - the launcher opens again in a moment.' 'Version {0} ist da und wird installiert – der Starter öffnet sich gleich wieder.') -f $newest
        $btnUpdate.Visible = $false
        $form.Refresh()
        Start-Update
    }
}
$btnUpdate.Add_Click({ $btnUpdate.Visible = $false; Start-Update })
$chkAutoUpdate.Add_CheckedChanged({ Save-UpdateState })
$btnNews.Add_Click({ Start-Process "https://github.com/$Repo/releases/tag/v$Version" })
# After an update (the version saved at the last start is older): say so once, with a button for the release notes.
if ($Installed -and $script:saved['LastVersion'] -match '^\d+\.\d+\.\d+$' -and [version]$script:saved['LastVersion'] -lt [version]$Version) {
    $updateLabel.Text = (Txt 'Updated to version {0}.' 'Aktualisiert auf Version {0}.') -f $Version
    $updateLabel.Visible = $true; $btnNews.Visible = $true
}
if ($Installed -and $script:saved['LastVersion'] -ne $Version) { Save-UpdateState }
# The downloaded copy of get.ps1 of the last update is no longer needed.
if (-not $SelfTest) { try { if (Test-Path -LiteralPath $UpdateFile) { Remove-Item -LiteralPath $UpdateFile -Force } } catch { } }
# Ask GitHub for the newest release in the background (at most 8 s; only the version number is fetched, nothing is sent
# but the request itself). Off with $env:TSEXT_NO_UPDATE_CHECK = '1'.
if ($Installed -and -not $SelfTest -and $env:TSEXT_NO_UPDATE_CHECK -ne '1') {
    try {
        $script:UpdateCheck = [PowerShell]::Create()
        [void]$script:UpdateCheck.AddScript({
                param($repo)
                $agent = 'tiberian-sun-extensions-launcher'
                try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
                try { return [string](Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = $agent } -TimeoutSec 8).tag_name } catch { }
                # Without the API (60 requests an hour): the release page redirects to the newest tag.
                try {
                    $request = [Net.HttpWebRequest]::Create("https://github.com/$repo/releases/latest")
                    $request.AllowAutoRedirect = $false; $request.UserAgent = $agent; $request.Timeout = 8000
                    $response = $request.GetResponse(); $location = [string]$response.Headers['Location']; $response.Close()
                    if ($location -match '/releases/tag/([^/?#]+)$') { return $Matches[1] }
                }
                catch { }
                ''
            }).AddArgument($Repo)
        $script:UpdateHandle = $script:UpdateCheck.BeginInvoke()
        $updateTimer = New-Object System.Windows.Forms.Timer
        $updateTimer.Interval = 500
        $updateTimer.Add_Tick({
                if (-not $script:UpdateHandle.IsCompleted) { return }
                $updateTimer.Stop()
                try { Show-UpdateNotice ([string](@($script:UpdateCheck.EndInvoke($script:UpdateHandle)) | Select-Object -First 1)) } catch { }
                $script:UpdateCheck.Dispose()
            })
        $updateTimer.Start()
    }
    catch { }
}

$form.Add_Shown({
        if (-not $GameDir) { $sub.Text = Txt 'Tiberian Sun (Steam) not found.' 'Tiberian Sun (Steam) nicht gefunden.' }
        else {
            $sub.Text = $GameDir
            # leftovers of a previous run (launcher closed while the game was running)
            if (-not (Get-GameProcess)) { Restore-AfterGame }
            else { $script:started = Get-Date; $script:runSettings = Get-Settings; $script:patched = $true; $timer.Start(); $btnStart.Enabled = $false; $btnOriginal.Enabled = $false; $status.Text = Txt 'The game is running.' 'Das Spiel läuft.' }
        }
        Update-CampaignList
        if ($AutoStart) { $btnStart.PerformClick() }
        if ($SelfTest) {
            $out = @()
            foreach ($b in $presetButtons) { $b.PerformClick(); $out += "preset $($b.Tag): " + (((Get-UiSettings).GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ') }
            foreach ($t in $tabs.TabPages) { $tabs.SelectedTab = $t; $form.Refresh() }
            $out += "tabs: $($tabs.TabPages.Count), options: $($combos.Count), campaign rows: $($lv.Items.Count)"
            if ($PreviewUpdate) { Show-UpdateNotice $PreviewUpdate }
            $out += "version: $Version, installed: $Installed, auto update: $($chkAutoUpdate.Checked) (box shown: $($chkAutoUpdate.Visible))"
            $out += "update row: shown=$($updateLabel.Visible) text=[$($updateLabel.Text)] update button=$($btnUpdate.Visible) news button=$($btnNews.Visible) started=[$($script:UpdateLog -join ', ')]"
            if ($PreviewImage) {
                $tabs.SelectedIndex = 0; $form.Refresh()
                if ($presetButtons.Count -gt 1) { $presetButtons[1].PerformClick(); $form.Refresh() }     # "Everything bigger" (needs its tab in front)
                $image = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
                $form.DrawToBitmap($image, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
                $image.Save($PreviewImage, [System.Drawing.Imaging.ImageFormat]::Png); $image.Dispose()
            }
            $out | Set-Content -LiteralPath (Join-Path $env:TEMP 'tsext-selftest.txt') -Encoding UTF8
            $form.Close()
        }
    })
$form.Add_FormClosing({ if (-not (Get-GameProcess)) { Restore-AfterGame } })
[void]$form.ShowDialog()




