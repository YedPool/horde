# Mutations of the link codec. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\link-protocol.psd1
# Each mutation breaks one rule of remote/Protocol.ps1 - the escaper, a cap, the BOM and CR handling,
# the one-spelling check, the version check, the reader - and test\test-link-protocol.ps1 must fail for
# every one. Every find string occurs exactly once, on one line.
# SECTIONS (tools\Mutate.ps1; issue #83): each mutant runs only the section of test\test-link-protocol.ps1
# that kills it: the cheapest whose checks failed for it in a whole-suite run of this spec on the
# always-on box (bd6cdb5, 2026-10-07). Each section passes run alone.
@{
    Target = "remote\Protocol.ps1"
    Suite  = "test\test-link-protocol.ps1"
    # Stop at the first failed check: a caught mutant needs nothing more.
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "del-left-raw"
           Find = 'elseif ($code -lt 0x20 -or $code -gt 0x7E)'
           Replace = 'elseif ($code -lt 0x20 -or $code -gt 0x7F)'
           Sections = @("escaping") }
        @{ Name = "non-ascii-left-raw"
           Find = 'elseif ($code -lt 0x20 -or $code -gt 0x7E)'
           Replace = 'elseif ($code -lt 0x20)'
           Sections = @("stream") }
        @{ Name = "fast-path-skips-quote-and-backslash"
           Find = '''\A[\x20\x21\x23-\x5B\x5D-\x7E]*\z'''
           Replace = '''\A[\x20-\x7E]*\z'''
           Sections = @("escaping") }
        @{ Name = "fast-path-takes-anything"
           Find = '''\A[\x20\x21\x23-\x5B\x5D-\x7E]*\z'''
           Replace = '''\A[\s\S]*\z'''
           Sections = @("stream") }
        @{ Name = "nul-crosses"
           Find = 'if ($code -eq 0) { throw'
           Replace = 'if ($false) { throw'
           Sections = @("escaping") }
        @{ Name = "lone-high-surrogate-crosses"
           Find = 'if ($i + 1 -ge $chars.Length -or -not [char]::IsLowSurrogate($chars[$i + 1])) { throw'
           Replace = 'if ($false) { throw'
           Sections = @("escaping") }
        @{ Name = "lone-low-surrogate-crosses"
           Find = 'if ($i -eq 0 -or -not [char]::IsHighSurrogate($chars[$i - 1])) { throw'
           Replace = 'if ($false) { throw'
           Sections = @("escaping") }
        @{ Name = "upper-case-hex"
           Find = '$code.ToString("x4")'
           Replace = '$code.ToString("X4")'
           Sections = @("stream") }
        @{ Name = "quote-not-escaped"
           Find = 'if ($c -ceq ''"'') { [void]$sb.Append(''\"'') }'
           Replace = 'if ($c -ceq ''"'') { [void]$sb.Append(''"'') }'
           Sections = @("escaping") }
        @{ Name = "measured-as-characters"
           Find = 'return ((ConvertTo-HordeWireString $Text).Length - 2)'
           Replace = 'return $Text.Length'
           Sections = @("escaping") }
        @{ Name = "depth-unguarded"
           Find = 'if ($d -gt $script:HordeWireMaxDepth)'
           Replace = 'if ($false)'
           Sections = @("escaping") }
        @{ Name = "ceiling-unchecked"
           Find = 'if ($cap -gt $Contract.limits["frameBytesCeiling"])'
           Replace = 'if ($false)'
           Sections = @("caps") }
        @{ Name = "sender-frame-cap-off-by-one"
           Find = 'if ($text.Length -gt $cap) {'
           Replace = 'if ($text.Length -gt $cap + 1) {'
           Sections = @("caps") }
        @{ Name = "receiver-frame-cap-off-by-one"
           Find = 'if ($length -gt $cap) {'
           Replace = 'if ($length -gt $cap + 1) {'
           Sections = @("caps") }
        # string-cap-off-by-one and list-cap-off-by-one moved with the caps into remote/Contract.ps1's link
        # walk: test/mutations/link-walk-caps.psd1.
        @{ Name = "args-caps-unchecked"
           Find = '[void]$walks.Add(@((Get-HordeLinkProp $Frame "args"), (Get-HordeLinkWalkTarget -Contract $Contract -Target "$($row.args)" -Path ''$.args''), ''$.args''))'
           Replace = ''
           Sections = @("caps") }
        @{ Name = "result-caps-unchecked"
           Find = '[void]$walks.Add(@((Get-HordeLinkProp $result "value"), (Get-HordeLinkWalkTarget -Contract $Contract -Target "$($row.result)" -Path ''$.result.value''), ''$.result.value''))'
           Replace = ''
           Sections = @("caps") }
        @{ Name = "sender-skips-caps"
           Find = 'if ($found.Count -gt 0) { return (New-HordeWireResult -Ok $false -Code "oversized" -Reason ("not sent: "'
           Replace = 'if ($false) { return (New-HordeWireResult -Ok $false -Code "oversized" -Reason ("not sent: "'
           Sections = @("caps") }
        @{ Name = "receiver-skips-caps"
           Find = 'if ($found.Count -gt 0) { return (New-HordeWireResult -Ok $false -Code "oversized" -Bom $bom -Reason ($found'
           Replace = 'if ($false) { return (New-HordeWireResult -Ok $false -Code "oversized" -Bom $bom -Reason ($found'
           Sections = @("caps") }
        @{ Name = "bom-accepted-anywhere"
           Find = 'if (-not $StreamStart) { return'
           Replace = 'if ($false) { return'
           Sections = @("receiver") }
        @{ Name = "bom-not-stripped"
           Find = '$start = 3'
           Replace = '$start = 0'
           Sections = @("receiver") }
        @{ Name = "utf16-not-named"
           Find = 'if ($end -ge 2 -and (($Bytes[0] -eq 0xFF'
           Replace = 'if ($false -and (($Bytes[0] -eq 0xFF'
           Sections = @("receiver") }
        @{ Name = "cr-not-stripped"
           Find = 'if ($end -gt $start -and $Bytes[$end - 1] -eq 13) { $end-- }'
           Replace = ''
           Sections = @("receiver") }
        @{ Name = "raw-bytes-not-refused"
           Find = 'if ($badAt.Success) {'
           Replace = 'if ($false) {'
           Sections = @("receiver") }
        @{ Name = "any-spelling-accepted"
           Find = 'if (-not [string]::Equals($again, $text, [System.StringComparison]::Ordinal)) {'
           Replace = 'if ($false) {'
           Sections = @("receiver") }
        @{ Name = "dictionary-keys-in-arrival-order"
           Find = '[Array]::Sort($keys, [System.StringComparer]::Ordinal)'
           Replace = ''
           Sections = @("escaping") }
        @{ Name = "object-keys-in-arrival-order"
           Find = '[Array]::Sort($keys, [StringComparer]::Ordinal)'
           Replace = ''
           Sections = @("receiver") }
        @{ Name = "fractions-written-with-their-scale"
           Find = 'if ($v -is [decimal] -or $v -is [double] -or $v -is [single]) {'
           Replace = 'if ($v -is [decimal] -or $v -is [double] -or $v -is [single]) { [void]$sb.Append($v.ToString($inv)); continue'
           Sections = @("receiver") }
        @{ Name = "version-not-read-first"
           Find = 'if (-not ($v -is [int] -and $v -eq 1))'
           Replace = 'if ($false)'
           Sections = @("receiver") }
        @{ Name = "version-as-text-accepted"
           Find = 'if (-not ($v -is [int] -and $v -eq 1))'
           Replace = 'if (-not ($v -eq 1))'
           Sections = @("receiver") }
        @{ Name = "closure-not-sticky"
           Find = 'if ($null -ne $Reader.closed) { return $Reader.closed }'
           Replace = ''
           Sections = @("stream") }
        @{ Name = "bom-allowed-on-every-line"
           Find = '$Reader.first = $false'
           Replace = ''
           Sections = @("stream") }
        @{ Name = "reader-unbounded"
           Find = 'if ($Reader.pending.Length -gt $limit) {'
           Replace = 'if ($false) {'
           Sections = @("stream") }
        @{ Name = "negotiation-ignores-our-list"
           Find = 'if ([long]$o -eq [long]$t -and $o -gt $best) { $best = $o }'
           Replace = 'if ($t -gt $best -and $t -le 2147483647) { $best = $t }'
           Sections = @("version") }
        @{ Name = "hello-version-count-unbounded"
           Find = 'if ($items.Count -gt $Contract.limits["versionItems"]) {'
           Replace = 'if ($false) {'
           Sections = @("version") }
        @{ Name = "hello-version-size-unbounded"
           Find = '-and [long]$x -gt [long]$Contract.limits["versionMax"]) {'
           Replace = '-and $false) {'
           Sections = @("version") }
        @{ Name = "bye-reason-not-cut"
           Find = '$said = Limit-HordeWireString -Text $Reason -Bytes $Contract.limits["reasonBytes"]'
           Replace = '$said = $Reason'
           Sections = @("version") }
        @{ Name = "cut-splits-surrogate-pairs"
           Find = 'if ([char]::IsHighSurrogate($Text[$n - 1])) { $n--; continue }'
           Replace = ''
           Sections = @("version") }
        @{ Name = "bye-names-every-offered-version"
           Find = '$named = @($theirs | Select-Object -First $Contract.limits["versionItems"])'
           Replace = '$named = @($theirs)'
           Sections = @("version") }
        @{ Name = "no-common-version-no-bye"
           Find = 'if ($p -gt 0) {'
           Replace = 'if ($p -ge 0) {'
           Sections = @("version") }
        # The writer is one loop over a work list (fix/link-writer-speed); these break its order.
        @{ Name = "writer-parts-reversed"
           Find = 'while ($order.Count -gt 0) { $todo.Push($order.Pop()) }'
           Replace = 'if ($order.Count -gt 0) { foreach ($o in @($order.ToArray()[($order.Count - 1)..0])) { $todo.Push($o) } }; while ($order.Count -gt 0) { $null = $order.Pop() }'
           Sections = @("receiver") }
        @{ Name = "writer-plain-key-unquoted"
           Find = 'if ([regex]::IsMatch($k, $plain)) { [void]$sb.Append(''"'').Append($k).Append(''":'') }'
           Replace = 'if ([regex]::IsMatch($k, $plain)) { [void]$sb.Append($k).Append('':'') }'
           Sections = @("receiver") }
        @{ Name = "writer-plain-string-unquoted"
           Find = 'if ([regex]::IsMatch($v, $plain)) { [void]$sb.Append(''"'').Append($v).Append(''"'') }'
           Replace = 'if ([regex]::IsMatch($v, $plain)) { [void]$sb.Append($v) }'
           Sections = @("receiver") }
        @{ Name = "writer-children-one-level-shallower"
           Find = '$order.Push(@(0, $item, ($d + 1)))'
           Replace = '$order.Push(@(0, $item, $d))'
           Sections = @("escaping") }
        # Review of PR #97, F7: the frame rules are applied where frames are sent and received.
        @{ Name = "frame-rules-unchecked-on-send"
           Find = 'if ($found.Count -eq 0) { $found = @(Test-HordeLinkFrameRules -Frame $Frame) }'
           Replace = ''
           Sections = @("frame-rules") }
        @{ Name = "frame-rules-unchecked-on-receive"
           Find = 'if ($found.Count -eq 0) { $found = @(Test-HordeLinkFrameRules -Frame $frame) }'
           Replace = ''
           Sections = @("frame-rules") }
    )
}
