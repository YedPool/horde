# Mutations of files/Path.ps1, the two questions it asks for the deny list: what a drive letter
# stands for, and where a folder really is. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-path-places.psd1
# Each lets a letter that stands for a network drive by, follows a chain wrongly, or mistakes a
# folder that is there for one that is not; test\test-files-deny.ps1 must fail for every one. The
# rest of files/Path.ps1 is in test\mutations\files-path.psd1, against the store's suite.
@{
    Target = "files\Path.ps1"
    Suite  = "test\test-files-deny.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- what a drive letter stands for ---
        @{ Name = "no-letter-stands-for-anything"
           Find = 'if ([HordeNative.FilePlace]::QueryDosDevice($Letter + ":", $text, 1024) -le 0) { return "" }'
           Replace = 'if ($true) { return "" }' }
        @{ Name = "letter-behind-the-prefix-not-seen"
           Find = 'if ($Path -cnotmatch ''\A(?:\\\\\?\\)?([A-Za-z]):'') { return "" }'
           Replace = 'if ($Path -cnotmatch ''\A([A-Za-z]):'') { return "" }' }
        @{ Name = "chain-of-letters-not-followed"
           Find = '        $last = $Matches[1]'
           Replace = '        $last = $first' }
        @{ Name = "chain-followed-one-letter-only"
           Find = 'for ($hop = 1; $hop -le 8; $hop++) {'
           Replace = 'for ($hop = 1; $hop -le 1; $hop++) {' }
        @{ Name = "ring-of-letters-not-refused"
           Find = 'if (-not $ended) { return ('
           Replace = 'if ($false) { return (' }
        @{ Name = "type-of-the-last-letter-not-asked"
           Find = 'if ((Get-HordeFilesNetworkRefusal -Path ($last + ":\")) -ne "") { return ('
           Replace = 'if ($false) { return (' }
        @{ Name = "every-letter-over-another-refused"
           Find = 'if ((Get-HordeFilesNetworkRefusal -Path ($last + ":\")) -ne "") { return ('
           Replace = 'if ($true) { return (' }
        @{ Name = "type-asked-of-the-first-letter"
           Find = 'if ((Get-HordeFilesNetworkRefusal -Path ($last + ":\")) -ne "") { return ('
           Replace = 'if ((Get-HordeFilesNetworkRefusal -Path ($first + ":\")) -ne "") { return (' }
        @{ Name = "letter-that-stands-for-itself-is-this-questions"
           Find = 'if ([string]::Equals($last, $first, [System.StringComparison]::Ordinal)) { return "" }'
           Replace = '' }
        @{ Name = "refusal-does-not-name-the-network-drive"
           Find = 'that stands for a network drive (" + $last + ":), and "'
           Replace = 'that stands for a network drive, and "' }
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
