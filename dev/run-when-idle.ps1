# Runs in-game tests only while nobody uses the PC: waits until there was no mouse or keyboard input for -IdleMinutes,
# then runs each test script in turn. As soon as a person touches the mouse or keyboard (a real event - the tests'
# own clicks and key presses are marked "injected" by Windows and do not count), it ends Game.exe at once; the test
# script then puts SUN.INI and the game folder back itself (its finally block), and the run waits for the next idle
# time. The game cannot run on an invisible desktop (it reports "graphics mode cannot be set"), so this is the way
# to test without getting in the way.
#   .\dev\run-when-idle.ps1 -Tests '.\dev\rmg-survey.ps1 -Only perfect -Start', '.\dev\launcher-game-test.ps1'
param([string[]]$Tests, [double]$IdleMinutes = 10, [double]$MaxHours = 24, [int]$MaxTries = 6, [string]$Log = '')
$ErrorActionPreference = 'Stop'
if (-not $Log) { $Log = Join-Path $PSScriptRoot '..\analysis\run-when-idle.log' }
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Threading;
public static class InputWatch {
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO i);
    static double SystemIdle() { var i = new LASTINPUTINFO(); i.cbSize = 8; GetLastInputInfo(ref i); return unchecked((uint)Environment.TickCount - i.dwTime) / 1000.0; }
    // time since the last input of a person: from the hook once it runs (the tests' own input does not count),
    // before that from Windows (any input)
    static volatile int lastReal;
    public static double IdleSeconds() { return th == null ? SystemIdle() : unchecked(Environment.TickCount - lastReal) / 1000.0; }

    delegate IntPtr HookProc(int code, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, HookProc f, IntPtr mod, uint tid);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int code, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr h, uint a, uint b);
    [DllImport("user32.dll")] static extern bool PostThreadMessage(uint tid, uint msg, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr h; public uint msg; public IntPtr w, l; public uint t; public int x, y; }
    static HookProc mouse = MouseProc, keys = KeyProc;   // keep the delegates alive
    static uint tid; static Thread th;
    public static volatile int RealEvents;               // input from a person (not injected)
    public static volatile int InjectedEvents;           // input made by a program (the tests' clicks and keys)
    public static volatile string Last = "";
    static IntPtr MouseProc(int code, IntPtr w, IntPtr l) {
        if (code >= 0) { int flags = Marshal.ReadInt32(l, 12); if ((flags & 1) == 0) { RealEvents++; lastReal = Environment.TickCount; Last = "mouse 0x" + w.ToInt64().ToString("X"); } else InjectedEvents++; }
        return CallNextHookEx(IntPtr.Zero, code, w, l);
    }
    static IntPtr KeyProc(int code, IntPtr w, IntPtr l) {
        if (code >= 0) { int flags = Marshal.ReadInt32(l, 8); if ((flags & 0x10) == 0) { RealEvents++; lastReal = Environment.TickCount; Last = "key " + Marshal.ReadInt32(l, 0); } else InjectedEvents++; }
        return CallNextHookEx(IntPtr.Zero, code, w, l);
    }
    public static void Start() {
        lastReal = unchecked(Environment.TickCount - (int)(SystemIdle() * 1000));
        th = new Thread(() => {
            tid = GetCurrentThreadId();
            IntPtr m = GetModuleHandle(null);
            IntPtr h1 = SetWindowsHookEx(14, mouse, m, 0), h2 = SetWindowsHookEx(13, keys, m, 0);   // WH_MOUSE_LL, WH_KEYBOARD_LL
            MSG msg; while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0) { }
            UnhookWindowsHookEx(h1); UnhookWindowsHookEx(h2);
        });
        th.IsBackground = true; th.Start();
    }
    public static void Stop() { if (th != null) { PostThreadMessage(tid, 0x0012, IntPtr.Zero, IntPtr.Zero); th.Join(2000); } }
}
'@
function Write-Log([string]$t) { $l = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $t; $l; Add-Content -LiteralPath $Log -Value $l -Encoding UTF8 }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$until = (Get-Date).AddHours($MaxHours)
$results = @{}
[InputWatch]::Start()
try {
    for ($i = 0; $i -lt $Tests.Count; $i++) {
        $test = $Tests[$i]; $tries = 0
        while ($true) {
            while ([InputWatch]::IdleSeconds() -lt $IdleMinutes * 60) {
                if ((Get-Date) -gt $until) { Write-Log "gave up waiting for an idle PC: $test"; $results[$test] = 'not run (PC never idle)'; break }
                Start-Sleep -Seconds 15
            }
            if ($results.ContainsKey($test)) { break }
            $tries++
            Write-Log ("PC idle {0:N0} min - running ({1}/{2}): {3}" -f ([InputWatch]::IdleSeconds() / 60), $tries, $MaxTries, $test)
            [InputWatch]::RealEvents = 0
            $out = Join-Path $root ('analysis\run-when-idle-{0}.txt' -f ($i + 1))
            $p = Start-Process -FilePath powershell.exe -WorkingDirectory $root -PassThru -WindowStyle Minimized -RedirectStandardOutput $out -RedirectStandardError "$out.err" `
                -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', "& $test; exit `$LASTEXITCODE")
            $null = $p.Handle     # keeps the handle, so that ExitCode is still there after the end
            $aborted = $false
            while (-not $p.HasExited) {
                Start-Sleep -Milliseconds 250
                if ([InputWatch]::RealEvents -gt 0 -and -not $aborted) {
                    $aborted = $true
                    Write-Log ("someone uses the PC ({0}) - ending the game, the test puts everything back" -f [InputWatch]::Last)
                    Get-Process -Name game -ErrorAction SilentlyContinue | Stop-Process -Force
                }
            }
            if (-not $aborted) { $results[$test] = "exit code $($p.ExitCode)"; Write-Log "finished: $test (exit $($p.ExitCode), output $out)"; break }
            if ($tries -ge $MaxTries) { $results[$test] = 'not finished (interrupted every time)'; Write-Log "interrupted $tries times, giving up: $test"; break }
        }
    }
}
finally {
    [InputWatch]::Stop()
    Get-Process -Name game -ErrorAction SilentlyContinue | Stop-Process -Force
}
foreach ($t in $Tests) { Write-Log ("result: {0} -> {1}" -f $t, $results[$t]) }
