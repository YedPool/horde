# Mutations of the link codec. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\link-protocol.psd1
# Each mutation breaks one rule of remote/Protocol.ps1 - the escaper, a cap, the BOM and CR handling,
# the one-spelling check, the version check, the reader - and test\test-link-protocol.ps1 must fail for
# every one. Every find string occurs exactly once, on one line.
@{
    Target = "remote\Protocol.ps1"
    Suite  = "test\test-link-protocol.ps1"
    Mutations = @(
        @{ Name = "del-left-raw"
           Find = 'elseif ($code -lt 0x20 -or $code -gt 0x7E)'
           Replace = 'elseif ($code -lt 0x20 -or $code -gt 0x7F)' }
        @{ Name = "non-ascii-left-raw"
           Find = 'elseif ($code -lt 0x20 -or $code -gt 0x7E)'
           Replace = 'elseif ($code -lt 0x20)' }
        @{ Name = "fast-path-skips-quote-and-backslash"
           Find = '''\A[\x20\x21\x23-\x5B\x5D-\x7E]*\z'''
           Replace = '''\A[\x20-\x7E]*\z''' }
        @{ Name = "fast-path-takes-anything"
           Find = '''\A[\x20\x21\x23-\x5B\x5D-\x7E]*\z'''
           Replace = '''\A[\s\S]*\z''' }
        @{ Name = "nul-crosses"
           Find = 'if ($code -eq 0) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "lone-high-surrogate-crosses"
           Find = 'if ($i + 1 -ge $chars.Length -or -not [char]::IsLowSurrogate($chars[$i + 1])) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "lone-low-surrogate-crosses"
           Find = 'if ($i -eq 0 -or -not [char]::IsHighSurrogate($chars[$i - 1])) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "upper-case-hex"
           Find = '$code.ToString("x4")'
           Replace = '$code.ToString("X4")' }
        @{ Name = "quote-not-escaped"
           Find = 'if ($c -ceq ''"'') { [void]$sb.Append(''\"'') }'
           Replace = 'if ($c -ceq ''"'') { [void]$sb.Append(''"'') }' }
        @{ Name = "measured-as-characters"
           Find = 'return ((ConvertTo-HordeWireString $Text).Length - 2)'
           Replace = 'return $Text.Length' }
        @{ Name = "depth-unguarded"
           Find = 'if ($Depth -gt $script:HordeWireMaxDepth)'
           Replace = 'if ($false)' }
        @{ Name = "ceiling-unchecked"
           Find = 'if ($cap -gt $Contract.limits["frameBytesCeiling"])'
           Replace = 'if ($false)' }
        @{ Name = "sender-frame-cap-off-by-one"
           Find = 'if ($text.Length -gt $cap) {'
           Replace = 'if ($text.Length -gt $cap + 1) {' }
        @{ Name = "receiver-frame-cap-off-by-one"
           Find = 'if ($length -gt $cap) {'
           Replace = 'if ($length -gt $cap + 1) {' }
        @{ Name = "string-cap-off-by-one"
           Find = 'if ($size -gt $limit) {'
           Replace = 'if ($size -gt $limit + 1) {' }
        @{ Name = "list-cap-off-by-one"
           Find = 'if ($x.value.Count -gt $limit) {'
           Replace = 'if ($x.value.Count -gt $limit + 1) {' }
        @{ Name = "args-caps-unchecked"
           Find = '[void]$walks.Add(@((Get-HordeLinkProp $Frame "args"), $t.node, $t.root, ''$.args''))'
           Replace = '' }
        @{ Name = "result-caps-unchecked"
           Find = '[void]$walks.Add(@((Get-HordeLinkProp $result "value"), $t.node, $t.root, ''$.result.value''))'
           Replace = '' }
        @{ Name = "sender-skips-caps"
           Find = 'if ($found.Count -gt 0) { return (New-HordeWireResult -Ok $false -Code "oversized" -Reason ("not sent: "'
           Replace = 'if ($false) { return (New-HordeWireResult -Ok $false -Code "oversized" -Reason ("not sent: "' }
        @{ Name = "receiver-skips-caps"
           Find = 'if ($found.Count -gt 0) { return (New-HordeWireResult -Ok $false -Code "oversized" -Bom $bom -Reason ($found'
           Replace = 'if ($false) { return (New-HordeWireResult -Ok $false -Code "oversized" -Bom $bom -Reason ($found' }
        @{ Name = "bom-accepted-anywhere"
           Find = 'if (-not $StreamStart) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "bom-not-stripped"
           Find = '$start = 3'
           Replace = '$start = 0' }
        @{ Name = "utf16-not-named"
           Find = 'if ($end -ge 2 -and (($Bytes[0] -eq 0xFF'
           Replace = 'if ($false -and (($Bytes[0] -eq 0xFF' }
        @{ Name = "cr-not-stripped"
           Find = 'if ($end -gt $start -and $Bytes[$end - 1] -eq 13) { $end-- }'
           Replace = '' }
        @{ Name = "raw-bytes-not-refused"
           Find = 'if ($badAt.Success) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-spelling-accepted"
           Find = 'if (-not [string]::Equals($again, $text, [System.StringComparison]::Ordinal)) {'
           Replace = 'if ($false) {' }
        @{ Name = "dictionary-keys-in-arrival-order"
           Find = '[Array]::Sort($keys, [System.StringComparer]::Ordinal)'
           Replace = '' }
        @{ Name = "object-keys-in-arrival-order"
           Find = '[Array]::Sort($keys, [StringComparer]::Ordinal)'
           Replace = '' }
        @{ Name = "fractions-written-with-their-scale"
           Find = 'if ($Value -is [decimal] -or $Value -is [double] -or $Value -is [single]) {'
           Replace = 'if ($Value -is [decimal] -or $Value -is [double] -or $Value -is [single]) { return $Value.ToString($inv)' }
        @{ Name = "version-not-read-first"
           Find = 'if (-not ($v -is [int] -and $v -eq 1))'
           Replace = 'if ($false)' }
        @{ Name = "version-as-text-accepted"
           Find = 'if (-not ($v -is [int] -and $v -eq 1))'
           Replace = 'if (-not ($v -eq 1))' }
        @{ Name = "closure-not-sticky"
           Find = 'if ($null -ne $Reader.closed) { return $Reader.closed }'
           Replace = '' }
        @{ Name = "bom-allowed-on-every-line"
           Find = '$Reader.first = $false'
           Replace = '' }
        @{ Name = "reader-unbounded"
           Find = 'if ($Reader.pending.Length -gt $limit) {'
           Replace = 'if ($false) {' }
        @{ Name = "negotiation-ignores-our-list"
           Find = 'if ([long]$o -eq [long]$t -and $o -gt $best) { $best = $o }'
           Replace = 'if ($t -gt $best -and $t -le 2147483647) { $best = $t }' }
        @{ Name = "hello-version-count-unbounded"
           Find = 'if ($items.Count -gt $Contract.limits["versionItems"]) {'
           Replace = 'if ($false) {' }
        @{ Name = "hello-version-size-unbounded"
           Find = '-and [long]$x -gt [long]$Contract.limits["versionMax"]) {'
           Replace = '-and $false) {' }
        @{ Name = "bye-reason-not-cut"
           Find = '$said = Limit-HordeWireString -Text $Reason -Bytes $Contract.limits["reasonBytes"]'
           Replace = '$said = $Reason' }
        @{ Name = "cut-splits-surrogate-pairs"
           Find = 'if ([char]::IsHighSurrogate($Text[$n - 1])) { $n--; continue }'
           Replace = '' }
        @{ Name = "bye-names-every-offered-version"
           Find = '$named = @($theirs | Select-Object -First $Contract.limits["versionItems"])'
           Replace = '$named = @($theirs)' }
        @{ Name = "no-common-version-no-bye"
           Find = 'if ($p -gt 0) {'
           Replace = 'if ($p -ge 0) {' }
    )
}
