# core/Fingerprints.ps1 - a folder's list of pinned files, and whether the files still match it.
#
# WHY. Horde depended on nothing outside Windows until an adapter needed a program library it cannot
# be written without (decisions design, 2026-10-06, section 3.11). A file brought in from elsewhere is
# committed beside a list of fingerprints, one line per file:
#
#   <file name> | <sha256, 64 lowercase hex> | <what it is and where it came from>
#
# and it is changed only by a pull request that changes the file and its line together. Two readers
# hold a folder to its list, and both read it through this file so that they cannot come to differ:
#   - the adapter that loads the files checks them BEFORE loading, and refuses on a mismatch;
#   - tools/HostNames.ps1, which otherwise refuses every byte that is not printable ASCII, lets a
#     listed file through without reading it as text, and fails when one no longer matches its line.
#
# A NAME IS A FILE NAME IN THE LIST'S OWN FOLDER, never a path: a list cannot pin, or excuse, a file
# anywhere else. Blank lines and lines beginning with # are ignored.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeFingerprintListName = "fingerprints.txt"

function Get-HordeFingerprintListName { return $script:HordeFingerprintListName }

function Get-HordeFileSha256 {
    # A file's SHA-256 as 64 lowercase hex digits. The file is read whole, shared for reading.
    param([Parameter(Mandatory = $true)][string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try { return (-join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") })) }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Read-HordeFingerprintList {
    # The lines of a fingerprint list as { entries; problems }: entries are { name; sha256; what; line },
    # problems the malformed lines in words. A line that is malformed pins nothing.
    param([Parameter(Mandatory = $true)][string]$Path)
    $entries = New-Object System.Collections.ArrayList
    $problems = New-Object System.Collections.ArrayList
    $seen = @{}
    $n = 0
    foreach ($raw in ([System.IO.File]::ReadAllText($Path) -split "`n")) {
        $n++
        $t = $raw.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        $cells = @($t -split "\|" | ForEach-Object { $_.Trim() })
        if ($cells.Count -ne 3) { [void]$problems.Add("line " + $n + " is not '<file name> | <sha256> | <what it is and where it came from>'"); continue }
        # A NAME, NEVER A PATH: no separator, no drive, no "..", so the list reaches only its own folder.
        if ($cells[0] -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z' -or $cells[0].Contains("..")) { [void]$problems.Add("line " + $n + " names '" + $cells[0] + "', which is not a plain file name in this folder"); continue }
        if ($cells[1] -cnotmatch '\A[0-9a-f]{64}\z') { [void]$problems.Add("line " + $n + " gives no SHA-256 for " + $cells[0] + ": 64 lowercase hex digits are wanted"); continue }
        if ($cells[2] -eq "") { [void]$problems.Add("line " + $n + " does not say what " + $cells[0] + " is or where it came from"); continue }
        # A plain @{} ignores case, as the file system does: A.DLL and a.dll are one file listed twice.
        $key = $cells[0]
        if ($seen.ContainsKey($key)) { [void]$problems.Add("line " + $n + " lists " + $cells[0] + " a second time"); continue }
        $seen[$key] = $true
        [void]$entries.Add([pscustomobject]@{ name = $cells[0]; sha256 = $cells[1]; what = $cells[2]; line = $n })
    }
    return [pscustomobject]@{ entries = @($entries); problems = @($problems) }
}

function Test-HordeFingerprints {
    # Is every file the list in -Folder names there, with exactly the fingerprint its line gives?
    # Returns { ok; findings; files }: findings in words, empty when ok; files the full paths of the
    # listed files, in the list's order, for a caller that goes on to load them. A folder with no list
    # is not ok: nothing in it is pinned.
    param([Parameter(Mandatory = $true)][string]$Folder)
    $findings = New-Object System.Collections.ArrayList
    $files = New-Object System.Collections.ArrayList
    $listPath = Join-Path $Folder $script:HordeFingerprintListName
    if (-not (Test-Path -LiteralPath $listPath -PathType Leaf)) {
        return [pscustomobject]@{ ok = $false; findings = @("there is no " + $script:HordeFingerprintListName + " in " + $Folder + ", so nothing there is pinned"); files = @() }
    }
    $read = Read-HordeFingerprintList -Path $listPath
    foreach ($p in $read.problems) { [void]$findings.Add($script:HordeFingerprintListName + ": " + $p) }
    if (@($read.entries).Count -eq 0) { [void]$findings.Add($script:HordeFingerprintListName + " lists no file") }
    foreach ($e in $read.entries) {
        $full = Join-Path $Folder $e.name
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { [void]$findings.Add($e.name + " is listed and is not there"); continue }
        $actual = ""
        try { $actual = Get-HordeFileSha256 -Path $full } catch { [void]$findings.Add($e.name + " could not be read to check its fingerprint: " + $_.Exception.Message); continue }
        if ($actual -cne $e.sha256) { [void]$findings.Add($e.name + " does not match its fingerprint: the list says " + $e.sha256 + " and the file is " + $actual); continue }
        [void]$files.Add($full)
    }
    return [pscustomobject]@{ ok = ($findings.Count -eq 0); findings = @($findings); files = @($files) }
}
