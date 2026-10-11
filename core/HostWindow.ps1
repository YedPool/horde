# core/HostWindow.ps1 - the port through which a terminal's adapter says which native window a session
# is shown in, so that nothing outside hosts/<name>/ names a terminal to ask (CONTRIBUTING 14).
#
# WHY (window attach design, 2026-10-06): a companion window stands beside a session's terminal
# window, and "which window is that" is knowledge about one terminal program - how it lists its panes,
# what its windows are called. Each host that can answer has hosts/<name>/Window.ps1, which registers
# one block here when it is dot-sourced, as hosts/<name>/Act.ps1 registers with core/HostAct.ps1, and
# is found by folder, never by name.
#
#   Find  param($Seat) -> a core/Tristate.ps1 answer
#         $Seat is { pane; instance } as core/SessionSeat.ps1 read them from the session's record, and
#         only once it has verified that the session is still running there: text only the session's
#         own terminal understands. known { handle; ... } when exactly one window is
#         proven to be the one showing that pane, handle being its native window handle; unknown, with
#         the reason, in every other case - a seat that is not this host's, a terminal that is not
#         running, a pane it does not list, two windows that cannot be told apart.
#
#   Settings  param($HordeHome) -> a core/ModuleSettings.ps1 answer { state; values; findings; path }
#         OPTIONAL, for a finder that reads a settings file of its own. A caller that must refuse to
#         start on a refused file (decisions/Window.ps1, before it opens anything) cannot name that
#         file, since its name names the terminal; it asks Get-HordeSessionWindowSettingsState, and is
#         told the finders' refusals in their own words. Without it a refused finder file only made the
#         companion window stand free with the finder's reason, on settings nobody chose.
#
# A FINDER NEVER GUESSES, AND NEITHER DOES THIS FILE. Each finder is asked; a known answer whose handle
# is not a whole number above zero is not an answer; the first proven window is the one; and when none
# is, the caller is told every finder's reason. A finder only READS: nothing here, and nothing a
# finder does, moves, types into or closes anything.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")

if ($null -eq (Get-Variable -Name HordeHostWindowFinders -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeHostWindowFinders = New-Object System.Collections.ArrayList }

function Register-HordeHostWindowFinder {
    # Called by hosts/<name>/Window.ps1 when it is dot-sourced. Re-registering a name replaces it.
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][scriptblock]$Find, [scriptblock]$Settings = $null)
    if ($Name -cnotmatch '\A[a-z][a-z0-9-]*\z') { throw ("a host name is lowercase letters, digits and hyphens: '" + $Name + "'") }
    foreach ($f in @($script:HordeHostWindowFinders)) { if ($f.name -ceq $Name) { $script:HordeHostWindowFinders.Remove($f) } }
    [void]$script:HordeHostWindowFinders.Add([pscustomobject]@{ name = $Name; find = $Find; settings = $Settings })
}

function Get-HordeHostWindowFinderFiles {
    # The finder files, found by folder: hosts/<name>/Window.ps1. The CALLER dot-sources each at its own
    # scope, so the adapter's helpers stay visible to the block it registers.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $hosts = Join-Path $Root "hosts"
    if (-not (Test-Path -LiteralPath $hosts -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $hosts -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Window.ps1" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Find-HordeSessionWindow {
    # The native window showing the session at -Seat, as an answer: known { handle; host; detail }, or
    # unknown with every finder's reason (header).
    param($Seat)
    if ($null -eq $Seat -or "$($Seat.pane)".Trim() -eq "" -or "$($Seat.instance)".Trim() -eq "") { return (New-HordeUnknown -Reason "no pane and terminal were given, so there is no window to look for") }
    if ($script:HordeHostWindowFinders.Count -eq 0) { return (New-HordeUnknown -Reason "no terminal adapter that can find a session's window is loaded") }
    $said = New-Object System.Collections.ArrayList
    foreach ($finder in @($script:HordeHostWindowFinders)) {
        $answer = $null
        try { $answer = & $finder.find $Seat } catch { [void]$said.Add($finder.name + ": its finder failed: " + $_.Exception.Message); continue }
        $answer = @($answer) | Select-Object -Last 1
        if (-not (Test-HordeAnswer $answer)) { [void]$said.Add($finder.name + ": its finder did not answer"); continue }
        if ($answer.state -cne "known") { [void]$said.Add($finder.name + ": " + $answer.reason); continue }
        $handle = $answer.value.handle
        if (($handle -isnot [int] -and $handle -isnot [long]) -or [long]$handle -le 0) { [void]$said.Add($finder.name + ": it named a window with no usable handle"); continue }
        return (New-HordeKnown -Value ([pscustomobject]@{ handle = [long]$handle; host = $finder.name; detail = "$($answer.value.detail)" }))
    }
    return (New-HordeUnknown -Reason ($said -join "; "))
}

function Get-HordeSessionWindowSettingsState {
    # The loaded finders' own settings under -HordeHome, as one answer { state; findings; files }:
    # refused when any finder's are, with every finding of each in the order the finders stand (the
    # settings module's sentences, which name the file and the key; a reader that fails or does not
    # answer is said under its host's name); otherwise read when any finder read a file, defaults when
    # none did, and none when no loaded finder declares settings. files is every path a finder said it
    # reads. Only READS: nothing is made, and no terminal is asked.
    param([string]$HordeHome = "")
    $found = New-Object System.Collections.ArrayList
    $files = New-Object System.Collections.ArrayList
    $states = New-Object System.Collections.ArrayList
    foreach ($finder in @($script:HordeHostWindowFinders)) {
        if ($null -eq $finder.settings) { continue }
        $given = $null
        try { $given = & $finder.settings $HordeHome } catch { [void]$states.Add("refused"); [void]$found.Add($finder.name + ": reading its finder's settings failed: " + $_.Exception.Message); continue }
        $given = @($given) | Select-Object -Last 1
        $state = ""
        if ($given -is [System.Management.Automation.PSCustomObject] -and $null -ne $given.PSObject.Properties["state"]) { $state = "" + $given.state }
        if (@("defaults", "read", "refused") -cnotcontains $state) { [void]$states.Add("refused"); [void]$found.Add($finder.name + ": its finder's settings did not answer"); continue }
        [void]$states.Add($state)
        if ($null -ne $given.PSObject.Properties["path"] -and "$($given.path)" -ne "") { [void]$files.Add("" + $given.path) }
        if ($state -ceq "refused") {
            $said = @()
            if ($null -ne $given.PSObject.Properties["findings"]) { $said = @($given.findings | ForEach-Object { "" + $_ } | Where-Object { $_ -ne "" }) }
            if ($said.Count -eq 0) { $said = @($finder.name + ": its finder's settings are refused, and say no reason") }
            foreach ($f in $said) { [void]$found.Add($f) }
        }
    }
    $overall = "none"
    if ($states -ccontains "refused") { $overall = "refused" } elseif ($states -ccontains "read") { $overall = "read" } elseif ($states.Count -gt 0) { $overall = "defaults" }
    return [pscustomobject]@{ state = $overall; findings = [string[]]@($found); files = [string[]]@($files) }
}
