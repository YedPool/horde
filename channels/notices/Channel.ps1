# channels/notices - the founder's notices on his phone, end to end encrypted: what notices/Decide.ps1
# decided he should be told, out to the phone; the follow switches he sets on his phone, in (the founder
# asked for both, 2026-10-13 and 14: "sessions should have a tool to be able to notify if I ask it to",
# and "notify me of progress postings for lane/orc x"). In the app, at once; no buzz yet - that is Web
# Push, three later pull requests, which hook in at notices/Decide.ps1's Invoke-HordeNoticeHook.
#
# WHAT THIS CHANNEL DECIDES: NOTHING. notices/Decide.ps1 is the one place that decides what becomes a
# notice. This channel only (1) offers it the progress log's NEW entries, (2) sends what it decided, and
# (3) hands it the switches the phone set.
#
# (1) FOLLOWING THE PROGRESS LOG. The log the progress channel sends (channels/progress: its setting
#     progressFile, read with that channel's own readers - this channel is loaded with it, and the
#     progress channel's own files are not changed). It is read FROM WHERE THIS CHANNEL STOOD, and on the
#     first look ever FROM ITS END: OLD ENTRIES NEVER BECOME NOTICES. Each new entry goes to the decider
#     with the lanes it belongs to - the phone's own rule (relay/js/protocol.js, entryLanes): the lanes
#     it names, else the lanes the area-to-lane map gives its area (channels/cards: its setting
#     areaLanesFile, read with that channel's reader), else none, which is the Thrall's. The place in the
#     log is kept in this channel's state (below) as a byte offset with the progress channel's marks of
#     what was read; a log replaced or cut short is followed again from its new end, said once - never
#     read from its start, which would make old entries new.
# (2) OUT, sealed to every TRUSTED phone identity key of the horde and put in the horde's phone mailbox,
#     exactly as the progress log is (channels/Port.ps1):
#       - kind notices: {"v":1,"kind":"notices","horde","machine","follows":{"<lane>":true|false},
#         "notices":[<the notice lines of notices/Store.ps1, as kept>]}. EVERY ENVELOPE CARRIES THE
#         SWITCHES THE MACHINE HOLDS, so the newest one the phone opens is what the machine holds now:
#         the phone never shows a switch it only wished for.
#       - Sent when there are notices past the last one sent (by their number n, never by a byte), or
#         the switches changed; a phone key trusted since is sent the newest backfillNotices, to it alone.
#         With no notice kept and no switch ever set nothing is sent at all: the phone shows the same.
#       - Pages within the relay's budget; a notice is never cut (they are at most a few hundred bytes).
#       - RECORDED, THEN PUT UNTIL TAKEN, from a durable state (<HORDE_HOME>\relay\notices\state.json,
#         replaced whole in one rename), as the progress channel does: an envelope recorded and not yet
#         taken is put again, the same envelope, next turn.
#       - THE PHONE'S MAILBOX HOLDS THE LAST keepEnvelopes OF THIS STREAM: every put says so
#         (channels/Port.ps1, WHAT GOES TO THE PHONE IS TRIMMED BY ITS SENDER).
#       - An envelope sealed to a key no longer trusted is dropped before it is put, and every trusted
#         key is then sent the newest backfillNotices again: the phone shows each notice once, by its id.
# (3) IN, kind follow, from the founder's trusted PASSKEYS only (senders founder: the port refuses a peer
#     machine and anyone untrusted before the journal records it). The body, read strictly - no member
#     repeated, missing or added:
#       {"v":1,"setId":"<32 hex>","machine":"<32 hex key id>","lane":"<lane>","on":true|false}
#     A SWITCH IS FOR ONE MACHINE: machine must be THIS machine's key id (a card is one machine's), else
#     refused. Its time is the envelope's own ts, which the passkey signed: the decider keeps the later.
#     done when the decider took it (changed or not: the same envelope again is the same switch),
#     refused for good when it does not read, retry when the switches cannot be written now.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "notices\Decide.ps1")

$script:HordeNoticesChannelFolder = $PSScriptRoot
$script:HordeNoticesChannelSettings = New-HordeModuleSettings -Module "relay-notices" -Settings @(
    # 100, as the progress log: what the phone shows is what the mailbox holds.
    @{ name = "keepEnvelopes"; kind = "whole"; default = 100; min = 1; max = 1000; what = "How many of this machine's newest notices envelopes stay in the phone's mailbox." },
    @{ name = "backfillNotices"; kind = "whole"; default = 50; min = 0; max = 1000; what = "How many of the newest notices a phone key newly trusted is sent." },
    # 30 s, as the cards look: a phone key trusted since waits at most this for its backfill.
    @{ name = "idleLookMs"; kind = "whole"; default = 30000; min = 0; max = 600000; what = "How long the channel may go without a full look while nothing it sends has changed, in milliseconds." }
)
$script:HordeNoticesChannelFollowMembers = @("lane", "machine", "on", "setId", "v")

function Get-HordeNoticesChannelSettingsDeclaration { return $script:HordeNoticesChannelSettings }

function Get-HordeNoticesChannelHome {
    param($Context)
    if ("$($Context.hordeHome)" -ne "") { return $Context.hordeHome }
    return (Get-HordeHome)
}

function Get-HordeNoticesChannelStatePath {
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return [System.IO.Path]::Combine($HordeHome, "relay", "notices", "state.json")
}

# --- the durable state ---

function New-HordeNoticesChannelState {
    return [pscustomobject]@{ started = $false; path = ""; offset = [long]0; line = [long]0; skip = $false; head = ""; tail = ""; sentN = [long]0; follows = ""; phones = @(); pending = @() }
}

function Read-HordeNoticesChannelState {
    # known (the empty state when there is no file), or unknown when it does not hold together - the
    # channel then stops, in words, and is never started over by itself (it would send old notices again
    # or, worse, read the log from a place it never stood).
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $path = Get-HordeNoticesChannelStatePath -HordeHome $HordeHome
    $r = Read-HordeNoticeJson -Path $path -What "notices channel state"
    if ($r.state -ceq "absent") { return (New-HordeKnown -Value (New-HordeNoticesChannelState)) }
    if ($r.state -cne "known") { return $r }
    $s = $r.value
    $why = "the notices channel state " + $path + " does not hold together"
    if ((@($s.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -cne "follows,head,line,offset,path,pending,phones,sentN,skip,started,tail,v" -or $s.v -ne 1) { return (New-HordeUnknown -Reason ($why + ": its members are not this code's")) }
    $whole = { param($v) return (($v -is [int] -or $v -is [long]) -and $v -ge 0) }
    $hash = { param($v) return ($v -is [string] -and $v -cmatch '\A([0-9a-f]{64})?\z') }
    if ($s.started -isnot [bool] -or $s.skip -isnot [bool] -or -not (& $whole $s.offset) -or -not (& $whole $s.line) -or -not (& $whole $s.sentN) -or -not (& $hash $s.head) -or -not (& $hash $s.tail) -or -not (& $hash $s.follows) -or $s.path -isnot [string]) { return (New-HordeUnknown -Reason ($why + ": a member is not of its kind")) }
    foreach ($k in @($s.phones)) { if ($k -isnot [string] -or $k -cnotmatch '\A[0-9a-f]{32}\z') { return (New-HordeUnknown -Reason ($why + ": a phone key is not a key id")) } }
    foreach ($k in @($s.pending)) { if ($k -isnot [string] -or $k.Length -gt 160) { return (New-HordeUnknown -Reason ($why + ": a pending envelope is not a replay key")) } }
    return (New-HordeKnown -Value ([pscustomobject]@{ started = $s.started; path = $s.path; offset = [long]$s.offset; line = [long]$s.line; skip = $s.skip; head = $s.head; tail = $s.tail; sentN = [long]$s.sentN; follows = $s.follows; phones = @($s.phones); pending = @($s.pending) }))
}

function ConvertTo-HordeNoticesChannelStateText {
    param([Parameter(Mandatory = $true)]$State)
    $tf = { param($b) if ($b) { "true" } else { "false" } }
    $list = { param($items) (@($items) | ForEach-Object { ConvertTo-HordeNoticeJsonString "$_" }) -join "," }
    return ('{"v":1,"started":' + (& $tf $State.started) + ',"path":' + (ConvertTo-HordeNoticeJsonString "$($State.path)") + ',"offset":' + [long]$State.offset + ',"line":' + [long]$State.line + ',"skip":' + (& $tf $State.skip) +
        ',"head":"' + $State.head + '","tail":"' + $State.tail + '","sentN":' + [long]$State.sentN + ',"follows":"' + $State.follows + '","phones":[' + (& $list $State.phones) + '],"pending":[' + (& $list $State.pending) + ']}')
}

function Write-HordeNoticesChannelState {
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)]$State)
    Write-HordeNoticeFile -Path (Get-HordeNoticesChannelStatePath -HordeHome $HordeHome) -Text (ConvertTo-HordeNoticesChannelStateText -State $State)
}

# --- (1) following the progress log ---

function Get-HordeNoticesChannelEntryLanes {
    # The lanes one entry belongs to: relay/js/protocol.js's entryLanes, the same rule on the machine -
    # its own lanes (comma separated) win; else its area's, the area compared with case and outer spaces
    # set aside; else none.
    param([Parameter(Mandatory = $true)]$Entry, [AllowEmptyCollection()][object[]]$Areas)
    $own = @(("" + $Entry.lane).Split([char]',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    if ($own.Count -gt 0) { return $own }
    $area = ("" + $Entry.area).Trim().ToLowerInvariant()
    if ($area -eq "") { return @() }
    foreach ($a in @($Areas)) { if ($a.area.Trim().ToLowerInvariant() -ceq $area) { return @($a.lanes) } }
    return @()
}

function Get-HordeNoticesChannelAreas {
    # The area-to-lane map the cards channel sends the phone (its setting areaLanesFile), so the machine
    # and the phone put an entry in the same lanes. No map, or none readable: no area maps to a lane.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    if ($null -eq (Get-Command -Name Read-HordeCardsChannelAreas -ErrorAction SilentlyContinue)) { return @() }
    $s = Get-HordeModuleSettings -Declaration (Get-HordeCardsChannelSettingsDeclaration) -HordeHome $HordeHome
    if ($s.state -ceq "refused") { return @() }
    $a = Read-HordeCardsChannelAreas -Path (Get-HordeCardsChannelPaths -HordeHome $HordeHome -Settings $s.values).areas
    return @($a.areas)
}

function Invoke-HordeNoticesChannelFollow {
    # (1) in the header, one look: { lines; failed; changed } - changed when the state's place moved.
    # The state -D is changed in memory; the caller writes it.
    param($Context, $D, $Mine, [Parameter(Mandatory = $true)][string]$HordeHome)
    $none = [pscustomobject]@{ lines = @(); failed = $false; changed = $false }
    if ($null -eq (Get-Command -Name Read-HordeProgressChannelLines -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ lines = @("progress is not followed: the progress channel is not loaded here"); failed = $false; changed = $false } }
    $ps = Get-HordeProgressChannelSettings -Context $Context
    if ($ps.state -cne "known") { return [pscustomobject]@{ lines = @("progress is not followed: " + $ps.reason); failed = $false; changed = $false } }
    $path = Get-HordeProgressChannelFilePath -HordeHome $HordeHome -Setting $ps.value.progressFile
    $info = New-Object System.IO.FileInfo -ArgumentList $path
    if (-not $info.Exists) { return $none }
    # Nothing written since the last look: the log is not opened.
    if ($D.started -and $D.path -ceq $path -and [long]$info.Length -eq $Mine.seenLength -and $info.LastWriteTimeUtc -eq $Mine.seenWrite) { return $none }
    $readBytes = [long]$ps.value.readBytes
    $lines = New-Object System.Collections.ArrayList
    $fresh = $false
    if ($D.started) {
        $why = ""
        if ($D.path -cne $path) { $why = "the setting progressFile now names another log" }
        else {
            $marks = Get-HordeProgressChannelMarks -Path $path -Offset $D.offset
            if (-not $marks.ok) { return $none }
            if ($marks.length -lt $D.offset) { $why = "it was cut short" }
            elseif ($marks.head -cne $D.head -or $marks.tail -cne $D.tail) { $why = "it was replaced or rewritten" }
        }
        if ($why -cne "") { [void]$lines.Add("the progress log " + $path + " is followed again from its present end, because " + $why + "; nothing before that end becomes a notice"); $fresh = $true }
    } else { $fresh = $true }
    $offset = $(if ($fresh) { [long]0 } else { $D.offset }); $line = $(if ($fresh) { [long]0 } else { $D.line }); $skip = $(if ($fresh) { $false } else { $D.skip })
    $entries = New-Object System.Collections.ArrayList
    # At most 64 reads a look; the rest is read on the next.
    for ($i = 0; $i -lt 64; $i++) {
        $r = Read-HordeProgressChannelLines -Path $path -Offset $offset -Line $line -Skip $skip -MaxBytes $readBytes
        if (-not $r.ok) { return [pscustomobject]@{ lines = @("progress is not followed now: the progress log " + $path + " could not be read: " + $r.reason); failed = $false; changed = $false } }
        # FROM ITS END ON A FRESH START: what is read now is only passed over.
        if (-not $fresh) { foreach ($e in @($r.entries)) { [void]$entries.Add($e.entry) } }
        $offset = $r.offset; $line = $r.line; $skip = $r.skip
        if (-not $r.more) { break }
    }
    if ($entries.Count -gt 0) {
        $areas = @(Get-HordeNoticesChannelAreas -HordeHome $HordeHome)
        $offered = @($entries.ToArray() | ForEach-Object { [pscustomobject]@{ id = $_.id; title = $_.title; kind = $_.kind; lanes = @(Get-HordeNoticesChannelEntryLanes -Entry $_ -Areas $areas) } })
        $sub = Submit-HordeProgressNotices -Entries $offered -HordeHome $HordeHome
        # NOT DECIDED, NOT PASSED: the place stays, and the same entries are offered again next turn.
        if ($sub.state -cne "known") { return [pscustomobject]@{ lines = @("new progress entries were not looked at for notices: " + $sub.reason); failed = $true; changed = $false } }
        if (@($sub.value).Count -gt 0) { [void]$lines.Add("" + @($sub.value).Count + " progress entr" + $(if (@($sub.value).Count -eq 1) { "y" } else { "ies" }) + " of a followed lane became notices") }
    }
    $marksNow = Get-HordeProgressChannelMarks -Path $path -Offset $offset
    if (-not $marksNow.ok -or $marksNow.length -lt $offset) { return [pscustomobject]@{ lines = @($lines.ToArray()); failed = $false; changed = $false } }
    $D.started = $true; $D.path = $path; $D.offset = $offset; $D.line = $line; $D.skip = $skip; $D.head = $marksNow.head; $D.tail = $marksNow.tail
    $Mine.seenLength = [long]$info.Length; $Mine.seenWrite = $info.LastWriteTimeUtc
    return [pscustomobject]@{ lines = @($lines.ToArray()); failed = $false; changed = $true }
}

# --- (2) out ---

function Get-HordeNoticesChannelFollowsText {
    # The switches as an envelope carries them: {"<lane>":true|false}, lanes in name order.
    param([Parameter(Mandatory = $true)][hashtable]$Follows)
    return ('{' + ((@($Follows.Keys | Sort-Object { $_ } -CaseSensitive) | ForEach-Object { (ConvertTo-HordeNoticeJsonString $_) + ':' + $(if ($Follows[$_].on) { "true" } else { "false" }) }) -join ",") + '}')
}

function New-HordeNoticesChannelPages {
    # The bodies for -Notices (lines as kept) and -FollowsText: as many as the budget needs, at least one.
    param($Context, [AllowEmptyCollection()][object[]]$Notices, [Parameter(Mandatory = $true)][string]$FollowsText, [long]$Budget)
    $front = '{"v":1,"kind":"notices","horde":"' + $Context.horde + '","machine":"' + $Context.signKeyId + '","follows":' + $FollowsText + ',"notices":['
    $back = ']}'
    $room = $Budget - $front.Length - $back.Length
    $pages = New-Object System.Collections.ArrayList
    $current = New-Object System.Collections.ArrayList
    $used = 0
    foreach ($n in @($Notices)) {
        $t = "" + $n.line
        if ($t.Length -gt $room) { continue }
        $add = $t.Length + $(if ($current.Count -gt 0) { 1 } else { 0 })
        if ($current.Count -gt 0 -and $used + $add -gt $room) { [void]$pages.Add($front + ($current -join ",") + $back); $current = New-Object System.Collections.ArrayList; $used = 0; $add = $t.Length }
        [void]$current.Add($t); $used += $add
    }
    if ($current.Count -gt 0 -or $pages.Count -eq 0) { [void]$pages.Add($front + ($current -join ",") + $back) }
    return @($pages.ToArray())
}

function Send-HordeNoticesChannelPending {
    # Put every envelope recorded and not yet taken, in order, dropping one sealed to a key no longer
    # trusted (the header). "" when all were taken, else why not. Writes the state after each.
    param($Context, $D, [Parameter(Mandatory = $true)][string]$HordeHome, [long]$Keep, [string[]]$Trusted)
    $mailbox = New-HordeRelayMailbox -Horde $Context.horde -Reader "phone"
    while (@($D.pending).Count -gt 0) {
        $key = @($D.pending)[0]
        $rec = Test-HordeRelayJournalSent -Key $key -HordeHome $HordeHome
        if ($rec.state -cne "known") { return ("the journal cannot give back " + $key + ": " + $rec.reason) }
        if ($rec.value.sent) {
            $to = @((Read-HordeRelayEnvelope -Text $rec.value.text).value.header.to)
            if (@($to | Where-Object { @($Trusted) -cnotcontains $_ }).Count -gt 0) {
                # Sealed to a key revoked since: dropped, and every trusted key is sent the newest again.
                $D.phones = @()
            } else {
                $put = Send-HordeRelayChannelSaved -Context $Context -Saved ([pscustomobject]@{ key = $key; text = $rec.value.text }) -Mailbox $mailbox -KeepFrom (Get-HordeRelayChannelKeepFrom -Key $key -Keep $Keep)
                if ($put.state -cne "known") { return $put.reason }
            }
        }
        $D.pending = @(@($D.pending) | Select-Object -Skip 1)
        try { Write-HordeNoticesChannelState -HordeHome $HordeHome -State $D } catch { return ("the notices channel state could not be written: " + $_.Exception.Message) }
    }
    return ""
}

function Invoke-HordeNoticesChannelTick {
    # (1) then (2), in the header: { lines; failed }.
    param($Context)
    if (-not $Context.state.ContainsKey("notices")) { $Context.state["notices"] = @{ loaded = $false; durable = $null; said = @{}; seenLength = [long]-1; seenWrite = [datetime]::MinValue; looked = $false; logStamp = ""; followStamp = "" } }
    $mine = $Context.state["notices"]
    $once = {
        param([string]$Key, [string]$Line, [bool]$Failed)
        if ($mine.said.ContainsKey($Key) -and $mine.said[$Key] -ceq $Line) { return [pscustomobject]@{ lines = @(); failed = $Failed } }
        $mine.said[$Key] = $Line
        return [pscustomobject]@{ lines = @($Line); failed = $Failed }
    }
    $homeDir = Get-HordeNoticesChannelHome $Context
    if (-not $mine.loaded) {
        $st = Read-HordeNoticesChannelState -HordeHome $homeDir
        if ($st.state -cne "known") { return (& $once "state" ("notices are stopped: " + $st.reason + "; mend or move the file, and the channel starts again") $true) }
        $mine.durable = $st.value; $mine.loaded = $true
    }
    $d = $mine.durable
    # IDLE: NOTHING CHANGED, NOTHING READ. The runner turns about once a second, and a full look reads
    # three settings files, the trust store, the notices and the switches: with it every turn of
    # test/test-relay-channels.ps1's run took over its 300 ms minimum turn (measured 2026-10-14, the check
    # "padded to the minimum turn" failed with no turn padded). So while the notices, the switches and
    # the followed log are as the last full look found them, and that look is younger than idleLookMs,
    # the Tick returns at once. What this delays is only a phone key trusted since (its backfill comes at
    # the next full look); nothing can go to a key revoked since, because a full look - the trust store
    # read again - comes first whenever there is something to send.
    if ($mine.ContainsKey("fullStamp") -and @($d.pending).Count -eq 0 -and ([datetime]::UtcNow - $mine.lastFull).TotalMilliseconds -lt $mine.idleLookMs) {
        if ((Get-HordeNoticesChannelFullStamp -Store $mine["store"] -D $d) -ceq $mine.fullStamp) { return [pscustomobject]@{ lines = @(); failed = $false } }
    }
    $set = Get-HordeModuleSettings -Declaration $script:HordeNoticesChannelSettings -HordeHome $homeDir
    if ($set.state -ceq "refused") { return (& $once "settings" ("notices are stopped: " + (@($set.findings) -join " ")) $true) }
    $store = Get-HordeNoticeStore -HordeHome $homeDir
    if (-not $store.ok) { return (& $once "store" ("notices are stopped: " + $store.reason) $true) }
    $mine.said.Remove("state"); $mine.said.Remove("settings"); $mine.said.Remove("store")
    $mine.looked = $true
    $mine["store"] = $store.store
    $mine["idleLookMs"] = [long]$set.values.idleLookMs
    # What this look starts from: a change after this moment is seen by the next Tick.
    $mine["fullStamp"] = Get-HordeNoticesChannelFullStamp -Store $store.store -D $d
    $mine["lastFull"] = [datetime]::UtcNow
    $out = New-Object System.Collections.ArrayList
    $was = ConvertTo-HordeNoticesChannelStateText -State $d

    # (1) THE PROGRESS LOG, every turn: its place moves whether or not any lane is followed, so a switch
    # turned on later never makes an old entry new.
    $f = Invoke-HordeNoticesChannelFollow -Context $Context -D $d -Mine $mine -HordeHome $homeDir
    foreach ($l in @($f.lines)) { $r = & $once ("follow:" + $l) $l $false; foreach ($x in @($r.lines)) { [void]$out.Add($x) } }
    $failed = [bool]$f.failed

    # (2) OUT.
    $phones = Find-HordeRelayPhoneKeys -HordeHome $homeDir
    if ($phones.state -cne "known") { [void]$out.Add("no notices sent: " + $phones.reason); return [pscustomobject]@{ lines = @($out.ToArray()); failed = $true } }
    $keys = @($phones.value)
    $limit = (Get-HordeRelayEnvelopeLimits).recipients
    if ($keys.Count -gt $limit) { $keys = @($keys | Select-Object -First $limit) }
    $trusted = @($keys | ForEach-Object { $_.agreeKeyId })
    $keep = [long]$set.values.keepEnvelopes
    if (@($d.pending).Count -gt 0) {
        $why = Send-HordeNoticesChannelPending -Context $Context -D $d -HordeHome $homeDir -Keep $keep -Trusted $trusted
        if ($why -cne "") { [void]$out.Add("notices not delivered yet (" + @($d.pending).Count + " envelope(s) recorded and waiting): " + $why); return [pscustomobject]@{ lines = @($out.ToArray()); failed = $true } }
    }
    if ($keys.Count -eq 0) {
        if ((ConvertTo-HordeNoticesChannelStateText -State $d) -cne $was) { try { Write-HordeNoticesChannelState -HordeHome $homeDir -State $d } catch { } }
        $r = & $once "phones" "no notices sent: no phone identity key of this horde is trusted yet" $false
        return [pscustomobject]@{ lines = @(@($out.ToArray()) + @($r.lines)); failed = $failed }
    }
    $mine.said.Remove("phones")
    # What the Glance compares with: the files as this look reads them, so a change after it is seen.
    $mine.logStamp = Get-HordeNoticesChannelStamp -Path (Get-HordeNoticeLogPath -Store $store.store)
    $mine.followStamp = Get-HordeNoticesChannelStamp -Path ([System.IO.Path]::Combine($store.store, "follows.json"))
    $log = Read-HordeNoticeLog -Store $store.store
    $follows = Read-HordeNoticeFollows -Store $store.store
    if ($log.state -cne "known" -or $follows.state -cne "known") {
        $r = & $once "read" ("no notices sent: " + $(if ($log.state -cne "known") { $log.reason } else { $follows.reason })) $true
        return [pscustomobject]@{ lines = @(@($out.ToArray()) + @($r.lines)); failed = $true }
    }
    $mine.said.Remove("read")
    $followsText = Get-HordeNoticesChannelFollowsText -Follows $follows.value
    $followsHash = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes ([System.Text.Encoding]::ASCII.GetBytes($followsText)))
    $all = @($log.value)
    $newOnes = @($all | Where-Object { $_.n -gt $d.sentN })
    $freshKeys = @($keys | Where-Object { @($d.phones) -cnotcontains $_.agreeKeyId })
    $oldKeys = @($keys | Where-Object { @($d.phones) -ccontains $_.agreeKeyId })
    $batches = New-Object System.Collections.ArrayList
    $backfill = [int]$set.values.backfillNotices
    # NOTHING TO SAY, NOTHING SENT: with no notice kept and no switch ever set, the phone shows the same
    # (none, every switch off) without an envelope, and the mailbox other channels share holds one less.
    if ($all.Count -eq 0 -and $follows.value.Count -eq 0) { $freshKeys = @(); $oldKeys = @(); $d.phones = $trusted; $d.follows = $followsHash }
    if ($freshKeys.Count -gt 0) { [void]$batches.Add([pscustomobject]@{ to = $freshKeys; notices = @($all | Select-Object -Last $backfill) }) }
    if ($oldKeys.Count -gt 0 -and ($newOnes.Count -gt 0 -or $followsHash -cne $d.follows)) { [void]$batches.Add([pscustomobject]@{ to = $oldKeys; notices = $newOnes }) }
    if ($batches.Count -eq 0) {
        if ((ConvertTo-HordeNoticesChannelStateText -State $d) -cne $was) { try { Write-HordeNoticesChannelState -HordeHome $homeDir -State $d } catch { [void]$out.Add("the notices channel state could not be written: " + $_.Exception.Message); $failed = $true } }
        return [pscustomobject]@{ lines = @($out.ToArray()); failed = $failed }
    }
    $saved = New-Object System.Collections.ArrayList
    $count = 0
    foreach ($b in $batches) {
        $budget = Get-HordeRelayChannelBodyBudget -Context $Context -Recipients @($b.to).Count
        foreach ($body in @(New-HordeNoticesChannelPages -Context $Context -Notices @($b.notices) -FollowsText $followsText -Budget $budget)) {
            $s = Save-HordeRelayChannelEnvelope -Context $Context -Channel "notices" -Kind "notices" -Body ([System.Text.Encoding]::ASCII.GetBytes($body)) -Recipients @(@($b.to) | ForEach-Object { , ([byte[]]$_.public) })
            if ($s.state -cne "known") {
                # What was recorded is put; the rest is made again next turn from the same state.
                $d.pending = @(@($d.pending) + @($saved.ToArray()))
                try { Write-HordeNoticesChannelState -HordeHome $homeDir -State $d } catch { }
                [void]$out.Add("no notices sent: " + $s.reason)
                return [pscustomobject]@{ lines = @($out.ToArray()); failed = $true }
            }
            [void]$saved.Add($s.value.key)
        }
        $count += @($b.notices).Count
    }
    # Every envelope is recorded: the state moves on, then they are put.
    $d.pending = @(@($d.pending) + @($saved.ToArray()))
    if ($all.Count -gt 0) { $d.sentN = [long]([System.Math]::Max([double]$d.sentN, [double]$all[-1].n)) }
    $d.follows = $followsHash
    $d.phones = $trusted
    try { Write-HordeNoticesChannelState -HordeHome $homeDir -State $d }
    catch { [void]$out.Add("notices recorded, and the notices channel state could not be written: " + $_.Exception.Message + "; they are sent again after a restart, and the phone shows each once"); return [pscustomobject]@{ lines = @($out.ToArray()); failed = $true } }
    $what = "" + $count + " notice(s) and the follow switches in " + $saved.Count + " envelope(s)"
    $why = Send-HordeNoticesChannelPending -Context $Context -D $d -HordeHome $homeDir -Keep $keep -Trusted $trusted
    if ($why -cne "") { [void]$out.Add($what + " recorded; not delivered yet: " + $why); return [pscustomobject]@{ lines = @($out.ToArray()); failed = $true } }
    [void]$out.Add($what + " sent")
    return [pscustomobject]@{ lines = @($out.ToArray()); failed = $failed }
}

function Get-HordeNoticesChannelStamp {
    # A file's length and last write, as one text: what the Glance compares. "" when it is not there.
    param([string]$Path)
    try { $i = New-Object System.IO.FileInfo -ArgumentList $Path; if (-not $i.Exists) { return "" }; return ("" + $i.Length + "|" + $i.LastWriteTimeUtc.Ticks) } catch { return "" }
}

function Get-HordeNoticesChannelFullStamp {
    # The notices, the switches and the followed progress log, as one text (IDLE, in the Tick).
    param([Parameter(Mandatory = $true)][string]$Store, [Parameter(Mandatory = $true)]$D)
    return ((Get-HordeNoticesChannelStamp -Path (Get-HordeNoticeLogPath -Store $Store)) + "/" + (Get-HordeNoticesChannelStamp -Path ([System.IO.Path]::Combine($Store, "follows.json"))) + "/" + $(if ("$($D.path)" -cne "") { Get-HordeNoticesChannelStamp -Path $D.path } else { "" }))
}

function Test-HordeNoticesChannelGlance {
    # THE GLANCE (channels/Port.ps1): has the notices log or the follow switches changed since the last
    # look? Two files asked their length and last write, nothing opened, nothing else read - so a notice
    # is on his phone in about a second, not at the end of a watch. No until a Tick has looked once; no
    # while an envelope waits to be put (that is the turn's Tick's, after the runner's backoff). The
    # progress log is not looked at here: an entry of a followed lane waits for the turn's own Tick.
    param($Context)
    if (-not $Context.state.ContainsKey("notices")) { return $false }
    $mine = $Context.state["notices"]
    if (-not $mine.looked -or -not $mine.ContainsKey("store") -or $null -eq $mine.durable -or @($mine.durable.pending).Count -gt 0) { return $false }
    $log = Get-HordeNoticesChannelStamp -Path (Get-HordeNoticeLogPath -Store $mine["store"])
    $fol = Get-HordeNoticesChannelStamp -Path ([System.IO.Path]::Combine($mine["store"], "follows.json"))
    $changed = ($log -cne $mine.logStamp -or $fol -cne $mine.followStamp)
    $mine.logStamp = $log; $mine.followStamp = $fol
    return $changed
}

# --- (3) in ---

function Read-HordeNoticesChannelFollow {
    # The phone's follow body, read strictly (the header, (3)): { ok; reason; value { setId; machine;
    # lane; on } }. Never throws for the body.
    param([AllowEmptyCollection()][byte[]]$Body)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
    try { $text = $strict.GetString($Body) } catch { $fail.reason = "the switch is not UTF-8"; return $fail }
    if (-not $text.TrimStart().StartsWith("{")) { $fail.reason = "the switch is not a JSON object"; return $fail }
    if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { $fail.reason = "the switch has a member more than once"; return $fail }
    try { $a = ConvertFrom-HordeJson -Text $text } catch { $fail.reason = "the switch is not JSON"; return $fail }
    if ($a -isnot [System.Management.Automation.PSCustomObject]) { $fail.reason = "the switch is not a JSON object"; return $fail }
    $names = @($a.PSObject.Properties | ForEach-Object { $_.Name })
    if ((@($names | Sort-Object) -join ",") -cne ($script:HordeNoticesChannelFollowMembers -join ",")) { $fail.reason = ("the switch's members are " + ($names -join ", ") + ", not " + ($script:HordeNoticesChannelFollowMembers -join ", ")); return $fail }
    if (-not ($a.v -is [int] -or $a.v -is [long]) -or $a.v -ne 1) { $fail.reason = "the switch is not version 1"; return $fail }
    if ($a.setId -isnot [string] -or $a.setId -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = "the switch's setId is not 32 lower-case hex"; return $fail }
    if ($a.machine -isnot [string] -or $a.machine -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = "the switch's machine is not a key id"; return $fail }
    if ($a.lane -isnot [string] -or -not (Test-HordeNoticeLane $a.lane)) { $fail.reason = "the switch's lane is not a lane"; return $fail }
    if ($a.on -isnot [bool]) { $fail.reason = "the switch's on is not true or false"; return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = [pscustomobject]@{ setId = $a.setId; machine = $a.machine; lane = $a.lane; on = [bool]$a.on } }
}

function Invoke-HordeNoticesChannelAccept {
    # (3) in the header: { outcome; reason }.
    param($Context, $Item)
    $r = Read-HordeNoticesChannelFollow -Body $Item.body
    if (-not $r.ok) { return [pscustomobject]@{ outcome = "refused"; reason = $r.reason } }
    if ($r.value.machine -cne $Context.signKeyId) { return [pscustomobject]@{ outcome = "refused"; reason = ("the switch is for another machine (" + $r.value.machine + "), not this one (" + $Context.signKeyId + ")") } }
    $set = Set-HordeNoticeFollow -Lane $r.value.lane -On $r.value.on -At ([long]$Item.ts) -Key $Item.key -HordeHome (Get-HordeNoticesChannelHome $Context)
    if ($set.state -cne "known") { return [pscustomobject]@{ outcome = "retry"; reason = ("the follow switches could not be written now: " + $set.reason) } }
    $words = $(if ($r.value.on) { "on" } else { "off" })
    if (-not $set.value.changed) { return [pscustomobject]@{ outcome = "done"; reason = ("following " + (Get-HordeNoticeLaneWords -Lane $r.value.lane) + " " + $words + ": the machine already holds this or a later setting") } }
    return [pscustomobject]@{ outcome = "done"; reason = ("following " + (Get-HordeNoticeLaneWords -Lane $r.value.lane) + " is now " + $words) }
}

$null = Register-HordeRelayChannel -Folder $script:HordeNoticesChannelFolder -Name "notices" -Kinds @("follow") -Senders "founder" `
    -Accept { param($Context, $Item) return (Invoke-HordeNoticesChannelAccept -Context $Context -Item $Item) } `
    -Tick { param($Context) return (Invoke-HordeNoticesChannelTick -Context $Context) } `
    -Glance { param($Context) return (Test-HordeNoticesChannelGlance -Context $Context) }
