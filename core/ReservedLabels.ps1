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

function Test-HordeLabelReserved {
    # Is this label one no session may be given? Compared exactly: a label is upper-case by its pattern,
    # and RS1 is another label.
    param($Label)
    return ($Label -is [string] -and (Get-HordeReservedLabels) -ccontains $Label)
}
