# core/NodePolicy - what a node lets a hub start on it, and the one check a spawn request passes.
#
# REMOTE PLAN STEP R9, as decided 2026-10-05 for the act path. Two inputs, each owned by the node:
#   - schema/node-policy.v1, the file <HordeHome>/node/policy.json: the registered clones, the engine
#     profiles offered, the daily spawn cap. Lists and maps, so a file of its own (see the schema).
#   - the engine configuration's resolution (core/EngineResolve.ps1) for the session being started:
#     the requested permission level (key permission) and the node's ceiling (remote.permissionCeiling,
#     settable only in L1 and L4 and only lowered by L4).
#
# A REQUEST ABOVE THE CEILING IS REFUSED, NEVER LOWERED. Test-HordePermissionLevelAllowed (R0) is the
# one comparison; this file compares no levels of its own.
#
# THE CEILING COMES FROM THE NODE'S OWN LAYERS AND NOWHERE ELSE. The registry already refuses the key
# in a run spec (L3) or a spawn (L5), and the resolver keeps L4 from raising it. This file checks the
# provenance again, because it is the last thing between a link and a bypassed session: a ceiling
# whose winning rule is not in L1 or L4 is not used, the default is, and the reason says so. The
# default, with no rule at all, is the level just below the top of R0's vocabulary - every approval
# skipped is never the default (remote design decision 4). The always-on node's owner may set the
# ceiling to the top in L1 (decision of 2026-10-05: ssh access to that box is already that trust).
#
# EVERY RULE IS CHECKED, AND EVERY REFUSAL IS NAMED. A request that breaks three rules is told all
# three, so its sender fixes it once.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Schema.ps1")
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "PermissionLevels.ps1")

# The most sessions a node may allow a hub to start per UTC day. A larger number is a typo, not a
# policy: the fleet's busiest day on record started about 120 sessions on one machine.
$script:HordeNodeSpawnCapMax = 1000
# The layers the ceiling may come from (core/config-keys.json says the same; this is the second line).
$script:HordeCeilingLayers = @("L1", "L4")

function Get-HordeNodePolicyPath {
    # Where the node keeps its policy: <HordeHome>\node\policy.json.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    return (Join-Path (Join-Path $HordeHome "node") "policy.json")
}

function Test-HordeNodePolicyPath {
    # Is this an absolute local path with no '.' or '..' segment? Such a segment would let a folder
    # that reads as inside a clone resolve outside it.
    param([string]$Path)
    if ($Path -cnotmatch '\A[A-Za-z]:\\') { return $false }
    foreach ($seg in $Path.Substring(3).Split('\')) { if ($seg -ceq "." -or $seg -ceq "..") { return $false } }
    return $true
}

function Test-HordeNodePathInside {
    # Is -Path the folder -Root or somewhere below it? Compared without case, as Windows compares paths,
    # on whole segments: C:\a\bc is not inside C:\a\b.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Root)
    $p = $Path.TrimEnd('\'); $r = $Root.TrimEnd('\')
    if ($p.Equals($r, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $p.StartsWith($r + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-HordeNodeWorktreeRoot {
    # A registered clone's worktree root: its own worktreeRoot, or the sibling <path>-worktrees.
    param([Parameter(Mandatory = $true)]$Repo)
    $wr = $Repo.PSObject.Properties["worktreeRoot"]
    if ($null -ne $wr -and "$($wr.Value)" -ne "") { return "$($wr.Value)".TrimEnd('\') }
    return ("$($Repo.path)".TrimEnd('\') + "-worktrees")
}

function Read-HordeNodePolicyText {
    # The policy from its text, as an answer: known with the parsed policy, or unknown naming every
    # problem. Plain ASCII, one key per object, the schema, then the rules the schema cannot say.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $problems = New-Object System.Collections.ArrayList
    if ($Text -cmatch '[^\x00-\x7F]') { return (New-HordeUnknown -Reason "the node policy holds a character that is not ASCII (CONTRIBUTING 13)") }
    foreach ($d in @(Find-HordeJsonDuplicateKey -Text $Text)) { if ($null -ne $d) { [void]$problems.Add("" + $d) } }
    $doc = $null
    try { $doc = $Text | ConvertFrom-Json } catch { return (New-HordeUnknown -Reason "the node policy is not JSON") }
    if ($null -eq $doc) { return (New-HordeUnknown -Reason "the node policy is empty") }
    foreach ($b in @(Test-HordeSchema -Value $doc -Schema (Get-HordeSchema -Name "node-policy.v1"))) { [void]$problems.Add("" + $b) }
    if ($problems.Count -gt 0) { return (New-HordeUnknown -Reason ("the node policy is malformed: " + ($problems -join "; "))) }
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($r in @($doc.repos)) {
        if ($null -eq $r) { continue }
        if (-not $ids.Add("" + $r.repoId)) { [void]$problems.Add("the repository " + $r.repoId + " is registered twice") }
        if (-not (Test-HordeNodePolicyPath -Path ("" + $r.path))) { [void]$problems.Add("the path of " + $r.repoId + " has a '.' or '..' segment") }
        $root = Get-HordeNodeWorktreeRoot -Repo $r
        if (-not (Test-HordeNodePolicyPath -Path $root)) { [void]$problems.Add("the worktree root of " + $r.repoId + " has a '.' or '..' segment") }
        # A ROOT INSIDE THE CLONE is refused: a worktree there is a folder git sees as part of the clone.
        elseif (Test-HordeNodePathInside -Path $root -Root ("" + $r.path)) { [void]$problems.Add("the worktree root of " + $r.repoId + " is inside its clone") }
    }
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($p in @($doc.profiles)) { if ($null -ne $p -and -not $names.Add("" + $p)) { [void]$problems.Add("the profile " + $p + " is offered twice") } }
    if ([long]$doc.dailySpawnCap -gt $script:HordeNodeSpawnCapMax) { [void]$problems.Add("the daily spawn cap " + $doc.dailySpawnCap + " is above " + $script:HordeNodeSpawnCapMax) }
    if ($problems.Count -gt 0) { return (New-HordeUnknown -Reason ("the node policy is malformed: " + ($problems -join "; "))) }
    return (New-HordeKnown -Value $doc)
}

function Get-HordeNodePolicy {
    # The node's policy from its file: known, absent when there is no file (the node offers nothing,
    # so every spawn is refused), or unknown when it cannot be read or is malformed.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return (New-HordeAbsent -Note ("this node has no policy file at " + $Path + ", so it lets a hub start nothing")) }
    $bytes = $null
    try { $bytes = [System.IO.File]::ReadAllBytes($Path) } catch { return (New-HordeUnknown -Reason ("the node policy could not be read: " + $_.Exception.Message)) }
    return (Read-HordeNodePolicyText -Text ([System.Text.Encoding]::ASCII.GetString($bytes)))
}

function Resolve-HordeNodeWorkdir {
    # Where a session for this repository runs, as an answer: the registered clone when no worktree is
    # named, <worktreeRoot>\<name> when one is. Pure: whether the folder exists is the caller's to ask.
    # -Worktree is the spawn's worktree object (its name) or $null.
    param([Parameter(Mandatory = $true)]$Policy, [string]$RepoId, $Worktree = $null)
    $repo = @(@($Policy.repos) | Where-Object { $null -ne $_ -and ("" + $_.repoId).Equals($RepoId, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($repo.Count -ne 1) { return (New-HordeUnknown -Reason ("this node has not registered the repository " + $RepoId)) }
    if ($null -eq $Worktree) { return (New-HordeKnown -Value ("" + $repo[0].path).TrimEnd('\')) }
    $name = "" + $Worktree.name
    # The link's worktree-name pattern already refuses a separator, '..' and a device name; this is the
    # second line, because a path built here is where a session will write.
    if ($name -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,99}\z' -or $name.Contains("..") -or $name.EndsWith(".")) { return (New-HordeUnknown -Reason ("'" + $name + "' is not a worktree name")) }
    $root = Get-HordeNodeWorktreeRoot -Repo $repo[0]
    $path = $root + "\" + $name
    if (-not (Test-HordeNodePathInside -Path $path -Root $root)) { return (New-HordeUnknown -Reason ("the worktree " + $name + " would not sit inside " + $root)) }
    return (New-HordeKnown -Value $path)
}

function Get-HordeNodeCeiling {
    # The ceiling for one resolution: { level; from; note }. From the winning rule when it is in L1 or
    # L4; the default when no rule sets it; $null level when it cannot be told (a tie), which refuses.
    param([Parameter(Mandatory = $true)]$Resolution, $Levels = $null)
    if ($null -eq $Levels) { $Levels = @(Get-HordePermissionLevels) }
    $default = "" + @($Levels)[@($Levels).Count - 2].name
    $s = $null
    if ($Resolution.settings.Contains("remote.permissionCeiling")) { $s = $Resolution.settings["remote.permissionCeiling"] }
    if ($null -eq $s -or $s.answer.state -eq "absent") { return [pscustomobject]@{ level = $default; from = "default"; note = ("no rule sets the ceiling, so it is the default, " + $default) } }
    if ($s.answer.state -ne "known") { return [pscustomobject]@{ level = $null; from = ""; note = ("the ceiling cannot be told: " + $s.answer.reason) } }
    if ($script:HordeCeilingLayers -cnotcontains ("" + $s.layer)) { return [pscustomobject]@{ level = $default; from = "default"; note = ("the ceiling rule " + $s.rule + " is in " + $s.layer + ", and only the node's own layers (" + ($script:HordeCeilingLayers -join ", ") + ") may set it; the default " + $default + " is used") } }
    return [pscustomobject]@{ level = ("" + $s.answer.value); from = ("" + $s.layer + " " + $s.rule); note = "" }
}

function Test-HordeRemotePolicy {
    # May a hub start this session on this node? Returns { allowed; reasons; level; ceiling;
    # ceilingFrom; workdir }. allowed is exactly $true or $false; reasons names every rule broken.
    # -Policy: the node policy answer (Get-HordeNodePolicy). -Resolution: Resolve-HordeEngine's for
    # the session's target. -Request: { profile; repoId; worktree } as the spawn carried them (worktree
    # $null for the registered clone). -SpawnsToday: what the node's journal counts for this UTC day.
    param([Parameter(Mandatory = $true)]$Policy, [Parameter(Mandatory = $true)]$Resolution,
        [Parameter(Mandatory = $true)]$Request, [int]$SpawnsToday = 0, $Levels = $null)
    if ($null -eq $Levels) { $Levels = @(Get-HordePermissionLevels) }
    $reasons = New-Object System.Collections.ArrayList
    $out = [ordered]@{ allowed = $false; reasons = @(); level = $null; ceiling = $null; ceilingFrom = ""; workdir = $null }

    # The policy file first: without one the node offers nothing.
    $pol = $null
    if ($Policy.state -eq "known") { $pol = $Policy.value }
    elseif ($Policy.state -eq "absent") { [void]$reasons.Add($Policy.reason) }
    else { [void]$reasons.Add("the node's policy cannot be read, so it lets a hub start nothing: " + $Policy.reason) }

    if ($null -ne $pol) {
        $profile = "" + $Request.profile
        if (@($pol.profiles) -cnotcontains $profile) { [void]$reasons.Add("this node does not offer the profile '" + $profile + "'") }
        if ($SpawnsToday -ge [int]$pol.dailySpawnCap) { [void]$reasons.Add("this node's daily spawn cap of " + $pol.dailySpawnCap + " is reached (" + $SpawnsToday + " today)") }
        $wd = Resolve-HordeNodeWorkdir -Policy $pol -RepoId ("" + $Request.repoId) -Worktree $Request.worktree
        if ($wd.state -eq "known") { $out.workdir = $wd.value } else { [void]$reasons.Add($wd.reason) }
    }

    # The binding must have resolved: a spawn on a guessed harness is no spawn.
    if ($Resolution.binding.state -ne "known") { [void]$reasons.Add("the engine is not resolved: " + $Resolution.binding.reason) }

    # The level asked for, and the ceiling.
    $lv = $Resolution.settings["permission"]
    if ($null -eq $lv -or $lv.answer.state -ne "known") {
        $why = "no rule sets it"
        if ($null -ne $lv -and $lv.answer.state -eq "unknown") { $why = $lv.answer.reason }
        [void]$reasons.Add("no permission level is resolved for this session (" + $why + "); a session is never started at a level nobody chose")
    } else { $out.level = "" + $lv.answer.value }
    $cap = Get-HordeNodeCeiling -Resolution $Resolution -Levels $Levels
    $out.ceiling = $cap.level; $out.ceilingFrom = $cap.from
    if ($null -eq $cap.level) { [void]$reasons.Add($cap.note) }
    elseif ($cap.from -ceq "default" -and $cap.note -like "*only the node's own layers*") { [void]$reasons.Add($cap.note) }
    if ($null -ne $out.level -and $null -ne $cap.level) {
        $ok = Test-HordePermissionLevelAllowed -Requested $out.level -Ceiling $cap.level -Levels $Levels
        if ($ok.state -ne "known") { [void]$reasons.Add($ok.reason) }
        elseif (-not $ok.value) { [void]$reasons.Add("the permission level " + $out.level + " is above this node's ceiling, " + $cap.level + " (" + $cap.from + "); it is refused, never lowered") }
    }

    $out.reasons = $reasons.ToArray()
    $out.allowed = [bool]($reasons.Count -eq 0)
    return [pscustomobject]$out
}
