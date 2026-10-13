# Mutations of core/PathText.ps1: the fold of A to Z, and the network question. Run:
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
           Find = 'if ($type -ceq "Network") { return ('
           Replace = 'if ($false) { return (' }
        @{ Name = "every-drive-is-a-network-drive"
           Find = 'if ($type -ceq "Network") { return ('
           Replace = 'if ($true) { return (' }
        @{ Name = "network-drive-behind-the-prefix-missed"
           Find = 'if ($Path -cmatch ''\A(?:\\\\\?\\)?([A-Za-z]):'') {'
           Replace = 'if ($Path -cmatch ''\A([A-Za-z]):'') {' }
        @{ Name = "network-drive-with-a-small-letter-missed"
           Find = 'if ($Path -cmatch ''\A(?:\\\\\?\\)?([A-Za-z]):'') {'
           Replace = 'if ($Path -cmatch ''\A(?:\\\\\?\\)?([A-Z]):'') {' }
        @{ Name = "drive-type-compared-without-its-case"
           Find = 'if ($type -ceq "Network") { return ('
           Replace = 'if ($type -eq "Network") { return (' }
        @{ Name = "drive-type-asked-of-no-letter-in-particular"
           Find = '$type = Get-HordeDriveLetterType -Letter $letter'
           Replace = '$type = Get-HordeDriveLetterType -Letter "R"' }
        @{ Name = "drive-type-not-asked"
           Find = '$type = Get-HordeDriveLetterType -Letter $letter'
           Replace = '$type = ""' }
        @{ Name = "every-letter-is-of-one-type"
           Find = 'try { return ("" + (New-Object System.IO.DriveInfo($Letter)).DriveType) }'
           Replace = 'try { return "Fixed" }' }
        @{ Name = "a-letter-that-cannot-be-asked-throws"
           Find = 'catch { return "" }'
           Replace = 'catch { throw }' }
    )
}
