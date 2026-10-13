# Mutations of files/Text.ps1: is a file that is named as text really text. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-text.psd1
# Each lets through bytes that are not text, or refuses text; test\test-files-store.ps1 must fail
# for every one.
@{
    Target = "files\Text.ps1"
    Suite  = "test\test-files-store.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "utf16-not-named-by-its-mark"
           Find = 'if ($Bytes.Length -ge 2 -and (($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) -or ($Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF))) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "big-endian-mark-not-known"
           Find = '(($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) -or ($Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF))'
           Replace = '($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE)' }
        @{ Name = "little-endian-mark-not-known"
           Find = '(($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) -or ($Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF))'
           Replace = '($Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF)' }
        @{ Name = "nul-allowed"
           Find = 'if ($nul -ge 0) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "nul-looked-for-in-the-first-byte-only"
           Find = '$nul = [Array]::IndexOf($Bytes, [byte]0)'
           Replace = '$nul = [Array]::IndexOf($Bytes, [byte]0, 0, [System.Math]::Min(1, $Bytes.Length))' }
        @{ Name = "nul-at-the-first-byte-allowed"
           Find = 'if ($nul -ge 0) { return'
           Replace = 'if ($nul -gt 0) { return' }
        @{ Name = "nul-said-to-be-one-byte-later"
           Find = '"it holds a NUL byte (the first is byte " + $nul + ")'
           Replace = '"it holds a NUL byte (the first is byte " + ($nul + 1) + ")' }
        @{ Name = "invalid-utf8-replaced-instead-of-refused"
           Find = '$strict = New-Object System.Text.UTF8Encoding($false, $true)'
           Replace = '$strict = New-Object System.Text.UTF8Encoding($false, $false)' }
        @{ Name = "invalid-utf8-noticed-and-let-through"
           Find = 'return ("it is not UTF-8: it holds a byte sequence'
           Replace = '$null = ("it is not UTF-8: it holds a byte sequence' }
        @{ Name = "json-held-to-nothing-more-than-text"
           Find = 'if ($Type -ceq "application/json") {'
           Replace = 'if ($false) {' }
        @{ Name = "every-text-held-to-json"
           Find = 'if ($Type -ceq "application/json") {'
           Replace = 'if ($true) {' }
        @{ Name = "json-problem-found-and-ignored"
           Find = 'if ($problem -ne "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "mark-read-as-part-of-the-json"
           Find = 'if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { $after = 3 }'
           Replace = '' }
        @{ Name = "any-three-first-bytes-stepped-over"
           Find = 'if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { $after = 3 }'
           Replace = 'if ($Bytes.Length -ge 3) { $after = 3 }' }
        @{ Name = "json-read-from-its-first-byte-whatever-is-asked"
           Find = 'return [HordeFilesJsonV1]::Problem($Bytes, $Offset)'
           Replace = 'return [HordeFilesJsonV1]::Problem($Bytes, 0)' }
    )
}
