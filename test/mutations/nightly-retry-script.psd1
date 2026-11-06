# Mutations of tools/nightly/NightlyRetry.ps1, the restart retry script (T-0397). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-retry-script.psd1
# Each breaks one rule; test\test-nightly-retry.ps1 must fail a named check for every one of them.
@{
    Target = "tools\nightly\NightlyRetry.ps1"
    Suite  = "test\test-nightly-retry.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "marker-never-kept"
           Find = '$fs.Write($bytes, 0, $bytes.Length); $fs.Dispose()'
           Replace = '$fs.Dispose(); Remove-Item -LiteralPath $markerPath' }
        @{ Name = "plan-runs-the-net"
           Find = '    if (-not $d.run -or $Plan) { exit 0 }'
           Replace = '    if (-not $d.run) { exit 0 }' }
        @{ Name = "net-exit-code-dropped"
           Find = '    exit $code'
           Replace = '    exit 0' }
        @{ Name = "nightly-log-line-dropped"
           Find = 'Add-Content -LiteralPath (Join-Path $WorkRoot "nightly.log")'
           Replace = 'Add-Content -LiteralPath (Join-Path $WorkRoot "nightly-x.log")' }
        @{ Name = "net-lock-never-looked-at"
           Find = 'if ([System.Threading.Mutex]::TryOpenExisting($MutexName, [ref]$held)) { $alive = $true; $held.Dispose() }'
           Replace = '$alive = $false' }
        @{ Name = "marker-from-the-wrong-night"
           Find = '$markerPath = Join-Path (Join-Path $WorkRoot "retry") ($night + ".marker")'
           Replace = '$markerPath = Join-Path (Join-Path $WorkRoot "retry") ($now.ToString("yyyy-MM-dd-HH") + ".marker")' }
    )
}
