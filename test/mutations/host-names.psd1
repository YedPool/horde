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
           Find = 'return ($script:HordeHostNamesProseTypes -contains [System.IO.Path]::GetExtension($Rel))'
           Replace = 'return $true' }
        @{ Name = "planning-extension-compared-with-case"
           Find = '$script:HordeHostNamesProseTypes -contains'
           Replace = '$script:HordeHostNamesProseTypes -ccontains' }
        @{ Name = "planning-other-type-not-refused"
           Find = 'Add-Finding "(repository)" $f.rel "is under planning/'
           Replace = 'continue; Add-Finding "(repository)" $f.rel "is under planning/' }
        @{ Name = "planning-prose-entry-kept"
           Find = ' -or (Test-HordePlanningProse -Rel $p)) {'
           Replace = ') {' }
        @{ Name = "own-folder-scanned"
           Find = '$skip = @($own)'
           Replace = '$skip = @()' }
        @{ Name = "every-host-folder-exempt"
           Find = '$skip = @($own)'
           Replace = '$skip = @("hosts")' }
        @{ Name = "git-folder-scanned"
           Find = '(Test-HordeUnderFolder -Rel $rel -Folders (@(".git") + $Skip))'
           Replace = '(Test-HordeUnderFolder -Rel $rel -Folders $Skip)' }
        @{ Name = "git-file-scanned"
           Find = 'if ($rel -eq ".git" -or '
           Replace = 'if (' }
        # --- every scanned byte printable ASCII
        @{ Name = "non-ascii-not-refused"
           Find = 'if ($bad -ge 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "nul-byte-allowed"
           Find = "'[^\t\n\r\x20-\x7E]'"
           Replace = "'[^\x00\t\n\r\x20-\x7E]'" }
        @{ Name = "high-bytes-allowed"
           Find = "'[^\t\n\r\x20-\x7E]'"
           Replace = "'[^\t\n\r\x20-\xFF]'" }
        @{ Name = "whitespace-refused"
           Find = "'[^\t\n\r\x20-\x7E]'"
           Replace = "'[^\x20-\x7E]'" }
        # --- a new mention
        @{ Name = "unlisted-file-accepted"
           Find = 'if (-not $a) { Add-Finding $hn $f.rel ('
           Replace = 'if (-not $a) { continue; Add-Finding $hn $f.rel (' }
        @{ Name = "growth-accepted"
           Find = 'if ($c -gt $a.count) {'
           Replace = 'if ($false) {' }
        # --- shrink-only
        @{ Name = "over-count-accepted"
           Find = 'elseif ($c -lt $a.count) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "stale-entry-kept"
           Find = 'elseif ($seen[$k] -eq 0) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "missing-file-entry-kept"
           Find = 'if (-not $seen.ContainsKey($k)) {'
           Replace = 'if ($false) {' }
        @{ Name = "excluded-path-entry-kept"
           Find = 'if ((Test-HordeUnderFolder -Rel $p -Folders $skip) -or (Test-HordePlanningProse -Rel $p)) {'
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
           Find = 'if ($r.cells.Count -ne 3) { Add-Finding'
           Replace = 'if ($false) { Add-Finding' }
        @{ Name = "backslash-path-not-normalised"
           Find = 'return ($Path -replace ''\\'', ''/'').TrimStart(''/'')'
           Replace = 'return $Path.TrimStart(''/'')' }
        # --- shrink-only, against origin/main
        @{ Name = "shrink-new-entry-accepted"
           Find = 'if ($was -eq 0) { Add-Finding $hn $e.path ('
           Replace = 'if ($was -eq 0) { continue; Add-Finding $hn $e.path (' }
        @{ Name = "shrink-raised-count-accepted"
           Find = 'else { Add-Finding $hn $e.path ("is allowed "'
           Replace = 'else { continue; Add-Finding $hn $e.path ("is allowed "' }
        @{ Name = "shrink-old-count-ignored"
           Find = 'if ($oldAllow.ContainsKey($k)) { $was = $oldAllow[$k].count }'
           Replace = '' }
        @{ Name = "shrink-equal-count-is-growth"
           Find = 'if ($e.count -le $was) { continue }'
           Replace = 'if ($e.count -lt $was) { continue }' }
        # --- growth recorded in growth.txt
        @{ Name = "growth-unrecorded-accepted"
           Find = 'if ($growth.permits.ContainsKey($k + "|" + $was + "|" + $e.count)) { continue }'
           Replace = 'if ($true) { continue }' }
        @{ Name = "growth-record-ignored"
           Find = 'if ($growth.permits.ContainsKey($k + "|" + $was + "|" + $e.count)) { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "growth-old-count-not-matched"
           Find = 'if ($growth.permits.ContainsKey($k + "|" + $was + "|" + $e.count)) { continue }'
           Replace = 'if (@($growth.permits.Keys | Where-Object { $_ -like ($k + "|*|" + $e.count) }).Count) { continue }' }
        @{ Name = "growth-new-count-not-matched"
           Find = 'if ($growth.permits.ContainsKey($k + "|" + $was + "|" + $e.count)) { continue }'
           Replace = 'if (@($growth.permits.Keys | Where-Object { $_ -like ($k + "|" + $was + "|*") }).Count) { continue }' }
        @{ Name = "growth-path-not-matched"
           Find = 'if ($growth.permits.ContainsKey($k + "|" + $was + "|" + $e.count)) { continue }'
           Replace = 'if (@($growth.permits.Keys | Where-Object { $_ -like ("*|" + $was + "|" + $e.count) }).Count) { continue }' }
        @{ Name = "growth-problems-dropped"
           Find = 'foreach ($g in $growth.problems) { Add-Finding $hn $g.path $g.problem }'
           Replace = '' }
        @{ Name = "growth-shape-unchecked"
           Find = 'if ($r.cells.Count -ne 4) { $bad ='
           Replace = 'if ($false) { $bad =' }
        @{ Name = "growth-arrow-unchecked"
           Find = 'elseif ($from -lt 0) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "growth-non-increase-accepted"
           Find = 'elseif ($to -le $from) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "growth-date-unchecked"
           Find = 'elseif (-not [datetime]::TryParseExact('
           Replace = 'elseif ($false -and -not [datetime]::TryParseExact(' }
        @{ Name = "growth-reason-unchecked"
           Find = 'elseif ((Get-HordeDistinctWordCount $r.cells[3]) -lt 4) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "growth-bad-line-still-permits"
           Find = 'if ($bad) { [void]$out.problems.Add([pscustomobject]@{ path = $where; problem = $bad }); continue }'
           Replace = 'if ($bad) { [void]$out.problems.Add([pscustomobject]@{ path = $where; problem = $bad }) }' }
        @{ Name = "growth-not-append-only"
           Find = 'if ($i -ge $new.Count -or ($new[$i].cells -join " | ") -cne $was) {'
           Replace = 'if ($false) {' }
        @{ Name = "growth-edit-accepted"
           Find = 'if ($i -ge $new.Count -or ($new[$i].cells -join " | ") -cne $was) {'
           Replace = 'if ($i -ge $new.Count) {' }
        @{ Name = "growth-main-file-not-read"
           Find = 'if ($OnRef.ContainsKey($rel)) { $old ='
           Replace = 'if ($false) { $old =' }
        @{ Name = "growth-history-line-reused"
           Find = 'for ($i = $old.Count; $i -lt $new.Count; $i++) {'
           Replace = 'for ($i = 0; $i -lt $new.Count; $i++) {' }
        @{ Name = "shrink-removed-name-accepted"
           Find = 'if (-not $newNames.ContainsKey($k)) {'
           Replace = 'if ($false) {' }
        @{ Name = "shrink-removed-host-accepted"
           Find = 'if ($p -match ''^hosts/([^/]+)/names\.txt$'' -and -not $here.ContainsKey($Matches[1])) {'
           Replace = 'if ($false) {' }
        @{ Name = "shrink-every-host-new"
           Find = 'if (-not $onRef.ContainsKey($own + "/names.txt")) {'
           Replace = 'if ($true) {' }
        @{ Name = "shrink-no-host-new"
           Find = 'if (-not $onRef.ContainsKey($own + "/names.txt")) {'
           Replace = 'if ($false) {' }
        @{ Name = "shrink-missing-git-not-skipped"
           Find = '{ $out.skip = "no .git at " + $RepoRoot + " - not a git checkout"; return $out }'
           Replace = '{ }' }
        @{ Name = "shrink-missing-ref-not-skipped"
           Find = 'if ($LASTEXITCODE -ne 0) { $out.skip = $Ref + " does not exist'
           Replace = 'if ($false) { $out.skip = $Ref + " does not exist' }
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
