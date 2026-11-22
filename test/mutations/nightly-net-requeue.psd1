# Mutations of tools/NightlyNet.ps1 for the queue of the suite phase (T-0491): a unit whose gate ran nothing is tried
# again once, and that second try waits for every repo's first pass (T-0504). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-net-requeue.psd1
# test\test-nightly-net.ps1 must fail for every one of them.
@{
    Target = "tools\NightlyNet.ps1"
    Suite  = "test\test-nightly-net.ps1"
    Mutations = @(
        @{ Name = "suite-not-sent-back"
           Find = 'if ($v -ceq "unrun" -and (Test-HordeNightlySlotLost $script:LastSlotRun)'
           Replace = 'if ($false -and (Test-HordeNightlySlotLost $script:LastSlotRun)' }
        @{ Name = "pytest-all-not-sent-back"
           Find = 'if ((Test-HordeNightlySlotLost $r) -and -not $Retries -and -not $Ctx.requeued.ContainsKey($u))'
           Replace = 'if ($false -and -not $Retries -and -not $Ctx.requeued.ContainsKey($u))' }
        @{ Name = "pytest-all-sent-back-never-counted"
           Find = 'if ($Ctx.requeued.ContainsKey("pytest-all") -and -not $Ctx.pytestDecided)'
           Replace = 'if ($false)' }
        @{ Name = "second-try-right-behind-its-own-repo"
           Find = 'foreach ($c in $ctxs) { Invoke-NightlyPhaseOne -Ctx $c -Cutoff $suiteCutoff -RunCutoff $cutoff }'
           Replace = 'foreach ($c in $ctxs) { Invoke-NightlyPhaseOne -Ctx $c -Cutoff $suiteCutoff -RunCutoff $cutoff; Invoke-NightlyPhaseOne -Ctx $c -Cutoff $suiteCutoff -RunCutoff $cutoff -Retries; $c.later.Clear() }' }
        @{ Name = "second-tries-never-run"
           Find = 'foreach ($c in $ctxs) { Invoke-NightlyPhaseOne -Ctx $c -Cutoff $suiteCutoff -RunCutoff $cutoff -Retries }'
           Replace = '$null = $ctxs' }
        @{ Name = "units-with-no-verdict-never-counted"
           Find = 'foreach ($c in $ctxs) { Complete-NightlyUnrun $c; Complete-NightlyCompare $c }'
           Replace = 'foreach ($c in $ctxs) { Complete-NightlyCompare $c }' }
    )
}
