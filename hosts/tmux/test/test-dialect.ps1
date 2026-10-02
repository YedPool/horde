# THE SHARED COMMAND LANGUAGE'S DATA (hosts plan step 5; hosts decision 3 of 2026-09-30)
#
# hosts/tmux/Dialect.ps1 is the one file another host imports (tools/HostNames.ps1, THE ONE CROSS-HOST
# IMPORT). This suite holds what step 5 puts in it: the environment variables of the language, handed
# out as data, so that an importing host can scrub them without spelling them. Each of them contains
# this host's name, which is why the importer must not spell them: the name scan matches substrings.
# The field lists, target syntax and send-keys escaping arrive with hosts plan step 6.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "hosts\tmux\Dialect.ps1")
. (Join-Path $root "tools\HostNames.ps1")

Write-Host ""
Write-Host "--- the dialect's environment variables, as data ---" -ForegroundColor Cyan

# EXACTLY these two, in this order, case and all. The hosts research (2026-09-30) measured both: a
# bare client inside a pane follows TMUX to that pane's server, and TMUX_PANE names the pane.
# hosts/tmux/test/Isolation.ps1 removes exactly these two from every child it starts (with WSLENV,
# which is WSL's and not the language's).
$envNames = @(Get-HordeMuxDialectEnvNames)
Check (($envNames -join ",") -ceq "TMUX,TMUX_PANE") ("the dialect's environment variables are TMUX and TMUX_PANE, exactly (" + ($envNames -join ",") + ")")

# WHY THIS IS DATA. Every name contains a name hosts/tmux/names.txt declares, so a file outside this
# folder that spelled one would be a mention of this host. The control reads the real names.txt
# through the shipped parser, so a renamed declaration turns this red rather than passing vacuously.
$declared = @()
foreach ($r in (Read-HordeHostTable -Path (Join-Path $root "hosts\tmux\names.txt"))) {
    $pn = ConvertTo-HordePortName $r
    if (-not $pn.problem) { $declared += $pn.name }
}
Check ($declared.Count -ge 1) ("CONTROL: hosts/tmux/names.txt declares at least one usable name (" + $declared.Count + ")")
foreach ($n in $envNames) {
    Check ((Get-HordeMentionSpans -Text $n -Names $declared).Count -ge 1) ("the variable " + $n + " is a mention of this host, which is why an importer asks for it instead of spelling it")
}

Complete-HordeSuite -Success "the shared dialect hands out its environment variables as data"
