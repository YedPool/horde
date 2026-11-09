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
    # the result is unknown and the mark is kept: it may have landed), "copy" (accepted, but only as a repost of a copy the messenger already
    # held: no mark is kept for it, so nothing new was posted and nothing is watched - what that copy became says nothing of THIS notice) or
    # "none" (a refusal: not posted, to be tried again) or "off" (no Tell tool: nothing is ever posted). A tool that is $null tells nobody. A tool that answers no "listed" (a stand-in) is taken at its ok.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Prefix, [Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Who, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][long]$Gen)
    if ($null -eq $Tools["Tell"]) { return [pscustomobject]@{ ok = $false; state = "off"; line = ($Prefix + ": would tell " + $Who + ", but telling is off") } }
    $r = $null
    try { $r = @(& $Tools["Tell"] $Text $Key $Gen) | Select-Object -Last 1 } catch { $r = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
    $ok = ($null -ne $r -and $r.ok -eq $true)
    $listed = ($null -ne $r -and $null -ne $r.PSObject.Properties["listed"] -and $r.listed -eq $true)
    $hasListed = ($null -ne $r -and $null -ne $r.PSObject.Properties["listed"])
    $state = $(if ($ok -and $hasListed -and -not $listed) { "copy" } elseif ($ok) { "posted" } elseif ($listed) { "maybe" } else { "none" })
    $more = @()
    if ($null -ne $r -and $null -ne $r.PSObject.Properties["lines"]) { $more = @(@($r.lines) | ForEach-Object { "" + $_ } | Where-Object { $_ -ne "" }) }
    $tail = $(if ($more.Count -gt 0) { " | " + ($more -join " | ") } else { "" })
    $head = $(if ($state -ceq "posted") { "posted to " + $Who + " (counted as told only when his session takes it)" }
              elseif ($state -ceq "copy") { "nothing new was posted to " + $Who + ": the messenger already held a copy of this notice, and none is watched for it" }
              elseif ($state -ceq "maybe") { "may have posted to " + $Who + " (the result is unknown; it is watched) - " + $(if ($null -ne $r) { "" + $r.detail } else { "no answer" }) }
              else { "could not tell " + $Who + ": " + $(if ($null -ne $r) { "" + $r.detail } else { "no answer" }) })
    return [pscustomobject]@{ ok = $ok; state = $state; line = ($Prefix + ": " + $head + $tail) }
}

function Get-HordeWatchTellTaken {
    # Has the warchief's session taken the notice of (-Key, -Gen)? "taken", "pending" (still awaited), "held" (the messenger holds it for good:
    # NOT delivered), "lost" (given up unread by the engine, which says it may still be in his mailbox; or posted a notice-ttl ago at
    # -PostedAt and never answered) or "unknown" (no tool, or no answer: nothing is guessed).
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][long]$Gen, $PostedAt, [Parameter(Mandatory = $true)][datetime]$Now)
    $a = "unknown"
    if ($null -ne $Tools["Taken"]) { try { $a = "" + (@(& $Tools["Taken"] $Key $Gen) | Select-Object -Last 1) } catch { $a = "unknown" } }
    if ($a -ceq "taken") { return "taken" }
    if ($a -ceq "held") { return "held" }
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
    if ($State -ceq "taken") { return "A notice to the warchief was taken by his session." }
    if ($State -ceq "off") { return "A notice to the warchief was not posted: telling is off." }
    if ($State -ceq "copy") { return "Nothing new was posted to the warchief: the messenger already held a copy of this notice." }
    return "A notice to the warchief was not posted."
}

function Get-HordeWatchLostText {
    # PURE. What became of a notice that is no longer watched and was not taken, for a log line: only what is known of it.
    param([Parameter(Mandatory = $true)][ValidateSet("held", "lost")][string]$Why)
    if ($Why -ceq "held") { return "could not be delivered (the messenger holds it for good) and is not taken" }
    return "was not taken in time and is no longer watched (it may still be in his mailbox)"
}

function Get-HordeWatchLostWords {
    # PURE. The same for a phone.
    param([Parameter(Mandatory = $true)][ValidateSet("held", "lost")][string]$Why)
    if ($Why -ceq "held") { return "The warchief's notice could not be delivered: the messenger holds it, and it was not taken." }
    return "The warchief's notice was not taken in time and is no longer watched; it may still be in his mailbox."
}

function Set-HordeWatchLogged {
    # The day's log slot of a daily notice (<MarkPath>.logged) is used: a line was logged at -Now.
    param([Parameter(Mandatory = $true)][string]$MarkPath, [Parameter(Mandatory = $true)][datetime]$Now)
    $logPath = $MarkPath + ".logged"
    try { [System.IO.File]::WriteAllText($logPath, "logged"); [System.IO.File]::SetLastWriteTimeUtc($logPath, $Now) } catch { }
}

function Send-HordeWatchDailyTell {
    # One notice to the warchief at most once a day, on the TAKEN rules, with its state in the small file -MarkPath (the caller's, beside a state
    # file it must not touch): { lines; fresh; logDue; state }. The file holds "posted <day>" while the notice awaits TAKEN, "maybe <day>" while a post
    # whose result was unknown does (it is posted again under the same id), "told" once it was taken, and "held" or "lost" once it was not taken and
    # is no longer watched; its time is when the FIRST post of that day's notice was made (a repost leaves it alone, so the 7-day give-up comes), or
    # when it became told, held or lost. Nothing is posted while one is awaited. A refused post (or no Tell tool at all) leaves no mark and is tried
    # again at the next pass, same id - so the pass's LOG is kept to once a day in a mark of its own, <MarkPath>.logged: logDue says it is time, and
    # a post line that is a repeat (a refusal, an off tool, an unknown result again) is added to lines only then. Lines that tell of a change (posted,
    # taken, held, lost) are always added. -Noun names it in a log line ("STOPPED notice"). fresh: a new post was made (or tried) in this pass.
    # state: what became of the notice - the post's own (Send-HordeWatchTell's) when one was made, else posted, taken, held or lost from the mark,
    # or "" when there is none - for a caller that tells a phone.
    # ("copy", a repost of a copy the messenger already held, is neither posted nor watched and is retried like a refusal: what that earlier copy
    # became is not this notice's, so it is never resolved here.)
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$MarkPath, [Parameter(Mandatory = $true)][string]$Prefix, [Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Noun, [Parameter(Mandatory = $true)][datetime]$Now)
    $lines = New-Object System.Collections.ArrayList
    $logPath = $MarkPath + ".logged"
    $logDue = (-not [System.IO.File]::Exists($logPath)) -or ($Now -ge [System.IO.File]::GetLastWriteTimeUtc($logPath).AddHours(24))
    # (The day's log slot is used up only by a line that is logged: here a repeated post line, below; by the caller, its own line, with
    # Set-HordeWatchLogged. A pass that says nothing leaves the slot for the next thing worth saying.)
    $done = { param([bool]$Fresh, [string]$State) return [pscustomobject]@{ lines = @($lines.ToArray()); fresh = $Fresh; logDue = $logDue; state = $State } }
    $exists = [System.IO.File]::Exists($MarkPath)
    $last = $(if ($exists) { [System.IO.File]::GetLastWriteTimeUtc($MarkPath) } else { [datetime]::MinValue })
    $content = ""
    if ($exists) { try { $content = ("" + [System.IO.File]::ReadAllText($MarkPath)).Trim() } catch { $content = "" } }
    $setMark = { param([string]$Mark, [bool]$KeepTime) try { [System.IO.File]::WriteAllText($MarkPath, $Mark); [System.IO.File]::SetLastWriteTimeUtc($MarkPath, $(if ($KeepTime) { $last } else { $Now })) } catch { } }
    $day = [long][System.Math]::Floor(($Now.ToUniversalTime() - ([datetime]"1970-01-01T00:00:00Z").ToUniversalTime()).TotalDays)
    $again = $false
    if ($content -cmatch '\A(posted|maybe) ([0-9]{1,9})\z') {
        $kind = $Matches[1]; $day = [long]$Matches[2]
        $t = Get-HordeWatchTellTaken -Tools $Tools -Key $Key -Gen $day -PostedAt $last -Now $Now
        if ($t -ceq "taken") { & $setMark "told" $false; [void]$lines.Add($Prefix + ": the warchief's session took the " + $Noun + ": he is told"); return (& $done $false "taken") }
        if ($t -ceq "held" -or $t -ceq "lost") { & $setMark $t $false; [void]$lines.Add($Prefix + ": the " + $Noun + " to the warchief " + (Get-HordeWatchLostText -Why $t)); return (& $done $false $t) }
        if ($kind -ceq "posted") { return (& $done $false "posted") }
        $again = $true
    }
    if (-not $again -and $Now -lt $last.AddHours(24)) {
        return (& $done $false $(if ($content -ceq "told") { "taken" } elseif ($content -ceq "held" -or $content -ceq "lost") { $content } else { "" }))
    }
    $w = Send-HordeWatchTell -Tools $Tools -Prefix $Prefix -Who "the warchief" -Key $Key -Gen $day -Text $Text
    if ($w.state -ceq "posted") { [void]$lines.Add($w.line) }
    elseif ($logDue) { [void]$lines.Add($w.line); Set-HordeWatchLogged -MarkPath $MarkPath -Now $Now }
    if ($w.state -ceq "posted" -or $w.state -ceq "maybe") { & $setMark ($w.state + " " + $day) $again }
    # A repost of a notice whose first post had an unknown result: if the repost is refused, the first copy MAY have landed - what is known is
    # still "maybe", never "not posted" (the stale-episode path says the same).
    return (& $done (-not $again) $(if ($again -and $w.state -cne "posted") { "maybe" } else { $w.state }))
}
