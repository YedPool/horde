# core/FileAtomic - replace a file whole, in one step.
#
# WHY ITS OWN FILE. It was core/MetricsStore.ps1's (review of PR #70); the hub's mirror files need the same
# write (review of PR #86, F3: File.Replace failed while a reader held the mirror with ordinary read
# sharing, and Win32 ReplaceFile works in steps), so it moved here, unchanged, for both.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

function Move-HordeFileAtomic {
    # Rename -From over -To in ONE step: MoveFileEx with REPLACE_EXISTING and WRITE_THROUGH, a single
    # rename on NTFS. Review of PR #70 measured why File.Replace is not enough: Win32 ReplaceFile works in
    # steps, and one of 40 kills inside it left NO index - the new one only in its temp file. A rename is
    # all or nothing: a kill leaves the old file or the new one, never neither. A reader holding the file
    # without delete sharing makes the rename fail for a moment; it is tried again for up to 2 s.
    param([Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$To)
    if (-not ([System.Management.Automation.PSTypeName]"HordeNative.FileMove").Type) {
        Add-Type -Namespace HordeNative -Name FileMove -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);'
    }
    $err = 0
    for ($i = 0; $i -lt 20; $i++) {
        # 0x1 MOVEFILE_REPLACE_EXISTING, 0x8 MOVEFILE_WRITE_THROUGH.
        if ([HordeNative.FileMove]::MoveFileEx($From, $To, 0x9)) { return }
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Start-Sleep -Milliseconds 100
    }
    throw (New-Object System.ComponentModel.Win32Exception($err))
}

# A MOVE TO A NAME NOTHING HAS, ON DISK WHEN IT RETURNS (added for decisions/Store.ps1, whose records are
# written under a temporary name and moved to their own; any write-once file can use it).
#
# THIS IS WHERE THE PLATFORM IS. A caller asks for "this file, under that name, only if the name is free,
# and durably", and is answered in words; how that is done is this file's. Today that is Windows. Another
# system supplies a function of this name and contract - on POSIX: link() or renameat2(RENAME_NOREPLACE),
# then fsync of the folder - and no caller changes. Asked on a system this file has no move for, it
# refuses in words; it never falls back to a move that is not durable, because the caller would then
# tell its own caller "saved" on the strength of a promise nobody kept.
#
# TWO MEANS, BECAUSE NEITHER CAN BE SEEN TO WORK WITHOUT CUTTING THE POWER:
#   1. MoveFileEx with MOVEFILE_WRITE_THROUGH and WITHOUT MOVEFILE_REPLACE_EXISTING. Documented: "the
#      function does not return until the file is actually moved on the disk".
#   2. When the caller still holds the file open (-Open), that handle is flushed after the move
#      (FileStream.Flush($true), which is FlushFileBuffers). On NTFS a flush of a file forces the
#      volume's log to disk up to that moment, and the rename is a record in that log.
# Measured 2026-10-06 on the development machine (NTFS on an SSD), 200 pairs, medians, a 600-byte file
# already flushed: a write-through move 0.44 ms and the flush after it 0.15 ms; a plain move 0.31 ms
# and the flush after it 0.24 ms. So the flag does move work into the rename - about what the later
# flush then no longer has to do - which is what a forced log write would look like. THAT IS EVIDENCE
# THE FLAG IS HONOURED, NOT PROOF THE RENAME SURVIVES A POWER CUT: no test here can cut the power, and a
# disk that acknowledges a flush it has not done defeats both means alike.
#
# THE NATIVE SIGNATURE IS WRITTEN A SECOND TIME BELOW, the same type under the same name as above, so
# that whichever function runs first defines it. Folding the two into one loader is a change to
# Move-HordeFileAtomic, which the metrics store and the hub's mirror run on; it is left for a change
# of its own.
function Get-HordeFileMoveNewFlags {
    # The MoveFileEx flags of a durable move that must not replace: 0x8 MOVEFILE_WRITE_THROUGH, alone.
    # 0x1 MOVEFILE_REPLACE_EXISTING is deliberately absent: with it, two writers would both succeed.
    return 0x8
}

function Confirm-HordeFileFlushed {
    # THE ONE FLUSH PATH. Flush an open stream through to the disk (FileStream.Flush($true), which is
    # FlushFileBuffers): "confirmed" when it returned, "unconfirmed" when it failed. Both callers below
    # come through here, so "what was done to put this on disk" has one answer and one place to test.
    param($Open)
    try { $Open.Flush($true) } catch { return "unconfirmed" }
    return "confirmed"
}

function Confirm-HordeFileDurable {
    # Have a file that already exists flushed through to the disk, name included: for a caller that
    # was once told "unconfirmed" and is asked again, or that must be sure before it says "saved".
    # Returns "confirmed", "unconfirmed" (it could not be opened for the flush, or the flush failed)
    # or "missing" (there is no such file). NOTHING IS WRITTEN TO THE FILE: it is opened as it is -
    # never created, never truncated - only because a flush is asked of a handle, and a handle that
    # may flush must be open for writing. It shares everything, so it never stands in a reader's way.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return "missing" }
    $held = $null
    try { $held = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)) }
    catch { return "unconfirmed" }
    try { return (Confirm-HordeFileFlushed -Open $held) } finally { $held.Dispose() }
}

function Move-HordeFileNewDurable {
    # Give the file -From the name -To, only if nothing has that name. Returns
    #   "moved"        the file has the name, and both means above returned success;
    #   "exists"       something already has the name; -From is untouched;
    #   "unconfirmed"  the file HAS the name, but the flush after the move failed, so nothing says the
    #                  rename is on disk. The caller must not report the file as saved.
    # Anything else throws, with -From untouched. -Open is the caller's own open stream on -From, or
    # $null: a file may be renamed while it is held open with delete sharing, and the caller that
    # holds it never has a moment when its file exists and nothing shows a writer is alive.
    param([Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$To, $Open = $null, $OsPlatform = [System.Environment]::OSVersion.Platform)
    if ("" + $OsPlatform -cne "Win32NT") { throw ("there is no durable move for this system yet (" + $OsPlatform + "): core/FileAtomic.ps1 has only the Windows one, and a move that is not durable is never used in its place") }
    if (-not ([System.Management.Automation.PSTypeName]"HordeNative.FileMove").Type) {
        Add-Type -Namespace HordeNative -Name FileMove -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);'
    }
    if (-not [HordeNative.FileMove]::MoveFileEx($From, $To, (Get-HordeFileMoveNewFlags))) {
        $moveError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        # 80 ERROR_FILE_EXISTS, 183 ERROR_ALREADY_EXISTS (measured 2026-10-06: 183 for a file and for a
        # folder of that name alike; which of the two it is, is the caller's to ask).
        if ($moveError -eq 80 -or $moveError -eq 183) { return "exists" }
        throw (New-Object System.ComponentModel.Win32Exception($moveError))
    }
    if ($null -ne $Open -and (Confirm-HordeFileFlushed -Open $Open) -cne "confirmed") { return "unconfirmed" }
    return "moved"
}
