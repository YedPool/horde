# Mutations of fleet/StatusPanel.ps1, the reader of each Orc's status record. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-status.psd1
# test\test-fleet-status.ps1 must fail for each.
@{
    Target = "fleet\StatusPanel.ps1"
    Suite  = "test\test-fleet-status.ps1"
    Mutations = @(
        # --- read whole or not at all
        @{ Name = "a-broken-record-passes-on-its-fields"
           Find = 'if ($problems.Count -gt 0) { return [pscustomobject]@{ problems = @($problems); fields = $null } }'
           Replace = 'if ($problems.Count -gt 0) { return [pscustomobject]@{ problems = @($problems); fields = $fields } }' }
        @{ Name = "a-broken-file-shown-as-written"
           Find = 'if ($null -eq $record.fields) { $out.problems = @($record.problems); return [pscustomobject]$out }'
           Replace = 'if ($null -eq $record.fields) { $out.problems = @($record.problems); $out.written = $true; return [pscustomobject]$out }' }
        # --- the seven shapes
        @{ Name = "byte-order-mark-accepted"
           Find = '[void]$problems.Add("starts with a byte-order mark")'
           Replace = '' }
        @{ Name = "non-ascii-accepted"
           Find = 'if (@($body | Where-Object { $_ -gt 127 }).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-number-of-lines"
           Find = 'if ($lines.Count -ne 6) {'
           Replace = 'if ($lines.Count -lt 6) {' }
        @{ Name = "fewer-lines-accepted"
           Find = 'if ($lines.Count -ne 6) {'
           Replace = 'if ($lines.Count -gt 6) {' }
        @{ Name = "any-first-line"
           Find = 'if ($lines.Count -eq 0 -or $lines[0] -cne $script:HordeFleetStatusHeader) {'
           Replace = 'if ($lines.Count -eq 0) {' }
        @{ Name = "another-version-read-as-this-one"
           Find = '$script:HordeFleetStatusHeader = "horde-orc-status 1"'
           Replace = '$script:HordeFleetStatusHeader = "horde-orc-status 2"' }
        @{ Name = "a-key-with-nothing-after-it-accepted"
           Find = ' -or $lines[$at].Substring($key.Length + 2).Trim() -eq "") {'
           Replace = ') {' }
        @{ Name = "a-key-with-no-space-accepted"
           Find = '$lines[$at].StartsWith($key + ": ", [System.StringComparison]::Ordinal)'
           Replace = '$lines[$at].StartsWith($key + ":", [System.StringComparison]::Ordinal)' }
        @{ Name = "keys-in-any-order"
           Find = '$script:HordeFleetStatusKeys = @("orc", "lane", "doing", "finished", "blocked")'
           Replace = '$script:HordeFleetStatusKeys = @("orc", "lane", "finished", "doing", "blocked")' }
        @{ Name = "any-length"
           Find = 'if ($value.Length -gt $script:HordeFleetStatusMostChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-cap-one-short"
           Find = 'if ($value.Length -gt $script:HordeFleetStatusMostChars) {'
           Replace = 'if ($value.Length -ge $script:HordeFleetStatusMostChars) {' }
        @{ Name = "bare-references-accepted"
           Find = 'if ($value -match $script:HordeFleetStatusBareReference) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-path-accepted"
           Find = '|#\d+|[A-Za-z]:\\'''
           Replace = '|#\d+''' }
        @{ Name = "the-reference-rule-reaches-the-lane"
           Find = 'if ($key -ceq "doing" -or $key -ceq "finished") {'
           Replace = 'if ($key -cne "orc") {' }
        @{ Name = "finished-not-held-to-the-rules"
           Find = 'if ($key -ceq "doing" -or $key -ceq "finished") {'
           Replace = 'if ($key -ceq "doing") {' }
        # --- this reader's own
        @{ Name = "any-text-names-an-orc"
           Find = 'if ($key -ceq "orc" -and $value -cnotmatch ''\A[A-Z]\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "a-small-letter-names-an-orc"
           Find = 'if ($key -ceq "orc" -and $value -cnotmatch ''\A[A-Z]\z'') {'
           Replace = 'if ($key -ceq "orc" -and $value -notmatch ''\A[A-Z]\z'') {' }
        @{ Name = "two-folders-one-letter-both-shown"
           Find = '| Where-Object { $_.Count -gt 1 })) {'
           Replace = '| Where-Object { $_.Count -gt 2 })) {' }
        @{ Name = "a-huge-file-read"
           Find = 'if ($info.Length -gt $script:HordeFleetStatusMostBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "blocked-only-when-it-says-yes"
           Find = 'if ($record.fields["blocked"].Trim() -cne "no") {'
           Replace = 'if ($record.fields["blocked"].Trim() -ceq "yes") {' }
        @{ Name = "age-from-the-clock-not-the-file"
           Find = '$out.ageSeconds = [int][Math]::Max(0, [Math]::Floor(($Now.ToUniversalTime() - $wroteAt).TotalSeconds))'
           Replace = '$out.ageSeconds = 0' }
        @{ Name = "a-missing-file-shown-as-written"
           Find = 'if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { $out.problems = @("there is no " + $script:HordeFleetStatusFile); return [pscustomobject]$out }'
           Replace = 'if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { $out.problems = @("there is no " + $script:HordeFleetStatusFile); $out.written = $true; return [pscustomobject]$out }' }
        @{ Name = "unlisted-folder-is-an-empty-fleet"
           Find = 'catch { return [pscustomobject]@{ schemaVersion = 1; state = "unreadable"; reason = ("the folder of status records could not be listed: "'
           Replace = 'catch { return [pscustomobject]@{ schemaVersion = 1; state = "read"; reason = ("the folder of status records could not be listed: "' }
        # --- the configuration
        @{ Name = "no-configuration-is-an-error"
           Find = 'return [pscustomobject]@{ state = "not-configured"; folder = "";'
           Replace = 'return [pscustomobject]@{ state = "unreadable"; folder = "";' }
        @{ Name = "any-version-of-the-configuration"
           Find = 'if ($null -eq $version -or $version.Value -ne 1) {'
           Replace = 'if ($null -eq $version) {' }
        @{ Name = "a-relative-folder-accepted"
           Find = ' -or -not [System.IO.Path]::IsPathRooted($folder.Value)) {'
           Replace = ') {' }
        @{ Name = "a-folder-that-is-not-there-accepted"
           Find = 'if (-not (Test-Path -LiteralPath $folder.Value -PathType Container -ErrorAction Stop)) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-folder-that-cannot-be-asked-about-throws"
           Find = '} catch { return (& $bad ("names a folder that could not be looked for: " + $_.Exception.Message)) }'
           Replace = '} catch { throw }' }
        @{ Name = "the-configuration-somewhere-else"
           Find = 'return (Join-Path (Join-Path $HordeHome "fleet") "status-source.json")'
           Replace = 'return (Join-Path (Join-Path $HordeHome "fleet") "status.json")' }
    )
}
