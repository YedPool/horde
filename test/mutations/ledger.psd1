# Mutations of the ledger gate's rule for what a "test" disposition may point at.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\ledger.psd1
# Each breaks one part of the path rule in tools\Ledger.ps1; test\test-ledger.ps1 must fail for every
# one. Written for the review of PR 21, which got a host's harness, an upper-case path and a trailing
# dot accepted as tests.
@{
    Target = "tools\Ledger.ps1"
    Suite  = "test\test-ledger.ps1"
    Mutations = @(
        # --- the path must be written as it is on disk
        @{ Name = "written-path-not-compared"
           Find = 'if (-not [string]::Equals(($wantFile -replace ''\\'', ''/''), $disk, [System.StringComparison]::Ordinal)) {'
           Replace = 'if ($false) {' }
        @{ Name = "written-path-compared-ignoring-case"
           Find = '$disk, [System.StringComparison]::Ordinal)) {'
           Replace = '$disk, [System.StringComparison]::OrdinalIgnoreCase)) {' }
        @{ Name = "backslash-path-not-normalised"
           Find = '[string]::Equals(($wantFile -replace ''\\'', ''/''), $disk,'
           Replace = '[string]::Equals($wantFile, $disk,' }
        @{ Name = "on-disk-spelling-not-read"
           Find = 'if ($hit.Count -eq 1) { $name = Split-Path -Leaf $hit[0] }'
           Replace = '' }
        # --- only a suite counts
        @{ Name = "suite-name-matched-ignoring-case"
           Find = 'if ($disk -cnotmatch '
           Replace = 'if ($disk -notmatch ' }
        @{ Name = "any-file-name-is-a-suite"
           Find = '/(e2e/)?(test|e2e)-[^/]+\.ps1$'
           Replace = '/(e2e/)?[^/]+\.ps1$' }
        @{ Name = "any-subfolder-is-a-suite-folder"
           Find = '(test|e2e)-[^/]+\.ps1$'
           Replace = '(test|e2e)-.+\.ps1$' }
        @{ Name = "e2e-folder-not-accepted"
           Find = '/(e2e/)?(test|e2e)-'
           Replace = '/(test|e2e)-' }
        @{ Name = "host-test-folder-not-accepted"
           Find = '^(test|hosts/[^/]+/test)/(e2e/)?'
           Replace = '^(test)/(e2e/)?' }
    )
}
