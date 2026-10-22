# core/HomeTasks - what `horde home` reports about the home after a flip (T-0299, round-1 review).
#
# A scheduled task that bakes a home into its action (HORDE_HOME set in the command it runs) outranks the pointer
# file, so it keeps the old folder after horde home set. New tasks no longer bake one, but a task registered before
# that change still does, and every task records the home it was registered under in its description. This reads
# the tasks under \Horde\ and names each one whose recorded or baked home is not the effective one. READ ONLY: it
# changes no task, and when the scheduler refuses the query it says so in one line and the verb goes on.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Home.ps1")
. (Join-Path $PSScriptRoot "Services.ps1")
. (Join-Path $PSScriptRoot "Heartbeat.ps1")

function ConvertTo-HordeHomeComparable {
    # A path made comparable: full path, no trailing separator. Text that is not a path comes back as it was.
    param([string]$Path)
    $p = "$Path".Trim()
    try { $p = [System.IO.Path]::GetFullPath($p) } catch { }
    return $p.TrimEnd('\', '/')
}

function Get-HordeTaskNamedHomes {
    # The homes a task names, as { home; how } rows: the home in its description's marker line ("registered under"),
    # and a HORDE_HOME baked into its action ("baked into its action"), read from the -EncodedCommand text: either
    # the scheduler job form (SetEnvironmentVariable('HORDE_HOME', (& $d '<base64>'), ...)) or the plain form
    # ($env:HORDE_HOME = '<path>').
    param([string]$Description, [string]$Arguments)
    $rows = New-Object System.Collections.ArrayList
    foreach ($l in @("$Description" -split "`r?`n")) {
        if ($l.StartsWith("horde-home: ") -and $l.Length -gt 12) { [void]$rows.Add([pscustomobject]@{ home = $l.Substring(12).Trim(); how = "registered under" }) }
    }
    if ("$Arguments" -match '-EncodedCommand\s+([A-Za-z0-9+/=]+)') {
        $text = ""
        try { $text = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Matches[1])) } catch { $text = "" }
        foreach ($m in [regex]::Matches($text, "SetEnvironmentVariable\('HORDE_HOME', \(& \`$d '([A-Za-z0-9+/=]*)'\)")) {
            try { [void]$rows.Add([pscustomobject]@{ home = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($m.Groups[1].Value)); how = "baked into its action" }) } catch { }
        }
        foreach ($m in [regex]::Matches($text, "\`$env:HORDE_HOME = '((?:[^']|'')*)'")) {
            [void]$rows.Add([pscustomobject]@{ home = $m.Groups[1].Value.Replace("''", "'"); how = "baked into its action" })
        }
    }
    return @($rows.ToArray())
}

function Get-HordeHomeTaskFindings {
    # One line per task under \Horde\ that names a home other than -Effective, or one line saying the tasks could
    # not be read. Returns { lines; checked } - checked is $false when the query was not possible. Never throws.
    param([Parameter(Mandatory = $true)][string]$Effective, [scriptblock]$ListTasks = $null)
    $want = ConvertTo-HordeHomeComparable $Effective
    $found = @()
    try {
        if ($null -eq $ListTasks) {
            if ($null -eq (Get-Command -Name Get-ScheduledTask -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ lines = @("tasks: not checked (Task Scheduler is not available here)"); checked = $false } }
            $ListTasks = { Get-ScheduledTask -TaskPath "\Horde\*" -ErrorAction Stop }
        }
        $found = @(& $ListTasks)
    } catch {
        $why = ("" + $_.Exception.Message).Trim() -replace '\s+', ' '
        return [pscustomobject]@{ lines = @("tasks: not checked (the Task Scheduler query was refused or failed: " + $why + "; try from an elevated prompt)"); checked = $false }
    }
    $lines = New-Object System.Collections.ArrayList
    foreach ($t in $found) {
        $args2 = ""
        $acts = @($t.Actions)
        if ($acts.Count -gt 0) { $args2 = "" + $acts[0].Arguments }
        $seen = @{}
        foreach ($r in @(Get-HordeTaskNamedHomes -Description ("" + $t.Description) -Arguments $args2)) {
            # ONLY A BAKED HOME IS A FINDING. A task that bakes none resolves the home at each run, so the home in its
            # marker (where it was registered) says nothing about where it runs; flagging it would call a correct task stale.
            if ($r.how -ceq "baked into its action" -and (ConvertTo-HordeHomeComparable $r.home) -ine $want -and -not $seen.ContainsKey($r.how)) {
                $seen[$r.how] = $true
                [void]$lines.Add("task " + $t.TaskPath + $t.TaskName + " is " + $r.how + " the home " + $r.home + ", not " + $Effective + " (it keeps that home whatever the pointer says; re-register it)")
            }
        }
    }
    if ($lines.Count -eq 0) { [void]$lines.Add("tasks: " + @($found).Count + " under \Horde\, none bakes in another home") }
    return [pscustomobject]@{ lines = @($lines.ToArray()); checked = $true }
}

function Get-HordeRunningHordeServices {
    # The horde-kind services of the definitions in -Home whose heartbeat says they are running now: { name; beat }
    # rows. `horde services stop` runs a service's stop command with the definition's hordeHome, so a service must be
    # stopped BEFORE the home is moved (planning/fleet-db-design.md). Read only. A definitions file or heartbeat that
    # cannot be read gives no row (the caller cannot tell, and says nothing rather than refuse on a guess).
    param([Parameter(Mandatory = $true)][string]$Home2, [datetime]$Now = [datetime]::UtcNow)
    $rows = New-Object System.Collections.ArrayList
    $defs = $null
    try { $defs = Get-HordeServiceDefinitions -HordeHome $Home2 } catch { return @() }
    if ($null -eq $defs -or "$($defs.state)" -ceq "refused") { return @() }
    foreach ($d in @($defs.services)) {
        if ($null -eq $d -or $d.enabled -ne $true -or $null -eq $d.alive) { continue }
        $horde = ($null -ne $d.start -and "$($d.start.kind)" -ceq "horde") -or ($null -ne $d.stop -and "$($d.stop.kind)" -ceq "horde")
        if (-not $horde) { continue }
        try {
            $beat = Read-HordeHeartbeat -Path $d.alive.path
            $v = Get-HordeHeartbeatVerdict -Heartbeat $beat -Now $Now -DefaultTickSeconds ([int]$d.alive.tickSeconds)
            if ($v.state -ceq "known" -and $v.value.fresh -eq $true) { [void]$rows.Add([pscustomobject]@{ name = "$($d.name)"; ageSeconds = $v.value.ageSeconds; clearsInSeconds = [Math]::Max(1, [long]$v.value.staleAfterSeconds - [long]$v.value.ageSeconds + 1) }) }
        } catch { }
    }
    return @($rows.ToArray())
}

function Get-HordeHomeAfterClear {
    # The home `horde home clear` would leave for every reader without HORDE_HOME: the default. (HORDE_HOME in THIS process
    # does not matter: clear removes the pointer for everyone else.)
    return (Join-Path (Get-HordeProfileDir) ".horde")
}

function Assert-HordeNoServiceRunsOnOldHome {
    # Throws when a horde-kind service of the CURRENT home is running and -NewHome is a different folder. The flip order
    # is: stop each service (its definition still names the old home), change the definitions' hordeHome, set the
    # pointer, start. Setting the pointer first, or editing a definition first, sends the stop to the wrong home while
    # the process runs on, so the relay runs twice or the stop does nothing.
    param([Parameter(Mandatory = $true)][string]$NewHome, [ValidateSet("set", "clear")][string]$Verb = "set", [datetime]$Now = [datetime]::UtcNow)
    # THE POINTER-LEVEL HOMES, ignoring HORDE_HOME in this process: the pointer decides for every reader without it, and
    # those are the processes a set or clear moves. Old = the pointer's home if there is a good pointer, else the default.
    # A bad or unreadable pointer, or no profile folder at all: the guard cannot tell and says nothing (it fails open).
    $old = ""
    $pointer = Get-HordeHomePointerPath
    if ($null -eq $pointer) { return }
    if (Test-Path -LiteralPath $pointer) {
        $read = Read-HordeHomePointer -File $pointer
        if (-not $read.ok) { return }
        $old = $read.home
    } else { $old = Join-Path (Get-HordeProfileDir) ".horde" }
    if ((ConvertTo-HordeHomeComparable $old) -ieq (ConvertTo-HordeHomeComparable $NewHome)) { return }
    $running = @(Get-HordeRunningHordeServices -Home2 $old -Now $Now)
    if ($running.Count -gt 0) {
        # horde services stop leaves the heartbeat file; "running" is a heartbeat younger than its stale time, so a
        # service stopped a moment ago still reads as running until the heartbeat goes stale.
        $wait = [long](@($running | ForEach-Object { $_.clearsInSeconds } | Measure-Object -Maximum).Maximum)
        throw ("home " + $Verb + " is refused: " + (@($running | ForEach-Object { $_.name }) -join ", ") + " (a horde-kind service, running under " + $old + ") would be left running on the old home. Stopped just now? its heartbeat clears in about " + $wait + " s, then try again. Stop each with horde services stop <name> first (while its definition still names the old home), then change the definitions' hordeHome, then run home set, then horde services start <name>")
    }
}

function Get-HordeHomeCheckLines {
    # The lines `horde home` prints after the home and its source: a warning when HORDE_HOME is set in this process
    # while a pointer exists (it overrides the pointer), then the task check.
    param([scriptblock]$ListTasks = $null)
    $now = Resolve-HordeHome
    $lines = New-Object System.Collections.ArrayList
    $pointer = Get-HordeHomePointerPath
    if ("$env:HORDE_HOME".Trim() -ne "" -and $null -ne $pointer -and (Test-Path -LiteralPath $pointer)) {
        [void]$lines.Add("WARNING: HORDE_HOME is set in this process (" + "$env:HORDE_HOME".Trim() + ") and overrides the pointer file; processes without it follow the pointer. Remove it where it is set (a user-level variable, a profile) for the pointer to rule here too.")
    }
    foreach ($l in @((Get-HordeHomeTaskFindings -Effective $now.path -ListTasks $ListTasks).lines)) { [void]$lines.Add($l) }
    return @($lines.ToArray())
}
