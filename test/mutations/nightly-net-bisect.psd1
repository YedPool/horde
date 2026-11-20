# Mutations of tools/NightlyNet.ps1 for what the net hands its bisect (T-0465). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-net-bisect.psd1
# test\test-nightly-net.ps1 must fail for every one of them.
@{
    Target = "tools\NightlyNet.ps1"
    Suite  = "test\test-nightly-net.ps1"
    Mutations = @(
        @{ Name = "bisect-not-given-last-nights-tip"
           Find = ' -MaxRuns $budget -Base $Ctx.state.lastTip'
           Replace = ' -MaxRuns $budget' }
    )
}
