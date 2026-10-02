# core/Schedule - one recurring job, defined once and handed to whichever scheduler this machine has.
#
# WHY A SEAM. `horde metrics collect` runs every 30 minutes (plan step M2). On Windows that is a Task
# Scheduler task; a Linux host will want cron or a systemd timer. The job - what runs, how
# often, at what priority, for how long at most - is defined here, and a SCHEDULER turns it into the
# platform's own form. A scheduler is a file under core/schedule/ that registers itself with
# Register-HordeScheduler: { name; available; install; remove; status }. A new platform is a new file.
#
# ONE JOB, BY NAME. Every operation names the job, so a test acts only on the job it created under a
# name of its own (CONTRIBUTING 9), never on the real one.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1.

$script:HordeSchedulers = New-Object System.Collections.ArrayList
$script:HordeCollectJobName = "Horde metrics collect"

function Register-HordeScheduler {
    # -Available answers whether this scheduler works on this machine. -Install takes a job
    # (New-HordeScheduledJob) and returns nothing; -Remove takes a name and returns whether a job was
    # removed; -Status takes a name and returns an answer: known { installed; enabled; state; everyMinutes;
    # lastRunAt; lastResult; nextRunAt; program; arguments }, absent when no such job exists.
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

function New-HordeScheduledJob {
    # The job, as a platform-neutral definition. -Program and -Arguments are what runs; it runs as the
    # current user, every -EveryMinutes, at low priority, stopped after -TimeLimitMinutes, never two at
    # once, and not at all when -Disabled.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Program,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [string]$Description = "",
        [int]$EveryMinutes = 30,
        [int]$TimeLimitMinutes = 20,
        [switch]$Disabled
    )
    if ($Name -notmatch '\A[A-Za-z0-9][A-Za-z0-9 ._-]{0,100}\z') { throw ("not a job name Horde will use: '" + $Name + "'") }
    if ($EveryMinutes -lt 1 -or $TimeLimitMinutes -lt 1 -or $TimeLimitMinutes -gt $EveryMinutes) { throw "a job runs at least every minute, and stops before its next run" }
    return [pscustomobject]@{ name = $Name; program = $Program; arguments = $Arguments; description = $Description; everyMinutes = $EveryMinutes; timeLimitMinutes = $TimeLimitMinutes; lowPriority = $true; disabled = [bool]$Disabled }
}

function New-HordeCollectJob {
    # The collect job: the shipped horde.ps1 of THIS checkout, `metrics collect`, every 30 minutes.
    #
    # THE HOME TRAVELS WITH IT. A scheduler starts the job with the user's own environment, not this
    # shell's, so a HORDE_HOME set here would not reach it and the job would collect into another home.
    # When HORDE_HOME is set, the job sets it itself; a path that cannot be quoted safely is refused.
    param([Parameter(Mandatory = $true)][string]$HordeScript, [string]$Name = $script:HordeCollectJobName, [switch]$Disabled)
    $setHome = "$env:HORDE_HOME".Trim()
    foreach ($p in @($HordeScript, $setHome)) { if ($p -match "['""`r`n]") { throw ("a path with a quote or a line break cannot be given to the scheduler: " + $p) } }
    $args2 = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden "
    if ($setHome -ne "") { $args2 += "-Command ""`$env:HORDE_HOME = '" + $setHome + "'; & '" + $HordeScript + "' metrics collect; exit `$LASTEXITCODE""" }
    else { $args2 += "-File """ + $HordeScript + """ metrics collect" }
    return (New-HordeScheduledJob -Name $Name -Program "powershell.exe" -Arguments $args2 -Disabled:$Disabled -Description "Horde: summarise new and changed agent transcripts into the metrics store when metrics are enabled. Managed by horde metrics schedule; remove it with horde metrics schedule remove.")
}
