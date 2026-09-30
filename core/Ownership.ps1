# core/ownership - who will own each field of a session, and how it is read until then.
#
# Step 0.6. The systems Horde replaces keep the same fact in several places - a session's pane is
# stored three times in wezfleet and derivable from a fourth source - and different callers trust
# different copies (planning/ledger/core-ownership.md, D1 to D24). Horde does not repair that. It
# writes down, as data in core\ownership.json, for every field:
#   - its ONE future owner, so there is never a second writer to disagree with, and
#   - until that field is switched over, the ORDER the old stores are read in when they disagree,
#     so every reader in Horde resolves a disagreement the same way.
#
# Test-HordeOwnership is the gate: a field with no owner, two owners, no read rule, or a store that
# does not exist is a finding.

Set-StrictMode -Off

$script:HordeOwnershipFieldKeys = @("name", "owner", "read", "derived", "provisional")
$script:HordeOwnershipDroppedKeys = @("name", "reason")
$script:HordeOwnershipReadKeys = @("store", "field", "when")

function Get-HordeOwnership {
    param([string]$Path = (Join-Path $PSScriptRoot "ownership.json"))
    return ((Get-Content -LiteralPath $Path -Raw) | ConvertFrom-Json)
}

function Get-HordeOwnershipField {
    # One field's entry, or $null.
    param($Doc, [Parameter(Mandatory = $true)][string]$Name)
    return (@($Doc.fields | Where-Object { $_.name -ceq $Name }) | Select-Object -First 1)
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

function Test-HordeOwnership {
    # Every way the ownership table can be wrong, as a list of findings. Empty means it holds.
    # Pass -Text, the file's raw JSON, wherever you have it: only the text shows a repeated key.
    [CmdletBinding()]
    param($Doc, [string]$Text = "")
    $findings = New-Object System.Collections.ArrayList
    if ($Text -ne "") {
        foreach ($d in @(Find-HordeJsonDuplicateKey -Text $Text)) { [void]$findings.Add($d) }
        if ($null -eq $Doc) {
            try { $Doc = $Text | ConvertFrom-Json } catch {
                [void]$findings.Add("the table is not JSON that PowerShell can read: " + $_.Exception.Message)
                return @($findings)
            }
        }
    }
    if ($null -eq $Doc -or $null -eq $Doc.fields -or $null -eq $Doc.stores -or $null -eq $Doc.owners) {
        [void]$findings.Add("the document needs owners, stores and fields")
        return @($findings)
    }
    $owners = @($Doc.owners.PSObject.Properties | ForEach-Object { $_.Name })
    $stores = @($Doc.stores.PSObject.Properties | ForEach-Object { $_.Name })
    $seen = @{}
    $usedStores = @{}
    $fieldNames = New-Object System.Collections.ArrayList
    foreach ($f in @($Doc.fields)) {
        $n = "$($f.name)"
        if ($n.Trim() -eq "") { [void]$findings.Add("a field has no name"); continue }
        if ($seen.ContainsKey($n)) { [void]$findings.Add("field '" + $n + "' is listed twice") }
        $seen[$n] = $true
        [void]$fieldNames.Add($n)
        foreach ($k in @($f.PSObject.Properties | ForEach-Object { $_.Name })) {
            if ($script:HordeOwnershipFieldKeys -notcontains $k) { [void]$findings.Add("field '" + $n + "' has an unknown key '" + $k + "'") }
        }
        # EXACTLY ONE OWNER: a single string naming a listed owner. An array is two owners.
        if ($f.owner -is [array]) { [void]$findings.Add("field '" + $n + "' names more than one owner") }
        elseif ("$($f.owner)".Trim() -eq "") { [void]$findings.Add("field '" + $n + "' has no owner") }
        elseif ($owners -notcontains "$($f.owner)") { [void]$findings.Add("field '" + $n + "' names owner '" + $f.owner + "', which is not one of the listed owners") }
        # A READ RULE: at least one store to read from, each one real, each naming a field.
        $read = @($f.read | Where-Object { $null -ne $_ })
        if ($read.Count -eq 0) { [void]$findings.Add("field '" + $n + "' has no read rule") }
        # Inside a read entry only store, field and when mean anything, so any other key is a
        # misspelling of one of them - a "wehn" would silently drop a guard. A when that is present
        # must say something, and one rule reading the same store and field twice is two orders
        # for one source (review finding 3, 2026-09-29).
        $readPairs = New-Object System.Collections.ArrayList
        foreach ($r in $read) {
            $s = "$($r.store)"
            if ($stores -notcontains $s) { [void]$findings.Add("field '" + $n + "' reads from store '" + $s + "', which is not in the store list") }
            else { $usedStores[$s] = $true }
            if ("$($r.field)".Trim() -eq "") { [void]$findings.Add("field '" + $n + "' reads from store '" + $s + "' without naming what it reads") }
            foreach ($k in @($r.PSObject.Properties | ForEach-Object { $_.Name })) {
                if ($script:HordeOwnershipReadKeys -cnotcontains $k) { [void]$findings.Add("field '" + $n + "' reads from store '" + $s + "' with an unknown key '" + $k + "'") }
            }
            $w = $r.PSObject.Properties["when"]
            if ($null -ne $w -and ($w.Value -isnot [string] -or "$($w.Value)".Trim() -eq "")) {
                [void]$findings.Add("field '" + $n + "' reads from store '" + $s + "' under an empty condition")
            }
            $pair = $s + "|" + "$($r.field)"
            if ($readPairs -ccontains $pair) { [void]$findings.Add("field '" + $n + "' reads '" + $r.field + "' from store '" + $s + "' twice") }
            [void]$readPairs.Add($pair)
        }
        foreach ($k in @("derived", "provisional")) {
            $p = $f.PSObject.Properties[$k]
            if ($null -ne $p -and "$($p.Value)".Trim() -eq "") { [void]$findings.Add("field '" + $n + "' says it is " + $k + " but not how or why") }
        }
    }
    foreach ($s in $stores) {
        if (-not $usedStores.ContainsKey($s)) { [void]$findings.Add("store '" + $s + "' is listed but no field reads it") }
    }

    # EVERY FIELD ACCOUNTED FOR. Without a list of what must be there, an empty table passed and a
    # deleted field was invisible (review finding 2, 2026-09-29): every check above runs per field,
    # so a field that is not there is never checked. The list lives in the JSON until
    # schema/session-record.v1 exists (migration plan step 1.2), and then that schema is the list.
    # A field is accounted for by being in `fields` (kept, with an owner and a read rule) or in
    # `dropped` (not carried into Horde, with the reason) - never both, never neither.
    $droppedNames = New-Object System.Collections.ArrayList
    foreach ($x in @($Doc.dropped | Where-Object { $null -ne $_ })) {
        $dn = "$($x.name)"
        if ($dn.Trim() -eq "") { [void]$findings.Add("a dropped entry has no name"); continue }
        foreach ($k in @($x.PSObject.Properties | ForEach-Object { $_.Name })) {
            if ($script:HordeOwnershipDroppedKeys -cnotcontains $k) { [void]$findings.Add("dropped field '" + $dn + "' has an unknown key '" + $k + "'") }
        }
        if ($droppedNames -ccontains $dn) { [void]$findings.Add("field '" + $dn + "' is dropped twice") }
        [void]$droppedNames.Add($dn)
        if ($x.reason -isnot [string] -or "$($x.reason)".Trim() -eq "") { [void]$findings.Add("field '" + $dn + "' is dropped without a reason") }
        if ($fieldNames -ccontains $dn) { [void]$findings.Add("field '" + $dn + "' is both kept and dropped") }
    }
    if ($null -eq $Doc.PSObject.Properties["required"]) {
        [void]$findings.Add("the table needs a required list naming every field of the session record")
        return @($findings)
    }
    $required = @($Doc.required | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
    if ($required.Count -eq 0) { [void]$findings.Add("the required list is empty") }
    $requiredSeen = New-Object System.Collections.ArrayList
    foreach ($r in $required) {
        if ($requiredSeen -ccontains $r) { [void]$findings.Add("the required list names '" + $r + "' twice") }
        [void]$requiredSeen.Add($r)
        if ($fieldNames -cnotcontains $r -and $droppedNames -cnotcontains $r) {
            [void]$findings.Add("required field '" + $r + "' is missing: it is neither in fields nor dropped")
        }
    }
    foreach ($x in @($fieldNames) + @($droppedNames)) {
        if ($required -cnotcontains $x) { [void]$findings.Add("field '" + $x + "' is not in the required list") }
    }
    return @($findings)
}
