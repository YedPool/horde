# core/PermissionLevels - Horde's closed, ordered vocabulary of permission levels.
#
# WHY IT IS ITS OWN STEP (remote plan R0, planning/execution-plan-remote.md). Two later steps read
# this list and neither may wait on the other: engines E2, whose agent descriptor maps every level to
# one harness's own flags, and remote R9, whose node ceiling refuses a spawn - and a session.deliver,
# which is class `drive` and gated exactly like spawn - above the level the node's owner allows. Landed
# first and alone, the file breaks that cycle.
#
# THE ORDER IS THE FILE'S ORDER, lowest first. A level's rank is its position, so "above the ceiling"
# means a higher rank. Nothing here ever lowers a level to the nearest one below: a request above a
# ceiling is refused, never clamped, because a silent lowering is a policy change nobody asked for
# (engines E2, R9).
#
# NO HARNESS IN HERE (CONTRIBUTING 14). A level's meaning is said in Horde's terms. Which flag gives
# it is each harness's own business, in agents/<name>/, so the table check refuses a meaning that
# spells a flag, and the port-names ratchet refuses a meaning that names a harness or a terminal.
#
# MATCHED EXACTLY. Names are lower-case by rule and compared ordinally: a ceiling of "Bypass" is not
# bypass, and " plan" is not plan. A policy value that is not a level is an unknown with the reason,
# never the lowest level and never the highest - the reader refuses on unknown.
#
# No Set-StrictMode here: this file is dot-sourced, so a file-scope Set-StrictMode would set the
# caller's mode (see core/Tristate.ps1). The functions run under -Version Latest.
. (Join-Path $PSScriptRoot "Tristate.ps1")
# The one duplicate-key scanner, shared with core/Ownership.ps1 (core/JsonText.ps1).
. (Join-Path $PSScriptRoot "JsonText.ps1")

# A level's name: a lower-case letter, then lower-case letters, digits or hyphens, at most 32 in all.
$script:HordePermissionLevelNamePattern = '^[a-z][a-z0-9-]{0,31}$'
# A meaning is one line a person reads; 200 characters is room for a sentence and no essay.
$script:HordePermissionLevelMeaningMax = 200
# A flag is a hyphen or two, or a slash, then a letter, where no letter or digit comes before it:
# "--skip-all", "-y", "(--x)", a quoted "--x", "/y". A hyphen or slash inside a word ("read-only",
# "and/or") is not one. The first pattern looked only after a space, and the review of this PR passed
# "(--skip-all)" and a quoted flag straight through it.
$script:HordePermissionLevelFlagPattern = '(^|[^A-Za-z0-9])(--?|/)[A-Za-z]'
# A value quoted back in a reason is at most this long and printable. Under R9 the name comes from a
# remote request, and a reason is written to logs.
$script:HordePermissionLevelQuoteMax = 40

function Format-HordePermissionLevelQuote {
    # A level name as a reason may quote it: in quotes when short and printable, else described only.
    param([string]$Text)
    if ($Text.Length -le $script:HordePermissionLevelQuoteMax -and (Test-HordePermissionLevelPrintable -Text $Text)) { return ("'" + $Text + "'") }
    return ("a value of " + $Text.Length + " characters, not shown")
}

function Test-HordePermissionLevelPrintable {
    # Is the text printable ASCII and nothing else? Every character from a space to a tilde.
    param([string]$Text)
    foreach ($c in $Text.ToCharArray()) { if ([int]$c -lt 0x20 -or [int]$c -gt 0x7E) { return $false } }
    return $true
}

function Test-HordePermissionLevelTable {
    # Every problem with a parsed vocabulary, as text. None means the table is well formed.
    #
    # THE SHAPE IS CLOSED: an object with exactly one key, levels, a non-empty list of rows, each an
    # object with exactly name and meaning. A key beyond those is refused, not ignored, so a field
    # such as a flag cannot ride along unread.
    param($Table)
    $out = New-Object System.Collections.ArrayList
    if ($Table -isnot [System.Management.Automation.PSCustomObject]) {
        [void]$out.Add("the vocabulary must be an object with a levels key"); return $out.ToArray()
    }
    $keys = @($Table.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($k in $keys) { if ($k -cne "levels") { [void]$out.Add("the vocabulary has an extra key '" + $k + "'; it may hold only levels") } }
    if (-not ($keys -ccontains "levels")) { [void]$out.Add("the vocabulary has no levels key"); return $out.ToArray() }
    # Looked up, not dereferenced, and the rows walked through @(): each guard below then fails
    # alone as a refusal, never as a strict-mode error that would hide which rule was missing.
    $levelsProp = $Table.PSObject.Properties["levels"]
    $list = $null
    if ($null -ne $levelsProp) { $list = $levelsProp.Value }
    if ($list -isnot [System.Array]) { [void]$out.Add("levels must be a list, lowest level first"); return $out.ToArray() }
    $list = @($list)
    if ($list.Count -eq 0) { [void]$out.Add("levels is empty; a vocabulary needs at least one level"); return $out.ToArray() }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    for ($i = 0; $i -lt $list.Count; $i++) {
        $row = $list[$i]
        $at = "level " + ($i + 1)
        if ($row -isnot [System.Management.Automation.PSCustomObject]) { [void]$out.Add($at + " must be an object with a name and a meaning"); continue }
        $rowKeys = @($row.PSObject.Properties | ForEach-Object { $_.Name })
        foreach ($k in $rowKeys) { if ($k -cne "name" -and $k -cne "meaning") { [void]$out.Add($at + " has an extra key '" + $k + "'; a level holds only a name and a meaning") } }
        $name = $null
        if ($rowKeys -ccontains "name") { $name = $row.name }
        if ($name -isnot [string] -or $name -cnotmatch $script:HordePermissionLevelNamePattern) {
            [void]$out.Add($at + " has the name '" + $name + "', which is not a lower-case word of at most 32 letters, digits or hyphens")
        } elseif (-not $seen.Add($name)) {
            [void]$out.Add("the level '" + $name + "' is listed twice")
        }
        $meaning = $null
        if ($rowKeys -ccontains "meaning") { $meaning = $row.meaning }
        if ($meaning -isnot [string] -or $meaning.Trim() -eq "") { [void]$out.Add($at + " has no meaning; every level says what it allows"); continue }
        if (-not (Test-HordePermissionLevelPrintable -Text $meaning)) { [void]$out.Add($at + "'s meaning is not printable ASCII (CONTRIBUTING 13)") }
        if ($meaning.Length -gt $script:HordePermissionLevelMeaningMax) { [void]$out.Add($at + "'s meaning is longer than " + $script:HordePermissionLevelMeaningMax + " characters") }
        if ($meaning -cmatch $script:HordePermissionLevelFlagPattern) { [void]$out.Add($at + "'s meaning spells a command-line flag; a harness's flags belong in its own agents folder") }
    }
    return $out.ToArray()
}

function Read-HordePermissionLevelText {
    # The levels of a vocabulary given as JSON text, lowest first, each { name; rank; meaning }.
    # Throws, naming every problem, when the table is not well formed: a caller holding a broken
    # vocabulary has no ceiling it can trust.
    param([Parameter(Mandatory = $true)][string]$Text)
    $dups = @(Find-HordeJsonDuplicateKey -Text $Text)
    # The first finding only, and only when it is short and printable: a reason is written to logs, and
    # the scanner quotes the key and its path as they are (review of this fix, 2026-10-02).
    if ($dups.Count -gt 0) {
        $first = "$($dups[0])"
        if ($first.Length -gt $script:HordePermissionLevelMeaningMax -or -not (Test-HordePermissionLevelPrintable -Text $first)) { $first = "a finding of " + $first.Length + " characters, not shown" }
        throw ("the permission-level vocabulary is malformed: a key is written twice in one object, and only the last would be read (" + $dups.Count + " found; first: " + $first + ")")
    }
    $table = ConvertFrom-HordeJson -Text ($Text)
    $problems = @(Test-HordePermissionLevelTable -Table $table)
    if ($problems.Count -gt 0) { throw ("the permission-level vocabulary is malformed: " + ($problems -join "; ")) }
    $out = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $table.levels.Count; $i++) {
        [void]$out.Add([pscustomobject]@{ name = $table.levels[$i].name; rank = $i; meaning = $table.levels[$i].meaning })
    }
    return $out.ToArray()
}

function Get-HordePermissionLevels {
    # The vocabulary from core/permission-levels.json, or from -Path. The bytes are checked before
    # they are decoded: a decoder would turn a raw non-ASCII byte into a character, or into a
    # replacement mark, and either could pass for text.
    param([string]$Path = (Join-Path $PSScriptRoot "permission-levels.json"))
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    # Named apart from other non-ASCII bytes, because an editor adds it without being asked.
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw ("the permission-level vocabulary at '" + $Path + "' starts with a UTF-8 byte-order mark; save it as plain ASCII (CONTRIBUTING 13)") }
    foreach ($b in $bytes) { if ($b -gt 0x7F) { throw ("the permission-level vocabulary at '" + $Path + "' holds a byte that is not ASCII (CONTRIBUTING 13)") } }
    return (Read-HordePermissionLevelText -Text ([System.Text.Encoding]::ASCII.GetString($bytes)))
}

function Get-HordePermissionLevelRank {
    # The rank of one level name, as a Horde answer: known with the rank (0 is the lowest level and is
    # a real value), or unknown naming the value and the vocabulary. -Name is untyped so that "not
    # given" stays $null instead of becoming "" (CONTRIBUTING 12).
    #
    # THE RANK IS THE ROW'S POSITION in -Levels, never a rank field a row carries: a hand-built row
    # with no rank read as rank 0 under a caller without strict mode (review of this PR), and R9 is
    # where a forged rank would admit a request.
    param($Name, $Levels = $null)
    if ($null -eq $Levels) { $Levels = @(Get-HordePermissionLevels) }
    $Levels = @($Levels)
    $known = @($Levels | ForEach-Object { $_.name }) -join ", "
    if ($Name -isnot [string] -or $Name -eq "") { return (New-HordeUnknown -Reason ("no permission level was given; the levels are " + $known)) }
    for ($i = 0; $i -lt $Levels.Count; $i++) { if ($Levels[$i].name -ceq $Name) { return (New-HordeKnown -Value $i) } }
    return (New-HordeUnknown -Reason ((Format-HordePermissionLevelQuote -Text $Name) + " is not a Horde permission level; the levels are " + $known))
}

function Test-HordePermissionLevelAllowed {
    # Is the requested level at or below the ceiling? Known true or false, or unknown when either
    # side is not a level. The one comparison of two levels, so that R9 and R19 name no operator of
    # their own (review of this PR). A request above the ceiling is known FALSE - refused, never
    # lowered to the ceiling - and an unknown on either side is never true.
    param($Requested, $Ceiling, $Levels = $null)
    if ($null -eq $Levels) { $Levels = @(Get-HordePermissionLevels) }
    $req = Get-HordePermissionLevelRank -Name $Requested -Levels $Levels
    if ($req.state -cne "known") { return (New-HordeUnknown -Reason ("the requested permission level is not known: " + $req.reason)) }
    $cap = Get-HordePermissionLevelRank -Name $Ceiling -Levels $Levels
    if ($cap.state -cne "known") { return (New-HordeUnknown -Reason ("the permission ceiling is not known: " + $cap.reason)) }
    return (New-HordeKnown -Value ([bool]($req.value -le $cap.value)))
}

function Test-HordePermissionLevelCoverage {
    # Does a mapping name every level exactly once, and nothing else? For engines E2: an agent
    # descriptor's permissionLevels rows, reduced to the level each row maps. Returns
    # { ok; missing; unknown; duplicate }, each list in the order met, and ok exactly true or false.
    #
    # A vocabulary that gains a level leaves an old descriptor with that level MISSING; one that loses
    # a level leaves the old descriptor mapping a level that is now UNKNOWN. Both fail, so a harness
    # never runs on a mapping written for another list.
    param($Mapped, $Levels = $null)
    if ($null -eq $Levels) { $Levels = @(Get-HordePermissionLevels) }
    $names = @($Levels | ForEach-Object { "$($_.name)" })
    $nameSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($n in $names) { [void]$nameSet.Add($n) }
    $counts = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
    $unknown = New-Object System.Collections.ArrayList
    $duplicate = New-Object System.Collections.ArrayList
    # No mapping at all is nothing mapped - not one mapping of the level "".
    if ($null -eq $Mapped) { $Mapped = @() }
    foreach ($m in @($Mapped)) {
        $s = "$m"
        if ($counts.ContainsKey($s)) {
            $counts[$s] = $counts[$s] + 1
            if ($counts[$s] -eq 2) { [void]$duplicate.Add($s) }
            continue
        }
        $counts[$s] = 1
        if (-not $nameSet.Contains($s)) { [void]$unknown.Add($s) }
    }
    $missing = @($names | Where-Object { -not $counts.ContainsKey($_) })
    $ok = ($missing.Count -eq 0 -and $unknown.Count -eq 0 -and $duplicate.Count -eq 0)
    return [pscustomobject]@{ ok = [bool]$ok; missing = $missing; unknown = $unknown.ToArray(); duplicate = $duplicate.ToArray() }
}
