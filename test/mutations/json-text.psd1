# Mutations of core/JsonText.ps1, the one duplicate-key scanner. Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\json-text.psd1
# Each breaks one rule of the scanner; test\test-json-text.ps1 must fail for every one of them.
@{
    Target = "core\JsonText.ps1"
    Suite  = "test\test-json-text.ps1"
    Mutations = @(
        @{ Name = "keys-compared-by-case"
           Find = '$low = $key.ToLowerInvariant()'
           Replace = '$low = $key'
           Expect = "survives"
           Reason = "each frame's keys are a plain @{}, which already ignores case, so the lower-casing is a second statement of the rule; kept as it was moved from core/Ownership.ps1, and the suite's case check passes through the table either way" }
        @{ Name = "escaped-key-not-decoded"
           Find = 'if ($key.Contains(''\'')) {'
           Replace = 'if ($false) {' }
        @{ Name = "escaped-quote-ends-the-string"
           Find = '{ if ($Text[$i] -eq ''\'') { $i++ }; $i++ }'
           Replace = '{ $i++ }' }
        @{ Name = "keys-shared-with-enclosing-objects"
           Find = '$top.keys[$low] = $true'
           Replace = 'foreach ($fr in $stack) { $fr.keys[$low] = $true }' }
        @{ Name = "comma-does-not-start-a-key"
           Find = 'if ($top.kind -eq "object") { $top.expectKey = $true }'
           Replace = 'if ($false) { $top.expectKey = $true }' }
        @{ Name = "values-read-as-keys"
           Find = 'if ($top.kind -ne "object" -or -not $top.expectKey) { continue }'
           Replace = 'if ($top.kind -ne "object") { continue }' }
        @{ Name = "array-path-without-index"
           Find = 'else { $path = $parent.path + "[" + $parent.index + "]" }'
           Replace = 'else { $path = $parent.path }' }
        @{ Name = "array-index-not-counted"
           Find = 'else { $top.index++ }'
           Replace = 'else { }' }
        @{ Name = "closing-bracket-keeps-the-frame"
           Find = '{ if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) } }'
           Replace = '{ }' }
        @{ Name = "duplicate-not-reported"
           Find = '[void]$out.Add("key ''" + $key + "'' appears more than once in one object (" + $top.path + ")")'
           Replace = '$null = $key' }
        @{ Name = "unterminated-string-read-past-the-end"
           Find = 'if ($i -ge $n) { break }'
           Replace = '' }
        @{ Name = "bad-escape-throws"
           Find = 'catch { } }'
           Replace = 'catch { throw } }' }
        @{ Name = "stray-closing-bracket-unguarded"
           Find = '{ if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) } }'
           Replace = '{ $stack.RemoveAt($stack.Count - 1) }' }
        @{ Name = "stray-comma-unguarded"
           Find = 'elseif ($c -eq '','' -and $stack.Count -gt 0) {'
           Replace = 'elseif ($c -eq '','') {' }
        @{ Name = "bom-accepted"
           Find = '$Bytes[2] -eq 0xBF) { throw'
           Replace = '$Bytes[2] -eq 0x00) { throw' }
        @{ Name = "non-ascii-accepted"
           Find = 'if ($b -gt 0x7F) { throw'
           Replace = 'if ($b -gt 0xFF) { throw' }
        @{ Name = "control-bytes-allowed"
           Find = '        if ($b -lt 0x20 -and $b -ne 0x09 -and $b -ne 0x0A -and $b -ne 0x0D) {'
           Replace = '        if ($false) {' }
        @{ Name = "tab-refused"
           Find = '        if ($b -lt 0x20 -and $b -ne 0x09 -and $b -ne 0x0A -and $b -ne 0x0D) {'
           Replace = '        if ($b -lt 0x20 -and $b -ne 0x0A -and $b -ne 0x0D) {' }
        # The one parse (issue #274, T-0366). Caught in this shell and, through the suite's child processes, the other.
        @{ Name = "array-unrolled-on-return"
           Find = 'if ($parsed -is [array]) { return , $parsed }'
           Replace = '' }
        @{ Name = "no-text-reads-as-nothing"
           Find = 'if ($null -eq $Text) { throw (New-Object System.ArgumentNullException "Text", "there is no text to parse") }'
           Replace = '' }
        @{ Name = "reason-left-wrapped"
           Find = 'catch [System.Management.Automation.MethodInvocationException] { throw $_.Exception.InnerException }'
           Replace = 'catch [System.Management.Automation.MethodInvocationException] { throw }' }
        @{ Name = "text-after-the-value-allowed"
           Find = 'if (i != text.Length) { throw Bad(i, "text after the value"); }'
           Replace = '' }
        @{ Name = "raw-control-character-allowed"
           Find = 'if (c < '' '') { throw Bad(i, "a control character inside a string"); }'
           Replace = '' }
        @{ Name = "unknown-escape-allowed"
           Find = 'default: throw Bad(i, "an escape JSON does not have");'
           Replace = 'default: sb.Append(e); break;' }
        @{ Name = "repeated-key-keeps-the-first"
           Find = 'StringComparison.Ordinal)) { have.Value = value; }'
           Replace = 'StringComparison.Ordinal)) { }' }
        @{ Name = "keys-by-case-overwrite"
           Find = 'else { throw new InvalidOperationException("not JSON a PowerShell object can hold: keys ''" + have.Name + "'' and ''" + key + "'' differ only in case"); }'
           Replace = 'else { have.Value = value; }' }
        @{ Name = "nesting-limit-raised"
           Find = 'private const int MaxDepth = 100;'
           Replace = 'private const int MaxDepth = 200;' }
        @{ Name = "int64-read-as-decimal"
           Find = 'if (long.TryParse(s, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out l)) { return l; }'
           Replace = 'if (long.TryParse(s, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out l)) { return (decimal)l; }' }
        @{ Name = "fraction-read-as-double"
           Find = 'if (decimal.TryParse(s, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out m)) { return m; }'
           Replace = 'if (decimal.TryParse(s, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out m)) { return (double)m; }' }
        @{ Name = "number-too-large-is-infinity"
           Find = 'throw Bad(start, "a number too large to hold");'
           Replace = 'return double.PositiveInfinity;' }
    )
}
