# Mutations of files/Key.ps1: the machine's own key, which file ids are made with. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-key.psd1
# Each makes a weaker key, lets others read it, uses a damaged one, or makes a second one;
# test\test-files-store.ps1 must fail for every one. The mutant only racing processes can see is in
# test\mutations\files-key-race.psd1.
@{
    Target = "files\Key.ps1"
    Suite  = "test\test-files-store.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- what the key is, and where ---
        @{ Name = "key-of-sixteen-bytes"
           Find = '    return 32'
           Replace = '    return 16' }
        @{ Name = "key-kept-under-another-name"
           Find = 'return (Join-Path (Join-Path $base "keys") "files-id.key")'
           Replace = 'return (Join-Path (Join-Path $base "keys") "files.key")' }
        @{ Name = "key-is-the-same-byte-thirty-two-times"
           Find = 'try { $generator.GetBytes($fresh) } finally { $generator.Dispose() }'
           Replace = 'for ($at = 0; $at -lt $fresh.Length; $at++) { $fresh[$at] = 7 }; $generator.Dispose()' }
        # --- only the current user may open it ---
        @{ Name = "key-inherits-its-folders-access-list"
           Find = '$access.SetAccessRuleProtection($true, $false)'
           Replace = '$access.SetAccessRuleProtection($false, $false)' }
        @{ Name = "key-made-without-its-access-list"
           Find = '[System.Security.AccessControl.FileSystemRights]::FullControl, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::WriteThrough, $access)'
           Replace = '[System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::WriteThrough)' }
        @{ Name = "everyone-may-read-the-key"
           Find = '[System.Security.AccessControl.FileSystemRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)))'
           Replace = '[System.Security.AccessControl.FileSystemRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow))); $access.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule((New-Object System.Security.Principal.SecurityIdentifier("S-1-1-0")), [System.Security.AccessControl.FileSystemRights]::Read, [System.Security.AccessControl.AccessControlType]::Allow)))' }
        @{ Name = "user-may-only-read-the-key"
           Find = '[System.Security.AccessControl.FileSystemRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)))'
           Replace = '[System.Security.AccessControl.FileSystemRights]::Read, [System.Security.AccessControl.AccessControlType]::Allow)))' }
        # --- a key is made once ---
        @{ Name = "key-move-replaces-the-key-that-is-there"
           Find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $Path'
           Replace = '[System.IO.File]::Copy($tmpPath, $Path, $true); $moved = "moved"' }
        @{ Name = "loser-leaves-its-temporary-key"
           Find = 'if ($moved -cne "moved") { try { [System.IO.File]::Delete($tmpPath) } catch { } }'
           Replace = '' }
        @{ Name = "taken-name-told-created"
           Find = '    if ($moved -ceq "moved") { return "created" }'
           Replace = '    if ($true) { return "created" }' }
        # --- a key that is damaged is refused ---
        @{ Name = "folder-in-the-keys-place-read-as-no-key"
           Find = 'if ([System.IO.Directory]::Exists($Path)) { return (& $refuse "is a folder, not a file") }'
           Replace = '' }
        @{ Name = "key-read-through-a-link"
           Find = 'if (Test-HordeFilesStoreLink -Path $Path) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "key-cut-short-used"
           Find = 'if ($have -ne $want) { return'
           Replace = 'if ($have -gt $want) { return' }
        @{ Name = "key-too-long-used"
           Find = 'if ($have -ne $want) { return'
           Replace = 'if ($have -lt $want) { return' }
        @{ Name = "key-too-long-not-seen"
           Find = '$buffer = New-Object byte[] ($want + 1)'
           Replace = '$buffer = New-Object byte[] ($want)' }
        @{ Name = "key-of-zeros-used"
           Find = 'if (@($key | Where-Object { $_ -ne 0 }).Count -eq 0) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "held-key-not-waited-for"
           Find = 'if ($busyCodes -contains (Get-HordeFilesStoreWin32Code $_)) { $busy = $true }'
           Replace = 'if ($false) { $busy = $true }' }
        @{ Name = "held-key-waited-for-without-end-of-tries"
           Find = 'if ($try -eq $HeldTries) { return (& $refuse ("is still held by another process after "'
           Replace = 'if ($try -eq $HeldTries) { break }; if ($false) { return (& $refuse ("is still held by another process after "' }
        @{ Name = "refusal-does-not-name-the-key-file"
           Find = 'reason = ("the key that file ids are made with, ''" + $Path + "'', " + $Why) } }'
           Replace = 'reason = ("the key that file ids are made with " + $Why) } }' }
        # --- a key that is gone is never made again ---
        @{ Name = "missing-key-made-again-whatever-the-store-holds"
           Find = 'if (Test-HordeFilesStoreHasRecord -Root $Root) {'
           Replace = 'if ($false) {' }
        @{ Name = "store-never-seen-to-hold-a-record"
           Find = 'if ([System.IO.Path]::GetFileName($full) -cmatch $format.record) { return $true }'
           Replace = '' }
        @{ Name = "any-json-file-counts-as-a-record"
           Find = 'if ([System.IO.Path]::GetFileName($full) -cmatch $format.record) { return $true }'
           Replace = 'return $true' }
        @{ Name = "key-made-meanwhile-refused-as-missing"
           Find = 'if ($again.state -cne "absent") { return (& $answer $again) }'
           Replace = '' }
        @{ Name = "damaged-key-answered-as-good"
           Find = 'return [pscustomobject]@{ ok = ($Read.state -ceq "ok"); key = $Read.key; reason = $Read.reason }'
           Replace = 'return [pscustomobject]@{ ok = $true; key = (New-Object byte[] 32); reason = $Read.reason }' }
    )
}
