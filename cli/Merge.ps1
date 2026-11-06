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
# DAYTIME MODE (T-0347, founder rule of 2026-10-22). Merges do NOT wait for test runs: running every guard
# in two shells before each merge was a test run, and it held every Orc's daytime merge. So -Guards later
# (the default) skips steps 3, 4 and 5 below - the combined-tree build, the guards and the base-moved
# re-check that exists only for them - and everything else stays. After the merge one JSON line is added to
# <HORDE_HOME>\merge\guards-owed.jsonl: {repo (lower case), baseRefName, pr, task, by, at, headSha, mergeSha,
# firstParent}; a line without baseRefName (written before it was recorded) went into the default branch. ONE run
# at night or at idle (horde merge -RunOwed, below) covers everything merged that day, and names WHICH merge
# turned which guard red; that merge's owner fixes it first thing. The warchief's tell, the analyst's mail
# and the progress line say the guards are OWED, never that they passed. -Guards now is the old behaviour:
# the guards run first, on the merge result, and nothing is merged when one is red.
#
# THE NIGHTLY RUN (horde merge -RunOwed [-Repo OWNER/REPO] [-Json]; Invoke-HordeMergeRunOwed). For each repo
# with entries in guards-owed.jsonl whose mergeSha is not in guards-checked.jsonl, and for each branch those
# merges went into (their baseRefName; the default branch when a line has none): the guard list runs on the
# branch's current tip, in a scratch checkout of this command's cache, each guard in both shells with the same
# pass rule as step 4. THE GUARDS RUN ARE THE TIP'S LIST AND THE BASELINE'S (the first queued merge's first
# parent): a guard listed at the baseline and gone from the tip's list is RED ("dropped from the list"), naming
# the first queued merge whose list lacks it - the old rule that a PR may add a guard but not drop one.
# For each guard red at the tip, the entries are walked in merge order, running only that guard in only the
# shells red at the tip: first at the baseline, then at each mergeSha. A red baseline is "red before today's
# first queued merge" and names no merge; otherwise the FIRST mergeSha that is red is named (a red that a later
# merge fixed and another turned red again still names the first: the walk is linear and never bisects, because
# a red can be fixed again). A red is run once more before it is believed. A guard that DID NOT RUN (the tool
# answered code -1: PowerShell 7 missing, a timeout) is not a red and names no merge: that branch ends as
# "could not run", its merges stay owed, and the run ends 2.
# The report goes to <HORDE_HOME>\merge\nightly\<UTC date>-<owner>-<repo>.txt (a second run on the same UTC
# date appends to the same file) and is printed; it is written BEFORE each walked entry's mergeSha is appended
# to guards-checked.jsonl, and a report that could not be written marks nothing. guards-owed.jsonl is
# append-only and is never edited. A line in it that is damaged, or a merge that is not in its branch's
# history (a force-push took it), is reported in every run - with the line number, or the line to add to
# guards-checked.jsonl to give it up - and the rest is still checked; the run ends 2 for them only when nothing
# at all could be checked. Result 0 all green, 1 any red, 2 could not run (with -Json the last line is a summary
# whose "exit" is that result; the horde process itself ends 0, or 1 for anything else, because horde's own
# code 2 means a wrong command line). It does not schedule itself and does not check idle: the nightly
# scheduler (T-0331) calls it.
# THE QUEUE IS PER MACHINE: guards-owed.jsonl lives in this machine's Horde home, so a merge made from another
# machine is in THAT machine's queue and this run does not see it; every report names the machine and the queue
# file it covered. Only -Guards now and -RunOwed hold the machine's merge lock (they use the work folder); a
# daytime merge only appends a line, so it never waits for a long nightly run.
#
# WHAT IT DOES, IN ORDER, and why each step is where it is:
#   1. The request is checked (Test-HordeMergeRequest) and the task is looked up in the ledger BEFORE
#      anything else: the ledger's own merged verb refuses an unknown task, and after the merge that
#      refusal would leave a merge with no event - the failure this command exists to end.
#   2. The pull request is read from GitHub: open, not a draft, mergeable, and no review missing where
#      the repository requires one (reviewDecision REVIEW_REQUIRED or CHANGES_REQUESTED). An answer of
#      UNKNOWN is GitHub still working it out; it is asked again a few times, then refused.
#   3. (-Guards now only.) THE TREE THAT WILL EXIST AFTER THE MERGE is built in a cache repository of this command's own
#      (never the caller's working tree): the base branch and the PR head are fetched, and when the head
#      does not already contain the base, a throwaway merge commit is made with git merge-tree (CONTRIBUTING
#      15 rule 2: "mergeable" is not "green"). It is cloned, detached, into a fresh scratch folder whose
#      origin/<base> is the base as fetched, because test-host-names compares the lists with origin/main.
#   4. (-Guards now only.) Every repo-wide guard listed in test\guards.txt runs there (CONTRIBUTING 15 rule 9), each in Windows
#      PowerShell 5.1 AND in PowerShell 7. The list is the checked tree's plus the base's, so a PR may add
#      a guard but not drop one. A guard passes only on exit 0 AND its
#      closing banner: a suite with no banner was NOT RUN (rule 7). On a failure the failing lines are
#      printed and nothing is merged. THE GUARDS RUN ARE THE PR'S OWN COPIES, as they stand in the merge
#      result: a PR that weakens a guard is checked by the weakened guard. That is the same trust every
#      suite run on a branch has; a review of the guard's diff, and CI on main, are what catch it.
#   5. (-Guards now only.) The base is read again. If it moved while the guards ran, the new combination is built and
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
#   Owed    param([string]$Line)                             -> { ok; detail }   adds one line to guards-owed.jsonl (-Guards later)
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
    param([string]$Pr, [string]$Task, [string]$State, [string]$By, [string]$On = "", [string]$Reason = "", [string]$Guards = "later")
    $no = { param([string]$Why) return [pscustomobject]@{ ok = $false; why = $Why } }
    $m = [regex]::Match($Pr, $script:HordeMergePrPattern)
    if (-not $m.Success -or $m.Groups[2].Value -ceq "." -or $m.Groups[2].Value -ceq "..") { return (& $no ("'" + $Pr + "' is not a pull request: OWNER/REPO#N, such as YedPool/horde#305")) }
    if ($Task -cnotmatch $script:HordeMergeTaskPattern) { return (& $no ("'" + $Task + "' is not a task id: T- and four or more digits, such as T-0247")) }
    if (@("done", "waiting", "progress") -cnotcontains $State) { return (& $no ("'" + $State + "' is not a state a merge leaves a task in: done, waiting or progress")) }
    if ($By -cnotmatch $script:HordeMergeLanePattern) { return (& $no ("'" + $By + "' is not a lane: one or two capital letters, then digits if any, such as F or C1")) }
    if ($On -ne "" -and $On -cnotmatch $script:HordeMergeOnPattern) { return (& $no ("'" + $On + "' is not who a task waits on: founder, M, lane:X, device or service")) }
    if ($Reason -ne "" -and $Reason -cnotmatch $script:HordeMergeReasonPattern) { return (& $no "the reason is one line of 1 to 300 plain ASCII characters") }
    if (@("later", "now") -cnotcontains $Guards) { return (& $no ("'" + $Guards + "' is not when the guards run: later (the nightly run, the default) or now (before this merge)")) }
    if ($State -ceq "waiting" -and $On -eq "") { return (& $no "-State waiting needs -On: who or what the task waits on (founder, M, lane:X, device or service)") }
    if ($State -ceq "progress" -and $Reason -eq "") { return (& $no "-State progress needs -Reason: what is left of the task after this merge") }
    return [pscustomobject]@{ ok = $true; why = ""; owner = $m.Groups[1].Value; repo = $m.Groups[2].Value; number = [int]$m.Groups[3].Value
        pr = $Pr; task = $Task; state = $State; by = $By; on = $On; reason = $Reason; guards = $Guards }
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
    param([Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)][string]$MergeSha, [Parameter(Mandatory = $true)]$Check, [string]$Landed = "", [switch]$NotQueued, [string]$HandLine = "")
    $state = "Task " + $Request.task + " is now " + $Request.state
    if ("" + $Request.on -ne "") { $state += ", waiting on " + $Request.on }
    if ("" + $Request.reason -ne "") { $state += "; left: " + $Request.reason }
    # S1 of the review of PR 375: the text must not say "queued" when queueing failed, or the receivers conclude
    # the nightly run covers a merge that is not in the file.
    if ($Check.skipped -eq $true -and $NotQueued) { return ("HORDE MERGE: " + $Request.by + " merged " + $Request.pr + " as " + $MergeSha + "." + "`n" + $state + ".`nGuards NOT RUN and merge NOT QUEUED: it is not in guards-owed.jsonl, so the nightly run will NOT cover it until this line is added there by hand: " + $HandLine) }
    if ($Check.skipped -eq $true) { return ("HORDE MERGE: " + $Request.by + " merged " + $Request.pr + " as " + $MergeSha + "." + "`n" + $state + ".`nGuards NOT RUN: owed to the nightly run (queued in guards-owed.jsonl), not checked before this merge.") }
    $checked = "Guards green on " + $Check.base.Substring(0, 8) + " + " + $Check.head.Substring(0, 8)
    if ($Check.merged) { $checked += " (checked as their merge, " + $Check.commit.Substring(0, 8) + ")" }
    if ($Landed -ne "") { $checked = "NOT CHECKED: " + $Landed + ". The guards were green on " + $Check.base.Substring(0, 8) + " + " + $Check.head.Substring(0, 8) + " only" }
    return ("HORDE MERGE: " + $Request.by + " merged " + $Request.pr + " as " + $MergeSha + ".`n" + $state + ".`n" + $checked + ".")
}

function Format-HordeMergeProgress {
    # PURE. The one-line progress draft. The title is the PR author's text: it is cut to plain ASCII and
    # 100 characters, and this line is printed for the session to read, never sent anywhere.
    param([Parameter(Mandatory = $true)]$Request, [AllowEmptyString()][string]$Title, [switch]$GuardsOwed, [switch]$NotQueued)
    $t = ($Title -replace '[^\x20-\x7E]', '?').Trim()
    if ($t.Length -gt 100) { $t = $t.Substring(0, 97) + "..." }
    $line = "progress draft: " + $Request.by + " merged " + $Request.pr
    if ($t -ne "") { $line += " - " + $t }
    $line += " (" + $Request.task + ", now " + $Request.state
    if ("" + $Request.on -ne "") { $line += " on " + $Request.on }
    if ($GuardsOwed -and $NotQueued) { $line += "; guards NOT RUN and NOT QUEUED for the nightly run" }
    elseif ($GuardsOwed) { $line += "; guards owed to the nightly run" }
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
    if ($ok) { return [pscustomobject]@{ ok = $true; ran = $true; lines = @() } }
    $bad = @($all | Where-Object { $_ -cmatch '\[(FAIL|ERROR)\]' })
    if ($bad.Count -eq 0) { $bad = @($all | Where-Object { $_.Trim() -ne "" } | Select-Object -Last 10) }
    $why = "exit " + $Run.code
    if ($banner.Count -eq 0) { $why += ", and no closing banner: it did not run to its end, so it counts as NOT RUN" }
    $shown = @($bad | Select-Object -First $script:HordeMergeFailLines)
    if ($bad.Count -gt $shown.Count) { $shown += ("... and " + ($bad.Count - $shown.Count) + " more") }
    # ran is false only for code -1: the program could not start, was stopped past its time, or the tool threw (PowerShell 7
    # missing, no memory). That is not a finding about the tree. A guard that exits on its own without a banner ran
    # and proved nothing: that is the tree's fault (an emptied script), so it stays a red the walk can attribute.
    return [pscustomobject]@{ ok = $false; ran = ($Run.code -ne -1); lines = @(@($why) + $shown) }
}

function Invoke-HordeMergeTool {
    # Call one tool of the table; a tool that throws answers as a failed program, so no step is skipped
    # by an exception nobody reads.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Name, [object[]]$With = @())
    try { return (& $Tools[$Name] @With) }
    catch { return [pscustomobject]@{ code = -1; out = ""; err = ("the " + $Name + " tool failed: " + $_.Exception.Message); ok = $false; detail = ("the " + $Name + " tool failed: " + $_.Exception.Message) } }
}

function Format-HordeMergeOwedLine {
    # PURE. The one JSON line a daytime merge queues for the nightly run, or "" when the merge has no sha
    # to queue. Every value is a checked pattern or a sha, so the line is plain ASCII. -FirstParent may be "".
    param([Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)][string]$HeadSha, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$MergeSha, [AllowEmptyString()][string]$FirstParent = "", [datetime]$Now = [datetime]::UtcNow, [AllowEmptyString()][string]$BaseRef = "")
    if ($MergeSha -cnotmatch $script:HordeMergeShaPattern) { return "" }
    # THE REPO IS WRITTEN IN LOWER CASE: GitHub names are not case sensitive, and the nightly run compares them
    # that way (S5 of the review of PR 375). THE BASE BRANCH IS RECORDED (M3): a merge into a stacked PR's branch
    # is walked on that branch, not on the default one; a line without it is the default branch's.
    $entry = [ordered]@{ repo = ($Request.owner + "/" + $Request.repo).ToLowerInvariant(); baseRefName = $BaseRef; pr = $Request.pr; task = $Request.task; by = $Request.by
        at = $Now.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
        headSha = $HeadSha; mergeSha = $MergeSha; firstParent = $FirstParent }
    return (ConvertTo-Json -InputObject $entry -Compress)
}

function Add-HordeMergeLine {
    # Append one line to a file of this command's (a JSONL queue or a report), creating its folder. { ok; detail }:
    # the path on success, the reason on failure. Never throws. A file that does not end in a line feed (a crash
    # in the middle of a write, a hand edit) gets one first, or the new line would be glued onto the damaged one and
    # both would be unusable (S2 of the review of PR 375).
    # A SHARING VIOLATION IS TRIED AGAIN, a few times and briefly: AppendAllText holds the file with FileShare.Read, so a
    # second writer (two daytime merges at once) or a writer meeting the nightly run's read failed at once with "NOT
    # QUEUED" (review of PR 375 follow-up, T-0347). The wait is bounded, and when it runs out the failure is the same
    # loud one. -Attempts and -DelayMs are seams for the suite; -Sleep takes milliseconds.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Line, [int]$Attempts = 8, [int]$DelayMs = 150, [scriptblock]$Sleep = { param([int]$Ms) Start-Sleep -Milliseconds $Ms })
    $last = ""
    for ($try = 1; $try -le $Attempts; $try++) {
        try {
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
            $prefix = ""
            if ([System.IO.File]::Exists($Path)) {
                $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    if ($fs.Length -gt 0) {
                        [void]$fs.Seek(-1, [System.IO.SeekOrigin]::End)
                        if ($fs.ReadByte() -ne 10) { $prefix = "`n" }
                    }
                } finally { $fs.Dispose() }
            }
            [System.IO.File]::AppendAllText($Path, ($prefix + $Line + "`n"), (New-Object System.Text.UTF8Encoding($false)))
            return [pscustomobject]@{ ok = $true; detail = $Path }
        } catch [System.IO.IOException] {
            $last = $_.Exception.Message
            if ($try -lt $Attempts) { & $Sleep ($DelayMs * $try) }
        } catch { return [pscustomobject]@{ ok = $false; detail = ("could not append to " + $Path + ": " + $_.Exception.Message) } }
    }
    return [pscustomobject]@{ ok = $false; detail = ("could not append to " + $Path + " after " + $Attempts + " tries, the file stayed in use: " + $last) }
}

function Read-HordeMergeFileText {
    # The text of a file of this command's, opened so a writer may append meanwhile (FileShare.ReadWrite): ReadAllText
    # takes FileShare.Read, which made a daytime merge that queued during the nightly run's read fail "NOT QUEUED".
    # Throws as ReadAllText does.
    param([Parameter(Mandatory = $true)][string]$Path)
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try {
        $sr = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding($false)), $true)
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $fs.Dispose() }
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
    return [pscustomobject]@{ ok = $true; why = ""; lines = @(); base = $baseSha; head = $headSha; commit = $commit; merged = $merged; skipped = $false }
}

$script:HordeMergeIntentFileName = "guards-intent.jsonl"
$script:HordeMergeIntentStaleMinutes = 60

function Format-HordeMergeIntentLine {
    # PURE. The line a daytime merge writes BEFORE it asks GitHub to merge (T-0347): a crash between the merge and the
    # queue write used to lose the merge for good, because nothing recorded that it was about to happen. Plain ASCII;
    # -Kind is "intent" or "settled" (-How says how it ended: queued, not-merged, recovered).
    param([Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)][string]$HeadSha, [AllowEmptyString()][string]$BaseRef = "", [string]$Kind = "intent", [string]$How = "", [datetime]$Now = [datetime]::UtcNow)
    $e = [ordered]@{ kind = $Kind; repo = ($Request.owner + "/" + $Request.repo).ToLowerInvariant(); owner = $Request.owner; name = $Request.repo; number = [int]$Request.number; pr = $Request.pr; task = $Request.task; by = $Request.by; baseRefName = $BaseRef; headSha = $HeadSha
        at = $Now.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($Kind -cne "intent") { $e["how"] = $How }
    return (ConvertTo-Json -InputObject $e -Compress)
}

function Read-HordeMergeOpenIntents {
    # PURE. { open; bad } from the text of guards-intent.jsonl: open is the intents with no later "settled" line for the
    # same repo, PR number and head (an ordered list of { repo; owner; name; number; pr; task; by; baseRefName; headSha; at }).
    # A later intent for the same key opens it again. bad counts the lines that are neither.
    param([AllowEmptyString()][string]$Text)
    $open = [ordered]@{}
    $bad = 0
    foreach ($raw in @(("" + $Text) -split "\r?\n")) {
        if ($raw.Trim() -eq "") { continue }
        $e = $null
        try { $e = ConvertFrom-HordeJson -Text $raw } catch { $bad++; continue }
        $v = @{}
        foreach ($k in @("kind", "repo", "owner", "name", "pr", "task", "by", "baseRefName", "headSha", "at")) {
            $v[$k] = ""
            if ($null -ne $e -and $null -ne $e.PSObject -and $null -ne $e.PSObject.Properties[$k] -and $e.PSObject.Properties[$k].Value -is [string]) { $v[$k] = [string]$e.PSObject.Properties[$k].Value }
        }
        $number = 0
        if ($null -ne $e -and $null -ne $e.PSObject -and $null -ne $e.PSObject.Properties["number"] -and ($e.number -is [int] -or $e.number -is [long])) { $number = [int]$e.number }
        if (-not (Test-HordeMergeOwedRepo -Repo $v["repo"]) -or $number -lt 1 -or $v["headSha"] -cnotmatch $script:HordeMergeShaPattern -or @("intent", "settled") -cnotcontains $v["kind"]) { $bad++; continue }
        $key = $v["repo"].ToLowerInvariant() + "#" + $number + "@" + $v["headSha"]
        if ($v["kind"] -ceq "settled") { $open.Remove($key); continue }
        if ($v["owner"] -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9-]{0,38}\z' -or $v["name"] -cnotmatch '\A[A-Za-z0-9_.-]{1,100}\z' -or ($v["baseRefName"] -ne "" -and $v["baseRefName"] -cnotmatch $script:HordeMergeRefPattern)) { $bad++; continue }
        foreach ($k in @("pr", "task", "by")) { $v[$k] = ($v[$k] -replace '[^\x20-\x7E]', '?') }
        $open[$key] = [pscustomobject]@{ key = $key; repo = $v["repo"].ToLowerInvariant(); owner = $v["owner"]; name = $v["name"]; number = $number; pr = $v["pr"]; task = $v["task"]; by = $v["by"]; baseRefName = $v["baseRefName"]; headSha = $v["headSha"]; at = $v["at"] }
    }
    return [pscustomobject]@{ open = @($open.Values); bad = $bad }
}

function Resolve-HordeMergeIntents {
    # The nightly run's first step (T-0347): every merge that was begun and never settled is asked of GitHub. One that is
    # MERGED is queued as owed (its merge commit is what GitHub says), so a crash between `gh pr merge` and the queue
    # write loses nothing. One that is not merged and is older than an hour is settled as not merged (a younger one may
    # be a merge still in flight in another process, which queues itself). { ok; recovered }: ok is false when
    # something could not be settled, which the run ends 2 for; the intent stays and is asked again next run.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Folder, [string]$Repo = "", [datetime]$Now = [datetime]::UtcNow)
    $say = $Tools["Say"]
    $path = [System.IO.Path]::Combine($Folder, $script:HordeMergeIntentFileName)
    if (-not [System.IO.File]::Exists($path)) { return [pscustomobject]@{ ok = $true; recovered = 0 } }
    $text = ""
    try { $text = Read-HordeMergeFileText -Path $path } catch { & $say ("could not read " + $path + ": " + $_.Exception.Message + " - merges begun and not queued cannot be recovered in this run"); return [pscustomobject]@{ ok = $false; recovered = 0 } }
    $read = Read-HordeMergeOpenIntents -Text $text
    $ok = $true
    $recovered = 0
    if ($read.bad -gt 0) { & $say ("WARNING: " + $path + " has " + $read.bad + " line(s) that are not a usable intent; they cannot be recovered"); }
    foreach ($i in @($read.open)) {
        if ($Repo -ne "" -and $i.repo -cne $Repo.ToLowerInvariant()) { continue }
        $v = Invoke-HordeMergeTool -Tools $Tools -Name "Gh" -With @(, [string[]]@("pr", "view", ("" + $i.number), "--repo", $i.repo, "--json", "state,mergeCommit"))
        $pr = $null
        if ($v.code -eq 0) { try { $pr = ConvertFrom-HordeJson -Text $v.out } catch { $pr = $null } }
        if ($null -eq $pr -or $null -eq $pr.PSObject.Properties["state"]) { $ok = $false; & $say ("COULD NOT ASK GITHUB whether " + $i.pr + " was merged (a merge begun and never settled): " + (Get-HordeMergeFirstLine ("" + $v.err)) + "; asked again next run"); continue }
        $how = ""
        if ("" + $pr.state -ceq "MERGED") {
            $sha = ""
            if ($null -ne $pr.PSObject.Properties["mergeCommit"] -and $null -ne $pr.mergeCommit) { $sha = "" + $pr.mergeCommit.oid }
            if ($sha -cnotmatch $script:HordeMergeShaPattern) { $ok = $false; & $say ("GitHub shows " + $i.pr + " MERGED but gave no merge commit; asked again next run"); continue }
            $req = [pscustomobject]@{ owner = $i.owner; repo = $i.name; pr = $i.pr; task = $i.task; by = $i.by }
            $line = Format-HordeMergeOwedLine -Request $req -HeadSha $i.headSha -MergeSha $sha -FirstParent "" -BaseRef $i.baseRefName
            $ow = Invoke-HordeMergeTool -Tools $Tools -Name "Owed" -With @($line)
            if ($ow.ok -ne $true) { $ok = $false; & $say ("COULD NOT QUEUE " + $i.pr + ", which was merged and never queued: " + $ow.detail + "; add this line to guards-owed.jsonl by hand: " + $line); continue }
            & $say ("recovered " + $i.pr + ": it was merged as " + $sha + " and never queued (a crash between the merge and the queue write); queued now")
            $recovered++
            $how = "recovered"
        } else {
            $age = 999999
            $at = [datetime]::MinValue
            if ([datetime]::TryParse($i.at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$at)) { $age = ($Now.ToUniversalTime() - $at).TotalMinutes }
            if ($age -lt $script:HordeMergeIntentStaleMinutes) { continue }
            $how = "not-merged"
        }
        $req2 = [pscustomobject]@{ owner = $i.owner; repo = $i.name; number = $i.number; pr = $i.pr; task = $i.task; by = $i.by }
        $st = Invoke-HordeMergeTool -Tools $Tools -Name "Intent" -With @((Format-HordeMergeIntentLine -Request $req2 -HeadSha $i.headSha -BaseRef $i.baseRefName -Kind "settled" -How $how))
        if ($st.ok -ne $true) { $ok = $false; & $say ("could not settle the intent of " + $i.pr + ": " + $st.detail) }
    }
    return [pscustomobject]@{ ok = $ok; recovered = $recovered }
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
    $url = ""
    if ($Request.guards -cne "later") {
        $u = Invoke-HordeMergeTool -Tools $Tools -Name "Gh" -With @(, [string[]]@("repo", "view", $repo, "--json", "url", "--jq", ".url"))
        $url = ("" + $u.out).Trim()
        if ($u.code -ne 0 -or $url -eq "") { return (& $refuse ("gh could not say where " + $repo + " is: " + (Get-HordeMergeFirstLine ("" + $u.err)))) }
    }

    # 3 TO 5. CHECK, AND AGAIN WHILE THE BASE MOVES. Only with -Guards now: in daytime mode (the default)
    # nothing is built or run here, and the head GitHub just reported is what the merge is pinned to.
    $check = $null
    $round = 0
    if ($Request.guards -ceq "later") {
        $check = [pscustomobject]@{ ok = $true; why = ""; lines = @(); base = ""; head = ("" + $pr.headRefOid); commit = ("" + $pr.headRefOid); merged = $false; skipped = $true }
    }
    while (-not ($Request.guards -ceq "later")) {
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
    # THE INTENT IS WRITTEN FIRST (daytime mode, T-0347): a crash between `gh pr merge` and the queue write used to lose the
    # merge, with nothing anywhere to say it had been begun. The nightly run asks GitHub about every intent never settled
    # and queues the ones that were merged. An intent that cannot be written refuses the merge: the queue is the same
    # folder, so the merge could not have been queued either.
    if ($check.skipped -eq $true) {
        $iw = Invoke-HordeMergeTool -Tools $Tools -Name "Intent" -With @((Format-HordeMergeIntentLine -Request $Request -HeadSha $check.head -BaseRef ("" + $pr.baseRefName)))
        if ($iw.ok -ne $true) { return (& $refuse ("the intent to merge could not be written, so nothing was merged: " + $iw.detail)) }
    }
    $settle = {
        param([string]$How)
        if ($check.skipped -ne $true) { return }
        $sr = Invoke-HordeMergeTool -Tools $Tools -Name "Intent" -With @((Format-HordeMergeIntentLine -Request $Request -HeadSha $check.head -BaseRef ("" + $pr.baseRefName) -Kind "settled" -How $How))
        if ($sr.ok -ne $true) { & $say ("could not settle the intent to merge " + $Request.pr + " (the nightly run settles it): " + $sr.detail) }
    }
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
    if (-not $isMerged -and $m.code -ne 0) {
        # SETTLED AS NOT MERGED ONLY WHEN GITHUB SAID SO (round 2 of T-0347). No answer to the view, or a merge that was
        # stopped on a timeout (code -1: GitHub may still be merging, whatever the view right after says), is an
        # unknown: the intent stays open and the nightly run asks GitHub, so the merge is never lost.
        $gitHubSaid = ($null -ne $after -and $m.code -ne -1)
        if ($gitHubSaid) { & $settle "not-merged" }
        $unknown = $(if ($gitHubSaid) { "" } else { "; GitHub's answer is unknown, so the intent stays open and the nightly run will ask" })
        return (& $refuse ("gh did not merge " + $Request.pr + ": " + (Get-HordeMergeFirstLine ("" + $m.err + "`n" + $m.out)) + $unknown))
    }
    if (-not $isMerged) {
        # gh said it merged and GitHub does not show it: nothing after this can be said truthfully.
        return [pscustomobject]@{ outcome = "merged-unfinished"; why = ("gh said it merged " + $Request.pr + ", but GitHub does not show it MERGED; look at it by hand. The ledger was NOT written and nobody was told" + $(if ($check.skipped -eq $true) { "; the intent to merge stays recorded, so the nightly run queues it if GitHub shows it MERGED" } else { "" })); mergeSha = ""; problems = @("look at the PR by hand") }
    }
    $mergeSha = ""
    if ($null -ne $after.PSObject.Properties["mergeCommit"] -and $null -ne $after.mergeCommit) { $mergeSha = "" + $after.mergeCommit.oid }
    if ($mergeSha -cnotmatch $script:HordeMergeShaPattern) { $mergeSha = "(GitHub gave no merge commit)" }
    & $say ("MERGED " + $Request.pr + " as " + $mergeSha)

    # WHERE DID IT LAND (header, step 6)? The merge commit's first parent must be the base the guards
    # checked; anything else - or no answer - means main now holds a tree nobody checked.
    # In daytime mode nothing was checked, so there is no checked base to compare with; the first parent is
    # only read, to be queued with the merge for the nightly run.
    $landed = ""
    $first = ""
    if ($mergeSha -cmatch $script:HordeMergeShaPattern) {
        $pa = Invoke-HordeMergeTool -Tools $Tools -Name "Gh" -With @(, [string[]]@("api", ("repos/" + $repo + "/commits/" + $mergeSha), "--jq", ".parents[].sha"))
        $first = (@(("" + $pa.out).Trim() -split "\s+")[0])
        if ($pa.code -ne 0 -or $first -cnotmatch $script:HordeMergeShaPattern) { $first = ""; if ($check.skipped -ne $true) { $landed = "the merge commit's parents could not be read, so where it landed is unknown" } }
        elseif ($check.skipped -ne $true -and $first -cne $check.base) { $landed = "the merge landed on " + $pr.baseRefName + " " + $first.Substring(0, 8) + ", which moved after the check" }
    } elseif ($check.skipped -ne $true) { $landed = "GitHub gave no merge commit, so where it landed is unknown" }

    # 7. THE LEDGER, THE TELLS, THE DRAFT. Each failure is said and kept; none undoes the merge.
    $problems = New-Object System.Collections.ArrayList
    $queued = $true
    $handLine = ""
    if ($landed -ne "") {
        & $say ("THE MERGE IS ON A TREE THE GUARDS DID NOT CHECK: " + $landed + "; run the guards on " + $pr.baseRefName + " now")
        [void]$problems.Add($landed + "; run the guards on " + $pr.baseRefName + " now")
    }
    # THE OWED LINE (daytime mode): the merge is queued for the nightly run. A failure to queue it comes after
    # a merge that happened, so it is said loudly with the line to add by hand, and the command exits 1.
    if ($check.skipped -eq $true) {
        $owedLine = Format-HordeMergeOwedLine -Request $Request -HeadSha $check.head -MergeSha $mergeSha -FirstParent $first -BaseRef ("" + $pr.baseRefName)
        $ow = $null
        if ($owedLine -eq "") { $ow = [pscustomobject]@{ ok = $false; detail = "GitHub gave no merge commit, so there is no sha to queue" } }
        else { $ow = Invoke-HordeMergeTool -Tools $Tools -Name "Owed" -With @($owedLine) }
        if ($ow.ok -eq $true) { $queued = $true; & $say "guards not run: queued for the nightly run (guards-owed.jsonl)"; & $settle "queued" }
        else {
            $queued = $false
            & $say ("THE MERGE HAPPENED, BUT IT WAS NOT QUEUED FOR THE NIGHTLY GUARDS RUN: " + $ow.detail)
            $hand = $owedLine
            if ($hand -eq "") { $hand = "(a line {repo, pr, task, by, at, headSha, mergeSha, firstParent} for " + $Request.pr + " once its merge commit is known)" }
            & $say ("add this line to guards-owed.jsonl by hand: " + $hand)
            $handLine = $hand
            [void]$problems.Add("the merge was not queued for the nightly guards run; add this line to guards-owed.jsonl: " + $hand)
        }
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
    $message = Format-HordeMergeMessage -Request $Request -MergeSha $mergeSha -Check $check -Landed $landed -NotQueued:(-not $queued) -HandLine $handLine
    $t = Invoke-HordeMergeTool -Tools $Tools -Name "Tell" -With @($message)
    if ($t.ok -eq $true) { & $say "told the warchief" }
    else { & $say ("COULD NOT TELL THE WARCHIEF: " + $t.detail); [void]$problems.Add("the warchief was not told: send the warchief the message below") }
    $a = Invoke-HordeMergeTool -Tools $Tools -Name "Mail" -With @($message)
    if ($a.ok -eq $true) { & $say ("mailed the analyst: " + $a.detail) }
    else { & $say ("COULD NOT MAIL THE ANALYST: " + $a.detail); [void]$problems.Add("the analyst was not mailed: horde analyst mail -Text with the message below") }
    if ($problems.Count -gt 0) { foreach ($l in @($message -split "`n")) { & $say ("    " + $l) } }
    & $say (Format-HordeMergeProgress -Request $Request -Title ("" + $pr.title) -GuardsOwed:($check.skipped -eq $true) -NotQueued:(-not $queued))
    if ($problems.Count -gt 0) { return [pscustomobject]@{ outcome = "merged-unfinished"; why = ("merged " + $Request.pr + " as " + $mergeSha + ", but " + ($problems -join "; ")); mergeSha = $mergeSha; problems = @($problems) } }
    return [pscustomobject]@{ outcome = "merged"; why = ""; mergeSha = $mergeSha; problems = @() }
}

# ---- THE NIGHTLY RUN: horde merge -RunOwed (header, "THE NIGHTLY RUN") -----------------------------------

$script:HordeMergeGiveUpLines = 50
$script:HordeMergeOwedRepoPattern = '\A([A-Za-z0-9][A-Za-z0-9-]{0,38})/([A-Za-z0-9_.-]{1,100})\z'

function Test-HordeMergeOwedRepo {
    # PURE. Is -Repo an OWNER/REPO? The same rule as Test-HordeMergeRequest: the repository may not be "." or "..".
    param([AllowEmptyString()][string]$Repo)
    $m = [regex]::Match("" + $Repo, $script:HordeMergeOwedRepoPattern)
    return [bool]($m.Success -and $m.Groups[2].Value -cne "." -and $m.Groups[2].Value -cne "..")
}

function Read-HordeMergeOwedEntries {
    # PURE. { entries; bad } from the text of guards-owed.jsonl: entries in file order (= merge order), each
    # { repo; base; pr; task; by; mergeSha; firstParent; headSha; at }; bad lists the line numbers that are not a
    # usable entry, so a damaged line is said and never silently dropped. The repo is read in lower case (GitHub
    # names are not case sensitive). base is "" for a line written before the base branch was recorded: that
    # merge went into the repository's default branch. A second line for a mergeSha already seen is dropped (a
    # hand re-add after a half-failed append would otherwise be walked twice).
    param([AllowEmptyString()][string]$Text)
    $entries = New-Object System.Collections.ArrayList
    $bad = New-Object System.Collections.ArrayList
    $seen = @{}
    $n = 0
    foreach ($raw in @(("" + $Text) -split "\r?\n")) {
        $n++
        if ($raw.Trim() -eq "") { continue }
        $e = $null
        try { $e = ConvertFrom-HordeJson -Text $raw } catch { [void]$bad.Add($n); continue }
        $v = @{}
        foreach ($k in @("repo", "baseRefName", "pr", "task", "by", "headSha", "mergeSha", "firstParent", "at")) {
            $v[$k] = ""
            if ($null -ne $e -and $null -ne $e.PSObject -and $null -ne $e.PSObject.Properties[$k] -and $e.PSObject.Properties[$k].Value -is [string]) { $v[$k] = [string]$e.PSObject.Properties[$k].Value }
        }
        if (-not (Test-HordeMergeOwedRepo -Repo $v["repo"]) -or $v["mergeSha"] -cnotmatch $script:HordeMergeShaPattern) { [void]$bad.Add($n); continue }
        if ($v["baseRefName"] -ne "" -and $v["baseRefName"] -cnotmatch $script:HordeMergeRefPattern) { [void]$bad.Add($n); continue }
        if ($v["firstParent"] -ne "" -and $v["firstParent"] -cnotmatch $script:HordeMergeShaPattern) { $v["firstParent"] = "" }
        foreach ($k in @("pr", "task", "by")) { $v[$k] = ($v[$k] -replace '[^\x20-\x7E]', '?') }
        if ($seen.ContainsKey($v["mergeSha"])) { continue }
        $seen[$v["mergeSha"]] = $true
        [void]$entries.Add([pscustomobject]@{ repo = $v["repo"].ToLowerInvariant(); base = $v["baseRefName"]; pr = $v["pr"]; task = $v["task"]; by = $v["by"]; headSha = $v["headSha"]; mergeSha = $v["mergeSha"]; firstParent = $v["firstParent"]; at = $v["at"] })
    }
    return [pscustomobject]@{ entries = @($entries); bad = @($bad) }
}

function Read-HordeMergeCheckedShas {
    # PURE. The mergeShas in the text of guards-checked.jsonl, as a hashtable used as a set. A damaged line
    # checks nothing: the merge is checked again, which costs a run and loses no merge. A line with a mergeSha
    # clears that merge whatever its result says: that is also how a person gives up on a merge that cannot be
    # walked (the report prints the line to add).
    param([AllowEmptyString()][string]$Text)
    $set = @{}
    foreach ($raw in @(("" + $Text) -split "\r?\n")) {
        if ($raw.Trim() -eq "") { continue }
        $e = $null
        try { $e = ConvertFrom-HordeJson -Text $raw } catch { continue }
        if ($null -ne $e -and $null -ne $e.PSObject -and $null -ne $e.PSObject.Properties["mergeSha"] -and "" + $e.mergeSha -cmatch $script:HordeMergeShaPattern) { $set["" + $e.mergeSha] = $true }
    }
    return $set
}

$script:HordeMergeRedFileName = "guards-red.json"

function Read-HordeMergeOpenReds {
    # { ok; why; reds } from guards-red.json (the record of reds still open, one per repo and branch, T-0347). reds is a
    # hashtable "repo|base" -> { repo; base; since; guards; merge; note } (merge is $null or { pr; task; by; mergeSha }).
    # No file is no open red. A file that is there and cannot be read, is not JSON, or holds a record that is not one is
    # NOT GREEN: ok is false and the run ends 2, because reading a damaged record as "nothing open" would turn a red
    # main green on the next quiet night, the very thing this file exists to stop.
    param([Parameter(Mandatory = $true)][string]$Path)
    $reds = @{}
    if (-not [System.IO.File]::Exists($Path)) { return [pscustomobject]@{ ok = $true; why = ""; reds = $reds } }
    $bad = { param([string]$Why) return [pscustomobject]@{ ok = $false; why = ($Path + " " + $Why); reds = @{} } }
    $text = ""
    try { $text = Read-HordeMergeFileText -Path $Path } catch { return (& $bad ("could not be read: " + $_.Exception.Message)) }
    $o = $null
    try { $o = ConvertFrom-HordeJson -Text $text } catch { return (& $bad "is not JSON") }
    if ($null -eq $o -or $null -eq $o.PSObject -or $null -eq $o.PSObject.Properties["reds"]) { return (& $bad "has no list of open reds") }
    foreach ($e in @($o.reds)) {
        if ($null -eq $e -or $null -eq $e.PSObject) { return (& $bad "holds a record that is not an object") }
        $v = @{}
        foreach ($k in @("repo", "base", "since", "note")) {
            $v[$k] = ""
            if ($null -ne $e.PSObject.Properties[$k] -and $e.PSObject.Properties[$k].Value -is [string]) { $v[$k] = [string]$e.PSObject.Properties[$k].Value }
        }
        if (-not (Test-HordeMergeOwedRepo -Repo $v["repo"]) -or $v["base"] -cnotmatch $script:HordeMergeRefPattern) { return (& $bad "holds a record with no usable repository or branch") }
        $guards = @()
        if ($null -ne $e.PSObject.Properties["guards"]) { $guards = @(@($e.guards) | Where-Object { $_ -is [string] }) }
        $merge = $null
        if ($null -ne $e.PSObject.Properties["merge"] -and $null -ne $e.merge -and $null -ne $e.merge.PSObject) {
            $mv = @{}
            foreach ($k in @("pr", "task", "by", "mergeSha")) { $mv[$k] = ""; if ($null -ne $e.merge.PSObject.Properties[$k] -and $e.merge.PSObject.Properties[$k].Value -is [string]) { $mv[$k] = ([string]$e.merge.PSObject.Properties[$k].Value -replace '[^\x20-\x7E]', '?') } }
            $merge = [pscustomobject]@{ pr = $mv["pr"]; task = $mv["task"]; by = $mv["by"]; mergeSha = $mv["mergeSha"] }
        }
        $reds[$v["repo"].ToLowerInvariant() + "|" + $v["base"]] = [pscustomobject]@{ repo = $v["repo"].ToLowerInvariant(); base = $v["base"]; since = ($v["since"] -replace '[^\x20-\x7E]', '?'); guards = @($guards); merge = $merge; note = ($v["note"] -replace '[^\x20-\x7E]', '?') }
    }
    return [pscustomobject]@{ ok = $true; why = ""; reds = $reds }
}

function Write-HordeMergeOpenReds {
    # { ok; detail }: guards-red.json rewritten whole, through a file beside it that replaces it, so a crash leaves the old
    # record or the new one and never half of either. Never throws.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][hashtable]$Reds)
    try {
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        $list = @()
        foreach ($k in @($Reds.Keys | Sort-Object)) {
            $e = $Reds[$k]
            $m = $null
            if ($null -ne $e.merge) { $m = [ordered]@{ pr = $e.merge.pr; task = $e.merge.task; by = $e.merge.by; mergeSha = $e.merge.mergeSha } }
            $list += , ([ordered]@{ repo = $e.repo; base = $e.base; since = $e.since; guards = @($e.guards); merge = $m; note = $e.note })
        }
        $json = ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = 1; reds = @($list) }) -Compress -Depth 8
        $tmp = $Path + ".tmp"
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        if ([System.IO.File]::Exists($Path)) { [System.IO.File]::Replace($tmp, $Path, [NullString]::Value) } else { [System.IO.File]::Move($tmp, $Path) }
        return [pscustomobject]@{ ok = $true; detail = $Path }
    } catch { return [pscustomobject]@{ ok = $false; detail = ("could not write " + $Path + ": " + $_.Exception.Message) } }
}

function Format-HordeMergeNamedMerge {
    # PURE. The words that name a merge in a report: "the merge of PR (task T, by L, mergeSha S)".
    param([Parameter(Mandatory = $true)]$Merge)
    return ("the merge of " + $Merge.pr + " (task " + $Merge.task + ", by " + $Merge.by + ", mergeSha " + $Merge.mergeSha + ")")
}

function Invoke-HordeMergeGuardAt {
    # One guard, at one commit of the scratch checkout, in the shells named by -ShellKeys (default: all).
    # { ok; red; absent; shells; shellKeys; lines; why }.
    #   ok false: no answer could be had - the commit would not check out, or the guard DID NOT RUN (the tool
    #     answered code -1: PowerShell 7 missing, a timeout, the tool threw). why says which. That is not a
    #     finding about the tree, so no merge may be blamed and nothing may be marked checked (M2, review of
    #     PR 375). A guard that exits by itself with no banner DID run and proved nothing: that is red, and the
    #     walk can find the merge that emptied it.
    #   absent: the guard is not in that commit's tree.
    #   red: a shell ran it and it failed, twice: a red is run once more before it is believed, and a guard
    #     that passes the second time is said and counted green (a starved or flaky run must not name a merge).
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Scratch, [Parameter(Mandatory = $true)][string]$Commit, [Parameter(Mandatory = $true)][string]$Guard, [string[]]$ShellKeys = @())
    $no = { param([string]$Why) return [pscustomobject]@{ ok = $false; red = $false; absent = $false; shells = @(); shellKeys = @(); lines = @(); why = $Why } }
    $r = Invoke-HordeMergeGit -Tools $Tools -What ("checking out " + $Commit.Substring(0, 8)) -Arguments @("-C", $Scratch, "-c", "core.longpaths=true", "checkout", "--detach", "--force", "--quiet", $Commit)
    if (-not $r.ok) { return (& $no $r.why) }
    if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($Scratch, $Guard))) { return [pscustomobject]@{ ok = $true; red = $false; absent = $true; shells = @(); shellKeys = @(); lines = @(); why = "" } }
    $shells = @()
    $keys = @()
    $lines = @()
    foreach ($sh in @(Get-HordeGuardShells)) {
        if (@($ShellKeys).Count -gt 0 -and @($ShellKeys) -cnotcontains $sh.key) { continue }
        $run = Invoke-HordeMergeTool -Tools $Tools -Name "Guard" -With @($Scratch, $Guard, $sh.key)
        $read = Read-HordeMergeGuardResult -Run $run
        if (-not $read.ok -and $read.ran) {
            $again = Invoke-HordeMergeTool -Tools $Tools -Name "Guard" -With @($Scratch, $Guard, $sh.key)
            $run = $again
            $read = Read-HordeMergeGuardResult -Run $again
            if ($read.ok) { & $Tools["Say"] ($Guard + " was red in " + $sh.label + " at " + $Commit.Substring(0, 8) + " and green on a second run: counted green (a flaky or starved run)") }
        }
        if (-not $read.ok -and -not $read.ran) { return (& $no ("the guard " + $Guard + " could not be run in " + $sh.label + " at " + $Commit.Substring(0, 8) + ", so nothing is said about it: " + (Get-HordeMergeFirstLine ("" + $run.err + "`n" + $run.out)))) }
        if (-not $read.ok) { $shells += $sh.label; $keys += $sh.key; if ($lines.Count -eq 0) { $lines = @($read.lines) } }
    }
    return [pscustomobject]@{ ok = $true; red = ($shells.Count -gt 0); absent = $false; shells = @($shells); shellKeys = @($keys); lines = @($lines); why = "" }
}

function Get-HordeMergeGuardListAt {
    # The guards listed at one commit of the cache. { ok; why; guards }: ok false when git failed; guards is $null
    # when the commit has no list or an unusable one (why says which), else the guards in order.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Cache, [Parameter(Mandatory = $true)][string]$Commit)
    $listGit = (Get-HordeGuardListPath).Replace("\", "/")
    $has = Invoke-HordeMergeGit -Tools $Tools -What ("asking whether " + $Commit.Substring(0, 8) + " has a guard list") -Arguments @("-C", $Cache, "ls-tree", "--name-only", $Commit, "--", $listGit)
    if (-not $has.ok) { return [pscustomobject]@{ ok = $false; why = $has.why; guards = $null } }
    if ($has.out -eq "") { return [pscustomobject]@{ ok = $true; why = ("no " + (Get-HordeGuardListPath) + " at " + $Commit.Substring(0, 8)); guards = $null } }
    $text = Invoke-HordeMergeGit -Tools $Tools -What ("reading the guard list of " + $Commit.Substring(0, 8)) -Arguments @("-C", $Cache, "show", ($Commit + ":" + $listGit))
    if (-not $text.ok) { return [pscustomobject]@{ ok = $false; why = $text.why; guards = $null } }
    $read = Read-HordeGuardList -Text $text.out
    if (-not $read.ok) { return [pscustomobject]@{ ok = $true; why = $read.why; guards = $null } }
    return [pscustomobject]@{ ok = $true; why = ""; guards = @($read.guards) }
}

function Invoke-HordeMergeRunOwedBase {
    # One repo's unchecked entries that went into ONE branch (-Entries, merge order). { status; reds; skipped;
    # checked; why }: status green, red or error (error: nothing of this branch may be marked checked).
    #   reds: { kind; guard; shells; entry; note; lines; base } - kind red, missing (the script is gone) or
    #     dropped (the list lost it); entry is the merge named, $null when none is.
    #   skipped: { entry; why } - an entry that is not in the branch's history (a force-push took it, or it was
    #     merged into another branch): reported, never walked, the others still are (M3).
    #   checked: the entries that were walked.
    param([Parameter(Mandatory = $true)][string]$Repo, [Parameter(Mandatory = $true)][string]$Base, [Parameter(Mandatory = $true)][string]$Cache, [Parameter(Mandatory = $true)][string]$Url, [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Entries, [Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$WorkFolder, [switch]$Recheck)
    # -Recheck: a red is open on this branch (guards-red.json). The guards run at the tip even when no merge is owed on it
    # (or none could be walked), so a red main stays red until a run finds it green (T-0347). With no merge to walk, a
    # red names no merge: the report names the one the open record holds.
    $say = $Tools["Say"]
    $err = { param([string]$Why) return [pscustomobject]@{ status = "error"; reds = @(); skipped = @(); checked = @(); why = $Why } }
    $r = Invoke-HordeMergeGit -Tools $Tools -What ("fetching " + $Base) -Arguments @("-C", $Cache, "fetch", "--no-tags", "--quiet", $Url, ("+refs/heads/" + $Base + ":refs/heads/" + $Base))
    if (-not $r.ok) { return (& $err $r.why) }
    $r = Invoke-HordeMergeGit -Tools $Tools -What "pointing the cache at the branch" -Arguments @("-C", $Cache, "symbolic-ref", "HEAD", ("refs/heads/" + $Base))
    if (-not $r.ok) { return (& $err $r.why) }
    $t = Invoke-HordeMergeGit -Tools $Tools -What "reading the branch" -Arguments @("-C", $Cache, "rev-parse", ("refs/heads/" + $Base))
    if (-not $t.ok) { return (& $err $t.why) }
    $tip = $t.out
    # Every commit the walk needs must be in the branch's history as fetched. One that is not (a force-push took
    # it away, or it was merged into another branch) is said and left out; the others are still walked.
    $walk = New-Object System.Collections.ArrayList
    $skipped = New-Object System.Collections.ArrayList
    foreach ($e in $Entries) {
        $h = Invoke-HordeMergeTool -Tools $Tools -Name "Git" -With @(, [string[]]@("-C", $Cache, "merge-base", "--is-ancestor", $e.mergeSha, $tip))
        if ($h.code -eq 0) { [void]$walk.Add($e); continue }
        if ($h.code -lt 0) { return (& $err ("asking git whether " + $e.mergeSha + " (" + $e.pr + ") is in " + $Base + " failed: " + (Get-HordeMergeFirstLine ("" + $h.err)))) }
        [void]$skipped.Add([pscustomobject]@{ entry = $e; why = ("the merge " + $e.mergeSha + " (" + $e.pr + ") is not in the history of " + $Base + " " + $tip.Substring(0, 8) + " as fetched, so it cannot be walked") })
    }
    $noWalk = ($walk.Count -eq 0)
    if ($noWalk -and -not $Recheck) { return [pscustomobject]@{ status = "green"; reds = @(); skipped = @($skipped); checked = @(); why = "" } }
    $baseline = $tip
    if (-not $noWalk) {
        $baseline = $walk[0].firstParent
        if ($baseline -eq "") {
            $pp = Invoke-HordeMergeGit -Tools $Tools -What ("reading the first parent of " + $walk[0].mergeSha.Substring(0, 8)) -Arguments @("-C", $Cache, "rev-parse", ($walk[0].mergeSha + "^1"))
            if (-not $pp.ok) { return (& $err $pp.why) }
            $baseline = $pp.out
        }
    }
    $runs = [System.IO.Path]::Combine($WorkFolder, "runs")
    if ([System.IO.Directory]::Exists($runs)) { foreach ($stale in @([System.IO.Directory]::GetDirectories($runs))) { Remove-HordeMergeFolder -Path $stale -Tools $Tools } }
    $scratch = [System.IO.Path]::Combine($runs, ("owed-" + [guid]::NewGuid().ToString("N").Substring(0, 6)))
    $reds = New-Object System.Collections.ArrayList
    try {
        $r = Invoke-HordeMergeGit -Tools $Tools -What "cloning the scratch checkout" -Arguments @("-c", "core.longpaths=true", "clone", "--shared", "--no-checkout", "--quiet", $Cache, $scratch)
        if (-not $r.ok) { return (& $err $r.why) }
        $r = Invoke-HordeMergeGit -Tools $Tools -What "checking out the tip" -Arguments @("-C", $scratch, "-c", "core.longpaths=true", "checkout", "--detach", "--quiet", $tip)
        if (-not $r.ok) { return (& $err $r.why) }
        # THE GUARDS ARE THE TIP'S LIST AND THE BASELINE'S (M1, review of PR 375): the pre-merge run held a PR to
        # "the checked tree's list plus the base's, so a PR may add a guard but not drop one", and a day's merges
        # still are. A guard listed at the baseline and gone from the tip's list is RED, naming the first queued
        # merge whose list lacks it; it is not run (its script may be gone with it).
        $tipList = Get-HordeMergeGuardListAt -Tools $Tools -Cache $Cache -Commit $tip
        if (-not $tipList.ok) { return (& $err $tipList.why) }
        if ($null -eq $tipList.guards) { return (& $err ($Base + " " + $tip.Substring(0, 8) + " has no usable guard list, so nothing can say it is green: " + $tipList.why)) }
        $baseGuards = @()
        if (-not $noWalk) {
        $baseList = Get-HordeMergeGuardListAt -Tools $Tools -Cache $Cache -Commit $baseline
        if (-not $baseList.ok) { return (& $err $baseList.why) }
        if ($null -eq $baseList.guards) { & $say ("the baseline " + $baseline.Substring(0, 8) + " has no usable guard list (" + $baseList.why + "): only the tip's list is run") }
        else { $baseGuards = @($baseList.guards) }
        }
        $tipGuards = @($tipList.guards)
        & $say ($Repo + " " + $Base + ": " + $walk.Count + " merge(s) owed" + $(if ($noWalk) { " (a red is open here: the tip is run again)" } else { "" }) + "; the guards of " + $tip.Substring(0, 8) + ": " + ($tipGuards -join ", "))
        foreach ($g in $baseGuards) {
            if ($tipGuards -ccontains $g) { continue }
            $item = [pscustomobject]@{ kind = "dropped"; guard = $g; shells = @("the guard list"); entry = $null; note = ("it was listed at " + $baseline.Substring(0, 8) + " and is not in the list at the tip " + $tip.Substring(0, 8) + "; no queued merge is named, the list changed outside them"); lines = @(); base = $Base }
            foreach ($e in $walk) {
                $li = Get-HordeMergeGuardListAt -Tools $Tools -Cache $Cache -Commit $e.mergeSha
                if (-not $li.ok) { return (& $err $li.why) }
                if ($null -eq $li.guards -or $li.guards -cnotcontains $g) { $item.entry = $e; break }
            }
            & $say ($g + " was dropped from " + (Get-HordeGuardListPath) + ": RED")
            [void]$reds.Add($item)
        }
        foreach ($g in $tipGuards) {
            & $say ("running " + $g + " on the tip " + $tip.Substring(0, 8))
            $at = Invoke-HordeMergeGuardAt -Tools $Tools -Scratch $scratch -Commit $tip -Guard $g
            if (-not $at.ok) { return (& $err $at.why) }
            if (-not $at.red -and -not $at.absent) { & $say ($g + " is green at the tip"); continue }
            $item = [pscustomobject]@{ kind = "red"; guard = $g; shells = @($at.shells); entry = $null; note = ""; lines = @($at.lines); base = $Base }
            $tipKeys = @($at.shellKeys)
            if ($at.absent) {
                $item.kind = "missing"; $item.shells = @("the tree"); $item.lines = @("the guard script is not in the tree of " + $tip.Substring(0, 8))
                & $say ($g + " is listed but MISSING at the tip: looking for the merge behind it")
            } else { & $say ($g + " is RED at the tip in " + ($at.shells -join " and ") + ": looking for the merge behind it") }
            if ($noWalk) { [void]$reds.Add($item); continue }
            # THE WALK RUNS ONLY THE SHELLS RED AT THE TIP: a merge that was red in another shell and was fixed
            # is not the cause of this red (S8, review of PR 375).
            $bl = Invoke-HordeMergeGuardAt -Tools $Tools -Scratch $scratch -Commit $baseline -Guard $g -ShellKeys $tipKeys
            if (-not $bl.ok) { return (& $err $bl.why) }
            if ($bl.red) { $item.note = "red before today's first queued merge (at " + $baseline.Substring(0, 8) + "); no merge is named" }
            else {
                $found = $false
                $present = (-not $bl.absent)
                foreach ($e in $walk) {
                    $step = Invoke-HordeMergeGuardAt -Tools $Tools -Scratch $scratch -Commit $e.mergeSha -Guard $g -ShellKeys $tipKeys
                    if (-not $step.ok) { return (& $err $step.why) }
                    if ($step.red) { $item.entry = $e; $item.shells = @($step.shells); $item.lines = @($step.lines); $found = $true; break }
                    if ($step.absent -and $present) { $item.entry = $e; $item.shells = @("the tree"); $item.lines = @("the guard script is not in the tree of this merge"); $found = $true; break }
                    $present = (-not $step.absent)
                }
                if (-not $found -and $at.absent) { $item.note = "the guard script is in no queued merge's tree; it was never added, or was removed outside the queued merges; no merge is named" }
                elseif (-not $found) { $item.note = "green at every queued merge and red at the tip " + $tip.Substring(0, 8) + ": it broke after the last queued merge (a push or a merge not made by horde merge); no merge is named" }
            }
            [void]$reds.Add($item)
        }
    } finally { Remove-HordeMergeFolder -Path $scratch -Tools $Tools }
    $status = "green"
    if ($reds.Count -gt 0) { $status = "red" }
    return [pscustomobject]@{ status = $status; reds = @($reds); skipped = @($skipped); checked = @($walk); why = "" }
}

function Invoke-HordeMergeRunOwedRepo {
    # One repo's unchecked entries (-Entries, merge order), walked branch by branch: a merge is walked on the
    # branch it went into (the entry's baseRefName, the default branch when it has none). { status; reds;
    # skipped; checked; errors; why }: status red (any red), error (something could not be run, or nothing could
    # be walked), else green. checked: { entry; result } for each entry that was walked; errors: { base; why;
    # entries } for each branch that could not be run - those merges stay owed.
    param([Parameter(Mandatory = $true)][string]$Repo, [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Entries, [Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$WorkFolder, [string[]]$OpenBases = @())
    $failAll = { param([string]$Why) return [pscustomobject]@{ status = "error"; reds = @(); skipped = @(); checked = @(); ran = @(); errors = @([pscustomobject]@{ base = ""; why = $Why; entries = @($Entries) }); why = $Why } }
    $parts = $Repo.Split("/")
    $u = Invoke-HordeMergeTool -Tools $Tools -Name "Gh" -With @(, [string[]]@("repo", "view", $Repo, "--json", "url", "--jq", ".url"))
    $url = ("" + $u.out).Trim()
    if ($u.code -ne 0 -or $url -eq "") { return (& $failAll ("gh could not say where " + $Repo + " is: " + (Get-HordeMergeFirstLine ("" + $u.err)))) }
    $sym = Invoke-HordeMergeGit -Tools $Tools -What "asking for the default branch" -Arguments @("ls-remote", "--symref", $url, "HEAD")
    if (-not $sym.ok) { return (& $failAll $sym.why) }
    $bm = [regex]::Match($sym.out, 'ref:\s+refs/heads/(\S+)\s+HEAD')
    if (-not $bm.Success -or $bm.Groups[1].Value -cnotmatch $script:HordeMergeRefPattern) { return (& $failAll ("git did not say which branch is " + $Repo + "'s default")) }
    $default = $bm.Groups[1].Value
    $cache = [System.IO.Path]::Combine($WorkFolder, "repos", $parts[0], ($parts[1] + ".git"))
    if (-not [System.IO.Directory]::Exists($cache)) {
        $r = Invoke-HordeMergeGit -Tools $Tools -What "making the cache repository" -Arguments @("init", "--bare", "--quiet", $cache)
        if (-not $r.ok) { return (& $failAll $r.why) }
    }
    # THE DEFAULT BRANCH IS ALWAYS IN THE CACHE, whatever branches the merges went into: the guards compare with
    # origin/<default> (test-host-names reads origin/main), and a scratch checkout of a stacked branch has no
    # origin/main unless the cache holds main.
    $r = Invoke-HordeMergeGit -Tools $Tools -What "fetching the default branch" -Arguments @("-C", $cache, "fetch", "--no-tags", "--quiet", $url, ("+refs/heads/" + $default + ":refs/heads/" + $default))
    if (-not $r.ok) { return (& $failAll $r.why) }
    $groups = [ordered]@{}
    foreach ($e in $Entries) {
        $b = $default
        if ($e.base -ne "") { $b = $e.base }
        if (-not $groups.Contains($b)) { $groups[$b] = New-Object System.Collections.ArrayList }
        [void]$groups[$b].Add($e)
    }
    # A BRANCH WITH AN OPEN RED IS RUN AT ITS TIP even when no merge is owed on it (T-0347).
    foreach ($ob in @($OpenBases)) { if (-not $groups.Contains($ob)) { $groups[$ob] = New-Object System.Collections.ArrayList } }
    $reds = New-Object System.Collections.ArrayList
    $skipped = New-Object System.Collections.ArrayList
    $checked = New-Object System.Collections.ArrayList
    $errors = New-Object System.Collections.ArrayList
    $ran = New-Object System.Collections.ArrayList
    $rechecked = 0
    foreach ($b in @($groups.Keys)) {
        $isOpen = (@($OpenBases) -ccontains $b)
        $res = Invoke-HordeMergeRunOwedBase -Repo $Repo -Base $b -Cache $cache -Url $url -Entries @($groups[$b]) -Tools $Tools -WorkFolder $WorkFolder -Recheck:$isOpen
        if ($res.status -ceq "error") { [void]$errors.Add([pscustomobject]@{ base = $b; why = $res.why; entries = @($groups[$b]) }); continue }
        [void]$ran.Add($b)
        if ($isOpen) { $rechecked++ }
        foreach ($d in @($res.reds)) { [void]$reds.Add($d) }
        foreach ($s in @($res.skipped)) { [void]$skipped.Add($s) }
        foreach ($c in @($res.checked)) { [void]$checked.Add([pscustomobject]@{ entry = $c; result = $res.status }) }
    }
    $status = "green"
    $why = ""
    if ($reds.Count -gt 0) { $status = "red" }
    elseif ($errors.Count -gt 0) { $status = "error"; $why = (@($errors | ForEach-Object { $_.why }) -join "; ") }
    elseif ($checked.Count -eq 0 -and $rechecked -eq 0) { $status = "error"; $why = "no queued merge could be walked" }
    return [pscustomobject]@{ status = $status; reds = @($reds); skipped = @($skipped); checked = @($checked); ran = @($ran); errors = @($errors); why = $why }
}

function Invoke-HordeMergeRunOwed {
    # The nightly run (header). { exit; json; repos }: exit 0 all green, 1 any red, 2 could not run (a red
    # elsewhere still makes it 1). -Folder holds guards-owed.jsonl, guards-checked.jsonl and nightly\. It
    # schedules nothing and checks no idle: the caller does.
    #   A DAMAGED QUEUE LINE, or a merge that is not in its branch's history, is reported in every run with its
    #   line number or the line to add to guards-checked.jsonl, and the rest is still checked; the run ends 2
    #   for them only when nothing at all could be checked (S7, review of PR 375).
    #   THE QUEUE IS THIS MACHINE'S: -Folder is under this machine's Horde home, so a merge made on another
    #   machine is in that machine's queue and is not covered here (S4). The report says which machine and queue.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$WorkFolder, [Parameter(Mandatory = $true)][string]$Folder, [string]$Repo = "", [datetime]$Now = [datetime]::UtcNow)
    $say = $Tools["Say"]
    $owedPath = [System.IO.Path]::Combine($Folder, "guards-owed.jsonl")
    $checkedPath = [System.IO.Path]::Combine($Folder, "guards-checked.jsonl")
    $nowUtc = $Now.ToUniversalTime()
    $date = $nowUtc.ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
    $stamp = $nowUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
    $summary = New-Object System.Collections.ArrayList
    $finish = {
        param([int]$Code)
        $obj = [ordered]@{ exit = $Code; date = $date; repos = @($summary) }
        return [pscustomobject]@{ exit = $Code; json = (ConvertTo-Json -InputObject $obj -Compress -Depth 8); repos = @($summary) }
    }
    if ($Repo -ne "" -and -not (Test-HordeMergeOwedRepo -Repo $Repo)) { & $say ("'" + $Repo + "' is not a repository: OWNER/REPO"); return (& $finish 2) }
    # MERGES BEGUN AND NEVER SETTLED are asked of GitHub first, and the ones that were merged join the queue (T-0347).
    $intentRun = Resolve-HordeMergeIntents -Tools $Tools -Folder $Folder -Repo $Repo -Now $nowUtc
    $owedText = ""
    if ([System.IO.File]::Exists($owedPath)) {
        try { $owedText = Read-HordeMergeFileText -Path $owedPath } catch { & $say ("could not read " + $owedPath + ": " + $_.Exception.Message); return (& $finish 2) }
    }
    $checkedText = ""
    if ([System.IO.File]::Exists($checkedPath)) {
        try { $checkedText = Read-HordeMergeFileText -Path $checkedPath } catch { & $say ("could not read " + $checkedPath + ": " + $_.Exception.Message); return (& $finish 2) }
    }
    # THE OPEN REDS (T-0347): a red is reported once and its merges are marked checked, so without this record the next
    # quiet night found nothing owed and read a red main as green. One that cannot be read is not green: exit 2.
    $redPath = [System.IO.Path]::Combine($Folder, $script:HordeMergeRedFileName)
    $openRed = Read-HordeMergeOpenReds -Path $redPath
    if (-not $openRed.ok) { & $say ("COULD NOT READ THE RECORD OF OPEN REDS: " + $openRed.why + ". A record that cannot be read is not green, so this run ends 2 and checks nothing; fix or remove the file by hand"); return (& $finish 2) }
    $owed = Read-HordeMergeOwedEntries -Text $owedText
    $checked = Read-HordeMergeCheckedShas -Text $checkedText
    $worst = 0
    if (-not $intentRun.ok) { $worst = 2 }
    $unchecked = 0
    if ($owed.bad.Count -gt 0) {
        & $say ("WARNING: " + $owedPath + " has " + $owed.bad.Count + " line(s) that are not a usable entry (line " + (($owed.bad | Select-Object -First 10) -join ", ") + "): those merges are NOT checked, and this is said again in every run until the file is fixed by hand; the other entries are still checked")
        $unchecked += $owed.bad.Count
    }
    $byRepo = [ordered]@{}
    foreach ($e in $owed.entries) {
        if ($Repo -ne "" -and $e.repo -cne $Repo.ToLowerInvariant()) { continue }
        if ($checked.ContainsKey($e.mergeSha)) { continue }
        if (-not $byRepo.Contains($e.repo)) { $byRepo[$e.repo] = New-Object System.Collections.ArrayList }
        [void]$byRepo[$e.repo].Add($e)
    }
    foreach ($okey in @($openRed.reds.Keys | Sort-Object)) {
        $orec = $openRed.reds[$okey]
        if ($Repo -ne "" -and $orec.repo -cne $Repo.ToLowerInvariant()) { continue }
        if (-not $byRepo.Contains($orec.repo)) { $byRepo[$orec.repo] = New-Object System.Collections.ArrayList }
    }
    if ($byRepo.Count -eq 0) {
        & $say "nothing is owed: every queued merge has been checked"
        if ($unchecked -gt 0) { $worst = 2 }
        return (& $finish $worst)
    }
    $anyRed = $false
    $anyChecked = $false
    foreach ($r in @($byRepo.Keys)) {
        $entries = @($byRepo[$r])
        $openBases = @($openRed.reds.Values | Where-Object { $_.repo -ceq $r } | ForEach-Object { $_.base })
        $res = Invoke-HordeMergeRunOwedRepo -Repo $r -Entries $entries -Tools $Tools -WorkFolder $WorkFolder -OpenBases $openBases
        $text = New-Object System.Collections.ArrayList
        [void]$text.Add("guards report for " + $r + ", " + $stamp + " (UTC)")
        [void]$text.Add("queue: " + $owedPath + " on " + [Environment]::MachineName + " - this machine's queue only; merges made on another machine are in that machine's queue and are not covered by this report")
        $redJson = @()
        foreach ($er in @($res.errors)) {
            [void]$text.Add("COULD NOT RUN" + $(if ($er.base -ne "") { " on " + $er.base } else { "" }) + ": " + $er.why)
            if ($openRed.reds.ContainsKey($r + "|" + $er.base)) { [void]$text.Add("STILL OPEN: the red on " + $er.base + " (since " + $openRed.reds[$r + "|" + $er.base].since + ") stays open until the guards run green there. If the branch is gone for good, remove its record from " + $redPath) }
            [void]$text.Add("" + @($er.entries).Count + " merge(s) stay owed and will be tried again; a guard that cannot run or hangs reads as 'could not run' (exit 2 in every run until it runs), never as red or green")
            # THE WAY OUT (T-0347): a branch that is gone (a stacked PR's base, deleted after its merge) can never be
            # fetched, so its merges stayed owed and ended every night 2 with no word of how to stop it. Each merge gets
            # the line that gives it up, as a merge skipped for not being in the history does.
            $shownErr = 0
            foreach ($ee in @($er.entries)) {
                if ($shownErr -ge $script:HordeMergeGiveUpLines) { [void]$text.Add("    ... and " + (@($er.entries).Count - $shownErr) + " more owed merge(s) of this branch"); break }
                $shownErr++
                $clearErr = ConvertTo-Json -InputObject ([ordered]@{ repo = $r; mergeSha = $ee.mergeSha; at = $stamp; result = "given-up" }) -Compress
                [void]$text.Add("STAYS OWED: " + $ee.pr + " (mergeSha " + $ee.mergeSha + ") is tried again in every run. If it can never run (its branch was deleted), give it up by adding this line to " + $checkedPath + ": " + $clearErr)
            }
        }
        $skippedJson = @()
        foreach ($sk in @($res.skipped)) {
            $clear = ConvertTo-Json -InputObject ([ordered]@{ repo = $r; mergeSha = $sk.entry.mergeSha; at = $stamp; result = "given-up" }) -Compress
            [void]$text.Add("NOT CHECKED: " + $sk.why + ". It is reported in every run; to give it up, add this line to " + $checkedPath + ": " + $clear)
            $skippedJson += , ([ordered]@{ pr = $sk.entry.pr; mergeSha = $sk.entry.mergeSha; why = $sk.why })
        }
        $nChecked = @($res.checked).Count
        if (@($res.reds).Count -eq 0 -and $nChecked -gt 0) {
            if (@($res.errors).Count -eq 0 -and @($res.skipped).Count -eq 0) { [void]$text.Add("all green over " + $nChecked + " merges") }
            else { [void]$text.Add("green over " + $nChecked + " merges; the others are listed above and were not checked") }
        }
        $redBases = @(@($res.reds) | ForEach-Object { $_.base })
        $backGreen = @(@($res.ran) | Where-Object { $openRed.reds.ContainsKey($r + "|" + $_) -and $redBases -cnotcontains $_ })
        foreach ($gb in $backGreen) {
            $grec = $openRed.reds[$r + "|" + $gb]
            $was = $grec.note
            if ($null -ne $grec.merge) { $was = "first red at " + (Format-HordeMergeNamedMerge -Merge $grec.merge) }
            [void]$text.Add("GREEN AGAIN: " + $gb + " was red since " + $grec.since + " (" + $was + ") and every guard is green at its tip now; the open red is cleared")
        }
        foreach ($d in @($res.reds)) {
            $who = $d.note
            $mj = $null
            $rec = $null
            if ($openRed.reds.ContainsKey($r + "|" + $d.base)) { $rec = $openRed.reds[$r + "|" + $d.base] }
            if ($null -ne $d.entry) {
                $verb = "first red at the merge of "
                if ($d.kind -ceq "dropped") { $verb = "dropped from the list by the merge of " }
                $who = $verb + $d.entry.pr + " (task " + $d.entry.task + ", by " + $d.entry.by + ", mergeSha " + $d.entry.mergeSha + ") on " + $d.base + "; its owner fixes it first thing"
                $mj = [ordered]@{ pr = $d.entry.pr; task = $d.entry.task; by = $d.entry.by; mergeSha = $d.entry.mergeSha }
            } elseif ($d.kind -ceq "dropped") { $who = $d.note }
            # STILL RED: the record keeps the merge that first turned it red. A walk that names a later merge is told too.
            if ($null -ne $rec) {
                if ($null -eq $d.entry) {
                    $orig = $rec.note
                    if ($null -ne $rec.merge) { $orig = "first red at " + (Format-HordeMergeNamedMerge -Merge $rec.merge) + " on " + $d.base + "; its owner fixes it first thing"; $mj = [ordered]@{ pr = $rec.merge.pr; task = $rec.merge.task; by = $rec.merge.by; mergeSha = $rec.merge.mergeSha } }
                    $who = "STILL RED since " + $rec.since + ": " + $orig + $(if ($d.note -ne "" -and $d.note -cne $rec.note) { " (this run: " + $d.note + ")" } else { "" })
                } else { $who += " (the red has been open since " + $rec.since + ")" }
            }
            if ($d.kind -ceq "dropped") { [void]$text.Add("RED " + $d.guard + " dropped from " + (Get-HordeGuardListPath) + ": " + $who) }
            else { [void]$text.Add("RED " + $d.guard + " in " + ($d.shells -join " and ") + ": " + $who) }
            foreach ($l in @($d.lines | Select-Object -First 10)) { [void]$text.Add("    " + $l) }
            $redJson += , ([ordered]@{ kind = $d.kind; guard = $d.guard; shells = @($d.shells); merge = $mj; note = $d.note; base = $d.base; open = ($null -ne $rec); since = $(if ($null -ne $rec) { $rec.since } else { $stamp }) })
        }
        if (@($res.reds).Count -gt 0) { [void]$text.Add("(" + $nChecked + " merges were walked; all are now checked)") }
        $reportPath = [System.IO.Path]::Combine($Folder, "nightly", ($date + "-" + $r.Replace("/", "-") + ".txt"))
        # THE REPORT IS WRITTEN BEFORE ANY MERGE IS MARKED CHECKED, and a report that could not be written marks
        # none: a marked merge is never run again, and the finding would then live only in this run's output (S6).
        $wrote = Add-HordeMergeLine -Path $reportPath -Line (($text -join "`n") + "`n")
        foreach ($l in $text) { & $say $l }
        $status = $res.status
        $why = $res.why
        if (-not $wrote.ok) {
            & $say ("COULD NOT WRITE THE REPORT: " + $wrote.detail + " - no merge is marked checked, so they are all run again")
            $status = "error"; $why = "the report could not be written: " + $wrote.detail
            $worst = 2
        } else {
            # THE OPEN-RED RECORD IS WRITTEN BEFORE ANY MERGE IS MARKED CHECKED, like the report: a red whose record was
            # not written would read green the next quiet night, so a failure leaves every merge owed (T-0347).
            $dirty = $false
            foreach ($rb in @($redBases | Select-Object -Unique)) {
                $first = @(@($res.reds) | Where-Object { $_.base -ceq $rb })[0]
                $key = $r + "|" + $rb
                $guardNames = @(@($res.reds) | Where-Object { $_.base -ceq $rb } | ForEach-Object { $_.guard } | Select-Object -Unique)
                if ($openRed.reds.ContainsKey($key)) { $openRed.reds[$key].guards = @($guardNames); $dirty = $true; continue }
                $named = @(@($res.reds) | Where-Object { $_.base -ceq $rb -and $null -ne $_.entry })
                $mrec = $null
                $nrec = $first.note
                if ($named.Count -gt 0) { $mrec = [pscustomobject]@{ pr = $named[0].entry.pr; task = $named[0].entry.task; by = $named[0].entry.by; mergeSha = $named[0].entry.mergeSha } }
                $openRed.reds[$key] = [pscustomobject]@{ repo = $r; base = $rb; since = $stamp; guards = @($guardNames); merge = $mrec; note = $nrec }
                $dirty = $true
            }
            foreach ($gb in $backGreen) { $openRed.reds.Remove($r + "|" + $gb); $dirty = $true }
            $stateWrote = [pscustomobject]@{ ok = $true; detail = "" }
            if ($dirty) { $stateWrote = Write-HordeMergeOpenReds -Path $redPath -Reds $openRed.reds }
            if (-not $stateWrote.ok) {
                & $say ("COULD NOT RECORD THE OPEN RED: " + $stateWrote.detail + " - no merge is marked checked, so they are all run again")
                $status = "error"; $why = "the record of open reds could not be written: " + $stateWrote.detail
                $worst = 2
            } else {
            # CHECKED ONLY WHEN IT RAN: a branch that could not run keeps its merges owed.
            $failed = $false
            foreach ($c in @($res.checked)) {
                $l = ConvertTo-Json -InputObject ([ordered]@{ repo = $r; mergeSha = $c.entry.mergeSha; at = $stamp; result = $c.result }) -Compress
                $ap = Add-HordeMergeLine -Path $checkedPath -Line $l
                if (-not $ap.ok) { $failed = $true; & $say ("COULD NOT MARK AS CHECKED: " + $ap.detail); & $say ("add this line to guards-checked.jsonl by hand: " + $l) }
            }
            if ($failed) { $status = "error"; $why = "the checked marks were not all written; they would be checked again"; $worst = 2 }
            elseif ($nChecked -gt 0) { $anyChecked = $true }
            if (@($res.errors).Count -gt 0) { $worst = 2 }
            }
        }
        if (@($res.reds).Count -gt 0) { $anyRed = $true }
        $unchecked += @($res.skipped).Count
        [void]$summary.Add([ordered]@{ repo = $r; status = $status; merges = $entries.Count; checked = $nChecked; skipped = @($skippedJson); reds = @($redJson); report = $reportPath; why = $why })
    }
    if ($unchecked -gt 0 -and -not $anyChecked -and $worst -lt 2) { $worst = 2 }
    $code = $worst
    if ($anyRed) { $code = 1 }
    return (& $finish $code)
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
    param([Parameter(Mandatory = $true)]$Values, [Parameter(Mandatory = $true)][scriptblock]$Tell, [Parameter(Mandatory = $true)][scriptblock]$Mail, $MachinePsModulePath = $null, [string]$OwedFolder = "")
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
    $appendLine = ${function:Add-HordeMergeLine}
    $owedPath = ""
    $intentPath = ""
    if ($OwedFolder -ne "") { $owedPath = [System.IO.Path]::Combine($OwedFolder, "guards-owed.jsonl"); $intentPath = [System.IO.Path]::Combine($OwedFolder, $script:HordeMergeIntentFileName) }
    return @{
        Gh = { param([string[]]$Arguments) return (& $runProgram -Program $gh -Arguments $Arguments -Directory $place) }.GetNewClosure()
        Git = { param([string[]]$Arguments) return (& $runProgram -Program $git -Arguments $Arguments -Directory $place) }.GetNewClosure()
        # -Shell is "5.1" or "7" (the shells table). PowerShell 7 that is not there is a red guard with the
        # path named, never a skipped one.
        Guard = {
            param([string]$Checkout, [string]$Suite, [string]$Which)
            $program = $shell
            if ($Which -ceq "7") {
                $program = $shell7
                if (-not [System.IO.File]::Exists($program)) { return [pscustomobject]@{ code = -1; out = ""; err = ("PowerShell 7 is not at " + $program + "; install the MSI or set guardShell7 in the merge settings") } }
            }
            elseif ($Which -cne "5.1") { return [pscustomobject]@{ code = -1; out = ""; err = ("the guard shell '" + $Which + "' is not 5.1 or 7") } }
            $env1 = & $guardEnvFor -Shell $Which -MachinePsModulePath ("" + $machinePath)
            return (& $runProgram -Program $program -Arguments @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", [System.IO.Path]::Combine($Checkout, $Suite)) -Directory $Checkout -Environment $env1)
        }.GetNewClosure()
        Ledger = { param([string[]]$Arguments) return (& $runProgram -Program $ledgerProgram -Arguments (@($ledgerScript) + @($Arguments)) -Directory $place) }.GetNewClosure()
        LedgerLine = { param([string[]]$Arguments) return (& $formatLine -Program $ledgerProgram -Script $ledgerScript -Arguments $Arguments) }.GetNewClosure()
        # The daytime queue (-Guards later): one line appended to <HORDE_HOME>\merge\guards-owed.jsonl.
        Owed = { param([string]$Line) if ($owedPath -eq "") { return [pscustomobject]@{ ok = $false; detail = "no merge folder was given, so there is nowhere to queue the merge" } }; return (& $appendLine -Path $owedPath -Line $Line) }.GetNewClosure()
        # The intent log (T-0347): written before a daytime merge, settled after its queue line.
        Intent = { param([string]$Line) if ($intentPath -eq "") { return [pscustomobject]@{ ok = $false; detail = "no merge folder was given, so there is nowhere to record the intent" } }; return (& $appendLine -Path $intentPath -Line $Line) }.GetNewClosure()
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
$script:HordeMergeTellNeeds = @("body.untyped", "idempotent.post", "receipt.receiver")
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
