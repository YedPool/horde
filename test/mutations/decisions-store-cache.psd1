# Mutations of the read cache in decisions/Store.ps1 (THE READ CACHE, T-0166). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-store-cache.psd1
# Each breaks one promise of the cache; test\test-decisions-store-cache.ps1 must fail for every one.
# The store's own promises, cache or none, are test\mutations\decisions-store.psd1's.
@{
    Target = "decisions\Store.ps1"
    Suite  = "test\test-decisions-store-cache.ps1"
    Mutations = @(
        @{ Name = "stamp-blind-to-size"
           Find = '$stamp = $cacheKey + "|" + $leaf + "|" + $fi.Length + "|" + $fi.LastWriteTimeUtc.Ticks'
           Replace = '$stamp = $cacheKey + "|" + $leaf + "|0|" + $fi.LastWriteTimeUtc.Ticks' }
        @{ Name = "stamp-blind-to-write-time"
           Find = '$stamp = $cacheKey + "|" + $leaf + "|" + $fi.Length + "|" + $fi.LastWriteTimeUtc.Ticks'
           Replace = '$stamp = $cacheKey + "|" + $leaf + "|" + $fi.Length + "|0"' }
        @{ Name = "gone-records-stay-cached"
           Find = '    $script:HordeDecisionStoreCache[$cacheKey] = $keep'
           Replace = '    foreach ($k in @($kept.Keys)) { if (-not $keep.ContainsKey($k)) { $keep[$k] = $kept[$k] } }; $script:HordeDecisionStoreCache[$cacheKey] = $keep' }
        @{ Name = "a-record-not-read-whole-is-kept"
           Find = '        if ($read.kind -ceq "ok") {'
           Replace = '        if ($true) {' }
        @{ Name = "nothing-is-kept"
           Find = '            $keep[$leaf] = [pscustomobject]@{ stamp = $stamp; text = $text }'
           Replace = '' }
        @{ Name = "another-version-reuses-the-cache"
           Find = ' -or "$($script:HordeDecisionStoreCacheStamp)" -cne $script:HordeDecisionStoreCodeStamp) {'
           Replace = ') {' }
        @{ Name = "a-store-that-is-gone-keeps-its-cache"
           Find = 'if (-not [System.IO.Directory]::Exists($Root)) { $script:HordeDecisionStoreCache.Remove([System.IO.Path]::GetFullPath($Root).TrimEnd("\").ToLowerInvariant()); return $none }'
           Replace = 'if (-not [System.IO.Directory]::Exists($Root)) { return $none }' }
        @{ Name = "cached-record-handed-out-without-its-stamp"
           Find = '            $rec | Add-Member -NotePropertyName stamp -NotePropertyValue $stamp'
           Replace = '' }
    )
}
