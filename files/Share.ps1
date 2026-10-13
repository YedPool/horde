# files/Share.ps1 - what may be shared, and what the list of shared files is.
#
# THE ONE JOB of this file is the two things a caller may ask of the files store: share this file, and
# list what was shared. It decides what is refused and what a record holds; how entries are kept is
# files/Store.ps1's, and every number is files/Settings.ps1's. `horde files` (cli/commands/files.ps1)
# is one caller; the channel that carries a share to the phone will be another, through the same two
# functions, so the two cannot come to differ.
#
# A RECORD, one per version of one shared file (the store's <file id>.<version>.json):
#   { schemaVersion: 1; fileId; version; title; type; size; sha256; time; session; editable }
#   fileId    32 hex: a digest of the sharing session and the file's full path. See below.
#   version   1, 2, ...: sharing the same path again from the same session is the next version.
#   type      the media type, from the table below; size in bytes; sha256 of the bytes, which names
#             them in the store; time in UTC, to the millisecond.
#   session   { known: true; id } - the session that shared it, as core/Identity.ps1 names the asking
#             session - or { known: false; reason } when the command was run outside any session. THE
#             RECORD SAYS SO AND NEVER GUESSES: no label and no other session is put in its place. A
#             label is display data that changes; whoever shows a record resolves one from the id.
#   editable  true or false, as the caller said. Only recorded here: nothing in this file acts on it.
# THE PATH IS NOT RECORDED: a record is meant to leave the machine, and a path names folders.
#
# THE FILE ID IS WORKED OUT, NOT GIVEN. Two shares of one path from one session, at one moment, in two
# processes, must come to ONE file with two versions. An id looked up in the store and then written
# would let both find nothing and both make a new file. A digest of (session, full path) needs no
# lookup: both reach the same id, both try for the same version name, and the store's move lets one
# have it. Shares made outside any session have no session to tell apart, so the same path shared
# again there is the next version of one file too.
#
# WHAT IS REFUSED, each with its reason, and nothing is written for any of them:
#   - a title that is empty, holds a control character, or is longer than the setting maxTitleChars;
#   - a path that names no file, or names a folder;
#   - A LINK. The file, or any folder on the way to it, that is a link of any kind (a symbolic link, a
#     junction, any reparse point): the bytes would come from somewhere the caller did not name. This
#     is the store's own test (decisions/Store.ps1's rule: the entry's own attributes, and an entry
#     that cannot be looked at is treated as a link). KNOWN COST: a sync folder's placeholders are
#     reparse points too, so a file there is refused until it is copied to an ordinary folder; telling
#     them apart needs the reparse tag, which is not read here. NOT CLOSED: a link swapped in between
#     the check and the open is followed, as in decisions/Store.ps1's sweep.
#   - a type that is not on the list: the extension is looked up in the table, and for a picture or a
#     PDF the first bytes must be that format's own, so a .png that is not a PNG is refused. SVG is
#     refused by name: it is a picture that can carry script.
#   - a file larger than the setting maxFileBytes, or one that cannot be opened and read.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced.

. (Join-Path $PSScriptRoot "Settings.ps1")
. (Join-Path $PSScriptRoot "Store.ps1")
# Which session is asking: the one definition, core's.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Identity.ps1")

function Get-HordeFilesTypes {
    # THE ALLOWED TYPES: extension (lower case) to { type; magic }. magic is a pattern over the first
    # twelve bytes written as upper-case hex, or "" for text, which has no signature to check.
    #   PNG  89 50 4E 47 0D 0A 1A 0A        JPEG  FF D8 FF        PDF  "%PDF-"
    #   GIF  "GIF87a" or "GIF89a"           WebP  "RIFF", four bytes of length, "WEBP"
    return [ordered]@{
        ".md" = @{ type = "text/markdown"; magic = "" }
        ".txt" = @{ type = "text/plain"; magic = "" }
        ".json" = @{ type = "application/json"; magic = "" }
        ".html" = @{ type = "text/html"; magic = "" }
        ".htm" = @{ type = "text/html"; magic = "" }
        ".png" = @{ type = "image/png"; magic = '\A89504E470D0A1A0A' }
        ".jpg" = @{ type = "image/jpeg"; magic = '\AFFD8FF' }
        ".jpeg" = @{ type = "image/jpeg"; magic = '\AFFD8FF' }
        ".gif" = @{ type = "image/gif"; magic = '\A47494638(37|39)61' }
        ".webp" = @{ type = "image/webp"; magic = '\A52494646[0-9A-F]{8}57454250' }
        ".pdf" = @{ type = "application/pdf"; magic = '\A255044462D' }
    }
}

function Get-HordeFilesType {
    # The type a file's NAME says it is: { ok; type; magic; reason }. No byte is read here.
    param([Parameter(Mandatory = $true)][string]$Path)
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $types = Get-HordeFilesTypes
    if ($extension -ceq ".svg") { return [pscustomobject]@{ ok = $false; type = ""; magic = ""; reason = "an SVG file is not shared: it is a picture that can carry script" } }
    if (-not $types.Contains($extension)) {
        $shown = $extension; if ($shown -eq "") { $shown = "no extension" }
        return [pscustomobject]@{ ok = $false; type = ""; magic = ""; reason = ("its type (" + $shown + ") is not one that is shared; the types are " + (@($types.Keys) -join ", ")) }
    }
    return [pscustomobject]@{ ok = $true; type = $types[$extension].type; magic = $types[$extension].magic; reason = "" }
}

function Test-HordeFilesMagic {
    # Do the first bytes fit the pattern of a type's signature? An empty pattern is text: always true.
    param([AllowEmptyString()][string]$Magic, [AllowEmptyCollection()][byte[]]$Bytes)
    if ($Magic -eq "") { return $true }
    $count = [System.Math]::Min(12, $Bytes.Length)
    $hex = [System.BitConverter]::ToString($Bytes, 0, $count).Replace("-", "")
    return [bool]($hex -cmatch $Magic)
}

function Find-HordeFilesLink {
    # The first link on the way to -Path, the file itself first and then each folder up to the root:
    # its path, or "" when there is none. The root itself is not asked: a drive is not a link.
    param([Parameter(Mandatory = $true)][string]$Path)
    $root = [System.IO.Path]::GetPathRoot($Path)
    $at = $Path
    while ($null -ne $at -and $at -ne "" -and $at -ne $root) {
        if (Test-HordeFilesStoreLink -Path $at) { return $at }
        $at = [System.IO.Path]::GetDirectoryName($at)
    }
    return ""
}

function Read-HordeFilesSource {
    # The bytes of the file to share: { ok; bytes; reason }. The length is asked before a byte is
    # read, so a file over the cap costs nothing; and no more than that length is read, so a file
    # that grows while it is read cannot pass the cap.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][int]$MaxBytes)
    $stream = $null
    try { $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read) }
    catch { return [pscustomobject]@{ ok = $false; bytes = $null; reason = ("it cannot be read: " + $_.Exception.GetBaseException().Message) } }
    try {
        if ($stream.Length -gt $MaxBytes) { return [pscustomobject]@{ ok = $false; bytes = $null; reason = ("it is " + $stream.Length + " bytes; the largest file that is shared is " + $MaxBytes + " bytes (the setting maxFileBytes)") } }
        $buffer = New-Object byte[] ([int]$stream.Length)
        $have = 0
        while ($have -lt $buffer.Length) {
            $got = $stream.Read($buffer, $have, $buffer.Length - $have)
            if ($got -le 0) { break }
            $have += $got
        }
        if ($have -ne $buffer.Length) { [Array]::Resize([ref]$buffer, $have) }
        return [pscustomobject]@{ ok = $true; bytes = $buffer; reason = "" }
    } catch { return [pscustomobject]@{ ok = $false; bytes = $null; reason = ("it could not be read to its end: " + $_.Exception.GetBaseException().Message) } }
    finally { $stream.Dispose() }
}

function Get-HordeFilesSession {
    # The sharing session as a record holds it. -Asking is an answer (core/Tristate.ps1) naming the
    # asking session; without it, core is asked. Anything but a known id is "no session", with the
    # reason: never a guess, and never the session of somebody else.
    param($Asking = $null)
    $answer = $Asking
    if ($null -eq $answer) { $answer = Get-HordeSelfSessionId }
    if ($answer.state -ceq "known") { return [ordered]@{ known = $true; id = ("" + $answer.value) } }
    return [ordered]@{ known = $false; reason = ("no session is known: " + $answer.reason) }
}

function Get-HordeFilesHex {
    # The sha256 of -Bytes, as 64 lower-case hex digits.
    param([AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace("-", "").ToLowerInvariant()) } finally { $sha.Dispose() }
}

function Get-HordeFilesId {
    # The id of the file a session shares from a path: the header says why it is a digest. The path is
    # compared as Windows compares it, without case. The first line makes this digest this file's own.
    param([Parameter(Mandatory = $true)]$Session, [Parameter(Mandatory = $true)][string]$FullPath)
    $who = "no-session"
    if ($Session.known) { $who = "session:" + $Session.id }
    $text = "horde-files-id.v1`n" + $who + "`n" + $FullPath.ToLowerInvariant()
    return (Get-HordeFilesHex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($text))).Substring(0, 32)
}

function Add-HordeFilesShare {
    # Share the file at -Path under -Title. Returns { outcome: shared | refused; reason; record; attempts }.
    #   shared   the bytes and the record are in the store; record is what was written.
    #   refused  nothing was written; reason says why, in words a person can act on.
    # Throws only for what is not the caller's doing: a refused settings file, a store folder that
    # cannot be written, or a record whose flush could not be confirmed.
    # -Root, -Asking and -Now are for a caller that must not use the real store, session or clock.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Title, [switch]$Editable,
        [string]$HordeHome = "", [string]$Root = "", $Asking = $null, [datetime]$Now = [datetime]::UtcNow)
    $settings = Get-HordeFilesSettings -HordeHome $HordeHome
    $store = $Root
    if ($store -eq "") { $store = Get-HordeFilesStoreRoot -HordeHome $HordeHome }
    $refuse = { param([string]$Why) return [pscustomobject]@{ outcome = "refused"; reason = $Why; record = $null; attempts = 0 } }

    $name = $Title.Trim()
    if ($name -eq "") { return (& $refuse "a shared file needs a title: give -Title") }
    if ($name -cmatch '\p{Cc}') { return (& $refuse "the title holds a control character; a title is one line") }
    if ($name.Length -gt $settings.maxTitleChars) { return (& $refuse ("the title is " + $name.Length + " characters; the longest is " + $settings.maxTitleChars + " (the setting maxTitleChars)")) }

    if ($Path.Trim() -eq "") { return (& $refuse "no file was named") }
    $full = ""
    # A relative path is the caller's, from where the caller stands; nothing is expanded or searched.
    try { $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } catch { return (& $refuse ("'" + $Path + "' is not a path of a file")) }
    if ([System.IO.Directory]::Exists($full)) { return (& $refuse ("'" + $full + "' is a folder; one file is shared at a time")) }
    if (-not [System.IO.File]::Exists($full)) { return (& $refuse ("there is no file '" + $full + "'")) }
    $link = Find-HordeFilesLink -Path $full
    if ($link -ne "") { return (& $refuse ("'" + $link + "' is a link, so what would be shared is not what was named; a link is never followed")) }
    $kind = Get-HordeFilesType -Path $full
    if (-not $kind.ok) { return (& $refuse $kind.reason) }
    $source = Read-HordeFilesSource -Path $full -MaxBytes $settings.maxFileBytes
    if (-not $source.ok) { return (& $refuse $source.reason) }
    if (-not (Test-HordeFilesMagic -Magic $kind.magic -Bytes $source.bytes)) { return (& $refuse ("its name says " + $kind.type + ", but its first bytes are not that format's")) }

    $session = Get-HordeFilesSession -Asking $Asking
    $fileId = Get-HordeFilesId -Session $session -FullPath $full
    $digest = Get-HordeFilesHex -Bytes $source.bytes
    # THE BYTES FIRST, then the record: a record never names bytes that are not there. "exists" is the
    # same bytes already kept - checked by their length, the one thing a digest's name cannot hide
    # cheaply: a file of that name and another length is damage, never something to build a record on.
    $bytesName = Get-HordeFilesBytesName -Sha256 $digest
    $kept = Add-HordeFilesStoreEntry -Root $store -Name $bytesName -Bytes $source.bytes -LeftoverMinAgeSeconds $settings.leftoverMinAgeSeconds
    if ($kept -ceq "unconfirmed") { throw "the file's bytes are in the store, but the system could not confirm they are on disk; nothing was recorded, so share it again" }
    if ($kept -ceq "exists" -and (New-Object System.IO.FileInfo((Join-Path $store $bytesName))).Length -ne $source.bytes.Length) { throw ("the store already holds " + $bytesName + " with another length: it is damaged, and nothing was recorded") }

    for ($attempt = 1; $attempt -le $settings.versionTries; $attempt++) {
        $version = (Get-HordeFilesStoreLastVersion -Root $store -FileId $fileId) + 1
        $record = [ordered]@{ schemaVersion = 1; fileId = $fileId; version = $version; title = $name; type = $kind.type; size = $source.bytes.Length; sha256 = $digest
            time = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture); session = $session; editable = [bool]$Editable }
        $text = ConvertTo-Json -InputObject $record -Compress -Depth 4
        $made = Add-HordeFilesStoreEntry -Root $store -Name (Get-HordeFilesRecordName -FileId $fileId -Version $version) -Bytes ([System.Text.Encoding]::UTF8.GetBytes($text)) -LeftoverMinAgeSeconds $settings.leftoverMinAgeSeconds
        if ($made -ceq "created") { return [pscustomobject]@{ outcome = "shared"; reason = ""; record = ([pscustomobject]$record); attempts = $attempt } }
        if ($made -ceq "unconfirmed") { throw ("version " + $version + " of file " + $fileId + " has its name, but the system could not confirm it is on disk; run horde files list to see it") }
        # "exists": another share of this file took that version first. The names are read again.
    }
    return (& $refuse ("other shares of the same file took the next version " + $settings.versionTries + " times in a row (the setting versionTries); share it again"))
}

function Get-HordeFilesRecordProblem {
    # Why a record that was read is not one this file wrote, or "" when it is. Checked on every read,
    # because the store folder is a folder: anyone may put a file there, and a list must not show a
    # share nobody made. -Entry is one record of Get-HordeFilesRecords, whose name gives the file id
    # and version the words inside must agree with.
    param([Parameter(Mandatory = $true)]$Entry)
    $data = $Entry.data
    $value = { param([string]$Name) $p = $data.PSObject.Properties[$Name]; if ($null -eq $p) { return $null }; return $p.Value }
    # A whole number is an Int32 from Windows PowerShell 5.1's parser and an Int64 from PowerShell 7's
    # (core/ModuleSettings.ps1 has the measurement), so either is one.
    $whole = { param([string]$Name) $v = & $value $Name; return ($v -is [int] -or $v -is [long]) }
    if (-not (& $whole "schemaVersion") -or (& $value "schemaVersion") -ne 1) { return "its schemaVersion is not 1" }
    if ((& $value "fileId") -isnot [string] -or (& $value "fileId") -cne $Entry.fileId) { return "its fileId is not the one in its name" }
    if (-not (& $whole "version") -or (& $value "version") -ne $Entry.version) { return "its version is not the one in its name" }
    $title = & $value "title"
    if ($title -isnot [string] -or $title.Trim() -eq "" -or $title -cmatch '\p{Cc}') { return "its title is not one line of text" }
    $type = & $value "type"
    if ($type -isnot [string] -or @((Get-HordeFilesTypes).Values | ForEach-Object { $_.type }) -cnotcontains $type) { return "its type is not one that is shared" }
    if (-not (& $whole "size") -or (& $value "size") -lt 0) { return "its size is not a count of bytes" }
    if ((& $value "sha256") -isnot [string] -or (& $value "sha256") -cnotmatch '\A[0-9a-f]{64}\z') { return "its sha256 is not 64 hex digits" }
    if ((& $value "time") -isnot [string] -or (& $value "time") -cnotmatch '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z\z') { return "its time is not a UTC time to the millisecond" }
    if ((& $value "editable") -isnot [bool]) { return "its editable is not true or false" }
    $session = & $value "session"
    if ($session -isnot [System.Management.Automation.PSCustomObject]) { return "it does not say which session shared it, or that none did" }
    $known = $session.PSObject.Properties["known"]
    if ($null -eq $known -or $known.Value -isnot [bool]) { return "its session does not say whether it is known" }
    $said = "reason"; if ($known.Value) { $said = "id" }
    $saidValue = $session.PSObject.Properties[$said]
    if ($null -eq $saidValue -or $saidValue.Value -isnot [string] -or $saidValue.Value -eq "") { return ("its session has no " + $said) }
    return ""
}

function Get-HordeFilesList {
    # What was shared: { state: ok | absent | unknown; reason; rows; unreadable; strays }.
    # rows is one per readable record, oldest first: { fileId; version; title; type; size; sha256;
    # time; session; sessionKnown; editable }, session being the sharing session's id or the words
    # "no session". unreadable is { file; reason } for a record that could not be read or is not one
    # this file wrote; strays is the store's. Reads only: no folder is made.
    param([string]$HordeHome = "", [string]$Root = "")
    $settings = Get-HordeFilesSettings -HordeHome $HordeHome
    $folder = $Root
    if ($folder -eq "") { $folder = Get-HordeFilesStoreRoot -HordeHome $HordeHome }
    $loaded = Get-HordeFilesRecords -Root $folder -HeldTries $settings.heldReadTries -HeldWaitMs $settings.heldReadWaitMs
    $rows = New-Object System.Collections.ArrayList
    $unreadable = New-Object System.Collections.ArrayList
    foreach ($entry in @($loaded.records)) {
        $why = $entry.reason
        if ($entry.kind -ceq "ok") { $why = Get-HordeFilesRecordProblem -Entry $entry }
        if ($why -ne "") { [void]$unreadable.Add([pscustomobject]@{ file = $entry.file; reason = $why }); continue }
        $d = $entry.data
        $who = "no session"; if ($d.session.known) { $who = $d.session.id }
        [void]$rows.Add([pscustomobject]@{ fileId = $d.fileId; version = $d.version; title = $d.title; type = $d.type; size = $d.size; sha256 = $d.sha256; time = $d.time
            session = $who; sessionKnown = [bool]$d.session.known; editable = $d.editable })
    }
    # The time is text of one fixed width in digits, so its order as text is its order in time.
    $ordered = @($rows.ToArray() | Sort-Object -Property time, fileId, version)
    return [pscustomobject]@{ state = $loaded.state; reason = $loaded.reason; rows = $ordered; unreadable = @($unreadable.ToArray()); strays = @($loaded.strays) }
}

function Format-HordeFilesList {
    # The list as lines for a console: one a version, the title last because it is the one free text.
    param([Parameter(Mandatory = $true)]$List)
    $lines = New-Object System.Collections.ArrayList
    if ($List.state -ceq "unknown") { [void]$lines.Add("the list of shared files could not be read: " + $List.reason); return @($lines.ToArray()) }
    if (@($List.rows).Count -eq 0) { [void]$lines.Add("no files have been shared") }
    foreach ($row in @($List.rows)) {
        [void]$lines.Add(("" + $row.fileId + "  v" + $row.version + "  " + $row.type + "  " + $row.size + " bytes  " + $row.session + "  " + $row.time + "  " + $row.title))
    }
    foreach ($bad in @($List.unreadable)) { [void]$lines.Add("unreadable record " + $bad.file + ": " + $bad.reason) }
    foreach ($stray in @($List.strays)) { [void]$lines.Add("not a record: " + $stray.file + ": " + $stray.reason) }
    return @($lines.ToArray())
}
