# core/Schedule - one recurring job, defined once and handed to whichever scheduler this machine has.
#
# WHY A SEAM. `horde metrics collect` runs every 30 minutes (plan step M2). On Windows that is a Task
# Scheduler task; a Linux host will want cron or a systemd timer. The job is defined here as DATA - the
# horde script, its arguments, the environment it needs, how often, how long at most - and a SCHEDULER
# turns it into the platform's own form, including which program runs it and how its arguments are
# passed. A scheduler is a file under core/schedule/ that registers itself with Register-HordeScheduler.
# A new platform is a new file; nothing here names a shell or a quoting rule.
#
# A JOB IS HORDE'S ONLY WHEN IT SAYS SO (review of PR #70, F1). A job lives in Horde's own folder of the
# scheduler (Horde, or HordeTest for suites), carries a marker and the Horde home it serves, and a
# scheduler installs over, or removes, only a job that carries the marker. A job of the same name that
# Horde did not make is refused and left alone.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1 and
# core/Home.ps1.

# What this file calls, loaded here so the file works on its own (tools/CoreLoad.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Home.ps1")

# A REGISTRY IS MADE ONCE, never reset by a later load (review of #114): core files load what they
# call, so this file is dot-sourced again by files loaded after the adapters have registered, and an
# unconditional reset here would silently empty it.
if ($null -eq (Get-Variable -Name HordeSchedulers -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeSchedulers = New-Object System.Collections.ArrayList }
$script:HordeCollectJobName = "Horde metrics collect"
$script:HordeJobFolders = @("Horde", "HordeTest")
$script:HordeJobMarker = "horde-managed-job: 1"

function Register-HordeScheduler {
    # -Available answers whether this scheduler works on this machine. -Install takes a job
    # (New-HordeScheduledJob); -Remove takes (name, folder) and returns whether a job was removed;
    # -Status takes (name, folder) and returns an answer: known { enabled; state; everyMinutes; marked;
    # home; lastRunAt; lastResult; nextRunAt; runs }, absent when no such job exists. Install and remove
    # throw rather than touch a job that does not carry Horde's marker.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Available,
        [Parameter(Mandatory = $true)][scriptblock]$Install,
        [Parameter(Mandatory = $true)][scriptblock]$Remove,
        [Parameter(Mandatory = $true)][scriptblock]$Status
    )
    foreach ($s in $script:HordeSchedulers) { if ($s.name -ceq $Name) { $script:HordeSchedulers.Remove($s); break } }
    [void]$script:HordeSchedulers.Add([pscustomobject]@{ name = $Name; available = $Available; install = $Install; remove = $Remove; status = $Status })
}

function Get-HordeSchedulerFiles {
    # The scheduler files, found by folder: core/schedule/*.ps1. The CALLER dot-sources each one at its
    # own scope, so the helpers a scheduler defines stay visible to the blocks it registers.
    return @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "schedule") -Filter "*.ps1" -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ceq ".ps1" } | Sort-Object Name | ForEach-Object { $_.FullName })
}

function Get-HordeScheduler {
    # The first registered scheduler that works here, as an answer; unknown when none does.
    foreach ($s in $script:HordeSchedulers) {
        $ok = $false
        try { $ok = (& $s.available) -eq $true } catch { $ok = $false }
        if ($ok) { return (New-HordeKnown -Value $s) }
    }
    return (New-HordeUnknown -Reason ("no scheduler works on this machine (registered: " + (@($script:HordeSchedulers | ForEach-Object { $_.name }) -join ", ") + ")"))
}

function Assert-HordeJobName {
    # A job's name and folder: plain words, and one of Horde's own folders. Applied to every action,
    # remove and status included, so no name reaches a scheduler that Horde would not have made.
    param([string]$Name, [string]$Folder)
    if ($Name -notmatch '\A[A-Za-z0-9][A-Za-z0-9 ._-]{0,100}\z') { throw ("not a job name Horde will use: '" + $Name + "'") }
    if ($script:HordeJobFolders -cnotcontains $Folder) { throw ("not one of Horde's scheduler folders (" + ($script:HordeJobFolders -join ", ") + "): '" + $Folder + "'") }
}

function New-HordeScheduledJob {
    # The job, as data. It runs -Script with -Arguments and -Environment as the current user, every
    # -EveryMinutes, at low priority, stopped after -TimeLimitMinutes, never two at once, and not at
    # all when -Disabled. -HordeHome is the home it serves, written into its marker.
    #
    # -WithPerson: THE JOB RUNS IN THE PERSON'S OWN LOGON SESSION, AND ONLY WHILE THEY ARE LOGGED ON.
    # A job is otherwise run where nobody sees it, logged on or not, which is right for work on files.
    # It is for a job that must open windows on the person's desktop or see their input. The
    # supervisor of services was such a job until 2026-10-14, and is not any more (-AtStartup below;
    # cli/ServicesTend.ps1 says what it gives up and how it copes). How a scheduler runs a job in the
    # person's session without a window flashing every minute is the scheduler's.
    #
    # -AtStartup: THE JOB ALSO RUNS WHEN THE MACHINE STARTS, before anyone has signed in, and then
    # every -EveryMinutes as before. It is for a job that keeps something running: after a restart on
    # 2026-10-14 the supervisor, then a -WithPerson job, did not run for 2 h 38 min because nobody
    # signed in, and the relay it keeps was down all that time. So it is refused together with
    # -WithPerson, which cannot run until someone signs in. A scheduler may need more rights to
    # register a job that runs at start-up; one that lacks them says so, and installs nothing else.
    #
    # -AtLogon: THE JOB ALSO RUNS WHEN THE PERSON IT RUNS AS SIGNS IN, and then every -EveryMinutes.
    # For a -WithPerson job, which can do nothing until then (review of PR 249: the supervisor keeps a
    # job in the person's session beside its start-up one, for the services that need their desktop).
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Folder = "Horde",
        [Parameter(Mandatory = $true)][string]$Script,
        [string[]]$Arguments = @(),
        [hashtable]$Environment = @{},
        [Parameter(Mandatory = $true)][string]$HordeHome,
        [string]$Description = "",
        [int]$EveryMinutes = 30,
        [int]$TimeLimitMinutes = 20,
        [switch]$Disabled,
        [switch]$WithPerson,
        [switch]$AtStartup,
        [switch]$AtLogon,
        [switch]$MayOutlastInterval,
        [switch]$TakeOver
    )
    Assert-HordeJobName -Name $Name -Folder $Folder
    if ($AtStartup -and $WithPerson) { throw "a job that runs in the person's own session cannot run at start-up, before anyone has signed in" }
    # -MayOutlastInterval: A JOB THAT ITSELF REFUSES TO RUN TWICE AT ONCE may be given longer than its
    # interval. The rule "stops before its next run" keeps two runs of a job apart by ending the
    # first. The supervisor's pass keeps them apart itself - it holds a lock, and the scheduler starts
    # no second run while one is going - and ending IT at its interval is the harm: a pass ended in
    # the middle of moving a checkout, or between making a process and recording it, leaves exactly
    # the half-done state the supervisor exists to prevent (safety review of the first build, item 6).
    if ($EveryMinutes -lt 1 -or $TimeLimitMinutes -lt 1 -or ($TimeLimitMinutes -gt $EveryMinutes -and -not $MayOutlastInterval)) { throw "a job runs at least every minute, and stops before its next run" }
    foreach ($k in @($Environment.Keys)) { if ("$k" -cnotmatch '\A[A-Z_][A-Z0-9_]*\z') { throw ("not an environment variable name: '" + $k + "'") } }
    # An argument starting with "-" reaches the script as a plain string, never a switch, and the run fails
    # with exit 2 every time it fires (review of #70, NEW-2, measured); refused here, once.
    # PowerShell reads U+2010 to U+2015 and the minus sign U+2212 as "-" too (review of #70).
    $dashes = @([char]0x2D, [char]0x2010, [char]0x2011, [char]0x2012, [char]0x2013, [char]0x2014, [char]0x2015, [char]0x2212)
    foreach ($a in @($Arguments)) { if ("$a".Length -gt 0 -and $dashes -contains "$a"[0]) { throw ("a job argument cannot start with '-': '" + $a + "'") } }
    foreach ($v in @(@($Script, $HordeHome) + @($Arguments) + @($Environment.Values))) { if ("$v" -match "[`r`n]") { throw "a job's script, arguments and environment cannot hold a line break" } }
    $text = $Description + "`n" + $script:HordeJobMarker + "`nhorde-home: " + $HordeHome
    return [pscustomobject]@{ name = $Name; folder = $Folder; script = $Script; arguments = @($Arguments); environment = $Environment; hordeHome = $HordeHome; description = $text; everyMinutes = $EveryMinutes; timeLimitMinutes = $TimeLimitMinutes; lowPriority = $true; disabled = [bool]$Disabled; withPerson = [bool]$WithPerson; takeOver = [bool]$TakeOver; atStartup = [bool]$AtStartup; atLogon = [bool]$AtLogon }
}

function Read-HordeJobMarker {
    # From a job's description: { marked; home }. Marked only when the marker line is there exactly.
    param([string]$Description)
    $lines = @("$Description" -split "`r?`n")
    $home2 = ""
    foreach ($l in $lines) { if ($l.StartsWith("horde-home: ")) { $home2 = $l.Substring(12) } }
    return [pscustomobject]@{ marked = ($lines -ccontains $script:HordeJobMarker); home = $home2 }
}

function New-HordeCollectJob {
    # The collect job: the shipped horde.ps1 of THIS checkout, `metrics collect`, every 30 minutes.
    #
    # THE HOME IS NOT BAKED IN (T-0299, round-1 review). The job runs as the user who registered it, so at each
    # run it resolves the home as every other command does: HORDE_HOME, then the pointer file, then the default.
    # A baked HORDE_HOME would outrank the pointer and keep the old folder after horde home set. The marker still
    # records the home it was registered under, for status and for the check that a re-register is deliberate.
    param([Parameter(Mandatory = $true)][string]$HordeScript, [string]$Name = $script:HordeCollectJobName, [string]$Folder = "Horde", [switch]$Disabled, [switch]$TakeOver)
    $home2 = Get-HordeHome
    return (New-HordeScheduledJob -Name $Name -Folder $Folder -Script $HordeScript -Arguments @("metrics", "collect") -HordeHome $home2 -Disabled:$Disabled -TakeOver:$TakeOver -Description "Horde: summarise new and changed agent transcripts into the metrics store when metrics are enabled. Managed by horde metrics schedule; remove it with horde metrics schedule remove.")
}
