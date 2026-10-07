# Mutations of core/Fingerprints.ps1, the one reader of a folder's list of pinned files. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fingerprints.psd1
# test\test-fingerprints.ps1 must fail for each.
@{
    Target = "core\Fingerprints.ps1"
    Suite  = "test\test-fingerprints.ps1"
    Mutations = @(
        @{ Name = "changed-file-accepted"
           Find = 'if ($actual -cne $e.sha256) {'
           Replace = 'if ($false) {' }
        @{ Name = "missing-file-accepted"
           Find = 'if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { [void]$findings.Add($e.name + " is listed and is not there"); continue }'
           Replace = 'if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }' }
        @{ Name = "folder-with-no-list-is-ok"
           Find = 'return [pscustomobject]@{ ok = $false; findings = @("there is no "'
           Replace = 'return [pscustomobject]@{ ok = $true; findings = @("there is no "' }
        @{ Name = "empty-list-is-ok"
           Find = 'if (@($read.entries).Count -eq 0) { [void]$findings.Add($script:HordeFingerprintListName + " lists no file") }'
           Replace = '' }
        @{ Name = "malformed-line-not-reported"
           Find = 'foreach ($p in $read.problems) { [void]$findings.Add($script:HordeFingerprintListName + ": " + $p) }'
           Replace = '' }
        @{ Name = "a-path-may-be-pinned"
           Find = 'if ($cells[0] -cnotmatch ''\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z'' -or $cells[0].Contains("..")) {'
           Replace = 'if ($false) {' }
        @{ Name = "two-dots-allowed-in-a-name"
           Find = ' -or $cells[0].Contains("..")) {'
           Replace = ') {' }
        @{ Name = "fingerprint-in-any-case"
           Find = 'if ($cells[1] -cnotmatch ''\A[0-9a-f]{64}\z'') {'
           Replace = 'if ($cells[1] -notmatch ''\A[0-9a-f]{64}\z'') {' }
        @{ Name = "fingerprint-of-any-length"
           Find = 'if ($cells[1] -cnotmatch ''\A[0-9a-f]{64}\z'') {'
           Replace = 'if ($cells[1] -cnotmatch ''\A[0-9a-f]{1,64}\z'') {' }
        @{ Name = "blank-reason-accepted"
           Find = 'if ($cells[2] -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "file-listed-twice-accepted"
           Find = 'if ($seen.ContainsKey($key)) {'
           Replace = 'if ($false) {' }
        @{ Name = "changed-file-still-handed-back"
           Find = 'the list says " + $e.sha256 + " and the file is " + $actual); continue }'
           Replace = 'the list says " + $e.sha256 + " and the file is " + $actual) }' }
        @{ Name = "list-under-another-name"
           Find = '$script:HordeFingerprintListName = "fingerprints.txt"'
           Replace = '$script:HordeFingerprintListName = "pinned.txt"' }
        # --- held from the check until the load, and what else is in the folder
        @{ Name = "a-held-file-may-be-written-to"
           Find = '[System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)'
           Replace = '[System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)' }
        @{ Name = "a-held-file-may-be-moved-away"
           Find = '[System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)'
           Replace = '[System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::Read -bor [System.IO.FileShare]::Delete))' }
        @{ Name = "nothing-is-held-when-asked"
           Find = 'if ($Hold) { [void]$held.Add($stream) } else { $stream.Dispose() }'
           Replace = '$stream.Dispose()' }
        @{ Name = "a-check-alone-leaves-the-files-held"
           Find = 'if ($Hold) { [void]$held.Add($stream) } else { $stream.Dispose() }'
           Replace = '[void]$held.Add($stream)' }
        @{ Name = "a-refused-folder-keeps-its-good-files-held"
           Find = 'if ($findings.Count -gt 0) { foreach ($h in @($held)) { $h.Dispose() }; $held.Clear() }'
           Replace = '' }
        @{ Name = "the-list-itself-is-called-unlisted"
           Find = ' + @($script:HordeFingerprintListName)'
           Replace = '' }
        @{ Name = "a-listed-file-is-called-unlisted"
           Find = 'Where-Object { $listed -cnotcontains $_ })'
           Replace = 'Where-Object { $true })' }
        # No mutant takes the fingerprint from a second look at the path instead of from the held
        # file: with nothing racing it the two read the same bytes, so no check here could tell.
    )
}
