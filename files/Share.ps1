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
#   fileId    32 hex: a keyed digest of the sharing session and the file's one real path. See below.
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
# would let both find nothing and both make a new file. A digest of (session, path) needs no
# lookup: both reach the same id, both try for the same version name, and the store's move lets one
# have it. Shares made outside any session have no session to tell apart, so the same path shared
# again there is the next version of one file too.
#   - THE DIGEST IS KEYED (HMAC-SHA-256) with a key only this machine has: files/Key.ps1 says why a
#     plain digest gave the path away, and what happens when the key is gone.
#   - THE PATH IS THE ONE THE OPEN HANDLE HAS, not the one that was written: files/Path.ps1. The
#     long-path prefix, an 8.3 short name and a subst drive all come to one path, so to one file.
#     THE SAME HANDLE IS THEN READ, so the name that decides the type and the id is the name of the
#     bytes that are kept.
#   AN ID IS PERMANENT once its first record exists: what goes into it cannot change afterwards,
#   and may not depend on the runtime that works it out (Get-HordeFilesId).
#
# WHAT IS REFUSED, each with its reason, and nothing is written for any of them:
#   - a share made under any runtime but Windows PowerShell 5.1 (files/Key.ps1 says why), before
#     anything is looked at or made;
#   - a title that is empty, holds a control character, a line or paragraph separator or a
#     character that turns the direction of text, or is longer than the setting maxTitleChars;
#   - A FILE IN A PLACE, OR OF A NAME, ON THE DENY LIST (files/Deny.ps1): the Horde home,
#     .horde-secrets and .ssh whatever the caller says; an agent harness's own folders, and a name
#     a file of secrets has, unless the caller gives -Force - which lifts the folder and never
#     such a name inside it;
#   - A TEXT FILE THAT HOLDS A CREDENTIAL BY ITS SHAPE (files/Deny.ps1): a private key whatever
#     the caller says, a token of a known shape unless the caller gives -Force;
#   - a path that names no file, or names a folder; a path in the device form, one holding a name
#     Windows keeps for a device, and one naming a stream inside a file (files/Path.ps1);
#   - A NETWORK PATH, in every spelling, and a file on a network drive - this machine's own drive
#     share too. Refused from the path's text and the drive's type BEFORE anything asks the disk or
#     the network about it: to look at such a path is to send the user's sign-in to the host it
#     names (core/PathText.ps1, Get-HordeNetworkPathRefusal);
#   - A LINK. The file, or any folder on the way to it, that is a link of any kind (a symbolic link, a
#     junction, any reparse point): the bytes would come from somewhere the caller did not name. This
#     is the store's own test (decisions/Store.ps1's rule: the entry's own attributes, and an entry
#     that cannot be looked at is treated as a link). It is asked AFTER the file is open, of the path
#     that was written and of the handle's own path. KNOWN COST: a sync folder's placeholders are
#     reparse points too, so a file there is refused until it is copied to an ordinary folder; telling
#     them apart needs the reparse tag, which is not read here.
#     THE SWAP, AND WHAT IS LEFT OF IT. Until 2026-10-13 the path was checked, then opened by name,
#     and the type and the id came from the written path: a link put in the file's place between
#     the two had another file's bytes recorded under this file's name, type and id. Now the type,
#     the first bytes, the text check and the id all come from the one open handle, so that cannot
#     happen. WHAT IS LEFT: a link put in the file's place before the open and taken away again
#     before the look that follows it is followed; the share is then OF the link's target - typed,
#     checked and identified as that target, never as the file that was named.
#   - a type that is not on the list: the extension is looked up in the table, and for a picture or a
#     PDF the first bytes must be that format's own, so a .png that is not a PNG is refused. SVG is
#     refused by name: it is a picture that can carry script.
#   - text that is not text (files/Text.ps1): a .md, .txt, .json or .html file must be strict UTF-8
#     with no NUL, and a .json file must be exactly one JSON text;
#   - a file larger than the setting maxFileBytes, or one that cannot be opened and read;
#   - a share the machine's key cannot be read for, and a file whose versions are used up.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced.

. (Join-Path $PSScriptRoot "Settings.ps1")
. (Join-Path $PSScriptRoot "Store.ps1")
. (Join-Path $PSScriptRoot "Key.ps1")
. (Join-Path $PSScriptRoot "Path.ps1")
. (Join-Path $PSScriptRoot "Deny.ps1")
. (Join-Path $PSScriptRoot "Text.ps1")
# Which session is asking: the one definition, core's.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Identity.ps1")
# The fold of A to Z that goes into a file id, and the network question asked of a path before
# anything looks at it: one definition each, core's, shared with whoever else needs them.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\PathText.ps1")

function Get-HordeFilesTypes {
    # THE ALLOWED TYPES: extension (lower case) to { type; magic }. magic is a pattern over the first
    # twelve bytes written as upper-case hex, or "" for text, which has no signature: text is held to
    # files/Text.ps1's check instead.
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
    # AN EXTENSION IS ONE OF THE TABLE'S ONLY WHEN IT IS THAT, CODE UNIT FOR CODE UNIT, once A to Z
    # are folded by the code's own hand (ConvertTo-HordeAsciiLower). Until 2026-10-13 it was lowered
    # by the runtime's case table and looked up in the table by its own comparer, and both let a
    # look-alike in. Measured that day on Windows PowerShell 5.1: a PNG named picture.pn<U+00AD>g was
    # shared as image/png, because the table's comparer (a culture-aware one) does not see a soft
    # hyphen; and under PowerShell 7.6 the case table makes U+212A, the Kelvin sign, a "k". So an
    # extension holding any character outside ASCII is none of the table's.
    param([Parameter(Mandatory = $true)][string]$Path)
    $extension = ConvertTo-HordeAsciiLower -Text ([System.IO.Path]::GetExtension($Path))
    $types = Get-HordeFilesTypes
    if ($extension -ceq ".svg") { return [pscustomobject]@{ ok = $false; type = ""; magic = ""; reason = "an SVG file is not shared: it is a picture that can carry script" } }
    $known = $null
    foreach ($listed in @($types.Keys)) { if ([string]::Equals($listed, $extension, [System.StringComparison]::Ordinal)) { $known = $types[$listed] } }
    if ($null -eq $known) {
        $shown = $extension; if ($shown -eq "") { $shown = "no extension" }
        return [pscustomobject]@{ ok = $false; type = ""; magic = ""; reason = ("its type (" + $shown + ") is not one that is shared; the types are " + (@($types.Keys) -join ", ")) }
    }
    return [pscustomobject]@{ ok = $true; type = $known.type; magic = $known.magic; reason = "" }
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
    # The bytes of the open file to share: { ok; bytes; reason }. -Stream is the one handle
    # files/Path.ps1 opened and asked its path of, so these are the bytes of the file that was typed
    # and identified. The length is asked before a byte is read, so a file over the cap costs
    # nothing; and no more than that length is read, so a file that grows while it is read cannot
    # pass the cap.
    param([Parameter(Mandatory = $true)]$Stream, [Parameter(Mandatory = $true)][int]$MaxBytes)
    try {
        if ($Stream.Length -gt $MaxBytes) { return [pscustomobject]@{ ok = $false; bytes = $null; reason = ("it is " + $Stream.Length + " bytes; the largest file that is shared is " + $MaxBytes + " bytes (the setting maxFileBytes)") } }
        $buffer = New-Object byte[] ([int]$Stream.Length)
        $have = 0
        while ($have -lt $buffer.Length) {
            $got = $Stream.Read($buffer, $have, $buffer.Length - $have)
            if ($got -le 0) { break }
            $have += $got
        }
        if ($have -ne $buffer.Length) { [Array]::Resize([ref]$buffer, $have) }
        return [pscustomobject]@{ ok = $true; bytes = $buffer; reason = "" }
    } catch { return [pscustomobject]@{ ok = $false; bytes = $null; reason = ("it could not be read to its end: " + $_.Exception.GetBaseException().Message) } }
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
    # The id of the file a session shares from a path: the header says why it is a digest, and why a
    # keyed one. -FullPath is the open handle's own path (files/Path.ps1). -Key is this machine's
    # (files/Key.ps1). The first line of the text makes this digest this file's own.
    # WHAT GOES IN NEVER DEPENDS ON THE RUNTIME: an id is permanent, so the same path must give the
    # same bytes under every runtime and after every update of one. Only A to Z are folded
    # (ConvertTo-HordeAsciiLower, core/PathText.ps1), so that a drive letter or a folder written in another case is no
    # other file; the handle's path already has every name as the disk holds it, in any alphabet.
    # KNOWN COST: a file renamed to another case of a letter outside A to Z is another file.
    param([Parameter(Mandatory = $true)]$Session, [Parameter(Mandatory = $true)][string]$FullPath, [Parameter(Mandatory = $true)][byte[]]$Key)
    $who = "no-session"
    if ($Session.known) { $who = "session:" + $Session.id }
    $text = "horde-files-id.v1`n" + $who + "`n" + (ConvertTo-HordeAsciiLower -Text $FullPath)
    $mac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (, $Key)
    try { return ((ConvertTo-HordeAsciiLower -Text ([System.BitConverter]::ToString($mac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))).Replace("-", ""))).Substring(0, 32)) } finally { $mac.Dispose() }
}

function Get-HordeFilesTitleProblem {
    # Why -Title is not one line of plain text, or "" when it is. Asked of a title before it is
    # recorded and of every record that is read. A control character, as before; and, since the
    # review of 2026-10-13, the two separators that break a line without being one (U+2028, U+2029)
    # and the characters that turn the direction of the text round them (U+061C, U+200E, U+200F,
    # U+202A to U+202E, U+2066 to U+2069): a title holding U+202E can show as other words than it
    # holds, and a title is what the founder reads to know what a file is.
    param([AllowEmptyString()][string]$Title)
    if ($Title -cmatch '\p{Cc}') { return "the title holds a control character; a title is one line" }
    if ($Title -cmatch '[\u2028\u2029]') { return "the title holds a line or paragraph separator (U+2028 or U+2029); a title is one line" }
    if ($Title -cmatch '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]') { return ("the title holds a character that turns the direction of the text round it (U+" + ([int][char]$Matches[0]).ToString("X4") + "), so it could show as other words than it holds; a title is plain text") }
    return ""
}

function Add-HordeFilesShare {
    # Share the file at -Path under -Title. Returns { outcome: shared | refused; reason; record; attempts }.
    #   shared   the bytes and the record are in the store; record is what was written.
    #   refused  nothing was written to the store; reason says why, in words a person can act on.
    # Throws only for what is not the caller's doing: a refused settings file, a store folder that
    # cannot be written, or a record whose flush could not be confirmed.
    # -Force is the caller saying the file holds no secret: it lifts what files/Deny.ps1 says it
    # lifts, and nothing else here.
    # -Root, -Asking and -Now are for a caller that must not use the real store, session or clock,
    # and -RepoRoot for one that must not read the real agent folders (files/Deny.ps1).
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Title, [switch]$Editable, [switch]$Force,
        [string]$HordeHome = "", [string]$Root = "", $Asking = $null, [datetime]$Now = [datetime]::UtcNow, [string]$RepoRoot = "")
    $refuse = { param([string]$Why) return [pscustomobject]@{ outcome = "refused"; reason = $Why; record = $null; attempts = 0 } }
    # BEFORE ANYTHING ELSE, so that a runtime that cannot finish a share never starts one.
    $runtime = Get-HordeFilesRuntimeRefusal
    if ($runtime -ne "") { return (& $refuse $runtime) }
    $settings = Get-HordeFilesSettings -HordeHome $HordeHome
    $store = $Root
    if ($store -eq "") { $store = Get-HordeFilesStoreRoot -HordeHome $HordeHome }

    $name = $Title.Trim()
    if ($name -eq "") { return (& $refuse "a shared file needs a title: give -Title") }
    $unclear = Get-HordeFilesTitleProblem -Title $name
    if ($unclear -ne "") { return (& $refuse $unclear) }
    if ($name.Length -gt $settings.maxTitleChars) { return (& $refuse ("the title is " + $name.Length + " characters; the longest is " + $settings.maxTitleChars + " (the setting maxTitleChars)")) }

    if ($Path.Trim() -eq "") { return (& $refuse "no file was named") }
    # FROM THE TEXT, BEFORE ANYTHING TOUCHES THE DISK OR THE NETWORK: looking at a network path sends
    # the user's sign-in to the host it names. A DRIVE LETTER THAT STANDS FOR A NETWORK DRIVE FIRST,
    # from the system's table of names, because the network question asks a letter's type and for
    # such a letter that alone looks the host up (core/PathText.ps1 has the measurement). Then the
    # network question; then a device, which opens, and a stream, which cannot be told later.
    $unfit = Get-HordeFilesPlaceRefusal -Path $Path
    if ($unfit -eq "") { $unfit = Get-HordeFilesPathRefusal -Path $Path }
    if ($unfit -ne "") { return (& $refuse $unfit) }
    $full = ""
    # A relative path is the caller's, from where the caller stands; nothing is expanded or searched.
    # THE NETWORK QUESTION IS ASKED BEFORE THIS LINE TOO, not only after it: handed a network drive's
    # letter it has not seen, this resolver looked the server up (measured 2026-10-13, 1289 ms).
    try { $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } catch { return (& $refuse ("'" + $Path + "' is not a path of a file")) }
    # AND ALL THREE AGAIN OF WHAT IT RESOLVED TO: a relative path, or a PowerShell drive over a share,
    # shows that it is a network path only here. Still nothing has asked the disk about it. THE DEVICE
    # AND STREAM QUESTION TOO: measured 2026-10-13, C:NUL.txt passed it as written - its one part
    # reads as "C" before the colon - and is the device name NUL.txt once it is resolved.
    $network = Get-HordeFilesPlaceRefusal -Path $full
    if ($network -eq "") { $network = Get-HordeFilesPathRefusal -Path $full }
    if ($network -ne "") { return (& $refuse $network) }
    if ([System.IO.Directory]::Exists($full)) { return (& $refuse ("'" + $full + "' is a folder; one file is shared at a time")) }
    if (-not [System.IO.File]::Exists($full)) { return (& $refuse ("there is no file '" + $full + "'")) }
    # OPENED ONCE. Everything after this is asked of that one handle, or of the path it gives.
    $opened = Open-HordeFilesSource -Path $full
    if (-not $opened.ok) { return (& $refuse $opened.reason) }
    $real = $opened.path
    $kind = $null
    $source = $null
    try {
        # THE DENY LIST, OF THE HANDLE'S OWN PATH AND BEFORE A BYTE IS READ (files/Deny.ps1). It is
        # asked before the link test on purpose: a link into a place that is never shared is refused
        # as that place, whatever the link test would have said of the link.
        $denied = Get-HordeFilesDenyRefusal -FinalPath $real -HordeHome $HordeHome -RepoRoot $RepoRoot -Force:$Force -Handle $opened.stream.SafeFileHandle
        if ($denied -ne "") { return (& $refuse $denied) }
        # The link test: of the path that was written, and then of the handle's own. The second is
        # asked behind the long-path prefix: measured 2026-10-13, a path of 578 characters without
        # it could not be looked at, and what cannot be looked at is treated as a link.
        $link = Find-HordeFilesLink -Path $full
        if ($link -eq "") { $link = Find-HordeFilesLink -Path ("\\?\" + $real) }
        if ($link -ne "") { return (& $refuse ("'" + $link + "' is a link, so what would be shared is not what was named; a link is never followed")) }
        $kind = Get-HordeFilesType -Path $real
        if (-not $kind.ok) { return (& $refuse $kind.reason) }
        $source = Read-HordeFilesSource -Stream $opened.stream -MaxBytes $settings.maxFileBytes
    } finally { $opened.stream.Dispose() }
    if (-not $source.ok) { return (& $refuse $source.reason) }
    if (-not (Test-HordeFilesMagic -Magic $kind.magic -Bytes $source.bytes)) { return (& $refuse ("its name says " + $kind.type + ", but its first bytes are not that format's")) }
    if ($kind.magic -eq "") {
        $notText = Get-HordeFilesTextProblem -Bytes $source.bytes -Type $kind.type
        if ($notText -ne "") { return (& $refuse $notText) }
        # WHAT THE TEXT HOLDS, now that it is known to be text and before anything is kept
        # (files/Deny.ps1): a private key whatever the caller says, a token of a known shape
        # unless the caller gives -Force. A picture and a PDF are not looked into.
        $holds = Get-HordeFilesContentRefusal -Bytes $source.bytes -Force:$Force
        if ($holds -ne "") { return (& $refuse $holds) }
    }

    # THE KEY, LAST OF ALL THAT CAN REFUSE THE FILE ITSELF: a first share that is refused makes no key.
    $keyed = Get-HordeFilesKey -HordeHome $HordeHome -HeldTries $settings.heldReadTries -HeldWaitMs $settings.heldReadWaitMs
    if (-not $keyed.ok) { return (& $refuse $keyed.reason) }
    $session = Get-HordeFilesSession -Asking $Asking
    $fileId = Get-HordeFilesId -Session $session -FullPath $real -Key $keyed.key
    $digest = Get-HordeFilesHex -Bytes $source.bytes
    # A FILE WHOSE VERSIONS ARE USED UP is refused before its bytes are kept. A version is six digits
    # of a record's name, and a stray record named for the last one made the next share throw.
    $lastVersion = (Get-HordeFilesStoreFormat).maxVersion
    $usedUp = "file " + $fileId + " already has version " + $lastVersion + ", the last a file can have; nothing more can be shared from this path"
    if ((Get-HordeFilesStoreLastVersion -Root $store -FileId $fileId) -ge $lastVersion) { return (& $refuse $usedUp) }
    # THE BYTES FIRST, then the record: a record never names bytes that are not there. "exists" is the
    # same bytes already kept - checked by their length, the one thing a digest's name cannot hide
    # cheaply: a file of that name and another length is damage, never something to build a record on.
    $bytesName = Get-HordeFilesBytesName -Sha256 $digest
    $kept = Add-HordeFilesStoreEntry -Root $store -Name $bytesName -Bytes $source.bytes -LeftoverMinAgeSeconds $settings.leftoverMinAgeSeconds
    if ($kept -ceq "unconfirmed") { throw "the file's bytes are in the store, but the system could not confirm they are on disk; nothing was recorded, so share it again" }
    if ($kept -ceq "exists" -and (New-Object System.IO.FileInfo((Join-Path $store $bytesName))).Length -ne $source.bytes.Length) { throw ("the store already holds " + $bytesName + " with another length: it is damaged, and nothing was recorded") }

    for ($attempt = 1; $attempt -le $settings.versionTries; $attempt++) {
        $version = (Get-HordeFilesStoreLastVersion -Root $store -FileId $fileId) + 1
        # Other shares took the last versions since the look above: still a refusal, never a throw.
        if ($version -gt $lastVersion) { return (& $refuse $usedUp) }
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
    if ($title -isnot [string] -or $title.Trim() -eq "" -or (Get-HordeFilesTitleProblem -Title $title) -ne "") { return "its title is not one line of text" }
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
