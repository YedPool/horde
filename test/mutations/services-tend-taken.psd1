# Mutations of the supervisor's pass (cli/ServicesTend.ps1), T-0391 slice 6: a notice the teller took is posted, not "told"; it leaves the
# state file only when taken by the teller; the look at the awaiting list is made every pass, its lines are the pass's lines, and its
# failure is its own.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\services-tend-taken.psd1
# test\test-services-tell-taken.ps1 must fail for every one.
@{
    Target = "cli\ServicesTend.ps1"
    Suite  = "test\test-services-tell-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # The teller's own lines are dropped.
        @{ Name = "services-tend-teller-lines-dropped"
           Find = 'if ($null -ne $answer -and $null -ne $answer.PSObject.Properties["lines"]) { foreach ($l in @($answer.lines)) { [void]$lines.Add("" + $l) } }'
           Replace = '$null = 0' }
        # A post is claimed as told again.
        @{ Name = "services-tend-posted-said-as-told"
           Find = '"posted (" + $n.kind + "): "'
           Replace = '"told (" + $n.kind + "): "' }
        # A notice nobody took is forgotten from the state file.
        @{ Name = "services-tend-untold-forgotten"
           Find = '$kept = @($s.notices | Where-Object { $told -cnotcontains $_.id })'
           Replace = '$kept = @()' }
        # The look at the awaiting list is never made.
        @{ Name = "services-tend-look-never-made"
           Find = 'if ($null -ne $Tools["TellTaken"]) {'
           Replace = 'if ($false) {' }
        # The look's lines are made and dropped.
        @{ Name = "services-tend-look-lines-dropped"
           Find = 'foreach ($l in @(& $Tools["TellTaken"] $HordeHome $policy)) { [void]$lines.Add("" + $l) }'
           Replace = 'foreach ($l in @(& $Tools["TellTaken"] $HordeHome $policy)) { }' }
        # A look that throws takes the pass with it.
        @{ Name = "services-tend-look-failure-escapes"
           Find = 'catch { [void]$lines.Add("services: the awaiting notices could not be asked: " + (Protect-HordeServiceText $_.Exception.Message)) }'
           Replace = 'catch { throw }' }
    )
}
