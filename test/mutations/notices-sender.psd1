# Mutations of the sender proof of `horde notify` (notices/Sender.ps1): no session may send as another. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\notices-sender.psd1
# test\test-notices.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "notices\Sender.ps1"
    Suite  = "test\test-notices.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-claim-is-believed"
           Find = '    $up = Test-HordeNoticeAncestor -Table $Processes.value -Self $Self -Ancestor ([int]$pidAnswer.value)'
           Replace = '    $up = [pscustomobject]@{ ok = $true; reason = "" }' }
        @{ Name = "a-later-process-is-taken-for-a-parent"
           Find = 'if ($null -eq $parent.created -or $null -eq $child.created -or $parent.created -gt $child.created) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-process-not-verified-running-counts"
           Find = 'if (@($verified | Where-Object { "$_" -ieq $sid }).Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-session-may-take-a-services-form"
           Find = 'if (Test-HordeNoticeServiceForm -Label $label) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-non-ascii-label-is-shown-as-itself"
           Find = 'if ($Label -cmatch ''[^\x20-\x7E]'') { return "a session" }'
           Replace = 'if ($false) { return "a session" }' }
        @{ Name = "the-gate-lets-latin-1-through"
           Find = 'if ($Label -cmatch ''[^\x20-\x7E]'') { return "a session" }'
           Replace = 'if ($Label -cmatch ''[^\x20-\xFF]'') { return "a session" }' }
        @{ Name = "three-does-not-read-as-e"
           Find = '    $map[''3''] = ''e'''
           Replace = '' }
        @{ Name = "l-pipe-and-bang-do-not-read-as-i"
           Find = 'foreach ($c in ''|'', ''!'', ''1'', ''l'') { $map["$c"] = ''i'' }'
           Replace = 'foreach ($c in ''1'') { $map["$c"] = ''i'' }' }
        @{ Name = "one-does-not-read-as-i"
           Find = 'foreach ($c in ''|'', ''!'', ''1'', ''l'') { $map["$c"] = ''i'' }'
           Replace = 'foreach ($c in ''|'', ''!'', ''l'') { $map["$c"] = ''i'' }' }
        @{ Name = "five-does-not-read-as-s"
           Find = 'foreach ($c in ''$'', ''5'') { $map["$c"] = ''s'' }'
           Replace = 'foreach ($c in ''$'') { $map["$c"] = ''s'' }' }
        @{ Name = "leading-lookalikes-use-up-the-edit"
           Find = 'foreach ($v in @($low, ($low -replace ''^[^a-z]+'', ''''), ($low -replace ''[^a-z]'', ''''))) {'
           Replace = 'foreach ($v in @($low, ($low -replace ''[^a-z]'', ''''))) {' }
        @{ Name = "a-lookalike-between-every-letter-passes"
           Find = 'foreach ($v in @($low, ($low -replace ''^[^a-z]+'', ''''), ($low -replace ''[^a-z]'', ''''))) {'
           Replace = 'foreach ($v in @($low, ($low -replace ''^[^a-z]+'', ''''))) {' }
        @{ Name = "repeated-letters-count-twice"
           Find = 'return [regex]::Replace($sb.ToString(), ''(.)\1+'', ''$1'')'
           Replace = 'return $sb.ToString()' }
        @{ Name = "a-swap-of-two-letters-is-two-edits"
           Find = '        return ($i + 1 -lt $A.Length -and $A[$i] -ceq $B[$i + 1] -and $A[$i + 1] -ceq $B[$i] -and $A.Substring($i + 2) -ceq $B.Substring($i + 2))'
           Replace = '        return $false' }
        @{ Name = "slash-v-does-not-read-as-v"
           Find = '$low = $Label.ToLowerInvariant().Replace(''\/'', ''v'')'
           Replace = '$low = $Label.ToLowerInvariant()' }
        @{ Name = "dollar-and-five-do-not-read-as-s"
           Find = 'foreach ($c in ''$'', ''5'') { $map["$c"] = ''s'' }'
           Replace = 'foreach ($c in ''5'') { $map["$c"] = ''s'' }' }
        @{ Name = "brackets-and-paren-do-not-read-as-c"
           Find = 'foreach ($c in ''('', ''<'', ''['', ''{'') { $map["$c"] = ''c'' }'
           Replace = '' }
        @{ Name = "u-does-not-read-as-v"
           Find = '    $map[''u''] = ''v'''
           Replace = '' }
        @{ Name = "one-edit-from-service-is-allowed"
           Find = 'if ($sk.Length -ge $n -and (Test-HordeWithinOneEdit -A $sk.Substring(0, $n) -B "service")) { return $true }'
           Replace = 'if ($sk.Length -ge $n -and $sk.Substring(0, $n) -ceq "service") { return $true }' }
        @{ Name = "an-added-letter-is-not-an-edit"
           Find = 'foreach ($n in 6, 7, 8) {'
           Replace = 'foreach ($n in 6, 7) {' }
        @{ Name = "a-missing-letter-is-not-an-edit"
           Find = 'foreach ($n in 6, 7, 8) {'
           Replace = 'foreach ($n in 7, 8) {' }
        @{ Name = "an-invisible-character-is-part-of-the-label"
           Find = '$label = (Remove-HordeNoticeInvisible -Text $label).Trim()'
           Replace = '$label = $label.Trim()' }
        @{ Name = "the-registry-label-is-ignored"
           Find = 'if ($l.state -ceq "known" -and $l.value -is [string]) { $label = $l.value.Trim(); if ($label -cne "") { $labelSource = "registry" } }'
           Replace = 'if ($false) { $label = $l.value.Trim() }' }
        @{ Name = "a-session-with-no-name-sends"
           Find = 'if ($label -ceq "") { return (& $no ('
           Replace = 'if ($label -ceq "") { $label = "?" }; if ($false) { return (& $no (' }
        @{ Name = "no-parent-pid-is-the-session"
           Find = 'if ($null -eq $up -or $up.Value -isnot [int] -or $up.Value -le 0) {'
           Replace = 'if ($null -eq $up) { return [pscustomobject]@{ ok = $true; reason = "" } }; if ($up.Value -isnot [int] -or $up.Value -le 0) {' }
    )
}
