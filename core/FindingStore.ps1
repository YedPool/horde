# core/FindingStore - keep a finding on this machine: one file per finding under <HORDE_HOME>\findings.
#
# LOCAL ONLY. This file writes to the local disk and does nothing else: no network, no transport, no
# remote call, no message to any session. Carrying findings off the machine is a later piece, over the
# remote link, and will read these files; nothing here prepares or announces them for it.
#
# THE RULES, and what makes each one hold:
#   - ONLY A FINDING core/Finding.ps1 READS IS WRITTEN. The text is read first; a refused text is
#     answered "refused" with its reasons, and nothing is created - no folder, no file.
#   - THE TEXT IS KEPT EXACTLY AS GIVEN. It has passed the ASCII check, so its bytes are its characters.
#   - A FILE'S NAME IS ITS CONTENT: finding-<the first 32 hex digits of the SHA-256 of its bytes>.json.
#     No clock and no counter: the same finding written twice is one file, and the second write is
#     answered "exists". 128 bits of a hash make two different findings with one name a thing that
#     does not happen by chance.
#   - NEVER OVERWRITTEN. The text is written whole into a temporary file of this writer's own
#     (writing-<32 hex>.part), held open and flushed to disk, and then given its name by
#     core/FileAtomic.ps1's Move-HordeFileNewDurable, a durable move that does not replace: if the name
#     is taken, the move says so and the file that has it is untouched. The order and what a kill at
#     each step leaves are decisions/Store.ps1's, whose write this is; that header has the measurements.
#   - A FINDING IS NEVER SEEN HALF-WRITTEN: it has no name until it is whole.
# THE LIMIT: a writer killed before the move leaves its .part file. Nothing sweeps it yet; it is never
# read as a finding, because only finding-*.json is one.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Finding.ps1")
. (Join-Path $PSScriptRoot "Home.ps1")
. (Join-Path $PSScriptRoot "FileAtomic.ps1")

$script:HordeFindingFolder = "findings"

function Get-HordeFindingFileName {
    # The file name a finding's text is kept under.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = $sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($Text)) } finally { $sha.Dispose() }
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $digest[0..15]) { [void]$sb.Append($b.ToString("x2")) }
    return ("finding-" + $sb.ToString() + ".json")
}

function Save-HordeFinding {
    # Keep a finding's text under <home>\findings. Returns { state; path; findings }:
    #   "written"      the file is in place, and everything that makes it durable returned success;
    #   "exists"       a file of that name - the same finding - is already there; it was not touched;
    #   "unconfirmed"  the file HAS its name, but the flush after the move failed. Not "written";
    #   "refused"      core/Finding.ps1 refused the text; findings says why, and nothing was created.
    # Throws when the folder or the file cannot be made, or the move fails any other way. Without
    # -HordeHome the home is Horde's own (core/Home.ps1).
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [string]$HordeHome = "")
    $read = Read-HordeFindingText -Text $Text
    if ($read.state -cne "read") { return [pscustomobject]@{ state = "refused"; path = ""; findings = [string[]]@($read.findings) } }
    $base = $HordeHome
    if ($base -eq "") { $base = Get-HordeHome }
    elseif (-not [System.IO.Path]::IsPathRooted($base)) { throw ("-HordeHome must be an absolute path, not '" + $base + "'") }
    $folder = [System.IO.Path]::Combine($base, $script:HordeFindingFolder)
    [void][System.IO.Directory]::CreateDirectory($folder)
    $target = [System.IO.Path]::Combine($folder, (Get-HordeFindingFileName -Text $Text))
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Text)
    $tmpPath = [System.IO.Path]::Combine($folder, ("writing-" + [guid]::NewGuid().ToString("N") + ".part"))
    # Sharing delete and nothing else: the file can be renamed while this handle is open, and nothing
    # can read or write it until it is whole and let go.
    $fs = New-Object System.IO.FileStream($tmpPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Delete, 4096, [System.IO.FileOptions]::WriteThrough)
    $moved = ""
    try {
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush($true)
        $moved = Move-HordeFileNewDurable -From $tmpPath -To $target -Open $fs
    } finally {
        $fs.Dispose()
        if ($moved -cne "moved" -and $moved -cne "unconfirmed") { try { [System.IO.File]::Delete($tmpPath) } catch { } }
    }
    if ($moved -ceq "moved") { return [pscustomobject]@{ state = "written"; path = $target; findings = [string[]]@() } }
    if ($moved -ceq "unconfirmed") { return [pscustomobject]@{ state = "unconfirmed"; path = $target; findings = [string[]]@("the finding has its name, but the flush after the move failed, so nothing says it is on disk") } }
    # "exists" only when a FILE has the name: a folder of that name is no finding.
    if ($moved -ceq "exists" -and [System.IO.File]::Exists($target)) { return [pscustomobject]@{ state = "exists"; path = $target; findings = [string[]]@() } }
    throw ("the finding could not be put in place: its name is taken by something that is not a finding (the move answered '" + $moved + "')")
}
