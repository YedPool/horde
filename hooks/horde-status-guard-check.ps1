# horde-status-guard-check - the PowerShell half of the status guard hook (see horde-status-guard.mjs).
#
# Given the lane folders the hook found to look at, it reads each status.txt with THE PANEL'S OWN
# reader (fleet/StatusPanel.ps1, resolved from this file's place, so the hook and the panel cannot
# disagree about what a card is) and does one of three things per folder:
#   clean      copy the bytes to .status.last-good.txt (whole, by rename); say nothing.
#   rejected   put .status.last-good.txt back as status.txt (whole, by rename) when that copy itself
#              reads clean; otherwise leave the bad file. Say which, and every problem.
#   (no file)  a folder with no status.txt is not this hook's business.
# status.retired.txt is never looked at: only the one name status.txt is read.
#
# OUTPUT, one line per rejected folder, tab separated, ASCII only:
#   rejected <TAB> <index into -Folders> <TAB> restored|left <TAB> <problem> [<TAB> <problem> ...]
# Folders are named by index so no path is ever sent through a console code page. Exit 0 when every
# folder was clean or absent, 3 when any was rejected. The caller turns 3 into the hook's exit 2.
#
# HORDE_STATUS_GUARD_MARKER (tests only): a file this script appends one line to when it runs, so a
# test can prove that a payload the hook should ignore never reached here.
param(
    [Parameter(Mandatory = $true)][string]$Folders
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'core\FileAtomic.ps1')
. (Join-Path $repo 'fleet\StatusPanel.ps1')

if ($env:HORDE_STATUS_GUARD_MARKER) {
    [System.IO.File]::AppendAllText($env:HORDE_STATUS_GUARD_MARKER, "checked`n")
}

$lastGood = '.status.last-good.txt'

function Format-StatusGuardText([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace '[^\x20-\x7e]', '?')
}
function Read-StatusGuardBytes([string]$Path) {
    # Shared for reading, writing and deleting: the Orc replaces the file whole, and this must never be why that fails.
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try {
        $bytes = New-Object byte[] $stream.Length
        $got = 0
        while ($got -lt $bytes.Length) { $n = $stream.Read($bytes, $got, $bytes.Length - $got); if ($n -le 0) { break }; $got += $n }
        return $bytes
    } finally { $stream.Dispose() }
}
function Write-StatusGuardFile([string]$Path, [byte[]]$Bytes) {
    $temp = $Path + '.tmp-' + [guid]::NewGuid().ToString('N')
    try {
        [System.IO.File]::WriteAllBytes($temp, $Bytes)
        Move-HordeFileAtomic -From $temp -To $Path
    } finally {
        if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) }
    }
}

$rejected = 0
$list = @($Folders -split '\*')
for ($i = 0; $i -lt $list.Count; $i++) {
    $dir = $list[$i]
    if ($dir -eq '') { continue }
    $file = Join-Path $dir $script:HordeFleetStatusFile
    if (-not [System.IO.File]::Exists($file)) { continue }
    $read = Read-HordeFleetStatusFolder -Path $dir
    $good = Join-Path $dir $lastGood
    if ($read.written) {
        # Copy what the panel just accepted. A re-read of the bytes, not of the verdict, so the copy is
        # the file as it is now; a card changed in between is checked again by the next call.
        $bytes = Read-StatusGuardBytes $file
        $check = ConvertFrom-HordeFleetStatusBytes -Bytes $bytes
        if ($check.problems.Count -eq 0) {
            $same = $false
            if ([System.IO.File]::Exists($good)) {
                $old = Read-StatusGuardBytes $good
                $same = ($old.Length -eq $bytes.Length) -and ([System.Convert]::ToBase64String($old) -ceq [System.Convert]::ToBase64String($bytes))
            }
            if (-not $same) { Write-StatusGuardFile $good $bytes }
        }
        continue
    }
    $rejected++
    $outcome = 'left'
    if ([System.IO.File]::Exists($good)) {
        $goodInfo = New-Object System.IO.FileInfo($good)
        if ($goodInfo.Length -le $script:HordeFleetStatusMostBytes) {
            $goodBytes = Read-StatusGuardBytes $good
            if ((ConvertFrom-HordeFleetStatusBytes -Bytes $goodBytes).problems.Count -eq 0) {
                Write-StatusGuardFile $file $goodBytes
                $outcome = 'restored'
            }
        }
    }
    $cols = @('rejected', "$i", $outcome)
    foreach ($p in @($read.problems)) { $cols += (Format-StatusGuardText "$p") }
    [Console]::Out.WriteLine(($cols -join "`t"))
}
if ($rejected -gt 0) { exit 3 }
exit 0
