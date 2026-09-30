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

function Get-HordeOwnership {
    param([string]$Path = (Join-Path $PSScriptRoot "ownership.json"))
    return ((Get-Content -LiteralPath $Path -Raw) | ConvertFrom-Json)
}

function Get-HordeOwnershipField {
    # One field's entry, or $null.
    param($Doc, [Parameter(Mandatory = $true)][string]$Name)
    return (@($Doc.fields | Where-Object { $_.name -ceq $Name }) | Select-Object -First 1)
}

function Test-HordeOwnership {
    # Every way the ownership table can be wrong, as a list of findings. Empty means it holds.
    param($Doc)
    $findings = New-Object System.Collections.ArrayList
    if ($null -eq $Doc -or $null -eq $Doc.fields -or $null -eq $Doc.stores -or $null -eq $Doc.owners) {
        [void]$findings.Add("the document needs owners, stores and fields")
        return @($findings)
    }
    $owners = @($Doc.owners.PSObject.Properties | ForEach-Object { $_.Name })
    $stores = @($Doc.stores.PSObject.Properties | ForEach-Object { $_.Name })
    $seen = @{}
    $usedStores = @{}
    foreach ($f in @($Doc.fields)) {
        $n = "$($f.name)"
        if ($n.Trim() -eq "") { [void]$findings.Add("a field has no name"); continue }
        if ($seen.ContainsKey($n)) { [void]$findings.Add("field '" + $n + "' is listed twice") }
        $seen[$n] = $true
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
        foreach ($r in $read) {
            $s = "$($r.store)"
            if ($stores -notcontains $s) { [void]$findings.Add("field '" + $n + "' reads from store '" + $s + "', which is not in the store list") }
            else { $usedStores[$s] = $true }
            if ("$($r.field)".Trim() -eq "") { [void]$findings.Add("field '" + $n + "' reads from store '" + $s + "' without naming what it reads") }
        }
        foreach ($k in @("derived", "provisional")) {
            $p = $f.PSObject.Properties[$k]
            if ($null -ne $p -and "$($p.Value)".Trim() -eq "") { [void]$findings.Add("field '" + $n + "' says it is " + $k + " but not how or why") }
        }
    }
    foreach ($s in $stores) {
        if (-not $usedStores.ContainsKey($s)) { [void]$findings.Add("store '" + $s + "' is listed but no field reads it") }
    }
    return @($findings)
}
