# One-line installer for the Tiberian Sun Extensions:
#   irm https://raw.githubusercontent.com/MisterDeeds/tiberian-sun-extensions/main/get.ps1 | iex
# Downloads the newest release (or the main branch if there is no release yet), unpacks it to %TEMP% and runs
# src\install.ps1, then starts the launcher. Everything runs inside & { } so that the caller's window stays open.
& {
    $ErrorActionPreference = 'Stop'
    $repo = 'MisterDeeds/tiberian-sun-extensions'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $zipUrl = $null
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'tsext-installer' }
        $zipUrl = $rel.zipball_url
    }
    catch { }
    if (-not $zipUrl) { $zipUrl = "https://github.com/$repo/archive/refs/heads/main.zip" }
    $tmp = Join-Path $env:TEMP ('tsext-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp 'tsext.zip'
    Write-Host "Download: $zipUrl"
    Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'tsext-installer' }
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    $root = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
    $install = Join-Path $root.FullName 'src\install.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $install
    $launcher = Join-Path $env:LOCALAPPDATA 'Programs\TSExtensions\launcher.ps1'
    if (Test-Path -LiteralPath $launcher) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`""
    }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
