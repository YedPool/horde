# Mutations of files/Path.ps1, what it asks for the deny list and before a share: whether a path is
# on this machine's own drives (core's two questions, in the one order), and where a folder really is. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-path-places.psd1
# Each drops a question or asks them in the order that looks a host up, or mistakes a folder that
# is there for one that is not; test\test-files-deny.ps1 must fail for every one. The
# rest of files/Path.ps1 is in test\mutations\files-path.psd1, against the store's suite.
@{
    Target = "files\Path.ps1"
    Suite  = "test\test-files-deny.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- is the path on this machine's own drives: core's two questions, in the one order ---
        @{ Name = "drive-letter-question-not-asked"
           Find = '$why = Get-HordeDriveAliasRefusal -Path $Path'
           Replace = '$why = ""' }
        # Still refused, and with the same words: only the DNS cache shows that the host was asked.
        @{ Name = "network-question-asked-before-the-drive-letter-question"
           Find = '$why = Get-HordeDriveAliasRefusal -Path $Path'
           Replace = '$why = Get-HordeNetworkPathRefusal -Path $Path; if ($why -eq "") { $why = Get-HordeDriveAliasRefusal -Path $Path }' }
        @{ Name = "network-question-not-asked"
           Find = 'if ($why -eq "") { $why = Get-HordeNetworkPathRefusal -Path $Path }'
           Replace = '' }
        @{ Name = "share-does-not-add-its-own-sentence"
           Find = 'return ($why + ". A file is shared from one of this machine''s own drives: name it by its local path, or copy it to a local folder")'
           Replace = 'return $why' }
        # --- where a folder really is ---
        @{ Name = "folder-that-is-not-there-is-unknown"
           Find = 'if ($code -eq 2 -or $code -eq 3) { return [pscustomobject]@{ state = "absent"; path = "" } }'
           Replace = '' }
        @{ Name = "folder-whose-parent-is-not-there-is-unknown"
           Find = 'if ($code -eq 2 -or $code -eq 3) {'
           Replace = 'if ($code -eq 2) {' }
        @{ Name = "folder-that-cannot-be-opened-taken-for-absent"
           Find = 'if ($code -eq 2 -or $code -eq 3) {'
           Replace = 'if ($true) {' }
        @{ Name = "folder-opened-as-a-file-is"
           Find = '[System.IntPtr]::Zero, 3, 0x02000000, [System.IntPtr]::Zero)'
           Replace = '[System.IntPtr]::Zero, 3, 0, [System.IntPtr]::Zero)' }
        @{ Name = "folder-answered-by-the-path-that-was-asked"
           Find = 'return [pscustomobject]@{ state = "ok"; path = $final }'
           Replace = 'return [pscustomobject]@{ state = "ok"; path = $Path }' }
    )
}
