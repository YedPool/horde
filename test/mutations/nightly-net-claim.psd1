# Mutations of tools/NightlyNet.ps1 for where the net's first claim on the heavy slot ends (T-0447). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-net-claim.psd1
# Each releases the claim too early; test\test-nightly-net.ps1 must fail for every one of them.
@{
    Target = "tools\NightlyNet.ps1"
    Suite  = "test\test-nightly-net.ps1"
    Mutations = @(
        @{ Name = "claim-released-before-bisects"
           Find = 'foreach ($c in $ctxs) { Invoke-NightlyBisect -Ctx $c -Cutoff $cutoff }'
           Replace = 'if ($null -ne $claim) { $claim.Dispose(); $claim = $null }; foreach ($c in $ctxs) { Invoke-NightlyBisect -Ctx $c -Cutoff $cutoff }' }
        @{ Name = "claim-released-before-report"
           Find = 'Write-NightlyNetLine ("report written: " + $file)'
           Replace = 'if ($null -ne $claim) { $claim.Dispose(); $claim = $null; Write-NightlyNetLine "early: first claim on the heavy slot released" }; Write-NightlyNetLine ("report written: " + $file)' }
    )
}
