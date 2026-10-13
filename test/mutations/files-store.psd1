# Mutations of files/Store.ps1, the files store's write-once entries. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-store.psd1
# Each breaks one promise of the store; test\test-files-store.ps1 must fail for every one, except
# those declared Expect = "survives". The mutants only racing processes can see are in
# test\mutations\files-store-race.psd1.
@{
    Target = "files\Store.ps1"
    Suite  = "test\test-files-store.ps1"
    Mutations = @(
        # --- an entry is put in place once, by a move that does not replace ---
        @{ Name = "move-overwrites"
           Find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $entryPath -Open $fs'
           Replace = '[System.IO.File]::WriteAllBytes($entryPath, $Bytes); $moved = "moved"' }
        @{ Name = "writer-lets-go-before-the-move"
           Find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $entryPath -Open $fs'
           Replace = '$fs.Dispose(); $moved = Move-HordeFileNewDurable -From $tmpPath -To $entryPath -Open $null' }
        @{ Name = "move-not-handed-the-writers-handle"
           Find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $entryPath -Open $fs'
           Replace = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $entryPath -Open $null' }
        @{ Name = "moved-before-it-is-written"
           Find = '        $fs.Write($Bytes, 0, $Bytes.Length)'
           Replace = '        $moved = Move-HordeFileNewDurable -From $tmpPath -To $entryPath -Open $fs; $fs.Write($Bytes, 0, $Bytes.Length); return "created"' }
        @{ Name = "unconfirmed-reads-as-created"
           Find = 'if ($moved -ceq "unconfirmed") { return "unconfirmed" }'
           Replace = 'if ($moved -ceq "unconfirmed") { return "created" }' }
        @{ Name = "any-answer-of-the-move-reads-as-created"
           Find = 'if ($moved -ceq "moved") { return "created" }'
           Replace = 'if ($true) { return "created" }' }
        @{ Name = "taken-name-is-an-error"
           Find = 'if ($moved -ceq "exists" -and [System.IO.File]::Exists($entryPath)) { return "exists" }'
           Replace = '' }
        @{ Name = "folder-of-the-entry-name-reads-as-taken"
           Find = 'if ($moved -ceq "exists" -and [System.IO.File]::Exists($entryPath)) { return "exists" }'
           Replace = 'if ($moved -ceq "exists") { return "exists" }' }
        @{ Name = "entry-written-under-its-own-name"
           Find = '$tmpPath = Join-Path $Root ("writing-" + [guid]::NewGuid().ToString("N") + ".part")'
           Replace = '$tmpPath = $entryPath' }
        @{ Name = "loser-leaves-its-temporary-file"
           Find = 'if ($moved -cne "moved" -and $moved -cne "unconfirmed") { try { [System.IO.File]::Delete($tmpPath) } catch { } }'
           Replace = '' }
        @{ Name = "any-name-is-written"
           Find = 'if ($Name -cnotmatch $format.record -and $Name -cnotmatch $format.bytes) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "relative-root-written"
           Find = 'if (-not [System.IO.Path]::IsPathRooted("$Root")) { throw ("the files store needs an absolute folder, not ''" + $Root + "''") }'
           Replace = '' }
        # --- names ---
        @{ Name = "version-zero-has-a-name"
           Find = 'if ($Version -lt 1 -or $Version -gt $format.maxVersion) {'
           Replace = 'if ($Version -gt $format.maxVersion) {' }
        @{ Name = "seven-digit-version-has-a-name"
           Find = 'if ($Version -lt 1 -or $Version -gt $format.maxVersion) {'
           Replace = 'if ($Version -lt 1) {' }
        @{ Name = "version-not-padded-to-its-width"
           Find = '$Version.ToString(("D" + $format.versionDigits), [System.Globalization.CultureInfo]::InvariantCulture)'
           Replace = '$Version.ToString([System.Globalization.CultureInfo]::InvariantCulture)' }
        @{ Name = "any-file-id-has-a-record-name"
           Find = 'if ($FileId -cnotmatch ''\A[0-9a-f]{32}\z'') { throw ("a file id is 32 lower-case hex digits, not ''" + $FileId + "''") }'
           Replace = '' }
        @{ Name = "any-digest-has-a-bytes-name"
           Find = 'if ($Sha256 -cnotmatch ''\A[0-9a-f]{64}\z'') { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "store-is-in-another-folder"
           Find = 'return (Join-Path (Join-Path $base "store") "files")'
           Replace = 'return (Join-Path (Join-Path $base "store") "file")' }
        @{ Name = "store-is-always-in-the-real-home"
           Find = 'if ($base -eq "") { $base = Get-HordeHome }'
           Replace = '$base = Get-HordeHome' }
        # --- the sweep's invariant ---
        @{ Name = "dead-writers-file-never-swept"
           Find = '$null = Remove-HordeFilesStoreLeftovers -Root $Root -MinAgeSeconds $LeftoverMinAgeSeconds'
           Replace = '' }
        @{ Name = "sweep-ignores-the-age-it-is-handed"
           Find = '$null = Remove-HordeFilesStoreLeftovers -Root $Root -MinAgeSeconds $LeftoverMinAgeSeconds'
           Replace = '$null = Remove-HordeFilesStoreLeftovers -Root $Root -MinAgeSeconds 1' }
        @{ Name = "live-writers-file-swept"
           Find = '.TotalSeconds -lt $MinAgeSeconds) { continue }'
           Replace = '.TotalSeconds -lt 0) { continue }' }
        @{ Name = "leftover-age-counted-in-minutes"
           Find = '.TotalSeconds -lt $MinAgeSeconds) { continue }'
           Replace = '.TotalMinutes -lt $MinAgeSeconds) { continue }' }
        @{ Name = "held-leftover-deleted-by-name"
           Find = '$claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 1, [System.IO.FileOptions]::DeleteOnClose)'
           Replace = '[System.IO.File]::Delete($leftover); $claim = New-Object System.IO.MemoryStream' }
        @{ Name = "leftover-claimed-beside-other-holders"
           Find = '$claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 1, [System.IO.FileOptions]::DeleteOnClose)'
           Replace = '$claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete), 1, [System.IO.FileOptions]::DeleteOnClose)' }
        @{ Name = "leftover-claimed-and-not-removed"
           Find = '$claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 1, [System.IO.FileOptions]::DeleteOnClose)'
           Replace = '$claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 1, [System.IO.FileOptions]::None)' }
        @{ Name = "leftover-claimed-through-a-link"
           Find = '            if (Test-HordeFilesStoreLink -Path $leftover) { continue }'
           Replace = '' }
        @{ Name = "sweep-in-a-store-folder-that-is-a-link"
           Find = '    if ([System.IO.Directory]::Exists($Root) -and (Test-HordeFilesStoreLink -Path $Root)) { return 0 }'
           Replace = '' }
        @{ Name = "no-entry-is-ever-a-link"
           Find = '    try { return (([System.IO.File]::GetAttributes($Path) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) } catch { return $true }'
           Replace = '    return $false' }
        @{ Name = "sweep-takes-names-that-are-not-its-own"
           Find = 'if ([System.IO.Path]::GetFileName($leftover) -cnotmatch $format.temporary) { continue }'
           Replace = '' }
        @{ Name = "sweep-fails-with-no-store"
           Find = 'try { $found = @([System.IO.Directory]::GetFiles($Root, "writing-*.part")) } catch { return 0 }'
           Replace = '$found = @([System.IO.Directory]::GetFiles($Root, "writing-*.part"))' }
        # --- a file's versions, read from the names ---
        @{ Name = "last-version-is-always-none"
           Find = '    return $last'
           Replace = '    return 0' }
        @{ Name = "last-version-fails-with-no-store"
           Find = '    if (-not [System.IO.Directory]::Exists($Root)) { return 0 }'
           Replace = '' }
        @{ Name = "any-text-is-looked-for-as-a-file-id"
           Find = 'if ($FileId -cnotmatch ''\A[0-9a-f]{32}\z'') { throw ("the file whose versions are asked for needs an id of 32 lower-case hex digits, not ''" + $FileId + "''") }'
           Replace = '' }
        # --- reading ---
        @{ Name = "record-read-through-a-link"
           Find = 'if (Test-HordeFilesStoreLink -Path $Path) { return [pscustomobject]@{ kind = "error"; data = $null; reason = "it is a link, or cannot be looked at; a record is never read through a link" } }'
           Replace = '' }
        @{ Name = "empty-file-not-named-empty"
           Find = 'if ("$text".Trim() -eq "") { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is empty" } }'
           Replace = '' }
        @{ Name = "cut-json-throws"
           Find = 'try { $data = $text | ConvertFrom-Json } catch { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is not complete JSON: it was damaged, or made by hand" } }'
           Replace = '$data = $text | ConvertFrom-Json' }
        @{ Name = "non-object-read-as-a-record"
           Find = 'if ($null -eq $data -or $data -isnot [System.Management.Automation.PSCustomObject]) { return [pscustomobject]@{ kind = "torn"; data = $null; reason = "it is not a JSON object" } }'
           Replace = '' }
        @{ Name = "bad-bytes-read-as-other-letters"
           Find = '$utf8 = New-Object System.Text.UTF8Encoding($false, $true)'
           Replace = '$utf8 = New-Object System.Text.UTF8Encoding($false, $false)' }
        @{ Name = "held-record-is-an-error"
           Find = 'if ($format.busyCodes -contains (Get-HordeFilesStoreWin32Code $_)) { $busy = $true }'
           Replace = 'if ($false) { $busy = $true }' }
        @{ Name = "sharing-violation-not-a-busy-code"
           Find = 'busyCodes = @(32, 33)'
           Replace = 'busyCodes = @(33)' }
        @{ Name = "no-read-error-has-a-code"
           Find = '    return ($ex.HResult -band 0xFFFF)'
           Replace = '    return -1' }
        @{ Name = "held-record-tried-once-whatever-it-is-handed"
           Find = 'for ($try = 1; $try -le $HeldTries; $try++) {'
           Replace = 'for ($try = 1; $try -le 1; $try++) {' }
        @{ Name = "held-record-retried-without-a-wait"
           Find = '        Start-Sleep -Milliseconds $HeldWaitMs'
           Replace = '' }
        @{ Name = "other-names-read-as-records"
           Find = 'record = ''\A([0-9a-f]{32})\.([0-9]{6})\.json\z'''
           Replace = 'record = ''([0-9a-f]{32})\.([0-9]{6})\.json''' }
        @{ Name = "version-zero-read"
           Find = 'if ($leaf -cnotmatch $format.record -or [int]$Matches[2] -lt 1) {'
           Replace = 'if ($leaf -cnotmatch $format.record) {' }
        @{ Name = "damaged-record-keeps-no-reason"
           Find = 'kind = $read.kind; data = $read.data; reason = $read.reason })'
           Replace = 'kind = $read.kind; data = $read.data; reason = "" })' }
        @{ Name = "link-named-like-a-leftover-not-reported"
           Find = '            [void]$strays.Add([pscustomobject]@{ file = $leaf; reason = "it is a link named like a writer''s temporary file; it is never followed and never removed, so whoever made it should remove it" })'
           Replace = '' }
        @{ Name = "file-in-place-of-the-store-reads-as-empty"
           Find = 'if ([System.IO.File]::Exists($Root)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "relative-root-read"
           Find = 'if (-not $rooted) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "reading-creates-the-store"
           Find = 'if (-not [System.IO.Directory]::Exists($Root)) { return [pscustomobject]@{ state = "absent"'
           Replace = 'if (-not [System.IO.Directory]::Exists($Root)) { [void][System.IO.Directory]::CreateDirectory($Root); return [pscustomobject]@{ state = "absent"' }
        @{ Name = "not-written-through"
           Find = '$fs.Flush($true)'
           Replace = '$fs.Flush()'
           Expect = "survives"
           Reason = "whether the bytes reached the disk before the entry took its name can only be seen by cutting the power; no suite can observe it, and the line is kept on decisions/Store.ps1's reasoning. The move's own durability is not this mutant: core/FileAtomic.ps1's flag and flush are mutated in test\mutations\file-move-new.psd1, and there each is caught" }
    )
}
