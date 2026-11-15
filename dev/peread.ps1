# Reads values from analysis\bin\Game.exe by virtual address (for analysis).
#   .\dev\peread.ps1 -Address 0x6d3f24 -Count 7 -Type int
#   .\dev\peread.ps1 -Address 0x6cbd30 -Type float
#   .\dev\peread.ps1 -Address 0x701d28 -Type string
#   .\dev\peread.ps1 -Address 0x53da7c -Type bytes -Count 16
param(
    [Parameter(Mandatory)][string]$Address,
    [int]$Count = 1,
    [ValidateSet('int', 'uint', 'short', 'byte', 'float', 'double', 'string', 'bytes')][string]$Type = 'int',
    [string]$Exe = (Join-Path $PSScriptRoot '..\analysis\bin\Game.exe')
)
$b = [IO.File]::ReadAllBytes((Resolve-Path $Exe))
$pe = [BitConverter]::ToInt32($b, 0x3c)
$ns = [BitConverter]::ToUInt16($b, $pe + 6)
$opt = [BitConverter]::ToUInt16($b, $pe + 20)
$ib = [BitConverter]::ToUInt32($b, $pe + 24 + 28)
$va = [Convert]::ToUInt32(($Address -replace '^0x', ''), 16)
$fo = -1
for ($i = 0; $i -lt $ns; $i++) {
    $o = $pe + 24 + $opt + 40 * $i
    $vs = [BitConverter]::ToUInt32($b, $o + 8); $sva = $ib + [BitConverter]::ToUInt32($b, $o + 12)
    $rp = [BitConverter]::ToUInt32($b, $o + 20)
    if ($va -ge $sva -and $va -lt $sva + $vs) { $fo = $rp + ($va - $sva); break }
}
if ($fo -lt 0) { throw "Address $Address is not in a section" }
"file offset 0x{0:X}" -f $fo
switch ($Type) {
    'int' { 0..($Count - 1) | ForEach-Object { [BitConverter]::ToInt32($b, $fo + 4 * $_) } }
    'uint' { 0..($Count - 1) | ForEach-Object { '0x{0:X8}' -f [BitConverter]::ToUInt32($b, $fo + 4 * $_) } }
    'short' { 0..($Count - 1) | ForEach-Object { [BitConverter]::ToInt16($b, $fo + 2 * $_) } }
    'byte' { 0..($Count - 1) | ForEach-Object { $b[$fo + $_] } }
    'float' { 0..($Count - 1) | ForEach-Object { [BitConverter]::ToSingle($b, $fo + 4 * $_) } }
    'double' { 0..($Count - 1) | ForEach-Object { [BitConverter]::ToDouble($b, $fo + 8 * $_) } }
    'string' { $e = $fo; while ($b[$e] -ne 0) { $e++ }; [Text.Encoding]::GetEncoding(1252).GetString($b, $fo, $e - $fo) }
    'bytes' { ($b[$fo..($fo + $Count - 1)] | ForEach-Object { $_.ToString('X2') }) -join ' ' }
}
