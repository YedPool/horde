# Mutations of tools/nightly/AppCloser.ps1, the nightly net's app closer (T-0331, 2026-10-26). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-apps.psd1
@{
    Target = "tools\nightly\AppCloser.ps1"
    Suite  = "test\test-nightly-apps.ps1"
    Mutations = @(
        @{ Name = "exact-name-becomes-a-prefix"
           Find = 'if ([string]::Equals(("" + $Name), ("" + $n), [System.StringComparison]::OrdinalIgnoreCase)) {'
           Replace = 'if (("" + $Name).StartsWith(("" + $n), [System.StringComparison]::OrdinalIgnoreCase)) {' }
        @{ Name = "every-app-forced"
           Find = '        if ((Test-HordeNightlyAppName -Name $x.name -Names $ForceNames) -eq "") { continue }'
           Replace = '' }
        @{ Name = "busy-pc-taken-as-idle"
           Find = ' -or [int]$Idle.seconds -lt $NeedSeconds) { return "busy" }'
           Replace = ') { return "busy" }' }
        @{ Name = "unknown-input-taken-as-idle"
           Find = 'if ($null -eq $Idle -or ("" + $Idle.state) -cne "known" -or'
           Replace = 'if ($null -eq $Idle -or' }
        @{ Name = "retry-time-ignored"
           Find = '    if ($Now -lt $NextTry) { return "wait" }'
           Replace = '' }
        @{ Name = "dry-run-acts"
           Find = '    if ($DryRun) { $res.running = $t; return $res }'
           Replace = '    if ($DryRun) { $res.running = $t }' }
        @{ Name = "reused-id-taken"
           Find = '$t = @($Targets | Where-Object { $null -ne $_ -and (Test-HordeNightlyAppAlive $_) })'
           Replace = '$t = @($Targets | Where-Object { $null -ne $_ })' }
        @{ Name = "chrome-hash-read-as-value"
           Find = '''"restore_on_startup"\s*:\s*(\d+)'''
           Replace = '''"restore_on_startup"\s*:\s*"?(\w+)''' }
    )
}
