# Starts the game for a test, logs its windows, reads addresses and saves window pictures, then ends it.
#   .\dev\game-probe.ps1 -Seconds 40 -Read 0x7e2240 -Steps 'wait:15','shot','cmd:<dlgtext>:<id>','key:13','click:x,y'
# Pictures go to analysis\shots. Does nothing while you are using the PC (idle check), unless -Force.
param(
    [int]$Seconds = 30,
    [string]$Read = '',      # addresses, separated by ;
    [string]$Steps = '',     # steps, separated by ;
    [string]$Args = '',
    [switch]$Force,
    [switch]$KeepRunning
)
. (Join-Path $PSScriptRoot '..\src\tslib.ps1')
$ReadList = @($Read -split ';' | Where-Object { $_ })
$StepList = @($Steps -split ';' | Where-Object { $_ })
$game = Find-TSGame
$shots = Join-Path $PSScriptRoot '..\analysis\shots'
New-Item -ItemType Directory -Force $shots | Out-Null
$idle = [TSExt.Win]::IdleMilliseconds()
if (-not $Force -and $idle -lt 120000) { "User active (idle $([int]($idle/1000)) s) - not starting the game."; exit 2 }

$p = Get-Process -Name game -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$game*" } | Select-Object -First 1
if (-not $p) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo (Join-Path $game 'Game.exe')
    $psi.WorkingDirectory = $game
    $psi.Arguments = $Args
    $psi.UseShellExecute = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    "started pid $($p.Id)"
}
$gp = New-Object TSExt.GameProcess $p
$t0 = Get-Date
$shotNo = 0
function Show-Windows {
    foreach ($w in [TSExt.Win]::TopWindows($p.Id)) {
        if (-not [TSExt.Win]::IsWindowVisible($w)) { continue }
        '  W ' + [TSExt.Win]::Describe($w)
        foreach ($c in [TSExt.Win]::Children($w)) { '     c ' + [TSExt.Win]::Describe($c) }
    }
}
function Read-Values {
    foreach ($a in $ReadList) {
        $addr = [Convert]::ToUInt32(($a -replace '^0x', ''), 16)
        $v = 0; $ok = $true
        try { $v = $gp.ReadInt($addr) } catch { $ok = $false }
        if ($ok) { '  [0x{0:X}] = {1} (0x{1:X})' -f $addr, $v } else { '  [0x{0:X}] unreadable' -f $addr }
    }
}
function Save-Shot([string]$tag) {
    $main = [TSExt.Win]::TopWindows($p.Id) | Where-Object { [TSExt.Win]::IsWindowVisible($_) } | Select-Object -First 1
    if (-not $main) { '  (no window)'; return }
    $bmp = [TSExt.Win]::Capture($main)
    $script:shotNo++
    $f = Join-Path $shots ('{0:00}_{1}.png' -f $script:shotNo, $tag)
    $bmp.Save($f, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    "  shot $f"
}
try {
    foreach ($s in $StepList) {
        if ($p.HasExited) { 'game exited'; break }
        $parts = $s -split ':', 3
        switch ($parts[0]) {
            'wait' { Start-Sleep -Seconds ([int]$parts[1]) }
            'shot' { Save-Shot ($(if ($parts.Count -gt 1) { $parts[1] } else { 'shot' })) }
            'win' { "t=$([int]((Get-Date) - $t0).TotalSeconds)s windows:"; Show-Windows }
            'read' { Read-Values }
            'cmd' {
                $dlg = [TSExt.Win]::TopWindows($p.Id) | Where-Object { [TSExt.Win]::IsWindowVisible($_) } | ForEach-Object { $_; [TSExt.Win]::Children($_) } | Where-Object { [TSExt.Win]::GetDlgItem($_, [int]$parts[2]) -ne [IntPtr]::Zero } | Select-Object -First 1
                if ($dlg) { [TSExt.Win]::Command($dlg, [int]$parts[2]); "  WM_COMMAND $($parts[2]) -> $([TSExt.Win]::Describe($dlg))" } else { "  no dialog with control $($parts[2])" }
            }
            'list' {
                # list:<listbox id> - prints the entries; list:<id>:<index> - selects one
                foreach ($w in [TSExt.Win]::TopWindows($p.Id)) {
                    foreach ($c in [TSExt.Win]::Children($w)) {
                        if ([TSExt.Win]::GetDlgCtrlID($c) -ne [int]$parts[1]) { continue }
                        $n = [int][TSExt.Win]::SendMessageA($c, 0x018B, [IntPtr]::Zero, [IntPtr]::Zero)   # LB_GETCOUNT
                        for ($i = 0; $i -lt $n; $i++) {
                            $len = [int][TSExt.Win]::SendMessageA($c, 0x018A, [IntPtr]$i, [IntPtr]::Zero)    # LB_GETTEXTLEN
                            $buf = [Runtime.InteropServices.Marshal]::AllocHGlobal($len + 2)
                            [void][TSExt.Win]::SendMessageA($c, 0x0189, [IntPtr]$i, $buf)                     # LB_GETTEXT
                            "  [$i] " + [Runtime.InteropServices.Marshal]::PtrToStringAnsi($buf)
                            [Runtime.InteropServices.Marshal]::FreeHGlobal($buf)
                        }
                        if ($parts.Count -gt 2) { [void][TSExt.Win]::SendMessageA($c, 0x0186, [IntPtr][int]$parts[2], [IntPtr]::Zero); "  selected $($parts[2])" }  # LB_SETCURSEL
                    }
                }
            }
            'combo' {
                # combo:<id> lists the entries, combo:<id>:<index> selects one (and notifies the dialog)
                foreach ($w in [TSExt.Win]::TopWindows($p.Id)) {
                    foreach ($c in [TSExt.Win]::Children($w)) {
                        if ([TSExt.Win]::GetDlgCtrlID($c) -ne [int]$parts[1] -or [TSExt.Win]::ClassName($c) -ne 'ComboBox' -or -not [TSExt.Win]::IsWindowVisible($c)) { continue }
                        $n = [int][TSExt.Win]::SendMessageA($c, 0x0146, [IntPtr]::Zero, [IntPtr]::Zero)
                        for ($i = 0; $i -lt $n; $i++) {
                            $buf = [Runtime.InteropServices.Marshal]::AllocHGlobal(256)
                            [void][TSExt.Win]::SendMessageA($c, 0x0148, [IntPtr]$i, $buf)
                            "  [$i] " + [Runtime.InteropServices.Marshal]::PtrToStringAnsi($buf)
                            [Runtime.InteropServices.Marshal]::FreeHGlobal($buf)
                        }
                        if ($parts.Count -gt 2) {
                            [void][TSExt.Win]::SendMessageA($c, 0x014E, [IntPtr][int]$parts[2], [IntPtr]::Zero)
                            $dlg = [TSExt.Win]::GetParent($c)
                            [void][TSExt.Win]::PostMessageA($dlg, 0x0111, [IntPtr](([int]$parts[1]) -bor (1 -shl 16)), $c)   # CBN_SELCHANGE
                            "  combo $($parts[1]) = $($parts[2])"
                        }
                    }
                }
            }
            'slider' {
                # slider:<id>:<pos> sets a trackbar (TBM_SETPOS) and notifies the dialog (WM_HSCROLL)
                foreach ($w in [TSExt.Win]::TopWindows($p.Id)) {
                    foreach ($c in [TSExt.Win]::Children($w)) {
                        if ([TSExt.Win]::GetDlgCtrlID($c) -ne [int]$parts[1] -or -not [TSExt.Win]::IsWindowVisible($c)) { continue }
                        [void][TSExt.Win]::SendMessageA($c, 0x0405, [IntPtr]1, [IntPtr][int]$parts[2])
                        [void][TSExt.Win]::SendMessageA([TSExt.Win]::GetParent($c), 0x0114, [IntPtr]8, $c)
                        "  slider $($parts[1]) = $($parts[2]) (now $([int][TSExt.Win]::SendMessageA($c, 0x0400, [IntPtr]::Zero, [IntPtr]::Zero)))"
                    }
                }
            }
            'dlgcmd' {
                # dlgcmd:<control id> - WM_COMMAND to the dialog that owns this control
                foreach ($w in [TSExt.Win]::TopWindows($p.Id)) {
                    foreach ($c in [TSExt.Win]::Children($w)) {
                        if ([TSExt.Win]::ClassName($c) -eq '#32770' -and [TSExt.Win]::IsWindowVisible($c) -and [TSExt.Win]::GetDlgItem($c, [int]$parts[1]) -ne [IntPtr]::Zero) { [TSExt.Win]::Command($c, [int]$parts[1]); "  WM_COMMAND $($parts[1])" }
                    }
                }
            }
            'patch' {
                # patch:rmgsize=2 - applies the memory patches of src\patcher.ps1 with these settings
                . (Join-Path $PSScriptRoot '..\src\patcher.ps1')
                $set = @{}; foreach ($kv in ($parts[1] -split ',')) { $q = $kv -split '='; $set[$q[0]] = $q[1] }
                Invoke-GamePatches $gp $set | ForEach-Object { "  $_" }
            }
            'threads' { $gp.SampleThreads() | Where-Object { $_ -match 'eip 00[4-6]' } | ForEach-Object { "  $_" } }
            'focus' { $gw = [TSExt.Win]::TopWindows($p.Id) | Where-Object { [TSExt.Win]::ClassName($_) -eq 'Tiberian Sun' } | Select-Object -First 1; if ($gw) { [TSExt.Win]::Focus($gw); Start-Sleep -Milliseconds 1500; '  focused game' } }
            'rclick' {
                $gw = [TSExt.Win]::TopWindows($p.Id) | Where-Object { [TSExt.Win]::ClassName($_) -eq 'Tiberian Sun' } | Select-Object -First 1
                if ($gw -and [TSExt.Win]::GetForegroundWindow() -ne $gw) { [TSExt.Win]::Focus($gw); Start-Sleep -Milliseconds 1200 }
                $xy = $parts[1] -split ','; [TSExt.Win]::RealClick([int]$xy[0], [int]$xy[1], $false); "  real click (screen) $($parts[1])"
            }
            'rkey' { [TSExt.Win]::RealKey([byte][int]$parts[1]); "  real key $($parts[1])" }
            'type' { foreach ($ch in $parts[1].ToCharArray()) { [TSExt.Win]::RealKey([byte][int][char]::ToUpper($ch)) }; "  typed $($parts[1])" }
            'key' { $main = [TSExt.Win]::TopWindows($p.Id) | Where-Object { [TSExt.Win]::IsWindowVisible($_) } | Select-Object -First 1; [TSExt.Win]::Key($main, [int]$parts[1]); "  key $($parts[1])" }
            'click' { $xy = $parts[1] -split ','; $main = [TSExt.Win]::TopWindows($p.Id) | Where-Object { [TSExt.Win]::IsWindowVisible($_) } | Select-Object -First 1; [TSExt.Win]::Click($main, [int]$xy[0], [int]$xy[1]); "  click $($parts[1])" }
        }
    }
    if (-not $StepList) {
        while (((Get-Date) - $t0).TotalSeconds -lt $Seconds -and -not $p.HasExited) {
            Start-Sleep -Seconds 5
            "t=$([int]((Get-Date) - $t0).TotalSeconds)s"; Show-Windows; Read-Values
        }
        Save-Shot 'end'
    }
}
finally {
    if (-not $KeepRunning -and -not $p.HasExited) { $p.Kill(); 'game ended' }
    $gp.Dispose()
}

