# cli/ServicesAct - the hands of the supervisor of services: everything a pass DOES to the machine.
# Read a process, read and move a checkout, check a new revision in a scratch copy, start, ask to
# stop, end. core/Services.ps1 decides and touches nothing; this file touches and decides nothing.
#
# WHY HERE. It starts programs - the revision tool, a horde command, the service itself - and core's
# rules are pure (core/Services.ps1) while the port's adapters own what differs by system
# (core/ServiceHostPort.ps1). What is the same on every system and still starts something lives in
# cli/, as the relay runner's loop does (cli/RelayRun.ps1).
#
# AN UPDATE RUNS NEW CODE UNATTENDED, SO EVERY STEP IS HELD TO THESE:
#   - ONLY THE CONFIGURED REMOTE AND BRANCH. The fetch names both and writes one ref,
#     refs/remotes/<remote>/<branch>; the wanted revision is read from that ref and nowhere else; and
#     before the checkout moves, the revision must still be what that ref says.
#   - FAST-FORWARD ONLY. The wanted revision must descend from what is checked out
#     (merge-base --is-ancestor), checked when the update is considered and again when it is applied.
#   - NEVER OVER LOCAL CHANGES. A checkout with a changed tracked file is left exactly as it is; the
#     move itself is `checkout --detach`, which refuses to write over a change, and there is no reset,
#     no clean and no force anywhere in this file.
#   - ONLY A DETACHED CHECKOUT IS MOVED. A checkout on a branch is somebody's work; moving it would
#     move their branch, or leave it behind them. A supervised checkout is a deployment, and detached.
#   - NOTHING FROM THE FETCHED TREE RUNS BEFORE THE SELF-CHECK, and the self-check runs it only in a
#     scratch copy with a scratch Horde home: the live checkout, the live home and the running
#     service are not touched by it. The copy is made with a private index file (read-tree, then
#     checkout-index into a temp folder), so not even the checkout's own index is written.
#   - NOTHING IS WRITTEN outside the supervisor's Horde home, the service's own checkout, and temp.
#   - THE REVISION TOOL NEVER PROMPTS. It runs with its terminal prompt off, so a remote that wants a
#     password fails at once instead of waiting on a console nobody is at.
#
# EVERY CALL OF ANOTHER PROGRAM HAS A TIME LIMIT, and a program that passes it is ended and counted
# as failed: one call that never returns would freeze the pass, and the pass is what notices
# everything else.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")
function Get-HordeServiceShell {
    # The shell a horde command is run in from here: on Windows, Windows PowerShell from the system
    # folder by its path, never whatever a search path finds first; elsewhere the one on the path.
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) { return [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe") }
    return "pwsh"
}

function Invoke-HordeServiceProgram {
    # Run one program to its end, with a time limit: { started; code; out; err; timedOut }. Its
    # arguments are separate texts, joined by the port's quoting (no shell reads them). Both output
    # streams are read as they come, so a program that fills one cannot stall on it. A program that
    # passes -TimeoutSeconds is ended - it alone, by the handle held since it started.
    # -DropEnvironment: prefixes of environment variables the program must NOT inherit from this
    # process; they are taken out before -Environment is put in.
    param([Parameter(Mandatory = $true)][string]$Program, [string[]]$Arguments = @(), [string]$WorkingDirectory = "", [hashtable]$Environment = @{}, [int]$TimeoutSeconds = 20, [string[]]$DropEnvironment = @())
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Program
    $psi.Arguments = (@($Arguments | ForEach-Object { ConvertTo-HordeServiceArgument -Text ("" + $_) }) -join " ")
    if ($WorkingDirectory -ne "") { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    if (@($DropEnvironment).Count -gt 0) {
        foreach ($k in @($psi.EnvironmentVariables.Keys)) { foreach ($prefix in @($DropEnvironment)) { if (("" + $k).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $psi.EnvironmentVariables.Remove("" + $k); break } } }
    }
    foreach ($k in @($Environment.Keys)) { $psi.EnvironmentVariables["" + $k] = "" + $Environment[$k] }
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) }
    catch { return [pscustomobject]@{ started = $false; code = -1; out = ""; err = ("it could not be started: " + $_.Exception.GetBaseException().Message); timedOut = $false } }
    try {
        # Input is closed at once: a program that asks a question reads the end of input, not a console.
        try { $p.StandardInput.Close() } catch { }
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit([System.Math]::Max(1, $TimeoutSeconds) * 1000)) {
            try { $p.Kill() } catch { }
            [void]$p.WaitForExit(5000)
            return [pscustomobject]@{ started = $true; code = -1; out = ""; err = ("it did not finish within " + $TimeoutSeconds + " s and was ended"); timedOut = $true }
        }
        # The plain WaitForExit after the timed one lets the two readers reach the end of their streams.
        $p.WaitForExit()
        return [pscustomobject]@{ started = $true; code = [int]$p.ExitCode; out = "" + $outTask.Result; err = "" + $errTask.Result; timedOut = $false }
    } finally { $p.Dispose() }
}

function Get-HordeServiceGitProgram {
    # The revision tool BY ITS FULL PATH, found once a process: "" when it is not installed. A bare
    # name is answered by whatever the search path - and the current folder - offers first; this
    # program moves checkouts and decides what code runs unattended, so it is named exactly.
    if ($null -eq (Get-Variable -Name HordeServiceGitProgram -Scope Script -ErrorAction SilentlyContinue)) {
        $found = ""
        try { $found = "" + (@(Get-Command -Name "git" -CommandType Application -ErrorAction Stop) | Select-Object -First 1).Source } catch { $found = "" }
        if ($found -ne "" -and (-not [System.IO.Path]::IsPathRooted($found) -or -not [System.IO.File]::Exists($found))) { $found = "" }
        $script:HordeServiceGitProgram = $found
    }
    return $script:HordeServiceGitProgram
}

function Test-HordeServiceCheckoutIsItsOwn {
    # Why -Checkout is not the top of a checkout of its own, or "" when it is (safety review of the
    # first build, item 5). `git -C <folder>` does not need the folder to be a checkout: it walks UP
    # until it finds one, so a folder that has lost its .git - or was never one - would have the
    # revision tool fetch into, check out over and report on the repository ABOVE it. The top the
    # tool itself names must be this folder. Compared resolved and without case, as the file system
    # compares; a folder reached through another name (a link, a mapped drive) is refused, which errs
    # towards doing nothing. An answer of "it is" is remembered for the life of the process.
    param([Parameter(Mandatory = $true)][string]$Checkout, [int]$TimeoutSeconds = 20)
    $full = ""
    try { $full = [System.IO.Path]::GetFullPath($Checkout).TrimEnd('\', '/') } catch { return ("its checkout " + $Checkout + " is not a path") }
    if ($null -eq (Get-Variable -Name HordeServiceOwnCheckouts -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeServiceOwnCheckouts = @{} }
    if ($script:HordeServiceOwnCheckouts.ContainsKey($full.ToUpperInvariant())) { return "" }
    if (-not [System.IO.Directory]::Exists($full)) { return ("its checkout " + $full + " is not there") }
    $top = Invoke-HordeServiceGit -Checkout $full -Arguments @("rev-parse", "--show-toplevel") -TimeoutSeconds $TimeoutSeconds -Unchecked
    if (-not $top.ok -or $top.out -eq "") { return ("its checkout " + $full + " is not a checkout" + $(if ($top.detail -ne "") { " (" + $top.detail + ")" } else { "" })) }
    $named = ""
    try { $named = [System.IO.Path]::GetFullPath(($top.out -replace '/', '\')).TrimEnd('\', '/') } catch { $named = $top.out }
    if ($named.ToUpperInvariant() -cne $full.ToUpperInvariant()) { return ("its checkout " + $full + " is not the top of a checkout of its own: the revision tool would act on " + $named) }
    $script:HordeServiceOwnCheckouts[$full.ToUpperInvariant()] = $true
    return ""
}

function Invoke-HordeServiceGit {
    # One call of the revision tool in a checkout: { ok; code; out; detail }. detail is one line for
    # a reason, with anything secret-shaped hidden: the tool's errors can quote a remote's address.
    # -Unchecked is for the one call that IS the check below; nothing else passes it.
    param([Parameter(Mandatory = $true)][string]$Checkout, [Parameter(Mandatory = $true)][string[]]$Arguments, [int]$TimeoutSeconds = 20, [hashtable]$Environment = @{}, [switch]$Unchecked)
    $git = Get-HordeServiceGitProgram
    if ($git -eq "") { return [pscustomobject]@{ ok = $false; code = -1; out = ""; detail = "the revision tool (git) was not found on this machine" } }
    # ON THIS CHECKOUT AND NO OTHER: every call is preceded by the proof that the folder is the top
    # of a checkout of its own (Test-HordeServiceCheckoutIsItsOwn), so no caller can forget it.
    if (-not $Unchecked) {
        $notOwn = Test-HordeServiceCheckoutIsItsOwn -Checkout $Checkout -TimeoutSeconds $TimeoutSeconds
        if ($notOwn -ne "") { return [pscustomobject]@{ ok = $false; code = -1; out = ""; detail = (Protect-HordeServiceText $notOwn) } }
    }
    # Never a prompt (header): GIT_TERMINAL_PROMPT=0 makes a credential question a failure.
    $env2 = @{ GIT_TERMINAL_PROMPT = "0"; GCM_INTERACTIVE = "never" }
    foreach ($k in @($Environment.Keys)) { $env2["" + $k] = "" + $Environment[$k] }
    # --no-optional-locks: a read (status, above all) must not rewrite the checkout's index behind a
    # person or a tool working in it; a background reader takes no lock it does not need.
    # NOTHING OF THE CALLER'S GIT ENVIRONMENT IS INHERITED. GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE and
    # their kin, left in the shell of whoever runs `horde rollout`, would point the tool at another
    # repository whatever -C says. Every GIT_ variable is taken out; the few this file means are put in.
    $r = Invoke-HordeServiceProgram -Program $git -Arguments (@("--no-optional-locks", "-C", $Checkout) + @($Arguments)) -Environment $env2 -TimeoutSeconds $TimeoutSeconds -DropEnvironment @("GIT_")
    $detail = ""
    if (-not $r.started -or $r.timedOut -or $r.code -ne 0) { $detail = Protect-HordeServiceText ("git " + $Arguments[0] + ": " + $(if ($r.err.Trim() -ne "") { $r.err } else { "exit " + $r.code })) }
    return [pscustomobject]@{ ok = [bool]($r.started -and -not $r.timedOut -and $r.code -eq 0); code = $r.code; out = ("" + $r.out).Trim(); detail = $detail }
}

function Get-HordeServiceRemoteRef {
    param([Parameter(Mandatory = $true)]$Definition)
    return ("refs/remotes/" + $Definition.follow.remote + "/" + $Definition.follow.branch)
}

function Update-HordeServiceRemote {
    # Ask the configured remote for the configured branch, and nothing else: { ok; detail }. One ref
    # is written, the remote-tracking one; no tag is fetched, and the checkout is not touched.
    param([Parameter(Mandatory = $true)]$Definition, [int]$TimeoutSeconds = 20)
    $ref = Get-HordeServiceRemoteRef -Definition $Definition
    $r = Invoke-HordeServiceGit -Checkout $Definition.checkout -Arguments @("fetch", "--no-tags", "--quiet", $Definition.follow.remote, ("+refs/heads/" + $Definition.follow.branch + ":" + $ref)) -TimeoutSeconds $TimeoutSeconds
    return [pscustomobject]@{ ok = $r.ok; detail = $r.detail }
}

function Get-HordeServiceCheckoutState {
    # What the checkout is on and what the remote wants, as the decision reads them:
    #   { checkout; wanted }  two core/Tristate.ps1 answers (core/Services.ps1, New-HordeServiceObserved)
    # CHEAP WHEN NOTHING IS WAITING: one call of the revision tool reads both revisions, and only when
    # they differ - or the service runs something other than what is wanted - are the three further
    # questions asked (is it detached, is it clean, is the wanted one a fast-forward). A pass runs
    # every minute for every service, and a process start is the dearest thing a pass does.
    # -Full: after a move of the checkout that was not seen to end (core/Services.ps1, $unsafe) the
    # cheap answer is not enough. The value then also says spotless: no changed tracked file AND no
    # untracked one - a move that was cut short leaves the new revision's files lying untracked.
    param([Parameter(Mandatory = $true)]$Definition, [string]$RunningRevision = "", [int]$TimeoutSeconds = 20, [switch]$Full)
    $dir = $Definition.checkout
    $ref = Get-HordeServiceRemoteRef -Definition $Definition
    $head = ""; $wanted = ""; $wantedWhy = ""
    $both = Invoke-HordeServiceGit -Checkout $dir -Arguments @("rev-parse", "--verify", "--quiet", "HEAD^{commit}") -TimeoutSeconds $TimeoutSeconds
    if (-not $both.ok -or $both.out -cnotmatch '\A[0-9a-f]{40}\z') { $why = "its checkout " + $dir + " could not be read" + $(if ($both.detail -ne "") { " (" + $both.detail + ")" } else { "" }); return [pscustomobject]@{ checkout = (New-HordeUnknown -Reason $why); wanted = (New-HordeUnknown -Reason $why) } }
    $head = $both.out
    $tip = Invoke-HordeServiceGit -Checkout $dir -Arguments @("rev-parse", "--verify", "--quiet", ($ref + "^{commit}")) -TimeoutSeconds $TimeoutSeconds
    if ($tip.ok -and $tip.out -cmatch '\A[0-9a-f]{40}\z') { $wanted = $tip.out } else { $wantedWhy = "the checkout has no " + $ref + " yet: the remote has not been fetched" }
    if ($Full) {
        $all = Invoke-HordeServiceGit -Checkout $dir -Arguments @("status", "--porcelain") -TimeoutSeconds $TimeoutSeconds
        if (-not $all.ok) { $why = "whether its checkout is whole could not be read (" + $all.detail + ")"; return [pscustomobject]@{ checkout = (New-HordeUnknown -Reason $why); wanted = (New-HordeUnknown -Reason $why) } }
        $tracked = Invoke-HordeServiceGit -Checkout $dir -Arguments @("status", "--porcelain", "--untracked-files=no") -TimeoutSeconds $TimeoutSeconds
        $onBranch = Invoke-HordeServiceGit -Checkout $dir -Arguments @("symbolic-ref", "--quiet", "--short", "HEAD") -TimeoutSeconds $TimeoutSeconds
        $c = New-HordeKnown -Value ([pscustomobject]@{ head = $head; detached = [bool](-not $onBranch.ok); clean = [bool]($tracked.ok -and $tracked.out -eq ""); branch = $(if ($onBranch.ok) { $onBranch.out } else { "" }); spotless = [bool]($all.out -eq "") })
        if ($wanted -eq "") { return [pscustomobject]@{ checkout = $c; wanted = (New-HordeUnknown -Reason $wantedWhy) } }
        $ahead = Invoke-HordeServiceGit -Checkout $dir -Arguments @("merge-base", "--is-ancestor", $head, $wanted) -TimeoutSeconds $TimeoutSeconds
        return [pscustomobject]@{ checkout = $c; wanted = (New-HordeKnown -Value ([pscustomobject]@{ revision = $wanted; fastForward = [bool]$ahead.ok })) }
    }
    if ($wanted -eq "" -or ($wanted -ceq $head -and ($RunningRevision -eq "" -or $RunningRevision -ceq $wanted))) {
        $c = New-HordeKnown -Value ([pscustomobject]@{ head = $head; detached = $true; clean = $true; branch = "" })
        if ($wanted -eq "") { return [pscustomobject]@{ checkout = $c; wanted = (New-HordeUnknown -Reason $wantedWhy) } }
        return [pscustomobject]@{ checkout = $c; wanted = (New-HordeKnown -Value ([pscustomobject]@{ revision = $wanted; fastForward = $true })) }
    }
    # Something is waiting: the three further questions.
    $branch = Invoke-HordeServiceGit -Checkout $dir -Arguments @("symbolic-ref", "--quiet", "--short", "HEAD") -TimeoutSeconds $TimeoutSeconds
    $status = Invoke-HordeServiceGit -Checkout $dir -Arguments @("status", "--porcelain", "--untracked-files=no") -TimeoutSeconds $TimeoutSeconds
    if (-not $status.ok) { $why = "whether its checkout has local changes could not be read (" + $status.detail + ")"; return [pscustomobject]@{ checkout = (New-HordeUnknown -Reason $why); wanted = (New-HordeKnown -Value ([pscustomobject]@{ revision = $wanted; fastForward = $false })) } }
    # symbolic-ref exits 1, silently, on a detached checkout; any other failure is not an answer.
    if (-not $branch.ok -and $branch.code -ne 1) { $why = "whether its checkout is on a branch could not be read (" + $branch.detail + ")"; return [pscustomobject]@{ checkout = (New-HordeUnknown -Reason $why); wanted = (New-HordeKnown -Value ([pscustomobject]@{ revision = $wanted; fastForward = $false })) } }
    $forward = Invoke-HordeServiceGit -Checkout $dir -Arguments @("merge-base", "--is-ancestor", $head, $wanted) -TimeoutSeconds $TimeoutSeconds
    # --is-ancestor exits 0 for yes and 1 for no; anything else did not answer, and is read as no.
    return [pscustomobject]@{
        checkout = (New-HordeKnown -Value ([pscustomobject]@{ head = $head; detached = [bool](-not $branch.ok); clean = [bool]($status.out -eq ""); branch = $(if ($branch.ok) { $branch.out } else { "" }) }))
        wanted = (New-HordeKnown -Value ([pscustomobject]@{ revision = $wanted; fastForward = [bool]$forward.ok }))
    }
}

function Test-HordeServiceScriptsParse {
    # Does every PowerShell file under -Tree parse? "" when all do, else the first that does not. The
    # files are READ by the parser and never run. Folders named test are skipped: fixtures hold broken
    # files on purpose.
    param([Parameter(Mandatory = $true)][string]$Tree)
    $root = [System.IO.Path]::GetFullPath($Tree).TrimEnd('\', '/')
    foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.ps1" | Where-Object { $_.Extension -ieq ".ps1" })) {
        $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
        if (@($rel -split '/') -contains "test") { continue }
        $tokens = $null; $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { return ($rel + " does not parse (line " + $errors[0].Extent.StartLineNumber + ")") }
    }
    return ""
}

function Test-HordeServiceRevision {
    # THE SELF-CHECK of a new revision, before anything is stopped: { ok; detail }. In order, each a
    # reason to refuse:
    #   1. it is what refs/remotes/<remote>/<branch> names now - the configured remote's, no other;
    #   2. it descends from what is checked out: a fast-forward;
    #   3. its tree is written to a scratch folder in temp through a PRIVATE index (header);
    #   4. every PowerShell file in that tree parses - read, not run, so a file `version` never loads
    #      (the runner's loop, say) cannot be broken and pass;
    #   5. for a horde service, `horde version` runs from the scratch tree against a scratch, empty
    #      Horde home, exits 0 and names a version, within -CheckSeconds;
    #   6. and, when the tree has it, `horde services status` runs from it the same way (below).
    # The scratch folder is removed whatever happened. A service that is not a horde command gets
    # steps 1 to 4: there is no command of its own that is known to be safe to run as a check.
    param([Parameter(Mandatory = $true)]$Definition, [Parameter(Mandatory = $true)][string]$Revision, [int]$GitSeconds = 20, [int]$CheckSeconds = 30, [string]$TempRoot = "")
    $fail = { param([string]$Why) return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText $Why) } }
    if ($Revision -cnotmatch '\A[0-9a-f]{40}\z') { return (& $fail "what is wanted is not a revision") }
    $dir = $Definition.checkout
    $ref = Get-HordeServiceRemoteRef -Definition $Definition
    $tip = Invoke-HordeServiceGit -Checkout $dir -Arguments @("rev-parse", "--verify", "--quiet", ($ref + "^{commit}")) -TimeoutSeconds $GitSeconds
    if (-not $tip.ok -or $tip.out -cne $Revision) { return (& $fail ("it is no longer what " + $Definition.follow.remote + "/" + $Definition.follow.branch + " names")) }
    $forward = Invoke-HordeServiceGit -Checkout $dir -Arguments @("merge-base", "--is-ancestor", "HEAD", $Revision) -TimeoutSeconds $GitSeconds
    if (-not $forward.ok) { return (& $fail "it is not a fast-forward of what is checked out") }
    # A FILE THE NEW REVISION ADDS, ALREADY LYING IN THE CHECKOUT (safety review, item 4). The clean
    # question the move asks is about tracked files; a file nobody tracks - or one an ignore rule
    # hides - is invisible to it. If the new revision adds a file of that name, the move either
    # stops on it (after the service has been stopped: a restart for nothing, repeated at every retry)
    # or, for an ignored file, writes over it without a word. So it is asked HERE, while the old
    # revision is still running and nothing has been stopped: every path the revision adds must be
    # free in the working tree. --no-renames: with rename detection (the tool's default) a file the
    # revision MOVES is listed as a rename, not as an addition, and its new path - which the move
    # writes just the same - would not be asked about at all (second review of the services).
    $added = Invoke-HordeServiceGit -Checkout $dir -Arguments @("diff", "--no-renames", "--name-only", "--diff-filter=A", "-z", "HEAD", $Revision) -TimeoutSeconds $GitSeconds
    if (-not $added.ok) { return (& $fail ("what it adds could not be listed (" + $added.detail + ")")) }
    foreach ($rel in @($added.out -split "`0" | Where-Object { $_ -ne "" })) {
        $there = [System.IO.Path]::Combine($dir, ($rel -replace '/', '\'))
        if ([System.IO.File]::Exists($there) -or [System.IO.Directory]::Exists($there)) { return (& $fail ("it adds " + $rel + ", and something of that name already lies in the checkout, untracked; the move would stop on it or write over it")) }
    }
    if ($TempRoot -eq "") { $TempRoot = [System.IO.Path]::GetTempPath() }
    $scratch = [System.IO.Path]::Combine($TempRoot, ("horde-service-check-" + [guid]::NewGuid().ToString("N")))
    try {
        $tree = [System.IO.Path]::Combine($scratch, "tree")
        [void][System.IO.Directory]::CreateDirectory($tree)
        $index = @{ GIT_INDEX_FILE = [System.IO.Path]::Combine($scratch, "index") }
        $read = Invoke-HordeServiceGit -Checkout $dir -Arguments @("read-tree", $Revision) -Environment $index -TimeoutSeconds $GitSeconds
        if (-not $read.ok) { return (& $fail ("its tree could not be read (" + $read.detail + ")")) }
        # --prefix takes the folder with a trailing slash, and forward slashes on every system.
        $out = Invoke-HordeServiceGit -Checkout $dir -Arguments @("checkout-index", "--all", ("--prefix=" + ($tree -replace '\\', '/') + "/")) -Environment $index -TimeoutSeconds ([System.Math]::Max($GitSeconds, $CheckSeconds))
        if (-not $out.ok) { return (& $fail ("its tree could not be written to the scratch folder (" + $out.detail + ")")) }
        $unparsed = Test-HordeServiceScriptsParse -Tree $tree
        if ($unparsed -ne "") { return (& $fail $unparsed) }
        if ($Definition.start.kind -ceq "horde") {
            $entry = [System.IO.Path]::Combine($tree, "horde.ps1")
            if (-not [System.IO.File]::Exists($entry)) { return (& $fail "it holds no horde entry point") }
            $scratchHome = [System.IO.Path]::Combine($scratch, "home")
            $ran = Invoke-HordeServiceProgram -Program (Get-HordeServiceShell) -Arguments @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $entry, "version") -WorkingDirectory $scratch -Environment @{ HORDE_HOME = $scratchHome } -TimeoutSeconds $CheckSeconds
            if (-not $ran.started -or $ran.timedOut) { return (& $fail ("horde version did not run from it: " + $ran.err)) }
            if ($ran.code -ne 0) { return (& $fail ("horde version failed from it with exit " + $ran.code + ": " + ($ran.err + " " + $ran.out).Trim())) }
            if (("" + $ran.out) -notmatch '(?m)^horde [0-9]+\.[0-9]+') { return (& $fail "horde version ran from it and named no version") }
            # 6. THE SUPERVISOR'S OWN COMMAND. The pass that would roll this revision back may itself
            #    run from the checkout being moved; a revision in which `services status` cannot even
            #    load would then take the roll-back away with it. So when the tree has the command,
            #    it must run - against the scratch home, where nothing is defined and nothing is read
            #    but that empty folder.
            if ([System.IO.File]::Exists([System.IO.Path]::Combine($tree, "cli", "commands", "services.ps1"))) {
                $own = Invoke-HordeServiceProgram -Program (Get-HordeServiceShell) -Arguments @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $entry, "services", "status") -WorkingDirectory $scratch -Environment @{ HORDE_HOME = $scratchHome } -TimeoutSeconds $CheckSeconds
                if (-not $own.started -or $own.timedOut) { return (& $fail ("horde services status did not run from it: " + $own.err)) }
                if ($own.code -ne 0) { return (& $fail ("horde services status failed from it with exit " + $own.code + ": " + ($own.err + " " + $own.out).Trim())) }
            }
        }
        return [pscustomobject]@{ ok = $true; detail = ("checked " + $Revision.Substring(0, 9) + " in a scratch copy") }
    } finally {
        try { if ([System.IO.Directory]::Exists($scratch)) { [System.IO.Directory]::Delete($scratch, $true) } } catch { }
    }
}

function Move-HordeServiceCheckout {
    # Move the checkout to -Revision: { ok; detail }. -Back is a roll-back, to a revision the service
    # ran before. EVERYTHING IS ASKED AGAIN HERE, AT THE MOMENT OF THE MOVE: what was true when the
    # update was considered may not be now - somebody edited a file, the remote moved on - and the
    # pass that decided may have been killed minutes ago.
    #   forward  the revision is still what the remote ref names, and a fast-forward of the checkout
    #   back     the revision is an ancestor of the checkout: back along its own history, nowhere else
    #   both     the checkout is detached and has no changed tracked file
    # The move is `checkout --detach`, which itself refuses to write over a local change. A checkout
    # already on the revision is done, and nothing is run.
    param([Parameter(Mandatory = $true)]$Definition, [Parameter(Mandatory = $true)][string]$Revision, [switch]$Back, [int]$TimeoutSeconds = 20)
    # touched: false for every refusal made BEFORE the checkout is asked to move - the checkout is as
    # it was; true once it has been asked, whatever then happened - a move that fails or passes its
    # time limit part way can leave files of two revisions (core/Services.ps1 keeps the mark then).
    $fail = { param([string]$Why, [bool]$Touched = $false) return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText $Why); touched = $Touched } }
    if ($Revision -cnotmatch '\A[0-9a-f]{40}\z') { return (& $fail "what it would move to is not a revision") }
    $dir = $Definition.checkout
    $head = Invoke-HordeServiceGit -Checkout $dir -Arguments @("rev-parse", "--verify", "--quiet", "HEAD^{commit}") -TimeoutSeconds $TimeoutSeconds
    if (-not $head.ok) { return (& $fail ("its checkout could not be read (" + $head.detail + ")")) }
    if ($head.out -ceq $Revision) { return [pscustomobject]@{ ok = $true; detail = ("its checkout is already on " + $Revision.Substring(0, 9)); touched = $false } }
    $branch = Invoke-HordeServiceGit -Checkout $dir -Arguments @("symbolic-ref", "--quiet", "--short", "HEAD") -TimeoutSeconds $TimeoutSeconds
    if ($branch.ok) { return (& $fail ("its checkout is on the branch " + $branch.out + "; only a detached checkout is moved")) }
    if ($branch.code -ne 1) { return (& $fail ("whether its checkout is on a branch could not be read (" + $branch.detail + ")")) }
    $status = Invoke-HordeServiceGit -Checkout $dir -Arguments @("status", "--porcelain", "--untracked-files=no") -TimeoutSeconds $TimeoutSeconds
    if (-not $status.ok) { return (& $fail ("whether its checkout has local changes could not be read (" + $status.detail + ")")) }
    if ($status.out -ne "") { return (& $fail "its checkout has local changes; they are never written over") }
    if ($Back) {
        $behind = Invoke-HordeServiceGit -Checkout $dir -Arguments @("merge-base", "--is-ancestor", $Revision, "HEAD") -TimeoutSeconds $TimeoutSeconds
        if (-not $behind.ok) { return (& $fail "the revision to go back to is not in the history of what is checked out") }
    } else {
        $tip = Invoke-HordeServiceGit -Checkout $dir -Arguments @("rev-parse", "--verify", "--quiet", ((Get-HordeServiceRemoteRef -Definition $Definition) + "^{commit}")) -TimeoutSeconds $TimeoutSeconds
        if (-not $tip.ok -or $tip.out -cne $Revision) { return (& $fail ("the remote has moved on: it is no longer what " + $Definition.follow.remote + "/" + $Definition.follow.branch + " names")) }
        $forward = Invoke-HordeServiceGit -Checkout $dir -Arguments @("merge-base", "--is-ancestor", "HEAD", $Revision) -TimeoutSeconds $TimeoutSeconds
        if (-not $forward.ok) { return (& $fail "it is not a fast-forward of what is checked out") }
    }
    $moved = Invoke-HordeServiceGit -Checkout $dir -Arguments @("checkout", "--detach", "--quiet", $Revision) -TimeoutSeconds ([System.Math]::Max($TimeoutSeconds, 60))
    if (-not $moved.ok) { return (& $fail ("the checkout did not move, or not wholly (" + $moved.detail + ")") $true) }
    $now = Invoke-HordeServiceGit -Checkout $dir -Arguments @("rev-parse", "--verify", "--quiet", "HEAD^{commit}") -TimeoutSeconds $TimeoutSeconds
    if (-not $now.ok -or $now.out -cne $Revision) { return (& $fail "the checkout was moved and is not on the revision asked for" $true) }
    return [pscustomobject]@{ ok = $true; detail = ("its checkout is on " + $Revision.Substring(0, 9)); touched = $true }
}

function Get-HordeServiceProcessEntry {
    # What the process table says of one pid, as core/Services.ps1's verdict takes it: known
    # { pid; startedAt (UTC) }, absent (no process has that pid, or it has ended), or unknown (it is
    # there and its start cannot be read - another user's process, which is never the service's own).
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    $p = $null
    try { $p = [System.Diagnostics.Process]::GetProcessById($ProcessId) }
    catch [System.ArgumentException] { return (New-HordeAbsent -Note ("no process has the number " + $ProcessId)) }
    catch {
        if ($_.Exception.GetBaseException() -is [System.ArgumentException]) { return (New-HordeAbsent -Note ("no process has the number " + $ProcessId)) }
        return (New-HordeUnknown -Reason ("process " + $ProcessId + " could not be looked at") -ErrorRecord $_)
    }
    try {
        if ($p.HasExited) { return (New-HordeAbsent -Note ("process " + $ProcessId + " has ended")) }
        return (New-HordeKnown -Value ([pscustomobject]@{ pid = $ProcessId; startedAt = $p.StartTime.ToUniversalTime() }))
    } catch {
        # A process that ends between the two reads throws here; it is gone, not unreadable.
        $gone = $false
        try { $gone = [bool]$p.HasExited } catch { $gone = $false }
        if ($gone) { return (New-HordeAbsent -Note ("process " + $ProcessId + " has ended")) }
        return (New-HordeUnknown -Reason ("when process " + $ProcessId + " started could not be read") -ErrorRecord $_)
    } finally { $p.Dispose() }
}

function Stop-HordeServiceProcess {
    # End the process -Process names ({ pid; startedAt }): { ok; detail }. THE IDENTITY IS CHECKED
    # AGAIN, HERE, and the kill goes to the very process that was checked: a pid that has been given
    # to another process since the pass looked is never ended (core/Services.ps1,
    # Get-HordeServiceProcessVerdict). A process already gone is done.
    #   THE HANDLE IS TAKEN FIRST. On .NET Framework a Process object found by its number holds only
    #   the number: StartTime opens the process, reads, and lets go, and Kill opens it AGAIN - so
    #   between the proof and the kill the number could pass to another process, and the kill would
    #   land on that one. The first version's comment said the kill went through the handle the check
    #   was made on, and it did not (safety review, item 8). Reading .Handle makes the object open
    #   the process and KEEP it; the start time and the kill then both go through that one handle,
    #   and Windows does not give a number out again while a handle to its process is held.
    param([Parameter(Mandatory = $true)]$Process)
    $p = $null
    try { $p = [System.Diagnostics.Process]::GetProcessById([int]$Process.pid) } catch { return [pscustomobject]@{ ok = $true; detail = "it had already ended" } }
    try {
        $started = $null
        try { $null = $p.Handle; if ($p.HasExited) { return [pscustomobject]@{ ok = $true; detail = "it had already ended" } }; $started = $p.StartTime.ToUniversalTime() }
        catch { return [pscustomobject]@{ ok = $false; detail = ("process " + $Process.pid + " could not be checked, so it was not ended") } }
        if (-not (Test-HordeHeartbeatSameStart -One $started -Other $Process.startedAt)) { return [pscustomobject]@{ ok = $true; detail = ("process " + $Process.pid + " is another process now; the service's had already ended, and nothing was ended") } }
        try { $p.Kill() } catch { if (-not $p.HasExited) { return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText ("process " + $Process.pid + " could not be ended: " + $_.Exception.GetBaseException().Message)) } } }
        if (-not $p.WaitForExit(5000)) { return [pscustomobject]@{ ok = $false; detail = ("process " + $Process.pid + " was told to end and had not after 5 s") } }
        return [pscustomobject]@{ ok = $true; detail = ("process " + $Process.pid + " was ended") }
    } finally { $p.Dispose() }
}

function Read-HordeServiceWindowReport {
    # The pid and window handle a window's report file names: known { pid; handle }, absent when
    # there is no file, unknown when it cannot be read as one. Only those two members are taken; the
    # file is another module's (the window that keeps it), read shared so its writer is never blocked.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return (New-HordeAbsent -Note ("there is no report file " + $Path)) }
    try {
        $text = Read-HordeSharedText -Path $Path
        # 2 MiB: the decisions window bounds its report at 60,000 characters; this is far above it.
        if ($text.Length -gt 2097152) { return (New-HordeUnknown -Reason "its report file is larger than a report is") }
        $have = Get-HordeObjectByKey (ConvertFrom-HordeJson -Text ($text))
        $processId = $have["pid"]; $handle = $have["handle"]
        if (($processId -isnot [int] -and $processId -isnot [long]) -or $processId -le 0 -or ($handle -isnot [int] -and $handle -isnot [long]) -or $handle -le 0) { return (New-HordeUnknown -Reason "its report file names no process and window") }
        return (New-HordeKnown -Value ([pscustomobject]@{ pid = [int]$processId; handle = [long]$handle }))
    } catch { return (New-HordeUnknown -Reason "its report file could not be read" -ErrorRecord $_) }
}

function Invoke-HordeServiceHordeCommand {
    # Run one horde command of a checkout to its end, for the Horde home it serves: { ok; detail }.
    # The entry point is run with the shell's -File, which takes every argument as a literal text:
    # nothing in a word or a value is parsed as code. Named values are refused by the definition when
    # they start with a dash, so none is read as a parameter.
    param([Parameter(Mandatory = $true)][string]$Checkout, [Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string[]]$Words, $Named = $null, [string[]]$Switches = @(), [int]$TimeoutSeconds = 30)
    $entry = [System.IO.Path]::Combine($Checkout, "horde.ps1")
    if (-not [System.IO.File]::Exists($entry)) { return [pscustomobject]@{ ok = $false; detail = ("there is no horde entry point in " + $Checkout) } }
    $arguments = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $entry) + @($Words)
    if ($null -ne $Named) { foreach ($k in @($Named.Keys)) { $arguments += @(("-" + $k), ("" + $Named[$k])) } }
    foreach ($k in @($Switches)) { $arguments += ("-" + $k) }
    $r = Invoke-HordeServiceProgram -Program (Get-HordeServiceShell) -Arguments $arguments -WorkingDirectory $Checkout -Environment @{ HORDE_HOME = $HordeHome } -TimeoutSeconds $TimeoutSeconds
    # transient: the command did not RUN to an end (not started, or ended at the time limit), which says
    # nothing of the command; a command that ran and exited non-zero is transient = false.
    if (-not $r.started -or $r.timedOut) { return [pscustomobject]@{ ok = $false; transient = $true; detail = (Protect-HordeServiceText ("horde " + ($Words -join " ") + ": " + $r.err)) } }
    if ($r.code -ne 0) { return [pscustomobject]@{ ok = $false; transient = $false; detail = (Protect-HordeServiceText ("horde " + ($Words -join " ") + " failed with exit " + $r.code + ": " + ($r.err + " " + $r.out).Trim())) } }
    return [pscustomobject]@{ ok = $true; detail = ("asked with horde " + ($Words -join " ")) }
}

function Request-HordeServiceStop {
    # Ask the service to stop, the way its definition says: { ok; detail }. ASKING IS NOT STOPPING:
    # the pass then waits for the process to go, and ends it after the definition's waitSeconds
    # (core/Services.ps1). A service with no way to be asked (kind kill) is ended here.
    param([Parameter(Mandatory = $true)]$Definition, [Parameter(Mandatory = $true)]$Process, [int]$TimeoutSeconds = 30)
    $stop = $Definition.stop
    if ($stop.kind -ceq "kill") { return (Stop-HordeServiceProcess -Process $Process) }
    if ($stop.kind -ceq "horde") { return (Invoke-HordeServiceHordeCommand -Checkout $Definition.checkout -HordeHome $Definition.hordeHome -Words $stop.words -Named $stop.named -Switches $stop.switches -TimeoutSeconds $TimeoutSeconds) }
    # kind window: the report names the window; it is asked to close only when the report is about
    # THIS process - a report left by an earlier run names a window that may be anyone's now.
    $report = Read-HordeServiceWindowReport -Path $stop.report
    if ($report.state -cne "known") { return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText ("its window could not be asked to close: " + $report.reason)) } }
    if ([int]$report.value.pid -ne [int]$Process.pid) { return [pscustomobject]@{ ok = $false; detail = ("its window could not be asked to close: the report file is about process " + $report.value.pid + ", not its process " + $Process.pid) } }
    # THE START TIME TOO, AT THIS MOMENT: the report and the state agree on a number, and a number is
    # given out again. The process that has it now must have started when the service's did, or the
    # window belongs to a stranger and nothing is sent.
    $still = Get-HordeServiceProcessVerdict -Claim $Process -Entry (Get-HordeServiceProcessEntry -ProcessId ([int]$Process.pid))
    if ($still.state -cne "known") { return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText ("its window was not asked to close: " + $still.reason)) } }
    $asked = Close-HordeServiceWindow -ProcessId ([int]$Process.pid) -Handle ([long]$report.value.handle)
    if ($asked.state -ceq "known") { return [pscustomobject]@{ ok = $true; detail = "its window was asked to close" } }
    return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText ("its window could not be asked to close: " + $asked.reason)) }
}

function Start-HordeServiceNow {
    # Start the service as its definition says: { ok; detail; process; revision }. process is
    # { pid; startedAt } of what was made; revision is what its checkout is on when it follows one
    # (what the new process runs), else "". -SupervisorHome is where its output file is kept.
    param([Parameter(Mandatory = $true)]$Definition, [string]$SupervisorHome = "", [int]$TimeoutSeconds = 20)
    $fail = { param([string]$Why) return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText $Why); process = $null; revision = "" } }
    $launch = $null
    # THE EXIT RECORD is asked for only of a service whose definition lists deliberate exit codes
    # (core/ServiceHostPort.ps1). The record of the run before is removed first: it is about a process
    # that is gone, and is refused anyway by its pid and start, but a file that is not there cannot
    # be misread at all.
    $exitFile = ""
    $deliberate = $null
    if ($null -ne $Definition.PSObject.Properties["stop"] -and $null -ne $Definition.stop) { $deliberate = $Definition.stop.PSObject.Properties["deliberateExitCodes"] }
    if ($null -ne $deliberate -and @($deliberate.Value).Count -gt 0) {
        $exitFile = Get-HordeServiceExitPath -Name $Definition.name -HordeHome $SupervisorHome
        try { if ([System.IO.File]::Exists($exitFile)) { [System.IO.File]::Delete($exitFile) } } catch { }
    }
    try {
        if ($Definition.start.kind -ceq "horde") {
            $entry = [System.IO.Path]::Combine($Definition.checkout, "horde.ps1")
            if (-not [System.IO.File]::Exists($entry)) { return (& $fail ("there is no horde entry point in its checkout " + $Definition.checkout)) }
            $log = Step-HordeServiceLog -Name $Definition.name -HordeHome $SupervisorHome
            $launch = New-HordeServiceLaunch -Kind "horde" -Script $entry -Words $Definition.start.words -Named $Definition.start.named -Switches $Definition.start.switches -Environment @{ HORDE_HOME = $Definition.hordeHome } -WorkingDirectory $Definition.checkout -LogFile $log -ExitFile $exitFile
        } else {
            if (-not [System.IO.File]::Exists($Definition.start.program)) { return (& $fail ("its program " + $Definition.start.program + " is not there")) }
            $launch = New-HordeServiceLaunch -Kind "program" -Program $Definition.start.program -Arguments $Definition.start.arguments -WorkingDirectory $Definition.checkout -ExitFile $exitFile
        }
    } catch { return (& $fail ("it could not be made ready to start: " + $_.Exception.Message)) }
    $revision = ""
    if ($null -ne $Definition.follow) {
        $head = Invoke-HordeServiceGit -Checkout $Definition.checkout -Arguments @("rev-parse", "--verify", "--quiet", "HEAD^{commit}") -TimeoutSeconds $TimeoutSeconds
        if ($head.ok -and $head.out -cmatch '\A[0-9a-f]{40}\z') { $revision = $head.out }
    }
    $made = Start-HordeServiceProcess -Launch $launch
    if ($made.state -cne "known") { return (& $fail $made.reason) }
    return [pscustomobject]@{ ok = $true; detail = ("started as process " + $made.value.pid); process = $made.value; revision = $revision }
}
