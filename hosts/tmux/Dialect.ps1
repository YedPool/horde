# Dialect.ps1 - the command language this host shares with another multiplexer that speaks it.
#
# WHY A FILE OF ITS OWN. Hosts decision 3 (2026-09-30): the language lives here, in this host's
# folder, and a second host that speaks it imports this file as a declared dependency rather than
# copying it. tools/HostNames.ps1 allows exactly that: one allowlist entry per importing file,
# "<path> | import | <why>", lets it name this host once, in the line that dot-sources this file, and
# nowhere else (THE ONE CROSS-HOST IMPORT in that file's header).
#
# WHY NEUTRAL NAMES. Everything an importer calls is named for the language, never for this host, so
# calling it is not a mention. What an importer would otherwise have to spell - this language's
# environment variables, each of which contains this host's name and so matches the name scan as a
# substring - is handed out as data, and only this file spells it.
#
# WHAT IS HERE NOW, and what is not. Hosts plan step 5 puts the environment variables here. The field
# lists and their parser, the target syntax and the literal send-keys escaping arrive with step 6,
# under names neutral to both hosts as well.

function Get-HordeMuxDialectEnvNames {
    # The language's environment variables, which a test harness must remove from every child it
    # starts. MEASURED in the hosts research, 2026-09-30: a client started inside a pane follows TMUX
    # to that pane's server, and TMUX_PANE names the pane; both are what this host's isolation harness
    # removes (hosts/tmux/test/Isolation.ps1). The other multiplexer sets TMUX_PANE as well (its docs,
    # read for the same research; not run here). TMUX_TMPDIR is left out: it is a client setting the
    # harness sets on purpose, and whether the other multiplexer reads it is unmeasured.
    return @("TMUX", "TMUX_PANE")
}
