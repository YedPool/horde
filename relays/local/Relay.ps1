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
# PUTS AND ACKS ARE SERIALISED by an exclusive open of the mailbox's lock file, retried every 20 ms for up
# to 10 s; READS TAKE NO LOCK, because an item, once named, never changes. A read that lists an item an
# ack deletes before it is opened skips it: it was acked, so the reader has it.
#
# WATCH polls the mailbox's names every 50 ms until something is past the cursor or the time is up. A
# change notification (FileSystemWatcher) was not used: it can drop events when its buffer fills, and
# a poll needs no event loop in a script. 50 ms is far inside the "within a second" that realtime
# promises, and a listing of a mailbox of a few hundred names is about a millisecond.
#
# DURABILITY: an item is flushed to disk (FileStream.Flush($true)) before it is renamed into place. The
# rename itself is not forced to disk, so a power cut can lose the last puts; a crash of the process
# cannot. That is enough for a relay whose every item the journal also holds.
#
# Runs on Windows PowerShell 5.1 and PowerShell 7 alike: only System.IO, no native call.

$script:HordeLocalRelayFolder = $PSScriptRoot
$script:HordeLocalRelayItemPattern = '\A([0-9]{16})-[0-9a-f]{64}\.item\z'
$script:HordeLocalRelayFloorPattern = '\Afloor-([0-9]{16})\z'
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
    if ([System.IO.Directory]::Exists($Dir)) {
        foreach ($p in [System.IO.Directory]::GetFiles($Dir)) {
            $n = [System.IO.Path]::GetFileName($p)
            $m = [regex]::Match($n, $script:HordeLocalRelayItemPattern)
            if ($m.Success) { [void]$items.Add([pscustomobject]@{ seq = [long]$m.Groups[1].Value; path = $p; hash = $n.Substring(17, 64) }); continue }
            $m = [regex]::Match($n, $script:HordeLocalRelayFloorPattern)
            if ($m.Success -and [long]$m.Groups[1].Value -gt $floor) { $floor = [long]$m.Groups[1].Value }
        }
    }
    $sorted = @($items | Sort-Object seq)
    $head = $floor
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

function New-HordeLocalRelayItems {
    param([object[]]$Items)
    return (New-HordeKnown -Value ([pscustomobject]@{ items = @($Items) }) -ObservedAt ([datetime]::UtcNow))
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
        # ITS OWN CAP, whoever calls: the port checks first, but a relay is written to by more than this
        # port's callers.
        if ($Text.Length -eq 0 -or $Text.Length -gt $script:HordeLocalRelayMaxText -or $Text -cnotmatch '\A[\x20-\x7E]+\z') { return (New-HordeUnknown -Reason ("the local relay holds printable ASCII texts of 1 to " + $script:HordeLocalRelayMaxText + " characters")) }
        if ($Key -cnotmatch '\A[\x21-\x7E]+\z') { return (New-HordeUnknown -Reason "the local relay needs a printable key") }
        $dir = Get-HordeLocalRelayDir -State $State -Mailbox $Mailbox
        [void][System.IO.Directory]::CreateDirectory($dir)
        $hash = Get-HordeLocalRelayHash -Key $Key
        $lock = Enter-HordeLocalRelayLock -Dir $dir
        try {
            $now = Get-HordeLocalRelayEntries -Dir $dir
            $held = @($now.items | Where-Object { $_.hash -ceq $hash })
            if ($held.Count -gt 0) { return (New-HordeKnown -Value ([pscustomobject]@{ seq = $held[0].seq; duplicate = $true }) -ObservedAt ([datetime]::UtcNow)) }
            $seq = $now.head + 1
            $tmp = Join-Path $dir ([guid]::NewGuid().ToString("N") + ".tmp")
            $bytes = [System.Text.Encoding]::ASCII.GetBytes($Key + "`n" + $Text)
            $fs = New-Object System.IO.FileStream($tmp, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
            [System.IO.File]::Move($tmp, (Join-Path $dir ($seq.ToString("0000000000000000") + "-" + $hash + ".item")))
            return (New-HordeKnown -Value ([pscustomobject]@{ seq = $seq; duplicate = $false }) -ObservedAt ([datetime]::UtcNow))
        } finally { $lock.Dispose() }
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
        $dir = Get-HordeLocalRelayDir -State $State -Mailbox $Mailbox
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        while ($true) {
            $items = @(Read-HordeLocalRelayItems -Dir $dir -Since $Since -Max $Max)
            if ($items.Count -gt 0) { return (New-HordeLocalRelayItems -Items $items) }
            $left = $TimeoutMs - $clock.ElapsedMilliseconds
            if ($left -le 0) { return (New-HordeLocalRelayItems -Items @()) }
            Start-Sleep -Milliseconds ([Math]::Min($script:HordeLocalRelayPollMs, $left))
        }
    } `
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
