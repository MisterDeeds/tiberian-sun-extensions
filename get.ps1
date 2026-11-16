# Tiberian Sun - Extensions: install (or update) with one line. Paste into PowerShell and press Enter:
#
#   irm https://raw.githubusercontent.com/MisterDeeds/tiberian-sun-extensions/main/get.ps1 | iex
#
# Downloads the newest release from GitHub, installs it with src\install.ps1 (program folder in
# %LOCALAPPDATA%\Programs, the campaigns built from your own maps, shortcuts, an entry in the Windows "Apps" list
# for removing it) and opens the launcher. The same line updates an existing installation, and the launcher runs it
# by itself when a newer release is out. No original game file is changed, no administrator rights are needed.
#
# For testing only (environment variables, because "irm | iex" takes no parameters):
#   TSEXT_SOURCE            a local .zip or folder in the layout of the repository instead of the download
#   TSEXT_SANDBOX           passed to src\install.ps1 -SandboxRoot (every user folder below that folder)
#   TSEXT_PAUSE_ON_ERROR=1  wait for Enter after an error (set by the launcher, which downloads this script and runs
#                           it as a file for its automatic update)
#
# Plain ASCII on purpose: Windows PowerShell 5.1 reads a downloaded .ps1 without BOM in the ANSI code page.
# Everything runs inside "& { }", so that nothing is left behind in the PowerShell window it was pasted into, and it
# never calls "exit", which would close that window.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads very slow in Windows PowerShell
    $repo = 'MisterDeeds/tiberian-sun-extensions'
    $german = if ($env:TSEXT_LANG) { $env:TSEXT_LANG -eq 'de' } else { (Get-UICulture).TwoLetterISOLanguageName -eq 'de' }
    function Txt([string]$en, [string]$de) { if ($german) { $de } else { $en } }

    Write-Host ''
    Write-Host ('  ' + (Txt 'Tiberian Sun - Extensions' 'Tiberian Sun - Erweiterungen')) -ForegroundColor Cyan
    Write-Host ('  ' + (Txt 'Huge worlds, sharp graphics, 15 new missions - installing ...' 'Riesige Welten, scharfe Grafik, 15 neue Missionen - wird installiert ...'))
    Write-Host ''

    if ($env:OS -ne 'Windows_NT') { Write-Host (Txt 'This only works on Windows.' 'Das geht nur unter Windows.') -ForegroundColor Red; return }
    # The installer always runs in Windows PowerShell 5.1 (part of every Windows 10 and 11), whichever PowerShell this
    # line was pasted into; from a 32-bit window through Sysnative, so that the 64-bit one is used.
    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) { $ps = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe' }

    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $agent = 'tiberian-sun-extensions-installer'
    $work = Join-Path ([IO.Path]::GetTempPath()) ('tiberian-sun-extensions-setup-' + [guid]::NewGuid().ToString('N'))
    $failed = $false
    try {
        New-Item -ItemType Directory -Path $work | Out-Null
        $source = $env:TSEXT_SOURCE
        if (-not $source) {
            Write-Host (Txt 'Looking for the newest version on GitHub ...' 'Suche die neuste Version auf GitHub ...')
            $tag = $null
            try { $tag = [string](Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = $agent } -TimeoutSec 30).tag_name } catch { }
            if (-not $tag) {
                # Without the API (it allows 60 requests an hour): the release page redirects to the newest tag.
                try {
                    $request = [Net.HttpWebRequest]::Create("https://github.com/$repo/releases/latest")
                    $request.AllowAutoRedirect = $false; $request.UserAgent = $agent; $request.Timeout = 30000
                    $response = $request.GetResponse(); $location = [string]$response.Headers['Location']; $response.Close()
                    if ($location -match '/releases/tag/([^/?#]+)$') { $tag = $Matches[1] }
                }
                catch { }
            }
            if ($tag -notmatch '^v?\d+\.\d+\.\d+$') { throw (Txt 'GitHub could not be reached. Please check the internet connection and try again.' 'GitHub ist nicht erreichbar. Bitte die Internetverbindung pruefen und nochmals versuchen.') }
            Write-Host ((Txt 'Downloading version {0} ...' 'Lade Version {0} herunter ...') -f $tag.TrimStart('v'))
            $source = Join-Path $work 'release.zip'
            Invoke-WebRequest -Uri "https://github.com/$repo/archive/refs/tags/$tag.zip" -OutFile $source -UseBasicParsing -Headers @{ 'User-Agent' = $agent } -TimeoutSec 300
        }
        $root = $source
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            $root = Join-Path $work 'files'
            Expand-Archive -LiteralPath $source -DestinationPath $root -Force
        }
        # The ZIP of a GitHub release holds one folder (tiberian-sun-extensions-<version>), a clone does not.
        $installer = @(@(Join-Path $root 'src\install.ps1') + @(Get-ChildItem -LiteralPath $root -Directory | ForEach-Object { Join-Path $_.FullName 'src\install.ps1' }) | Where-Object { Test-Path -LiteralPath $_ }) | Select-Object -First 1
        if (-not $installer) { throw (Txt 'The download is incomplete (src\install.ps1 is missing). Please try again.' 'Der Download ist unvollstaendig (src\install.ps1 fehlt). Bitte nochmals versuchen.') }
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-StartLauncher')
        if ($env:TSEXT_SANDBOX) { $arguments += @('-SandboxRoot', $env:TSEXT_SANDBOX) }
        & $ps @arguments
        if ($LASTEXITCODE -ne 0) { throw (Txt 'The installation did not finish, see the messages above.' 'Die Installation wurde nicht fertig, siehe die Meldungen oben.') }
    }
    catch {
        $failed = $true
        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host (Txt "The game files are unchanged. Help: https://github.com/$repo/issues" "Die Spieldateien sind unveraendert. Hilfe: https://github.com/$repo/issues") -ForegroundColor Yellow
    }
    finally {
        # A virus scanner may still hold the freshly unpacked files for a moment: try a few times.
        for ($i = 0; $i -lt 10 -and (Test-Path -LiteralPath $work); $i++) {
            try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 }
        }
    }
    if ($failed -and $env:TSEXT_PAUSE_ON_ERROR -eq '1') {
        try { [void](Read-Host (Txt 'Press Enter to close this window' 'Enter druecken, um dieses Fenster zu schliessen')) } catch { }
    }
}
