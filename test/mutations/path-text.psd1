# Mutations of core/PathText.ps1: the fold of A to Z, the network question, and what a drive letter
# stands for. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\path-text.psd1
# Each folds a character it must not, hands the fold to the runtime's case table, lets a network
# path through, or refuses a local one; test\test-path-text.ps1 must fail for every one.
#
# Every mutant here came with the two functions from the files store on 2026-10-13, unchanged: six
# from test\mutations\files-share.psd1 and thirteen from test\mutations\files-path.psd1. The mutants
# of the lines that CALL the two functions stayed there.
# No mutant here needs an administrator's token or a share that can be reached: a host that does not
# exist is enough to test with.
@{
    Target = "core\PathText.ps1"
    Suite  = "test\test-path-text.ps1"
    Mutations = @(
        # --- the fold: A to Z by the code's own hand, and nothing else ---
        @{ Name = "own-fold-hands-over-to-the-runtimes-case-table"
           Find = '    return $folded.ToString()'
           Replace = '    return $Text.ToLowerInvariant()' }
        @{ Name = "capital-a-not-folded"
           Find = 'if ($code -ge 65 -and $code -le 90) { $code += 32 }'
           Replace = 'if ($code -ge 66 -and $code -le 90) { $code += 32 }' }
        @{ Name = "capital-z-not-folded"
           Find = 'if ($code -ge 65 -and $code -le 90) { $code += 32 }'
           Replace = 'if ($code -ge 65 -and $code -le 89) { $code += 32 }' }
        @{ Name = "character-before-a-folded"
           Find = 'if ($code -ge 65 -and $code -le 90) { $code += 32 }'
           Replace = 'if ($code -ge 64 -and $code -le 90) { $code += 32 }' }
        @{ Name = "characters-after-z-folded"
           Find = 'if ($code -ge 65 -and $code -le 90) { $code += 32 }'
           Replace = 'if ($code -ge 65 -and $code -le 96) { $code += 32 }' }
        @{ Name = "every-capital-letter-of-every-alphabet-folded"
           Find = 'if ($code -ge 65 -and $code -le 90) { $code += 32 }'
           Replace = 'if ([char]::IsUpper($character)) { $code = [int][char]::ToLowerInvariant($character) }' }
        # --- a network path is refused from its text, and a network drive by its type ---
        @{ Name = "network-path-not-refused-from-its-text"
           Find = 'if ($unc) { return ('
           Replace = 'if ($false) { return (' }
        @{ Name = "only-backslashes-make-a-network-path"
           Find = '$unc = ($Path -cmatch ''\A[\\/]{2}'' -and'
           Replace = '$unc = ($Path -cmatch ''\A\\{2}'' -and' }
        @{ Name = "long-path-prefix-taken-for-a-network-path"
           Find = '$unc = ($Path -cmatch ''\A[\\/]{2}'' -and $Path -cnotmatch ''\A[\\/]{2}[.?][\\/]'')'
           Replace = '$unc = ($Path -cmatch ''\A[\\/]{2}'')' }
        @{ Name = "prefixed-unc-forms-not-network-paths"
           Find = 'if (-not $unc) { $unc = ($Path -cmatch'
           Replace = 'if ($false) { $unc = ($Path -cmatch' }
        @{ Name = "unc-prefix-seen-only-in-capitals"
           Find = '[\\/][Uu][Nn][Cc](?:[\\/]|\z)'')'
           Replace = '[\\/]UNC(?:[\\/]|\z)'')' }
        @{ Name = "unc-prefix-seen-only-with-backslashes"
           Find = '''\A(?:[\\/]{2}[.?]|\\\?\?)[\\/][Uu][Nn][Cc]'
           Replace = '''\A(?:\\{2}[.?]|\\\?\?)\\[Uu][Nn][Cc]' }
        @{ Name = "device-prefix-unc-form-missed"
           Find = '''\A(?:[\\/]{2}[.?]|\\\?\?)[\\/][Uu][Nn][Cc]'
           Replace = '''\A(?:[\\/]{2}[?]|\\\?\?)[\\/][Uu][Nn][Cc]' }
        @{ Name = "nt-form-unc-missed"
           Find = '''\A(?:[\\/]{2}[.?]|\\\?\?)[\\/][Uu][Nn][Cc]'
           Replace = '''\A(?:[\\/]{2}[.?])[\\/][Uu][Nn][Cc]' }
        @{ Name = "unc-prefix-with-nothing-after-it-missed"
           Find = '[\\/][Uu][Nn][Cc](?:[\\/]|\z)'')'
           Replace = '[\\/][Uu][Nn][Cc][\\/]'')' }
        @{ Name = "network-drive-not-refused"
           Find = 'if ($type -eq [System.IO.DriveType]::Network) { return ('
           Replace = 'if ($false) { return (' }
        @{ Name = "every-drive-is-a-network-drive"
           Find = 'if ($type -eq [System.IO.DriveType]::Network) { return ('
           Replace = 'if ($true) { return (' }
        @{ Name = "network-drive-behind-the-prefix-missed"
           Find = 'if ($Path -cmatch ''\A(?:\\\\\?\\)?([A-Za-z]):'') {'
           Replace = 'if ($Path -cmatch ''\A([A-Za-z]):'') {' }
        @{ Name = "network-drive-with-a-small-letter-missed"
           Find = 'if ($Path -cmatch ''\A(?:\\\\\?\\)?([A-Za-z]):'') {'
           Replace = 'if ($Path -cmatch ''\A(?:\\\\\?\\)?([A-Z]):'') {' }
        # --- the reason is every caller's (2026-10-13): no word of what the caller was doing ---
        @{ Name = "network-reason-speaks-of-sharing-again"
           Find = '    $local = "only a path on one of this machine''s own drives is taken"'
           Replace = '    $local = "only a file on one of this machine''s own drives is shared: name it by its local path, or copy it to a local folder"' }
        @{ Name = "drive-letter-reason-speaks-of-sharing"
           Find = '    $ownDrives = "only a path on one of this machine''s own drives is taken"'
           Replace = '    $ownDrives = "only a file on one of this machine''s own drives is shared"' }
        # --- what a drive letter stands for ---
        @{ Name = "no-letter-stands-for-anything"
           Find = 'if ([HordeNative.DriveName]::QueryDosDevice($Letter + ":", $text, 1024) -le 0) { return "" }'
           Replace = 'if ($true) { return "" }' }
        @{ Name = "letter-behind-the-prefix-not-asked-what-it-stands-for"
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
           Find = 'if ((Get-HordeNetworkPathRefusal -Path ($last + ":\")) -ne "") { return ('
           Replace = 'if ($false) { return (' }
        @{ Name = "every-letter-over-another-refused"
           Find = 'if ((Get-HordeNetworkPathRefusal -Path ($last + ":\")) -ne "") { return ('
           Replace = 'if ($true) { return (' }
        @{ Name = "type-asked-of-the-first-letter"
           Find = 'if ((Get-HordeNetworkPathRefusal -Path ($last + ":\")) -ne "") { return ('
           Replace = 'if ((Get-HordeNetworkPathRefusal -Path ($first + ":\")) -ne "") { return (' }
        @{ Name = "letter-that-stands-for-itself-is-this-questions"
           Find = 'if ([string]::Equals($last, $first, [System.StringComparison]::Ordinal)) { return "" }'
           Replace = '' }
        @{ Name = "refusal-does-not-name-the-network-drive"
           Find = 'that stands for a network drive (" + $last + ":), and "'
           Replace = 'that stands for a network drive, and "' }
    )
}
