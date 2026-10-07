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

$script:HordeSchedulers = New-Object System.Collections.ArrayList
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
        [switch]$Disabled
    )
    Assert-HordeJobName -Name $Name -Folder $Folder
    if ($EveryMinutes -lt 1 -or $TimeLimitMinutes -lt 1 -or $TimeLimitMinutes -gt $EveryMinutes) { throw "a job runs at least every minute, and stops before its next run" }
    foreach ($k in @($Environment.Keys)) { if ("$k" -cnotmatch '\A[A-Z_][A-Z0-9_]*\z') { throw ("not an environment variable name: '" + $k + "'") } }
    # An argument starting with "-" reaches the script as a plain string, never a switch, and the run fails
    # with exit 2 every time it fires (review of #70, NEW-2, measured); refused here, once.
    # PowerShell reads U+2010 to U+2015 and the minus sign U+2212 as "-" too (review of #70).
    $dashes = @([char]0x2D, [char]0x2010, [char]0x2011, [char]0x2012, [char]0x2013, [char]0x2014, [char]0x2015, [char]0x2212)
    foreach ($a in @($Arguments)) { if ("$a".Length -gt 0 -and $dashes -contains "$a"[0]) { throw ("a job argument cannot start with '-': '" + $a + "'") } }
    foreach ($v in @(@($Script, $HordeHome) + @($Arguments) + @($Environment.Values))) { if ("$v" -match "[`r`n]") { throw "a job's script, arguments and environment cannot hold a line break" } }
    $text = $Description + "`n" + $script:HordeJobMarker + "`nhorde-home: " + $HordeHome
    return [pscustomobject]@{ name = $Name; folder = $Folder; script = $Script; arguments = @($Arguments); environment = $Environment; hordeHome = $HordeHome; description = $text; everyMinutes = $EveryMinutes; timeLimitMinutes = $TimeLimitMinutes; lowPriority = $true; disabled = [bool]$Disabled }
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
    # THE HOME TRAVELS WITH IT, AS DATA. A scheduler starts the job with the user's own environment, not
    # this shell's, so the job sets HORDE_HOME itself, to the home this shell resolves - which is also the
    # home its marker names. How the value reaches the program is the scheduler's business, never a
    # command string built here (review of PR #70, F2: a curly quote closed one).
    param([Parameter(Mandatory = $true)][string]$HordeScript, [string]$Name = $script:HordeCollectJobName, [string]$Folder = "Horde", [switch]$Disabled)
    $home2 = Get-HordeHome
    return (New-HordeScheduledJob -Name $Name -Folder $Folder -Script $HordeScript -Arguments @("metrics", "collect") -Environment @{ HORDE_HOME = $home2 } -HordeHome $home2 -Disabled:$Disabled -Description "Horde: summarise new and changed agent transcripts into the metrics store when metrics are enabled. Managed by horde metrics schedule; remove it with horde metrics schedule remove.")
}
