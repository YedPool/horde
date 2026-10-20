# fleet/LotTables.ps1 - the parking lot's four tables, named and shaped as the founder's SSOT audit has them
# (work-data-ssot-audit-2026-10-19, "Target schema sketch", parking): parking_lot, parking_lot_member, wake and
# wake_member. T-0216, the founder's words of 2026-10-19: "When we park, the park is one entity showing a list
# of orcs parked. Could choose to resurrect any combination of them or all. If I subsequently park other Orcs,
# they are another parking lot - new datetime and list this way I can see things organized by when they got
# parked."
#
#   <HORDE_HOME>\fleet\hibernations\<hid>\parking_lot.json           schema/fleet-parking-lot.v1
#   <HORDE_HOME>\fleet\hibernations\<hid>\parking_lot_member.json    schema/fleet-parking-lot-member.v1
#   <HORDE_HOME>\fleet\hibernations\<hid>\wakes\<wake id>\wake.json          schema/fleet-wake.v1
#   <HORDE_HOME>\fleet\hibernations\<hid>\wakes\<wake id>\wake_member.json   schema/fleet-wake-member.v1
#   <HORDE_HOME>\fleet\hibernations\<hid>\record.json                schema/fleet-hibernation.v1  (the detail)
#
# EACH FILE IS ONE TABLE: {"v":1,"table":"<name>","rows":[...]}. A row has exactly the report's columns - no more
# - and a column that is not known is LEFT OUT, never null (the idiom of schema/fleet-hibernation.v1; an import
# reads a missing column as NULL), so a row moves into the future fleet.db as it is. Foreign keys are the
# report's: parking_lot_member.lot_id -> parking_lot.id, wake.lot_id -> parking_lot.id, wake_member.wake_id ->
# wake.id; session ids are the harness's own uuids, the `session` table's keys.
#
# ID KIND: A ULID (the report: "every row has a ULID primary key, sortable by time, unique across PCs"). The 48
# bit time of a lot's ULID is its created_at, to the second; the folder it sits in (<hid>, yyyymmdd-hhmmss) is
# that same time, so a lot's folder is found from its id and a hibernation id still names the lot it always named
# (`horde fleet wake <hid>`, the phone's wake.json hibernationId). A hibernate run claims <hid> with CreateNew
# (fleet/Hibernation.ps1) before it writes anything, so two lots never share a folder. A lot from a backfill, or a
# record from before lots, has a ULID made from its time and a seed instead of from chance, so the same park is
# the same id every time: that is what makes a backfill idempotent, and a legacy record's id stable though nothing
# is written for it.
#
# THE RECORD KEEPS THE DETAIL. The audit's session table owns label, role, cwd, parent and pane, and the lot rows
# do not repeat them; record.json carries them (with placement, the process that ran it and its history, which a
# wake needs), so nothing is moved out of it and nothing is lost. While a lot has a record, the record is the
# authority for each member's state and parking_lot_member.json is its copy: Write-HordeFleetRecord, the one
# place a record is written, refreshes the copy in the same call (Sync-HordeFleetLotMembers). The member state is
# the audit's three words: parked, woken, dropped (the record's still-awake: it never slept, so it left the park).
# Whether a member is ASLEEP is not stored: it is the lot together with whether its process runs (fleet/Lots.ps1).
#
# A RECORD WITH NO parking_lot.json IS A LOT TOO. Every record taken before lots existed is read as one (reason
# "hibernate", selection_kind from its selection) and none is rewritten: a migration could only have lost
# something, and reading loses nothing.
#
# WRITTEN WHOLE OR NOT AT ALL, each file to a temporary file beside it and renamed over it in one step
# (core/FileAtomic.ps1). The members are written BEFORE the lot row: a lot is there only once its row is, so a
# crash between the two leaves a folder no reader lists, never a lot without members.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It uses Format-HordeFleetTime and
# ConvertTo-HordeFleetAsciiJson from fleet/Hibernation.ps1, which dot-sources it.

$script:HordeUlidAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
$script:HordeUlidPattern = '\A[0-7][0-9A-HJKMNP-TV-Z]{25}\z'
$script:HordeFleetLotSelectionKinds = @("all", "labels", "orcs", "backfill")
$script:HordeFleetTableNames = @{ lot = "parking_lot"; member = "parking_lot_member"; wake = "wake"; wakeMember = "wake_member" }

function New-HordeFleetUlid {
    # A ULID whose time is -At (to the millisecond) and whose 80 random bits are fresh, or, with -Seed, the first
    # 80 bits of SHA-256 of the seed: the same time and seed always make the same id.
    param([Parameter(Mandatory = $true)][datetime]$At, [string]$Seed = "")
    $ms = [long]([System.DateTimeOffset]::new($At.ToUniversalTime()).ToUnixTimeMilliseconds())
    $rnd = New-Object 'byte[]' 10
    if ($Seed -ne "") {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Seed)) } finally { $sha.Dispose() }
        [Array]::Copy($h, 0, $rnd, 0, 10)
    } else {
        $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
        try { $rng.GetBytes($rnd) } finally { $rng.Dispose() }
    }
    $bits = New-Object System.Text.StringBuilder
    [void]$bits.Append("00")
    for ($i = 5; $i -ge 0; $i--) { [void]$bits.Append([Convert]::ToString([int](($ms -shr (8 * $i)) -band 255), 2).PadLeft(8, "0")) }
    foreach ($b in $rnd) { [void]$bits.Append([Convert]::ToString([int]$b, 2).PadLeft(8, "0")) }
    $s = $bits.ToString()
    $out = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt 130; $i += 5) { [void]$out.Append($script:HordeUlidAlphabet[[Convert]::ToInt32($s.Substring($i, 5), 2)]) }
    return $out.ToString()
}

function Get-HordeFleetUlidTime {
    # The UTC time (to the millisecond) a ULID was made for.
    param([Parameter(Mandatory = $true)][string]$Ulid)
    if ($Ulid -cnotmatch $script:HordeUlidPattern) { throw ("'" + $Ulid + "' is not a ULID") }
    [long]$v = 0
    foreach ($ch in $Ulid.Substring(0, 10).ToCharArray()) { $v = ($v * 32) + $script:HordeUlidAlphabet.IndexOf($ch) }
    return ([System.DateTimeOffset]::FromUnixTimeMilliseconds($v).UtcDateTime)
}

function Get-HordeFleetLotDir {
    # The folder of the lot -Id, which is either its ULID or the hibernation id (yyyymmdd-hhmmss) of its folder.
    param([Parameter(Mandatory = $true)][string]$Id, [string]$HordeHome = (Get-HordeHome))
    $hid = Get-HordeFleetLotFolderId -Id $Id
    return (Join-Path (Get-HordeFleetHibernationsDir -HordeHome $HordeHome) $hid)
}

function Get-HordeFleetLotFolderId {
    # The folder name (hibernation id) of a lot given by its ULID or by that name. THROWS on anything else.
    param([Parameter(Mandatory = $true)][string]$Id)
    if ($Id -cmatch $script:HordeFleetIdPattern) { return $Id }
    if ($Id -cmatch $script:HordeUlidPattern) { return (New-HordeFleetHibernationId -At (Get-HordeFleetUlidTime -Ulid $Id)) }
    throw ("'" + $Id + "' is not a parking lot id (a ULID, or a hibernation id yyyymmdd-hhmmss)")
}

function New-HordeFleetLot {
    # The parking_lot row of a park taken at -At. -ById is the parking session's id and -ByOrc its Orc's id, each
    # only when known. -Kind is how the park chose its sessions: all, labels, orcs, or backfill. -Seed makes the id
    # a function of the park (backfill, legacy); without it the id is fresh.
    param([Parameter(Mandatory = $true)][datetime]$At, [string]$ById = "", [string]$ByOrc = "", [Parameter(Mandatory = $true)][string]$Reason, [string]$Kind = "", [string]$Seed = "", [switch]$KeepVisible)
    $why = ([string]($Reason -replace '[\x00-\x1F]+', ' ')).Trim()
    if ($why.Length -gt 200) { $why = $why.Substring(0, 197) + "..." }
    # To the second, as the folder and the table say it; named apart from -At, which a lint reads as a shadow of it.
    $wholeSecond = New-Object DateTime ($At.ToUniversalTime().Ticks - ($At.ToUniversalTime().Ticks % [TimeSpan]::TicksPerSecond)), ([System.DateTimeKind]::Utc)
    $row = [ordered]@{ id = (New-HordeFleetUlid -At $wholeSecond -Seed $Seed); created_at = (Format-HordeFleetTime -At $wholeSecond) }
    if ($ById -cmatch $script:HordeFleetSessionPattern) { $row["created_by_session_id"] = $ById }
    if ($ByOrc -ne "") { $row["created_by_orc_id"] = $ByOrc }
    $row["reason"] = $why
    if ($Kind -ne "") { $row["selection_kind"] = $Kind }
    # KEEP_VISIBLE IS KNOWN FOR EVERY LOT WRITTEN NOW (0 unless the park asked for 1), so it is always written.
    $row["keep_visible"] = $(if ($KeepVisible) { 1 } else { 0 })
    return [pscustomobject]$row
}

function Get-HordeFleetMemberState {
    # The audit's state for a record's state word: parked, woken or dropped.
    param([AllowEmptyString()][string]$RecordState)
    if ($RecordState -ceq "woken") { return "woken" }
    if ($RecordState -ceq "still-awake") { return "dropped" }
    return "parked"
}

function ConvertTo-HordeFleetLotMember {
    # The parking_lot_member row of one session of a record. -Prior is the row it had: its orc_id, tier and
    # note are kept when the record does not say.
    param([Parameter(Mandatory = $true)][string]$LotId, [Parameter(Mandatory = $true)]$Session, $Prior = $null, [int]$Tier = 0)
    $get = { param($o, $n) if ($null -eq $o) { return "" }; $p = $o.PSObject.Properties[$n]; if ($null -eq $p -or $null -eq $p.Value) { return "" }; return ("" + $p.Value) }
    $row = [ordered]@{ lot_id = $LotId; session_id = (& $get $Session "sessionId") }
    $orc = & $get $Prior "orc_id"; if ($orc -ne "") { $row["orc_id"] = $orc }
    $tier = & $get $Prior "tier"; if ($tier -ne "") { $row["tier"] = [int]$tier } elseif ($Tier -gt 0) { $row["tier"] = $Tier }
    $row["state"] = (Get-HordeFleetMemberState -RecordState (& $get $Session "state"))
    $note = & $get $Session "parkedFile"; if ($note -eq "") { $note = & $get $Prior "note" }
    if ($note -ne "") { $row["note"] = $note }
    return [pscustomobject]$row
}

function ConvertTo-HordeFleetLotMembers {
    # Every session of a record as rows, in the record's order, merged over -Prior rows (by session id).
    param([Parameter(Mandatory = $true)][string]$LotId, [Parameter(Mandatory = $true)]$Record, [object[]]$Prior = @(), [int]$Tier = 0)
    $byId = @{}
    foreach ($p in @($Prior)) { if ($null -ne $p) { $byId["" + $p.session_id] = $p } }
    return @(@($Record.sessions) | ForEach-Object { ConvertTo-HordeFleetLotMember -LotId $LotId -Session $_ -Prior $byId["" + $_.sessionId] -Tier $Tier })
}

function Test-HordeFleetTable {
    # Findings for rows against the schema -Name (fleet-parking-lot.v1 ...).
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][object[]]$Rows)
    $out = New-Object System.Collections.ArrayList
    $schema = Get-HordeSchema -Name $Name
    foreach ($r in @($Rows)) { foreach ($f in @(Test-HordeSchema -Value $r -Schema $schema)) { [void]$out.Add($Name + ": " + $f) } }
    return @($out)
}

function Test-HordeFleetLotFiles {
    # Findings for a lot row and its member rows: the schemas', and what they cannot say - the lot holds a member,
    # each member names this lot, and a session is in it once.
    param([Parameter(Mandatory = $true)]$Lot, [Parameter(Mandatory = $true)][object[]]$Members, [string]$FolderId = "")
    $out = New-Object System.Collections.ArrayList
    foreach ($f in @(Test-HordeFleetTable -Name "fleet-parking-lot.v1" -Rows @($Lot))) { [void]$out.Add($f) }
    foreach ($f in @(Test-HordeFleetTable -Name "fleet-parking-lot-member.v1" -Rows @($Members))) { [void]$out.Add($f) }
    if ($out.Count -gt 0) { return @($out) }
    if ($FolderId -ne "" -and (Get-HordeFleetLotFolderId -Id ("" + $Lot.id)) -cne $FolderId) { [void]$out.Add("the lot " + $Lot.id + " is made for " + (Get-HordeFleetLotFolderId -Id ("" + $Lot.id)) + " but sits in the folder " + $FolderId) }
    if ($FolderId -ne "" -and (New-HordeFleetHibernationId -At ([datetime]::ParseExact("" + $Lot.created_at, "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal))) -cne $FolderId) { [void]$out.Add("the lot says it was created at " + $Lot.created_at + " but sits in the folder " + $FolderId) }
    if (@($Members).Count -eq 0) { [void]$out.Add("the lot holds no member: an empty lot is never written") }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in @($Members)) {
        if ("" + $m.lot_id -cne "" + $Lot.id) { [void]$out.Add("member " + $m.session_id + " names lot " + $m.lot_id + ", not " + $Lot.id) }
        if (-not $seen.Add("" + $m.session_id)) { [void]$out.Add("session " + $m.session_id + " is in the lot twice") }
    }
    return @($out)
}

function Write-HordeFleetTableFile {
    # -Rows as the table -Table in -Path: {"v":1,"table":..,"rows":[..]}, ASCII, whole, in one step.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Table, [Parameter(Mandatory = $true)][object[]]$Rows)
    $tmp = $Path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    $doc = [pscustomobject][ordered]@{ v = 1; table = $Table; rows = @($Rows) }
    [System.IO.File]::WriteAllText($tmp, (ConvertTo-HordeFleetAsciiJson -Value $doc), (New-Object System.Text.UTF8Encoding($false)))
    try { Move-HordeFileAtomic -From $tmp -To $Path }
    catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; throw }
}

function Read-HordeFleetTableFile {
    # The rows of table -Table in -Path. THROWS when the file is not that table.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Table)
    $doc = ConvertFrom-HordeJson -Text (Read-HordeSharedText -Path $Path)
    if ($null -eq $doc.PSObject.Properties["v"] -or $doc.v -ne 1 -or "" + $doc.table -cne $Table -or $null -eq $doc.PSObject.Properties["rows"]) { throw ($Path + " is not version 1 of table " + $Table) }
    return @($doc.rows)
}

function Write-HordeFleetLot {
    # Write one lot into -Dir: its members first, then its row. Throws, writing nothing, when they break their
    # schemas: a lot that does not read back is worse than none.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)]$Lot, [Parameter(Mandatory = $true)][object[]]$Members)
    $findings = @(Test-HordeFleetLotFiles -Lot $Lot -Members @($Members) -FolderId (Split-Path -Leaf $Dir))
    if ($findings.Count -gt 0) { throw ("the lot was not written, it breaks its schema: " + ($findings -join "; ")) }
    Write-HordeFleetTableFile -Path (Join-Path $Dir "parking_lot_member.json") -Table $script:HordeFleetTableNames.member -Rows @($Members)
    Write-HordeFleetTableFile -Path (Join-Path $Dir "parking_lot.json") -Table $script:HordeFleetTableNames.lot -Rows @($Lot)
    return (Join-Path $Dir "parking_lot.json")
}

function Sync-HordeFleetLotMembers {
    # Refresh parking_lot_member.json from -Record, for a lot that has its row. A session of the record takes its
    # state from the record; a row the record does not hold is kept as it is, so a member that never entered the
    # record (no working directory to wake it in) does not vanish. A folder with no parking_lot.json is a record
    # from before lots: nothing is written there. A copy that would break its schema is not written: the record it
    # copies has just been written whole and is the authority.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)]$Record)
    $lotPath = Join-Path $Dir "parking_lot.json"
    if (-not (Test-Path -LiteralPath $lotPath -PathType Leaf)) { return }
    $lot = (Read-HordeFleetTableFile -Path $lotPath -Table $script:HordeFleetTableNames.lot)[0]
    $prior = @()
    $path = Join-Path $Dir "parking_lot_member.json"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try { $prior = @(Read-HordeFleetTableFile -Path $path -Table $script:HordeFleetTableNames.member) } catch { $prior = @() }
    }
    $fresh = @(ConvertTo-HordeFleetLotMembers -LotId ("" + $lot.id) -Record $Record -Prior $prior)
    $held = @{}
    foreach ($m in $fresh) { $held["" + $m.session_id] = $true }
    $kept = @(@($prior) | Where-Object { $null -ne $_ -and -not $held.ContainsKey("" + $_.session_id) })
    $rows = @(@($fresh) + @($kept))
    if (@(Test-HordeFleetLotFiles -Lot $lot -Members $rows -FolderId (Split-Path -Leaf $Dir)).Count -gt 0) { return }
    Write-HordeFleetTableFile -Path $path -Table $script:HordeFleetTableNames.member -Rows $rows
}

function Read-HordeFleetLot {
    # The lot -Id (a ULID or the hibernation id of its folder) as an answer: known { lot; members; record;
    # folder } (record is $null for a lot with none; folder is the hibernation id), absent when there is no such
    # lot, unknown when a file of it cannot be read or breaks its schema. A lot with a record takes each member's
    # state from it (the record is the authority); a record with no parking_lot.json is read as a lot (header).
    param([Parameter(Mandatory = $true)][string]$Id, [string]$HordeHome = (Get-HordeHome))
    $hid = $null
    try { $hid = Get-HordeFleetLotFolderId -Id $Id } catch { return (New-HordeUnknown -Reason $_.Exception.Message) }
    $dir = Join-Path (Get-HordeFleetHibernationsDir -HordeHome $HordeHome) $hid
    $lotPath = Join-Path $dir "parking_lot.json"
    $recPath = Join-Path $dir "record.json"
    $hasLot = Test-Path -LiteralPath $lotPath -PathType Leaf
    $hasRec = Test-Path -LiteralPath $recPath -PathType Leaf
    if (-not $hasLot -and -not $hasRec) { return (New-HordeAbsent -Note ("there is no hibernation " + $Id + " (no " + $recPath + ")")) }
    $record = $null
    if ($hasRec) {
        $r = Read-HordeFleetRecord -Id $hid -HordeHome $HordeHome
        if ($r.state -cne "known") { return (New-HordeUnknown -Reason ("the record of lot " + $hid + " cannot be used: " + $r.reason)) }
        $record = $r.value
    }
    $lot = $null; $members = @()
    if (-not $hasLot) {
        $at = [datetime]::ParseExact("" + $record.createdAt, "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
        $kind = "" + $record.selection.kind
        if ($script:HordeFleetLotSelectionKinds -cnotcontains $kind) { $kind = "" }
        $lot = New-HordeFleetLot -At $at -Reason "hibernate (recorded before parking lots)" -Kind $kind -Seed ("legacy|" + $hid)
        return (New-HordeKnown -Value ([pscustomobject]@{ lot = $lot; members = @(ConvertTo-HordeFleetLotMembers -LotId ("" + $lot.id) -Record $record); record = $record; folder = $hid }))
    }
    try {
        $lot = (Read-HordeFleetTableFile -Path $lotPath -Table $script:HordeFleetTableNames.lot)[0]
        $members = @(Read-HordeFleetTableFile -Path (Join-Path $dir "parking_lot_member.json") -Table $script:HordeFleetTableNames.member)
    } catch { return (New-HordeUnknown -Reason ("lot " + $hid + " could not be read") -ErrorRecord $_) }
    $findings = @(Test-HordeFleetLotFiles -Lot $lot -Members $members -FolderId $hid)
    if ($findings.Count -gt 0) { return (New-HordeUnknown -Reason ("lot " + $hid + " breaks its schema: " + ($findings -join "; "))) }
    if ($null -ne $record) {
        $merged = @(ConvertTo-HordeFleetLotMembers -LotId ("" + $lot.id) -Record $record -Prior $members)
        $held = @{}
        foreach ($m in $merged) { $held["" + $m.session_id] = $true }
        $members = @(@($merged) + @(@($members) | Where-Object { -not $held.ContainsKey("" + $_.session_id) }))
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ lot = $lot; members = @($members); record = $record; folder = $hid }))
}

function Write-HordeFleetWake {
    # Record one wake of lot -Lot in -Dir\wakes\<wake id>\: a wake row (which lot, when, by whom) and a
    # wake_member row for each session it was asked to wake, with the outcome and the id it came back under.
    # -Outcomes: { sessionId; outcome } each; -NewIds: session id -> new session id. Returns the wake's id.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][string]$LotId, [Parameter(Mandatory = $true)][datetime]$At,
          [string]$ById = "", [Parameter(Mandatory = $true)][object[]]$Outcomes, $NewIds = @{})
    $wakeRow = [ordered]@{ id = (New-HordeFleetUlid -At $At); lot_id = $LotId; requested_at = (Format-HordeFleetTime -At $At) }
    if ($ById -cmatch $script:HordeFleetSessionPattern) { $wakeRow["requested_by_session_id"] = $ById }
    $rows = New-Object System.Collections.ArrayList
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($o in @($Outcomes)) {
        if (-not $seen.Add("" + $o.sessionId)) { continue }
        $r = [ordered]@{ wake_id = $wakeRow["id"]; session_id = "" + $o.sessionId }
        $n = $NewIds["" + $o.sessionId]
        if ($null -ne $n -and "" + $n -ne "") { $r["new_session_id"] = "" + $n }
        $r["outcome"] = "" + $o.outcome
        [void]$rows.Add([pscustomobject]$r)
    }
    $findings = @(Test-HordeFleetTable -Name "fleet-wake.v1" -Rows @([pscustomobject]$wakeRow)) + @(Test-HordeFleetTable -Name "fleet-wake-member.v1" -Rows @($rows))
    if ($findings.Count -gt 0) { throw ("the wake was not recorded, it breaks its schema: " + ($findings -join "; ")) }
    $wdir = Join-Path (Join-Path $Dir "wakes") $wakeRow["id"]
    [void](New-Item -ItemType Directory -Path $wdir -Force)
    Write-HordeFleetTableFile -Path (Join-Path $wdir "wake_member.json") -Table $script:HordeFleetTableNames.wakeMember -Rows @($rows)
    Write-HordeFleetTableFile -Path (Join-Path $wdir "wake.json") -Table $script:HordeFleetTableNames.wake -Rows @([pscustomobject]$wakeRow)
    return ("" + $wakeRow["id"])
}

function Read-HordeFleetWakes {
    # Every wake recorded for the lot in -Dir, as { wake; members }, oldest first. A wake that cannot be read is left out.
    param([Parameter(Mandatory = $true)][string]$Dir)
    $out = New-Object System.Collections.ArrayList
    $root = Join-Path $Dir "wakes"
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
    foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name)) {
        try {
            $w = (Read-HordeFleetTableFile -Path (Join-Path $d.FullName "wake.json") -Table $script:HordeFleetTableNames.wake)[0]
            $m = @(Read-HordeFleetTableFile -Path (Join-Path $d.FullName "wake_member.json") -Table $script:HordeFleetTableNames.wakeMember)
            [void]$out.Add([pscustomobject]@{ wake = $w; members = $m })
        } catch { continue }
    }
    return @($out)
}
