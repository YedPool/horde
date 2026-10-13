# relays/local - a relay on this machine's disk: mailboxes as folders under a root the caller names.
#
# WHY IT EXISTS (relay design 2026-10-09, PR plan item 3). The channels, the journal and the runner are
# built and tested against a relay before the hosted one exists, and two processes of one horde on one
# machine can meet through it for real. It is honest about the rest: it declares reach.remote no, so a
# channel between machines, which requires it, never picks this one.
#
# THE LAYOUT, under the root given as Options.root (an absolute path; the caller chooses it, so a test
# keeps it in its own temp folder):
#   <root>\<horde>\<reader>\                       one mailbox (relays/Port.ps1 has already refused any
#                                                  part that is not a safe folder name)
#   <seq, 16 digits>-<SHA-256 of the key>.item     one item: its key, a line feed, its text (ASCII)
#   floor-<seq, 16 digits>                         the highest seq ever acked (empty file)
#   top-<seq, 16 digits>                           the highest seq ever given, written only when a
#                                                  sender's trim deletes the item that held it (empty)
#   lock                                           held while a put or an ack changes the mailbox
# The seq and the key's hash are in the item's NAME so one rename publishes both at once: a put is
# written under a temporary name, flushed, and renamed into place, and a reader lists names and never
# sees half an item. 16 digits hold 2^53-1, the port's largest seq, and sort as numbers do.
#
# THE HEAD is the larger of the highest item seq and the highest floor, so no number is ever reused:
# an ack writes its floor BEFORE deleting the items it covers, and a kill between the two leaves items
# a later ack deletes. There is no head file to rewrite, because a file cannot be replaced in one step
# from Windows PowerShell 5.1 without a native call (core/FileAtomic.ps1), and names can.
#
# A SENDER TRIMS ITS OWN STREAM (relays/Port.ps1, the section of that name): a put that carries KeepFrom
# deletes, under the same lock and AFTER its own item is in place (or found already held), every item of
# the mailbox whose key names the put's stream with a seq before KeepFrom. An item's key is the first
# line of its file, so the trim reads that line of each item: a mailbox that is being trimmed holds a
# few hundred at the most, and one that is not yet is read once in full by the first trim. The floor
# is the ack's and is not touched - an ack at or behind it changes nothing, so a trim that moved it
# would make a later ack skip what it should delete. When the items deleted include the one with the
# highest seq (a put made again out of order can be), a top marker is written FIRST, as the floor is
# before an ack's deletes, so the head still never moves back and no number is reused.
#
# PUTS AND ACKS ARE SERIALISED by an exclusive open of the mailbox's lock file, retried every 20 ms for up
# to 10 s; READS TAKE NO LOCK, because an item, once named, never changes. A read that lists an item an
# ack deletes before it is opened skips it: it was acked, so the reader has it.
#
# WATCH polls the mailbox's names every 50 ms until something is past the cursor or the time is up. A
# change notification (FileSystemWatcher) was not used: it can drop events when its buffer fills, and
# a poll needs no event loop in a script. 50 ms is far inside the "within a second" that realtime
# promises, and a listing of a mailbox of a few hundred names is about a millisecond.
#
# THE WATCH IN SLICES (relays/Port.ps1, A WATCH IN SLICES) is that same poll, stopped when the slice is
# over as well as when the watch is, and taken up again where it stopped. Nothing is held open between
# two slices - the handle is the folder, the cursor and when the watch began - so a put, a read or an
# ack between them meets nothing of the watch's. The blocking watch is one slice as long as the watch:
# the two cannot drift apart, because there is one loop (Wait-HordeLocalRelayWatch).
#
# DURABILITY: an item is flushed to disk (FileStream.Flush($true)) before it is renamed into place. The
# rename itself is not forced to disk, so a power cut can lose the last puts; a crash of the process
# cannot. That is enough for a relay whose every item the journal also holds.
#
# Runs on Windows PowerShell 5.1 and PowerShell 7 alike: only System.IO, no native call.

$script:HordeLocalRelayFolder = $PSScriptRoot
$script:HordeLocalRelayItemPattern = '\A([0-9]{16})-[0-9a-f]{64}\.item\z'
$script:HordeLocalRelayFloorPattern = '\Afloor-([0-9]{16})\z'
$script:HordeLocalRelayTopPattern = '\Atop-([0-9]{16})\z'
# A key that names its stream, as relays/Port.ps1 reads one (its own copy: a relay is written to by
# more than the port's callers, and judges a key by itself).
$script:HordeLocalRelayStreamKeyPattern = '\A([0-9a-f]{32}/[a-z][a-z0-9-]{0,31}/)([1-9][0-9]{0,15})/[0-9a-f]{24}\z'
$script:HordeLocalRelayLockMs = 10000
$script:HordeLocalRelayPollMs = 50

function Get-HordeLocalRelayLimits {
    # This relay's own copy of its declared limits, for the checks it makes itself.
    $caps = [System.IO.File]::ReadAllText((Join-Path $script:HordeLocalRelayFolder "capabilities.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    return $caps.limits
}
$script:HordeLocalRelayMaxText = [int](Get-HordeLocalRelayLimits).maxTextChars

function Get-HordeLocalRelayDir {
    param($State, [string]$Mailbox)
    $parts = $Mailbox.Split([char]'/')
    return [System.IO.Path]::Combine($State.root, $parts[0], $parts[1])
}

function Get-HordeLocalRelayHash {
    param([string]$Key)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($Key)) } finally { $sha.Dispose() }
    return (($h | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Get-HordeLocalRelayEntries {
    # The mailbox's items as { seq; path; hash }, in seq order, and its floor. A missing folder is an
    # empty mailbox. Names that are not this relay's are ignored.
    param([string]$Dir)
    $items = New-Object System.Collections.ArrayList
    $floor = [long]0
    $top = [long]0
    if ([System.IO.Directory]::Exists($Dir)) {
        foreach ($p in [System.IO.Directory]::GetFiles($Dir)) {
            $n = [System.IO.Path]::GetFileName($p)
            $m = [regex]::Match($n, $script:HordeLocalRelayItemPattern)
            if ($m.Success) { [void]$items.Add([pscustomobject]@{ seq = [long]$m.Groups[1].Value; path = $p; hash = $n.Substring(17, 64) }); continue }
            $m = [regex]::Match($n, $script:HordeLocalRelayFloorPattern)
            if ($m.Success -and [long]$m.Groups[1].Value -gt $floor) { $floor = [long]$m.Groups[1].Value }
            $m = [regex]::Match($n, $script:HordeLocalRelayTopPattern)
            if ($m.Success -and [long]$m.Groups[1].Value -gt $top) { $top = [long]$m.Groups[1].Value }
        }
    }
    $sorted = @($items | Sort-Object seq)
    $head = [Math]::Max($floor, $top)
    if ($sorted.Count -gt 0 -and $sorted[$sorted.Count - 1].seq -gt $head) { $head = $sorted[$sorted.Count - 1].seq }
    return [pscustomobject]@{ items = $sorted; floor = $floor; head = $head }
}

function Enter-HordeLocalRelayLock {
    # The mailbox's lock, held open with no sharing until the caller disposes it. Throws after the wait.
    param([string]$Dir)
    $path = Join-Path $Dir "lock"
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        try { return [System.IO.File]::Open($path, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None) }
        catch [System.IO.IOException] {
            if ($clock.ElapsedMilliseconds -ge $script:HordeLocalRelayLockMs) { throw ("the mailbox at " + $Dir + " stayed locked for " + $script:HordeLocalRelayLockMs + " ms") }
            Start-Sleep -Milliseconds 20
        }
    }
}

function Read-HordeLocalRelayItems {
    # Up to -Max items after -Since, as { seq; key; text }. An item deleted since it was listed is skipped.
    param([string]$Dir, [long]$Since, [int]$Max)
    $out = New-Object System.Collections.ArrayList
    foreach ($e in @((Get-HordeLocalRelayEntries -Dir $Dir).items | Where-Object { $_.seq -gt $Since })) {
        if ($out.Count -ge $Max) { break }
        try { $raw = [System.IO.File]::ReadAllText($e.path, [System.Text.Encoding]::ASCII) }
        catch [System.IO.FileNotFoundException] { continue }
        $cut = $raw.IndexOf([char]10)
        # A file that is not key, line feed, text is handed over as it is, keyless: the port drops it and
        # says why. This relay does not judge what is in its own folders any more than any relay does.
        if ($cut -lt 0) { [void]$out.Add([pscustomobject]@{ seq = $e.seq; key = ""; text = $raw }); continue }
        [void]$out.Add([pscustomobject]@{ seq = $e.seq; key = $raw.Substring(0, $cut); text = $raw.Substring($cut + 1) })
    }
    return @($out.ToArray())
}

function Read-HordeLocalRelayItemKey {
    # The key of one item: the first line of its file, at most the 160 characters a key may be. "" for
    # a file that is gone or holds no such line.
    param([string]$Path)
    try {
        $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try { $buffer = New-Object byte[] 162; $got = $fs.Read($buffer, 0, $buffer.Length) } finally { $fs.Dispose() }
    } catch [System.IO.IOException] { return "" }
    $head = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $got)
    $cut = $head.IndexOf([char]10)
    if ($cut -lt 1) { return "" }
    return $head.Substring(0, $cut)
}

function Remove-HordeLocalRelayOlder {
    # A SENDER TRIMS ITS OWN STREAM (the header): delete every item of -Dir whose key names -Key's
    # stream with a seq before -KeepFrom. How many were deleted. The caller holds the mailbox's lock and
    # has checked that -Key names a stream and that -KeepFrom is not past its seq.
    param([string]$Dir, [string]$Key, [long]$KeepFrom)
    $stream = [regex]::Match($Key, $script:HordeLocalRelayStreamKeyPattern).Groups[1].Value
    $now = Get-HordeLocalRelayEntries -Dir $Dir
    $older = New-Object System.Collections.ArrayList
    foreach ($e in @($now.items)) {
        $m = [regex]::Match((Read-HordeLocalRelayItemKey -Path $e.path), $script:HordeLocalRelayStreamKeyPattern)
        if ($m.Success -and $m.Groups[1].Value -ceq $stream -and [long]$m.Groups[2].Value -lt $KeepFrom) { [void]$older.Add($e) }
    }
    if ($older.Count -eq 0) { return 0 }
    # THE TOP FIRST, then the items, when the newest item is among them: a kill in between leaves items,
    # never a reused number.
    if (@($older | Where-Object { $_.seq -eq $now.head }).Count -gt 0) {
        $tp = Join-Path $Dir ("top-" + $now.head.ToString("0000000000000000"))
        $fs = New-Object System.IO.FileStream($tp, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try { $fs.Flush($true) } finally { $fs.Dispose() }
        foreach ($old in [System.IO.Directory]::GetFiles($Dir, "top-*")) {
            $m = [regex]::Match([System.IO.Path]::GetFileName($old), $script:HordeLocalRelayTopPattern)
            if ($m.Success -and [long]$m.Groups[1].Value -lt $now.head) { [System.IO.File]::Delete($old) }
        }
    }
    foreach ($e in $older) { [System.IO.File]::Delete($e.path) }
    return $older.Count
}

function Add-HordeLocalRelayItem {
    # The put, and with -KeepFrom over 0 the sender's trim after it (the header): known { seq;
    # duplicate; trimmed }, trimmed 0 when nothing was asked.
    param($State, [string]$Mailbox, [string]$Key, [string]$Text, [long]$KeepFrom = 0)
    # ITS OWN CAP, whoever calls: the port checks first, but a relay is written to by more than this
    # port's callers.
    if ($Text.Length -eq 0 -or $Text.Length -gt $script:HordeLocalRelayMaxText -or $Text -cnotmatch '\A[\x20-\x7E]+\z') { return (New-HordeUnknown -Reason ("the local relay holds printable ASCII texts of 1 to " + $script:HordeLocalRelayMaxText + " characters")) }
    if ($Key -cnotmatch '\A[\x21-\x7E]+\z') { return (New-HordeUnknown -Reason "the local relay needs a printable key") }
    if ($KeepFrom -gt 0) {
        # ITS OWN CHECK OF THE TRIM, too: a stream is named, and the put is never among what it deletes.
        $named = [regex]::Match($Key, $script:HordeLocalRelayStreamKeyPattern)
        if (-not $named.Success -or $KeepFrom -gt [long]$named.Groups[2].Value) { return (New-HordeUnknown -Reason "the local relay trims only the stream its key names, and never from past the key's own seq") }
    }
    $dir = Get-HordeLocalRelayDir -State $State -Mailbox $Mailbox
    [void][System.IO.Directory]::CreateDirectory($dir)
    $hash = Get-HordeLocalRelayHash -Key $Key
    $lock = Enter-HordeLocalRelayLock -Dir $dir
    try {
        $now = Get-HordeLocalRelayEntries -Dir $dir
        $held = @($now.items | Where-Object { $_.hash -ceq $hash })
        $seq = $now.head + 1
        if ($held.Count -gt 0) { $seq = $held[0].seq }
        else {
            $tmp = Join-Path $dir ([guid]::NewGuid().ToString("N") + ".tmp")
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($Key + "`n" + $Text)
            $fs = New-Object System.IO.FileStream($tmp, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
            [System.IO.File]::Move($tmp, (Join-Path $dir ($seq.ToString("0000000000000000") + "-" + $hash + ".item")))
        }
        # THE TRIM AFTER THE ITEM IS IN PLACE, never before: a kill between the two leaves older items a
        # later trim deletes, and never a mailbox with the old gone and the new not there.
        $trimmed = 0
        if ($KeepFrom -gt 0) { $trimmed = Remove-HordeLocalRelayOlder -Dir $dir -Key $Key -KeepFrom $KeepFrom }
        return (New-HordeKnown -Value ([pscustomobject]@{ seq = $seq; duplicate = ($held.Count -gt 0); trimmed = [long]$trimmed }) -ObservedAt ([datetime]::UtcNow))
    } finally { $lock.Dispose() }
}

function New-HordeLocalRelayItems {
    param([object[]]$Items)
    return (New-HordeKnown -Value ([pscustomobject]@{ items = @($Items) }) -ObservedAt ([datetime]::UtcNow))
}

function New-HordeLocalRelayWatch {
    # A watch's handle: where it looks, from which cursor, and how long ago it began (the header, THE
    # WATCH IN SLICES). Nothing is opened: a handle that is never closed leaks nothing.
    param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs)
    return [pscustomobject]@{ dir = (Get-HordeLocalRelayDir -State $State -Mailbox $Mailbox); since = $Since; max = $Max; timeoutMs = $TimeoutMs; began = [System.Diagnostics.Stopwatch]::StartNew() }
}

function Wait-HordeLocalRelayWatch {
    # Poll -Watch's mailbox until something is past its cursor (ended, with the items), its own time is
    # up (ended, with none) or -WaitMs of this slice have passed (not ended): known { ended; items }.
    # The mailbox is read BEFORE either clock is asked, so a watch of 0 ms, and a slice of 0 ms, still
    # see what is already there.
    param($Watch, [int]$WaitMs)
    $slice = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $items = @(Read-HordeLocalRelayItems -Dir $Watch.dir -Since $Watch.since -Max $Watch.max)
        if ($items.Count -gt 0) { return (New-HordeKnown -Value ([pscustomobject]@{ ended = $true; items = $items }) -ObservedAt ([datetime]::UtcNow)) }
        $left = $Watch.timeoutMs - $Watch.began.ElapsedMilliseconds
        if ($left -le 0) { return (New-HordeKnown -Value ([pscustomobject]@{ ended = $true; items = @() }) -ObservedAt ([datetime]::UtcNow)) }
        $leftOfSlice = $WaitMs - $slice.ElapsedMilliseconds
        if ($leftOfSlice -le 0) { return (New-HordeKnown -Value ([pscustomobject]@{ ended = $false; items = @() }) -ObservedAt ([datetime]::UtcNow)) }
        Start-Sleep -Milliseconds ([Math]::Min($script:HordeLocalRelayPollMs, [Math]::Min($left, $leftOfSlice)))
    }
}

$null = Register-HordeRelay -Folder $script:HordeLocalRelayFolder `
    -Connect {
        param($Options)
        $r = $null
        if ($Options -is [System.Collections.IDictionary] -and $Options.Contains("root")) { $r = $Options["root"] }
        elseif ($null -ne $Options -and $null -ne $Options.PSObject.Properties["root"]) { $r = $Options.root }
        if ($r -isnot [string] -or $r -eq "" -or -not [System.IO.Path]::IsPathRooted($r)) { return (New-HordeUnknown -Reason "the local relay needs Options.root, an absolute folder path") }
        $full = [System.IO.Path]::GetFullPath($r)
        [void][System.IO.Directory]::CreateDirectory($full)
        return (New-HordeKnown -Value ([pscustomobject]@{ root = $full }))
    } `
    -Put {
        param($State, [string]$Mailbox, [string]$Key, [string]$Text)
        return (Add-HordeLocalRelayItem -State $State -Mailbox $Mailbox -Key $Key -Text $Text)
    } `
    -PutKeeping {
        param($State, [string]$Mailbox, [string]$Key, [string]$Text, [long]$KeepFrom)
        return (Add-HordeLocalRelayItem -State $State -Mailbox $Mailbox -Key $Key -Text $Text -KeepFrom $KeepFrom)
    } `
    -Get {
        param($State, [string]$Mailbox, [long]$Since, [int]$Max)
        # WRAPPED IN @() BEFORE IT IS PASSED: an empty result bound straight to [object[]] is $null under
        # Windows PowerShell 5.1 but a list holding one $null under PowerShell 7.6 (measured 2026-10-09:
        # the empty read came back as one malformed item there).
        $items = @(Read-HordeLocalRelayItems -Dir (Get-HordeLocalRelayDir -State $State -Mailbox $Mailbox) -Since $Since -Max $Max)
        return (New-HordeLocalRelayItems -Items $items)
    } `
    -Watch {
        param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs)
        # One slice as long as the watch: it ends only with items, or with the watch's own time.
        return (Wait-HordeLocalRelayWatch -Watch (New-HordeLocalRelayWatch -State $State -Mailbox $Mailbox -Since $Since -Max $Max -TimeoutMs $TimeoutMs) -WaitMs $TimeoutMs)
    } `
    -WatchOpen {
        param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs)
        return (New-HordeKnown -Value (New-HordeLocalRelayWatch -State $State -Mailbox $Mailbox -Since $Since -Max $Max -TimeoutMs $TimeoutMs) -ObservedAt ([datetime]::UtcNow))
    } `
    -WatchWait {
        param($State, $Handle, [int]$WaitMs)
        return (Wait-HordeLocalRelayWatch -Watch $Handle -WaitMs $WaitMs)
    } `
    -WatchClose { param($State, $Handle) } `
    -Ack {
        param($State, [string]$Mailbox, [long]$Through)
        $dir = Get-HordeLocalRelayDir -State $State -Mailbox $Mailbox
        if (-not [System.IO.Directory]::Exists($dir)) {
            if ($Through -eq 0) { return (New-HordeKnown -Value ([pscustomobject]@{ through = $Through })) }
            return (New-HordeUnknown -Reason ("the mailbox " + $Mailbox + " holds nothing, so nothing through " + $Through + " can be acked"))
        }
        $lock = Enter-HordeLocalRelayLock -Dir $dir
        try {
            $now = Get-HordeLocalRelayEntries -Dir $dir
            if ($Through -gt $now.head) { return (New-HordeUnknown -Reason ("the mailbox " + $Mailbox + " ends at " + $now.head + "; an ack through " + $Through + " is past it")) }
            if ($Through -gt $now.floor) {
                # THE FLOOR FIRST, then the items: a kill in between leaves items, never a reused number.
                $fp = Join-Path $dir ("floor-" + $Through.ToString("0000000000000000"))
                $fs = New-Object System.IO.FileStream($fp, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                try { $fs.Flush($true) } finally { $fs.Dispose() }
                foreach ($e in @($now.items | Where-Object { $_.seq -le $Through })) { [System.IO.File]::Delete($e.path) }
                foreach ($old in [System.IO.Directory]::GetFiles($dir, "floor-*")) {
                    $m = [regex]::Match([System.IO.Path]::GetFileName($old), $script:HordeLocalRelayFloorPattern)
                    if ($m.Success -and [long]$m.Groups[1].Value -lt $Through) { [System.IO.File]::Delete($old) }
                }
            }
            return (New-HordeKnown -Value ([pscustomobject]@{ through = $Through }) -ObservedAt ([datetime]::UtcNow))
        } finally { $lock.Dispose() }
    }
