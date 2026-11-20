# Mutations of tools/NightlyNet.ps1 for the queue of the suite phase (T-0491): a unit whose gate ran nothing goes back
# on the end of the night's queue once. Run:
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
           Find = 'if ((Test-HordeNightlySlotLost $r) -and -not $requeued.ContainsKey($u))'
           Replace = 'if ($false -and -not $requeued.ContainsKey($u))' }
        @{ Name = "pytest-all-sent-back-never-counted"
           Find = 'if ($requeued.ContainsKey("pytest-all") -and -not $pytestDecided)'
           Replace = 'if ($false)' }
        @{ Name = "sent-back-to-the-front"
           Find = '$requeued[$u] = $true; $queue.Add($u); Write-NightlyNetLine ($Ctx.repo + " " + $u + " gave up waiting for the slot (exit " + $r.code'
           Replace = '$requeued[$u] = $true; $queue.Insert($qi + 1, $u); Write-NightlyNetLine ($Ctx.repo + " " + $u + " gave up waiting for the slot (exit " + $r.code' }
    )
}
