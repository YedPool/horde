# orcs/Console.ps1 - `horde orcs` at a command line: what each verb takes, and the lines it prints.
#
# THE ONE JOB of this file is to turn a command line into a call of orcs/Registry.ps1 and its answer into
# lines. Everything about the list - what is stored, what is derived, what is refused and why - is the
# registry's, so this caller cannot come to differ from the next one (the phone's signed command, PR 3).
#
# WHO MAY CHANGE WHAT (C and M, 2026-10-15): the domain lines are written ONCE by M as the seed (seed);
# an Orc proposes a change to its own through M, and later the founder edits through the same signed path
# as a reorder. So domain and name are for M and the founder, not for each Orc writing its own; the help
# says so. Every record keeps who wrote it (by): the session's own label when the command runs inside a
# session that can be proven (notices/Sender.ps1, the proof horde notify uses), else console.
#
# An id may be given as the Orc's letter when exactly one Orc on the list has it ("F" for
# decisions-page), as M and the founder know the Orcs by their letters.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Registry.ps1")

$script:HordeOrcVerbs = @("list", "order", "backburner", "name", "domain", "retire", "tier", "seed")

function Get-HordeOrcVerbs { return @($script:HordeOrcVerbs) }

function Resolve-HordeOrcBy {
    # Who is running the command, for the record's by: the proven session label, else "console". Never
    # refuses and never throws: it is kept, and it decides nothing.
    try {
        . (Join-Path (Split-Path -Parent $PSScriptRoot) "notices\Sender.ps1")
        $who = Resolve-HordeNoticeSender
        if ($who.ok -and "$($who.label)" -cmatch '\A[A-Za-z0-9][A-Za-z0-9 ._()-]{0,63}\z') { return "$($who.label)" }
    } catch { }
    return "console"
}

function Resolve-HordeOrcId {
    # The id -Given names: an id on the list as it stands, or the letter of exactly one Orc on it. Else
    # -Given as it came, for the registry to refuse in its own words.
    param([string]$Given, $Dash)
    $rows = @($Dash.orcs)
    if (@($rows | Where-Object { $_.id -ceq $Given }).Count -gt 0) { return $Given }
    if ($Given -cmatch '\A[A-Z]\z') {
        $by = @($rows | Where-Object { $_.letter -ceq $Given })
        if ($by.Count -eq 1) { return $by[0].id }
    }
    return $Given
}

function Format-HordeOrcRow {
    # One Orc as a line: place, letter, name, status, open questions, sessions, domain.
    param($Row)
    $open = $(if ($null -eq $Row.open) { "? open" } else { "" + $Row.open + " open" })
    $sess = $(if ($null -eq $Row.sessions) { "? sessions" } else { "" + $Row.sessions + " session" + $(if ($Row.sessions -eq 1) { "" } else { "s" }) })
    # Wargs: active/inactive, as his phone will show them (the founder, 2026-10-15).
    $sess = $sess + $(if ($null -eq $Row.wargsActive) { ", Wargs ?" } else { ", Wargs " + $Row.wargsActive + "/" + $Row.wargsInactive })
    $mark = $(if ($Row.registered) { "" } else { "  (new: registered at the next change)" })
    $letter = $(if ("$($Row.letter)" -ne "") { $Row.letter } else { "-" })
    return (("{0,3}  {1}  {2,-14} {3,-24} {4,-7} {5,-24} {6}  [{7}]{8}" -f $Row.order, $letter, $Row.name, $Row.statusText, $open, $sess, $Row.domain, $Row.id, $mark).TrimEnd())
}

function Get-HordeOrcListLines {
    param($Dash)
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add("Orcs, in his order (registry version " + $Dash.version + "):")
    $main = @($Dash.orcs | Where-Object { -not $_.backBurner })
    $back = @($Dash.orcs | Where-Object { $_.backBurner })
    if ($main.Count -eq 0) { [void]$lines.Add("  (none)") }
    foreach ($r in $main) { [void]$lines.Add((Format-HordeOrcRow $r)) }
    [void]$lines.Add("--- Back-burner ---")
    if ($back.Count -eq 0) { [void]$lines.Add("  (none)") }
    foreach ($r in $back) { [void]$lines.Add((Format-HordeOrcRow $r)) }
    foreach ($l in @($Dash.lines)) { [void]$lines.Add("note: " + $l) }
    return @($lines.ToArray())
}

function ConvertTo-HordeOrcJsonLine {
    # One line of JSON, ASCII: what -Json prints.
    param($Value)
    $t = ConvertTo-Json -InputObject $Value -Compress -Depth 8
    return [regex]::Replace($t, '[^\x20-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") })
}

function Invoke-HordeOrcCommand {
    # One verb with its arguments: { lines; failure }. failure is "" when it worked, else what to throw
    # (horde exits 1); a command line that is wrong throws New-HordeUsageError's kind (exit 2).
    param([Parameter(Mandatory = $true)][string]$Verb, [string[]]$Rest = @(), [string]$BackBurner = "", [string]$Version = "", [string]$File = "", [switch]$Json, [string]$HordeHome = "", [string]$By = "")
    $usage = { param($m) $e = New-Object System.ArgumentException($m); $e.Data["horde.usage"] = $true; throw $e }
    # An empty remainder can arrive as one empty word (measured 2026-10-15: `horde orcs list` bound one).
    $words = @($Rest | Where-Object { $null -ne $_ -and "$_" -ne "" })
    $ver = [long]-1
    if ($Version -ne "") {
        if ($Version -cnotmatch '\A[0-9]{1,15}\z') { & $usage ("-Version is the registry version the change was drawn from, a whole number (horde orcs list shows it), not '" + $Version + "'") }
        $ver = [long]$Version
    }
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    $paths = Get-HordeOrcPaths -HordeHome $HordeHome
    if (-not $paths.ok) { return [pscustomobject]@{ lines = @(); failure = $paths.reason } }
    $dash = Get-HordeOrcDash -Paths $paths
    if ($Verb -ceq "list") {
        if ($words.Count -gt 0) { & $usage "list takes no words" }
        if (-not $dash.ok) { return [pscustomobject]@{ lines = @(); failure = $dash.reason } }
        if ($Json) {
            # The same document the phone is sent (ConvertTo-HordeOrcDashDocument), and the notes beside it.
            $doc = ConvertTo-HordeOrcDashDocument -Dash $dash
            $doc | Add-Member -NotePropertyName "lines" -NotePropertyValue @($dash.lines)
            return [pscustomobject]@{ lines = @(ConvertTo-HordeOrcJsonLine $doc); failure = "" }
        }
        return [pscustomobject]@{ lines = @(Get-HordeOrcListLines $dash); failure = "" }
    }
    if ($By -eq "") { $By = Resolve-HordeOrcBy }
    if ($Verb -ceq "seed") {
        if ($File -eq "" -or $words.Count -gt 0) { & $usage "seed takes -File <seed.json> and nothing else" }
        if (-not [System.IO.File]::Exists($File)) { return [pscustomobject]@{ lines = @(); failure = ("there is no seed file at " + $File) } }
        $text = [System.IO.File]::ReadAllText($File, (New-Object System.Text.UTF8Encoding($false, $true)))
        $seed = $null
        if (@(Find-HordeJsonDuplicateKey -Text $text).Count -eq 0) { try { $seed = ConvertFrom-HordeJson $text } catch { $seed = $null } }
        $ok = ($seed -is [System.Management.Automation.PSCustomObject] -and $null -ne $seed.PSObject.Properties["v"] -and $seed.v -eq 1 -and $null -ne $seed.PSObject.Properties["domains"] -and $seed.domains -is [System.Management.Automation.PSCustomObject])
        if ($ok) { foreach ($p in @($seed.domains.PSObject.Properties)) { if ($p.Value -isnot [string]) { $ok = $false } } }
        if (-not $ok) { return [pscustomobject]@{ lines = @(); failure = ("the seed file is not {""v"":1,""domains"":{""<letter>"":""<domain>"", ...}} with no member repeated: " + $File) } }
        $table = [ordered]@{}
        foreach ($p in @($seed.domains.PSObject.Properties)) { $table[$p.Name] = [string]$p.Value }
        $r = Invoke-HordeOrcSeed -Domains $table -Paths $paths -By $By
        return [pscustomobject]@{ lines = @($r.lines); failure = $(if ($r.ok) { "" } else { "the seed was not applied whole; the lines above say which Orcs" }) }
    }
    $request = $null
    switch -CaseSensitive ($Verb) {
        "order" {
            if ($words.Count -eq 0) { & $usage "order names every Orc on the list, first to last: horde orcs order <id> <id> ... [-BackBurner <id,id>]" }
            $back = @("$BackBurner".Split([char]',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } | ForEach-Object { Resolve-HordeOrcId -Given $_ -Dash $dash })
            $request = @{ order = @($words | ForEach-Object { Resolve-HordeOrcId -Given $_ -Dash $dash }); backBurner = @($back) }
        }
        "backburner" {
            if ($words.Count -ne 2 -or @("on", "off") -cnotcontains $words[1]) { & $usage "backburner takes an id and on or off: horde orcs backburner <id> on" }
            $request = @{ id = (Resolve-HordeOrcId -Given $words[0] -Dash $dash); on = ($words[1] -ceq "on") }
        }
        "name" {
            if ($words.Count -lt 2) { & $usage "name takes an id and the name: horde orcs name <id> ""<name>""" }
            $request = @{ id = (Resolve-HordeOrcId -Given $words[0] -Dash $dash); name = (@($words | Select-Object -Skip 1) -join " ") }
        }
        "domain" {
            if ($words.Count -lt 2) { & $usage "domain takes an id and the domain line: horde orcs domain <id> ""<one line>""" }
            $request = @{ id = (Resolve-HordeOrcId -Given $words[0] -Dash $dash); domain = (@($words | Select-Object -Skip 1) -join " ") }
        }
        "retire" {
            if ($words.Count -ne 1) { & $usage "retire takes one id: horde orcs retire <id>" }
            $request = @{ id = (Resolve-HordeOrcId -Given $words[0] -Dash $dash) }
        }
        "tier" {
            if ($words.Count -ne 2 -or @("1", "2") -cnotcontains $words[1]) { & $usage "tier takes an id and 1 or 2: horde orcs tier <id> 1" }
            $request = @{ id = (Resolve-HordeOrcId -Given $words[0] -Dash $dash); tier = [int]$words[1] }
        }
        default { & $usage ("'" + $Verb + "' is not a verb of horde orcs; the verbs are: " + ($script:HordeOrcVerbs -join ", ")) }
    }
    $r = Invoke-HordeOrcWrite -Operation $Verb -Request $request -Paths $paths -Version $ver -By $By
    if ($Json) { return [pscustomobject]@{ lines = @(ConvertTo-HordeOrcJsonLine $r); failure = $(if ($r.outcome -ceq "done" -or $r.outcome -ceq "unchanged") { "" } else { $r.outcome + ": " + $r.reason }) } }
    switch -CaseSensitive ($r.outcome) {
        "done" { return [pscustomobject]@{ lines = @("done: the registry is at version " + $r.version + $(if ($r.written -gt 1) { " (" + ($r.written - 1) + " new lane(s) registered first)" } else { "" })); failure = "" } }
        "unchanged" { return [pscustomobject]@{ lines = @("unchanged: " + $r.reason + " (version " + $r.version + ")"); failure = "" } }
        default { return [pscustomobject]@{ lines = @(); failure = ($r.outcome + ": " + $r.reason) } }
    }
}
