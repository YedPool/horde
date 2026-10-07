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
        @{ Name = "every-claimant-of-a-letter-is-named"
           Find = '$names = @($claimants | Select-Object -First $script:HordeFleetStatusMostNamed) -join ", "'
           Replace = '$names = @($claimants) -join ", "' }
        @{ Name = "the-claimants-not-named-are-not-counted"
           Find = 'if ($claimants.Count -gt $script:HordeFleetStatusMostNamed) { $names += '
           Replace = 'if ($false) { $names += ' }
        @{ Name = "a-control-character-accepted"
           Find = '[void]$problems.Add("holds a control character")'
           Replace = '' }
        @{ Name = "a-tab-and-a-lone-return-accepted"
           Find = "-cmatch '[\x00-\x09\x0B-\x1F\x7F]') {"
           Replace = "-cmatch '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]') {" }
        @{ Name = "a-delete-accepted"
           Find = "\x0B-\x1F\x7F]') {"
           Replace = "\x0B-\x1F]') {" }
        @{ Name = "a-huge-file-read\"
           Find = 'if ($info.Length -gt $script:HordeFleetStatusMostBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "blocked-only-when-it-says-yes"
           Find = 'if (-not [string]::Equals($record.fields["blocked"].Trim(), "no", [System.StringComparison]::OrdinalIgnoreCase)) {'
           Replace = 'if ($record.fields["blocked"].Trim() -ceq "yes") {' }
        @{ Name = "no-is-read-in-one-letter-case-only"
           Find = '"no", [System.StringComparison]::OrdinalIgnoreCase)) {'
           Replace = '"no", [System.StringComparison]::Ordinal)) {' }
        @{ Name = "a-sentence-that-begins-with-no-is-not-blocked"
           Find = 'if (-not [string]::Equals($record.fields["blocked"].Trim(), "no",'
           Replace = 'if (-not $record.fields["blocked"].Trim().StartsWith("no", [System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::Equals("x", "no",' }
        @{ Name = "age-from-the-clock-not-the-file"
           Find = '$out.ageSeconds = [int][Math]::Max(0, [Math]::Floor(($Now.ToUniversalTime() - $wroteAt).TotalSeconds))'
           Replace = '$out.ageSeconds = 0' }
        @{ Name = "a-missing-file-shown-as-written"
           Find = 'if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { $out.problems = @("there is no " + $script:HordeFleetStatusFile); return [pscustomobject]$out }'
           Replace = 'if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { $out.problems = @("there is no " + $script:HordeFleetStatusFile); $out.written = $true; return [pscustomobject]$out }' }
        @{ Name = "unlisted-folder-is-an-empty-fleet"
           Find = 'catch { return (& $none "unreadable" ("the folder of status records could not be listed: " + $_.Exception.Message)) }'
           Replace = 'catch { return (& $none "read" ("the folder of status records could not be listed: " + $_.Exception.Message)) }' }
        # --- the module's settings: where the records are
        @{ Name = "no-setting-is-an-error"
           Find = 'return [pscustomobject]@{ state = "not-configured"; folder = "";'
           Replace = 'return [pscustomobject]@{ state = "unreadable"; folder = "";' }
        @{ Name = "a-folder-that-is-not-there-accepted"
           Find = 'if (-not (Test-Path -LiteralPath $folder -PathType Container -ErrorAction Stop)) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-folder-that-cannot-be-asked-about-throws"
           Find = '} catch { return (& $bad ("names a folder that could not be looked for: " + $_.Exception.Message)) }'
           Replace = '} catch { throw }' }
        @{ Name = "the-settings-of-another-module"
           Find = '$script:HordeFleetSettings = New-HordeModuleSettings -Module "fleet" -Settings @('
           Replace = '$script:HordeFleetSettings = New-HordeModuleSettings -Module "fleets" -Settings @(' }
        @{ Name = "the-folder-setting-has-a-default-place"
           Find = '@{ name = "statusFolder"; kind = "folder"; default = "";'
           Replace = '@{ name = "statusFolder"; kind = "folder"; default = "C:\no\such\folder\of-orcs";' }
        @{ Name = "what-was-wrong-in-the-file-not-said"
           Find = '$findings = @($Settings.findings | ForEach-Object { "" + $_ })'
           Replace = '$findings = @()' }
        # --- the module's settings: how many folders are read
        @{ Name = "every-folder-read"
           Find = '$orcs = @($paths | Select-Object -First $most | ForEach-Object { Read-HordeFleetStatusFolder -Path $_ -Now $Now })'
           Replace = '$orcs = @($paths | ForEach-Object { Read-HordeFleetStatusFolder -Path $_ -Now $Now })' }
        @{ Name = "the-rest-not-counted"
           Find = '$notRead = [Math]::Max(0, $paths.Length - $most)'
           Replace = '$notRead = 0' }
        @{ Name = "the-most-is-another-number"
           Find = '@{ name = "statusFoldersRead"; kind = "whole"; default = 64;'
           Replace = '@{ name = "statusFoldersRead"; kind = "whole"; default = 65;' }
        @{ Name = "which-are-read-is-by-letter-case"
           Find = '[System.Array]::Sort($paths, [System.StringComparer]::OrdinalIgnoreCase)'
           Replace = '[System.Array]::Sort($paths, [System.StringComparer]::Ordinal); [System.Array]::Reverse($paths)' }
        @{ Name = "the-count-of-unread-not-handed-on"
           Find = 'orcs = $sorted; notRead = $notRead; findings = $findings }'
           Replace = 'orcs = $sorted; notRead = 0; findings = $findings }' }
    )
}
