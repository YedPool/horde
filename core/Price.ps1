# core/Price - what a model call would cost at list price, from a versioned price table.
#
# DECISIONS THIS CARRIES (metrics design, "Decisions taken"):
#   - Cost is computed from token counts and a price table, never read from a harness's own cost
#     field and never asked of a vendor (decision 7, the founder, 2026-09-30).
#   - Every cost is DERIVED, tagged ESTIMATE, and carries the table's version, so a past figure can
#     be recomputed and a figure from one table is never silently mixed with another's (design 1.2).
#   - It is labelled notionalUsd: on a subscription no token is billed, so this is what the tokens
#     WOULD have cost at API list price, never money spent (decision 4). Nothing here sums it into a
#     USD total.
#
# WHERE THE TABLES LIVE (coordinator's decision, 2026-10-01): in the repository, one per engine, at
# agents/<name>/prices.json - the one place CONTRIBUTING 14 lets a harness's and its models' names
# appear - so a price change is a reviewable commit. A user may add <HordeHome>\metrics\prices.json, an
# OVERRIDE layered on top: a model it prices replaces the repository's entry for that model, and nothing
# else changes. Every model entry remembers which file and which version it came from, and every cost
# names the tables that priced it. Core finds the repository tables by folder and names none.
#
# WHAT A RATE DEPENDS ON, AND WHAT M1 LEAVES OUT. Observed 2026-09-30 (design 2.9): cache writes are
# priced by lifetime (5 minutes and 1 hour differ), and a request's geography can multiply every rate
# (1.1 for "us" on one provider). Both are read per call. Context-size tiers, time-of-day windows and
# batch discounts are not modelled yet (plan step M4): a call they would apply to is not in the table
# this plan ships, and a table that names a speed or geography this code does not know gets UNKNOWN,
# never the standard rate.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1,
# core/ReadShared.ps1 and core/Home.ps1.

# What this file calls, loaded here so the file works on its own (tools/CoreLoad.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "Home.ps1")

$script:HordeRateKeys = @("input", "cacheRead", "cacheWrite", "cacheWrite5m", "cacheWrite1h", "output")


function Test-HordeRates {
    # Problems with a rates object, as strings.
    param($Rates, [string]$Where)
    $p = @()
    if ($Rates -isnot [System.Collections.IDictionary]) { return @($Where + ": rates must be an object") }
    foreach ($k in @($Rates.Keys)) {
        if ($script:HordeRateKeys -cnotcontains $k) { $p += ($Where + ": '" + $k + "' is not a rate this table can hold") ; continue }
        $v = $Rates[$k]
        if (-not ($v -is [int] -or $v -is [long] -or $v -is [decimal] -or $v -is [double]) -or $v -lt 0) { $p += ($Where + ": rate '" + $k + "' must be a number of at least 0") }
    }
    return $p
}

function ConvertFrom-HordePriceTableText {
    # Parse and check a price table. Returns an answer: known table, or unknown with every problem
    # found, so a table that is wrong in two places says so once rather than twice over two runs.
    #
    # -Source names where the table came from; every model entry is stamped with it, the table's
    # version and its perTokens, so a cost can always say which file and version priced it.
    param([Parameter(Mandatory = $true)][string]$Text, [string]$What = "the price table", [string]$Source = "a given table")
    $t = $null
    try { $t = ConvertFrom-HordeJsonObject -Text ($Text) } catch { return (New-HordeUnknown -Reason ($What + " is not JSON") -ErrorRecord $_) }
    if ($t -isnot [System.Collections.IDictionary]) { return (New-HordeUnknown -Reason ($What + " is not a JSON object")) }
    $p = @()
    if ($t["schemaVersion"] -ne 1) { $p += "schemaVersion must be 1, not '" + $t["schemaVersion"] + "'" }
    if ($t["version"] -isnot [string] -or "$($t["version"])".Trim() -eq "") { $p += "it has no version, so a cost could not say which table priced it" }
    $per = $t["perTokens"]
    if (-not ($per -is [int] -or $per -is [long]) -or $per -le 0) { $p += "perTokens must be a positive whole number" }
    $models = $t["models"]
    if ($models -isnot [System.Collections.IDictionary] -or $models.Count -eq 0) { $p += "it prices no models" }
    else {
        foreach ($id in @($models.Keys)) {
            $m = $models[$id]
            if ($m -isnot [System.Collections.IDictionary]) { $p += ("model '" + $id + "' is not an object"); continue }
            $p += @(Test-HordeRates -Rates $m["rates"] -Where ("model '" + $id + "'"))
            if ($null -ne $m["geo"]) {
                if ($m["geo"] -isnot [System.Collections.IDictionary]) { $p += ("model '" + $id + "': geo must be an object") }
                else { foreach ($g in @($m["geo"].Keys)) { $gv = $m["geo"][$g]; if (-not ($gv -is [int] -or $gv -is [decimal] -or $gv -is [long]) -or $gv -le 0) { $p += ("model '" + $id + "': geo '" + $g + "' must be a positive multiplier") } } }
            }
            if ($null -ne $m["speeds"]) {
                if ($m["speeds"] -isnot [System.Collections.IDictionary]) { $p += ("model '" + $id + "': speeds must be an object") }
                else { foreach ($s in @($m["speeds"].Keys)) { $p += @(Test-HordeRates -Rates $m["speeds"][$s] -Where ("model '" + $id + "' speed '" + $s + "'")) } }
            }
        }
    }
    if ($p.Count -gt 0) { return (New-HordeUnknown -Reason ($What + " is not usable: " + ($p -join "; "))) }
    foreach ($id in @($models.Keys)) { $models[$id]["source"] = $Source; $models[$id]["tableVersion"] = "$($t["version"])"; $models[$id]["perTokens"] = $per }
    return (New-HordeKnown -Value $t)
}

function Get-HordePriceOverridePath { return (Join-Path (Join-Path (Get-HordeHome) "metrics") "prices.json") }

function Get-HordePriceTableFiles {
    # The repository's tables, found by folder and never named: agents/<name>/prices.json.
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    $agents = Join-Path $Root "agents"
    if (-not (Test-Path -LiteralPath $agents -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $agents -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "prices.json" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Read-HordePriceTableFile {
    # One table file as an answer, its entries stamped with -Source.
    param([string]$Path, [string]$Source)
    $text = $null
    try { $text = Read-HordeSharedText -Path $Path } catch { return (New-HordeUnknown -Reason ("could not read the price table " + $Source) -ErrorRecord $_) }
    return (ConvertFrom-HordePriceTableText -Text $text -What ("the price table " + $Source) -Source $Source)
}

function Merge-HordePriceTables {
    # Layer tables into one book: -Base (the repository's, which may not price one model twice), then
    # -Override, whose models replace the base's. Returns an answer: known book { version; models;
    # sources }, absent when there is no table at all, unknown when any table is unusable - an override
    # that cannot be read is never silently skipped, or the repository price would stand in for it.
    param([object[]]$Base = @(), $Override = $null)
    $tables = @($Base) + @($(if ($null -ne $Override) { $Override }))
    foreach ($t in $tables) { if ($t.state -eq "unknown") { return $t } }
    $models = @{}
    $sources = New-Object System.Collections.ArrayList
    foreach ($t in @($Base)) {
        foreach ($id in @($t.value["models"].Keys)) {
            if ($models.ContainsKey($id)) { return (New-HordeUnknown -Reason ("model '" + $id + "' is priced by both " + $models[$id]["source"] + " and " + $t.value["models"][$id]["source"] + "; the repository must price a model once")) }
            $models[$id] = $t.value["models"][$id]
        }
    }
    if ($null -ne $Override) { foreach ($id in @($Override.value["models"].Keys)) { $models[$id] = $Override.value["models"][$id] } }
    if ($tables.Count -eq 0) { return (New-HordeAbsent -Note "no price table: none in the repository's agents folders and no override") }
    foreach ($t in $tables) { $first = @($t.value["models"].Values)[0]; [void]$sources.Add("" + $first["source"] + " " + $first["tableVersion"]) }
    return (New-HordeKnown -Value @{ version = ($sources -join "; "); models = $models; sources = $sources.ToArray() })
}

function Read-HordePriceBook {
    # The repository's tables with the user's override on top, as an answer (Merge-HordePriceTables).
    param([string]$Root = (Split-Path -Parent $PSScriptRoot), [string]$OverridePath = (Get-HordePriceOverridePath))
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $base = @(foreach ($f in (Get-HordePriceTableFiles -Root $Root)) { Read-HordePriceTableFile -Path $f -Source ([System.IO.Path]::GetFullPath($f).Substring($rootFull.Length).Replace('\', '/')) })
    $over = $null
    if (Test-Path -LiteralPath $OverridePath -PathType Leaf) { $over = Read-HordePriceTableFile -Path $OverridePath -Source "the HORDE_HOME override" }
    return (Merge-HordePriceTables -Base $base -Override $over)
}

function Get-HordePriceSource {
    # "<file> <version>" of the table that prices a model in a book, or "" when none does.
    param($Table, [string]$Model)
    $e = $Table["models"][$Model]
    if ($null -eq $e) { return "" }
    return ("" + $e["source"] + " " + $e["tableVersion"])
}

function Get-HordeCallCost {
    # The notional list-price cost of one call record, as an answer: known [decimal], or unknown with
    # the first reason it cannot be priced. Arithmetic is in [decimal], so a sum of thousands of calls
    # carries no binary rounding.
    param([Parameter(Mandatory = $true)]$Table, [Parameter(Mandatory = $true)]$Call)
    $version = "$($Table["version"])"
    # Each entry knows its own table: in a layered book the repository and the override differ.
    if ($Call.model.state -ne "known") { return (New-HordeUnknown -Reason ("a call's model is unknown, so it cannot be priced (line " + $Call.line + ")")) }
    $model = "$($Call.model.value)"
    $entry = $Table["models"][$model]
    if ($null -eq $entry) { return (New-HordeUnknown -Reason ("price table " + $version + " has no price for model '" + $model + "'")) }
    if ($Call.usage.state -ne "known") { return (New-HordeUnknown -Reason ("a call on " + $model + " has no usage (line " + $Call.line + ")")) }
    $version = "" + $entry["source"] + " " + $entry["tableVersion"]
    $u = $Call.usage.value

    $rates = $entry["rates"]
    $speed = "$($Call.speed)"
    if ($speed -ne "" -and $speed -ne "standard") {
        $sp = $null
        if ($null -ne $entry["speeds"]) { $sp = $entry["speeds"][$speed] }
        if ($null -eq $sp) { return (New-HordeUnknown -Reason ("price table " + $version + " has no rates for speed '" + $speed + "' on " + $model)) }
        $rates = $sp
    }

    $mult = [decimal]1
    $geo = "$($Call.inferenceGeo)"
    $standard = @()
    if ($null -ne $entry["geoStandard"]) { $standard = @($entry["geoStandard"] | ForEach-Object { "$_" }) }
    if ($geo -ne "" -and $standard -cnotcontains $geo) {
        $gm = $null
        if ($null -ne $entry["geo"]) { $gm = $entry["geo"][$geo] }
        if ($null -eq $gm) { return (New-HordeUnknown -Reason ("price table " + $version + " does not say how geography '" + $geo + "' prices on " + $model)) }
        $mult = [decimal]$gm
    }

    # Each token class needs its rate only when it has tokens: a table with no cache-write rate still
    # prices a call that wrote no cache. A class with tokens and no rate is unknown, never free.
    $parts = New-Object System.Collections.ArrayList
    $need = { param($n, $key) if ($n -gt 0) { if ($null -eq $rates[$key]) { throw ("price table " + $version + " has no '" + $key + "' rate for " + $model) }; [void]$parts.Add([decimal]$n * [decimal]$rates[$key]) } }
    try {
        & $need $u.input "input"
        & $need $u.cacheRead "cacheRead"
        & $need $u.output "output"
        if ($u.cacheWrite -gt 0) {
            if ($u.cacheWriteSplit.state -eq "known") {
                $s = $u.cacheWriteSplit.value
                if (($s.m5 + $s.h1) -ne $u.cacheWrite) { throw ("the cache-write split of a call on " + $model + " (" + $s.m5 + " + " + $s.h1 + ") does not add up to its cache writes (" + $u.cacheWrite + ")") }
                & $need $s.m5 "cacheWrite5m"
                & $need $s.h1 "cacheWrite1h"
            }
            elseif ($null -ne $rates["cacheWrite"]) { & $need $u.cacheWrite "cacheWrite" }
            else { throw ("a call on " + $model + " wrote cache without saying for how long, and table " + $version + " prices only by lifetime") }
        }
    } catch { return (New-HordeUnknown -Reason "$($_.Exception.Message)") }
    $sum = [decimal]0
    foreach ($x in $parts) { $sum += $x }
    return (New-HordeKnown -Value ($sum * $mult / [decimal]$entry["perTokens"]))
}
