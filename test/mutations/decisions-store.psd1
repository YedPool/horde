# Mutations of decisions/Store.ps1, the decisions list's write-once records. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-store.psd1
# Each breaks one promise of the store; test\test-decisions-store.ps1 must fail for every one, except
# those declared Expect = "survives". The mutants only racing processes can see are in
# test\mutations\decisions-store-race.psd1.
@{
    Target = "decisions\Store.ps1"
    Suite  = "test\test-decisions-store.ps1"
    Mutations = @(
        @{ Name = "file-in-place-of-the-store-reads-as-empty"
           Find = 'if ([System.IO.File]::Exists($Root)) {'
           Replace = 'if ($false) {' }
        @{ Name = "move-overwrites"
           Find = '[System.IO.File]::Move($tmpPath, $recPath)'
           Replace = '[System.IO.File]::Copy($tmpPath, $recPath, $true)' }
        @{ Name = "taken-number-is-an-error"
           Find = 'if (($script:HordeDecisionStoreExistsCodes -contains $code) -and [System.IO.File]::Exists($recPath)) { return "exists" }'
           Replace = '' }
        @{ Name = "folder-of-the-record-name-reads-as-taken"
           Find = 'if (($script:HordeDecisionStoreExistsCodes -contains $code) -and [System.IO.File]::Exists($recPath)) { return "exists" }'
           Replace = 'if ($script:HordeDecisionStoreExistsCodes -contains $code) { return "exists" }' }
        @{ Name = "record-written-under-its-own-name"
           Find = '$tmpPath = Join-Path $Root ("writing-" + [guid]::NewGuid().ToString("N") + ".part")'
           Replace = '$tmpPath = $recPath' }
        @{ Name = "loser-leaves-its-temporary-file"
           Find = 'try { [System.IO.File]::Delete($tmpPath) } catch { }'
           Replace = '' }
        @{ Name = "dead-writers-file-never-swept"
           Find = '$null = Remove-HordeDecisionStoreLeftovers -Root $Root'
           Replace = '' }
        @{ Name = "live-writers-file-swept"
           Find = '.TotalMinutes -lt $script:HordeDecisionStoreTempStaleMinutes) { continue }'
           Replace = '.TotalMinutes -lt 0) { continue }' }
        @{ Name = "sweep-takes-names-that-are-not-its-own"
           Find = 'if ([System.IO.Path]::GetFileName($leftover) -cnotmatch $script:HordeDecisionStoreTempPattern) { continue }'
           Replace = '' }
        @{ Name = "sweep-fails-the-write-with-no-store"
           Find = 'try { $found = @([System.IO.Directory]::GetFiles($Root, "writing-*.part")) } catch { return 0 }'
           Replace = '$found = @([System.IO.Directory]::GetFiles($Root, "writing-*.part"))' }
        @{ Name = "name-of-nine-digits"
           Find = 'return ($Sequence.ToString("D10", [System.Globalization.CultureInfo]::InvariantCulture) + ".json")'
           Replace = 'return ($Sequence.ToString("D9", [System.Globalization.CultureInfo]::InvariantCulture) + ".json")' }
        @{ Name = "sequence-zero-allowed"
           Find = 'if ($Sequence -lt 1 -or $Sequence -gt 9999999999) {'
           Replace = 'if ($Sequence -gt 9999999999) {' }
        @{ Name = "eleven-digit-sequence-allowed"
           Find = 'if ($Sequence -lt 1 -or $Sequence -gt 9999999999) {'
           Replace = 'if ($Sequence -lt 1) {' }
        @{ Name = "relative-root-written"
           Find = 'if (-not [System.IO.Path]::IsPathRooted("$Root")) { throw ("the decisions store needs an absolute folder, not ''" + $Root + "''") }'
           Replace = '' }
        @{ Name = "relative-root-read"
           Find = 'if (-not $absolute) {'
           Replace = 'if ($false) {' }
        @{ Name = "reading-creates-the-store"
           Find = 'if (-not [System.IO.Directory]::Exists($Root)) { return $none }'
           Replace = 'if (-not [System.IO.Directory]::Exists($Root)) { [void][System.IO.Directory]::CreateDirectory($Root); return $none }' }
        @{ Name = "empty-file-not-named-empty"
           Find = 'if ("$text".Trim() -eq "") { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is empty: its writer stopped before writing it" } }'
           Replace = '' }
        @{ Name = "cut-json-throws"
           Find = 'try { $data = $text | ConvertFrom-Json } catch { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is not complete JSON: its writer stopped while writing it, or it was damaged" } }'
           Replace = '$data = $text | ConvertFrom-Json' }
        @{ Name = "non-object-read-as-a-record"
           Find = 'if ($null -eq $data -or $data -isnot [System.Management.Automation.PSCustomObject]) { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is not a JSON object" } }'
           Replace = '' }
        @{ Name = "bad-bytes-read-as-other-letters"
           Find = '$script:HordeDecisionStoreUtf8 = New-Object System.Text.UTF8Encoding($false, $true)'
           Replace = '$script:HordeDecisionStoreUtf8 = New-Object System.Text.UTF8Encoding($false, $false)' }
        @{ Name = "held-record-is-an-error"
           Find = 'if ($script:HordeDecisionStoreBusyCodes -contains $code) { $busy = $true }'
           Replace = 'if ($false) { $busy = $true }' }
        @{ Name = "held-record-not-waited-for"
           Find = '$script:HordeDecisionStoreBusyTries = 40'
           Replace = '$script:HordeDecisionStoreBusyTries = 1' }
        @{ Name = "missing-record-is-an-error"
           Find = 'if ($code -eq 2 -or $code -eq 3) {'
           Replace = 'if ($false) {' }
        @{ Name = "other-names-read-as-records"
           Find = '$script:HordeDecisionStoreNamePattern = ''\A([0-9]{10})\.json\z'''
           Replace = '$script:HordeDecisionStoreNamePattern = ''([0-9]{10})\.json''' }
        @{ Name = "last-record-left-out"
           Find = 'for ($seq = [long]1; $seq -le $last; $seq++) {'
           Replace = 'for ($seq = [long]1; $seq -lt $last; $seq++) {' }
        @{ Name = "damaged-record-keeps-no-reason"
           Find = '[void]$records.Add([pscustomobject]@{ sequence = $seq; file = $leaf; kind = $read.kind; data = $read.data; reason = $read.reason })'
           Replace = '[void]$records.Add([pscustomobject]@{ sequence = $seq; file = $leaf; kind = $read.kind; data = $read.data; reason = "" })' }
        @{ Name = "not-written-through"
           Find = '$fs.Flush($true)'
           Replace = '$fs.Flush()'
           Expect = "survives"
           Reason = "whether the bytes reached the disk before the record took its name can only be seen by cutting the power; no suite can observe it, and the line is kept on remote/Journal.ps1's reasoning" }
    )
}
