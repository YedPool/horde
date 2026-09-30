# core/HostPort - the one way the read model learns what a terminal host can see right now.
#
# D12 (planning/migration-plan.html): nothing outside hosts/<name>/ names a terminal. The
# projection needs two live facts that only a host can give - which handles (panes, in the first
# host's words) exist, and which host instance they belong to - so it asks through this port and
# never through a terminal's own command line. The first real adapter will live under
# hosts/<name>/; until then tests pass a fake port and the reality check passes an unavailable one.
#
# WHAT A PORT ANSWERS, both through core/tristate so "could not ask" is never read as "none":
#   Handles   the live handles, each { handle; window; tab; hostTitle } and optionally { pid; cwd;
#             space } - handle and window as text, because a handle is opaque to the engine (D12: a
#             terminal's pane id "is a host handle ... never a key"). wezfleet turned an unreadable
#             pane list into an empty map (YedPool/wezfleet lib/Common.ps1:497-503) and census then
#             printed "no live panes." for a mux it could not read (commands/census.ps1:10-11).
#   Instance  { id; startedAt; running; ambiguous }: which host instance the handles belong to,
#             when it started (a record written before then describes another instance's handle -
#             YedPool/wezfleet 0e1c75a), how many instances are running, and whether the port
#             cannot tell which one is meant (lib/Common.ps1:539-595 had the same four facts).
#
# THE CONTRACT AN ADAPTER KEEPS. Written before the second host, from research into three more
# (planning/ledger/core-projection.md L-074 to L-081), while this port has one caller:
#   CAPABILITIES ARE DECLARED, NEVER INFERRED. New-HordeHostPort takes a mandatory -Capabilities: for
#     each name in $script:HordeHostCapabilityNames, yes, no, declined (the host could; the adapter
#     refuses) or unverified. Core relies on a capability only when it is yes; unverified counts as
#     no, never as an optimistic yes. One host cannot read its screen and another cannot send text,
#     so asking for what a host lacks is an unknown with that reason, never a crash (D5).
#   A HANDLE IS UNIQUE WITHIN ITS INSTANCE, and only there. A host whose native ids repeat inside one
#     instance - one server per session, each numbering its panes from the start - composes the
#     handle from both, <session>.<pane>, so no two live handles of one instance are the same text.
#     A list with a repeated handle is unknown as a whole.
#   RUNNING COUNTS INSTANCES - the namespaces handles are unique in - NOT SERVER PROCESSES. A host
#     that runs one server per session reports its whole namespace as one instance; counting
#     servers would read every user with two sessions as two instances, and the projection refuses
#     every pane-sessions file while more than one instance runs.
#   HANDLE TEXT IS PLAIN, and the mapping is the adapter's. A native id with a sigil (a leading %, @
#     or $) fails the handle rule and makes the list unknown; the adapter maps each native id to
#     plain text (for example %1 to p1) and back, one to one, so no $ reaches a reason string core
#     builds, where PowerShell would try to expand it.
#   THE ADAPTER BUILDS THE INSTANCE ID, from whatever names the running server, and the id must change
#     when the server restarts: a host that reuses a socket name for its next server would otherwise
#     hand a new instance's handles the old one's records. It is plain text of letters, digits and
#     . _ : - up to 128 characters - room for <distro>.<socket>.<server pid> - and an adapter whose
#     natural name is longer or holds other characters maps it (a path to its leaf, say), one to one.
#     A malformed id is never dropped: the instance is unknown, with the reason.
#   WINDOW AND TAB ARE THE FIRST HOST'S WORDS, kept because the restore plan uses them. A host maps its
#     own levels onto them - a multiplexer's session onto window and its window onto tab; a host with
#     windows and tabs maps them directly - and gives $null for a level it does not have.
#   A STORED HANDLE BELONGS TO THE HOST THAT WROTE IT. wezfleet's registry, rosters and reports, the
#     pane-sessions files and the spawn claims hold bare handle text with no host in it, written by
#     the first host. Another host's handle 17 is not that pane 17, so a port declares, with
#     -StoredHandles, the stores whose handles it wrote; a handle from any other store is unknown to
#     it (review of PR #31, finding 2). A record that names its instance is also checked against it.
#     ONE WRITER PER STORE. The rule holds only while each store has exactly one writer host, so a
#     second host declaring a store another host already declared is refused (second review of
#     PR #31, finding 2). A record that carries no host belongs to the legacy writer alone - the one
#     host that declares its store. An adapter takes its list from its own capabilities.json
#     (hosts/<name>/capabilities.json, key storedHandles), never from code; a new host that writes
#     handles into Horde's own stores tags each with its host and instance instead.
#   PID AND CWD CARRY A NAMESPACE. A row that gives a pid or cwd names its space: windows,
#     wsl:<distro>, posix or synthetic. A multiplexer running inside a Linux subsystem returns that
#     system's pids and paths. Core's process table is the windows one (CIM), so a pid or cwd from
#     any other space is unknown, with the reason, and is never compared with it.
#   A PANE'S OWN-ID VARIABLE IS A CAPABILITY (selfHandle), and propagating it is the adapter's job:
#     each host names its own variable, and a host inside a subsystem must export it to the Windows
#     processes it starts, or a child never sees it. core/Identity.ps1 still never falls back to it.
#
# A port is data plus two script blocks. The projection calls them through Invoke-HordeRead, so a
# port that throws, writes an error or returns nothing is unknown with the reason, never empty.

# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Platform.ps1")

# The closed vocabulary of what a host may offer (the runtime verbs and facts of the terminal port;
# layout capabilities belong to the layout port). A name outside it is refused, so a typo cannot
# declare a capability nobody checks.
$script:HordeHostCapabilityNames = @("list", "pid", "tty", "cwd", "title.read", "title.set", "text.read", "text.send",
    "spawn", "spawn.env", "spawn.cwd", "kill", "focus", "selfHandle", "instance.startedAt")
$script:HordeHostCapabilityStates = @("yes", "no", "declined", "unverified")
# The stores that hold bare handle text (core/ownership.json): registry, claims, roster, reports and
# pane-sessions files.
$script:HordeHandleStores = @("W1", "W2", "W4", "W5", "X1")
# Which host declared each store's handles, for this process: the single-writer rule.
if ($null -eq (Get-Variable -Name HordeStoreWriters -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeStoreWriters = @{} }

function ConvertTo-HordeHostCapabilities {
    # A declaration as a full table: every name, each yes, no, declined or unverified. A name that is
    # not declared is no. Refuses anything else, loudly: a capability table is the adapter's code.
    param($Capabilities)
    if ($null -eq $Capabilities) { throw "-Capabilities must declare what the host offers: yes, no, declined or unverified per capability" }
    $pairs = @()
    if ($Capabilities -is [System.Collections.IDictionary]) { $pairs = @($Capabilities.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Name = "$($_.Key)"; Value = $_.Value } }) }
    elseif ($Capabilities -is [System.Management.Automation.PSCustomObject]) { $pairs = @($Capabilities.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } }) }
    else { throw "-Capabilities must be a hashtable or object of capability names to yes, no, declined or unverified" }
    $table = @{}
    foreach ($n in $script:HordeHostCapabilityNames) { $table[$n] = "no" }
    foreach ($p in $pairs) {
        if ($script:HordeHostCapabilityNames -cnotcontains $p.Name) { throw ("'" + $p.Name + "' is not a host capability; one of " + ($script:HordeHostCapabilityNames -join ", ")) }
        if ($p.Value -isnot [string] -or $script:HordeHostCapabilityStates -cnotcontains $p.Value) { throw ("capability " + $p.Name + " must be yes, no, declined or unverified, not '" + $p.Value + "'") }
        $table[$p.Name] = $p.Value
    }
    return $table
}

function ConvertTo-HordeHandleStores {
    # The stores whose handle text a host wrote: a list of store ids from $script:HordeHandleStores,
    # possibly empty. Refuses $null and anything else, so an adapter has to decide.
    param($StoredHandles)
    if ($null -eq $StoredHandles) { throw "-StoredHandles must list the stores whose handles this host wrote (it may be empty)" }
    $out = @()
    foreach ($x in @($StoredHandles)) {
        if ($x -isnot [string] -or $script:HordeHandleStores -cnotcontains $x) { throw ("'" + $x + "' is not a store that holds handles; one of " + ($script:HordeHandleStores -join ", ")) }
        if ($out -cnotcontains $x) { $out += $x }
    }
    return , $out
}

function Test-HordeHostWroteStore {
    # Did this host write the handle text in this store?
    param($Port, [string]$Store)
    Assert-HordeHostPort $Port
    return ($Port.available -and @($Port.storedHandles) -ccontains $Store)
}

function New-HordeHostPort {
    # A host port. -Name is the host's own name, supplied by its adapter; core never spells one.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowNull()]$Capabilities,
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()]$StoredHandles,
        [Parameter(Mandatory = $true)][scriptblock]$Handles,
        [Parameter(Mandatory = $true)][scriptblock]$Instance
    )
    $table = ConvertTo-HordeHostCapabilities $Capabilities
    $stores = ConvertTo-HordeHandleStores $StoredHandles
    foreach ($st in $stores) {
        if ($script:HordeStoreWriters.ContainsKey($st) -and $script:HordeStoreWriters[$st] -cne $Name) {
            throw ("store " + $st + "'s handles are already declared by host '" + $script:HordeStoreWriters[$st] + "'; a store has one writer host, and records that carry no host belong to it alone")
        }
    }
    foreach ($st in $stores) { $script:HordeStoreWriters[$st] = $Name }
    return [pscustomobject]@{ PSTypeName = "Horde.HostPort"; name = $Name; available = $true; reason = ""; capabilities = $table; storedHandles = $stores; handles = $Handles; instance = $Instance }
}

function New-HordeUnavailableHostPort {
    # A port for a host that cannot be asked - no adapter attached yet, or the adapter cannot reach
    # its terminal. It offers nothing, and every answer through it is unknown with this reason, so a
    # stored handle is never verified against it (the lead's decision 2, 2026-09-30).
    param([Parameter(Mandatory = $true)][string]$Reason)
    if ("$Reason".Trim() -eq "") { throw "an unavailable host port needs a reason" }
    return [pscustomobject]@{ PSTypeName = "Horde.HostPort"; name = ""; available = $false; reason = $Reason; capabilities = (ConvertTo-HordeHostCapabilities @{}); storedHandles = @(); handles = $null; instance = $null }
}

function Assert-HordeHostPort {
    param($Port)
    if ($null -eq $Port -or @($Port.PSObject.TypeNames) -notcontains "Horde.HostPort") {
        throw "-HostPort must be made by New-HordeHostPort or New-HordeUnavailableHostPort"
    }
}

function Test-HordeHostCapability {
    # Does the host offer this? $true only for yes: no, declined and unverified all mean core must not
    # rely on it. A name outside the vocabulary is a programming error and throws.
    param($Port, [Parameter(Mandatory = $true)][string]$Name)
    Assert-HordeHostPort $Port
    if ($script:HordeHostCapabilityNames -cnotcontains $Name) { throw ("'" + $Name + "' is not a host capability") }
    return ($Port.available -and "$($Port.capabilities[$Name])" -ceq "yes")
}

function Get-HordeHostCapabilityReason {
    # Why core will not rely on a capability, for an unknown's reason.
    param($Port, [string]$Name)
    if (-not $Port.available) { return ("the host cannot be asked: " + $Port.reason) }
    return ("the host does not offer " + $Name + " (it declares " + $Port.capabilities[$Name] + ", and only yes is relied on)")
}

function ConvertTo-HordeHandleText {
    # A handle or window id as text: "12" for 12 and for "12". Anything that is not a whole number
    # or plain text of letters, digits and . _ : - is refused as $null, so a malformed id - or a
    # native id with a sigil the adapter failed to map - never becomes a key.
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [int] -or $Value -is [long]) { if ($Value -lt 0) { return $null }; return ("" + $Value) }
    $t = "$Value"
    if ($t -cmatch '^[A-Za-z0-9._:-]{1,64}$') { return $t }
    return $null
}

function ConvertTo-HordeInstanceText {
    # An instance id as text, or $null: plain text of letters, digits and . _ : -, 1 to 128 characters.
    param($Value)
    if ($null -eq $Value) { return $null }
    $t = "$Value"
    if ($t -cmatch '^[A-Za-z0-9._:-]{1,128}$') { return $t }
    return $null
}

function Read-HordeHandleNamespaced {
    # A row's pid or cwd as an answer, in the platform's namespace only. Unknown when the host does not
    # offer it, the row gives none, the row names no space, or the space is not the platform's: a pid
    # from a Linux subsystem is a different process from the Windows pid with the same number, and is
    # never compared with it. The platform (core/Platform.ps1) says which namespace core's own process
    # table is in.
    param($Port, $Row, [string]$Field, [string]$LocalSpace)
    if (-not (Test-HordeHostCapability -Port $Port -Name $Field)) { return (New-HordeUnknown -Reason (Get-HordeHostCapabilityReason -Port $Port -Name $Field)) }
    $v = Get-HordeField -Record $Row -Name $Field
    if ($v.state -ne "known") { return (New-HordeUnknown -Reason ("the host gives no " + $Field + " for this handle")) }
    $sp = Get-HordeField -Record $Row -Name "space"
    if ($sp.state -ne "known" -or "$($sp.value)" -cnotmatch $script:HordeProcessSpacePattern) {
        return (New-HordeUnknown -Reason ("the host gives a " + $Field + " with no namespace, so it cannot be placed"))
    }
    if ("$($sp.value)" -cne $LocalSpace) {
        return (New-HordeUnknown -Reason ("the " + $Field + " is in namespace " + $sp.value + ", not " + $LocalSpace + " where core's process table lives, and is never compared across namespaces"))
    }
    if ($Field -eq "pid") {
        if (($v.value -isnot [int] -and $v.value -isnot [long]) -or $v.value -le 0) { return (New-HordeUnknown -Reason "the host's pid is not a positive whole number") }
        return (New-HordeKnown -Value ([int]$v.value))
    }
    if ($v.value -isnot [string] -or "$($v.value)".Trim() -eq "") { return (New-HordeUnknown -Reason "the host's cwd is not text") }
    return (New-HordeKnown -Value "$($v.value)")
}

function Read-HordeHostHandles {
    # The port's handle list as an answer: known @( { handle; window; tab; hostTitle; pid; cwd } ),
    # pid and cwd each an answer, or unknown. A list with a malformed or repeated handle is unknown as
    # a whole: one bad row makes it impossible to say which handles are live.
    param($Port, $Platform = (Get-HordeLocalPlatform))
    Assert-HordeHostPort $Port
    Assert-HordePlatform $Platform
    if (-not (Test-HordeHostCapability -Port $Port -Name "list")) { return (New-HordeUnknown -Reason (Get-HordeHostCapabilityReason -Port $Port -Name "list")) }
    # Flattened one level, so a port may return its rows plainly or as one list with the unary comma
    # (PowerShell 5.1 delivers the second as a single element holding the list).
    $got = Invoke-HordeRead -What "the host's live handles" -Read { return , @(& $Port.handles | ForEach-Object { $_ }) }
    if ($got.state -ne "known") { return $got }
    $seen = @{}
    $rows = New-Object System.Collections.ArrayList
    foreach ($h in @($got.value)) {
        $hf = Get-HordeField -Record $h -Name "handle"
        $id = $null
        if ($hf.state -eq "known") { $id = ConvertTo-HordeHandleText $hf.value }
        if ($null -eq $id) { return (New-HordeUnknown -Reason "the host listed a handle that is not plain handle text; an adapter maps native ids to it") }
        if ($seen.ContainsKey($id)) { return (New-HordeUnknown -Reason ("the host listed handle " + $id + " twice, and a handle must be unique within its instance")) }
        $seen[$id] = $true
        $wf = Get-HordeField -Record $h -Name "window"
        $tf = Get-HordeField -Record $h -Name "tab"
        $tt = Get-HordeField -Record $h -Name "hostTitle"
        [void]$rows.Add([pscustomobject]@{
            handle = $id
            window = $(if ($wf.state -eq "known") { ConvertTo-HordeHandleText $wf.value } else { $null })
            tab = $(if ($tf.state -eq "known") { ConvertTo-HordeHandleText $tf.value } else { $null })
            hostTitle = $(if ($tt.state -eq "known") { "$($tt.value)" } else { $null })
            pid = (Read-HordeHandleNamespaced -Port $Port -Row $h -Field "pid" -LocalSpace $Platform.processSpace)
            cwd = (Read-HordeHandleNamespaced -Port $Port -Row $h -Field "cwd" -LocalSpace $Platform.processSpace)
        })
    }
    return (New-HordeKnown -Value $rows.ToArray())
}

function Read-HordeHostInstance {
    # The port's instance as an answer: known { id; startedAt; running; ambiguous }, or unknown.
    # startedAt is kept only when the host offers instance.startedAt, and must then be a placed
    # [datetime]; running is a whole number of instances (see the contract above).
    param($Port)
    Assert-HordeHostPort $Port
    if (-not $Port.available) { return (New-HordeUnknown -Reason ("the host cannot be asked: " + $Port.reason)) }
    $got = Invoke-HordeRead -What "the host instance" -Read { & $Port.instance }
    if ($got.state -ne "known") { return $got }
    $v = $got.value
    $run = Get-HordeField -Record $v -Name "running"
    if ($run.state -ne "known" -or ($run.value -isnot [int] -and $run.value -isnot [long]) -or $run.value -lt 0) {
        return (New-HordeUnknown -Reason "the host did not say how many instances are running")
    }
    # Neither field is dropped or defaulted when it is malformed (review of PR #31, finding 4): an id
    # that is not plain instance text, or an ambiguity flag that is not true or false, makes the whole
    # instance unknown, because which instance the handles belong to is then not known.
    $amb = Get-HordeField -Record $v -Name "ambiguous"
    $ambiguous = $false
    if ($amb.state -eq "known") {
        if ($amb.value -isnot [bool]) { return (New-HordeUnknown -Reason ("the host's ambiguous flag is '" + $amb.value + "', not true or false")) }
        $ambiguous = $amb.value
    }
    $idf = Get-HordeField -Record $v -Name "id"
    $id = $null
    if ($idf.state -eq "known") {
        $id = ConvertTo-HordeInstanceText $idf.value
        if ($null -eq $id) { return (New-HordeUnknown -Reason "the host gave an instance id that is not plain text of at most 128 characters; its adapter maps the native name") }
    }
    $started = $null
    if (Test-HordeHostCapability -Port $Port -Name "instance.startedAt") {
        $sf = Get-HordeField -Record $v -Name "startedAt"
        if ($sf.state -eq "known") {
            if ($sf.value -isnot [datetime] -or $sf.value.Kind -eq [System.DateTimeKind]::Unspecified) {
                return (New-HordeUnknown -Reason "the host gave an instance start time that is not a placed [datetime]")
            }
            $started = $sf.value.ToUniversalTime()
        }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ id = $id; startedAt = $started; running = [int]$run.value; ambiguous = $ambiguous; startedAtOffered = (Test-HordeHostCapability -Port $Port -Name "instance.startedAt") }))
}
