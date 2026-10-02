# Mutations of core/Price.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\price.psd1
# Each breaks one rule the price table exists for; test\test-price.ps1 must fail for every one.
@{
    Target = "core\Price.ps1"
    Suite  = "test\test-price.ps1"
    Mutations = @(
        @{ Name = "geo-ignored"
           Find = '$mult = [decimal]$gm'
           Replace = '$mult = [decimal]1' }
        @{ Name = "unknown-geo-is-standard"
           Find = 'if ($null -eq $gm) { return (New-HordeUnknown -Reason ("price table " + $version + " does not say how geography'
           Replace = 'if ($null -eq $gm) { $gm = 1 }; if ($false) { return (New-HordeUnknown -Reason ("price table " + $version + " does not say how geography' }
        @{ Name = "hour-cache-at-five-minute-rate"
           Find = '& $need $s.h1 "cacheWrite1h"'
           Replace = '& $need $s.h1 "cacheWrite5m"' }
        @{ Name = "missing-rate-is-free"
           Find = 'if ($null -eq $rates[$key]) { throw ("price table " + $version + " has no '''
           Replace = 'if ($null -eq $rates[$key]) { return }; if ($false) { throw ("price table " + $version + " has no ''' }
        @{ Name = "unpriced-model-is-free"
           Find = 'if ($null -eq $entry) { return (New-HordeUnknown -Reason ("price table " + $version + " has no price for model'
           Replace = 'if ($null -eq $entry) { return (New-HordeKnown -Value ([decimal]0)) }; if ($false) { return (New-HordeUnknown -Reason ("price table " + $version + " has no price for model' }
        @{ Name = "speed-ignored"
           Find = '        $rates = $sp'
           Replace = '        $rates = $entry["rates"]' }
        @{ Name = "split-not-checked"
           Find = 'if (($s.m5 + $s.h1) -ne $u.cacheWrite) {'
           Replace = 'if ($false) {' }
        @{ Name = "no-version-accepted"
           Find = '$p += "it has no version, so a cost could not say which table priced it"'
           Replace = '$null = 0' }
        @{ Name = "unknown-rate-name-accepted"
           Find = 'if ($script:HordeRateKeys -cnotcontains $k) {'
           Replace = 'if ($false) {' }
    )
}
