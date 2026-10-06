# Mutations of the D12 host-names ratchet. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\host-names.psd1
# Each breaks one rule tools\HostNames.ps1 enforces; test\test-host-names.ps1 must fail for every one.
@{
    Target = "tools\HostNames.ps1"
    Suite  = "test\test-host-names.ps1"
    Mutations = @(
        # --- what counts as a mention
        @{ Name = "mentions-matched-with-case"
           Find = '$at = $Text.IndexOf($nm, [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = '$at = $Text.IndexOf($nm, [System.StringComparison]::Ordinal)' }
        @{ Name = "path-not-checked"
           Find = 'foreach ($nm in $Names) { if ($Rel.IndexOf($nm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $count = 1; break } }'
           Replace = '' }
        @{ Name = "one-mention-per-name"
           Find = '$at = $Text.IndexOf($nm, $at + $nm.Length, [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = '$at = -1' }
        @{ Name = "lines-counted-not-mentions"
           Find = '$at = $Text.IndexOf($nm, $at + $nm.Length, [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = '$at = $Text.IndexOf("`n", $at); if ($at -ge 0) { $at = $Text.IndexOf($nm, $at, [System.StringComparison]::OrdinalIgnoreCase) }' }
        # --- one place in the text, one mention (lifecycle plan step 5)
        @{ Name = "overlapping-names-counted-twice"
           Find = 'if ($s.start -lt $taken) { continue }'
           Replace = '' }
        @{ Name = "shortest-name-taken-first"
           Find = '@{ Expression = { $_.end }; Descending = $true }'
           Replace = '@{ Expression = { $_.end }; Ascending = $true }' }
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
           Find = 'if ((Get-HordeDistinctWordCount $r.cells[2]) -lt 4) { Add-Finding'
           Replace = 'if ($false) { Add-Finding' }
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
           Find = 'if ($p -match ''^([^/]+/[^/]+)/names\.txt$'' -and -not $here.ContainsKey($Matches[1])) {'
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
           Find = 'if ((Get-HordeDistinctWordCount $out.why) -lt 4) {'
           Replace = 'if ($false) {' }
        @{ Name = "name-shape-unchecked"
           Find = 'else { $out.problem = "a name line is <name> | <why it identifies this host>, or <name> | <kind> | <why>"; return $out }'
           Replace = 'else { $out.name = $Row.cells[0]; $out.why = "a reason long enough to pass" }' }
        # --- kinds of name (lifecycle plan step 5)
        @{ Name = "four-part-line-accepted"
           Find = 'elseif ($Row.cells.Count -eq 3) {'
           Replace = 'elseif ($Row.cells.Count -ge 3) {' }
        @{ Name = "kind-line-refused"
           Find = 'elseif ($Row.cells.Count -eq 3) { $out.name = $Row.cells[0]; $out.kind = $Row.cells[1]; $out.why = $Row.cells[2] }'
           Replace = '' }
        @{ Name = "kind-unchecked"
           Find = 'if ($script:HordePortNameKinds -cnotcontains $out.kind) {'
           Replace = 'if ($false) {' }
        @{ Name = "kind-matched-without-case"
           Find = 'if ($script:HordePortNameKinds -cnotcontains $out.kind) {'
           Replace = 'if ($script:HordePortNameKinds -notcontains $out.kind) {' }
        @{ Name = "kind-reason-unchecked"
           Find = '$out.kind = $Row.cells[1]; $out.why = $Row.cells[2] }'
           Replace = '$out.kind = $Row.cells[1]; $out.why = "a reason long enough to pass" }' }
        @{ Name = "shrink-kind-line-invisible"
           Find = 'if ($r.cells.Count -eq 2 -or $r.cells.Count -eq 3) {'
           Replace = 'if ($r.cells.Count -eq 2) {' }
        # --- core matches no process image (Test-HordeProcessImages)
        @{ Name = "image-finding-dropped"
           Find = '[void]$found.Add([pscustomobject]@{ host = $m.images[0].own;'
           Replace = 'continue; [void]$found.Add([pscustomobject]@{ host = $m.images[0].own;' }
        @{ Name = "image-path-not-checked"
           Find = 'if ($Rel.IndexOf($form, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $n++ }'
           Replace = '' }
        @{ Name = "image-matched-with-case"
           Find = '$at = $Text.IndexOf($form, [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = '$at = $Text.IndexOf($form, [System.StringComparison]::Ordinal)' }
        @{ Name = "image-escaped-form-ignored"
           Find = '@(@($img.name, [regex]::Escape($img.name)) | Select-Object -Unique)'
           Replace = '@($img.name)' }
        @{ Name = "image-one-match-per-form"
           Find = '$at = $Text.IndexOf($form, $at + $form.Length, [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = '$at = -1' }
        @{ Name = "image-any-kind"
           Find = 'if (-not $pn.problem -and $pn.kind -ceq $Kind) {'
           Replace = 'if (-not $pn.problem) {' }
        @{ Name = "image-test-folder-checked"
           Find = '$script:HordeProcessImageExempt = @("test")'
           Replace = '$script:HordeProcessImageExempt = @()' }
        @{ Name = "image-port-folders-checked"
           Find = '-Skip (@(Get-HordePortFolders -RepoRoot $RepoRoot) + @($script:HordeProcessImageExempt))'
           Replace = '-Skip @($script:HordeProcessImageExempt)' }
        # --- transports/ is the third family (remote plan step R5)
        @{ Name = "transports-not-a-family"
           Find = '$script:HordePortFamilies = @("hosts", "agents", "transports", "messengers")'
           Replace = '$script:HordePortFamilies = @("hosts", "agents", "messengers")' }
        @{ Name = "image-rule-skips-whole-families"
           Find = '-Skip (@(Get-HordePortFolders -RepoRoot $RepoRoot) + @($script:HordeProcessImageExempt))'
           Replace = '-Skip (@($script:HordePortFamilies) + @($script:HordeProcessImageExempt))' }
        @{ Name = "port-folders-returned-as-one-object"
           Find = 'return @($out)'
           Replace = 'return , $out' }
        # --- the legacy list: exact counts, and only shrinking (review of this PR, A1 to A3)
        @{ Name = "legacy-excuses-any-file"
           Find = 'if ($legacy.ContainsKey($key)) {'
           Replace = 'if ($legacy.Count) {' }
        @{ Name = "legacy-gain-accepted"
           Find = 'if ($m.count -gt $allowedCount) {'
           Replace = 'if ($false) {' }
        @{ Name = "legacy-over-count-accepted"
           Find = 'elseif ($m.count -lt $allowedCount) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "legacy-stale-kept"
           Find = 'if (-not $matched.ContainsKey($k)) {'
           Replace = 'if ($false) {' }
        @{ Name = "legacy-not-normalised"
           Find = '$out.entries[$key] = [pscustomobject]@{ path = $p; count = $c }'
           Replace = '$out.entries[$r.cells[0]] = [pscustomobject]@{ path = $p; count = $c }' }
        @{ Name = "legacy-problems-dropped"
           Find = 'foreach ($x in $read.problems) {'
           Replace = 'foreach ($x in @()) {' }
        @{ Name = "legacy-count-unchecked"
           Find = 'elseif (-not [int]::TryParse($r.cells[1], [ref]$c) -or $c -lt 1) { $bad = "the match count'
           Replace = 'elseif ($false) { $bad = "the match count' }
        @{ Name = "legacy-reason-unchecked"
           Find = 'elseif ((Get-HordeDistinctWordCount $r.cells[2]) -lt 4) { $bad = $r.cells[0] + " needs a reason'
           Replace = 'elseif ($false) { $bad = $r.cells[0] + " needs a reason' }
        @{ Name = "legacy-shape-unchecked"
           Find = 'if ($r.cells.Count -ne 3) { $bad = "a legacy line is'
           Replace = 'if ($false) { $bad = "a legacy line is' }
        @{ Name = "legacy-duplicate-kept"
           Find = 'if ($out.entries.ContainsKey($key)) { $bad = $p + " is listed twice" }'
           Replace = 'if ($false) { $bad = $p + " is listed twice" }' }
        @{ Name = "legacy-shrink-new-entry-accepted"
           Find = 'if (-not $oldLegacy.ContainsKey($k)) { Add-Finding'
           Replace = 'if ($false) { Add-Finding' }
        @{ Name = "legacy-shrink-raised-count-accepted"
           Find = 'elseif ($e.count -gt $oldLegacy[$k].count) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "legacy-shrink-always-new"
           Find = 'if (@(& git -C $RepoRoot ls-tree --name-only $Ref -- $lf).Count -eq 0) {'
           Replace = 'if ($true) {' }
        @{ Name = "legacy-shrink-never-new"
           Find = 'if (@(& git -C $RepoRoot ls-tree --name-only $Ref -- $lf).Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "kind-demotion-accepted"
           Find = 'if ($oldKinds[$k] -ceq "processImage" -and $newKinds.ContainsKey($k) -and $newKinds[$k] -cne "processImage") {'
           Replace = 'if ($false) {' }
        # --- the one cross-host import (hosts plan step 5)
        @{ Name = "import-of-any-file"
           Find = "'[\\/]' + [regex]::Escape(`$script:HordeDialectFile) + '`$'"
           Replace = "'[\\/]'" }
        @{ Name = "import-path-unanchored"
           Find = "[regex]::Escape(`$script:HordeDialectFile) + '`$'"
           Replace = "[regex]::Escape(`$script:HordeDialectFile)" }
        @{ Name = "import-not-dot-sourced"
           Find = "`$line = '^\s*\.\s+(?:'"
           Replace = "`$line = '^\s*[.&]\s+(?:'" }
        @{ Name = "import-through-a-loader"
           Find = "'|\(\s*Join-Path\s+\`$[A-Za-z_][A-Za-z0-9_:]*\s+'"
           Replace = "'|\(\s*[A-Za-z-]+\s+(?:\S+\s+)?'" }
        @{ Name = "import-line-unchecked"
           Find = 'elseif ($a.import -and -not (Test-HordeDialectImport'
           Replace = 'elseif ($false -and -not (Test-HordeDialectImport' }
        @{ Name = "import-line-mention-unchecked"
           Find = 'if ((Get-HordeMentionSpans -Text $text -Names $Names).Count -ge 1) { return $true }'
           Replace = 'return $true' }
        @{ Name = "import-from-any-family"
           Find = 'if (-not $otherPort -or -not $otherPort.StartsWith($fam + "/")) {'
           Replace = 'if (-not $otherPort) {' }
        @{ Name = "import-from-anywhere"
           Find = 'if (-not $otherPort -or -not $otherPort.StartsWith($fam + "/")) {'
           Replace = 'if ($false) {' }
        @{ Name = "import-without-dialect"
           Find = 'if (-not (Test-Path -LiteralPath (Join-Path $h.FullName $script:HordeDialectFile) -PathType Leaf)) {'
           Replace = 'if ($false) {' }
        @{ Name = "import-word-matched-without-case"
           Find = '$isImport = ($r.cells[1] -ceq $script:HordeImportCount)'
           Replace = '$isImport = ($r.cells[1] -eq $script:HordeImportCount)' }
        @{ Name = "numbered-entry-in-other-port-allowed"
           Find = '} elseif ($otherPort -and -not (Test-HordePortListFile -Rel $p)) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "list-files-not-exempt"
           Find = 'return ($script:HordePortListFiles -contains $rest)'
           Replace = 'return $false' }
        @{ Name = "shrink-import-invisible"
           Find = 'if ($r.cells[1] -ceq $script:HordeImportCount) { $c = 1 }'
           Replace = 'if ($false) { $c = 1 }' }
    )
}
