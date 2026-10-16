# test/fixtures/merge/StandIns.ps1 - the stand-in gh and task ledger test/test-merge.ps1 runs horde merge
# against. NOTHING HERE REACHES GITHUB, THE FLEET'S LEDGER OR ANYONE'S MAIL: gh's answers come from a state
# file the suite wrote, and its merge is a real merge commit made in a bare repository the suite made in
# temp. The suite calls these functions in its own process, and, for the end-to-end part, through small
# scripts it writes beside each state file, which dot-source this file (test/test-merge.ps1, New-CliCase).
#
# THE GH STATE, gh-state.json: { origin; prs: { "<n>": { state; isDraft; mergeable; reviewDecision; title;
# mergeCommit; mergeableQueue; headRefOid; failMerge } }; calls: [ "<arguments joined by spaces>" ] }.
# mergeableQueue, when not empty, is answered first, one item per pr view. headRefOid, when set, is
# answered instead of the real head (a head that moved). failMerge makes pr merge refuse.
# THE LEDGER STATE, ledger-state.json: { tasks: [ ids ]; failMerged; calls: [ ... ] }.

. (Join-Path $PSScriptRoot "..\..\..\core\JsonText.ps1")

function Read-MergeStandInState {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($Path)))
}

function Write-MergeStandInState {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$State)
    [System.IO.File]::WriteAllText($Path, ($State | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-MergeStandInGit {
    # git in the suite's own bare repository; its output, or a throw.
    param([Parameter(Mandatory = $true)][string]$Repo, [Parameter(Mandatory = $true)][string[]]$Arguments)
    $o = & git -C $Repo @Arguments
    if ($LASTEXITCODE -ne 0) { throw ("stand-in git " + ($Arguments -join " ") + " failed: " + $LASTEXITCODE) }
    return ((@($o) -join "`n").Trim())
}

function Invoke-MergeStandInGh {
    # One gh call: { code; out; err }.
    param([Parameter(Mandatory = $true)][string]$StatePath, [string[]]$Arguments = @())
    $s = Read-MergeStandInState -Path $StatePath
    $s.calls = @(@($s.calls) + ($Arguments -join " "))
    $answer = { param([int]$Code, [string]$Out, [string]$Err) Write-MergeStandInState -Path $StatePath -State $s; return [pscustomobject]@{ code = $Code; out = $Out; err = $Err } }
    $a = @($Arguments)
    if ($a.Count -ge 3 -and $a[0] -ceq "repo" -and $a[1] -ceq "view") { return (& $answer 0 ("" + $s.origin + "`n") "") }
    if ($a.Count -lt 3 -or $a[0] -cne "pr") { return (& $answer 1 "" ("stand-in gh: not a call it knows: " + ($a -join " "))) }
    $n = "" + $a[2]
    $p = $s.prs.PSObject.Properties[$n]
    if ($null -eq $p) { return (& $answer 1 "" ("GraphQL: Could not resolve to a PullRequest with the number of " + $n + ".")) }
    $pr = $p.Value
    $prRef = "refs/pull/" + $n + "/head"
    if ($a[1] -ceq "view") {
        $mergeable = "" + $pr.mergeable
        if (@($pr.mergeableQueue).Count -gt 0) { $mergeable = "" + @($pr.mergeableQueue)[0]; $pr.mergeableQueue = @(@($pr.mergeableQueue) | Select-Object -Skip 1) }
        $head = "" + $pr.headRefOid
        if ($head -eq "") { $head = Invoke-MergeStandInGit -Repo $s.origin -Arguments @("rev-parse", $prRef) }
        $view = [ordered]@{ number = [int]$n; state = $pr.state; isDraft = $pr.isDraft; mergeable = $mergeable; reviewDecision = $pr.reviewDecision; headRefOid = $head; baseRefName = "main"; title = $pr.title; mergeCommit = $pr.mergeCommit }
        return (& $answer 0 (($view | ConvertTo-Json -Depth 5 -Compress) + "`n") "")
    }
    if ($a[1] -ceq "merge") {
        if ($a -ccontains "--squash" -or $a -ccontains "--rebase" -or $a -cnotcontains "--merge") { return (& $answer 1 "" "stand-in gh: only --merge is taken") }
        if ($pr.failMerge -eq $true) { return (& $answer 1 "" "stand-in gh: the merge was refused") }
        if ("" + $pr.state -cne "OPEN") { return (& $answer 1 "" ("Pull request #" + $n + " is not open")) }
        $head = Invoke-MergeStandInGit -Repo $s.origin -Arguments @("rev-parse", $prRef)
        $i = [array]::IndexOf($a, "--match-head-commit")
        if ($i -lt 0 -or $a[$i + 1] -cne $head) { return (& $answer 1 "" "stand-in gh: Head branch was modified. Review and try the merge again.") }
        $main = Invoke-MergeStandInGit -Repo $s.origin -Arguments @("rev-parse", "refs/heads/main")
        $tree = @((Invoke-MergeStandInGit -Repo $s.origin -Arguments @("merge-tree", "--write-tree", "--no-messages", $main, $head)) -split "`n")[0]
        $commit = Invoke-MergeStandInGit -Repo $s.origin -Arguments @("-c", "user.name=stand-in", "-c", "user.email=stand-in@localhost", "commit-tree", $tree, "-p", $main, "-p", $head, "-m", ("Merge pull request #" + $n))
        $null = Invoke-MergeStandInGit -Repo $s.origin -Arguments @("update-ref", "refs/heads/main", $commit)
        $pr.state = "MERGED"
        $pr.mergeCommit = [pscustomobject]@{ oid = $commit }
        return (& $answer 0 ("Merged pull request #" + $n + "`n") "")
    }
    return (& $answer 1 "" ("stand-in gh: not a call it knows: " + ($a -join " ")))
}

function Invoke-MergeStandInLedger {
    # One ledger call, its first argument the ledger script's path: { code; out; err }.
    param([Parameter(Mandatory = $true)][string]$StatePath, [string[]]$Arguments = @())
    $s = Read-MergeStandInState -Path $StatePath
    $a = @($Arguments | Select-Object -Skip 1)
    $s.calls = @(@($s.calls) + ($a -join " "))
    Write-MergeStandInState -Path $StatePath -State $s
    if ($a.Count -ge 2 -and $a[0] -ceq "show") {
        if (@($s.tasks) -ccontains $a[1]) { return [pscustomobject]@{ code = 0; out = ('{"task": "' + $a[1] + '", "event": "opened"}' + "`n"); err = "" } }
        return [pscustomobject]@{ code = 0; out = ""; err = "" }
    }
    if ($a.Count -ge 2 -and $a[0] -ceq "merged") {
        if ($s.failMerged -eq $true) { return [pscustomobject]@{ code = 1; out = ""; err = "stand-in ledger: the ledger file is locked" } }
        return [pscustomobject]@{ code = 0; out = ""; err = "" }
    }
    return [pscustomobject]@{ code = 2; out = ""; err = "stand-in ledger: not a verb it knows" }
}
