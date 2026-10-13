# Mutations of files/Path.ps1: which file a path really names. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-path.psd1
# Each opens or looks at something that must be refused from its text or its drive's type, or takes
# a network path for a file's one path; test\test-files-store.ps1 must fail for every one.
#
# WHAT THE BOX MUST BE ABLE TO DO for every mutant to be seen: make 8.3 short names (short-names-kept).
# Where it cannot, the suite prints [SKIP] with the reason and that mutant is reported as not caught.
# No mutant here needs an administrator's token or a share that can be reached: a network path is
# refused before anything looks at it, so a host that does not exist is enough to test with.
@{
    Target = "files\Path.ps1"
    Suite  = "test\test-files-store.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- refused from the text: the device form ---
        @{ Name = "device-form-opened"
           Find = 'elseif ($rest -match ''\A(?:[\\/]{2}[.?]|\\\?\?)[\\/]'') { return'
           Replace = 'elseif ($false) { return' }
        @{ Name = "only-the-dot-device-form-refused"
           Find = '''\A(?:[\\/]{2}[.?]|\\\?\?)[\\/]'''
           Replace = '''\A(?:[\\/]{2}[.]|\\\?\?)[\\/]''' }
        @{ Name = "nt-device-form-opened"
           Find = '''\A(?:[\\/]{2}[.?]|\\\?\?)[\\/]'''
           Replace = '''\A(?:[\\/]{2}[.?])[\\/]''' }
        @{ Name = "device-form-with-forward-slashes-opened"
           Find = '''\A(?:[\\/]{2}[.?]|\\\?\?)[\\/]'''
           Replace = '''\A(?:\\{2}[.?]|\\\?\?)\\''' }
        @{ Name = "prefixed-path-taken-for-a-device"
           Find = '    if ($rest -match ''\A\\\\\?\\[A-Za-z]:\\'') { $rest = $rest.Substring(4) }'
           Replace = '    if ($false) { }' }
        @{ Name = "nothing-looked-for-behind-the-prefix"
           Find = '    if ($rest -match ''\A\\\\\?\\[A-Za-z]:\\'') { $rest = $rest.Substring(4) }'
           Replace = '    if ($rest -match ''\A\\\\\?\\[A-Za-z]:\\'') { return "" }' }
        # --- refused from the text: a device's name ---
        @{ Name = "device-names-not-looked-for"
           Find = 'foreach ($part in @($rest -split ''[\\/]'')) {'
           Replace = 'foreach ($part in @()) {' }
        @{ Name = "device-name-looked-for-only-in-the-last-part"
           Find = 'foreach ($part in @($rest -split ''[\\/]'')) {'
           Replace = 'foreach ($part in @(@($rest -split ''[\\/]'')[-1])) {' }
        @{ Name = "device-name-with-an-extension-opened"
           Find = '$base = (@($part -split ''[.:]'')[0]).TrimEnd('' '')'
           Replace = '$base = $part' }
        @{ Name = "device-name-with-a-blank-after-it-opened"
           Find = '$base = (@($part -split ''[.:]'')[0]).TrimEnd('' '')'
           Replace = '$base = (@($part -split ''[.:]'')[0])' }
        @{ Name = "serial-ports-not-devices"
           Find = 'COM[0-9\u00B9\u00B2\u00B3]|'
           Replace = '' }
        @{ Name = "superscript-port-numbers-not-devices"
           Find = 'COM[0-9\u00B9\u00B2\u00B3]|'
           Replace = 'COM[0-9]|' }
        @{ Name = "port-zero-not-a-device"
           Find = 'COM[0-9\u00B9\u00B2\u00B3]|'
           Replace = 'COM[1-9\u00B9\u00B2\u00B3]|' }
        @{ Name = "printer-ports-not-devices"
           Find = 'LPT[0-9\u00B9\u00B2\u00B3]|'
           Replace = '' }
        @{ Name = "console-handles-not-devices"
           Find = '|CONIN\$|CONOUT\$)\z'
           Replace = ')\z' }
        @{ Name = "device-name-found-inside-a-longer-name"
           Find = '\A(?:CON|PRN|AUX|NUL|'
           Replace = '(?:CON|PRN|AUX|NUL|' }
        # --- refused from the text: a stream inside a file ---
        @{ Name = "stream-opened"
           Find = 'if (($rest -replace ''\A[A-Za-z]:'', '''').Contains(":")) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "drive-letter-taken-for-a-stream"
           Find = 'if (($rest -replace ''\A[A-Za-z]:'', '''').Contains(":")) { return'
           Replace = 'if ($rest.Contains(":")) { return' }
        # --- the final path of the open handle ---
        @{ Name = "short-names-kept"
           Find = '$Stream.SafeFileHandle, $text, $size, 0)'
           Replace = '$Stream.SafeFileHandle, $text, $size, 0x8)' }
        @{ Name = "final-path-not-asked-again-when-it-did-not-fit"
           Find = 'if ($length -lt $size) { return $text.ToString() }'
           Replace = 'return $text.ToString()' }
        @{ Name = "no-final-path-is-not-refused-as-that"
           Find = 'if ($Final -eq "") { return (& $refuse "Windows would not say'
           Replace = 'if ($false) { return (& $refuse "Windows would not say' }
        @{ Name = "final-path-kept-with-its-prefix"
           Find = 'return [pscustomobject]@{ ok = $true; path = $Final.Substring(4); reason = "" }'
           Replace = 'return [pscustomobject]@{ ok = $true; path = $Final; reason = "" }' }
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
        @{ Name = "network-final-path-used-as-it-is"
           Find = 'if ($Final -cnotmatch ''\A\\\\\?\\[A-Za-z]:\\'') { return (& $refuse ('
           Replace = 'if ($false) { return (& $refuse (' }
        @{ Name = "own-drive-share-brought-home-on-its-word"
           Find = 'if ($Final -cnotmatch ''\A\\\\\?\\[A-Za-z]:\\'') { return (& $refuse ('
           Replace = 'if ($Final -cmatch ''\A\\\\\?\\UNC\\[^\\]+\\([A-Za-z])\$\\(.+)\z'') { return [pscustomobject]@{ ok = $true; path = ($Matches[1] + ":\" + $Matches[2]); reason = "" } }; if ($Final -cnotmatch ''\A\\\\\?\\[A-Za-z]:\\'') { return (& $refuse (' }        # --- the open ---
        @{ Name = "unreadable-file-not-said-so"
           Find = 'reason = ("it cannot be read: " + $_.Exception.GetBaseException().Message) } }'
           Replace = 'reason = "" } }' }
        @{ Name = "refused-file-stays-open"
           Find = 'finally { if ($null -eq $where -or -not $where.ok) { $stream.Dispose() } }'
           Replace = 'finally { }' }
        @{ Name = "file-held-against-every-reader"
           Find = '[System.IO.FileAccess]::Read, [System.IO.FileShare]::Read) }'
           Replace = '[System.IO.FileAccess]::Read, [System.IO.FileShare]::None) }' }
    )
}
