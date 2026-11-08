# core/WatchTell - how the relay watch (core/RelayWatch.ps1) and the watcher check (core/WatcherHeartbeat.ps1) hand a tell to the warchief
# and count it (T-0391 slice 8). The rule of the task: a Horde sender counts as delivered only on the target session's own TAKEN, and a
# person is told what is KNOWN, no more.
#
# WHY. Both watches handed the text to a Tell tool and counted its ok as "the warchief is told". ok meant the messenger ACCEPTED the mail, so
# an outage whose mail the warchief's session never took was closed as told, and the founder's phone said "the warchief is told by fleet
# mail". Now the Tell tool (cli/AnalystTend.ps1, Send-HordeAnalystWatchTell) marks the notice on the awaiting list BEFORE it posts
# (decisions/NoticeTaken.ps1, used as it is) and answers ok only for POSTED AND WATCHED; the engine's pass says TAKEN and ALARM in the log.
# The watch keeps "posted" in its own state and asks the Taken tool each pass; only "taken" counts as told. A notice given up (the
# messenger holds it for good, or it is a notice-ttl old) is "lost": an ALARM has been said, and nothing is posted again for that event.
# An answer that cannot be had ("unknown") changes nothing: no guess either way.
#
# THE TOOLS (handed in, as everywhere in the watches):
#   Tell   param($Body, $Key, $Gen)  answers { ok; detail; listed; lines } - ok: posted and watched; listed: the mark is on the list now,
#                                    so a not-ok answer with listed set is an UNKNOWN result that may have landed. A fake with only ok works.
#   Taken  param($Key, $Gen)         answers "taken" | "pending" | "lost" | "unknown" for the notice of that key and generation.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

# A notice not taken in a notice-ttl is given up by the engine (decisions/NoticeTaken.ps1, 7 days); a watch that has waited that long stops waiting.
$script:HordeWatchTellTtlSeconds = 604800

function Send-HordeWatchTell {
    # Hand one text to the Tell tool under (-Key, -Gen): { ok; state; line }. state: "posted" (accepted and watched), "maybe" (not accepted but
    # the result is unknown and the mark is kept: it may have landed) or "none" (not posted). A tool that is $null tells nobody.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Prefix, [Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Who, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][long]$Gen)
    if ($null -eq $Tools["Tell"]) { return [pscustomobject]@{ ok = $false; state = "none"; line = ($Prefix + ": would tell " + $Who + ", but telling is off") } }
    $r = $null
    try { $r = @(& $Tools["Tell"] $Text $Key $Gen) | Select-Object -Last 1 } catch { $r = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
    $ok = ($null -ne $r -and $r.ok -eq $true)
    $listed = ($null -ne $r -and $null -ne $r.PSObject.Properties["listed"] -and $r.listed -eq $true)
    $state = $(if ($ok) { "posted" } elseif ($listed) { "maybe" } else { "none" })
    $more = @()
    if ($null -ne $r -and $null -ne $r.PSObject.Properties["lines"]) { $more = @(@($r.lines) | ForEach-Object { "" + $_ } | Where-Object { $_ -ne "" }) }
    $tail = $(if ($more.Count -gt 0) { " | " + ($more -join " | ") } else { "" })
    $head = $(if ($state -ceq "posted") { "posted to " + $Who + " (counted as told only when his session takes it)" }
              elseif ($state -ceq "maybe") { "may have posted to " + $Who + " (the result is unknown; it is watched) - " + $(if ($null -ne $r) { "" + $r.detail } else { "no answer" }) }
              else { "could not tell " + $Who + ": " + $(if ($null -ne $r) { "" + $r.detail } else { "no answer" }) })
    return [pscustomobject]@{ ok = $ok; state = $state; line = ($Prefix + ": " + $head + $tail) }
}

function Get-HordeWatchTellTaken {
    # Has the warchief's session taken the notice of (-Key, -Gen)? "taken", "pending" (still awaited), "lost" (given up: the tool says so, or it
    # was posted a notice-ttl ago at -PostedAt) or "unknown" (no tool, or no answer: nothing is guessed).
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][long]$Gen, $PostedAt, [Parameter(Mandatory = $true)][datetime]$Now)
    $a = "unknown"
    if ($null -ne $Tools["Taken"]) { try { $a = "" + (@(& $Tools["Taken"] $Key $Gen) | Select-Object -Last 1) } catch { $a = "unknown" } }
    if ($a -ceq "taken") { return "taken" }
    if ($a -ceq "lost") { return "lost" }
    if ($PostedAt -is [datetime] -and ($Now.ToUniversalTime() - ([datetime]$PostedAt).ToUniversalTime()).TotalSeconds -ge $script:HordeWatchTellTtlSeconds) { return "lost" }
    if ($a -ceq "pending") { return "pending" }
    return "unknown"
}

function Get-HordeWatchTellWords {
    # PURE. What a phone is told of the warchief's notice, from Send-HordeWatchTell's state: only what is known.
    param([Parameter(Mandatory = $true)][string]$State)
    if ($State -ceq "posted") { return "A notice to the warchief was posted and is being watched for its taking." }
    if ($State -ceq "maybe") { return "A notice to the warchief may have been posted; the watch cannot tell." }
    return "A notice to the warchief was not posted."
}
