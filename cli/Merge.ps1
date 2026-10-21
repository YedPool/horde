# cli/Merge - `horde merge`: one pull request merged the fleet's way, every step in one command.
#
# WHY ONE COMMAND (fleet audit of 2026-10-16, findings 2, 4 and 10). Merging was five steps each session
# had to remember: the repo-wide guards on the combined head, gh pr merge --merge, the task ledger's
# merged event, telling the warchief, and a progress line. On 2026-10-14 PRs 278, 279 and 288 were
# merged without the guards and main went red on both until PR 292; on 2026-10-06 three merges were
# told to nobody, and the warchief told three lanes a fixed defect was still open. 7 of 12 lane-state
# files never mentioned the merged step, 9 of 12 never mentioned the guards. A step a command does
# cannot be forgotten.
#
# WHAT IT DOES, IN ORDER, and why each step is where it is:
#   1. The request is checked (Test-HordeMergeRequest) and the task is looked up in the ledger BEFORE
#      anything else: the ledger's own merged verb refuses an unknown task, and after the merge that
#      refusal would leave a merge with no event - the failure this command exists to end.
#   2. The pull request is read from GitHub: open, not a draft, mergeable, and no review missing where
#      the repository requires one (reviewDecision REVIEW_REQUIRED or CHANGES_REQUESTED). An answer of
#      UNKNOWN is GitHub still working it out; it is asked again a few times, then refused.
#   3. THE TREE THAT WILL EXIST AFTER THE MERGE is built in a cache repository of this command's own
#      (never the caller's working tree): the base branch and the PR head are fetched, and when the head
#      does not already contain the base, a throwaway merge commit is made with git merge-tree (CONTRIBUTING
#      15 rule 2: "mergeable" is not "green"). It is cloned, detached, into a fresh scratch folder whose
#      origin/<base> is the base as fetched, because test-host-names compares the lists with origin/main.
#   4. Every repo-wide guard listed in test\guards.txt runs there (CONTRIBUTING 15 rule 9), each in Windows
#      PowerShell 5.1 AND in PowerShell 7. The list is the checked tree's plus the base's, so a PR may add
#      a guard but not drop one. A guard passes only on exit 0 AND its
#      closing banner: a suite with no banner was NOT RUN (rule 7). On a failure the failing lines are
#      printed and nothing is merged. THE GUARDS RUN ARE THE PR'S OWN COPIES, as they stand in the merge
#      result: a PR that weakens a guard is checked by the weakened guard. That is the same trust every
#      suite run on a branch has; a review of the guard's diff, and CI on main, are what catch it.
#   5. The base is read again. If it moved while the guards ran, the new combination is built and
#      checked first; after $script:HordeMergeRounds rounds that each saw it move, the command refuses.
#   6. gh pr merge --merge, never squash or rebase, with --match-head-commit, so a head pushed after the
#      check is refused by GitHub itself. The base can still move in the seconds between the last read
#      and the merge (gh has no "match base" option), so the merge commit's first parent is read back
#      (gh api .../commits/<sha>): when it is not the base that was checked, the merge landed on a tree
#      nobody checked, and the command ends merged-unfinished and says so in every message.
#   7. The ledger's merged event, then the warchief and the analyst are told, then a progress line is
#      drafted. A failure of any of these comes AFTER a merge that happened: it is said loudly, with the
#      exact command to run by hand, and the command exits 1. It never reports success it did not have.
#
# THE TOOLS ARE A TABLE (New-HordeMergeTools; tests hand in their own, as test/test-analyst-tend.ps1 does):
#   Gh      param([string[]]$Arguments)                      -> { code; out; err }
#   Git     param([string[]]$Arguments)                      -> { code; out; err }
#   Guard   param([string]$Checkout, [string]$Suite, [string]$Shell)  -> { code; out; err }   Shell: "5.1" or "7"
#   Ledger  param([string[]]$Arguments)                      -> { code; out; err }, run as <program> <script> <arguments>
#   Tell    param([string]$Body)                             -> { ok; detail }   the warchief
#   Mail    param([string]$Text)                             -> { ok; detail }   the analyst
#   Wait    param([int]$Seconds)
#   Say     param([string]$Line)                             each line as it happens
#   LedgerLine  param([string[]]$Arguments)                  -> the exact command, for a person to paste
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "..\core\ModuleSettings.ps1")
. (Join-Path $PSScriptRoot "..\core\JsonText.ps1")
. (Join-Path $PSScriptRoot "..\core\ServiceHostPort.ps1")
. (Join-Path $PSScriptRoot "..\core\GuardList.ps1")

# THE SETTINGS of the module "merge", in <HORDE_HOME>\settings\merge.json. The ledger script has no
# default: it is the fleet's file, and where it lives is the person's to say - with none, every merge is
# refused before anything is merged, because a merge with no ledger event is what this command prevents.
$script:HordeMergeSettings = New-HordeModuleSettings -Module "merge" -Settings @(
    @{ name = "gh"; kind = "text"; min = 1; max = 260; default = "gh"
       what = "The gh program: a name on PATH or an absolute path. A .ps1 is run with this PowerShell." },
    @{ name = "git"; kind = "text"; min = 1; max = 260; default = "git"
       what = "The git program: a name on PATH or an absolute path." },
    @{ name = "guardShell"; kind = "text"; min = 1; max = 260; default = "powershell.exe"
       what = "The Windows PowerShell 5.1 the guards run in first; the gate runs suites in Windows PowerShell." },
    @{ name = "guardShell7"; kind = "folder"; default = ""
       what = "The absolute path of the PowerShell 7 the guards run in second. Empty: the MSI install under Program Files, never the Store copy that may be on the search path." },
    @{ name = "ledgerProgram"; kind = "text"; min = 1; max = 260; default = "python"
       what = "The program that runs the task ledger script. A .ps1 is run with this PowerShell." },
    @{ name = "ledgerScript"; kind = "folder"; default = ""
       what = "The absolute path of the fleet's task ledger script. Empty: every merge is refused." },
    @{ name = "workFolder"; kind = "folder"; default = ""
       what = "Where the cache and scratch checkouts live. Empty: horde\merge in local application data." }
)

# How many times the base may move under the guards before the command gives up (step 5), how many
# times an UNKNOWN mergeable is asked again and how long apart (step 2), and how long one program may run.
$script:HordeMergeRounds = 3
$script:HordeMergeUnknownTries = 4
$script:HordeMergeUnknownWaitSeconds = 3

$script:HordeMergeProgramSeconds = 900
# The most failing lines of a guard that are printed; the rest are counted.
$script:HordeMergeFailLines = 40

# THE REQUEST'S SHAPES. A lane is a hub label (schema/link-verbs.v1, label), so the warchief's messenger
# can carry it as the sender's label; who a task waits on is the ledger's own list (task.py, its help).
$script:HordeMergePrPattern = '\A([A-Za-z0-9][A-Za-z0-9-]{0,38})/([A-Za-z0-9_.-]{1,100})#([1-9][0-9]{0,6})\z'
$script:HordeMergeTaskPattern = '\AT-[0-9]{4,6}\z'
$script:HordeMergeLanePattern = '\A[A-Z]{1,2}([1-9][0-9]{0,3})?\z'
$script:HordeMergeOnPattern = '\A(founder|M|device|service|lane:[A-Z]{1,2}([1-9][0-9]{0,3})?)\z'
$script:HordeMergeReasonPattern = '\A[\x20-\x7E]{1,300}\z'
$script:HordeMergeRefPattern = '\A(?!-)(?!.*\.\.)[A-Za-z0-9._/-]{1,200}\z'
$script:HordeMergeShaPattern = '\A[0-9a-f]{40}\z'

function Test-HordeMergeRequest {
    # PURE. { ok; reason; owner; repo; number; pr; task; state; by; on; reason } for what was typed.
    # Every refusal names the value and the shape it must have.
    param([string]$Pr, [string]$Task, [string]$State, [string]$By, [string]$On = "", [string]$Reason = "")
    $no = { param([string]$Why) return [pscustomobject]@{ ok = $false; why = $Why } }
    $m = [regex]::Match($Pr, $script:HordeMergePrPattern)
    if (-not $m.Success -or $m.Groups[2].Value -ceq "." -or $m.Groups[2].Value -ceq "..") { return (& $no ("'" + $Pr + "' is not a pull request: OWNER/REPO#N, such as YedPool/horde#305")) }
    if ($Task -cnotmatch $script:HordeMergeTaskPattern) { return (& $no ("'" + $Task + "' is not a task id: T- and four or more digits, such as T-0247")) }
    if (@("done", "waiting", "progress") -cnotcontains $State) { return (& $no ("'" + $State + "' is not a state a merge leaves a task in: done, waiting or progress")) }
    if ($By -cnotmatch $script:HordeMergeLanePattern) { return (& $no ("'" + $By + "' is not a lane: one or two capital letters, then digits if any, such as F or C1")) }
    if ($On -ne "" -and $On -cnotmatch $script:HordeMergeOnPattern) { return (& $no ("'" + $On + "' is not who a task waits on: founder, M, lane:X, device or service")) }
    if ($Reason -ne "" -and $Reason -cnotmatch $script:HordeMergeReasonPattern) { return (& $no "the reason is one line of 1 to 300 plain ASCII characters") }
    if ($State -ceq "waiting" -and $On -eq "") { return (& $no "-State waiting needs -On: who or what the task waits on (founder, M, lane:X, device or service)") }
    if ($State -ceq "progress" -and $Reason -eq "") { return (& $no "-State progress needs -Reason: what is left of the task after this merge") }
    return [pscustomobject]@{ ok = $true; why = ""; owner = $m.Groups[1].Value; repo = $m.Groups[2].Value; number = [int]$m.Groups[3].Value
        pr = $Pr; task = $Task; state = $State; by = $By; on = $On; reason = $Reason }
}

function Get-HordeMergeLedgerArguments {
    # PURE. The ledger's merged event for a checked request, as task.py takes it.
    param([Parameter(Mandatory = $true)]$Request)
    $a = New-Object System.Collections.ArrayList
    foreach ($w in @("merged", $Request.task, "--pr", $Request.pr, "--by", $Request.by, "--state", $Request.state)) { [void]$a.Add($w) }
    if ("" + $Request.on -ne "") { [void]$a.Add("--on"); [void]$a.Add($Request.on) }
    # --reason=<text> as ONE word: argparse reads a separate word that starts with "-" as a flag, so
    # "--reason -docs left" was refused by the ledger after the merge (review of PR 320).
    if ("" + $Request.reason -ne "") { [void]$a.Add("--reason=" + $Request.reason) }
    return [string[]]$a.ToArray()
}

function ConvertTo-HordeMergeQuoted {
    # One word as PowerShell reads it back unchanged: in single quotes, a single quote doubled. Every
    # word is quoted: a PR reference holds '#', which starts a comment when it is bare.
    param([AllowEmptyString()][string]$Text)
    return ("'" + $Text.Replace("'", "''") + "'")
}

function Format-HordeMergeLedgerLine {
    # PURE. The exact command a person runs when the ledger step failed after the merge.
    param([Parameter(Mandatory = $true)][string]$Program, [Parameter(Mandatory = $true)][string]$Script, [Parameter(Mandatory = $true)][string[]]$Arguments)
    $words = @($Program, $Script) + @($Arguments)
    return ("& " + (@($words | ForEach-Object { ConvertTo-HordeMergeQuoted -Text $_ }) -join " "))
}

function Format-HordeMergeMessage {
    # PURE. What the warchief and the analyst are told: fixed words around values that each passed a
    # pattern (the request) or are shas. Nothing the PR's author wrote - its title or body - is in it,
    # so nothing a remote author shapes is put before an AI session as Horde's own words.
    # -Landed is "" when the merge's first parent is the checked base, else the words that say it is not.
    param([Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)][string]$MergeSha, [Parameter(Mandatory = $true)]$Check, [string]$Landed = "")
    $state = "Task " + $Request.task + " is now " + $Request.state
    if ("" + $Request.on -ne "") { $state += ", waiting on " + $Request.on }
    if ("" + $Request.reason -ne "") { $state += "; left: " + $Request.reason }
    $checked = "Guards green on " + $Check.base.Substring(0, 8) + " + " + $Check.head.Substring(0, 8)
    if ($Check.merged) { $checked += " (checked as their merge, " + $Check.commit.Substring(0, 8) + ")" }
    if ($Landed -ne "") { $checked = "NOT CHECKED: " + $Landed + ". The guards were green on " + $Check.base.Substring(0, 8) + " + " + $Check.head.Substring(0, 8) + " only" }
    return ("HORDE MERGE: " + $Request.by + " merged " + $Request.pr + " as " + $MergeSha + ".`n" + $state + ".`n" + $checked + ".")
}

function Format-HordeMergeProgress {
    # PURE. The one-line progress draft. The title is the PR author's text: it is cut to plain ASCII and
    # 100 characters, and this line is printed for the session to read, never sent anywhere.
    param([Parameter(Mandatory = $true)]$Request, [AllowEmptyString()][string]$Title)
    $t = ($Title -replace '[^\x20-\x7E]', '?').Trim()
    if ($t.Length -gt 100) { $t = $t.Substring(0, 97) + "..." }
    $line = "progress draft: " + $Request.by + " merged " + $Request.pr
    if ($t -ne "") { $line += " - " + $t }
    $line += " (" + $Request.task + ", now " + $Request.state
    if ("" + $Request.on -ne "") { $line += " on " + $Request.on }
    return ($line + ")")
}

function Read-HordeMergeGuardResult {
    # PURE. { ok; lines } for a guard's run. ok only on exit 0 AND a closing banner that is not a
    # failure's (CONTRIBUTING 15 rule 7: no banner is NOT RUN). lines are the ones that say why it failed.
    param([Parameter(Mandatory = $true)]$Run)
    $all = @(("" + $Run.out + "`n" + $Run.err) -split "\r?\n")
    $banner = @($all | Where-Object { $_ -cmatch '\A==== .+ ====\s*\z' })
    $failedBanner = @($banner | Where-Object { $_ -cmatch 'FAILURE' })
    $ok = ($Run.code -eq 0 -and $banner.Count -gt 0 -and $failedBanner.Count -eq 0)
    if ($ok) { return [pscustomobject]@{ ok = $true; lines = @() } }
    $bad = @($all | Where-Object { $_ -cmatch '\[(FAIL|ERROR)\]' })
    if ($bad.Count -eq 0) { $bad = @($all | Where-Object { $_.Trim() -ne "" } | Select-Object -Last 10) }
    $why = "exit " + $Run.code
    if ($banner.Count -eq 0) { $why += ", and no closing banner: it did not run to its end, so it counts as NOT RUN" }
    $shown = @($bad | Select-Object -First $script:HordeMergeFailLines)
    if ($bad.Count -gt $shown.Count) { $shown += ("... and " + ($bad.Count - $shown.Count) + " more") }
    return [pscustomobject]@{ ok = $false; lines = @(@($why) + $shown) }
}

function Invoke-HordeMergeTool {
    # Call one tool of the table; a tool that throws answers as a failed program, so no step is skipped
    # by an exception nobody reads.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Name, [object[]]$With = @())
    try { return (& $Tools[$Name] @With) }
    catch { return [pscustomobject]@{ code = -1; out = ""; err = ("the " + $Name + " tool failed: " + $_.Exception.Message); ok = $false; detail = ("the " + $Name + " tool failed: " + $_.Exception.Message) } }
}

function Get-HordeMergeFirstLine {
    param([AllowEmptyString()][string]$Text)
    $l = @(("" + $Text) -split "\r?\n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
    if ($l.Count -eq 0) { return "(it said nothing)" }
    return $l[0].Trim()
}

function Read-HordeMergePr {
    # { ok; why; pr } from gh pr view: the fields this command decides on. UNKNOWN mergeable is asked
    # again (header, step 2).
    param([Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)]$Tools)
    $repo = $Request.owner + "/" + $Request.repo
    $pr = $null
    for ($try = 1; $try -le $script:HordeMergeUnknownTries; $try++) {
        $r = Invoke-HordeMergeTool -Tools $Tools -Name "Gh" -With @(, [string[]]@("pr", "view", ("" + $Request.number), "--repo", $repo, "--json", "number,state,isDraft,mergeable,reviewDecision,headRefOid,baseRefName,title"))
        if ($r.code -ne 0) { return [pscustomobject]@{ ok = $false; why = ("gh could not read " + $Request.pr + ": " + (Get-HordeMergeFirstLine $r.err)) } }
        try { $pr = ConvertFrom-HordeJson -Text $r.out } catch { return [pscustomobject]@{ ok = $false; why = ("gh's answer about " + $Request.pr + " is not JSON") } }
        if ("" + $pr.mergeable -cne "UNKNOWN") { break }
        if ($try -lt $script:HordeMergeUnknownTries) { & $Tools["Wait"] $script:HordeMergeUnknownWaitSeconds }
    }
    if ("" + $pr.state -cne "OPEN") { return [pscustomobject]@{ ok = $false; why = ($Request.pr + " is not open: GitHub says " + $pr.state) } }
    if ($pr.isDraft -eq $true) { return [pscustomobject]@{ ok = $false; why = ($Request.pr + " is a draft; mark it ready first") } }
    if ("" + $pr.mergeable -ceq "CONFLICTING") { return [pscustomobject]@{ ok = $false; why = ($Request.pr + " is not mergeable: it conflicts with its base") } }
    if ("" + $pr.mergeable -cne "MERGEABLE") { return [pscustomobject]@{ ok = $false; why = ($Request.pr + " is not mergeable yet: GitHub still says " + $pr.mergeable + " after " + $script:HordeMergeUnknownTries + " asks; run again in a minute") } }
    if (@("REVIEW_REQUIRED", "CHANGES_REQUESTED") -ccontains ("" + $pr.reviewDecision)) { return [pscustomobject]@{ ok = $false; why = ($Request.pr + " is missing a review its repository requires: GitHub says " + $pr.reviewDecision) } }
    if ("" + $pr.headRefOid -cnotmatch $script:HordeMergeShaPattern) { return [pscustomobject]@{ ok = $false; why = ("gh gave no head commit for " + $Request.pr) } }
    if ("" + $pr.baseRefName -cnotmatch $script:HordeMergeRefPattern) { return [pscustomobject]@{ ok = $false; why = ("gh gave a base branch for " + $Request.pr + " that is not a plain branch name") } }
    return [pscustomobject]@{ ok = $true; why = ""; pr = $pr }
}

function Invoke-HordeMergeGit {
    # Run git; { ok; out; why }. -What names the step for the reason.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string[]]$Arguments, [Parameter(Mandatory = $true)][string]$What)
    $r = Invoke-HordeMergeTool -Tools $Tools -Name "Git" -With @(, $Arguments)
    if ($r.code -ne 0) { return [pscustomobject]@{ ok = $false; code = $r.code; out = ("" + $r.out); why = ($What + " failed: " + (Get-HordeMergeFirstLine ("" + $r.err + "`n" + $r.out))) } }
    return [pscustomobject]@{ ok = $true; code = 0; out = ("" + $r.out).Trim(); why = "" }
}

function Remove-HordeMergeFolder {
    # Delete a scratch checkout of this command's own. git writes some files read-only, which a plain
    # delete refuses, so their attributes are cleared first. A failure is said, never thrown: the merge
    # does not depend on it.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Tools)
    if (-not [System.IO.Directory]::Exists($Path)) { return }
    try {
        foreach ($f in [System.IO.Directory]::GetFiles($Path, "*", [System.IO.SearchOption]::AllDirectories)) { [System.IO.File]::SetAttributes($f, [System.IO.FileAttributes]::Normal) }
        [System.IO.Directory]::Delete($Path, $true)
    } catch { & $Tools["Say"] ("the scratch checkout " + $Path + " could not be removed: " + $_.Exception.Message) }
}

function Invoke-HordeMergeCheck {
    # One round of steps 3 and 4: fetch, build the tree that will exist after the merge, run the guards
    # on it. { ok; why; lines; base; head; commit; merged }. -Url is where git fetches from.
    param([Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)]$Pr, [Parameter(Mandatory = $true)][string]$Url, [Parameter(Mandatory = $true)][string]$WorkFolder, [Parameter(Mandatory = $true)]$Tools)
    $base = "" + $Pr.baseRefName
    $cache = [System.IO.Path]::Combine($WorkFolder, "repos", $Request.owner, ($Request.repo + ".git"))
    $prRef = "refs/horde-merge/pr-" + $Request.number
    $no = { param([string]$Why, $Lines = @()) return [pscustomobject]@{ ok = $false; why = $Why; lines = @($Lines) } }
    if (-not [System.IO.Directory]::Exists($cache)) {
        $r = Invoke-HordeMergeGit -Tools $Tools -What "making the cache repository" -Arguments @("init", "--bare", "--quiet", $cache)
        if (-not $r.ok) { return (& $no $r.why) }
    }
    $r = Invoke-HordeMergeGit -Tools $Tools -What "fetching the base and the PR head" -Arguments @("-C", $cache, "fetch", "--no-tags", "--quiet", $Url, ("+refs/heads/" + $base + ":refs/heads/" + $base), ("+refs/pull/" + $Request.number + "/head:" + $prRef))
    if (-not $r.ok) { return (& $no $r.why) }
    $r = Invoke-HordeMergeGit -Tools $Tools -What "pointing the cache at the base" -Arguments @("-C", $cache, "symbolic-ref", "HEAD", ("refs/heads/" + $base))
    if (-not $r.ok) { return (& $no $r.why) }
    $b = Invoke-HordeMergeGit -Tools $Tools -What "reading the base" -Arguments @("-C", $cache, "rev-parse", ("refs/heads/" + $base))
    $h = Invoke-HordeMergeGit -Tools $Tools -What "reading the PR head" -Arguments @("-C", $cache, "rev-parse", $prRef)
    if (-not $b.ok) { return (& $no $b.why) }
    if (-not $h.ok) { return (& $no $h.why) }
    $baseSha = $b.out; $headSha = $h.out
    if ($headSha -cne ("" + $Pr.headRefOid)) { return (& $no ("the PR head moved while it was read (GitHub said " + ("" + $Pr.headRefOid).Substring(0, 8) + ", the fetch got " + $headSha.Substring(0, 8) + "); run again")) }

    # DOES THE HEAD ALREADY CONTAIN THE BASE? Then the merge's tree is the head's. If not, the tree that is
    # checked is the merge result, made here as a throwaway commit (header, step 3).
    $contains = Invoke-HordeMergeTool -Tools $Tools -Name "Git" -With @(, [string[]]@("-C", $cache, "merge-base", "--is-ancestor", $baseSha, $headSha))
    $merged = $false
    $commit = $headSha
    if ($contains.code -eq 0) { & $Tools["Say"] ("the PR head " + $headSha.Substring(0, 8) + " already contains " + $base + " " + $baseSha.Substring(0, 8) + ": the head is what is checked") }
    elseif ($contains.code -eq 1) {
        $t = Invoke-HordeMergeTool -Tools $Tools -Name "Git" -With @(, [string[]]@("-C", $cache, "merge-tree", "--write-tree", "--no-messages", $baseSha, $headSha))
        if ($t.code -eq 1) { return (& $no ("the PR head does not merge cleanly with " + $base + " " + $baseSha.Substring(0, 8) + ": update the branch first")) }
        if ($t.code -ne 0) { return (& $no ("building the merge result failed: " + (Get-HordeMergeFirstLine ("" + $t.err)))) }
        $tree = (@(("" + $t.out) -split "\r?\n")[0]).Trim()
        $c = Invoke-HordeMergeGit -Tools $Tools -What "making the throwaway merge commit" -Arguments @("-C", $cache, "-c", "user.name=horde merge", "-c", "user.email=horde-merge@localhost", "commit-tree", $tree, "-p", $baseSha, "-p", $headSha, "-m", ("horde merge: the check of " + $Request.pr))
        if (-not $c.ok) { return (& $no $c.why) }
        $commit = $c.out
        $merged = $true
        & $Tools["Say"] ("the PR head " + $headSha.Substring(0, 8) + " does NOT contain " + $base + " " + $baseSha.Substring(0, 8) + ": what is checked is their merge " + $commit.Substring(0, 8) + ", the tree that will exist after the merge")
    }
    else { return (& $no ("asking git whether the head contains the base failed: " + (Get-HordeMergeFirstLine ("" + $contains.err)))) }

    # A SHORT NAME, because the checked tree's own paths are long: Horde's longest is 136 characters
    # (measured 2026-10-16), and a checkout under a 140-character folder failed with "Filename too long".
    # core.longpaths lets git write such a path; a guard that cannot read one then fails red, never green.
    # A run killed before its finally left its folder: anything under runs is a past run's, and this command
    # holds the machine's merge lock, so no other run is using one.
    $runs = [System.IO.Path]::Combine($WorkFolder, "runs")
    if ([System.IO.Directory]::Exists($runs)) { foreach ($old in [System.IO.Directory]::GetDirectories($runs)) { Remove-HordeMergeFolder -Path $old -Tools $Tools } }
    $scratch = [System.IO.Path]::Combine($runs, ("" + $Request.number + "-" + [guid]::NewGuid().ToString("N").Substring(0, 6)))
    try {
        $r = Invoke-HordeMergeGit -Tools $Tools -What "cloning the scratch checkout" -Arguments @("-c", "core.longpaths=true", "clone", "--shared", "--no-checkout", "--quiet", $cache, $scratch)
        if (-not $r.ok) { return (& $no $r.why) }
        $r = Invoke-HordeMergeGit -Tools $Tools -What "checking out the tree to check" -Arguments @("-C", $scratch, "-c", "core.longpaths=true", "checkout", "--detach", "--quiet", $commit)
        if (-not $r.ok) { return (& $no $r.why) }
        # THE GUARDS ARE THE REPOSITORY'S OWN LIST (test\guards.txt): the checked tree's, plus every guard
        # the base's list has, so a PR cannot drop a guard by editing the list. No list anywhere: refused.
        $listFile = [System.IO.Path]::Combine($scratch, (Get-HordeGuardListPath))
        $treeText = ""
        if ([System.IO.File]::Exists($listFile)) { $treeText = [System.IO.File]::ReadAllText($listFile) }
        $listGit = (Get-HordeGuardListPath).Replace("\", "/")
        $baseHas = Invoke-HordeMergeGit -Tools $Tools -What "asking whether the base has a guard list" -Arguments @("-C", $cache, "ls-tree", "--name-only", $baseSha, "--", $listGit)
        if (-not $baseHas.ok) { return (& $no $baseHas.why) }
        $baseGuards = $null
        if ($baseHas.out -ne "") {
            $baseText = Invoke-HordeMergeGit -Tools $Tools -What "reading the base's guard list" -Arguments @("-C", $cache, "show", ($baseSha + ":" + $listGit))
            if (-not $baseText.ok) { return (& $no $baseText.why) }
            $baseRead = Read-HordeGuardList -Text $baseText.out
            if (-not $baseRead.ok) { return (& $no ("the base's guard list is unusable: " + $baseRead.why)) }
            $baseGuards = $baseRead.guards
        }
        $treeGuards = @()
        if ($treeText -ne "") {
            $treeRead = Read-HordeGuardList -Text $treeText
            if (-not $treeRead.ok) { return (& $no ("the checked tree's guard list is unusable: " + $treeRead.why)) }
            $treeGuards = $treeRead.guards
        }
        $guards = @(Join-HordeGuardLists -Tree $treeGuards -Base $baseGuards)
        if ($guards.Count -eq 0) { return (& $no ("neither the checked tree nor " + $base + " has " + (Get-HordeGuardListPath) + ", so nothing can say it is green")) }
        & $Tools["Say"] ("the guards, from " + (Get-HordeGuardListPath) + ": " + ($guards -join ", ") + " - each in " + (((Get-HordeGuardShells) | ForEach-Object { $_.label }) -join " and "))
        foreach ($g in $guards) {
            if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($scratch, $g))) { return (& $no ("the guard " + $g + " is not in the checked tree, so nothing can say it is green")) }
            foreach ($sh in (Get-HordeGuardShells)) {
                & $Tools["Say"] ("running " + $g + " on " + $commit.Substring(0, 8) + " in " + $sh.label)
                $run = Invoke-HordeMergeTool -Tools $Tools -Name "Guard" -With @($scratch, $g, $sh.key)
                $read = Read-HordeMergeGuardResult -Run $run
                if (-not $read.ok) { return (& $no ("the guard " + $g + " is red on " + $commit.Substring(0, 8) + " in " + $sh.label + "; nothing was merged") $read.lines) }
                & $Tools["Say"] ($g + " is green in " + $sh.label)
            }
        }
    } finally {
        Remove-HordeMergeFolder -Path $scratch -Tools $Tools
        # The PR's ref is dropped once checked, so the cache does not keep every PR it ever merged.
        $null = Invoke-HordeMergeTool -Tools $Tools -Name "Git" -With @(, [string[]]@("-C", $cache, "update-ref", "-d", $prRef))
    }
    return [pscustomobject]@{ ok = $true; why = ""; lines = @(); base = $baseSha; head = $headSha; commit = $commit; merged = $merged }
}

function Invoke-HordeMerge {
    # The whole command (header). { outcome; why; mergeSha; problems }: outcome refused (nothing merged),
    # merged (every step done) or merged-unfinished (merged; problems says what is left to do by hand).
    param([Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$WorkFolder)
    $refuse = { param([string]$Why) return [pscustomobject]@{ outcome = "refused"; why = $Why; mergeSha = ""; problems = @() } }
    $say = $Tools["Say"]

    # 1. THE TASK, BEFORE ANYTHING (header).
    $shown = Invoke-HordeMergeTool -Tools $Tools -Name "Ledger" -With @(, [string[]]@("show", $Request.task))
    if ($shown.code -ne 0) { return (& $refuse ("the task ledger could not be read: " + (Get-HordeMergeFirstLine ("" + $shown.err + "`n" + $shown.out)))) }
    $taskSeen = $false
    foreach ($l in @(("" + $shown.out) -split "\r?\n")) {
        if ($l.Trim() -eq "") { continue }
        try { $e = ConvertFrom-HordeJson -Text $l } catch { continue }
        if ($null -ne $e -and $null -ne $e.PSObject.Properties["task"] -and "" + $e.task -ceq $Request.task) { $taskSeen = $true; break }
    }
    if (-not $taskSeen) { return (& $refuse ("the task ledger has no task " + $Request.task + "; open it first, or name the right one")) }

    # 2. THE PULL REQUEST.
    $read = Read-HordeMergePr -Request $Request -Tools $Tools
    if (-not $read.ok) { return (& $refuse $read.why) }
    $pr = $read.pr
    $repo = $Request.owner + "/" + $Request.repo
    $u = Invoke-HordeMergeTool -Tools $Tools -Name "Gh" -With @(, [string[]]@("repo", "view", $repo, "--json", "url", "--jq", ".url"))
    $url = ("" + $u.out).Trim()
    if ($u.code -ne 0 -or $url -eq "") { return (& $refuse ("gh could not say where " + $repo + " is: " + (Get-HordeMergeFirstLine ("" + $u.err)))) }

    # 3 TO 5. CHECK, AND AGAIN WHILE THE BASE MOVES.
    $check = $null
    $round = 0
    while ($true) {
        $round++
        $check = Invoke-HordeMergeCheck -Request $Request -Pr $pr -Url $url -WorkFolder $WorkFolder -Tools $Tools
        if (-not $check.ok) {
            foreach ($l in @($check.lines)) { & $say ("    " + $l) }
            return (& $refuse $check.why)
        }
        $now = Invoke-HordeMergeTool -Tools $Tools -Name "Git" -With @(, [string[]]@("ls-remote", $url, ("refs/heads/" + $pr.baseRefName)))
        $nowSha = (@(("" + $now.out).Trim() -split "\s+")[0])
        if ($now.code -ne 0 -or $nowSha -cnotmatch $script:HordeMergeShaPattern) { return (& $refuse ("the base could not be read again after the guards: " + (Get-HordeMergeFirstLine ("" + $now.err)))) }
        if ($nowSha -ceq $check.base) { break }
        if ($round -ge $script:HordeMergeRounds) { return (& $refuse ($pr.baseRefName + " moved under the guards " + $round + " times in a row; nothing was merged, run again when it is quieter")) }
        & $say ($pr.baseRefName + " moved from " + $check.base.Substring(0, 8) + " to " + $nowSha.Substring(0, 8) + " while the guards ran: checking the new combination before merging")
    }

    # 6. THE MERGE.
    & $say ("merging " + $Request.pr + " with a merge commit")
    $m = Invoke-HordeMergeTool -Tools $Tools -Name "Gh" -With @(, [string[]]@("pr", "merge", ("" + $Request.number), "--repo", $repo, "--merge", "--match-head-commit", $check.head))
    $after = $null
    for ($try = 1; $try -le $script:HordeMergeUnknownTries; $try++) {
        $v = Invoke-HordeMergeTool -Tools $Tools -Name "Gh" -With @(, [string[]]@("pr", "view", ("" + $Request.number), "--repo", $repo, "--json", "state,mergeCommit"))
        if ($v.code -eq 0) { try { $after = ConvertFrom-HordeJson -Text $v.out } catch { $after = $null } }
        if ($null -ne $after -and "" + $after.state -ceq "MERGED") { break }
        # Asked again only when gh said it merged: a refused merge is not waited on.
        if ($m.code -ne 0) { break }
        if ($try -lt $script:HordeMergeUnknownTries) { & $Tools["Wait"] $script:HordeMergeUnknownWaitSeconds }
    }
    $isMerged = ($null -ne $after -and "" + $after.state -ceq "MERGED")
    if ($isMerged -and $m.code -ne 0) { & $say ("gh answered with an error, but GitHub shows " + $Request.pr + " MERGED: " + (Get-HordeMergeFirstLine ("" + $m.err))) }
    if (-not $isMerged -and $m.code -ne 0) { return (& $refuse ("gh did not merge " + $Request.pr + ": " + (Get-HordeMergeFirstLine ("" + $m.err + "`n" + $m.out)))) }
    if (-not $isMerged) {
        # gh said it merged and GitHub does not show it: nothing after this can be said truthfully.
        return [pscustomobject]@{ outcome = "merged-unfinished"; why = ("gh said it merged " + $Request.pr + ", but GitHub does not show it MERGED; look at it by hand. The ledger was NOT written and nobody was told"); mergeSha = ""; problems = @("look at the PR by hand") }
    }
    $mergeSha = ""
    if ($null -ne $after.PSObject.Properties["mergeCommit"] -and $null -ne $after.mergeCommit) { $mergeSha = "" + $after.mergeCommit.oid }
    if ($mergeSha -cnotmatch $script:HordeMergeShaPattern) { $mergeSha = "(GitHub gave no merge commit)" }
    & $say ("MERGED " + $Request.pr + " as " + $mergeSha)

    # WHERE DID IT LAND (header, step 6)? The merge commit's first parent must be the base the guards
    # checked; anything else - or no answer - means main now holds a tree nobody checked.
    $landed = ""
    if ($mergeSha -cmatch $script:HordeMergeShaPattern) {
        $pa = Invoke-HordeMergeTool -Tools $Tools -Name "Gh" -With @(, [string[]]@("api", ("repos/" + $repo + "/commits/" + $mergeSha), "--jq", ".parents[].sha"))
        $first = (@(("" + $pa.out).Trim() -split "\s+")[0])
        if ($pa.code -ne 0 -or $first -cnotmatch $script:HordeMergeShaPattern) { $landed = "the merge commit's parents could not be read, so where it landed is unknown" }
        elseif ($first -cne $check.base) { $landed = "the merge landed on " + $pr.baseRefName + " " + $first.Substring(0, 8) + ", which moved after the check" }
    } else { $landed = "GitHub gave no merge commit, so where it landed is unknown" }

    # 7. THE LEDGER, THE TELLS, THE DRAFT. Each failure is said and kept; none undoes the merge.
    $problems = New-Object System.Collections.ArrayList
    if ($landed -ne "") {
        & $say ("THE MERGE IS ON A TREE THE GUARDS DID NOT CHECK: " + $landed + "; run the guards on " + $pr.baseRefName + " now")
        [void]$problems.Add($landed + "; run the guards on " + $pr.baseRefName + " now")
    }
    $ledgerArgs = Get-HordeMergeLedgerArguments -Request $Request
    $lr = Invoke-HordeMergeTool -Tools $Tools -Name "Ledger" -With @(, $ledgerArgs)
    if ($lr.code -eq 0) { & $say ("ledger: " + $Request.task + " recorded as merged, now " + $Request.state) }
    else {
        & $say ("THE MERGE HAPPENED, BUT THE LEDGER WAS NOT WRITTEN: " + (Get-HordeMergeFirstLine ("" + $lr.err + "`n" + $lr.out)))
        $line = & $Tools["LedgerLine"] $ledgerArgs
        & $say ("run this by hand: " + $line)
        [void]$problems.Add("the ledger event was not written; run: " + $line)
    }
    $message = Format-HordeMergeMessage -Request $Request -MergeSha $mergeSha -Check $check -Landed $landed
    $t = Invoke-HordeMergeTool -Tools $Tools -Name "Tell" -With @($message)
    if ($t.ok -eq $true) { & $say "told the warchief" }
    else { & $say ("COULD NOT TELL THE WARCHIEF: " + $t.detail); [void]$problems.Add("the warchief was not told: send the warchief the message below") }
    $a = Invoke-HordeMergeTool -Tools $Tools -Name "Mail" -With @($message)
    if ($a.ok -eq $true) { & $say ("mailed the analyst: " + $a.detail) }
    else { & $say ("COULD NOT MAIL THE ANALYST: " + $a.detail); [void]$problems.Add("the analyst was not mailed: horde analyst mail -Text with the message below") }
    if ($problems.Count -gt 0) { foreach ($l in @($message -split "`n")) { & $say ("    " + $l) } }
    & $say (Format-HordeMergeProgress -Request $Request -Title ("" + $pr.title))
    if ($problems.Count -gt 0) { return [pscustomobject]@{ outcome = "merged-unfinished"; why = ("merged " + $Request.pr + " as " + $mergeSha + ", but " + ($problems -join "; ")); mergeSha = $mergeSha; problems = @($problems) } }
    return [pscustomobject]@{ outcome = "merged"; why = ""; mergeSha = $mergeSha; problems = @() }
}

function Test-HordeMergeShellScript {
    # PURE. Is -Program a batch file (run through cmd, which re-reads its arguments)?
    param([AllowEmptyString()][string]$Program)
    return [bool]($Program.Trim().TrimEnd('"') -match '\.(cmd|bat)\z')
}

function Get-HordeMergeShell {
    # The PowerShell this process runs in, for a .ps1 given as a program.
    return [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
}

function Invoke-HordeMergeProgram {
    # Run one program to its end: { code; out; err }; code -1 when it could not start or ran past
    # -Seconds (then it is stopped, with its children). A .ps1 is run with this PowerShell. Its input is
    # closed and gh and git are told never to prompt, so nothing waits on a person who is not there.
    # PSModulePath is left out of its environment: a Windows PowerShell started from PowerShell 7 or from
    # Git Bash with theirs could not load its own modules (measured 2026-10-16: test-mutation-specs failed
    # with 'Import-PowerShellDataFile' not recognized when started from Git Bash).
    param([Parameter(Mandatory = $true)][string]$Program, [string[]]$Arguments = @(), [string]$Directory = "", [int]$Seconds = $script:HordeMergeProgramSeconds, [hashtable]$Environment = @{})
    # NEVER A .cmd OR .bat: Windows runs one through cmd, which reads the argument line again with its
    # own rules (& | < > ^ %), so a reason typed for the ledger could become a command. Name the program.
    if (Test-HordeMergeShellScript -Program $Program) { return [pscustomobject]@{ code = -1; out = ""; err = ($Program + " is a .cmd or .bat, which cmd would run and re-read; name the program itself") } }
    $file = $Program
    $words = @($Arguments)
    if ($Program -match '\.ps1\z') { $file = Get-HordeMergeShell; $words = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $Program) + $words }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $file
    $psi.Arguments = (@($words | ForEach-Object { ConvertTo-HordeServiceArgument -Text $_ }) -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $psi.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    if ($Directory -ne "") { $psi.WorkingDirectory = $Directory }
    if ($psi.EnvironmentVariables.ContainsKey("PSModulePath")) { $psi.EnvironmentVariables.Remove("PSModulePath") }
    # -Environment is set after the drop, so a caller can give a child its own PSModulePath.
    foreach ($k in @($Environment.Keys)) { $psi.EnvironmentVariables[[string]$k] = "" + $Environment[$k] }
    $psi.EnvironmentVariables["GH_PROMPT_DISABLED"] = "1"
    $psi.EnvironmentVariables["GIT_TERMINAL_PROMPT"] = "0"
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return [pscustomobject]@{ code = -1; out = ""; err = ("could not start " + $Program + ": " + $_.Exception.Message) } }
    try {
        $p.StandardInput.Close()
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($Seconds * 1000)) {
            try { $null = & taskkill.exe /T /F /PID $p.Id } catch { }
            $global:LASTEXITCODE = 0
            return [pscustomobject]@{ code = -1; out = ""; err = ($Program + " ran past " + $Seconds + " s and was stopped") }
        }
        $p.WaitForExit()
        return [pscustomobject]@{ code = $p.ExitCode; out = $outTask.Result; err = $errTask.Result }
    } finally { $p.Dispose() }
}

function Get-HordeMergeWorkFolder {
    # The setting, or horde\merge under the local application data folder.
    param([Parameter(Mandatory = $true)]$Values)
    if ("" + $Values.workFolder -ne "") { return ("" + $Values.workFolder) }
    $local = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ("" + $local -eq "") { throw "there is no local application data folder; set workFolder in the merge settings" }
    return [System.IO.Path]::Combine($local, "horde", "merge")
}

function New-HordeMergeTools {
    # The real programs, from the settings' values. Tell and Mail are the caller's (cli/commands/merge.ps1),
    # because the messenger and the analyst's mail are loaded in the command's own scope.
    # THE BLOCKS ARE CLOSURES, AND A CLOSURE RUNS IN A MODULE OF ITS OWN that sees global functions only, not
    # these, which a command dot-sources in its own scope. So each block holds the functions it calls as
    # values ($runProgram, $formatLine): a function's own block runs where it was defined.
    param([Parameter(Mandatory = $true)]$Values, [Parameter(Mandatory = $true)][scriptblock]$Tell, [Parameter(Mandatory = $true)][scriptblock]$Mail, $MachinePsModulePath = $null)
    $gh = "" + $Values.gh; $git = "" + $Values.git; $shell = "" + $Values.guardShell
    $shell7 = Get-HordeGuardPwsh7 -Setting ("" + $(if ($null -ne $Values.PSObject.Properties["guardShell7"]) { $Values.guardShell7 } else { "" }))
    # -MachinePsModulePath is a seam for the suite; the command reads the machine value itself.
    $machinePath = $MachinePsModulePath
    if ($null -eq $machinePath) { $machinePath = [Environment]::GetEnvironmentVariable("PSModulePath", "Machine") }
    $guardEnvFor = ${function:Get-HordeGuardEnvironment}
    $ledgerProgram = "" + $Values.ledgerProgram; $ledgerScript = "" + $Values.ledgerScript
    # gh, git and the ledger run in the work folder, never in the caller's: gh reads the git checkout it is
    # started in, and nothing here may act on the caller's tree.
    $place = Get-HordeMergeWorkFolder -Values $Values
    $runProgram = ${function:Invoke-HordeMergeProgram}
    $formatLine = ${function:Format-HordeMergeLedgerLine}
    return @{
        Gh = { param([string[]]$Arguments) return (& $runProgram -Program $gh -Arguments $Arguments -Directory $place) }.GetNewClosure()
        Git = { param([string[]]$Arguments) return (& $runProgram -Program $git -Arguments $Arguments -Directory $place) }.GetNewClosure()
        # -Shell is "5.1" or "7" (the shells table). PowerShell 7 that is not there is a red guard with the
        # path named, never a skipped one.
        Guard = {
            param([string]$Checkout, [string]$Suite, [string]$Shell)
            $program = $shell
            if ($Shell -ceq "7") {
                $program = $shell7
                if (-not [System.IO.File]::Exists($program)) { return [pscustomobject]@{ code = -1; out = ""; err = ("PowerShell 7 is not at " + $program + "; install the MSI or set guardShell7 in the merge settings") } }
            }
            elseif ($Shell -cne "5.1") { return [pscustomobject]@{ code = -1; out = ""; err = ("the guard shell '" + $Shell + "' is not 5.1 or 7") } }
            $env1 = & $guardEnvFor -Shell $Shell -MachinePsModulePath ("" + $machinePath)
            return (& $runProgram -Program $program -Arguments @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", [System.IO.Path]::Combine($Checkout, $Suite)) -Directory $Checkout -Environment $env1)
        }.GetNewClosure()
        Ledger = { param([string[]]$Arguments) return (& $runProgram -Program $ledgerProgram -Arguments (@($ledgerScript) + @($Arguments)) -Directory $place) }.GetNewClosure()
        LedgerLine = { param([string[]]$Arguments) return (& $formatLine -Program $ledgerProgram -Script $ledgerScript -Arguments $Arguments) }.GetNewClosure()
        Tell = $Tell
        Mail = $Mail
        Wait = { param([int]$Seconds) Start-Sleep -Seconds $Seconds }
        Say = { param([string]$Line) [Console]::Out.WriteLine($Line) }
    }
}

# THE WARCHIEF'S TELL, through the messenger port as cli/ServicesTell.ps1 tells it: whichever loaded
# messenger offers body.untyped and idempotent.post, to the session holding the role of warchief.
# A TEST'S HOME TELLS NOBODY: a Horde home under the temp folder is a suite's, and is refused before any
# messenger or session record is looked for. The caller loads the port, the messengers, core/SessionSeat.ps1
# and core/Device.ps1 in its own scope.
$script:HordeMergeTellNeeds = @("body.untyped", "idempotent.post")
$script:HordeMergeTellStages = @("accepted", "handed-over", "seen")
$script:HordeMergeTellFrom = "horde-merge"
$script:HordeMergeTellTtlSeconds = 604800

function Test-HordeMergeHomeIsATests {
    # Is -HordeHome under the temp folder? One that cannot be resolved is taken as a test's.
    param([string]$HordeHome, [string]$TempRoot = "")
    if ($TempRoot -eq "") { $TempRoot = [System.IO.Path]::GetTempPath() }
    try {
        $rootFull = [System.IO.Path]::GetFullPath($TempRoot).TrimEnd('\', '/') + '\'
        $full = [System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\', '/') + '\'
        return [bool]$full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
    } catch { return $true }
}

function Send-HordeMergeTell {
    # { ok; detail }. -Label is the merging lane, worn as the sender's label.
    param([Parameter(Mandatory = $true)][string]$Body, [Parameter(Mandatory = $true)][string]$Label, [Parameter(Mandatory = $true)][string]$HordeHome)
    if (Test-HordeMergeHomeIsATests -HordeHome $HordeHome) { return [pscustomobject]@{ ok = $false; detail = "this Horde home is under the temp folder, so it is a test's: nobody is told" } }
    $found = Find-HordeMessenger -Require $script:HordeMergeTellNeeds
    if ($found.state -cne "known") { return [pscustomobject]@{ ok = $false; detail = ("no messenger can deliver to a session: " + $(if ($found.state -ceq "absent") { $found.note } else { $found.reason })) } }
    $seat = Get-HordeRoleSeat -Role "warchief"
    if ($seat.state -cne "known") { return [pscustomobject]@{ ok = $false; detail = ("the warchief's session cannot be told: " + $(if ($seat.state -ceq "absent") { $seat.note } else { $seat.reason })) } }
    $deviceId = ""
    try { $deviceId = Get-HordeDeviceId -HomeRoot $HordeHome } catch { return [pscustomobject]@{ ok = $false; detail = ("this machine's device id could not be had: " + $_.Exception.Message) } }
    $message = [pscustomobject]@{
        messageId = [guid]::NewGuid().ToString(); sessionId = "" + $seat.value.sessionId
        from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeMergeTellFrom; label = $Label }
        body = $Body; ttlSeconds = $script:HordeMergeTellTtlSeconds
    }
    $posted = Send-HordeMessengerMessage -Messenger $found.value -Message $message
    if ($posted.state -ceq "known" -and $script:HordeMergeTellStages -ccontains "$($posted.value.stage)") { return [pscustomobject]@{ ok = $true; detail = ("" + $posted.value.stage) } }
    if ($posted.state -ceq "known") { return [pscustomobject]@{ ok = $false; detail = ("the messenger answered " + $posted.value.stage) } }
    return [pscustomobject]@{ ok = $false; detail = ("the messenger did not take it: " + $posted.reason) }
}

function Get-HordeMergeLock {
    # A machine-wide named mutex (Global\, so merges from two sign-in sessions also take turns) per work
    # folder: two merges on one machine share the cache, and a second waits for
    # the first rather than fetching into it at the same time. Merges in order is the batch rule too
    # (CONTRIBUTING 15 rule 6).
    param([Parameter(Mandatory = $true)][string]$WorkFolder)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try { $hash = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($WorkFolder.ToLowerInvariant())) | Select-Object -First 8 | ForEach-Object { $_.ToString("x2") }) } finally { $sha.Dispose() }
    return (New-Object System.Threading.Mutex($false, ("Global\HordeMerge-" + $hash)))
}
