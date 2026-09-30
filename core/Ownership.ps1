# core/ownership - who will own each field of a session, and how it is read until then.
#
# Step 0.6. The systems Horde replaces keep the same fact in several places - a session's pane is
# stored three times in wezfleet and derivable from a fourth source - and different callers trust
# different copies (planning/ledger/core-ownership.md, entries L-001 onward). Horde does not repair
# that. It writes down, as data in core\ownership.json, for every field:
#   - its ONE future owner, so there is never a second writer to disagree with, and
#   - until that field is switched over, the ORDER the old stores are read in when they disagree,
#     so every reader in Horde resolves a disagreement the same way.
# A field of the record that Horde does not carry is listed under `dropped`, with the reason.
#
# Test-HordeOwnership is the gate. Each of these is a finding, and this list is every one it makes:
#   the text   - a key repeated inside one object, compared ignoring case; text that is not JSON
#                PowerShell can read.
#   top level  - a key other than about, owners, stores, storeIdGaps, surveyedVersions, required,
#                fields and dropped; no owners, stores or fields.
#   surveyed   - a surveyed version for a store not in the store list; one that is not a version.
#   owners     - a description that is empty or not text.
#   stores     - an unknown key; system, what or path missing, empty or not text; a guard that is
#                empty or not text; an id that is also listed in storeIdGaps; a store no field reads.
#   fields     - no name; a name listed twice; two names that differ only in case; an unknown key;
#                no owner, an owner given as a list, more than one owner, or an owner not listed;
#                a derived or provisional that is empty or not text.
#   reads      - no read rule; a null read entry; a store not in the store list; a field read that
#                is empty or not text; an unknown key; a when that is empty or not text; one store
#                and field read twice in one rule, field names compared ignoring case.
#   dropped    - no name; an unknown key; dropped twice; no reason, or a reason that is not text;
#                both kept and dropped; a store not in the store list; a store without a key, or a
#                key without a store; a key that is not text; a store key some field also reads; a
#                provisional that is empty or not text.
#   required   - no required list; an empty one; a name listed twice; a required field that is
#                neither kept nor dropped; a kept or dropped field that is not required.
# Names - owners, stores, fields - are otherwise matched exactly, case included.

Set-StrictMode -Off

$script:HordeOwnershipFieldKeys = @("name", "owner", "read", "derived", "provisional")
# A dropped entry may name the store key it drops (store and field), when that key is not the
# record field's own name - the control file's agent is not Horde's agent - and say it is provisional.
$script:HordeOwnershipDroppedKeys = @("name", "reason", "store", "field", "provisional")
$script:HordeOwnershipReadKeys = @("store", "field", "when")
$script:HordeOwnershipStoreKeys = @("system", "what", "path", "guard")
$script:HordeOwnershipTopKeys = @("about", "owners", "stores", "storeIdGaps", "surveyedVersions", "required", "fields", "dropped")

function Get-HordeOwnership {
    param([string]$Path = (Join-Path $PSScriptRoot "ownership.json"))
    return ((Get-Content -LiteralPath $Path -Raw) | ConvertFrom-Json)
}

function Get-HordeOwnershipStoreKeys {
    # Every key of one store the table has decided about: read by some field, or dropped by an entry
    # naming the store. A key of that store in neither list is one nobody has looked at. The test
    # suites take the list from here, so the table's own gate and the live check count alike.
    #
    # Every property is read through PSObject.Properties: a caller under Set-StrictMode -Version
    # Latest (test/test-identity.ps1) runs this in its own strict mode, where reading a dropped
    # entry's missing store throws (seen: "The property 'store' cannot be found on this object").
    param($Doc, [Parameter(Mandatory = $true)][string]$Store)
    $keys = New-Object System.Collections.ArrayList
    foreach ($f in @($Doc.fields)) {
        $rp = $f.PSObject.Properties["read"]
        if ($null -eq $rp) { continue }
        foreach ($r in @($rp.Value)) {
            if ($null -eq $r) { continue }
            $sp = $r.PSObject.Properties["store"]; $fp = $r.PSObject.Properties["field"]
            if ($null -ne $sp -and $null -ne $fp -and "$($sp.Value)" -ceq $Store) { [void]$keys.Add("$($fp.Value)") }
        }
    }
    foreach ($x in @($Doc.dropped | Where-Object { $null -ne $_ })) {
        $sp = $x.PSObject.Properties["store"]; $fp = $x.PSObject.Properties["field"]
        if ($null -ne $sp -and $null -ne $fp -and "$($sp.Value)" -ceq $Store) { [void]$keys.Add("$($fp.Value)") }
    }
    return @($keys | Sort-Object -Unique -CaseSensitive)
}

function Get-HordeOwnershipSurveyedVersion {
    # The newest agent version whose keys the table was checked against, for one store, as a
    # [version]; $null when the table records none or it is not a version.
    param($Doc, [Parameter(Mandatory = $true)][string]$Store)
    $sv = $Doc.PSObject.Properties["surveyedVersions"]
    if ($null -eq $sv -or $null -eq $sv.Value) { return $null }
    $p = $sv.Value.PSObject.Properties[$Store]
    if ($null -eq $p) { return $null }
    $v = $null
    if ("$($p.Value)" -match '^[0-9]+(\.[0-9]+){1,3}$' -and [version]::TryParse("$($p.Value)", [ref]$v)) { return $v }
    return $null
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
    # THE TOP LEVEL HAS A FIXED SET OF KEYS, like every other object in the table: a misspelled
    # "requird" or "droped" would be ignored, and everything it held with it (second review,
    # finding 6).
    if ($null -ne $Doc) {
        foreach ($k in @($Doc.PSObject.Properties | ForEach-Object { $_.Name })) {
            if ($script:HordeOwnershipTopKeys -cnotcontains $k) { [void]$findings.Add("the table has an unknown top-level key '" + $k + "'") }
        }
    }
    if ($null -eq $Doc -or $null -eq $Doc.fields -or $null -eq $Doc.stores -or $null -eq $Doc.owners) {
        [void]$findings.Add("the document needs owners, stores and fields")
        return @($findings)
    }
    $owners = @($Doc.owners.PSObject.Properties | ForEach-Object { $_.Name })
    # An owner is described in text; an empty description listed an owner nothing explains
    # (second review, finding 5).
    foreach ($op in @($Doc.owners.PSObject.Properties)) {
        if ($op.Value -isnot [string] -or "$($op.Value)".Trim() -eq "") { [void]$findings.Add("owner '" + $op.Name + "' has no description") }
    }
    $stores = @($Doc.stores.PSObject.Properties | ForEach-Object { $_.Name })
    # AN ID IS A STORE OR A GAP IN THE NUMBERING, NEVER BOTH. A gap that names a real store says
    # the store does not exist while fields read it.
    if ($null -ne $Doc.storeIdGaps) {
        foreach ($gapId in @($Doc.storeIdGaps.PSObject.Properties | ForEach-Object { $_.Name })) {
            if ($stores -contains $gapId) { [void]$findings.Add("store id '" + $gapId + "' is both a store and a gap in the numbering") }
        }
    }
    # A SURVEYED VERSION says which agent version a store's keys were last checked against; the live
    # check fails on a file written by a newer one (core-ownership L-056). It names a real store and
    # is a dotted version, or it would compare against nothing.
    $svProp = $Doc.PSObject.Properties["surveyedVersions"]
    if ($null -ne $svProp) {
        foreach ($vp in @($svProp.Value.PSObject.Properties)) {
            if ($stores -cnotcontains $vp.Name) { [void]$findings.Add("the table records a surveyed version for store '" + $vp.Name + "', which is not in the store list") }
            if ($vp.Value -isnot [string] -or "$($vp.Value)" -notmatch '^[0-9]+(\.[0-9]+){1,3}$') { [void]$findings.Add("the surveyed version for store '" + $vp.Name + "' is not a version: '" + $vp.Value + "'") }
        }
    }
    # A STORE'S GUARD applies to EVERY read of that store, before the read's own when. It exists
    # because a condition repeated per read was forgotten per read: the pane-sessions file was
    # guarded where it gave sessionId and pane and read bare for three other fields (review
    # finding 6, 2026-09-29). On the store, a read cannot leave it out. So a guard must say
    # something, and a store key the gate does not know is refused, since a misspelled guard
    # would read as no guard.
    foreach ($sp in @($Doc.stores.PSObject.Properties)) {
        foreach ($k in @($sp.Value.PSObject.Properties | ForEach-Object { $_.Name })) {
            if ($script:HordeOwnershipStoreKeys -cnotcontains $k) { [void]$findings.Add("store '" + $sp.Name + "' has an unknown key '" + $k + "'") }
        }
        # A store names its system, what it is and where it lives, as text. {} passed as a store,
        # so a field could read from a store nobody could find (second review, finding 5).
        $described = $true
        foreach ($k in @("system", "what", "path")) {
            $sv = $sp.Value.PSObject.Properties[$k]
            if ($null -eq $sv -or $sv.Value -isnot [string] -or "$($sv.Value)".Trim() -eq "") { $described = $false }
        }
        if (-not $described) { [void]$findings.Add("store '" + $sp.Name + "' needs system, what and path, each as text") }
        $g = $sp.Value.PSObject.Properties["guard"]
        if ($null -ne $g -and ($g.Value -isnot [string] -or "$($g.Value)".Trim() -eq "")) {
            [void]$findings.Add("store '" + $sp.Name + "' has an empty guard")
        }
    }
    # FIELD NAMES ARE MATCHED EXACTLY, as owners, stores and the required list are: a PowerShell
    # @{} ignores case, so it called sessionId and SessionId "listed twice". Two names that differ
    # only in case are still refused, under their own finding, because PowerShell reads them as one
    # property of a record (second review, finding 9).
    $seen = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
    $seenFolded = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $usedStores = @{}
    $allReads = @{}
    $fieldNames = New-Object System.Collections.ArrayList
    foreach ($f in @($Doc.fields)) {
        $n = "$($f.name)"
        if ($n.Trim() -eq "") { [void]$findings.Add("a field has no name"); continue }
        if ($seen.ContainsKey($n)) { [void]$findings.Add("field '" + $n + "' is listed twice") }
        elseif ($seenFolded.ContainsKey($n)) { [void]$findings.Add("fields '" + $seenFolded[$n] + "' and '" + $n + "' differ only in case") }
        $seen[$n] = $n
        if (-not $seenFolded.ContainsKey($n)) { $seenFolded[$n] = $n }
        [void]$fieldNames.Add($n)
        foreach ($k in @($f.PSObject.Properties | ForEach-Object { $_.Name })) {
            if ($script:HordeOwnershipFieldKeys -cnotcontains $k) { [void]$findings.Add("field '" + $n + "' has an unknown key '" + $k + "'") }
        }
        # EXACTLY ONE OWNER: a single string naming a listed owner. A list of two or more is two
        # owners; a list of one is still a list, and saying "more than one owner" about it sent a
        # reader looking for an owner that is not there (review finding 13).
        if ($f.owner -is [array] -and @($f.owner).Count -gt 1) { [void]$findings.Add("field '" + $n + "' names more than one owner") }
        elseif ($f.owner -is [array] -and @($f.owner).Count -eq 1) { [void]$findings.Add("field '" + $n + "' gives its owner as a list; an owner is one name, not a list") }
        elseif ($f.owner -is [array]) { [void]$findings.Add("field '" + $n + "' has no owner") }
        elseif ("$($f.owner)".Trim() -eq "") { [void]$findings.Add("field '" + $n + "' has no owner") }
        elseif ($owners -cnotcontains "$($f.owner)") { [void]$findings.Add("field '" + $n + "' names owner '" + $f.owner + "', which is not one of the listed owners") }
        # A READ RULE: at least one store to read from, each one real, each naming a field.
        # A null entry is a finding, not skipped: filtering it out let `[ {...}, null ]` pass as a
        # one-read rule, hiding whatever the null replaced (second review, finding 5). @($null)
        # is a one-element array, so an absent read is tested before it is wrapped.
        $read = @()
        if ($null -ne $f.read) { $read = @($f.read) }
        $realReads = 0
        foreach ($r in $read) { if ($null -ne $r) { $realReads++ } }
        if ($realReads -eq 0) { [void]$findings.Add("field '" + $n + "' has no read rule") }
        # Inside a read entry only store, field and when mean anything, so any other key is a
        # misspelling of one of them - a "wehn" would silently drop a guard. A when that is present
        # must say something, and one rule reading the same store and field twice is two orders
        # for one source (review finding 3, 2026-09-29).
        $readPairs = New-Object System.Collections.ArrayList
        foreach ($r in $read) {
            if ($null -eq $r) { [void]$findings.Add("field '" + $n + "' has an empty read entry"); continue }
            $s = "$($r.store)"
            if ($stores -cnotcontains $s) { [void]$findings.Add("field '" + $n + "' reads from store '" + $s + "', which is not in the store list") }
            else { $usedStores[$s] = $true }
            # The field read is text: 5 and true stringify to "5" and "True" and passed as names.
            if ($r.field -isnot [string] -or "$($r.field)".Trim() -eq "") { [void]$findings.Add("field '" + $n + "' reads from store '" + $s + "' without naming what it reads, as text") }
            foreach ($k in @($r.PSObject.Properties | ForEach-Object { $_.Name })) {
                if ($script:HordeOwnershipReadKeys -cnotcontains $k) { [void]$findings.Add("field '" + $n + "' reads from store '" + $s + "' with an unknown key '" + $k + "'") }
            }
            $w = $r.PSObject.Properties["when"]
            if ($null -ne $w -and ($w.Value -isnot [string] -or "$($w.Value)".Trim() -eq "")) {
                [void]$findings.Add("field '" + $n + "' reads from store '" + $s + "' under an empty condition")
            }
            # The field name is compared ignoring case: PowerShell reads sessionId and SessionId as
            # one property, so two reads differing only in case are one read listed twice.
            $pair = $s + "|" + "$($r.field)".ToLowerInvariant()
            if ($readPairs -ccontains $pair) { [void]$findings.Add("field '" + $n + "' reads '" + $r.field + "' from store '" + $s + "' twice (field names compared ignoring case)") }
            [void]$readPairs.Add($pair)
            $allReads[$s + "|" + "$($r.field)"] = $true
        }
        # A reason is text. false and 0 stringify to "False" and "0", which passed as reasons.
        foreach ($k in @("derived", "provisional")) {
            $p = $f.PSObject.Properties[$k]
            if ($null -ne $p -and ($p.Value -isnot [string] -or "$($p.Value)".Trim() -eq "")) { [void]$findings.Add("field '" + $n + "' says it is " + $k + " but not how or why") }
        }
    }
    foreach ($s in $stores) {
        if (-not $usedStores.ContainsKey($s)) { [void]$findings.Add("store '" + $s + "' is listed but no field reads it") }
    }

    # EVERY FIELD ACCOUNTED FOR. Without a list of what must be there, an empty table passed and a
    # deleted field was invisible (review finding 2, 2026-09-29): every check above runs per field,
    # so a field that is not there is never checked. The list is `required` in core/ownership.json,
    # and it stays there: schema/session-record.v1 is only the record the ENGINE stores - the
    # engine's own fields that are not derived - so it cannot be the list of every field. The
    # schema that answers for every field is session-view, deferred to migration plan step 2.3.
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
        $dsP = $x.PSObject.Properties["store"]; $dfP = $x.PSObject.Properties["field"]
        if ($null -ne $dsP -and $null -eq $dfP) { [void]$findings.Add("dropped field '" + $dn + "' names a store without a key") }
        elseif ($null -eq $dsP -and $null -ne $dfP) { [void]$findings.Add("dropped field '" + $dn + "' names a key without a store") }
        elseif ($null -ne $dsP) {
            if ($stores -cnotcontains "$($dsP.Value)") { [void]$findings.Add("dropped field '" + $dn + "' is from store '" + $dsP.Value + "', which is not in the store list") }
            if ($dfP.Value -isnot [string] -or "$($dfP.Value)".Trim() -eq "") { [void]$findings.Add("dropped field '" + $dn + "' names no key of its store, as text") }
            elseif ($allReads.ContainsKey("$($dsP.Value)" + "|" + "$($dfP.Value)")) { [void]$findings.Add("store key '" + $dfP.Value + "' of store '" + $dsP.Value + "' is both read and dropped") }
        }
        $dpP = $x.PSObject.Properties["provisional"]
        if ($null -ne $dpP -and ($dpP.Value -isnot [string] -or "$($dpP.Value)".Trim() -eq "")) { [void]$findings.Add("dropped field '" + $dn + "' says it is provisional but not why") }
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
