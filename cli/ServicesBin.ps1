# cli/ServicesBin - the INSTALLED CLI follows main: one step of `horde services tend` that keeps the
# git clone every Orc runs `horde` from (the bin clone) on origin/main, the way the supervisor already
# keeps the relay runner on it.
#
# WHY (T-0265, 2026-10-17). Nothing updated the bin clone. It fell 233 commits behind main: it had no
# `decisions ack` verb, it warned that newer records came from a later version, and Orcs worked round
# it by hand. The runner checkout, beside it, had followed origin/main by itself for weeks, because the
# supervisor's pass moves it (cli/ServicesTend.ps1). Two checkouts of one repository that only one of
# them follows WILL drift; so the pass that already follows main follows for both.
#
# WHAT A PASS DOES, in order, and where it stops:
#   1. Asks origin for main (one ref, no tags) when it is due: at the interval of the setting
#      fetchIntervalSeconds, and never more often than once a minute. The bin clone is its own
#      repository, so the runner's fetch cannot serve it; the interval is what keeps it cheap.
#   2. If the clone is on origin/main already: nothing more. A quiet pass reads two refs.
#   3. If it is not, it is moved ONLY when it is safe, and a trouble is told once:
#        branch    it is not on the branch main (detached, or a feature branch)
#        dirty     a tracked file is changed
#        diverged  it holds commits origin/main does not: a fast-forward is not possible
#      Nothing is ever reset, stashed, merged or written over for any of these.
#   4. Safe means `merge --ff-only`. Then the CLI is PROVED to load: `horde version` is run from the
#      clone, in a fresh shell. If it does not load, the clone is put back on the revision it was on,
#      the revision that failed is not tried again until origin/main moves on, and a person is told.
#
# TELLING IS ONCE. The kind of trouble is kept in <home>\services\installed-cli.json when it is told,
# and told again only after the clone has been in order, or the trouble has changed. A tell that could
# not be delivered is not recorded, so it is tried again next pass (as the services' notices are).
#
# THE TOOLS ARE HANDED IN, as for the rest of the pass: a suite gives the follower a probe and a
# teller of its own, and the real ones are made only by the command (cli/commands/services.ps1).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeInstalledCliService = "installed-cli"
$script:HordeInstalledCliRemote = "origin"
$script:HordeInstalledCliBranch = "main"
# The least gap between two asks of the remote, whatever the setting: the design's "no fetch more
# than once a minute".
$script:HordeInstalledCliFetchFloorSeconds = 60
$script:HordeInstalledCliSentences = [ordered]@{
    "branch"   = "the installed CLI is not on the branch main, so the supervisor did not move it; a person puts it back on main"
    "dirty"    = "the installed CLI has changed files of its own, so the supervisor did not move it; a person commits or discards them"
    "diverged" = "the installed CLI holds commits that origin/main does not, so it cannot be fast-forwarded and the supervisor did not move it; a person reconciles it"
    "apply"    = "the installed CLI could not be fast-forwarded to origin/main; it was left as it was"
    "failed"   = "the installed CLI did not load after an update, so it was put back on the revision it was on; that revision is not tried again until origin/main moves on"
    "stuck"    = "the installed CLI did not load after an update and could NOT be put back; a person must repair it now"
}

function Get-HordeInstalledCliPath {
    # Where the installed CLI is: the setting installedCliFolder, else the bin clone under the person's
    # profile (shipped code names no one's folder; the profile is asked of the machine).
    param([Parameter(Mandatory = $true)]$Policy)
    $set = "" + $Policy.installedCliFolder
    if ($set -ne "") { return $set }
    return [System.IO.Path]::Combine([System.Environment]::GetFolderPath("UserProfile"), "bin", "horde")
}

function Get-HordeInstalledCliRefusal {
    # PURE. Why this pass must not follow at all, or "". A test's home (under the temp folder) with no
    # folder set would reach the person's REAL installed CLI through the default: the suites that run
    # the real `horde services tend` in a home of their own must never move it. A test that means to
    # follow a throwaway clone says so with installedCliFolder.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)]$Policy, [string]$TempRoot = "")
    if ("" + $Policy.installedCliFolder -eq "" -and (Test-HordeServiceHomeIsATests -HordeHome $HordeHome -TempRoot $TempRoot)) { return "this Horde home is under the temp folder, so it is a test's: the default installed CLI is not touched" }
    return ""
}

function Get-HordeInstalledCliStatePath {
    param([string]$HordeHome = "")
    return [System.IO.Path]::Combine((Get-HordeServiceFolder -HordeHome $HordeHome), "installed-cli.json")
}

function Read-HordeInstalledCliState {
    # { lastFetchAt; said; told; failedTip }. A file that is missing or cannot be read is a new state:
    # the worst that costs is one more ask of the remote and one more tell.
    param([string]$HordeHome = "")
    $s = [pscustomobject]@{ lastFetchAt = $null; said = ""; told = ""; failedTip = "" }
    $path = Get-HordeInstalledCliStatePath -HordeHome $HordeHome
    if (-not [System.IO.File]::Exists($path)) { return $s }
    try {
        $r = (Read-HordeSharedText -Path $path) | ConvertFrom-Json
        # Kept as ticks, a whole number: a date written as text is turned into a local date by pwsh 7's
        # ConvertFrom-Json and read back as another instant.
        if ($null -ne $r.PSObject.Properties["lastFetchTicks"] -and $r.lastFetchTicks -is [int64] -and $r.lastFetchTicks -gt 0) { $s.lastFetchAt = [datetime]::new([int64]$r.lastFetchTicks, [System.DateTimeKind]::Utc) }
        foreach ($k in @("said", "told", "failedTip")) { if ($null -ne $r.PSObject.Properties[$k]) { $s.$k = "" + $r.$k } }
    } catch { return [pscustomobject]@{ lastFetchAt = $null; said = ""; told = ""; failedTip = "" } }
    return $s
}

function Write-HordeInstalledCliState {
    param([Parameter(Mandatory = $true)]$State, [string]$HordeHome = "")
    $path = Get-HordeInstalledCliStatePath -HordeHome $HordeHome
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
    $row = [ordered]@{ lastFetchTicks = $(if ($State.lastFetchAt -is [datetime]) { [int64]$State.lastFetchAt.ToUniversalTime().Ticks } else { [int64]0 }); said = "" + $State.said; told = "" + $State.told; failedTip = "" + $State.failedTip }
    $temp = $path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    [System.IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $row), (New-Object System.Text.UTF8Encoding($false)))
    try { Move-HordeFileAtomic -From $temp -To $path }
    catch { try { [System.IO.File]::Delete($temp) } catch { }; throw }
}

function New-HordeInstalledCliTools {
    # The real tools: Probe proves the CLI loads. param($Path, $Policy) -> { ok; detail }.
    return @{
        Probe = {
            param($Path, $Policy)
            return (Invoke-HordeServiceHordeCommand -Checkout $Path -HordeHome (Get-HordeHome) -Words @("version") -TimeoutSeconds ([int]$Policy.checkSeconds))
        }
    }
}

function Read-HordeInstalledCliCheckout {
    # What the installed clone is on and what origin/main last was, read and never changed:
    # { ok; reason; head; tip; branch; clean; ahead; behind }. branch is "" when detached.
    param([Parameter(Mandatory = $true)][string]$Path, [int]$GitSeconds = 20)
    $no = { param($Why) return [pscustomobject]@{ ok = $false; reason = (Protect-HordeServiceText $Why); head = ""; tip = ""; branch = ""; clean = $false; ahead = 0; behind = 0 } }
    $ref = "refs/remotes/" + $script:HordeInstalledCliRemote + "/" + $script:HordeInstalledCliBranch
    $head = Invoke-HordeServiceGit -Checkout $Path -Arguments @("rev-parse", "--verify", "--quiet", "HEAD^{commit}") -TimeoutSeconds $GitSeconds
    if (-not $head.ok -or $head.out -cnotmatch '\A[0-9a-f]{40}\z') { return (& $no ("the installed CLI could not be read (" + $head.detail + ")")) }
    $tip = Invoke-HordeServiceGit -Checkout $Path -Arguments @("rev-parse", "--verify", "--quiet", ($ref + "^{commit}")) -TimeoutSeconds $GitSeconds
    if (-not $tip.ok -or $tip.out -cnotmatch '\A[0-9a-f]{40}\z') { return (& $no ("the installed CLI has no " + $ref + " yet: the remote has not been fetched")) }
    $branch = Invoke-HordeServiceGit -Checkout $Path -Arguments @("symbolic-ref", "--quiet", "--short", "HEAD") -TimeoutSeconds $GitSeconds
    if (-not $branch.ok -and $branch.code -ne 1) { return (& $no ("whether the installed CLI is on a branch could not be read (" + $branch.detail + ")")) }
    $status = Invoke-HordeServiceGit -Checkout $Path -Arguments @("status", "--porcelain", "--untracked-files=no") -TimeoutSeconds $GitSeconds
    if (-not $status.ok) { return (& $no ("whether the installed CLI has changed files could not be read (" + $status.detail + ")")) }
    $ahead = 0; $behind = 0
    if ($head.out -cne $tip.out) {
        $counts = Invoke-HordeServiceGit -Checkout $Path -Arguments @("rev-list", "--left-right", "--count", ($head.out + "..." + $tip.out)) -TimeoutSeconds $GitSeconds
        if ($counts.ok -and $counts.out -cmatch '\A(\d+)\s+(\d+)\z') { $ahead = [int]$Matches[1]; $behind = [int]$Matches[2] }
        else { return (& $no ("how far the installed CLI is from origin/main could not be read (" + $counts.detail + ")")) }
    }
    return [pscustomobject]@{ ok = $true; reason = ""; head = $head.out; tip = $tip.out; branch = $(if ($branch.ok) { $branch.out } else { "" }); clean = [bool]($status.out -eq ""); ahead = $ahead; behind = $behind }
}

function Get-HordeInstalledCliStatus {
    # What `horde services status` shows of the installed CLI, READ ONLY (no remote is asked):
    # { state; path; sha; wanted; behind; branch; clean; said; lastFetchAt }
    #   state  current | behind | blocked | absent | off | unknown
    # behind is how many commits origin/main (as last fetched) has that the clone does not.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)]$Policy)
    $path = Get-HordeInstalledCliPath -Policy $Policy
    $row = { param($State, $Said, $Read, $Fetched) return [pscustomobject]@{ state = $State; path = $path; sha = $(if ($null -ne $Read) { $Read.head } else { "" }); wanted = $(if ($null -ne $Read) { $Read.tip } else { "" }); behind = $(if ($null -ne $Read) { [int]$Read.behind } else { 0 }); branch = $(if ($null -ne $Read) { $Read.branch } else { "" }); clean = $(if ($null -ne $Read) { [bool]$Read.clean } else { $true }); said = $Said; lastFetchAt = $Fetched } }
    $kept = Read-HordeInstalledCliState -HordeHome $HordeHome
    if ($Policy.followInstalledCli -ne $true) { return (& $row "off" "the supervisor is set not to follow main for the installed CLI (the setting followInstalledCli)" $null $kept.lastFetchAt) }
    if (-not [System.IO.Directory]::Exists($path)) { return (& $row "absent" ("there is no installed CLI at " + $path) $null $kept.lastFetchAt) }
    $own = Test-HordeServiceCheckoutIsItsOwn -Checkout $path -TimeoutSeconds ([int]$Policy.gitSeconds)
    if ($own -ne "") { return (& $row "unknown" $own $null $kept.lastFetchAt) }
    $read = Read-HordeInstalledCliCheckout -Path $path -GitSeconds ([int]$Policy.gitSeconds)
    if (-not $read.ok) { return (& $row "unknown" $read.reason $null $kept.lastFetchAt) }
    if ($read.head -ceq $read.tip) { return (& $row "current" "on origin/main" $read $kept.lastFetchAt) }
    $why = Get-HordeInstalledCliBlock -Read $read
    if ($why -ne "") { return (& $row "blocked" ($why + " (" + $script:HordeInstalledCliSentences[$why] + ")") $read $kept.lastFetchAt) }
    if ($kept.failedTip -ceq $read.tip) { return (& $row "blocked" ("failed: " + $script:HordeInstalledCliSentences["failed"]) $read $kept.lastFetchAt) }
    return (& $row "behind" ("origin/main is " + $read.behind + " commit(s) ahead; the next pass moves it") $read $kept.lastFetchAt)
}

function Get-HordeInstalledCliBlock {
    # PURE. Why the clone must not be moved, or "": branch, dirty or diverged, in that order.
    param([Parameter(Mandatory = $true)]$Read)
    if ($Read.branch -cne $script:HordeInstalledCliBranch) { return "branch" }
    if (-not $Read.clean) { return "dirty" }
    if ($Read.ahead -gt 0) { return "diverged" }
    return ""
}

function Invoke-HordeInstalledCliFollow {
    # One pass of the follower: the lines to show. -Tell is the pass's teller (param($Notices,
    # $HordeHome, $Policy) -> { told; problem }), $null when nothing can tell. -Tools is
    # New-HordeInstalledCliTools or a suite's own. -NoFetch is for a suite that fetches by hand.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)]$Policy, [Parameter(Mandatory = $true)][datetime]$Now, $Tell = $null, $Tools = $null, [switch]$NoFetch)
    if ($null -eq $Tools) { $Tools = New-HordeInstalledCliTools }
    $lines = New-Object System.Collections.ArrayList
    if ($Policy.followInstalledCli -ne $true) { return @() }
    if ((Get-HordeInstalledCliRefusal -HordeHome $HordeHome -Policy $Policy) -ne "") { return @() }
    $path = Get-HordeInstalledCliPath -Policy $Policy
    if (-not [System.IO.Directory]::Exists($path)) { return @() }
    $gitSeconds = [int]$Policy.gitSeconds
    $own = Test-HordeServiceCheckoutIsItsOwn -Checkout $path -TimeoutSeconds $gitSeconds
    if ($own -ne "") { return @("installed CLI: left alone - " + $own) }
    $state = Read-HordeInstalledCliState -HordeHome $HordeHome
    $dirty = $false
    $journal = { param($Code, $Outcome, $Reason) $null = Write-HordeServiceJournal -HordeHome $HordeHome -Entries @(New-HordeServiceJournalEntry -At $Now -Service $script:HordeInstalledCliService -Action "follow-main" -Code $Code -Outcome $Outcome -Reason $Reason) }
    # 1. THE ASK, at the setting's interval and never faster than the floor.
    $interval = [System.Math]::Max([int]$Policy.fetchIntervalSeconds, $script:HordeInstalledCliFetchFloorSeconds)
    if (-not $NoFetch -and (Test-HordeServiceFetchDue -LastFetchAt $state.lastFetchAt -Now $Now -IntervalSeconds $interval)) {
        $ref = "refs/remotes/" + $script:HordeInstalledCliRemote + "/" + $script:HordeInstalledCliBranch
        $got = Invoke-HordeServiceGit -Checkout $path -Arguments @("fetch", "--no-tags", "--quiet", $script:HordeInstalledCliRemote, ("+refs/heads/" + $script:HordeInstalledCliBranch + ":" + $ref)) -TimeoutSeconds $gitSeconds
        # Kept whether or not it worked: a remote that cannot be reached is asked at the interval.
        $state.lastFetchAt = $Now.ToUniversalTime(); $dirty = $true
        if (-not $got.ok) { [void]$lines.Add("installed CLI: the remote could not be asked - " + $got.detail) }
    }
    # 2. WHERE IT IS.
    $read = Read-HordeInstalledCliCheckout -Path $path -GitSeconds $gitSeconds
    $code = ""; $reason = ""; $tellWhat = ""
    if (-not $read.ok) { [void]$lines.Add("installed CLI: not judged - " + $read.reason) }
    elseif ($read.head -ceq $read.tip) {
        # In order: what was said or told is over, so a new trouble is said and told again.
        if ($state.said -ne "" -or $state.told -ne "" -or $state.failedTip -ne "") { $state.said = ""; $state.told = ""; $state.failedTip = ""; $dirty = $true }
    } else {
        $block = Get-HordeInstalledCliBlock -Read $read
        if ($block -ne "") { $code = $block; $tellWhat = $block; $reason = $script:HordeInstalledCliSentences[$block] }
        elseif ($state.failedTip -ceq $read.tip) { $code = "failed-held" }
        else {
            # 3. SAFE: fast-forward only, then prove it loads.
            $move = Invoke-HordeServiceGit -Checkout $path -Arguments @("merge", "--ff-only", "--quiet", $read.tip) -TimeoutSeconds ([System.Math]::Max($gitSeconds, 60))
            $after = Read-HordeInstalledCliCheckout -Path $path -GitSeconds $gitSeconds
            if (-not $move.ok -or -not $after.ok -or $after.head -cne $read.tip) {
                $code = "apply"; $tellWhat = "apply"; $reason = $script:HordeInstalledCliSentences["apply"]
                $state.failedTip = $read.tip; $dirty = $true
                # A merge that began and did not end must not leave the clone part way.
                if ($after.ok -and $after.head -cne $read.head) { $null = Invoke-HordeServiceGit -Checkout $path -Arguments @("reset", "--hard", "--quiet", $read.head) -TimeoutSeconds ([System.Math]::Max($gitSeconds, 60)) }
            } else {
                $proof = $null
                try { $proof = @(& $Tools["Probe"] $path $Policy) | Select-Object -Last 1 } catch { $proof = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
                if ($null -ne $proof -and $null -ne $proof.PSObject.Properties["ok"] -and $proof.ok -eq $true) {
                    $code = "updated"
                    [void]$lines.Add("installed CLI: moved " + $read.head.Substring(0, 9) + " -> " + $read.tip.Substring(0, 9) + " and it loads")
                    & $journal "updated" "done" ("moved " + $read.head.Substring(0, 9) + " -> " + $read.tip.Substring(0, 9))
                    $state.said = ""; $state.told = ""; $state.failedTip = ""; $dirty = $true
                } else {
                    # 4. IT DOES NOT LOAD: put it back where it was, and do not try this revision again.
                    $detail = $(if ($null -ne $proof -and $null -ne $proof.PSObject.Properties["detail"]) { Protect-HordeServiceText ("" + $proof.detail) } else { "the probe did not answer" })
                    $back = Invoke-HordeServiceGit -Checkout $path -Arguments @("reset", "--hard", "--quiet", $read.head) -TimeoutSeconds ([System.Math]::Max($gitSeconds, 60))
                    $now2 = Read-HordeInstalledCliCheckout -Path $path -GitSeconds $gitSeconds
                    $state.failedTip = $read.tip; $dirty = $true
                    if ($back.ok -and $now2.ok -and $now2.head -ceq $read.head) { $code = "failed"; $tellWhat = "failed" }
                    else { $code = "stuck"; $tellWhat = "stuck"; $state.failedTip = "" }
                    $reason = $script:HordeInstalledCliSentences[$code]
                    [void]$lines.Add("installed CLI: the update to " + $read.tip.Substring(0, 9) + " did not load (" + $detail + ")")
                    & $journal $code "failed" ("the update to " + $read.tip.Substring(0, 9) + " did not load: " + $detail)
                }
            }
        }
    }
    # 5. SAID AND TOLD ONCE per kind of trouble.
    if ($code -ne "" -and $code -cne "updated") {
        if ($state.said -cne $code) {
            [void]$lines.Add("installed CLI: " + $code + $(if ($reason -ne "") { " - " + $reason } else { "" }))
            if ($code -cne "failed-held" -and $code -cne "failed" -and $code -cne "stuck" -and $code -cne "apply") { & $journal $code "" $reason }
            $state.said = $code; $dirty = $true
        }
        if ($tellWhat -ne "" -and $state.told -cne $tellWhat) {
            $notice = [pscustomobject]@{ id = [guid]::NewGuid().ToString(); kind = "cli"; text = $reason; at = $Now; service = $script:HordeInstalledCliService; what = $tellWhat }
            $answer = $null
            if ($Policy.tellWarchief -ne $true -or $null -eq $Tell) { [void]$lines.Add("installed CLI: 1 notice waits untold: " + $(if ($Policy.tellWarchief -ne $true) { "telling is switched off (the setting tellWarchief)" } else { "nothing here can tell anyone" })) }
            else {
                try { $answer = @(& $Tell @($notice) $HordeHome $Policy) | Select-Object -Last 1 } catch { [void]$lines.Add("installed CLI: the notice waits untold: " + (Protect-HordeServiceText $_.Exception.Message)) }
                if ($null -ne $answer -and $null -ne $answer.PSObject.Properties["told"] -and @($answer.told | ForEach-Object { "" + $_ }) -ccontains $notice.id) { $state.told = $tellWhat; $dirty = $true; [void]$lines.Add("installed CLI: told (" + $tellWhat + ")") }
                elseif ($null -ne $answer) { [void]$lines.Add("installed CLI: the notice waits untold" + $(if ($null -ne $answer.PSObject.Properties["problem"] -and "" + $answer.problem -ne "") { ": " + (Protect-HordeServiceText ("" + $answer.problem)) } else { "" }) + "; tried again next pass") }
            }
        }
    }
    if ($dirty) { try { Write-HordeInstalledCliState -State $state -HordeHome $HordeHome } catch { [void]$lines.Add("installed CLI: its state could not be kept - " + (Protect-HordeServiceText $_.Exception.Message)) } }
    return @($lines.ToArray())
}

function Format-HordeInstalledCliStatus {
    # The status line of the installed CLI, as a person reads it.
    param([Parameter(Mandatory = $true)]$Row)
    $short = { param($s) if ("" + $s -eq "") { return "unknown" } return ("" + $s).Substring(0, [System.Math]::Min(9, ("" + $s).Length)) }
    $head = "installed CLI: " + $Row.state.ToUpperInvariant() + " - " + $Row.path
    if ($Row.state -ceq "current" -or $Row.state -ceq "behind" -or $Row.state -ceq "blocked") { $head += " is on " + (& $short $Row.sha) + ", origin/main was " + (& $short $Row.wanted) + $(if ($Row.behind -gt 0) { " (" + $Row.behind + " behind)" } else { " (not behind)" }) }
    return @($head, ("    " + $Row.said))
}
