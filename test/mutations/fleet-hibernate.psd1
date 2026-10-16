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
        @{ Name = "tier-takes-every-orc-with-a-tier"
           Find = '$null -ne $_.tier -and "" + $_.tier -ceq ("" + $Tier)'
           Replace = '$null -ne $_.tier' }
        @{ Name = "tier-without-a-field-is-not-said"
           Find = 'if ($withField.Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "tier-refuses-an-orc-that-is-not-running"
           Find = 'if (@($orcs | Where-Object { "" + $_.label -ceq $letter }).Count -gt 0) { [void]$running.Add($letter) }'
           Replace = '[void]$running.Add($letter)' }
        @{ Name = "tier-and-names-together"
           Find = 'if (@($Names).Count -gt 0 -or $null -ne $Selector) {'
           Replace = 'if ($false) {' }
        @{ Name = "tier-with-an-unreadable-registry-goes-on"
           Find = 'if ($null -eq $rows -or "" + $rows.state -cne "known") {'
           Replace = 'if ($false) {' }
    )
}
