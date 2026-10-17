# Mutations of fleet/Hibernate.ps1, `horde fleet hibernate`. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-hibernate.psd1
# Each breaks one rule of who is put to sleep, or when, or how; test\test-fleet-hibernate.ps1 must fail a
# check for every one.
@{
    Target = "fleet\Hibernate.ps1"
    Suite  = "test\test-fleet-hibernate.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "founder-window-shorter"
           Find = '$script:HordeFleetHibernateTypedMinutes = 30'
           Replace = '$script:HordeFleetHibernateTypedMinutes = 28' }
        @{ Name = "fleet-lines-count-as-founder"
           Find = 'if (Test-HordeFleetFleetLine -Text ("" + $t.text)) { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "bom-line-counts-as-founder"
           Find = 'if ($Text.Length -gt 0 -and [int]$Text[0] -eq 0xFEFF) { return $true }'
           Replace = 'if ($false) { return $true }' }
        @{ Name = "master-hibernated"
           Find = 'if (Test-HordeFleetMaster -Candidate $Candidate) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "self-hibernated"
           Find = 'if ($Caller -ne "" -and "" + $Candidate.sessionId -ceq $Caller) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "analyst-hibernated"
           Find = 'if (@($Analysts) -ccontains ("" + $Candidate.sessionId)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "unlabelled-hibernated"
           Find = 'if ("" + $Candidate.label -eq "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "unreadable-transcript-hibernated"
           Find = 'if ($null -eq $Typed -or "" + $Typed.state -cne "known") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "open-question-ignored"
           Find = 'if ($q -gt 0) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "question-label-not-whole-word"
           Find = '$pattern = ''(?<![A-Za-z0-9])Orc\s+'' + [regex]::Escape($Label) + ''(?![A-Za-z0-9])'''
           Replace = '$pattern = ''Orc\s+'' + [regex]::Escape($Label)' }
        @{ Name = "orc-before-its-wargs"
           Find = 'Sort-Object -Property @{ Expression = { $_.depth }; Descending = $true }'
           Replace = 'Sort-Object -Property @{ Expression = { $_.depth }; Descending = $false }' }
        @{ Name = "wargs-not-selected"
           Find = 'foreach ($u in $under) { if (-not $out.Contains($u.candidate)) { [void]$out.Add($u.candidate) } }'
           Replace = 'foreach ($u in @()) { }' }
        @{ Name = "unknown-name-dropped"
           Find = 'throw ("no running, unretired Orc is named "'
           Replace = 'continue; throw ("no running, unretired Orc is named "' }
        @{ Name = "idle-gate-open"
           Find = 'if ($word -cne $pair[1]) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "unreadable-state-is-idle"
           Find = 'if ($null -eq $State -or "" + $State.state -cne "known") { return [pscustomobject]@{ ok = $false;'
           Replace = 'if ($null -eq $State -or "" + $State.state -cne "known") { return [pscustomobject]@{ ok = $true;' }
        @{ Name = "old-parked-file-taken"
           Find = 'if ($at.ToUniversalTime() -lt ([datetime]$Request.askedAt).ToUniversalTime()) {'
           Replace = 'if ($false) {' }
        @{ Name = "exit-sent-twice"
           Find = 'if ($m.exitSent) {'
           Replace = 'if ($false) {' }
        @{ Name = "blocked-box-typed-again"
           Find = 'if ("" + $m.blocked -ne "") { return (& $ans "refused" $m.blocked) }'
           Replace = '' }
        @{ Name = "refused-exit-not-retried"
           Find = '"" + $sent.value.outcome -ceq "refused") { return (& $ans "not-yet"'
           Replace = '"" + $sent.value.outcome -ceq "refused") { return (& $ans "refused"' }
        @{ Name = "park-seam-bypassed"
           Find = '$park = $(if ($null -ne $Deps.PSObject.Properties["Park"]) { $Deps.Park } else {'
           Replace = '$park = $(if ($false) { $Deps.Park } else {' }
        @{ Name = "orc-exits-before-wargs"
           Find = 'if ($waitingFor.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "deadline-doubled"
           Find = '$deadline = (& $Deps.Now).AddMinutes($WaitMinutes)'
           Replace = '$deadline = (& $Deps.Now).AddMinutes($WaitMinutes * 2)' }
        @{ Name = "live-lock-ignored"
           Find = 'if (-not $owner.stale) { throw ("another hibernation is running'
           Replace = 'if ($false) { throw ("another hibernation is running' }
        @{ Name = "unreadable-questions-taken-as-none"
           Find = 'if ($null -eq $q -or "" + $q.state -cne "known") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "unreadable-analyst-taken-as-none"
           Find = 'if ($null -eq $an -or "" + $an.state -cne "known") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "empty-selection-proceeds"
           Find = 'throw ("nothing was hibernated: every session'
           Replace = 'return ("nothing was hibernated: every session' }
        @{ Name = "post-failure-still-waited-on"
           Find = 'if ($null -eq $posted -or "" + $posted.state -cne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "ask-id-random"
           Find = 'return (ConvertTo-HordeTextUuid -Text ("horde-fleet-hibernate/" + $Id + "/" + $SessionId))'
           Replace = 'return ([guid]::NewGuid().ToString())' }
        @{ Name = "no-restore-marker-never-asked"
           Find = 'if ($null -ne $mark) {'
           Replace = 'if ($false) {' }
        @{ Name = "no-restore-marker-wrong-reason"
           Find = '$mk = & $mark $sid "hibernated" (& $Deps.Now)'
           Replace = '$mk = & $mark $sid "parked" (& $Deps.Now)' }
        @{ Name = "no-restore-marker-failure-unsaid"
           Find = 'if ($null -eq $mk -or "" + $mk.state -cne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "last-look-after-the-deadline-dropped"
           Find = 'if ($lastLook.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "last-look-without-the-process"
           Find = '@($recordIds | Where-Object { $_ -cne $sid }) $since (Get-HordeFleetMember $s "process") } catch { $v = $null } }'
           Replace = '@($recordIds | Where-Object { $_ -cne $sid }) $since } catch { $v = $null } }' }
        @{ Name = "park-step-liveness-without-the-process"
           Find = '@($Request.others) $Request.since (Get-HordeFleetMember $Request "process")'
           Replace = '@($Request.others) $Request.since' }
        @{ Name = "last-look-takes-running-for-gone"
           Find = 'if ($null -ne $v -and "" + $v.state -ceq "stopped") { & $markExited $s }'
           Replace = 'if ($null -ne $v) { & $markExited $s }' }
        @{ Name = "sent-exit-not-looked-at-last"
           Find = '-or ($pending.ContainsKey("" + $_.sessionId) -and $pending["" + $_.sessionId].memo.exitSent -eq $true) })'
           Replace = '-or $false })' }
        @{ Name = "unreadable-exit-answer-not-looked-at-last"
           Find = 'if ($step.exitMaybe -eq $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "deadline-kept-once-a-pass-only"
           Find = 'if ((& $Deps.Now) -ge $deadline) { break }'
           Replace = 'if ($false) { break }' }
        @{ Name = "typing-not-looked-at-again"
           Find = '$hit = Get-HordeFleetFounderTyped -Turns @($typed.value) -Since ([datetime]$Request.askedAt)'
           Replace = '$hit = $null' }
        @{ Name = "unreadable-typing-recheck-taken-as-clear"
           Find = 'if ($null -eq $typed -or "" + $typed.state -cne "known") { return (& $ans "not-yet"'
           Replace = 'if ($false) { return (& $ans "not-yet"' }
        @{ Name = "typing-recheck-skipped-without-a-candidate"
           Find = 'if ($null -eq $typedFor -or $null -eq $Deps.PSObject.Properties["Typed"]) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "tier-argument-other-than-2-accepted"
           Find = 'if ($Tier -ne 2) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "tier-1-orc-counts-as-tier-2"
           Find = 'return [bool](($t -is [int] -or $t -is [long]) -and [int]$t -eq 2)'
           Replace = 'return [bool](($t -is [int] -or $t -is [long]) -and [int]$t -ge 1)' }
        @{ Name = "no-tier-counts-as-tier-2"
           Find = 'return [bool](($t -is [int] -or $t -is [long]) -and [int]$t -eq 2)'
           Replace = 'return [bool](($t -is [int] -or $t -is [long] -or $null -eq $t) -and [int]$t -ne 1)' }
        @{ Name = "unknown-orc-counts-as-tier-2"
           Find = 'if (@($Tiers.Keys) -cnotcontains $Label) { return $false }'
           Replace = 'if (@($Tiers.Keys) -cnotcontains $Label) { return $true }' }
        @{ Name = "named-orc-outside-tier-2-not-refused"
           Find = 'if ($off.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "tier-run-chooses-every-orc"
           Find = '-and (Test-HordeFleetOrcInTier2 -Tiers $tierMap -Label ("" + $_.label)) } | ForEach-Object'
           Replace = '-and $true } | ForEach-Object' }
        @{ Name = "unreadable-tiers-taken-as-none"
           Find = 'if ($null -eq $tiers -or "" + $tiers.state -cne "known") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "tier-gate-not-applied-to-an-orc-picked-anyway"
           Find = 'if ("" + $Candidate.role -ceq "orc" -and -not (Test-HordeFleetOrcInTier2 -Tiers $Tiers -Label ("" + $Candidate.label))) {'
           Replace = 'if ($false) {' }
        @{ Name = "wargs-of-a-tier-1-orc-not-held-by-the-gate"
           Find = 'if ("" + $a.role -ceq "orc" -and -not (Test-HordeFleetOrcInTier2 -Tiers $Tiers -Label ("" + $a.label))) {'
           Replace = 'if ($false) {' }
        @{ Name = "orc-slept-with-a-warg-left-running"
           Find = 'if ($null -eq $held -and "" + $c.role -ceq "orc") {'
           Replace = 'if ($false) {' }
        @{ Name = "wargs-slept-under-an-orc-left-running"
           Find = 'if ("" + $a.role -cne "orc") { continue }'
           Replace = 'if ($true) { continue }' }
        @{ Name = "wargs-of-the-caller-orc-held"
           Find = '$_.reason -cne "self" })'
           Replace = '$true })' }
        @{ Name = "stale-marker-kept-on-a-running-chosen-session"
           Find = 'foreach ($l in @(Clear-HordeFleetHibernatedMarker -HostAdapter $Deps.Host -Ids @($ordered | ForEach-Object { "" + $_.sessionId }))) { & $say ("  " + $l) }'
           Replace = 'foreach ($l in @()) { }' }
    )
}
