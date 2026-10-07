# Mutations of decisions/Store.ps1, the decisions list's write-once records. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-store.psd1
# Each breaks one promise of the store; test\test-decisions-store.ps1 must fail for every one, except
# those declared Expect = "survives". The mutants only racing processes can see are in
# test\mutations\decisions-store-race.psd1. The store's numbers are settings: the mutants of their
# defaults are in test\mutations\decisions-settings.psd1.
@{
    Target = "decisions\Store.ps1"
    Suite  = "test\test-decisions-store.ps1"
    Mutations = @(
        @{ Name = "file-in-place-of-the-store-reads-as-empty"
           Find = 'if ([System.IO.File]::Exists($Root)) {'
           Replace = 'if ($false) {' }
        @{ Name = "move-overwrites"
           Find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $recPath -Open $fs'
           Replace = '[System.IO.File]::WriteAllBytes($recPath, $bytes); $moved = "moved"' }
        @{ Name = "taken-number-is-an-error"
           Find = 'if ($moved -ceq "exists" -and [System.IO.File]::Exists($recPath)) { return "exists" }'
           Replace = '' }
        @{ Name = "folder-of-the-record-name-reads-as-taken"
           Find = 'if ($moved -ceq "exists" -and [System.IO.File]::Exists($recPath)) { return "exists" }'
           Replace = 'if ($moved -ceq "exists") { return "exists" }' }
        # --- durable before "created": the order of a write, and what the store says of each answer ---
        @{ Name = "writer-lets-go-before-the-move"
           Find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $recPath -Open $fs'
           Replace = '$fs.Dispose(); $moved = Move-HordeFileNewDurable -From $tmpPath -To $recPath -Open $null' }
        @{ Name = "move-not-handed-the-writers-handle"
           Find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $recPath -Open $fs'
           Replace = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $recPath -Open $null' }
        @{ Name = "moved-before-it-is-written"
           Find = '        $fs.Write($bytes, 0, $bytes.Length)'
           Replace = '        $moved = Move-HordeFileNewDurable -From $tmpPath -To $recPath -Open $fs; $fs.Write($bytes, 0, $bytes.Length); return "created"' }
        @{ Name = "unconfirmed-reads-as-created"
           Find = 'if ($moved -ceq "unconfirmed") { return "unconfirmed" }'
           Replace = 'if ($moved -ceq "unconfirmed") { return "created" }' }
        @{ Name = "any-answer-of-the-move-reads-as-created"
           Find = 'if ($moved -ceq "moved") { return "created" }'
           Replace = 'if ($true) { return "created" }' }
        @{ Name = "name-taken-by-no-record-reads-as-taken"
           Find = 'throw ("record " + $Sequence + " could not be put in place: its name is taken by something that is not a record (the move answered ''" + $moved + "'')")'
           Replace = 'return "exists"' }
        @{ Name = "record-written-under-its-own-name"
           Find = '$tmpPath = Join-Path $Root ("writing-" + [guid]::NewGuid().ToString("N") + ".part")'
           Replace = '$tmpPath = $recPath' }
        @{ Name = "loser-leaves-its-temporary-file"
           Find = 'if ($moved -cne "moved" -and $moved -cne "unconfirmed") { try { [System.IO.File]::Delete($tmpPath) } catch { } }'
           Replace = '' }
        @{ Name = "dead-writers-file-never-swept"
           Find = '$null = Remove-HordeDecisionStoreLeftovers -Root $Root'
           Replace = '' }
        @{ Name = "live-writers-file-swept"
           Find = '.TotalSeconds -lt $minAgeSeconds) { continue }'
           Replace = '.TotalSeconds -lt 0) { continue }' }
        # --- the sweep's invariant: never a file some process holds open ---
        @{ Name = "held-leftover-deleted-by-name"
           Find = '$claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 1, [System.IO.FileOptions]::DeleteOnClose)'
           Replace = '[System.IO.File]::Delete($leftover); $claim = New-Object System.IO.MemoryStream' }
        @{ Name = "leftover-claimed-beside-other-holders"
           Find = '$claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 1, [System.IO.FileOptions]::DeleteOnClose)'
           Replace = '$claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete), 1, [System.IO.FileOptions]::DeleteOnClose)' }
        @{ Name = "leftover-claimed-and-not-removed"
           Find = '$claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 1, [System.IO.FileOptions]::DeleteOnClose)'
           Replace = '$claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 1, [System.IO.FileOptions]::None)' }
        @{ Name = "leftover-age-counted-in-minutes"
           Find = '.TotalSeconds -lt $minAgeSeconds) { continue }'
           Replace = '.TotalMinutes -lt $minAgeSeconds) { continue }' }
        @{ Name = "sweep-takes-names-that-are-not-its-own"
           Find = 'if ([System.IO.Path]::GetFileName($leftover) -cnotmatch $script:HordeDecisionStoreTempPattern) { continue }'
           Replace = '' }
        @{ Name = "sweep-fails-the-write-with-no-store"
           Find = 'try { $found = @([System.IO.Directory]::GetFiles($Root, "writing-*.part")) } catch { return 0 }'
           Replace = '$found = @([System.IO.Directory]::GetFiles($Root, "writing-*.part"))' }
        @{ Name = "name-not-padded-to-its-width"
           Find = 'return ($Sequence.ToString(("D" + (Get-HordeDecisionSequenceDigits)), [System.Globalization.CultureInfo]::InvariantCulture) + ".json")'
           Replace = 'return ($Sequence.ToString([System.Globalization.CultureInfo]::InvariantCulture) + ".json")' }
        @{ Name = "sequence-zero-allowed"
           Find = 'if ($Sequence -lt 1 -or $Sequence -gt $most) {'
           Replace = 'if ($Sequence -gt $most) {' }
        @{ Name = "eleven-digit-sequence-allowed"
           Find = 'if ($Sequence -lt 1 -or $Sequence -gt $most) {'
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
        @{ Name = "held-record-tried-once-whatever-the-setting"
           Find = 'for ($try = 1; $try -le $heldTries; $try++) {'
           Replace = 'for ($try = 1; $try -le 1; $try++) {' }
        @{ Name = "held-record-retried-without-a-wait"
           Find = '        Start-Sleep -Milliseconds $heldWaitMs'
           Replace = '' }
        @{ Name = "missing-record-is-an-error"
           Find = 'if ($code -eq 2 -or $code -eq 3) {'
           Replace = 'if ($false) {' }
        @{ Name = "other-names-read-as-records"
           Find = 'return (''\A([0-9]{'' + (Get-HordeDecisionSequenceDigits) + ''})\.json\z'')'
           Replace = 'return (''([0-9]{'' + (Get-HordeDecisionSequenceDigits) + ''})\.json'')' }
        @{ Name = "damaged-record-keeps-no-reason"
           Find = '[void]$records.Add([pscustomobject]@{ sequence = $seq; span = [long]1; file = $leaf; kind = $read.kind; data = $read.data; reason = $read.reason })'
           Replace = '[void]$records.Add([pscustomobject]@{ sequence = $seq; span = [long]1; file = $leaf; kind = $read.kind; data = $read.data; reason = "" })' }
        # --- gaps and strays ---
        @{ Name = "file-far-ahead-believed"
           Find = 'if ($gap -gt $maxGap) {'
           Replace = 'if ($false) {' }
        @{ Name = "gap-at-the-limit-is-a-stray"
           Find = 'if ($gap -gt $maxGap) {'
           Replace = 'if ($gap -ge $maxGap) {' }
        @{ Name = "gap-of-several-covers-one-number"
           Find = 'span = $gap;'
           Replace = 'span = [long]1;' }
        @{ Name = "gap-left-out"
           Find = 'if ($gap -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "gap-does-not-say-how-far"
           Find = 'if ($gap -gt 1) { $why ='
           Replace = 'if ($false) { $why =' }
        @{ Name = "number-of-another-width-read-as-a-record"
           Find = 'if ($leaf -cnotmatch $namePattern -or [long]$Matches[1] -lt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "record-zero-read"
           Find = 'if ($leaf -cnotmatch $namePattern -or [long]$Matches[1] -lt 1) {'
           Replace = 'if ($leaf -cnotmatch $namePattern) {' }
        @{ Name = "records-read-in-the-order-of-their-names-as-listed"
           Find = '    $numbered.Sort()'
           Replace = '    $numbered.Reverse()' }
        @{ Name = "not-written-through"
           Find = '$fs.Flush($true)'
           Replace = '$fs.Flush()'
           Expect = "survives"
           Reason = "whether the bytes reached the disk before the record took its name can only be seen by cutting the power; no suite can observe it, and the line is kept on remote/Journal.ps1's reasoning. The move's own durability is not this mutant: core/FileAtomic.ps1's flag and flush are mutated in test\mutations\file-move-new.psd1, and there each is caught" }
    )
}
