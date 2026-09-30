# core/ReadShared - the one way Horde reads a file that another system is writing.
#
# WHY IT IS ITS OWN FUNCTION. Horde reads the stores of the systems it is replacing while they are
# still running. wezfleet writes a record by writing a temp file and swapping it into place with
# [System.IO.File]::Replace. Measured 2026-09-29: while a reader holds the record open with the
# ordinary read share - which is what [System.IO.File]::ReadAllText uses - that Replace FAILS with
# "being used by another process". Opened with read, write and delete sharing, the Replace succeeds.
# So a Horde reader using the obvious call would make wezfleet's writes fail at random, just by reading.
#
# Everything in Horde that reads another system's file goes through Read-HordeSharedText.

# No Set-StrictMode here: this file is dot-sourced, so a file-scope Set-StrictMode would set the
# caller's mode (see core/Tristate.ps1). The functions run under -Version Latest.

function Open-HordeSharedStream {
    # A read-only stream that shares read, write and delete. The caller disposes it.
    param([Parameter(Mandatory = $true)][string]$Path)
    $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    return [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
}

function Read-HordeSharedText {
    # The whole text of a file, opened for reading only, and sharing read, write and delete so the
    # writer it belongs to is never blocked. Throws if the file cannot be read; the caller turns that
    # into an unknown.
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = Open-HordeSharedStream -Path $Path
    try {
        $reader = New-Object System.IO.StreamReader($stream, $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}
