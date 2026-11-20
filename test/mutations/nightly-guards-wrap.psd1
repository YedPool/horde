# Mutations of tools/nightly/guards-wrap.ps1 (T-0347 round 4): the wrapper must PRINT the walk-stopped line, because the net's notice is built from
# what the wrapper prints (the last 10 lines, cut to their last 700 characters). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-guards-wrap.psd1
@{
    Target = "tools\nightly\guards-wrap.ps1"
    Suite  = "test\test-nightly-net.ps1"
    Mutations = @(
        @{ Name = "wrapper-does-not-print-the-stop-line"
           Find = 'if ($stopLine -ne "") { Write-Output ("guards-wrap: " + $stopLine) }'
           Replace = '' }
        @{ Name = "wrapper-prints-the-stop-line-after-the-state"
           Find = 'exit $answer.code'
           Replace = 'if ($stopLine -ne "") { Write-Output ("guards-wrap: " + $stopLine) }; exit $answer.code' }
    )
}
