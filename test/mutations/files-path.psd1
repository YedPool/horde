# Mutations of files/Path.ps1: which file a path really names. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-path.psd1
# Each opens something that must be refused from its text, or takes a path for a file's one path
# without the proof; test\test-files-store.ps1 must fail for every one, except those declared
# Expect = "survives".
#
# WHAT THE BOX MUST BE ABLE TO DO for every mutant to be seen: make 8.3 short names (short-names-kept)
# and open its own drive share, which needs an administrator's token (file-held-against-every-reader).
# Where it cannot, the suite prints [SKIP] with the reason and that mutant is reported as not caught.
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
           Find = 'elseif ($rest -match ''\A\\\\\?\\[A-Za-z]:\\'') { $rest = $rest.Substring(4) }'
           Replace = 'elseif ($false) { }' }
        @{ Name = "nothing-looked-for-behind-the-prefix"
           Find = 'elseif ($rest -match ''\A\\\\\?\\[A-Za-z]:\\'') { $rest = $rest.Substring(4) }'
           Replace = 'elseif ($rest -match ''\A\\\\\?\\[A-Za-z]:\\'') { return "" }' }
        @{ Name = "prefixed-unc-path-taken-for-a-device"
           Find = 'if ($rest -match ''\A\\\\\?\\UNC\\'') { $rest = $rest.Substring(8) }'
           Replace = 'if ($false) { }' }
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
        # --- a network path is brought home by proof, or refused ---
        @{ Name = "network-path-used-as-it-is"
           Find = '\$\\(.+)\z'') { return (& $refuse $network) }'
           Replace = '\$\\(.+)\z'') { return [pscustomobject]@{ ok = $true; path = $shown; reason = "" } }' }
        @{ Name = "drive-share-trusted-without-proof"
           Find = 'if (-not (Test-HordeFilesSameFile -One $mine -Other (Get-HordeFilesIdentity -Stream $beside)) -or $local'
           Replace = 'if ($local' }
        @{ Name = "drive-share-with-no-local-file-trusted"
           Find = '[System.IO.FileShare]::Delete)) } catch { return (& $refuse $network) }'
           Replace = '[System.IO.FileShare]::Delete)) } catch { return [pscustomobject]@{ ok = $true; path = $candidate; reason = "" } }' }
        @{ Name = "no-identity-is-the-same-as-no-identity"
           Find = 'return ($One -ne "" -and $One -ceq $Other)'
           Replace = 'return ($One -ceq $Other)' }
        @{ Name = "every-file-is-the-same-file"
           Find = 'return ($One -ne "" -and $One -ceq $Other)'
           Replace = 'return ($One -ne "")' }
        @{ Name = "a-file-is-known-by-its-volume-size-and-time-alone"
           Find = '@($info.VolumeSerial, $info.IndexHigh, $info.IndexLow, $info.SizeHigh,'
           Replace = '@($info.VolumeSerial, $info.SizeHigh,' }
        @{ Name = "file-with-no-index-has-an-identity"
           Find = 'if ($info.IndexHigh -eq 0 -and $info.IndexLow -eq 0) { return "" }'
           Replace = ''
           Expect = "survives"
           Reason = "NTFS numbers every file, so no test here can make a file whose index is zero. The guard is for a file system that numbers nothing: there, two different files would both read 0:0 and be taken for one. What an empty identity then means is tested by itself (no-identity-is-the-same-as-no-identity)." }
        # --- the open ---
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
