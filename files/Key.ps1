# files/Key.ps1 - the machine's own key, which file ids are made with.
#
# THE ONE JOB of this file: make that key once, and hand it to files/Share.ps1 every time after.
#
# WHY THERE IS A KEY. A file id is worked out from the sharing session and the file's path, and a
# record leaves the machine. Until 2026-10-13 the id was a plain SHA-256 of the two, and the session
# id sits in the same record: whoever held a record could try paths until one gave the id, and so
# learn the path the record is careful not to hold (review of the files store). With a key only this
# machine has, the id is an HMAC, and a guess cannot be checked without the key.
#
# THE KEY: 32 bytes from the system's cryptographic generator, in <HordeHome>\keys\files-id.key.
#   - IT NEVER LEAVES THIS FILE'S RETURN VALUE. It is in no record, no message, no error and no log:
#     every reason below names the FILE, never a byte of it.
#   - ONLY THE CURRENT USER MAY OPEN IT. The file is CREATED with its access list - owner the current
#     user, inheritance off, one entry: that user, full control - so there is no moment when it
#     exists under the folder's inherited list. Measured 2026-10-13: the list is on the file after
#     the move to its name (O:<user>D:P(A;;FA;;;<user>)).
#   - IT IS MADE ONCE, BY THE MOVE THAT DOES NOT REPLACE (core/FileAtomic.ps1, as every store entry
#     is). Two first shares at one moment each write a key of their own under a temporary name; the
#     operating system lets one move succeed; and BOTH then read the key from the file that has the
#     name, the winner too. So there is one key, and what every share uses is what is on disk.
#     test/test-files-race.ps1 races processes for it, and against a copy that overwrites.
#   - A KEY THAT IS GONE OR DAMAGED IS A REFUSAL, NEVER A NEW KEY. A new key gives every file a new
#     id: the same path shared again would start a second file at version 1 and nothing would say
#     so. So a key is made only while the store holds no record. Once it holds one, a key file that
#     is missing, empty, cut short, too long, all zeros (how a file whose blocks were never written
#     reads after a power cut), a link, a folder, or not readable refuses the share with the reason.
#     WHAT THIS DOES NOT SEE: a key replaced by another whole key of 32 bytes; and a store emptied
#     of its records together with the key, which is a new store.
#
# WHY NOT core/Secrets.ps1: that file is the one list of what text LOOKS like a credential, to refuse
# or hide it; it keeps nothing. This file follows its rule that a finding names the kind and never
# repeats the value.
#
# A key writer killed before its move leaves its temporary file: 32 random bytes that were never the
# key, readable by the user alone. It is not swept; it is not the key and names nothing.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\FileAtomic.ps1")
. (Join-Path $PSScriptRoot "Store.ps1")

function Get-HordeFilesRuntimeRefusal {
    # Why a file may not be shared under this runtime, or "" under Windows PowerShell 5.1.
    # THE KEY FILE IS CREATED WITH ITS ACCESS LIST (New-HordeFilesKey), by a FileStream constructor
    # that only the .NET Framework has. Measured 2026-10-13 under PowerShell 7.6.6: a first share
    # threw "Cannot find an overload for FileStream and the argument count: 7", after the keys
    # folder had been made. Making the key another way there - created first, its list set after -
    # would leave a moment when it stands under the folder's inherited list, which is what the
    # constructor is for. So nothing is shared there, and the share says so before it looks at
    # anything or makes anything (files/Share.ps1 asks this first).
    # -Edition and -Version are for a test that must ask of a runtime it is not running under.
    param([string]$Edition = ("" + $PSVersionTable.PSEdition), [string]$Version = ("" + $PSVersionTable.PSVersion))
    if ($Edition -ceq "Desktop") { return "" }
    return ("files are shared under Windows PowerShell 5.1 only, and this is PowerShell " + $Version + ": the key that file ids are made with must be created readable by this user alone, which this runtime has no way to do in one step. Nothing was shared and nothing was made; run the command with powershell.exe")
}

function Get-HordeFilesKeyLength {
    # The length of the key in bytes: HMAC-SHA-256's own block of output, and of the generator's draw.
    return 32
}

function Get-HordeFilesKeyPath {
    # Where the key is: <home>\keys\files-id.key. A path only; nothing is looked at or made.
    param([string]$HordeHome = "")
    $base = $HordeHome
    if ($base -eq "") { $base = Get-HordeHome }
    return (Join-Path (Join-Path $base "keys") "files-id.key")
}

function Read-HordeFilesKey {
    # Read the key file: { state: ok | absent | refused; key; reason }. absent is "no file of that
    # name"; anything that is there and is not a whole key is refused, with why. A file another
    # process holds for a moment is tried again, as a record is (files/Store.ps1).
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][int]$HeldTries, [Parameter(Mandatory = $true)][int]$HeldWaitMs)
    $refuse = { param([string]$Why) return [pscustomobject]@{ state = "refused"; key = $null; reason = ("the key that file ids are made with, '" + $Path + "', " + $Why) } }
    if ([System.IO.Directory]::Exists($Path)) { return (& $refuse "is a folder, not a file") }
    if (-not [System.IO.File]::Exists($Path)) { return [pscustomobject]@{ state = "absent"; key = $null; reason = "" } }
    if (Test-HordeFilesStoreLink -Path $Path) { return (& $refuse "is a link, or cannot be looked at; a key is never read through a link") }
    $want = Get-HordeFilesKeyLength
    $busyCodes = (Get-HordeFilesStoreFormat).busyCodes
    # One byte more than a key is asked for, so a file that is too long is seen and never read whole.
    $buffer = New-Object byte[] ($want + 1)
    $have = 0
    for ($try = 1; $try -le $HeldTries; $try++) {
        $busy = $false
        try {
            $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try {
                $have = 0
                while ($have -lt $buffer.Length) {
                    $got = $stream.Read($buffer, $have, $buffer.Length - $have)
                    if ($got -le 0) { break }
                    $have += $got
                }
            } finally { $stream.Dispose() }
        } catch {
            if ($busyCodes -contains (Get-HordeFilesStoreWin32Code $_)) { $busy = $true }
            else { return (& $refuse ("cannot be read: " + $_.Exception.GetBaseException().Message)) }
        }
        if (-not $busy) { break }
        if ($try -eq $HeldTries) { return (& $refuse ("is still held by another process after " + ($HeldTries * $HeldWaitMs) + " ms")) }
        Start-Sleep -Milliseconds $HeldWaitMs
    }
    if ($have -ne $want) { return (& $refuse ("is not a key: a key is " + $want + " bytes, and it is " + $(if ($have -gt $want) { "longer" } else { "" + $have + " bytes" }) + "; it is empty, was cut short, or is another file")) }
    $key = New-Object byte[] $want
    [Array]::Copy($buffer, $key, $want)
    if (@($key | Where-Object { $_ -ne 0 }).Count -eq 0) { return (& $refuse "is all zero bytes: it was never written through to the disk, and is no key") }
    return [pscustomobject]@{ state = "ok"; key = $key; reason = "" }
}

function New-HordeFilesKey {
    # Make a key and give it the name -Path, only if nothing has that name: "created" or "exists".
    # The header says how. Throws when the folder or the file cannot be made. The key is not
    # returned: whoever made it reads it back like everybody else.
    param([Parameter(Mandatory = $true)][string]$Path)
    $folder = [System.IO.Path]::GetDirectoryName($Path)
    [void][System.IO.Directory]::CreateDirectory($folder)
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $access = New-Object System.Security.AccessControl.FileSecurity
    $access.SetOwner($user)
    # Protected, and inherited entries not kept: the folder's list gives this file nothing.
    $access.SetAccessRuleProtection($true, $false)
    $access.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($user, [System.Security.AccessControl.FileSystemRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)))
    $fresh = New-Object byte[] (Get-HordeFilesKeyLength)
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($fresh) } finally { $generator.Dispose() }
    $tmpPath = Join-Path $folder ("making-" + [guid]::NewGuid().ToString("N") + ".part")
    $moved = ""
    try {
        $out = New-Object System.IO.FileStream($tmpPath, [System.IO.FileMode]::CreateNew, [System.Security.AccessControl.FileSystemRights]::FullControl, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::WriteThrough, $access)
        # Written, flushed and LET GO before the move: the file is whole on disk when it takes its
        # name, and no reader of the name ever finds its maker still holding it.
        try { $out.Write($fresh, 0, $fresh.Length); $out.Flush($true) } finally { $out.Dispose() }
        $moved = Move-HordeFileNewDurable -From $tmpPath -To $Path
    } finally {
        [Array]::Clear($fresh, 0, $fresh.Length)
        if ($moved -cne "moved") { try { [System.IO.File]::Delete($tmpPath) } catch { } }
    }
    if ($moved -ceq "moved") { return "created" }
    return "exists"
}

function Test-HordeFilesStoreHasRecord {
    # Does the store folder hold any file named as a record? By names alone: a damaged record was
    # still given an id made with the key.
    param([Parameter(Mandatory = $true)][string]$Root)
    if (-not [System.IO.Directory]::Exists($Root)) { return $false }
    $format = Get-HordeFilesStoreFormat
    foreach ($full in @([System.IO.Directory]::GetFiles($Root, "*.json"))) { if ([System.IO.Path]::GetFileName($full) -cmatch $format.record) { return $true } }
    return $false
}

function Get-HordeFilesKey {
    # The key for the home -HordeHome: { ok; key; reason }. Made now if this is the home's first
    # share; refused, never made again, once the home's store holds a record.
    # THE STORE THAT IS LOOKED IN IS THE HOME'S OWN, never one the caller names. Until 2026-10-13 it
    # was the caller's -Root: measured that day, a home whose store held records and whose key was
    # gone, shared into with -Root an empty folder, was given a NEW key in silence - the very thing
    # the refusal exists to stop. The key belongs to the home, so the home's store answers for it.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][int]$HeldTries, [Parameter(Mandatory = $true)][int]$HeldWaitMs)
    $path = Get-HordeFilesKeyPath -HordeHome $HordeHome
    $answer = { param($Read) return [pscustomobject]@{ ok = ($Read.state -ceq "ok"); key = $Read.key; reason = $Read.reason } }
    $read = Read-HordeFilesKey -Path $path -HeldTries $HeldTries -HeldWaitMs $HeldWaitMs
    if ($read.state -cne "absent") { return (& $answer $read) }
    if (Test-HordeFilesStoreHasRecord -Root (Get-HordeFilesStoreRoot -HordeHome $HordeHome)) {
        # ASKED AGAIN, ONCE. Another first share may have made the key and its record between the
        # look above and this one: a record is written only after the key, so if that is what
        # happened the key is there now.
        $again = Read-HordeFilesKey -Path $path -HeldTries $HeldTries -HeldWaitMs $HeldWaitMs
        if ($again.state -cne "absent") { return (& $answer $again) }
        return [pscustomobject]@{ ok = $false; key = $null; reason = ("the key that file ids are made with, '" + $path + "', is missing, and the store already holds shared files whose ids were made with it. A new key would give every file a new id, so none is made: put the key file back") }
    }
    $null = New-HordeFilesKey -Path $path
    # Made here or by another share at the same moment: either way, what is on disk is the key.
    $read = Read-HordeFilesKey -Path $path -HeldTries $HeldTries -HeldWaitMs $HeldWaitMs
    if ($read.state -ceq "absent") { return [pscustomobject]@{ ok = $false; key = $null; reason = ("the key that file ids are made with, '" + $path + "', was made and is gone again") } }
    return (& $answer $read)
}
