# core/JsonText - what Horde checks in JSON text before it parses it, and the parse itself.
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

# THE BYTE CHECK lives here too (review of #109): every reader of a Horde data file runs it before it
# decodes, and every one of them already loads this file, so no reader can call it without loading it
# (core/NodePolicy.ps1 once called it from a file it never loaded; tools/CoreLoad.ps1 now guards that).

# THE ONE PARSE, the same under both PowerShells (issue #274). PowerShell 7's ConvertFrom-Json reads a
# date-shaped string as a [datetime]; Windows PowerShell 5.1 never does. Measured 2026-10-14 on 7.6.6:
# '{"at":"2026-10-14T12:00:00.0000000Z"}' gave $o.at as System.DateTime under pwsh and System.String
# under 5.1 ("2026-10-14" alone stayed a string under both). So every Horde record read under 7 carried
# its timestamps as dates, and `horde decisions add` refused its own new record before writing it:
# "it is not a decision-event.v1 record: $.at should be string". ConvertFrom-HordeJson is the parse a
# Horde reader uses instead of ConvertFrom-Json, so a string in the text is a string in the result.
#   - 7.5 and later: -DateKind String, which leaves every string exactly as written.
#   - 7.0 to 7.4 have no -DateKind: the parsed value is walked and each [datetime] is written back as
#     round-trip ("o") text. Exact for every timestamp Horde writes itself (UTC, "o"); a date-shaped
#     string written another way ("...T12:00:00Z", or with an offset) comes back as the same instant in
#     "o" form, not as typed. OWED: an exact reader for 7.0 to 7.4.
#   - 5.1 never converts, so the text is parsed as it is.
# The output is ConvertFrom-Json's own, passed on unchanged (a function body that is the pipeline
# re-wraps nothing), so a caller sees the same arrays and objects as from the cmdlet itself.
$script:HordeJsonDateKind = (Get-Command ConvertFrom-Json).Parameters.ContainsKey("DateKind")
$script:HordeJsonMakesDates = ("" + $PSVersionTable.PSEdition) -ceq "Core"

function ConvertFrom-HordeJson {
    # -Text parsed as JSON, with every string left a string. Throws as ConvertFrom-Json throws on text
    # that is not JSON.
    param($Text)
    if ($script:HordeJsonDateKind) { $Text | ConvertFrom-Json -DateKind String -ErrorAction Stop }
    elseif ($script:HordeJsonMakesDates) { $Text | ConvertFrom-Json -ErrorAction Stop | ForEach-Object { ConvertTo-HordeJsonDateText -Value $_ } }
    else { $Text | ConvertFrom-Json -ErrorAction Stop }
}

function ConvertTo-HordeJsonDateText {
    # -Value with every [datetime] or [datetimeoffset] in it, at any depth, turned back into round-trip
    # ("o") text: in place for objects and lists, and returned. For PowerShell 7.0 to 7.4 (above).
    param($Value)
    if ($Value -is [datetime] -or $Value -is [datetimeoffset]) { return $Value.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in @($Value.PSObject.Properties)) { $p.Value = ConvertTo-HordeJsonDateText -Value $p.Value }
        return $Value
    }
    if ($Value -is [System.Collections.IList]) {
        for ($i = 0; $i -lt $Value.Count; $i++) { $Value[$i] = ConvertTo-HordeJsonDateText -Value $Value[$i] }
        # The comma keeps a list one value on the way out, as ConvertFrom-Json gave it.
        return , $Value
    }
    return $Value
}

function Assert-HordeAsciiBytes {
    # Throw unless the bytes are plain ASCII with no byte-order mark and no control byte but tab, CR and
    # LF. Checked before decoding: a decoder turns a stray byte into a character, or a replacement mark,
    # and either reads as text. A NUL is how a file saved as UTF-16 without a mark looks byte by byte, so
    # it is named as that rather than left to fail later as not JSON (review of #109).
    param([byte[]]$Bytes, [string]$What)
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { throw ($What + " starts with a UTF-8 byte-order mark; save it as plain ASCII (CONTRIBUTING 13)") }
    foreach ($b in $Bytes) {
        if ($b -gt 0x7F) { throw ($What + " holds a byte that is not ASCII (CONTRIBUTING 13)") }
        if ($b -lt 0x20 -and $b -ne 0x09 -and $b -ne 0x0A -and $b -ne 0x0D) { throw ($What + " holds the control byte 0x" + ([int]$b).ToString("X2") + $(if ($b -eq 0) { ", as a file saved as UTF-16 does" } else { "" }) + "; save it as plain ASCII (CONTRIBUTING 13)") }
    }
}

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
