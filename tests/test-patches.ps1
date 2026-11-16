# Checks every memory patch of src\patcher.ps1 against the Game.exe of the installation (file on disk, no game run):
# the original bytes must be where the patches expect them, and the new code must decode as intended.
. (Join-Path $PSScriptRoot '..\src\tslib.ps1')
. (Join-Path $PSScriptRoot '..\src\patcher.ps1')
$ErrorActionPreference = 'Stop'
$game = Find-TSGame
$exe = [IO.File]::ReadAllBytes((Join-Path $game 'Game.exe'))
$errors = 0
function Check([string]$what, [bool]$ok) { if ($ok) { "  ok   $what" } else { "  FAIL $what"; $script:errors++ } }
if (-not (Test-GameVersion $game)) { 'Game.exe is not 2.03 TUC (Steam) - the patches are skipped there; nothing to check.'; exit 0 }

# virtual address -> file offset (PE section table)
$pe = [BitConverter]::ToInt32($exe, 0x3C)
$nSec = [BitConverter]::ToUInt16($exe, $pe + 6); $optSize = [BitConverter]::ToUInt16($exe, $pe + 20)
$imageBase = [BitConverter]::ToUInt32($exe, $pe + 24 + 28)
$secs = @(); $s0 = $pe + 24 + $optSize
for ($i = 0; $i -lt $nSec; $i++) {
    $o = $s0 + $i * 40
    $secs += @{ Va = [BitConverter]::ToUInt32($exe, $o + 12); Size = [BitConverter]::ToUInt32($exe, $o + 16); Raw = [BitConverter]::ToUInt32($exe, $o + 20) }
}
function Get-Bytes([uint32]$va, [int]$n) {
    $rva = $va - $imageBase
    foreach ($s in $secs) { if ($rva -ge $s.Va -and $rva -lt $s.Va + $s.Size) { $b = New-Object byte[] $n; [Array]::Copy($exe, [int]($s.Raw + $rva - $s.Va), $b, 0, $n); return , $b } }
    throw ('address 0x{0:X} not in the file' -f $va)
}
function Hex($b) { ($b | ForEach-Object { $_.ToString('X2') }) -join ' ' }

"random map size tables:"
foreach ($t in 'MinW', 'MinH', 'MaxW', 'MaxH') {
    $orig = if ($t -like 'Min*') { $script:RmgOriginal.Min } else { $script:RmgOriginal.Max }
    Check "$t at 0x$('{0:X}' -f $script:RmgTables[$t]) = $($orig -join ',')" ((Hex (Get-Bytes $script:RmgTables[$t] 28)) -eq (Hex (ConvertTo-IntBytes $orig)))
}
"sidebar:"
foreach ($h in $script:SidebarHooks) { Check ('hook 0x{0:X}: {1}' -f $h.At, (Hex $h.Orig)) ((Hex (Get-Bytes $h.At $h.Orig.Length)) -eq (Hex $h.Orig)) }
foreach ($r in $script:SidebarArrayRefs) { Check ('array reference 0x{0:X}' -f $r[0]) ([BitConverter]::ToUInt32((Get-Bytes $r[0] 4), 0) -eq [uint32]($script:SidebarArrayOld + $r[1])) }
foreach ($s in $script:SidebarStridePatches) { Check ('stride 0x{0:X}: {1:X2}' -f $s[0], $s[1]) ((Get-Bytes $s[0] 1)[0] -eq $s[1]) }
"random map Tiberium:"
Check ('hook 0x{0:X}: LEA EAX,[EDX+EDX*1+0x9C4]' -f $script:TibHookAt) ((Hex (Get-Bytes $script:TibHookAt 7)) -eq (Hex $script:TibHookOrig))
# the instructions around it: *3, *5, then the hook, then IMUL EAX,[EBX+0x44] (players)
Check 'context: LEA EAX,[EAX+EAX*2]; LEA EDX,[EAX+EAX*4] before, IMUL EAX,[EBX+0x44] after' (((Hex (Get-Bytes 0x54661E 6)) -eq '8D 04 40 8D 14 80') -and ((Hex (Get-Bytes 0x54662B 4)) -eq '0F AF 43 44'))
Check ('start field hook 0x{0:X}: ADD EAX,0x1F4' -f $script:TibStartHookAt) ((Hex (Get-Bytes $script:TibStartHookAt 5)) -eq (Hex $script:TibStartHookOrig))
Check 'context: the start field amount goes to FUN_005468F0 (CALL 0x5468F0 at 0x5468CA)' ((Hex (Get-Bytes 0x5468CA 5)) -eq 'E8 21 00 00 00')
"computer opponents:"
Check ('repair flag test 0x{0:X}: JNZ +0x14D' -f $script:RepairPatch.At) ((Hex (Get-Bytes $script:RepairPatch.At 6)) -eq (Hex $script:RepairPatch.Orig))
Check 'context: MOV AL,[ECX+0x118]; TEST AL,AL before' ((Hex (Get-Bytes 0x4355C8 8)) -eq '8A 81 18 01 00 00 84 C0')
Check 'the patched jump skips to the end of the building AI (0x435723)' ((0x4355D6 + 0x14D) -eq 0x435723)

"random map sliders (with a stand-in for the game's memory):"
# the generator object as the game has it at the start: players 2, Tiberium 1, all other sliders 0
$fake = New-Object PSObject -Property @{ Mem = @{} }
$fake | Add-Member ScriptMethod ReadInt { param([uint32]$a) if ($this.Mem.ContainsKey($a)) { $this.Mem[$a] } else { 0 } }
$fake | Add-Member ScriptMethod Write { param([uint32]$a, [byte[]]$b) $this.Mem[$a] = [BitConverter]::ToInt32($b, 0) }
$fake.Mem[[uint32]($script:RmgObject + $script:RmgFields.Players)] = 2
$fake.Mem[[uint32]($script:RmgObject + $script:RmgFields.Tiberium)] = 1
$r = Set-RmgSliders $fake $script:TerrainSliders['flat'] 'flat'
$ok = $true; foreach ($k in $script:TerrainSliders['flat'].Keys) { if ($fake.ReadInt([uint32]($script:RmgObject + $script:RmgFields[$k])) -ne $script:TerrainSliders['flat'][$k]) { $ok = $false } }
Check "flat: $r" $ok
Check 'flat: Tiberium slider untouched (1)' ($fake.ReadInt([uint32]($script:RmgObject + $script:RmgFields.Tiberium)) -eq 1)
Check ('field offsets match the dialog code (FUN_0053A8C0): RegionSize +0x64, Ruggedness +0x38, Accessibility +0x60') ($script:RmgFields.RegionSize -eq 0x64 -and $script:RmgFields.Ruggedness -eq 0x38 -and $script:RmgFields.Accessibility -eq 0x60)
$empty = New-Object PSObject -Property @{ Mem = @{} }
$empty | Add-Member ScriptMethod ReadInt { param([uint32]$a) 0 }
$empty | Add-Member ScriptMethod Write { param([uint32]$a, [byte[]]$b) $this.Mem[$a] = 1 }
$r = Set-RmgSliders $empty $script:TerrainSliders['rugged'] 'rugged'
Check "unexpected object (players 0): nothing written - $r" ($empty.Mem.Count -eq 0 -and $r -match 'unexpected')
foreach ($n in $script:TerrainSliders.Keys) { foreach ($k in $script:TerrainSliders[$n].Keys) { if (-not $script:RmgFields.Contains($k) -or $script:TerrainSliders[$n][$k] -lt 0 -or $script:TerrainSliders[$n][$k] -gt 100) { Check "$n $k is a known slider 0..100" $false } } }
Check 'every terrain value is a known slider within 0..100' $true

if ($errors) { "$errors errors"; exit 1 } else { 'all patch checks ok' }
