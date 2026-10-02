# Mutations of the selector behind tools\Mutate.ps1 -Changed.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\mutate-changed.psd1
# Each breaks one rule of tools\MutateChanged.ps1 - which lines a diff changed, where a mutant sits,
# what is selected, when zero is an error; test\test-mutate-changed.ps1 must fail for every one. A
# selector that drops a mutant it should run makes a review round green for the wrong reason.
@{
    Target = "tools\MutateChanged.ps1"
    Suite  = "test\test-mutate-changed.ps1"
    # Stop at the first failed check: a caught mutant needs nothing more.
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- reading the diff
        @{ Name = "drops-modified-lines"
           Find = '''^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@'''
           Replace = '''^@@ -\d+,0 \+(\d+)(?:,(\d+))? @@''' }
        @{ Name = "no-count-means-zero"
           Find = '$count = 1'
           Replace = '$count = 0' }
        @{ Name = "range-short-by-one"
           Find = '$i -lt $start + $count;'
           Replace = '$i -lt $start + $count - 1;' }
        @{ Name = "deletion-unmarked"
           Find = '[void]$files[$cur].Add($start); [void]$files[$cur].Add($start + 1)'
           Replace = '$null = 0' }
        @{ Name = "deletion-one-side"
           Find = '; [void]$files[$cur].Add($start + 1)'
           Replace = '' }
        @{ Name = "deleted-file-not-touched"
           Find = '$cur = ConvertTo-HordeDiffKey $hdr.Groups[1].Value'
           Replace = '$cur = $null' }
        @{ Name = "keys-keep-case"
           Find = 'return $p.ToLowerInvariant()'
           Replace = 'return $p' }
        @{ Name = "keys-keep-backslashes"
           Find = '($Path.Trim() -replace ''\\'', ''/'')'
           Replace = '($Path.Trim())' }
        @{ Name = "diff-against-head-not-merge-base"
           Find = '"--dst-prefix=b/", $sha, "--"'
           Replace = '"--dst-prefix=b/", "HEAD", "--"' }
        @{ Name = "untracked-ignored"
           Find = 'Add-HordeWholeFile -Changed $changed -Path $rel -LineCount $n'
           Replace = '$null = $n' }
        @{ Name = "bad-base-accepted"
           Find = 'if ($mb.code -ne 0 -or -not $mb.out.Trim()) {'
           Replace = 'if ($false) {' }
        # --- placing a mutant
        @{ Name = "missing-target-placed"
           Find = 'if ($null -eq $Text) { return [pscustomobject]@{ status = "missing"'
           Replace = 'if ($null -eq $Text) { return [pscustomobject]@{ status = "located"' }
        @{ Name = "ambiguous-placed-at-first"
           Find = 'if ($n -gt 1) {'
           Replace = 'if ($n -gt 99) {' }
        @{ Name = "lines-counted-from-zero"
           Find = '$line = 1'
           Replace = '$line = 0' }
        # --- the selection
        @{ Name = "skips-unlocatable"
           Find = '$sel = $true; $why = "find string not found in "'
           Replace = '$sel = $false; $why = "find string not found in "' }
        @{ Name = "skips-ambiguous"
           Find = '$sel = $true; $why = "find string occurs "'
           Replace = '$sel = $false; $why = "find string occurs "' }
        @{ Name = "spec-change-ignored"
           Find = '} elseif ($sp.specChanged) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "multiline-placed"
           Find = 'if ($Find -match "[\r\n]") { return [pscustomobject]@{ status = "multiline"'
           Replace = 'if ($false) { return [pscustomobject]@{ status = "multiline"' }
        @{ Name = "multiline-skipped"
           Find = '$sel = $true; $why = "find string spans lines'
           Replace = '$sel = $false; $why = "find string spans lines' }
        # --- the diff is read the same way whatever the git config says
        @{ Name = "prefixes-not-forced"
           Find = '"--src-prefix=a/", "--dst-prefix=b/", '
           Replace = '' }
        @{ Name = "parse-problem-ignored"
           Find = 'if ($why) { return [pscustomobject]@{ ok = $false; error = $why;'
           Replace = 'if ($false) { return [pscustomobject]@{ ok = $false; error = $why;' }
        @{ Name = "partial-parse-accepted"
           Find = 'if ($parsed -ne $headers -or $Changed.Count -eq 0) {'
           Replace = 'if ($parsed -eq 0 -and $Changed.Count -eq 0) {' }
        # --- zero is not a pass
        @{ Name = "zero-on-a-touched-target-passes"
           Find = 'if ($hit.Count -gt 0) {'
           Replace = 'if ($hit.Count -gt 99) {' }
    )
}
