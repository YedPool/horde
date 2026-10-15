# cli/RelaySessions.ps1 - `horde relay sessions` and `horde relay sessions end`: what this machine holds
# of the founder's unlocked phone sessions (channels/Sessions.ps1), and the command that ends them all.
#
# END ALL IS THE FOUNDER'S BRAKE (design note "Unlocked session", his "yes" to it): a phone left
# unlocked in someone else's hand, or a doubt about any page, and one command at the PC makes every
# session-signed envelope from then on refused (session-ended), so the next answer from any phone asks
# for the passkey again. It is a record (write-once, channels/Sessions.ps1), not a deletion: nothing a
# session already did is undone, and every answer it gave stays in the list with its evidence.
#
# Requires channels/Port.ps1 (and so channels/Sessions.ps1) to be loaded first.

function Get-HordeRelaySessionLines {
    # One line per vouch this machine holds, newest last, each live or why not by this machine's clock;
    # then the idle limit and the last end-all. Lines, never a throw for what the records say.
    param([string]$HordeHome = "", $Now = $null)
    $recs = Read-HordeRelaySessionRecords -HordeHome $HordeHome
    if (-not $recs.ok) { return @("the session records cannot be read, so no phone session is taken until they are repaired: " + $recs.reason) }
    $nowMs = ConvertTo-HordeRelayRecordMs -Time $Now
    $out = New-Object System.Collections.ArrayList
    $idle = $null
    try { $idle = Get-HordeRelaySessionIdleMs -HordeHome $HordeHome } catch { [void]$out.Add("the setting idleMinutes is refused: " + $_.Exception.Message) }
    $byFrom = @{}
    foreach ($e in @($recs.vouches)) { $byFrom[$e.record.by] = $true }
    $n = 0
    foreach ($from in @($byFrom.Keys | Sort-Object)) {
        $st = Get-HordeRelaySessionStatus -HordeHome $HordeHome -From $from -NowMs $nowMs -Records $recs
        if ($null -eq $st) { continue }
        foreach ($v in @($st.vouches)) {
            $e = @($recs.vouches | Where-Object { $_.record.vouchId -ceq $v.vouchId }) | Select-Object -First 1
            if ($null -eq $e) { [void]$out.Add("  passkey " + $from + "  session " + $v.vouchId + "  " + $v.state + " (refused, never held)"); continue }
            $n++
            $until = [System.DateTimeOffset]::FromUnixTimeMilliseconds([long]$e.vouch.notAfter).UtcDateTime.ToString("yyyy-MM-dd HH:mm") + " UTC"
            [void]$out.Add("  passkey " + $from + "  session " + $v.vouchId + "  " + $v.state + "  until " + $until)
        }
    }
    if ($n -eq 0) { [void]$out.Insert(0, "no phone session is held by this machine") }
    else { [void]$out.Insert(0, ("" + $n + " phone session(s) held by this machine (the newest " + 8 + " of each passkey):")) }
    if ($null -ne $idle) { [void]$out.Add("idle limit: " + [long]($idle / 60000) + " minutes (setting idleMinutes, module relay-sessions); no maximum session length") }
    if ([long]$recs.endedAt -gt 0) { [void]$out.Add("every session was last ended at " + [System.DateTimeOffset]::FromUnixTimeMilliseconds([long]$recs.endedAt).UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss") + " UTC") }
    [void]$out.Add("end them all with: horde relay sessions end")
    return @($out.ToArray())
}

function Invoke-HordeRelaySessionsEnd {
    # End every phone session now. Lines; a throw when the record could not be written, so the command
    # exits non-zero and nobody believes the sessions are ended when they are not.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Reason, $Now = $null)
    $r = Stop-HordeRelaySessions -HordeHome $HordeHome -Reason $Reason -Now $Now
    if ($r.state -cne "known") { throw ("the phone sessions were NOT ended: " + $r.reason) }
    return @(("ended every phone session at " + [System.DateTimeOffset]::FromUnixTimeMilliseconds([long]$r.value.endedAt).UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss") + " UTC (" + $r.value.live + " were inside their window)"),
        "the next answer from any phone asks for the passkey again")
}
