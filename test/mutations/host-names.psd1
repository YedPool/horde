# Mutations of the D12 host-names ratchet. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\host-names.psd1
# Each breaks one rule tools\HostNames.ps1 enforces; test\test-host-names.ps1 must fail for every one.
@{
    Target = "tools\HostNames.ps1"
    Suite  = "test\test-host-names.ps1"
    Mutations = @(
        # --- what counts as a mention
        @{ Name = "mentions-matched-with-case"
           Find = '$at = $text.IndexOf($nm, [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = '$at = $text.IndexOf($nm, [System.StringComparison]::Ordinal)' }
        @{ Name = "path-not-checked"
           Find = 'foreach ($nm in $Names) { if ($Rel.IndexOf($nm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $count = 1; break } }'
           Replace = '' }
        @{ Name = "one-mention-per-name"
           Find = '$at = $text.IndexOf($nm, $at + $nm.Length, [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = '$at = -1' }
        @{ Name = "lines-counted-not-mentions"
           Find = '$at = $text.IndexOf($nm, $at + $nm.Length, [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = '$at = $text.IndexOf("`n", $at); if ($at -ge 0) { $at = $text.IndexOf($nm, $at, [System.StringComparison]::OrdinalIgnoreCase) }' }
        @{ Name = "comment-lines-read-as-data"
           Find = 'if ($t -eq "" -or $t.StartsWith("#")) { continue }'
           Replace = 'if ($t -eq "") { continue }' }
        # --- what is scanned
        @{ Name = "planning-prose-scanned"
           Find = 'if (Test-HordePlanningProse -Rel $rel) { continue }'
           Replace = '' }
        @{ Name = "planning-any-type-skipped"
           Find = 'return ($script:HordeHostNamesProseTypes -contains ([System.IO.Path]::GetExtension($Rel).ToLowerInvariant()))'
           Replace = 'return $true' }
        @{ Name = "planning-extension-compared-with-case"
           Find = '([System.IO.Path]::GetExtension($Rel).ToLowerInvariant())'
           Replace = '([System.IO.Path]::GetExtension($Rel))' }
        @{ Name = "planning-other-type-not-refused"
           Find = 'Add-Finding "(repository)" $f.rel'
           Replace = 'continue; Add-Finding "(repository)" $f.rel' }
        @{ Name = "planning-prose-entry-kept"
           Find = ' -or (Test-HordePlanningProse -Rel $p)) {'
           Replace = ') {' }
        @{ Name = "own-folder-scanned"
           Find = '$skip = @($own) + $script:HordeHostNamesExcluded'
           Replace = '$skip = @() + $script:HordeHostNamesExcluded' }
        @{ Name = "every-host-folder-exempt"
           Find = '$skip = @($own) + $script:HordeHostNamesExcluded'
           Replace = '$skip = @("hosts") + $script:HordeHostNamesExcluded' }
        @{ Name = "git-folder-scanned"
           Find = '(Test-HordeUnderFolder -Rel $rel -Folders (@(".git") + $Skip))'
           Replace = '(Test-HordeUnderFolder -Rel $rel -Folders $Skip)' }
        @{ Name = "git-file-scanned"
           Find = 'if ($rel -eq ".git" -or '
           Replace = 'if (' }
        # --- a new mention
        @{ Name = "unlisted-file-accepted"
           Find = 'if (-not $a) { Add-Finding $hn $f.rel ('
           Replace = 'if (-not $a) { continue; Add-Finding $hn $f.rel (' }
        @{ Name = "growth-accepted"
           Find = 'if ($c -gt $a.lines) {'
           Replace = 'if ($false) {' }
        # --- shrink-only
        @{ Name = "over-count-accepted"
           Find = 'elseif ($c -lt $a.lines) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "stale-entry-kept"
           Find = 'elseif ($seen[$k] -eq 0) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "missing-file-entry-kept"
           Find = 'if (-not $seen.ContainsKey($k)) {'
           Replace = 'if ($false) {' }
        @{ Name = "excluded-path-entry-kept"
           Find = 'if (Test-HordeUnderFolder -Rel $p -Folders $skip) {'
           Replace = 'if ($false) {' }
        @{ Name = "duplicate-entry-kept"
           Find = 'if ($allowed.ContainsKey($key)) {'
           Replace = 'if ($false) {' }
        @{ Name = "zero-count-accepted"
           Find = '-or $allowCount -lt 1)'
           Replace = ')' }
        @{ Name = "entry-reason-unchecked"
           Find = 'if ((Get-HordeDistinctWordCount $r.cells[2]) -lt 4) {'
           Replace = 'if ($false) {' }
        @{ Name = "entry-shape-unchecked"
           Find = 'if ($r.cells.Count -ne 3) {'
           Replace = 'if ($false) {' }
        @{ Name = "backslash-path-not-normalised"
           Find = '$p = ($r.cells[0] -replace ''\\'', ''/'').TrimStart(''/'')'
           Replace = '$p = $r.cells[0].TrimStart(''/'')' }
        # --- a host must declare what identifies it
        @{ Name = "host-without-names-passes"
           Find = 'Add-Finding $hn $own "declares no names.txt, so nothing can check that it stays in its folder"; continue'
           Replace = 'continue' }
        @{ Name = "empty-names-pass"
           Find = 'if ($names.Count -eq 0) { Add-Finding $hn ($own + "/names.txt") "lists no usable name, so nothing is checked"; continue }'
           Replace = 'if ($names.Count -eq 0) { continue }' }
        @{ Name = "short-name-accepted"
           Find = '$script:HordeHostNameMinLength = 4'
           Replace = '$script:HordeHostNameMinLength = 1' }
        @{ Name = "name-reason-unchecked"
           Find = 'if ((Get-HordeDistinctWordCount $r.cells[1]) -lt 4) {'
           Replace = 'if ($false) {' }
        @{ Name = "name-shape-unchecked"
           Find = 'if ($r.cells.Count -ne 2) {'
           Replace = 'if ($false) {' }
    )
}
