# channels/fleet - the founder's phone sets an Orc's tier, hibernates tier 2 and wakes a hibernation, and
# is shown the fleet's sleep state, end to end encrypted (T-0216, the sleeping-sessions lane; the founder's
# brief of 2026-10-16: "set an Orc's tier, press Hibernate Tier 2 Orcs, and Wake").
#
# THE CONTRACT IS test/fixtures/fleet/ (README.md and four files), agreed with the phone side before
# either was built. This file reads those bodies and writes that snapshot, and nothing else:
#   in   kind tier       {v, setId, machine, orc, tier 1|2, version}
#   in   kind hibernate  {v, setId, machine, tier 2, version}
#   in   kind wake       {v, setId, machine, hibernationId}
#   out  kind snapshot   {v, version, tiers, never, running, hibernations, lastResult}, replaced whole
# A body is read STRICTLY: a member it does not list, a member missing, a member twice and a value outside
# its shape are refused, never guessed. The snapshot this channel writes is read back by the same rule
# (Test-HordeFleetChannelSnapshot) before it is sent, so the channel cannot emit a shape the phone side
# would refuse. That check also refuses a state from the OTHER state list: the README gives a running
# hibernation's sessions one list (asked, parked, exited, still-awake, failed) and a finished one's
# another (asleep, woken, still-awake, failed). They share still-awake and failed only, so a check
# against their union is wrong and would let "exited" into a finished hibernation.
#
# WHO MAY ASK. The founder's passkeys (the channel's sender is "founder"), and for each of the three kinds
# either a fresh passkey (proof webauthn) or his unlocked session (proof session) - M's decision of
# 2026-10-16, because Wake undoes Hibernate and the phone asks on-page confirmation for it. The proof is
# the Item's own, read as channels/decisions reads it (the needsPasskey rule): an item that says nothing
# of its proof, or says es256 (a machine), is refused. A body is for ONE machine: machine must be this
# machine's key id.
#
# WHAT EACH KIND DOES, every outside effect through a seam (below) that the suite stubs:
#   tier       Set-HordeOrcTier (orcs/Registry.ps1), the registry's own write, with the version the phone
#              drew the request from. A registry that has moved on answers stale, and that is a retry.
#              An Orc in the never list is refused.
#   hibernate  starts `horde fleet hibernate -Tier 2` in the background and returns: Accept must be fast,
#              and a hibernation takes up to fifteen minutes. One at a time: while one runs (its lock, or
#              a process this channel started and that still runs) the answer is retry.
#   wake       starts `horde fleet wake <id>` in the background the same way.
# EVERY ANSWER LANDS IN lastResult of the next snapshot, with the request's setId.
#
# RETRY IS THE PHONE'S WORD, NOT THE PORT'S. In the snapshot, outcome retry means "not done now; read the
# snapshot and ask again". At the port (channels/Port.ps1) retry means "hand me the same record again
# later". Handing a stale tier request again would never end (the registry does not go back), and handing a
# hibernate that found one running again would start another the moment the first ended, which the founder
# did not ask for. So a contract retry is finished at the port as "refused" (its reason says retry), and
# the item the Accept returns names the contract's word in `answer`. Only a failure to WRITE (the registry
# or this channel's state cannot be written now) is a port retry, because nothing was done.
#
# IDEMPOTENT PER setId. The phone keeps the setId of a request on every retry of it, so a request carried
# twice is acted on once. A setId whose answer was done or refused is remembered (the last 64) and answered
# again from memory, nothing acted on. A setId answered retry is NOT remembered: the phone asks again with
# the same setId after re-reading the snapshot, and that is a new attempt.
#
# THE SNAPSHOT is built each look from the Orc registry (tiers, version), the never list, the running
# hibernation and the newest ten records, and is sent only when it changed (or a phone key trusted since
# has none). A look is at most every lookMs unless a request was just answered, so the registry and the
# records are not read once a second. THE NEVER LIST names the Orcs that are never put to sleep as Orcs:
# the Thrall's lane (the master, M) and the fleet analyst service. Sessions that hibernate leaves
# running for a reason of the moment (the founder typed into them, an open question waits on them, a
# transcript could not be read) are not "never": that Orc is in tier 2 and is left running this time.
#
# THE STATE is <HORDE_HOME>\relay\fleet\state.json, written whole by rename (core/FileAtomic.ps1): the hash
# of the last snapshot sent, the phone keys it went to, the envelopes recorded and not yet put, the last
# answer, the setIds answered, and the background processes this channel started.
#
# SEAMS (a table kept in the run context, $Context.state["fleet.seams"], that a suite fills; the defaults
# are the real ones, below): Registry, Never, SetTier, Records, Busy, Start, ProcessStart.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest,
# so a member that may be missing is read through Get-HordeFleetChannelMember.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "fleet\Hibernate.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "fleet\StatusPanel.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "orcs\Registry.ps1")

$script:HordeFleetChannelFolder = $PSScriptRoot
$script:HordeFleetChannelSettings = New-HordeModuleSettings -Module "relay-fleet" -Settings @(
    # The snapshot is replaced whole, so the phone needs only the newest; a few stay for a phone that reads late.
    @{ name = "keepEnvelopes"; kind = "whole"; default = 5; min = 1; max = 100; what = "How many of this machine's newest fleet envelopes stay in the phone's mailbox." },
    @{ name = "sessionsMost"; kind = "whole"; default = 12; min = 1; max = 200; what = "How many sessions of one hibernation the snapshot lists; the rest are counted in more." },
    # 5 s: a request just answered is looked at at once; this bounds the idle reads of the registry and the records.
    @{ name = "lookMs"; kind = "whole"; default = 5000; min = 0; max = 600000; what = "How long the channel may go without a full look while no request was answered, in milliseconds." }
)
$script:HordeFleetChannelMembers = @{
    tier      = @("machine", "orc", "setId", "tier", "v", "version")
    hibernate = @("machine", "setId", "tier", "v", "version")
    wake      = @("hibernationId", "machine", "setId", "v")
}
$script:HordeFleetChannelMostAnswered = 64
$script:HordeFleetChannelMostHibernations = 10
$script:HordeFleetChannelSnapshotMembers = @("v", "version", "tiers", "never", "running", "hibernations", "lastResult")
$script:HordeFleetChannelRunningStates = @("asked", "parked", "exited", "still-awake", "failed")
$script:HordeFleetChannelFinishedStates = @("asleep", "woken", "still-awake", "failed")
$script:HordeFleetChannelPhases = @("asking", "parking", "done")
$script:HordeFleetChannelOutcomes = @("done", "refused", "retry")
$script:HordeFleetChannelIdPattern = '\A[0-9]{8}-[0-9]{6}\z'
$script:HordeFleetChannelTimePattern = '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z'
$script:HordeFleetChannelOrcPattern = '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z'
$script:HordeFleetChannelAnalystOrc = "analyst-service"

function Get-HordeFleetChannelSettingsDeclaration { return $script:HordeFleetChannelSettings }

function Get-HordeFleetChannelMember {
    # A member of a parsed object that may be left out, or $null - safe under strict mode.
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Get-HordeFleetChannelHome {
    param($Context)
    if ("$($Context.hordeHome)" -ne "") { return $Context.hordeHome }
    return (Get-HordeHome)
}

function Get-HordeFleetChannelStatePath {
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return [System.IO.Path]::Combine($HordeHome, "relay", "fleet", "state.json")
}

function ConvertTo-HordeFleetChannelText {
    # -Text as printable ASCII of at most -Most characters: what goes in a reason, so the state file and the
    # snapshot are ASCII whatever a path or a registry reason holds (CONTRIBUTING 13).
    param([AllowEmptyString()][string]$Text, [int]$Most = 300)
    $t = [regex]::Replace("" + $Text, '[^\x20-\x7E]', "?")
    if ($t.Length -gt $Most) { $t = $t.Substring(0, $Most) }
    return $t
}

function ConvertTo-HordeFleetChannelJsonString {
    # A JSON string of printable ASCII text: only the backslash and the double quote need escaping.
    param([AllowEmptyString()][string]$Text)
    return ('"' + ((ConvertTo-HordeFleetChannelText -Text $Text -Most 1000).Replace('\', '\\').Replace('"', '\"')) + '"')
}

function Test-HordeFleetChannelWhole {
    param($Value)
    return (($Value -is [int] -or $Value -is [long]) -and $Value -ge 0)
}

function Get-HordeFleetChannelSeam {
    # The seam -Name: the suite's, when it filled $Context.state["fleet.seams"], else the real one.
    param($Context, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -ne $Context -and $null -ne $Context.state -and $Context.state.ContainsKey("fleet.seams")) {
        $t = $Context.state["fleet.seams"]
        if ($t.ContainsKey($Name)) { return $t[$Name] }
    }
    return $script:HordeFleetChannelDefaultSeams[$Name]
}

# --- the durable state ---

function New-HordeFleetChannelState {
    return [pscustomobject]@{ hash = ""; phones = @(); pending = @(); lastResult = $null; answered = @(); children = @() }
}

function Test-HordeFleetChannelResultShape {
    # Is -R a { setId; outcome; reason } the state or the snapshot may hold?
    param($R)
    if ($null -eq $R -or $R -isnot [System.Management.Automation.PSCustomObject]) { return $false }
    $names = @($R.PSObject.Properties | ForEach-Object { $_.Name })
    if (($names -join ",") -cne "setId,outcome,reason") { return $false }
    return ($R.setId -is [string] -and $R.setId -cmatch '\A[0-9a-f]{32}\z' -and $R.outcome -is [string] -and $script:HordeFleetChannelOutcomes -ccontains $R.outcome -and $R.reason -is [string] -and $R.reason.Length -le 600)
}

function Read-HordeFleetChannelState {
    # known (the empty state when there is no file), or unknown when the file does not hold together - the
    # channel then stops, in words, and is never started over by itself: it would answer a setId again.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $path = Get-HordeFleetChannelStatePath -HordeHome $HordeHome
    if (-not [System.IO.File]::Exists($path)) { return (New-HordeKnown -Value (New-HordeFleetChannelState)) }
    $why = "the fleet channel state " + $path + " does not hold together"
    $s = $null
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        foreach ($b in $bytes) { if ($b -gt 126) { return (New-HordeUnknown -Reason ($why + ": it is not ASCII")) } }
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { return (New-HordeUnknown -Reason ($why + ": a member is there twice")) }
        $s = ConvertFrom-Json -InputObject $text
    } catch { return (New-HordeUnknown -Reason ($why + ": " + $_.Exception.Message)) }
    if ($s -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ($why + ": it is not an object")) }
    if ((@($s.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object { $_ } -CaseSensitive) -join ",") -cne "answered,children,hash,lastResult,pending,phones,v" -or $s.v -ne 1) { return (New-HordeUnknown -Reason ($why + ": its members are not this code's")) }
    if ($s.hash -isnot [string] -or $s.hash -cnotmatch '\A([0-9a-f]{64})?\z') { return (New-HordeUnknown -Reason ($why + ": its hash is not a hash")) }
    foreach ($k in @($s.phones)) { if ($k -isnot [string] -or $k -cnotmatch '\A[0-9a-f]{32}\z') { return (New-HordeUnknown -Reason ($why + ": a phone key is not a key id")) } }
    foreach ($k in @($s.pending)) { if ($k -isnot [string] -or $k.Length -gt 160) { return (New-HordeUnknown -Reason ($why + ": a pending envelope is not a replay key")) } }
    if ($null -ne $s.lastResult -and -not (Test-HordeFleetChannelResultShape $s.lastResult)) { return (New-HordeUnknown -Reason ($why + ": its last result is not one")) }
    foreach ($a in @($s.answered)) { if (-not (Test-HordeFleetChannelResultShape $a) -or @("done", "refused") -cnotcontains $a.outcome) { return (New-HordeUnknown -Reason ($why + ": an answered request is not one")) } }
    foreach ($c in @($s.children)) {
        $n = @($c.PSObject.Properties | ForEach-Object { $_.Name }) -join ","
        if ($n -cne "kind,id,pid,start" -or @("hibernate", "wake") -cnotcontains $c.kind -or $c.id -isnot [string] -or $c.id -cnotmatch '\A([0-9]{8}-[0-9]{6})?\z' -or -not (Test-HordeFleetChannelWhole $c.pid) -or $c.start -isnot [string] -or $c.start -cnotmatch '\A[0-9]{0,19}\z') { return (New-HordeUnknown -Reason ($why + ": a child process is not one")) }
    }
    $last = $null
    if ($null -ne $s.lastResult) { $last = [pscustomobject]@{ setId = $s.lastResult.setId; outcome = $s.lastResult.outcome; reason = $s.lastResult.reason } }
    return (New-HordeKnown -Value ([pscustomobject]@{
        hash = $s.hash; phones = @($s.phones); pending = @($s.pending); lastResult = $last
        answered = @(@($s.answered) | ForEach-Object { [pscustomobject]@{ setId = $_.setId; outcome = $_.outcome; reason = $_.reason } })
        children = @(@($s.children) | ForEach-Object { [pscustomobject]@{ kind = $_.kind; id = $_.id; pid = [long]$_.pid; start = $_.start } }) }))
}

function ConvertTo-HordeFleetChannelResultJson {
    param($R)
    if ($null -eq $R) { return "null" }
    return ('{"setId":"' + $R.setId + '","outcome":"' + $R.outcome + '","reason":' + (ConvertTo-HordeFleetChannelJsonString $R.reason) + '}')
}

function ConvertTo-HordeFleetChannelStateText {
    param([Parameter(Mandatory = $true)]$State)
    $list = { param($items) (@($items) | ForEach-Object { ConvertTo-HordeFleetChannelJsonString "$_" }) -join "," }
    $answered = (@($State.answered) | ForEach-Object { ConvertTo-HordeFleetChannelResultJson $_ }) -join ","
    $children = (@($State.children) | ForEach-Object { '{"kind":"' + $_.kind + '","id":"' + $_.id + '","pid":' + [long]$_.pid + ',"start":"' + $_.start + '"}' }) -join ","
    return ('{"v":1,"hash":"' + $State.hash + '","phones":[' + (& $list $State.phones) + '],"pending":[' + (& $list $State.pending) + '],"lastResult":' + (ConvertTo-HordeFleetChannelResultJson $State.lastResult) + ',"answered":[' + $answered + '],"children":[' + $children + ']}')
}

function Write-HordeFleetChannelState {
    # The state as the whole of its file, ASCII, replaced in one rename. Throws.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)]$State)
    $path = Get-HordeFleetChannelStatePath -HordeHome $HordeHome
    $dir = [System.IO.Path]::GetDirectoryName($path)
    [void][System.IO.Directory]::CreateDirectory($dir)
    $tmp = [System.IO.Path]::Combine($dir, ("state.json." + [guid]::NewGuid().ToString("N") + ".tmp"))
    try { [System.IO.File]::WriteAllText($tmp, (ConvertTo-HordeFleetChannelStateText -State $State), [System.Text.Encoding]::ASCII); Move-HordeFileAtomic -From $tmp -To $path }
    catch { try { [System.IO.File]::Delete($tmp) } catch { }; throw }
}

function Get-HordeFleetChannelMine {
    # This channel's memory in the run context (created on first use): the durable state as loaded, whether a
    # request was answered since the last look, and the lines already said.
    param($Context)
    if (-not $Context.state.ContainsKey("fleet")) { $Context.state["fleet"] = @{ loaded = $false; durable = $null; said = @{}; dirty = $false; lastLook = [datetime]::MinValue } }
    return $Context.state["fleet"]
}

function Get-HordeFleetChannelDurable {
    # known the durable state (loaded once, kept in memory), or the unknown that stops the channel.
    param($Context, $Mine)
    if (-not $Mine.loaded) {
        $st = Read-HordeFleetChannelState -HordeHome (Get-HordeFleetChannelHome $Context)
        if ($st.state -cne "known") { return $st }
        $Mine.durable = $st.value; $Mine.loaded = $true
    }
    return (New-HordeKnown -Value $Mine.durable)
}

# --- the snapshot: built, and read back by the contract's own rules ---

function Get-HordeFleetChannelSessionState {
    # One session state of a RECORD as the snapshot says it, in the list of a running or a finished
    # hibernation, or $null when the record's state has no word there. Two lists, never their union.
    param([string]$State, [bool]$Running)
    if ($Running) {
        switch ($State) {
            "recorded" { return "asked" }
            "asked" { return "asked" }
            "parked" { return "parked" }
            "exited" { return "exited" }
            "still-awake" { return "still-awake" }
            "failed" { return "failed" }
        }
        return $null
    }
    # A finished one. waking is asleep: the wake has started its pane and not yet seen the session run, and
    # the wake watcher counts it asleep too (fleet/Asleep.ps1), so the phone can press Wake again and be
    # told the truth. recorded, asked and parked in a hibernation that is no longer running never went to
    # sleep (the run ended before it exited them), so they are awake.
    switch ($State) {
        "exited" { return "asleep" }
        "waking" { return "asleep" }
        "woken" { return "woken" }
        "still-awake" { return "still-awake" }
        "failed" { return "failed" }
        "recorded" { return "still-awake" }
        "asked" { return "still-awake" }
        "parked" { return "still-awake" }
    }
    return $null
}

function ConvertTo-HordeFleetChannelSessionsJson {
    # { sessions (JSON array text); more } of a record's sessions, at most -Most listed.
    param($Record, [bool]$Running, [int]$Most)
    $all = @(Get-HordeFleetChannelMember $Record "sessions")
    $items = New-Object System.Collections.ArrayList
    foreach ($s in $all) {
        if ($items.Count -ge $Most) { break }
        $state = Get-HordeFleetChannelSessionState -State ("" + (Get-HordeFleetChannelMember $s "state")) -Running $Running
        if ($null -eq $state) { $state = "failed" }
        $label = "" + (Get-HordeFleetChannelMember $s "label")
        if ($label -eq "") { $label = ("" + (Get-HordeFleetChannelMember $s "sessionId")); if ($label.Length -gt 8) { $label = $label.Substring(0, 8) } }
        $role = $(if ("" + (Get-HordeFleetChannelMember $s "role") -ceq "orc") { "orc" } else { "warg" })
        [void]$items.Add('{"label":' + (ConvertTo-HordeFleetChannelJsonString $label) + ',"role":"' + $role + '","state":"' + $state + '"}')
    }
    return [pscustomobject]@{ sessions = ('[' + ($items -join ",") + ']'); more = [int]($all.Count - $items.Count) }
}

function Build-HordeFleetChannelSnapshot {
    # The snapshot text (the README's fleet-snapshot.json) from:
    #   -Registry   { version; orcs: { id; tier } }     -Never  list of { orc; reason }
    #   -Records    hibernation records, newest first (each with a phase)
    #   -Busy       is a hibernation running now?       -LastResult  { setId; outcome; reason } or $null
    # The running hibernation is the newest record in phase asking or parking WHILE one runs; every other
    # record with a phase is finished (a run that died leaves its record in a phase and no lock). A record
    # with no phase was made by `fleet record` and is no hibernation. A hibernation is in running or in
    # hibernations, never both.
    param($Registry, [object[]]$Never = @(), [object[]]$Records = @(), [bool]$Busy = $false, $LastResult = $null, [int]$SessionsMost = 12)
    $neverIds = @($Never | ForEach-Object { "" + $_.orc })
    $tiers = New-Object System.Collections.ArrayList
    foreach ($o in @($Registry.orcs)) {
        $id = "" + $o.id
        if ($neverIds -ccontains $id) { continue }
        $t = Get-HordeFleetChannelMember $o "tier"
        $tier = $(if ($null -ne $t -and "" + $t -ceq "2") { 2 } else { 1 })
        [void]$tiers.Add((ConvertTo-HordeFleetChannelJsonString $id) + ':' + $tier)
    }
    $never = @($Never | ForEach-Object { '{"orc":' + (ConvertTo-HordeFleetChannelJsonString ("" + $_.orc)) + ',"reason":' + (ConvertTo-HordeFleetChannelJsonString ("" + $_.reason)) + '}' })
    $withPhase = @(@($Records) | Where-Object { @("asking", "parking", "done") -ccontains ("" + (Get-HordeFleetChannelMember $_ "phase")) })
    $runningRecord = $null
    if ($Busy) { $runningRecord = @($withPhase | Where-Object { @("asking", "parking") -ccontains ("" + $_.phase) }) | Select-Object -First 1 }
    $running = "null"
    if ($null -ne $runningRecord) {
        $s = ConvertTo-HordeFleetChannelSessionsJson -Record $runningRecord -Running $true -Most $SessionsMost
        $running = '{"id":"' + $runningRecord.id + '","startedAt":"' + $runningRecord.createdAt + '","phase":"' + $runningRecord.phase + '","sessions":' + $s.sessions + ',"more":' + $s.more + '}'
    }
    $done = New-Object System.Collections.ArrayList
    foreach ($r in $withPhase) {
        if ($done.Count -ge $script:HordeFleetChannelMostHibernations) { break }
        if ($null -ne $runningRecord -and "" + $r.id -ceq "" + $runningRecord.id) { continue }
        $s = ConvertTo-HordeFleetChannelSessionsJson -Record $r -Running $false -Most $SessionsMost
        [void]$done.Add('{"id":"' + $r.id + '","at":"' + $r.createdAt + '","sessions":' + $s.sessions + ',"more":' + $s.more + '}')
    }
    return ('{"v":1,"version":' + [long]$Registry.version + ',"tiers":{' + ($tiers -join ",") + '},"never":[' + ($never -join ",") + '],"running":' + $running + ',"hibernations":[' + ($done -join ",") + '],"lastResult":' + (ConvertTo-HordeFleetChannelResultJson $LastResult) + '}')
}

function Test-HordeFleetChannelSnapshot {
    # The README's snapshot rules, as a reader: { ok; reason }. A member it does not list, a member missing,
    # a member twice, a value outside its shape, and a state from the other list are each refused.
    param([AllowEmptyString()][string]$Text)
    $no = { param($w) return [pscustomobject]@{ ok = $false; reason = $w } }
    if (@(Find-HordeJsonDuplicateKey -Text $Text).Count -gt 0) { return (& $no "a member is there twice") }
    $s = $null
    try { $s = ConvertFrom-Json -InputObject $Text } catch { return (& $no "it is not JSON") }
    $exact = {
        param($o, [string[]]$Want, [string]$What)
        if ($o -isnot [System.Management.Automation.PSCustomObject]) { return ($What + " is not an object") }
        $have = @($o.PSObject.Properties | ForEach-Object { $_.Name })
        if (($have -join ",") -cne ($Want -join ",")) { return ($What + " has the members " + ($have -join ", ") + ", not " + ($Want -join ", ")) }
        return ""
    }
    $w = & $exact $s $script:HordeFleetChannelSnapshotMembers "the snapshot"
    if ($w -ne "") { return (& $no $w) }
    if (-not ($s.v -is [int] -or $s.v -is [long]) -or $s.v -ne 1) { return (& $no "v is not 1") }
    if (-not (Test-HordeFleetChannelWhole $s.version)) { return (& $no "version is not a whole number") }
    if ($s.tiers -isnot [System.Management.Automation.PSCustomObject]) { return (& $no "tiers is not an object") }
    $tierIds = @($s.tiers.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($p in @($s.tiers.PSObject.Properties)) {
        if ($p.Name -cnotmatch $script:HordeFleetChannelOrcPattern) { return (& $no ("tiers names '" + $p.Name + "', which is not an Orc id")) }
        if (-not ($p.Value -is [int] -or $p.Value -is [long]) -or @(1, 2) -notcontains $p.Value) { return (& $no ("the tier of " + $p.Name + " is not 1 or 2")) }
    }
    if ($s.never -isnot [System.Array]) { return (& $no "never is not a list") }
    foreach ($n in @($s.never)) {
        $w = & $exact $n @("orc", "reason") "a never entry"
        if ($w -ne "") { return (& $no $w) }
        if ($n.orc -isnot [string] -or $n.orc -cnotmatch $script:HordeFleetChannelOrcPattern -or $n.reason -isnot [string] -or $n.reason -eq "") { return (& $no "a never entry does not name an Orc and say why") }
        if ($tierIds -ccontains $n.orc) { return (& $no ("" + $n.orc + " is in both never and tiers")) }
    }
    $checkSessions = {
        param($o, [string[]]$States, [string]$What)
        if ($o.sessions -isnot [System.Array]) { return ($What + " sessions is not a list") }
        if (-not (Test-HordeFleetChannelWhole $o.more)) { return ($What + " more is not a whole number") }
        foreach ($x in @($o.sessions)) {
            $w2 = & $exact $x @("label", "role", "state") ($What + " session")
            if ($w2 -ne "") { return $w2 }
            if ($x.label -isnot [string] -or $x.label -eq "") { return ($What + " has a session with no label") }
            if ($x.role -isnot [string] -or @("orc", "warg") -cnotcontains $x.role) { return ($What + " has a session whose role is not orc or warg") }
            if ($x.state -isnot [string] -or $States -cnotcontains $x.state) { return ($What + " has a session in the state '" + $x.state + "', which is not one of " + ($States -join ", ") + " for it") }
        }
        return ""
    }
    $runningId = ""
    if ($null -ne $s.running) {
        $w = & $exact $s.running @("id", "startedAt", "phase", "sessions", "more") "running"
        if ($w -ne "") { return (& $no $w) }
        if ($s.running.id -isnot [string] -or $s.running.id -cnotmatch $script:HordeFleetChannelIdPattern) { return (& $no "running.id is not a hibernation id") }
        if ($s.running.startedAt -isnot [string] -or $s.running.startedAt -cnotmatch $script:HordeFleetChannelTimePattern) { return (& $no "running.startedAt is not a UTC time") }
        if ($s.running.phase -isnot [string] -or $script:HordeFleetChannelPhases -cnotcontains $s.running.phase) { return (& $no "running.phase is not asking, parking or done") }
        $w = & $checkSessions $s.running $script:HordeFleetChannelRunningStates "running"
        if ($w -ne "") { return (& $no $w) }
        $runningId = $s.running.id
    }
    if ($s.hibernations -isnot [System.Array]) { return (& $no "hibernations is not a list") }
    if (@($s.hibernations).Count -gt $script:HordeFleetChannelMostHibernations) { return (& $no ("hibernations holds more than " + $script:HordeFleetChannelMostHibernations)) }
    $seen = @{}; $previous = ""
    foreach ($h in @($s.hibernations)) {
        $w = & $exact $h @("id", "at", "sessions", "more") "a hibernation"
        if ($w -ne "") { return (& $no $w) }
        if ($h.id -isnot [string] -or $h.id -cnotmatch $script:HordeFleetChannelIdPattern) { return (& $no "a hibernation's id is not a hibernation id") }
        if ($h.at -isnot [string] -or $h.at -cnotmatch $script:HordeFleetChannelTimePattern) { return (& $no "a hibernation's at is not a UTC time") }
        if ($seen.ContainsKey($h.id)) { return (& $no ("hibernation " + $h.id + " is there twice")) }
        if ($h.id -ceq $runningId) { return (& $no ("hibernation " + $h.id + " is both running and finished")) }
        if ($previous -ne "" -and [string]::CompareOrdinal($h.id, $previous) -ge 0) { return (& $no "hibernations are not newest first") }
        $seen[$h.id] = $true; $previous = $h.id
        $w = & $checkSessions $h $script:HordeFleetChannelFinishedStates ("hibernation " + $h.id)
        if ($w -ne "") { return (& $no $w) }
    }
    if ($null -ne $s.lastResult -and -not (Test-HordeFleetChannelResultShape $s.lastResult)) { return (& $no "lastResult is not null or a { setId, outcome, reason } with a 32 hex setId and an outcome of done, refused or retry") }
    if ($null -ne $s.lastResult -and $s.lastResult.reason -eq "") { return (& $no "lastResult says no reason") }
    return [pscustomobject]@{ ok = $true; reason = "" }
}

# --- the real seams ---

function Get-HordeFleetChannelRegistryReal {
    # F's reader (orcs/Registry.ps1): known { version; orcs: each { id; tier } } - tier $null until set.
    # The registry folded, the lanes read, the list as the Dash shows it, without the Dash's questions and
    # progress (which cost seconds): the snapshot needs tiers and the version only.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $paths = Get-HordeOrcPaths -HordeHome $HordeHome
    if (-not $paths.ok) { return (New-HordeUnknown -Reason ("" + $paths.reason)) }
    $state = Read-HordeOrcRegistry -Root $paths.registry
    if ($state.state -cne "ok") { return (New-HordeUnknown -Reason ("the Orc registry could not be read: " + $state.reason)) }
    $lanes = Read-HordeOrcLanes -Folder $paths.lanes -NotOrcs $paths.notOrcs -Most $paths.lanesRead
    if (-not $lanes.ok) { return (New-HordeUnknown -Reason ("" + $lanes.reason)) }
    $rows = @(Get-HordeOrcView -State $state -Lanes $lanes | ForEach-Object { [pscustomobject]@{ id = "" + $_.id; tier = (Get-HordeFleetChannelMember $_ "tier") } })
    return (New-HordeKnown -Value ([pscustomobject]@{ version = [long]$state.version; orcs = $rows }))
}

function Get-HordeFleetChannelNeverReal {
    # The Orcs that are never put to sleep, each { orc; reason }: the Thrall's lane (the status record whose
    # letter is M) and the fleet analyst service. The analyst is a service and has no lane folder, so it is
    # always named.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $out = New-Object System.Collections.ArrayList
    # The lanes folder is the registry's own (the cards channel's setting), so the Thrall's lane named here is
    # the one the registry passed over.
    $paths = Get-HordeOrcPaths -HordeHome $HordeHome
    $status = $(if ($paths.ok) { Get-HordeFleetStatus -Folder $paths.lanes -HordeHome $HordeHome } else { Get-HordeFleetStatus -HordeHome $HordeHome })
    if ("" + $status.state -ceq "read") {
        foreach ($o in @($status.orcs)) {
            if ($o.written -and "" + $o.orc -ceq "M") { [void]$out.Add([pscustomobject]@{ orc = ("" + $o.folder); reason = "the master coordinates the fleet and is never put to sleep" }) }
        }
    }
    [void]$out.Add([pscustomobject]@{ orc = $script:HordeFleetChannelAnalystOrc; reason = "the fleet analyst runs as a service and is never parked" })
    return (New-HordeKnown -Value @($out.ToArray()))
}

function Set-HordeFleetChannelTierReal {
    # The registry's own write (Set-HordeOrcTier), as the phone's: { outcome; reason; version }.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][int]$Tier, [Parameter(Mandatory = $true)][long]$Version)
    return (Set-HordeOrcTier -Id $Id -Tier $Tier -Version $Version -HordeHome $HordeHome -Actor "phone" -By "founder")
}

function Get-HordeFleetChannelRecordsReal {
    # The hibernation records, newest first, known { records; lines }: those that read and hold a phase, at
    # most -Most; one that cannot be read is said and passed over, not a reason to send no snapshot.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [int]$Most = 11)
    $dir = Get-HordeFleetHibernationsDir -HordeHome $HordeHome
    $lines = New-Object System.Collections.ArrayList
    $records = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return (New-HordeKnown -Value ([pscustomobject]@{ records = @(); lines = @() })) }
    $ids = @()
    try { $ids = @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction Stop | ForEach-Object { $_.Name } | Where-Object { $_ -cmatch $script:HordeFleetIdPattern } | Sort-Object -Descending) }
    catch { return (New-HordeUnknown -Reason ("the hibernations folder could not be listed: " + $_.Exception.Message)) }
    $looked = 0
    foreach ($id in $ids) {
        if ($records.Count -ge $Most -or $looked -ge 60) { break }
        $looked++
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $dir $id) "record.json") -PathType Leaf)) { continue }
        $r = Read-HordeFleetRecord -Id $id -HordeHome $HordeHome
        if ($r.state -cne "known") { [void]$lines.Add("hibernation " + $id + " is not shown: " + $r.reason); continue }
        if ("" + (Get-HordeFleetChannelMember $r.value "phase") -ceq "") { continue }
        [void]$records.Add($r.value)
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ records = @($records.ToArray()); lines = @($lines.ToArray()) }))
}

function Test-HordeFleetChannelChildAlive {
    # Is the process this channel started still the one that runs: its pid, with the start time it had.
    param($Child, $Context)
    $look = Get-HordeFleetChannelSeam -Context $Context -Name "ProcessStart"
    $now = "" + (& $look ([long]$Child.pid))
    if ($now -eq "") { return $false }
    if ($now -ceq "?" -or "" + $Child.start -eq "") { return $true }
    $a = [long]0; $b = [long]0
    if (-not [long]::TryParse($now, [ref]$a) -or -not [long]::TryParse("" + $Child.start, [ref]$b)) { return $true }
    return ([Math]::Abs($a - $b) -le 10000000)
}

function Test-HordeFleetChannelLockHeld {
    # Is the lock file at -Path held by a live owner? No file, or an owner gone (or a pid now another
    # process's), is not; a lock that cannot be read or names no owner IS held - an owner nobody can rule
    # out still holds it (fleet/Wake.ps1, Get-HordeFleetLockOwner). -Look is the ProcessStart seam.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][scriptblock]$Look)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $text = ""
    try { $text = Read-HordeSharedText -Path $Path } catch { return $true }
    $o = Get-HordeFleetLockOwner -Text $text -ProcessStart $Look
    return (-not $o.stale)
}

function Get-HordeFleetChannelBusyReal {
    # What runs now: known { hibernating; waking: ids }. A hibernation runs when its lock is held by a live
    # owner (fleet/Hibernate.ps1 takes it; a stale one is not a run), or when a process this channel started
    # for it still runs - the first seconds of a run, before it has taken the lock. A wake likewise: a
    # waking.lock of a live owner in a record's folder, or a process this channel started for that id.
    param($Context, [Parameter(Mandatory = $true)][string]$HordeHome, [object[]]$Children = @())
    $look = Get-HordeFleetChannelSeam -Context $Context -Name "ProcessStart"
    $dir = Get-HordeFleetHibernationsDir -HordeHome $HordeHome
    $hibernating = (Test-HordeFleetChannelLockHeld -Path (Join-Path $dir $script:HordeFleetHibernateLockName) -Look $look)
    $waking = New-Object System.Collections.ArrayList
    foreach ($c in @($Children)) {
        if (-not (Test-HordeFleetChannelChildAlive -Child $c -Context $Context)) { continue }
        if ("" + $c.kind -ceq "hibernate") { $hibernating = $true } else { [void]$waking.Add("" + $c.id) }
    }
    if (Test-Path -LiteralPath $dir -PathType Container) {
        foreach ($d in @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -cmatch $script:HordeFleetIdPattern })) {
            if ((Test-HordeFleetChannelLockHeld -Path (Join-Path $d.FullName "waking.lock") -Look $look) -and $waking -cnotcontains $d.Name) { [void]$waking.Add($d.Name) }
        }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ hibernating = [bool]$hibernating; waking = @($waking.ToArray()) }))
}

function Start-HordeFleetChannelCommand {
    # THE REAL SPAWN: `horde fleet <verb> <args>` in a hidden, detached process of its own, which this
    # channel does not wait for. Known { pid; start } - start the process's start time as ticks text, so a
    # reused pid is not mistaken for it later; unknown when it could not be started. -Words are checked
    # here to be plain words, so nothing a phone sent reaches a command line unchecked.
    param([Parameter(Mandatory = $true)][string[]]$Words)
    foreach ($w in $Words) { if ($w -cnotmatch '\A[A-Za-z0-9-]{1,32}\z') { return (New-HordeUnknown -Reason ("'" + $w + "' is not a plain word for a command line")) } }
    $horde = [System.IO.Path]::Combine((Split-Path -Parent (Split-Path -Parent $PSScriptRoot)), "horde.ps1")
    if (-not [System.IO.File]::Exists($horde)) { return (New-HordeUnknown -Reason ("horde.ps1 is not at " + $horde)) }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + $horde + "`" fleet " + ($Words -join " ")
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return (New-HordeUnknown -Reason ("the command could not be started: " + $_.Exception.Message)) }
    try {
        $start = ""
        try { $start = "" + $p.StartTime.ToFileTimeUtc() } catch { $start = "" }
        return (New-HordeKnown -Value ([pscustomobject]@{ pid = [long]$p.Id; start = $start }))
    } finally { $p.Dispose() }
}

$script:HordeFleetChannelDefaultSeams = @{
    Registry     = { param($HordeHome) Get-HordeFleetChannelRegistryReal -HordeHome $HordeHome }
    Never        = { param($HordeHome) Get-HordeFleetChannelNeverReal -HordeHome $HordeHome }
    SetTier      = { param($HordeHome, $Id, $Tier, $Version) Set-HordeFleetChannelTierReal -HordeHome $HordeHome -Id $Id -Tier $Tier -Version $Version }
    Records      = { param($HordeHome) Get-HordeFleetChannelRecordsReal -HordeHome $HordeHome }
    Busy         = { param($Context, $HordeHome, $Children) Get-HordeFleetChannelBusyReal -Context $Context -HordeHome $HordeHome -Children $Children }
    Start        = { param($Words) Start-HordeFleetChannelCommand -Words $Words }
    ProcessStart = { param($ProcessId) Get-HordeFleetProcessStart -ProcessId $ProcessId }
}

# --- (3) in ---

function Read-HordeFleetChannelRequest {
    # A request body read strictly for -Kind: { ok; reason; setId; value }. setId is filled whenever the body
    # is an object with a good setId, even when something else is wrong, so the refusal can be answered to
    # the request it is for. Never throws for the body.
    param([AllowEmptyCollection()][byte[]]$Body, [Parameter(Mandatory = $true)][string]$Kind)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; setId = ""; value = $null }
    if (-not $script:HordeFleetChannelMembers.ContainsKey($Kind)) { $fail.reason = "the channel takes no request of the kind " + $Kind; return $fail }
    $strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
    try { $text = $strict.GetString($Body) } catch { $fail.reason = "the request is not UTF-8"; return $fail }
    if (-not $text.TrimStart().StartsWith("{")) { $fail.reason = "the request is not a JSON object"; return $fail }
    if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { $fail.reason = "the request has a member more than once"; return $fail }
    try { $a = ConvertFrom-Json -InputObject $text } catch { $fail.reason = "the request is not JSON"; return $fail }
    if ($a -isnot [System.Management.Automation.PSCustomObject]) { $fail.reason = "the request is not a JSON object"; return $fail }
    $names = @($a.PSObject.Properties | ForEach-Object { $_.Name })
    $sid = Get-HordeFleetChannelMember $a "setId"
    if ($sid -is [string] -and $sid -cmatch '\A[0-9a-f]{32}\z') { $fail.setId = $sid }
    $sorted = [string[]]@($names)
    [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    $want = $script:HordeFleetChannelMembers[$Kind]
    if (($sorted -join ",") -cne ($want -join ",")) { $fail.reason = ("the " + $Kind + " request's members are " + ($names -join ", ") + ", not " + (($want | Sort-Object { $_ } -CaseSensitive) -join ", ")); return $fail }
    if (-not ($a.v -is [int] -or $a.v -is [long]) -or $a.v -ne 1) { $fail.reason = "the request is not version 1"; return $fail }
    if ($fail.setId -eq "") { $fail.reason = "the request's setId is not 32 lower-case hex"; return $fail }
    if ($a.machine -isnot [string] -or $a.machine -cnotmatch '\A[0-9a-f]{32}\z') { $fail.reason = "the request's machine is not a key id"; return $fail }
    $v = [ordered]@{ setId = $a.setId; machine = $a.machine }
    if ($Kind -ceq "wake") {
        if ($a.hibernationId -isnot [string] -or $a.hibernationId -cnotmatch $script:HordeFleetChannelIdPattern) { $fail.reason = "the request's hibernationId is not yyyymmdd-hhmmss"; return $fail }
        $v["hibernationId"] = $a.hibernationId
    } else {
        if (-not ($a.tier -is [int] -or $a.tier -is [long])) { $fail.reason = "the request's tier is not a whole number"; return $fail }
        if ($Kind -ceq "hibernate" -and $a.tier -ne 2) { $fail.reason = "a hibernate request's tier is 2, not " + $a.tier; return $fail }
        if ($Kind -ceq "tier" -and @(1, 2) -notcontains $a.tier) { $fail.reason = "the request's tier is 1 or 2, not " + $a.tier; return $fail }
        if (-not (Test-HordeFleetChannelWhole $a.version)) { $fail.reason = "the request's version is not a whole number"; return $fail }
        $v["tier"] = [int]$a.tier; $v["version"] = [long]$a.version
        if ($Kind -ceq "tier") {
            if ($a.orc -isnot [string] -or $a.orc -cnotmatch $script:HordeFleetChannelOrcPattern) { $fail.reason = "the request's orc is not an Orc id"; return $fail }
            $v["orc"] = $a.orc
        }
    }
    return [pscustomobject]@{ ok = $true; reason = ""; setId = $a.setId; value = [pscustomobject]$v }
}

function New-HordeFleetChannelAnswer {
    # What the request comes to: { answer: done|refused|retry (the contract's word); reason; transient: the
    # act could not be done now and nothing was done, so the port hands the record again; child }.
    param([string]$Answer, [string]$Reason, [bool]$Transient = $false, $Child = $null)
    return [pscustomobject]@{ answer = $Answer; reason = (ConvertTo-HordeFleetChannelText -Text $Reason -Most 400); transient = $Transient; child = $Child }
}

function Invoke-HordeFleetChannelTier {
    param($Context, $Request, [string]$HordeHome)
    $reg = & (Get-HordeFleetChannelSeam -Context $Context -Name "Registry") $HordeHome
    if ($reg.state -cne "known") { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("the Orc registry cannot be read now: " + $reg.reason) -Transient $true) }
    $never = & (Get-HordeFleetChannelSeam -Context $Context -Name "Never") $HordeHome
    if ($never.state -cne "known") { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("which Orcs are never put to sleep cannot be told now: " + $never.reason) -Transient $true) }
    $orc = $Request.orc
    $hit = @($never.value | Where-Object { "" + $_.orc -ceq $orc })
    if ($hit.Count -gt 0) { return (New-HordeFleetChannelAnswer -Answer "refused" -Reason ($orc + " is never put to sleep: " + $hit[0].reason + ", so it has no tier to set")) }
    if ([long]$reg.value.version -ne [long]$Request.version) { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("the Orc registry is at version " + $reg.value.version + ", not " + $Request.version + ": read the snapshot again and ask again")) }
    if (@($reg.value.orcs | Where-Object { "" + $_.id -ceq $orc }).Count -eq 0) { return (New-HordeFleetChannelAnswer -Answer "refused" -Reason ("there is no Orc " + $orc + " in the Orc registry")) }
    $set = & (Get-HordeFleetChannelSeam -Context $Context -Name "SetTier") $HordeHome $orc ([int]$Request.tier) ([long]$Request.version)
    $o = "" + (Get-HordeFleetChannelMember $set "outcome")
    $why = "" + (Get-HordeFleetChannelMember $set "reason")
    if ($o -ceq "done") { return (New-HordeFleetChannelAnswer -Answer "done" -Reason ($orc + " is now in tier " + $Request.tier)) }
    if ($o -ceq "unchanged") { return (New-HordeFleetChannelAnswer -Answer "done" -Reason ($orc + " was already in tier " + $Request.tier + "; nothing was written")) }
    if ($o -ceq "stale") { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("the Orc registry moved on while the change was being written: " + $why)) }
    if ($o -ceq "refused") { return (New-HordeFleetChannelAnswer -Answer "refused" -Reason $why) }
    return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("the tier could not be written now: " + $why) -Transient $true)
}

function Invoke-HordeFleetChannelHibernate {
    param($Context, $Request, [string]$HordeHome, $D)
    $reg = & (Get-HordeFleetChannelSeam -Context $Context -Name "Registry") $HordeHome
    if ($reg.state -cne "known") { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("the Orc registry cannot be read now: " + $reg.reason) -Transient $true) }
    if ([long]$reg.value.version -ne [long]$Request.version) { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("the registry is at version " + $reg.value.version + ", not " + $Request.version + ": read the snapshot again and ask again")) }
    $busy = & (Get-HordeFleetChannelSeam -Context $Context -Name "Busy") $Context $HordeHome @($D.children)
    if ($busy.state -cne "known") { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("whether a hibernation runs cannot be told now: " + $busy.reason) -Transient $true) }
    if ($busy.value.hibernating) { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason "a hibernation is running; ask again when it is done") }
    $ids = Get-HordeFleetTierIds -Rows @($reg.value.orcs) -Tier 2
    if (@($ids.ids).Count -eq 0) { return (New-HordeFleetChannelAnswer -Answer "refused" -Reason ("nothing to hibernate: " + $ids.said)) }
    $started = & (Get-HordeFleetChannelSeam -Context $Context -Name "Start") @("hibernate", "-Tier", "2")
    if ($started.state -cne "known") { return (New-HordeFleetChannelAnswer -Answer "refused" -Reason ("hibernation could not be started: " + $started.reason)) }
    return (New-HordeFleetChannelAnswer -Answer "done" -Reason ("hibernation of tier 2 started for " + @($ids.ids).Count + " Orc(s); it is shown as running once it has taken its record") -Child ([pscustomobject]@{ kind = "hibernate"; id = ""; pid = [long]$started.value.pid; start = "" + $started.value.start }))
}

function Invoke-HordeFleetChannelWake {
    param($Context, $Request, [string]$HordeHome, $D)
    $id = $Request.hibernationId
    $recs = & (Get-HordeFleetChannelSeam -Context $Context -Name "Records") $HordeHome
    if ($recs.state -cne "known") { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("the hibernation records cannot be read now: " + $recs.reason) -Transient $true) }
    if (@($recs.value.records | Where-Object { "" + $_.id -ceq $id }).Count -eq 0) { return (New-HordeFleetChannelAnswer -Answer "refused" -Reason ("there is no hibernation " + $id)) }
    $busy = & (Get-HordeFleetChannelSeam -Context $Context -Name "Busy") $Context $HordeHome @($D.children)
    if ($busy.state -cne "known") { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("whether a wake runs cannot be told now: " + $busy.reason) -Transient $true) }
    if ($busy.value.hibernating) { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason "a hibernation is running; wake when it is done") }
    if (@($busy.value.waking) -ccontains $id) { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("hibernation " + $id + " is being woken now")) }
    $started = & (Get-HordeFleetChannelSeam -Context $Context -Name "Start") @("wake", $id)
    if ($started.state -cne "known") { return (New-HordeFleetChannelAnswer -Answer "refused" -Reason ("the wake could not be started: " + $started.reason)) }
    return (New-HordeFleetChannelAnswer -Answer "done" -Reason ("waking hibernation " + $id + " started") -Child ([pscustomobject]@{ kind = "wake"; id = $id; pid = [long]$started.value.pid; start = "" + $started.value.start }))
}

function Complete-HordeFleetChannelAnswer {
    # Keep what came of a request - the last result, the setId when its answer is final, the process started
    # - and write the state; the item the port is given. A state that cannot be written is a port retry:
    # the answer is not recorded, so the request comes again.
    param($Context, $Mine, $D, [string]$HordeHome, [string]$SetId, $A)
    $result = [pscustomobject]@{ setId = $SetId; outcome = $A.answer; reason = $A.reason }
    $was = ConvertTo-HordeFleetChannelStateText -State $D
    $D.lastResult = $result
    if (@("done", "refused") -ccontains $A.answer) {
        $D.answered = @(@($D.answered | Where-Object { $_.setId -cne $SetId }) + @($result) | Select-Object -Last $script:HordeFleetChannelMostAnswered)
    }
    if ($null -ne $A.child) { $D.children = @(@($D.children) + @($A.child)) }
    try { Write-HordeFleetChannelState -HordeHome $HordeHome -State $D }
    catch {
        $back = ConvertFrom-Json -InputObject $was
        $D.lastResult = $(if ($null -ne $back.lastResult) { [pscustomobject]@{ setId = $back.lastResult.setId; outcome = $back.lastResult.outcome; reason = $back.lastResult.reason } } else { $null })
        $D.answered = @(@($back.answered) | ForEach-Object { [pscustomobject]@{ setId = $_.setId; outcome = $_.outcome; reason = $_.reason } })
        $D.children = @(@($back.children) | ForEach-Object { [pscustomobject]@{ kind = $_.kind; id = $_.id; pid = [long]$_.pid; start = $_.start } })
        return [pscustomobject]@{ outcome = "retry"; reason = ("the fleet channel state could not be written: " + $_.Exception.Message); answer = "retry" }
    }
    $Mine.dirty = $true
    $port = $(if ($A.transient) { "retry" } elseif ($A.answer -ceq "done") { "done" } else { "refused" })
    return [pscustomobject]@{ outcome = $port; reason = $A.reason; answer = $A.answer }
}

function Invoke-HordeFleetChannelAccept {
    # (3) in the header: { outcome; reason; answer } - outcome the port's, answer the contract's word.
    param($Context, $Item)
    $proofProp = $Item.PSObject.Properties["proof"]
    $proof = $(if ($null -eq $proofProp) { "" } else { "$($proofProp.Value)" })
    if (@("webauthn", "session") -cnotcontains $proof) {
        return [pscustomobject]@{ outcome = "refused"; reason = ("a fleet request is signed by a fresh passkey or by his unlocked session, not by '" + $(if ($proof -ceq "") { "no proof named" } else { $proof }) + "'"); answer = "refused" }
    }
    $mine = Get-HordeFleetChannelMine -Context $Context
    $home_ = Get-HordeFleetChannelHome $Context
    $got = Get-HordeFleetChannelDurable -Context $Context -Mine $mine
    if ($got.state -cne "known") { return [pscustomobject]@{ outcome = "retry"; reason = ("the fleet channel is stopped: " + $got.reason); answer = "retry" } }
    $d = $got.value
    $r = Read-HordeFleetChannelRequest -Body $Item.body -Kind ("" + $Item.kind)
    if ($r.setId -cne "") {
        $seen = @($d.answered | Where-Object { $_.setId -ceq $r.setId })
        if ($seen.Count -gt 0) {
            return [pscustomobject]@{ outcome = $(if ($seen[0].outcome -ceq "done") { "done" } else { "refused" }); reason = ("the same request again, answered once already: " + $seen[0].reason); answer = $seen[0].outcome }
        }
    }
    $answer = $null
    if (-not $r.ok) { $answer = New-HordeFleetChannelAnswer -Answer "refused" -Reason $r.reason }
    elseif ($r.value.machine -cne $Context.signKeyId) { $answer = New-HordeFleetChannelAnswer -Answer "refused" -Reason ("the request is for another machine (" + $r.value.machine + "), not this one (" + $Context.signKeyId + ")") }
    elseif ($Item.kind -ceq "tier") { $answer = Invoke-HordeFleetChannelTier -Context $Context -Request $r.value -HordeHome $home_ }
    elseif ($Item.kind -ceq "hibernate") { $answer = Invoke-HordeFleetChannelHibernate -Context $Context -Request $r.value -HordeHome $home_ -D $d }
    else { $answer = Invoke-HordeFleetChannelWake -Context $Context -Request $r.value -HordeHome $home_ -D $d }
    # No setId to answer to (the body was not an object with one): refused at the port, nothing to show.
    if ($r.setId -ceq "") { return [pscustomobject]@{ outcome = "refused"; reason = $answer.reason; answer = "refused" } }
    return (Complete-HordeFleetChannelAnswer -Context $Context -Mine $mine -D $d -HordeHome $home_ -SetId $r.setId -A $answer)
}

# --- (2) out ---

function Send-HordeFleetChannelPending {
    # Put every envelope recorded and not yet taken, in order, dropping one sealed to a key no longer
    # trusted. "" when all were taken, else why not. Writes the state after each.
    param($Context, $D, [Parameter(Mandatory = $true)][string]$HordeHome, [long]$Keep, [string[]]$Trusted)
    $mailbox = New-HordeRelayMailbox -Horde $Context.horde -Reader "phone"
    while (@($D.pending).Count -gt 0) {
        $key = @($D.pending)[0]
        $rec = Test-HordeRelayJournalSent -Key $key -HordeHome $HordeHome
        if ($rec.state -cne "known") { return ("the journal cannot give back " + $key + ": " + $rec.reason) }
        if ($rec.value.sent) {
            $to = @((Read-HordeRelayEnvelope -Text $rec.value.text).value.header.to)
            if (@($to | Where-Object { @($Trusted) -cnotcontains $_ }).Count -gt 0) {
                # Sealed to a key revoked since: dropped, and the newest snapshot is made again for the trusted keys.
                $D.hash = ""
            } else {
                $put = Send-HordeRelayChannelSaved -Context $Context -Saved ([pscustomobject]@{ key = $key; text = $rec.value.text }) -Mailbox $mailbox -KeepFrom (Get-HordeRelayChannelKeepFrom -Key $key -Keep $Keep)
                if ($put.state -cne "known") { return $put.reason }
            }
        }
        $D.pending = @(@($D.pending) | Select-Object -Skip 1)
        try { Write-HordeFleetChannelState -HordeHome $HordeHome -State $D } catch { return ("the fleet channel state could not be written: " + $_.Exception.Message) }
    }
    return ""
}

function Invoke-HordeFleetChannelTick {
    # (2) in the header: { lines; failed }.
    param($Context)
    $mine = Get-HordeFleetChannelMine -Context $Context
    $once = {
        param([string]$Key, [string]$Line, [bool]$Failed)
        if ($mine.said.ContainsKey($Key) -and $mine.said[$Key] -ceq $Line) { return [pscustomobject]@{ lines = @(); failed = $Failed } }
        $mine.said[$Key] = $Line
        return [pscustomobject]@{ lines = @($Line); failed = $Failed }
    }
    $homeDir = Get-HordeFleetChannelHome $Context
    $got = Get-HordeFleetChannelDurable -Context $Context -Mine $mine
    if ($got.state -cne "known") { return (& $once "state" ("the fleet channel is stopped: " + $got.reason + "; mend or move the file, and the channel starts again") $true) }
    $d = $got.value
    $set = Get-HordeModuleSettings -Declaration $script:HordeFleetChannelSettings -HordeHome $homeDir
    if ($set.state -ceq "refused") { return (& $once "settings" ("the fleet channel is stopped: " + (@($set.findings) -join " ")) $true) }
    $mine.said.Remove("state"); $mine.said.Remove("settings")
    # IDLE: a full look reads the registry, the lanes and the records. Within lookMs of the last, with no request
    # answered since and nothing waiting to be put, the Tick returns at once.
    $sinceLook = ([datetime]::UtcNow - $mine.lastLook).TotalMilliseconds
    if (-not $mine.dirty -and @($d.pending).Count -eq 0 -and $sinceLook -lt [long]$set.values.lookMs) { return [pscustomobject]@{ lines = @(); failed = $false } }
    $mine.lastLook = [datetime]::UtcNow
    $mine.dirty = $false
    $out = New-Object System.Collections.ArrayList
    $failed = $false

    $phones = Find-HordeRelayPhoneKeys -HordeHome $homeDir
    if ($phones.state -cne "known") { [void]$out.Add("no fleet snapshot sent: " + $phones.reason); return [pscustomobject]@{ lines = @($out.ToArray()); failed = $true } }
    $keys = @($phones.value)
    $limit = (Get-HordeRelayEnvelopeLimits).recipients
    if ($keys.Count -gt $limit) { $keys = @($keys | Select-Object -First $limit) }
    $trusted = @($keys | ForEach-Object { $_.agreeKeyId })
    $keep = [long]$set.values.keepEnvelopes
    if (@($d.pending).Count -gt 0) {
        $why = Send-HordeFleetChannelPending -Context $Context -D $d -HordeHome $homeDir -Keep $keep -Trusted $trusted
        if ($why -cne "") { [void]$out.Add("fleet snapshot not delivered yet (" + @($d.pending).Count + " envelope(s) recorded and waiting): " + $why); return [pscustomobject]@{ lines = @($out.ToArray()); failed = $true } }
    }
    if ($keys.Count -eq 0) {
        $r = & $once "phones" "no fleet snapshot sent: no phone identity key of this horde is trusted yet" $false
        return [pscustomobject]@{ lines = @(@($out.ToArray()) + @($r.lines)); failed = $false }
    }
    $mine.said.Remove("phones")

    $reg = & (Get-HordeFleetChannelSeam -Context $Context -Name "Registry") $homeDir
    if ($reg.state -cne "known") { $r = & $once "registry" ("no fleet snapshot sent: the Orc registry cannot be read: " + $reg.reason) $true; return [pscustomobject]@{ lines = @(@($out.ToArray()) + @($r.lines)); failed = $true } }
    $never = & (Get-HordeFleetChannelSeam -Context $Context -Name "Never") $homeDir
    if ($never.state -cne "known") { $r = & $once "never" ("no fleet snapshot sent: " + $never.reason) $true; return [pscustomobject]@{ lines = @(@($out.ToArray()) + @($r.lines)); failed = $true } }
    $recs = & (Get-HordeFleetChannelSeam -Context $Context -Name "Records") $homeDir
    if ($recs.state -cne "known") { $r = & $once "records" ("no fleet snapshot sent: " + $recs.reason) $true; return [pscustomobject]@{ lines = @(@($out.ToArray()) + @($r.lines)); failed = $true } }
    foreach ($l in @($recs.value.lines)) { $r = & $once ("rec:" + $l) $l $false; foreach ($x in @($r.lines)) { [void]$out.Add($x) } }
    # Children that have ended are forgotten.
    $alive = @(@($d.children) | Where-Object { Test-HordeFleetChannelChildAlive -Child $_ -Context $Context })
    $childrenChanged = ($alive.Count -ne @($d.children).Count)
    $busy = & (Get-HordeFleetChannelSeam -Context $Context -Name "Busy") $Context $homeDir $alive
    if ($busy.state -cne "known") { $r = & $once "busy" ("no fleet snapshot sent: " + $busy.reason) $true; return [pscustomobject]@{ lines = @(@($out.ToArray()) + @($r.lines)); failed = $true } }
    $mine.said.Remove("registry"); $mine.said.Remove("never"); $mine.said.Remove("records"); $mine.said.Remove("busy")

    # Smaller until it fits: the snapshot lists fewer sessions of each hibernation before it is refused.
    $budget = Get-HordeRelayChannelBodyBudget -Context $Context -Recipients $keys.Count
    $most = [int]$set.values.sessionsMost
    $text = ""
    while ($true) {
        $text = Build-HordeFleetChannelSnapshot -Registry $reg.value -Never @($never.value) -Records @($recs.value.records) -Busy ([bool]$busy.value.hibernating) -LastResult $d.lastResult -SessionsMost $most
        if ($text.Length -le $budget -or $most -le 1) { break }
        $most = [int][Math]::Max(1, [Math]::Floor($most / 2))
    }
    $ok = Test-HordeFleetChannelSnapshot -Text $text
    if (-not $ok.ok) { $r = & $once "shape" ("no fleet snapshot sent: it would break the contract (" + $ok.reason + ")") $true; return [pscustomobject]@{ lines = @(@($out.ToArray()) + @($r.lines)); failed = $true } }
    if ($text.Length -gt $budget) { $r = & $once "size" ("no fleet snapshot sent: it is " + $text.Length + " characters, more than one envelope holds (" + $budget + ")") $true; return [pscustomobject]@{ lines = @(@($out.ToArray()) + @($r.lines)); failed = $true } }
    $mine.said.Remove("shape"); $mine.said.Remove("size")
    $hash = ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes ([System.Text.Encoding]::ASCII.GetBytes($text)))
    $sameKeys = ((@($d.phones) | Sort-Object) -join ",") -ceq ((@($trusted) | Sort-Object) -join ",")
    if ($hash -ceq $d.hash -and $sameKeys) {
        if ($childrenChanged) { $d.children = $alive; try { Write-HordeFleetChannelState -HordeHome $homeDir -State $d } catch { [void]$out.Add("the fleet channel state could not be written: " + $_.Exception.Message); $failed = $true } }
        return [pscustomobject]@{ lines = @($out.ToArray()); failed = $failed }
    }
    $s = Save-HordeRelayChannelEnvelope -Context $Context -Channel "fleet" -Kind "snapshot" -Body ([System.Text.Encoding]::ASCII.GetBytes($text)) -Recipients @(@($keys) | ForEach-Object { , ([byte[]]$_.public) })
    if ($s.state -cne "known") { [void]$out.Add("no fleet snapshot sent: " + $s.reason); return [pscustomobject]@{ lines = @($out.ToArray()); failed = $true } }
    # The envelope is recorded: the state moves on, then it is put.
    $d.pending = @(@($d.pending) + @($s.value.key))
    $d.hash = $hash; $d.phones = $trusted; $d.children = $alive
    try { Write-HordeFleetChannelState -HordeHome $homeDir -State $d }
    catch { [void]$out.Add("the fleet snapshot is recorded, and the fleet channel state could not be written: " + $_.Exception.Message + "; it is sent again after a restart"); return [pscustomobject]@{ lines = @($out.ToArray()); failed = $true } }
    $why = Send-HordeFleetChannelPending -Context $Context -D $d -HordeHome $homeDir -Keep $keep -Trusted $trusted
    if ($why -cne "") { [void]$out.Add("fleet snapshot recorded; not delivered yet: " + $why); return [pscustomobject]@{ lines = @($out.ToArray()); failed = $true } }
    [void]$out.Add("fleet snapshot sent")
    return [pscustomobject]@{ lines = @($out.ToArray()); failed = $failed }
}

function Test-HordeFleetChannelGlance {
    # THE GLANCE (channels/Port.ps1): was a request answered since the last look? Nothing is read or opened:
    # a flag the Accept set, so the answer is on his phone in about a second and not at the next idle look.
    param($Context)
    if (-not $Context.state.ContainsKey("fleet")) { return $false }
    return [bool]$Context.state["fleet"].dirty
}

$null = Register-HordeRelayChannel -Folder $script:HordeFleetChannelFolder -Name "fleet" -Kinds @("tier", "hibernate", "wake") -Senders "founder" `
    -Accept { param($Context, $Item) return (Invoke-HordeFleetChannelAccept -Context $Context -Item $Item) } `
    -Tick { param($Context) return (Invoke-HordeFleetChannelTick -Context $Context) } `
    -Glance { param($Context) return (Test-HordeFleetChannelGlance -Context $Context) }
