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
            if ((ConvertTo-HordeHomeComparable $r.home) -ine $want -and -not $seen.ContainsKey($r.how)) {
                $seen[$r.how] = $true
                [void]$lines.Add("task " + $t.TaskPath + $t.TaskName + " is " + $r.how + " the home " + $r.home + ", not " + $Effective + $(if ($r.how -ceq "baked into its action") { " (it keeps that home whatever the pointer says; re-register it)" } else { " (re-register it to follow the new home)" }))
            }
        }
    }
    if ($lines.Count -eq 0) { [void]$lines.Add("tasks: " + @($found).Count + " under \Horde\, none names another home") }
    return [pscustomobject]@{ lines = @($lines.ToArray()); checked = $true }
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
