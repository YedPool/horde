# fleet/Lots.ps1 - parking lots as the founder reads them (T-0216): list them newest first with each member's
# state, wake a whole lot or any of its members and record the wake, and write down parks that happened before
# lots existed. The tables (the audit's parking_lot, parking_lot_member, wake, wake_member), their ULIDs, and why
# the record keeps the detail are in fleet/LotTables.ps1.
#
#   horde fleet lots [-Json]                                   Get-HordeFleetLots
#   horde fleet wake -Lot <id> [-Members a,b] [-DryRun]         Invoke-HordeFleetWakeLot
#   horde fleet wake <hibernation id> [-Only a,b]               the same wake, by the folder's name
#   horde fleet lots backfill -File <json>                     Invoke-HordeFleetLotBackfill
#
# A MEMBER IS ASLEEP WHEN IT IS IN THE LOT AND NOT RUNNING - the meaning fleet/Asleep.ps1 gave the word in PR 326,
# decided by the same adapter's liveness rule a wake asks. So a member whose process runs is never asleep, whatever
# its stored state says (a hand restart, a terminal restore): it is "woken" when the lot's last word for it was
# woken, and "still-awake" otherwise. A member that is not running keeps the lot's last word when that word is
# woken, still-awake or failed (it woke, it never slept, the wake could not bring it back), and is "asleep" for
# every other word. Not proven running is not running: the same side Asleep.ps1 takes, because its mail only queues.
# Which processes run cannot be read: the answer is unknown, with the reason, and no member is guessed.
#
# A WAKE OF A LOT IS A WAKE (fleet/Wake.ps1), with a smaller list. -Members picks sessions by id (a unique prefix of
# eight or more characters, or an exact label); a name that picks nobody, or more than one, refuses and nothing is
# woken. Held spawns, the liveness refusal, the 15 percent memory gate and the removal of the no-restore marker are
# the wake's own and are not repeated here, so they cannot drift. What this adds is the record: every wake that is
# not a dry run writes a wake row (which lot, when, by whom) and a wake_member row for each session it was asked
# to wake, with its outcome and the id it came back under.
#
# A BACKFILL WRITES A RECORD TOO. The parks it records happened before lots existed, so the only detail there is
# is the file's and the fleet registry's; a record is built from it (members with a working directory), so that a
# wake of a backfilled lot is the same wake as any other. A member with no working directory has only its
# parking_lot_member row: it cannot be started anywhere, and a wake reports it failed, never guesses a folder.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Wake.ps1")

function Get-HordeFleetLotMemberStatus {
    # The state a person reads for one member: asleep, woken, still-awake or failed (header). -Stored is the
    # lot's own last word, in the record's vocabulary.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Stored, [Parameter(Mandatory = $true)][bool]$Running)
    if ($Running) { if ($Stored -ceq "woken") { return "woken" }; return "still-awake" }
    if (@("failed", "woken", "still-awake") -ccontains $Stored) { return $Stored }
    return "asleep"
}

function Get-HordeFleetStoredWord {
    # The lot's last word for a member: the record's own state when the record holds the session, else the
    # row's (parked, woken, dropped) read back into the record's words.
    param($Row, $Session)
    if ($null -ne $Session) { return ("" + $Session.state) }
    switch ("" + $Row.state) { "woken" { return "woken" } "dropped" { return "still-awake" } default { return "exited" } }
}

function Get-HordeFleetLots {
    # Every lot as an answer: known { lots; skipped }, lots newest first (by created_at, then by id), each
    # { id; hibernation_id; created_at; by; reason; selection_kind; members; wakes }. A member is its row's
    # columns (session_id, note) with what the record says of the session (label, role, parent, cwd, pane), the
    # `state` above and `stored`, the lot's own word. skipped has one line for each lot that could not be read: one
    # corrupt lot is reported and the rest still listed. Unknown, naming why, when which processes run cannot be
    # read. -Agent is the harness adapter whose liveness decides (fleet/Port.ps1); when not given, the loaded one.
    param([string]$HordeHome = (Get-HordeHome), $Agent = $null)
    $dir = Get-HordeFleetHibernationsDir -HordeHome $HordeHome
    $skipped = New-Object System.Collections.ArrayList
    $read = New-Object System.Collections.ArrayList
    $empty = { $a = New-HordeKnown -Value ([pscustomobject]@{ lots = @(); skipped = @($skipped) }); return $a }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return (& $empty) }
    $ids = @()
    try { $ids = @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction Stop | ForEach-Object { $_.Name } | Where-Object { $_ -cmatch $script:HordeFleetIdPattern }) }
    catch { return (New-HordeUnknown -Reason ("the lots folder could not be listed: " + $_.Exception.Message)) }
    foreach ($id in $ids) {
        $one = Read-HordeFleetLot -Id $id -HordeHome $HordeHome
        if ($one.state -ceq "absent") { continue }
        if ($one.state -cne "known") { [void]$skipped.Add("lot " + $id + " is skipped: " + $one.reason); continue }
        [void]$read.Add($one.value)
    }
    if ($read.Count -eq 0) { return (& $empty) }
    $adapter = $Agent
    if ($null -eq $adapter) {
        $found = Resolve-HordeFleetAdapter -Kind "agent"
        if ($found.state -cne "known") { return (New-HordeUnknown -Reason ("which members are asleep cannot be told, because which run cannot: " + $found.reason)) }
        $adapter = $found.value
    }
    $snapshot = $null
    try { $snapshot = & $adapter.snapshot } catch { return (New-HordeUnknown -Reason ("which members are asleep cannot be told, because which run cannot be read: " + $_.Exception.Message)) }
    $lots = New-Object System.Collections.ArrayList
    foreach ($one in $read) {
        $bySid = @{}
        if ($null -ne $one.record) { foreach ($s in @($one.record.sessions)) { $bySid["" + $s.sessionId] = $s } }
        $recordIds = @()
        if ($null -ne $one.record) { $recordIds = @(@($one.record.sessions) | ForEach-Object { "" + $_.sessionId; $w = "" + (Get-HordeFleetMember $_ "wokenAs"); if ($w -ne "") { $w } }) }
        $rows = New-Object System.Collections.ArrayList
        foreach ($m in @($one.members)) {
            $sess = $bySid["" + $m.session_id]
            $cwd = $(if ($null -ne $sess) { "" + $sess.cwd } else { "" })
            $v = $null
            try {
                if ($null -ne $sess) { $v = & $adapter.verdict $snapshot (Get-HordeFleetCurrentId -Session $sess) $cwd $recordIds (Get-HordeFleetSince -Session $sess -Record $one.record) (Get-HordeFleetMember $sess "process") }
                else { $v = & $adapter.verdict $snapshot ("" + $m.session_id) $cwd @() }
            } catch { return (New-HordeUnknown -Reason ("which members are asleep cannot be told, because whether " + $m.session_id + " runs cannot be read: " + $_.Exception.Message)) }
            if ($null -eq $v) { return (New-HordeUnknown -Reason ("which members are asleep cannot be told, because the harness answered nothing about " + $m.session_id)) }
            if ("" + (Get-HordeFleetMember $v "kind") -ceq "reading") { return (New-HordeUnknown -Reason ("which members are asleep cannot be told, because which run cannot be read: " + (Get-HordeFleetMember $v "reason"))) }
            $running = ("" + (Get-HordeFleetMember $v "state") -ceq "running")
            $stored = Get-HordeFleetStoredWord -Row $m -Session $sess
            $g = { param($o, $n) $x = Get-HordeFleetMember $o $n; if ($null -eq $x) { "" } else { "" + $x } }
            [void]$rows.Add([pscustomobject][ordered]@{
                session_id = "" + $m.session_id; label = (& $g $sess "label"); role = (& $g $sess "role"); parent = (& $g $sess "parent"); cwd = $cwd
                pane = (& $g $sess "pane"); note = (& $g $m "note"); state = (Get-HordeFleetLotMemberStatus -Stored $stored -Running $running); stored = $stored })
        }
        $by = ""
        if ($null -ne $one.record -and $null -ne (Get-HordeFleetMember $one.record "parkedBy")) { $by = "" + $one.record.parkedBy }
        elseif ($null -ne (Get-HordeFleetMember $one.lot "created_by_session_id")) { $by = "" + $one.lot.created_by_session_id }
        $kind = Get-HordeFleetMember $one.lot "selection_kind"
        $kv = Get-HordeFleetMember $one.lot "keep_visible"
        $wakes = @(Read-HordeFleetWakes -Dir (Join-Path (Get-HordeFleetHibernationsDir -HordeHome $HordeHome) $one.folder) | ForEach-Object {
            [pscustomobject][ordered]@{ id = "" + $_.wake.id; requested_at = "" + $_.wake.requested_at; members = @($_.members | ForEach-Object { $nid = Get-HordeFleetMember $_ "new_session_id"; [pscustomobject][ordered]@{ session_id = "" + $_.session_id; new_session_id = $(if ($null -ne $nid) { "" + $nid } else { "" }); outcome = "" + $_.outcome } }) } })
        [void]$lots.Add([pscustomobject][ordered]@{ id = "" + $one.lot.id; hibernation_id = "" + $one.folder; created_at = "" + $one.lot.created_at; by = $by; reason = "" + $one.lot.reason
            selection_kind = $(if ($null -ne $kind) { "" + $kind } else { "" }); keep_visible = $(if ("" + $kv -ceq "1") { 1 } else { 0 }); members = @($rows); wakes = @($wakes) })
    }
    # NEWEST FIRST: the founder reads his parks by when they were parked. The id breaks a tie, being the same second.
    $sorted = @($lots | Sort-Object -Property @{ Expression = { $_.created_at }; Descending = $true }, @{ Expression = { $_.id }; Descending = $true })
    return (New-HordeKnown -Value ([pscustomobject]@{ lots = @($sorted); skipped = @($skipped) }))
}

function Format-HordeFleetLotsText {
    # The lots as lines for a person: one line for the lot, then one for each member.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Lots)
    $lines = New-Object System.Collections.ArrayList
    foreach ($l in @($Lots)) {
        $counts = New-Object System.Collections.ArrayList
        foreach ($k in @("asleep", "woken", "still-awake", "failed")) {
            $n = @(@($l.members) | Where-Object { "" + $_.state -ceq $k }).Count
            if ($n -gt 0) { [void]$counts.Add("" + $n + " " + $k) }
        }
        $by = $(if ("" + $l.by -ne "") { " by " + $l.by } else { "" })
        $why = $(if ("" + $l.reason -ne "") { ", " + $l.reason } else { "" })
        [void]$lines.Add("lot " + $l.id + "  " + $l.created_at + $by + $why + $(if ("" + $l.keep_visible -ceq "1") { ", kept visible" } else { "" }) + "  " + @($l.members).Count + " member(s): " + ($counts -join ", "))
        foreach ($m in @($l.members)) {
            $name = $(if ("" + $m.label -ne "") { $m.label + " (" + ("" + $m.session_id).Substring(0, 8) + ")" } else { ("" + $m.session_id).Substring(0, 8) })
            [void]$lines.Add("  " + ("" + $m.state).PadRight(11) + " " + $name + " " + $m.role + " " + $m.cwd)
        }
    }
    return @($lines)
}

$script:HordeFleetBackfillLotKeys = @("at", "by", "why", "members")
$script:HordeFleetBackfillMemberKeys = @("sessionId", "label", "role", "parent", "cwd", "pane", "parkedNote")

function Read-HordeFleetBackfillFile {
    # The lots a backfill file holds, as { hid; at; by; reason; lot; members; sessions } each, checked whole BEFORE
    # anything is written: the file is { "v": 1, "lots": [ { at, by, why, members: [ { sessionId, label?, role?,
    # parent?, cwd?, pane?, parkedNote? } ] } ] }. Strict, as the fixtures' contract is (test/fixtures/fleet/README.md): a
    # member the shape does not name is refused, never ignored. A lot's folder is its time, so two lots at one second
    # are refused. A member's missing fields are filled from -Enrich ($sessionId -> { label; parent; cwd; pane } or $null),
    # so a file carries no machine path; its note is PARKED-<label>.md in -ParkedFolder when the file is there.
    # THROWS, naming the lot and the member, on anything else.
    param([Parameter(Mandatory = $true)][string]$File, $Enrich = $null, [string]$ParkedFolder = "", [scriptblock]$ParkedExists = $null)
    if ($null -eq $ParkedExists) { $ParkedExists = { param($p) Test-Path -LiteralPath $p -PathType Leaf } }
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw ("the backfill file " + $File + " is not there") }
    $doc = $null
    try { $doc = ConvertFrom-HordeJson -Text (Read-HordeSharedText -Path $File) } catch { throw ("the backfill file " + $File + " is not JSON: " + $_.Exception.Message) }
    if ($null -eq $doc -or $null -eq $doc.PSObject.Properties["v"] -or $doc.v -ne 1) { throw "the backfill file must be an object with v 1" }
    $extra = @($doc.PSObject.Properties | Where-Object { @("v", "lots") -cnotcontains $_.Name } | ForEach-Object { $_.Name })
    if ($extra.Count -gt 0) { throw ("the backfill file has a member it does not know: " + ($extra -join ", ")) }
    $docLots = @($doc.lots)
    if ($null -eq $doc.PSObject.Properties["lots"] -or $docLots.Count -eq 0) { throw "the backfill file holds no lot" }
    $out = New-Object System.Collections.ArrayList
    $seenIds = New-Object 'System.Collections.Generic.HashSet[string]'
    $n = 0
    foreach ($dl in $docLots) {
        $n++
        $where = "lot " + $n + " of the backfill file"
        foreach ($k in $script:HordeFleetBackfillLotKeys) { if ($null -eq $dl.PSObject.Properties[$k]) { throw ($where + " has no " + $k) } }
        $bad = @($dl.PSObject.Properties | Where-Object { $script:HordeFleetBackfillLotKeys -cnotcontains $_.Name } | ForEach-Object { $_.Name })
        if ($bad.Count -gt 0) { throw ($where + " has a member it does not know: " + ($bad -join ", ")) }
        $at = [datetime]::MinValue
        if (-not [datetime]::TryParseExact("" + $dl.at, "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture, ([System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal), [ref]$at)) { throw ($where + ": at '" + $dl.at + "' is not a UTC time, yyyy-MM-ddTHH:mm:ssZ") }
        $hid = New-HordeFleetHibernationId -At $at
        if (-not $seenIds.Add($hid)) { throw ($where + ": another lot of the file is at the same second (" + $hid + "), and a lot's folder is its time") }
        $by = ("" + $dl.by).Trim()
        $seed = "backfill|" + (Format-HordeFleetTime -At $at) + "|" + $dl.why
        # The id depends on the time and seed only; the parking session is known once the members are, so the row is made again below.
        $lot = New-HordeFleetLot -At $at -Reason ("" + $dl.why) -Kind "backfill" -Seed $seed
        $labelSessions = @{}
        $rows = New-Object System.Collections.ArrayList
        $sessions = New-Object System.Collections.ArrayList
        foreach ($dm in @($dl.members)) {
            $bad = @($dm.PSObject.Properties | Where-Object { $script:HordeFleetBackfillMemberKeys -cnotcontains $_.Name } | ForEach-Object { $_.Name })
            if ($bad.Count -gt 0) { throw ($where + ": a member has a member it does not know: " + ($bad -join ", ")) }
            $get = { param($o, $name) $p = $o.PSObject.Properties[$name]; if ($null -eq $p -or $null -eq $p.Value) { return "" }; return ("" + $p.Value) }
            $sid = & $get $dm "sessionId"
            $info = $null
            if ($null -ne $Enrich -and $sid -cmatch $script:HordeFleetSessionPattern) { $info = & $Enrich $sid }
            $fill = { param($name) $v = & $get $dm $name; if ($v -ne "" -or $null -eq $info) { return $v }; $p = $info.PSObject.Properties[$name]; if ($null -eq $p -or $null -eq $p.Value) { return "" }; return ("" + $p.Value) }
            $label = & $fill "label"
            if ($label -ne "" -and $sid -cmatch $script:HordeFleetSessionPattern) { $labelSessions[$label] = $sid }
            $note = & $get $dm "parkedNote"
            if ($note -eq "" -and $label -ne "" -and $ParkedFolder -ne "") { $pf = Join-Path $ParkedFolder ("PARKED-" + $label + ".md"); if ([bool](& $ParkedExists $pf)) { $note = $pf } }
            $role = & $get $dm "role"; if (@("orc", "warg") -cnotcontains $role) { $role = "other" }
            $row = [ordered]@{ lot_id = "" + $lot.id; session_id = $sid; state = "parked" }
            if ($note -ne "") { $row["note"] = $note }
            [void]$rows.Add([pscustomobject]$row)
            $cwd = & $fill "cwd"
            if ($cwd -ne "") {
                $s = [ordered]@{ sessionId = $sid; role = $role; cwd = $cwd; state = "exited"; history = @([pscustomobject][ordered]@{ state = "exited"; at = (Format-HordeFleetTime -At $at) }) }
                if ($label -ne "") { $s["label"] = $label }
                $par = & $fill "parent"; if ($par -cmatch $script:HordeFleetSessionPattern) { $s["parent"] = $par }
                $pn = & $fill "pane"; if ($pn -ne "") { $s["pane"] = $pn }
                if ($note -ne "") { $s["parkedFile"] = $note }
                [void]$sessions.Add([pscustomobject]$s)
            }
        }
        # WHO PARKED is kept whatever it is (review of PR 338): a session id, else the id of the member it is the label of, and
        # the word itself only in the record's parkedBy (created_by_orc_id is the orc table's foreign key, never a free word).
        $byId = ""
        if ($by -cmatch $script:HordeFleetSessionPattern) { $byId = $by }
        elseif ($by -ne "") {
            if ($labelSessions.ContainsKey($by)) { $byId = "" + $labelSessions[$by] }
        }
        $lot = New-HordeFleetLot -At $at -ById $byId -Reason ("" + $dl.why) -Kind "backfill" -Seed $seed
        $findings = @(Test-HordeFleetLotFiles -Lot $lot -Members @($rows) -FolderId $hid)
        if ($findings.Count -gt 0) { throw ($where + " breaks the lot shape: " + ($findings -join "; ")) }
        [void]$out.Add([pscustomobject]@{ hid = $hid; at = $at; by = $by; lot = $lot; members = @($rows); sessions = @($sessions) })
    }
    return @($out)
}

function Test-HordeFleetBackfillOwnRecord {
    # "" when the record.json in the folder of the parsed backfill lot -Parsed is this backfill's own half-written lot: taken at
    # its time, holding exactly the sessions it would have written. Otherwise the reason it is not (the record is some other park).
    param([Parameter(Mandatory = $true)]$Parsed, [string]$HordeHome = (Get-HordeHome))
    $r = Read-HordeFleetRecord -Id ("" + $Parsed.hid) -HordeHome $HordeHome
    if ($r.state -cne "known") { return ("the record cannot be read: " + $r.reason) }
    if (@($Parsed.sessions).Count -eq 0) { return "this backfill writes no record for the lot, so one that is there is another park's" }
    $at = Format-HordeFleetTime -At $Parsed.at
    if ("" + $r.value.createdAt -cne $at) { return ("it was taken at " + $r.value.createdAt + ", not " + $at) }
    $have = @(@($r.value.sessions) | ForEach-Object { "" + $_.sessionId } | Sort-Object)
    $want = @(@($Parsed.sessions) | ForEach-Object { "" + $_.sessionId } | Sort-Object)
    if (($have -join ",") -cne ($want -join ",")) { return "it holds other sessions than the file names" }
    return ""
}

function Invoke-HordeFleetLotBackfill {
    # `horde fleet lots backfill -File <json>`: write each lot of the file that is not there yet (selection_kind
    # backfill). IDEMPOTENT: a lot whose folder has a parking_lot.json or a record.json already is left as it is and
    # said, so a second run writes nothing; its id is made from its time and why, so it is the same id every time.
    # The whole file is checked first: one bad lot writes none. Returns { written; skipped; lines }.
    # -Deps: Enrich, ParkedFolder, ParkedExists (optional; see Read-HordeFleetBackfillFile), AgentName and HostName
    # (the adapters a woken session will be started through; they name the record).
    param([Parameter(Mandatory = $true)][string]$File, $Deps = $null, [string]$HordeHome = (Get-HordeHome))
    $enrich = $null; $parkedFolder = ""; $parkedExists = $null; $agentName = "unknown"; $hostName = "unknown"
    if ($null -ne $Deps) {
        if ($null -ne $Deps.PSObject.Properties["Enrich"]) { $enrich = $Deps.Enrich }
        if ($null -ne $Deps.PSObject.Properties["ParkedFolder"]) { $parkedFolder = "" + $Deps.ParkedFolder }
        if ($null -ne $Deps.PSObject.Properties["ParkedExists"]) { $parkedExists = $Deps.ParkedExists }
        if ($null -ne $Deps.PSObject.Properties["AgentName"] -and "" + $Deps.AgentName -ne "") { $agentName = "" + $Deps.AgentName }
        if ($null -ne $Deps.PSObject.Properties["HostName"] -and "" + $Deps.HostName -ne "") { $hostName = "" + $Deps.HostName }
    }
    $parsed = @(Read-HordeFleetBackfillFile -File $File -Enrich $enrich -ParkedFolder $parkedFolder -ParkedExists $parkedExists)
    $lines = New-Object System.Collections.ArrayList
    $written = 0; $skipped = 0; $refused = 0
    foreach ($p in $parsed) {
        $dir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $HordeHome) $p.hid
        # THE LOT ROW IS THE COMMIT: a lot is there once its parking_lot.json is (fleet/LotTables.ps1), so that alone is "there already".
        if (Test-Path -LiteralPath (Join-Path $dir "parking_lot.json") -PathType Leaf) {
            $skipped++; [void]$lines.Add("lot " + $p.lot.id + " (" + $p.hid + ") is there already, left as it is"); continue
        }
        $recPath = Join-Path $dir "record.json"
        if (Test-Path -LiteralPath $recPath -PathType Leaf) {
            # A record with no lot row: a hibernate of the same second, or an earlier backfill that stopped part way. It is
            # completed only when it is this backfill's own (its time and its sessions), else this lot is refused.
            $why = Test-HordeFleetBackfillOwnRecord -Parsed $p -HordeHome $HordeHome
            if ($why -ne "") { $refused++; [void]$lines.Add("lot " + $p.lot.id + " (" + $p.hid + ") is refused: its folder holds a record that is not this backfill's (" + $why + ")"); continue }
            [void](Write-HordeFleetLot -Dir $dir -Lot $p.lot -Members @($p.members))
            $written++; [void]$lines.Add("completed lot " + $p.lot.id + " (" + $p.hid + "): its record was there from an earlier run, its lot rows were not")
            continue
        }
        # WRITTEN IN A STAGING FOLDER, then renamed to the lot's name in one step: a crash leaves "<id>.partial", which no reader
        # lists (it is not a hibernation id), never a record that reads as a lot from before lots. A re-run starts it again.
        $stage = $dir + ".partial"
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
        [void](New-Item -ItemType Directory -Path $stage -Force)
        if (@($p.sessions).Count -gt 0) {
            $labels = @(@($p.sessions) | Where-Object { $null -ne $_.PSObject.Properties["label"] } | ForEach-Object { "" + $_.label })
            $rec = [pscustomobject][ordered]@{ schemaVersion = 1; id = $p.hid; createdAt = (Format-HordeFleetTime -At $p.at); agent = $agentName; host = $hostName
                selection = [pscustomobject][ordered]@{ kind = "labels"; labels = @($labels); exclude = @() }; sessions = @($p.sessions) }
            if ($p.by -cmatch '\A[^\x00-\x1F]{1,200}\z') { $rec | Add-Member -NotePropertyName "parkedBy" -NotePropertyValue $p.by -Force }
            [void](Write-HordeFleetRecord -Dir $stage -Record $rec -FolderId $p.hid)
        }
        [void](Write-HordeFleetLot -Dir $stage -Lot $p.lot -Members @($p.members) -FolderId $p.hid)
        if (Test-Path -LiteralPath $dir) { foreach ($f in @(Get-ChildItem -LiteralPath $stage -Force)) { Move-Item -LiteralPath $f.FullName -Destination $dir -Force }; Remove-Item -LiteralPath $stage -Force }
        else { Move-Item -LiteralPath $stage -Destination $dir }
        $written++; [void]$lines.Add("wrote lot " + $p.lot.id + " (" + $p.hid + ", " + @($p.members).Count + " member(s), " + $p.lot.reason + ")")
    }
    [void]$lines.Add("backfill: " + $written + " lot(s) written, " + $skipped + " already there" + $(if ($refused -gt 0) { ", " + $refused + " refused" } else { "" }))
    return [pscustomobject]@{ written = $written; skipped = $skipped; refused = $refused; lines = @($lines) }
}

function Resolve-HordeFleetLotMembers {
    # The session ids -Names pick among -Rows (each { session_id; label }): an exact session id, an exact label, or a
    # unique prefix of eight or more hex characters. THROWS when a name picks nobody or more than one.
    param([Parameter(Mandatory = $true)][string[]]$Names, [Parameter(Mandatory = $true)][object[]]$Rows, [string]$Lot = "")
    $out = New-Object System.Collections.ArrayList
    foreach ($nm in @($Names | Where-Object { "" + $_ -ne "" })) {
        $name = ("" + $nm).Trim()
        $hit = @(@($Rows) | Where-Object { "" + $_.session_id -ceq $name })
        if ($hit.Count -eq 0) { $hit = @(@($Rows) | Where-Object { "" + $_.label -ceq $name }) }
        if ($hit.Count -eq 0 -and $name -cmatch '\A[0-9a-f]{8,36}\z') { $hit = @(@($Rows) | Where-Object { ("" + $_.session_id).StartsWith($name, [System.StringComparison]::Ordinal) }) }
        if ($hit.Count -eq 0) { throw ("lot " + $Lot + " holds no member '" + $name + "', so nothing was woken") }
        if ($hit.Count -gt 1) { throw ("'" + $name + "' names " + $hit.Count + " members of lot " + $Lot + "; which is meant cannot be told, so nothing was woken") }
        if (-not $out.Contains("" + $hit[0].session_id)) { [void]$out.Add("" + $hit[0].session_id) }
    }
    return @($out)
}

function Invoke-HordeFleetWakeLot {
    # `horde fleet wake -Lot <id> [-Members a,b] [-DryRun] [-Retry]`: wake the whole lot, or just -Members, through
    # Invoke-HordeFleetWake with every rule it has, and record the wake (header). -Lot is the lot's ULID or the
    # hibernation id of its folder. -By is the session asking. Returns { id; wake; lines; outcomes } as a wake does;
    # `wake` is the wake row's id, empty for a dry run. Throws, changing nothing, when the lot is not there or cannot
    # be read, or -Members names no member or more than one.
    param([Parameter(Mandatory = $true)][string]$Lot, [string[]]$Members = @(), [Parameter(Mandatory = $true)]$Deps, [switch]$DryRun, [switch]$Retry, [string]$By = "", [string]$HordeHome = (Get-HordeHome))
    $read = Read-HordeFleetLot -Id $Lot -HordeHome $HordeHome
    if ($read.state -cne "known") { throw $read.reason }
    $hid = "" + $read.value.folder
    # WHEN IT WAS ASKED, not when it ended: a wake polls for minutes, and the row says when the request was made.
    $requestedAt = & $Deps.Now
    $record = $read.value.record
    $labelOf = @{}
    if ($null -ne $record) { foreach ($s in @($record.sessions)) { $l = Get-HordeFleetMember $s "label"; if ($null -ne $l) { $labelOf["" + $s.sessionId] = "" + $l } } }
    $rows = @($read.value.members | ForEach-Object { [pscustomobject]@{ session_id = "" + $_.session_id; label = $(if ($labelOf.ContainsKey("" + $_.session_id)) { $labelOf["" + $_.session_id] } else { "" }) } })
    $wanted = @($rows | ForEach-Object { $_.session_id })
    $named = @($Members | Where-Object { "" + $_ -ne "" })
    if ($named.Count -gt 0) { $wanted = @(Resolve-HordeFleetLotMembers -Names $named -Rows $rows -Lot $hid) }
    $lines = New-Object System.Collections.ArrayList
    $outcomes = New-Object System.Collections.ArrayList
    $inRecord = @()
    if ($null -ne $record) { $inRecord = @(@($record.sessions) | ForEach-Object { "" + $_.sessionId }) }
    $wakeIds = @($wanted | Where-Object { $inRecord -ccontains $_ })
    # A MEMBER THE RECORD DOES NOT HOLD has no working directory to start in (header, BACKFILL): reported, not guessed.
    foreach ($sid in @($wanted | Where-Object { $inRecord -cnotcontains $_ })) {
        $lab = $(if ($labelOf.ContainsKey($sid)) { $labelOf[$sid] } else { "" })
        $name = $(if ($lab -ne "") { $lab + " (" + $sid.Substring(0, 8) + ")" } else { $sid.Substring(0, 8) })
        $why = "no working directory is known for it, so there is nowhere to start it"
        [void]$lines.Add("  failed " + $name + ": " + $why)
        [void]$outcomes.Add([pscustomobject]@{ sessionId = $sid; label = $lab; outcome = "failed"; reason = $why })
    }
    if ($wakeIds.Count -gt 0) {
        # The whole record is asked for with no id list when everything in it is wanted, so a later wake of the
        # same lot is the same wake it always was.
        $only = $(if ($named.Count -eq 0) { @() } else { $wakeIds })
        $sink = New-Object System.Collections.ArrayList
        $done = $null
        try { $done = Invoke-HordeFleetWake -Id $hid -Deps $Deps -DryRun:$DryRun -Retry:$Retry -OnlyIds $only -HordeHome $HordeHome -OutcomesSink $sink }
        catch {
            # A WAKE THAT THROWS AFTER IT STARTED SESSIONS still happened: record what it gathered, the rest as failed with the
            # error, then let the error through (review of PR 338). One that threw before any outcome changed nothing and records nothing.
            $err = $_
            if (-not $DryRun -and $sink.Count -gt 0) {
                foreach ($o in @($sink)) { [void]$outcomes.Add($o) }
                $got = @($outcomes | ForEach-Object { "" + $_.sessionId })
                foreach ($sid in @($wakeIds | Where-Object { $got -cnotcontains $_ })) {
                    $lab = $(if ($labelOf.ContainsKey($sid)) { $labelOf[$sid] } else { "" })
                    [void]$outcomes.Add([pscustomobject]@{ sessionId = $sid; label = $lab; outcome = "failed"; reason = ("the wake stopped on an error: " + $err.Exception.Message) })
                }
                try { [void](Write-HordeFleetWake -Dir (Join-Path (Get-HordeFleetHibernationsDir -HordeHome $HordeHome) $hid) -LotId ("" + $read.value.lot.id) -At $requestedAt -ById $By -Outcomes @($outcomes)) } catch { $null = $_ }
            }
            throw $err
        }
        foreach ($l in @($done.lines)) { [void]$lines.Add($l) }
        foreach ($o in @($done.outcomes)) { [void]$outcomes.Add($o) }
    } else { [void]$lines.Add("  nothing to wake") }
    $wakeId = ""
    if (-not $DryRun -and $outcomes.Count -gt 0) {
        $newIds = @{}
        $again = Read-HordeFleetRecord -Id $hid -HordeHome $HordeHome
        if ($again.state -ceq "known") { foreach ($s in @($again.value.sessions)) { $w = Get-HordeFleetMember $s "wokenAs"; if ($null -ne $w -and "" + $w -ne "") { $newIds["" + $s.sessionId] = "" + $w } } }
        $recordable = @($outcomes | Where-Object { @("woken", "still-awake", "failed", "held", "asleep") -ccontains ("" + $_.outcome) })
        if ($recordable.Count -gt 0) { $wakeId = Write-HordeFleetWake -Dir (Join-Path (Get-HordeFleetHibernationsDir -HordeHome $HordeHome) $hid) -LotId ("" + $read.value.lot.id) -At $requestedAt -ById $By -Outcomes $recordable -NewIds $newIds }
    }
    return [pscustomobject]@{ id = $hid; wake = $wakeId; lines = @($lines); outcomes = @($outcomes) }
}
