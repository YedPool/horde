# core/JsonText - what Horde checks in JSON text before it parses it.
#
# ONE SCANNER, SHARED. ConvertFrom-Json in Windows PowerShell 5.1 keeps one of two repeated keys and
# reports nothing, so text can show its reader one value and give Horde another. core/Ownership.ps1
# (the ownership table) and core/PermissionLevels.ps1 (the permission-level vocabulary) both refuse
# such text through Find-HordeJsonDuplicateKey, which lives here alone. Until 2026-10-02 each file had
# a scanner of its own under that one name, with different answers - a list of findings ignoring case,
# against the first repeat compared exactly - and PowerShell gives a name to whichever definition
# loads last, so a caller loading both would have run one while its author tested the other
# (test/test-function-names.ps1 now fails on any name defined twice). Moved here unchanged from
# core/Ownership.ps1, with one change: an unterminated string now ends the scan instead of throwing.
# test/test-json-text.ps1 holds it.
#
# No Set-StrictMode here: this file is dot-sourced, so a file-scope Set-StrictMode would set the
# caller's mode (see core/Tristate.ps1). The function runs under -Version Latest.

function Find-HordeJsonDuplicateKey {
    # Every key that appears more than once in ONE object of a JSON text, as findings.
    #
    # WHY THE TEXT AND NOT THE PARSED TABLE: ConvertFrom-Json keeps one of two repeated keys and
    # reports nothing, so {"owner":"agent","owner":"engine"} parses to a field with one owner and
    # passes every check on the parsed object. A review found exactly that on 2026-09-29.
    #
    # PER OBJECT, NOT PER FILE: "store" legitimately appears in every read entry. Keys are
    # compared ignoring case, because PowerShell reads properties ignoring case and Windows
    # PowerShell 5.1's ConvertFrom-Json throws on two keys that differ only in case.
    # A key written with escapes is decoded before it is compared, so an escaped spelling of a
    # key is still the same key.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $out = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.ArrayList   # one frame per open object or array
    $i = 0; $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($c -eq '"') {
            $start = $i; $i++
            while ($i -lt $n -and $Text[$i] -ne '"') { if ($Text[$i] -eq '\') { $i++ }; $i++ }
            # AN UNTERMINATED STRING ENDS THE SCAN: nothing after it can be a key, and reading its
            # text ran Substring past the end ("{\"a\\" threw, review of this fix). ConvertFrom-Json
            # refuses the text with its own message.
            if ($i -ge $n) { break }
            $i++
            if ($stack.Count -eq 0) { continue }
            $top = $stack[$stack.Count - 1]
            if ($top.kind -ne "object" -or -not $top.expectKey) { continue }
            $key = $Text.Substring($start + 1, [Math]::Max(0, $i - $start - 2))
            if ($key.Contains('\')) { try { $key = [string]('"' + $key + '"' | ConvertFrom-Json) } catch { } }
            $low = $key.ToLowerInvariant()
            if ($top.keys.ContainsKey($low)) {
                [void]$out.Add("key '" + $key + "' appears more than once in one object (" + $top.path + ")")
            }
            $top.keys[$low] = $true
            $top.lastKey = $key
            $top.expectKey = $false
            continue
        }
        if ($c -eq '{' -or $c -eq '[') {
            $path = "top level"
            if ($stack.Count -gt 0) {
                $parent = $stack[$stack.Count - 1]
                if ($parent.kind -eq "object") { $path = $parent.path + "." + $parent.lastKey }
                else { $path = $parent.path + "[" + $parent.index + "]" }
                if ($path.StartsWith("top level.")) { $path = $path.Substring(10) }
            }
            $kind = if ($c -eq '{') { "object" } else { "array" }
            [void]$stack.Add(@{ kind = $kind; keys = @{}; expectKey = ($c -eq '{'); lastKey = ""; index = 0; path = $path })
        }
        elseif ($c -eq '}' -or $c -eq ']') { if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) } }
        elseif ($c -eq ',' -and $stack.Count -gt 0) {
            $top = $stack[$stack.Count - 1]
            if ($top.kind -eq "object") { $top.expectKey = $true } else { $top.index++ }
        }
        $i++
    }
    return @($out)
}
