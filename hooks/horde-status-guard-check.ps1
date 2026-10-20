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
# -RestoreFolders: the folders (joined by *) the hook may put a last good copy back into. A bad card in any other
# folder is only reported (outcome "reported"): it may be another Orc's edit in progress, and blaming and
# overwriting it from someone else's command is wrong.
#
# THE CARD IS READ AGAIN right before the restore, and the restore is skipped when its bytes are not those
# the verdict was made on: a good `horde status set` may have landed in between.
#
# HORDE_STATUS_GUARD_TEST_REWRITE (tests only): a file whose bytes are written over status.txt just before
# that second read, standing in for a write that lands in the window.
#
# HORDE_STATUS_GUARD_MARKER (tests only): a file this script appends one line to when it runs, so a
# test can prove that a payload the hook should ignore never reached here.
param(
    [Parameter(Mandatory = $true)][string]$Folders,
    [string]$RestoreFolders = ''
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
function Write-StatusGuardFile([string]$Path, [byte[]]$Bytes, $Mtime = $null) {
    $temp = $Path + '.tmp-' + [guid]::NewGuid().ToString('N')
    try {
        [System.IO.File]::WriteAllBytes($temp, $Bytes)
        # The panel's "as of" is the file's modified time, so a restored card keeps its copy's, not "now".
        if ($null -ne $Mtime) { [System.IO.File]::SetLastWriteTimeUtc($temp, $Mtime) }
        Move-HordeFileAtomic -From $temp -To $Path
    } finally {
        if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) }
    }
}

$rejected = 0
function Get-NormalPath([string]$p) { return ([System.IO.Path]::GetFullPath($p).TrimEnd('\', '/')).ToLowerInvariant() }
$allowed = @{}
foreach ($rf in @($RestoreFolders -split '\*')) { if ($rf -ne '' -and $rf -ne '-') { $allowed[(Get-NormalPath $rf)] = $true } }
$list = @($Folders -split '\*')
for ($i = 0; $i -lt $list.Count; $i++) {
    $dir = $list[$i]
    if ($dir -eq '') { continue }
    $file = Join-Path $dir $script:HordeFleetStatusFile
    if (-not [System.IO.File]::Exists($file)) { continue }
    # The bytes the verdict is made on are read FIRST, so a change after this point is seen at the restore.
    # A card past the size cap is not read into memory: its length and modified time stand in for its bytes.
    $seen = $null
    $seenInfo = New-Object System.IO.FileInfo($file)
    $seenLength = $seenInfo.Length; $seenTicks = $seenInfo.LastWriteTimeUtc.Ticks
    if ($seenLength -le $script:HordeFleetStatusMostBytes) { $seen = Read-StatusGuardBytes $file }
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
    $outcome = 'left'
    $mayRestore = $allowed.ContainsKey((Get-NormalPath $dir))
    if ($env:HORDE_STATUS_GUARD_TEST_REWRITE) { [System.IO.File]::WriteAllBytes($file, [System.IO.File]::ReadAllBytes($env:HORDE_STATUS_GUARD_TEST_REWRITE)) }
    if ([System.IO.File]::Exists($file)) {
        if ($null -ne $seen) {
            $now = Read-StatusGuardBytes $file
            if ($now.Length -ne $seen.Length -or [System.Convert]::ToBase64String($now) -cne [System.Convert]::ToBase64String($seen)) { continue }
        } else {
            $nowInfo = New-Object System.IO.FileInfo($file)
            if ($nowInfo.Length -ne $seenLength -or $nowInfo.LastWriteTimeUtc.Ticks -ne $seenTicks) { continue }
        }
    }
    $rejected++
    if (-not $mayRestore) { $outcome = 'reported' }
    elseif ([System.IO.File]::Exists($good)) {
        $goodInfo = New-Object System.IO.FileInfo($good)
        if ($goodInfo.Length -le $script:HordeFleetStatusMostBytes) {
            $goodBytes = Read-StatusGuardBytes $good
            if ((ConvertFrom-HordeFleetStatusBytes -Bytes $goodBytes).problems.Count -eq 0) {
                Write-StatusGuardFile $file $goodBytes $goodInfo.LastWriteTimeUtc
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
