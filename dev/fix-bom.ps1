# Windows PowerShell 5.1 reads .ps1 files without a byte order mark as ANSI. Scripts with umlauts therefore need
# UTF-8 with BOM. This adds the BOM to every .ps1 of the project that contains non-ASCII characters.
$root = Join-Path $PSScriptRoot '..'
$utf8Bom = New-Object System.Text.UTF8Encoding $true
foreach ($f in Get-ChildItem -LiteralPath $root -Recurse -Filter *.ps1 | Where-Object { $_.FullName -notmatch '\\(analysis|\.git)\\' }) {
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if ($hasBom) { continue }
    $nonAscii = $false; foreach ($b in $bytes) { if ($b -ge 0x80) { $nonAscii = $true; break } }
    if (-not $nonAscii) { continue }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    [IO.File]::WriteAllText($f.FullName, $text, $utf8Bom)
    "BOM added: $($f.Name)"
}
