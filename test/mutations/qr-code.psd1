# Mutations of the QR encoder. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\qr-code.psd1
# Each breaks one rule of the standard cli/QrCode.ps1 follows - a table, a code, a pattern, the
# placement, a mask, the penalty choice, the PNG - and test\test-qr-code.ps1 must fail for every one.
# Every find string occurs once in the target.
@{
    Target = "cli\QrCode.ps1"
    Suite  = "test\test-qr-code.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "level-bits-swapped"
           Find = '@{ L = 1; M = 0; Q = 3; H = 2 }'
           Replace = '@{ L = 0; M = 1; Q = 3; H = 2 }' }
        @{ Name = "format-not-masked"
           Find = '-bor $rem) -bxor 0x5412)'
           Replace = '-bor $rem))' }
        @{ Name = "version-bits-wrong-code"
           Find = '* 0x1F25)'
           Replace = '* 0x1F24)' }
        @{ Name = "field-polynomial-wrong"
           Find = '* 0x11D)'
           Replace = '* 0x11B)' }
        # An equivalent mutant in byte mode: mode (4) + count (8 or 16) + whole bytes always leaves 4 bits
        # to the next byte, so the padding to a byte writes the same four zeros the terminator would.
        @{ Name = "no-terminator"
           Find = '& $put 0 ([System.Math]::Min(4, $capBits - $bits.Count))'
           Replace = '$null = 0'
           Expect = "survives"
           Reason = "equivalent in byte mode: the padding to a whole byte writes the same four zero bits" }
        @{ Name = "pad-bytes-not-alternating"
           Find = '$pad = $pad -bxor (0xEC -bxor 0x11)'
           Replace = '$pad = $pad' }
        @{ Name = "count-always-eight-bits"
           Find = '& $put $Bytes.Length $(if ($Version -lt 10) { 8 } else { 16 })'
           Replace = '& $put $Bytes.Length 8' }
        @{ Name = "short-block-placeholder-kept"
           Find = 'if ($i -ne $shortLen - $eccLen -or $j -ge $numShort) {'
           Replace = 'if ($i -ne $shortLen - $eccLen -or $j -ge 0) {' }
        @{ Name = "alignment-on-a-finder-corner"
           Find = '($i -eq 0 -and $j -eq $pos.Count - 1) -or '
           Replace = '' }
        @{ Name = "timing-phase-swapped"
           Find = '& $set 6 $i ([int]($i % 2 -eq 0))'
           Replace = '& $set 6 $i ([int]($i % 2 -eq 1))' }
        @{ Name = "placement-never-upward"
           Find = '$upward = ((($right + 1) -band 2) -eq 0)'
           Replace = '$upward = $false' }
        @{ Name = "inline-mask-four-wrong"
           Find = '((($x - $x % 3) / 3 + ($y - $y % 2) / 2) % 2 -eq 0)'
           Replace = '((($x - $x % 3) / 3 + $y / 2) % 2 -eq 0)' }
        @{ Name = "penalty-ignored"
           Find = 'if ($s -lt $bestScore) {'
           Replace = 'if ($m -eq 0) {' }
        @{ Name = "version-not-smallest"
           Find = 'for ($v = $MinVersion; $v -le 40; $v++) {'
           Replace = 'for ($v = $MinVersion + 1; $v -le 40; $v++) {' }
        @{ Name = "non-ascii-taken"
           Find = 'if ($Text -cnotmatch ''\A[\x20-\x7E]*\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "png-inverted"
           Find = '$(if ($dark) { 0 } else { 255 })'
           Replace = '$(if ($dark) { 255 } else { 0 })' }
        @{ Name = "png-no-quiet-zone"
           Find = '$side = ($Code.size + 2 * $Border) * $Scale'
           Replace = '$side = $Code.size * $Scale' }
    )
}
