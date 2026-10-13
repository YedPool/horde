# core/ReservedLabels - the labels no session may ever be given.
#
# WHY. A label is how the fleet's people and sessions name a session at a glance: A, B, C1. Some mail is
# not from a session at all - the restore source's resume mail and stall notice (core/RestoreSource.ps1),
# and what the wake watcher tells the warchief (core/WakeTell.ps1) - and a messenger that names senders
# by label needs one for each. That mail wears RS, or WW. If a real session
# could be given RS too, a line "from RS" would be a machine's or a session's and nobody could tell
# which; worse, a session told "RS says resume" might answer RS. So the label is reserved here, in one
# list, and refused wherever Horde takes a label for a session (review of PR #208):
#   - `horde session spawn -Label` (cli/commands/session.ps1): the hub hands a label to a request there,
#     so a reserved one never leaves the hub;
#   - Format-HordeSessionName (core/AgentLaunch.ps1): a node never names a session with one, whatever
#     hub asked.
# THIS LIST IS A COPY, AND THE OTHER COPY IS NOT IN THIS REPOSITORY. The fleet tool keeps its own:
# wezfleet's lib\Registry.ps1, $script:WfReservedLabels, which it refuses to give a session and prints
# with `wezfleet labels reserved [-Json]` (its main, 2026-10-13). Two lists kept by hand in two
# repositories drift, and a label reserved in one and not in the other is a label a session can be
# given after all. So the two are compared, both ways, wherever the fleet's can be asked for:
# test\test-waker-conformance.ps1 asks each waker for the labels its fleet reserves
# (wakers/Port.ps1, Get-HordeWakerReservedLabels) and fails on any difference
# (Compare-HordeReservedLabels, below). Where it cannot be asked - an older fleet tool, or none to be
# found - that is said, as NOT COMPARED: it is never taken for equal. CHANGE THE TWO TOGETHER.
#
# WHAT THIS CANNOT REACH: a fleet run by the tool Horde is replacing allocates its labels in that tool,
# outside this repository. The reservation holds there only when that tool refuses the label too.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

function Get-HordeReservedLabels {
    # Every label that is not a session's to wear, with whose it is.
    #   RS  the restore source (core/RestoreSource.ps1, the setting fromLabel)
    #   WW  the wake watcher's tell sender (core/WakeTell.ps1, the setting fromLabel)
    #   SV  reserved by the fleet's own mail for a sender that is no session (the fleet tool reserves
    #       RS, WW and SV together, as of its main 5b281ed, 2026-10-13); listed here so that Horde never
    #       gives it to a session either, and the wake watcher never nudges one that wears it
    return @("RS", "WW", "SV")
}

function Compare-HordeReservedLabels {
    # Horde's list against another's - a fleet tool's own: { equal; ours; theirs; onlyOurs; onlyTheirs }.
    # Compared as Test-HordeLabelReserved compares, by the exact letters; the order of a list and a
    # label written twice in it are no difference. equal only when neither has a label the other lacks.
    param($Theirs)
    $ours = @(Get-HordeReservedLabels)
    $them = New-Object System.Collections.ArrayList
    foreach ($l in @($Theirs)) { if ($null -ne $l -and $them -cnotcontains "$l") { [void]$them.Add("$l") } }
    $onlyOurs = @($ours | Where-Object { $them -cnotcontains $_ })
    $onlyTheirs = @($them | Where-Object { $ours -cnotcontains $_ })
    return [pscustomobject]@{ equal = ($onlyOurs.Count -eq 0 -and $onlyTheirs.Count -eq 0); ours = $ours; theirs = $them.ToArray(); onlyOurs = $onlyOurs; onlyTheirs = $onlyTheirs }
}

function Test-HordeLabelReserved {
    # Is this label one no session may be given? Compared exactly: a label is upper-case by its pattern,
    # and RS1 is another label.
    param($Label)
    return ($Label -is [string] -and (Get-HordeReservedLabels) -ccontains $Label)
}
