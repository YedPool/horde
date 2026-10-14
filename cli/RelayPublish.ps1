# cli/RelayPublish - the supervisor's pass keeps the hosted phone page current: it deploys the page
# itself when only the page changed, checks that the deploy took, and otherwise tells the warchief once
# why it did not.
#
# WHY. The phone app (surfaces/pwa/, with relay/js/protocol.js) is served by the hosted relay, and the
# relay serves only what was last handed to it by `horde relay deploy` (cli/RelayDeploy.ps1). The
# supervisor keeps the machine's checkout on what was merged, but nothing kept the hosted page: on
# 2026-10-14 the founder could not see merged cards on his phone for hours because nobody had deployed.
#
# THE RULE (approved 2026-10-14, exactly):
#   1. The last deployed commit is recorded in the home (<home>\relay\deployed.json, written by every
#      deploy, by hand or by this; cli/RelayDeploy.ps1) and compared with the checkout's commit.
#   2. When what changed since then is ONLY the phone page - surfaces/pwa/** and relay/js/** - this
#      deploys, logged; then checks that /app/sw.js's VERSION changed and that every new or changed
#      file the site serves answers 200; and tells the warchief once how it went.
#   3. When the RELAY changed - anything under relays/**, which holds the hosted relay's Worker and its
#      deploy config - this does NOT deploy: a change there can alter storage or the API, and a person
#      reads it first. The warchief is told once.
#   4. Anything else that changed is not the page either: told once, not deployed. UNKNOWN IS NEVER A
#      DEPLOY - a record that is missing or names no clean commit, a diff that cannot be read, a
#      checkout with local changes. A deploy that failed or a check that failed is told once, and tried
#      again an hour later at the earliest.
#   5. One deploy at a time, by hand or not: the deploy itself holds the lock (cli/RelayDeploy.ps1), and
#      a deploy that finds it held is left to the next pass, neither a failure nor told.
#
# THE RELAY IS NOT NAMED HERE (CONTRIBUTING 14). relays/** is every relay's folder, so "the relay
# changed" needs no relay's name; the origin the check asks is the one the deploy answered with, the
# relay's own configured origin, never an address written here.
#
# THE FIRST RUN HAS NO RECORD, AND DOES NOT DEPLOY. The live page's VERSION cannot stand in for a
# commit: it is a hash of the built files, and the commit that built it could be found only by building
# commits until one matched. So a home with no record is told once that one deploy by hand records it.
#
# WHAT IS KEPT: <home>\relay\publish-state.json - a deploy part way (attempt), the last failure and its
# base (so a deploy whose check failed is tried again from the same base), the keys of what has been
# told (each told once), and the notices not yet taken by a teller (they wait, as the services' do,
# cli/ServicesTend.ps1). <home>\relay\publish-log.txt gets a line for everything that happened, and
# every line of a deploy; it is set aside at 1 MB.
#
# THE TOOLS ARE HANDED IN, as the pass's are (cli/ServicesTend.ps1, New-HordeServiceTools): a suite
# makes its own, and the real ones (New-HordeRelayPublishTools) are made only by the command, which
# also refuses a Horde home under the temp folder before any of them is made.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). Requires core/Tristate.ps1,
# core/Home.ps1, core/FileAtomic.ps1 and cli/RelayDeploy.ps1 (its record, read and written there).

$script:HordeRelayPublishPagePrefixes = @("surfaces/pwa/", "relay/js/")
$script:HordeRelayPublishRelayPrefix = "relays/"
$script:HordeRelayPublishRetrySeconds = 3600
$script:HordeRelayPublishStateVersion = 1
$script:HordeRelayPublishToldMost = 50
$script:HordeRelayPublishLogMaxBytes = 1048576
$script:HordeRelayPublishHttpSeconds = 10
$script:HordeRelayPublishGitSeconds = 20
$script:HordeRelayPublishVersionPattern = 'const VERSION = "([0-9a-f]{8,64})";'
$script:HordeRelayPublishCommitPattern = '\A[0-9a-f]{40}\z'

function ConvertTo-HordeRelayPublishShort {
    # PURE. A commit as a line shows it: its first seven characters, or what there is of it.
    param([AllowEmptyString()][string]$Commit)
    if ($Commit.Length -le 7) { return $Commit }
    return $Commit.Substring(0, 7)
}

function Get-HordeRelayPublishStatePath { param([string]$HordeHome = "") return [System.IO.Path]::Combine((Get-HordeRelayDeployFolder -HordeHome $HordeHome), "publish-state.json") }
function Get-HordeRelayPublishLogPath { param([string]$HordeHome = "") return [System.IO.Path]::Combine((Get-HordeRelayDeployFolder -HordeHome $HordeHome), "publish-log.txt") }

function New-HordeRelayPublishState {
    return [pscustomobject]@{ attempt = $null; failure = $null; told = [string[]]@(); pending = @() }
}

function Read-HordeRelayPublishState {
    # known state, absent (none kept yet), or unknown: a state that cannot be read is never begun again
    # as new, which would forget a failure and deploy again at once.
    param([string]$HordeHome = "")
    $path = Get-HordeRelayPublishStatePath -HordeHome $HordeHome
    if (-not [System.IO.File]::Exists($path)) { return (New-HordeAbsent -Note "nothing kept yet") }
    $r = $null
    try { $r = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::ASCII) | ConvertFrom-Json }
    catch { return (New-HordeUnknown -Reason ("its state file " + $path + " could not be read") -ErrorRecord $_) }
    if ($null -eq $r -or $r.schemaVersion -ne $script:HordeRelayPublishStateVersion) { return (New-HordeUnknown -Reason ("its state file " + $path + " is not one this wrote; mend it or remove it")) }
    $when = {
        param($Text)
        $t = [datetime]::MinValue
        if (-not [datetime]::TryParseExact(("" + $Text), "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture, ([System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal), [ref]$t)) { throw "a time in the state is not one this wrote" }
        return $t
    }
    try {
        $s = New-HordeRelayPublishState
        if ($null -ne $r.attempt) { $s.attempt = [pscustomobject]@{ head = "" + $r.attempt.head; base = "" + $r.attempt.base; at = (& $when $r.attempt.at) } }
        if ($null -ne $r.failure) { $s.failure = [pscustomobject]@{ head = "" + $r.failure.head; base = "" + $r.failure.base; at = (& $when $r.failure.at); what = "" + $r.failure.what } }
        $s.told = [string[]]@(@($r.told) | Where-Object { $null -ne $_ } | ForEach-Object { "" + $_ })
        $s.pending = @(@($r.pending) | Where-Object { $null -ne $_ } | ForEach-Object { [pscustomobject]@{ id = "" + $_.id; kind = "page"; what = "" + $_.what; revision = "" + $_.revision; service = "phone-page"; text = ""; at = (& $when $_.at) } })
        return (New-HordeKnown -Value $s)
    } catch { return (New-HordeUnknown -Reason ("its state file " + $path + " is not one this wrote; mend it or remove it") -ErrorRecord $_) }
}

function Write-HordeRelayPublishState {
    # Replace the state whole (core/FileAtomic.ps1).
    param([Parameter(Mandatory = $true)]$State, [string]$HordeHome = "")
    $fmt = { param($T) return $T.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) }
    $rec = [ordered]@{
        schemaVersion = $script:HordeRelayPublishStateVersion
        attempt = $(if ($null -ne $State.attempt) { [ordered]@{ head = $State.attempt.head; base = $State.attempt.base; at = (& $fmt $State.attempt.at) } } else { $null })
        failure = $(if ($null -ne $State.failure) { [ordered]@{ head = $State.failure.head; base = $State.failure.base; at = (& $fmt $State.failure.at); what = $State.failure.what } } else { $null })
        told = [string[]]@($State.told)
        pending = @(@($State.pending) | ForEach-Object { [ordered]@{ id = $_.id; what = $_.what; revision = $_.revision; at = (& $fmt $_.at) } })
    }
    $path = Get-HordeRelayPublishStatePath -HordeHome $HordeHome
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
    $temp = $path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    [System.IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $rec -Depth 5), [System.Text.Encoding]::ASCII)
    try { Move-HordeFileAtomic -From $temp -To $path }
    catch { try { [System.IO.File]::Delete($temp) } catch { }; throw }
}

function Write-HordeRelayPublishLog {
    # One line, stamped, to the log (header). A log that cannot be written costs the line, not the pass.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][datetime]$At, [AllowEmptyString()][string]$Line)
    $path = Get-HordeRelayPublishLogPath -HordeHome $HordeHome
    try {
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
        if ([System.IO.File]::Exists($path) -and (New-Object System.IO.FileInfo($path)).Length -ge $script:HordeRelayPublishLogMaxBytes) { [System.IO.File]::Copy($path, $path + ".1", $true); [System.IO.File]::Delete($path) }
        $clean = (($Line -replace '[\r\n\t]+', ' ') -replace '[^\x20-\x7E]', '?')
        [System.IO.File]::AppendAllText($path, ($At.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) + " " + $clean + "`r`n"), [System.Text.Encoding]::ASCII)
    } catch { }
}

function Get-HordeRelayPublishClasses {
    # PURE. The changed paths, as the revision tool names them (forward slashes, from the top), sorted
    # into the page, the relay, and everything else (header, THE RULE).
    param([string[]]$Paths = @())
    $page = New-Object System.Collections.ArrayList; $relay = New-Object System.Collections.ArrayList; $other = New-Object System.Collections.ArrayList
    foreach ($p in @($Paths | Where-Object { "" + $_ -ne "" })) {
        $isPage = $false
        foreach ($prefix in $script:HordeRelayPublishPagePrefixes) { if ($p.StartsWith($prefix, [System.StringComparison]::Ordinal)) { $isPage = $true } }
        if ($isPage) { [void]$page.Add($p) }
        elseif ($p.StartsWith($script:HordeRelayPublishRelayPrefix, [System.StringComparison]::Ordinal)) { [void]$relay.Add($p) }
        else { [void]$other.Add($p) }
    }
    return [pscustomobject]@{ page = [string[]]@($page.ToArray()); relay = [string[]]@($relay.ToArray()); other = [string[]]@($other.ToArray()) }
}

function Get-HordeRelayPublishBase {
    # PURE. What the checkout's commit is compared with: { kind; base; what; key; reason }. kind is
    # "same" (nothing to do), "base" (diff from base), or "unknown" (told once by key, never deployed).
    #   -Head    the checkout: { commit; clean }
    #   -Record  the deploy record, as an answer (cli/RelayDeploy.ps1, Read-HordeRelayDeployed)
    #   -State   this step's state
    # A FAILED DEPLOY OF THIS VERY COMMIT is tried again from the base it failed from, even when the
    # deploy itself worked and only its check did not (the record then names this commit) - unless a
    # deploy recorded after the failure (by hand) has settled it.
    param([Parameter(Mandatory = $true)]$Head, [Parameter(Mandatory = $true)]$Record, [Parameter(Mandatory = $true)]$State)
    $none = { param([string]$Key, [string]$Why) return [pscustomobject]@{ kind = "unknown"; base = ""; what = "no-record"; key = $Key; reason = $Why } }
    if ($Record.state -ceq "absent") { return (& $none "no-record:absent" "nothing records which commit the hosted page was deployed from") }
    if ($Record.state -cne "known") { return (& $none "no-record:unreadable" ("the deploy record cannot be read: " + $Record.reason)) }
    $r = $Record.value
    if (("" + $r.commit) -cnotmatch $script:HordeRelayPublishCommitPattern) { return (& $none "no-record:no-commit" "the last deploy recorded no commit") }
    if ($r.clean -ne $true) { return (& $none ("no-record:unclean:" + $r.commit) "the last deploy was made from a checkout with changes of its own, so no commit says what is live") }
    $base = "" + $r.commit
    $f = $State.failure
    if ($null -ne $f -and $f.head -ceq $Head.commit -and $f.base -cmatch $script:HordeRelayPublishCommitPattern -and -not ($r.commit -ceq $Head.commit -and $r.at -gt $f.at)) { $base = $f.base }
    if ($base -ceq $Head.commit) { return [pscustomobject]@{ kind = "same"; base = $base; what = ""; key = ""; reason = "the hosted page was deployed from this commit" } }
    return [pscustomobject]@{ kind = "base"; base = $base; what = ""; key = ""; reason = "" }
}

function Get-HordeRelayPublishDecision {
    # PURE. What to do about what changed between -Base and -Head: { action; what; key; reason }, action
    # one of nothing | warn | wait | deploy. -Classes is Get-HordeRelayPublishClasses's answer.
    param([Parameter(Mandatory = $true)]$Classes, [Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)][string]$Base)
    $kinds = @()
    if (@($Classes.page).Count -gt 0) { $kinds += "page" }
    if (@($Classes.relay).Count -gt 0) { $kinds += "relay" }
    if (@($Classes.other).Count -gt 0) { $kinds += "other" }
    $say = { param([string]$Action, [string]$What, [string]$Key, [string]$Why) return [pscustomobject]@{ action = $Action; what = $What; key = $Key; reason = $Why } }
    if ($kinds.Count -eq 0) { return (& $say "nothing" "" "" "no file differs from the last deploy") }
    # Told once for each base and each mix of what changed: a page change arriving on top of a held
    # relay change is worth saying again; the same mix on the next merge is not.
    $key = "held:" + $Base + ":" + ($kinds -join "+")
    if (@($Classes.relay).Count -gt 0) { return (& $say "warn" "relay-changed" $key ("the relay changed (" + @($Classes.relay).Count + " file(s) under relays/), so it is not deployed by the supervisor")) }
    if (@($Classes.other).Count -gt 0) { return (& $say "warn" "other-changed" $key ("" + @($Classes.other).Count + " file(s) beyond the phone page changed, so it is not deployed by the supervisor")) }
    if ($null -ne $State.failure -and $Now -lt $State.failure.at.AddSeconds($script:HordeRelayPublishRetrySeconds)) {
        return (& $say "wait" "" "" ("the last deploy failed at " + $State.failure.at.ToString("HH:mm 'UTC'", [System.Globalization.CultureInfo]::InvariantCulture) + "; it is tried again an hour after that"))
    }
    return (& $say "deploy" "" "" ("only the phone page changed (" + @($Classes.page).Count + " file(s))"))
}

function Get-HordeRelayPublishServed {
    # PURE. The site paths to ask for after a deploy: every changed repository path the site serves.
    # -SiteMap is site path -> repository path (cli/RelayDeploy.ps1, Get-HordeRelayDeploySiteSources).
    param([string[]]$Changed = @(), [Parameter(Mandatory = $true)]$SiteMap)
    $out = New-Object System.Collections.ArrayList
    foreach ($site in @($SiteMap.Keys)) { if (@($Changed) -ccontains ("" + $SiteMap[$site]) -and -not $out.Contains("" + $site)) { [void]$out.Add("" + $site) } }
    return [string[]]@($out.ToArray() | Sort-Object)
}

function Get-HordeRelayPublishVersion {
    # PURE. The VERSION a fetched app/sw.js carries, or "" (an answer that is not one, not 200, or none).
    param($Answer)
    if ($null -eq $Answer -or $Answer.state -cne "known" -or [int]$Answer.value.status -ne 200) { return "" }
    $m = [regex]::Match(("" + $Answer.value.body), $script:HordeRelayPublishVersionPattern)
    if (-not $m.Success) { return "" }
    return $m.Groups[1].Value
}

function Test-HordeRelayPublishCheck {
    # PURE. Did the deploy take? { ok; reason }. -Before is the VERSION served before the deploy ("" when
    # it could not be read), -Built the VERSION the deploy built, -After the answer for app/sw.js after
    # it, -Files { path; answer } for every new or changed file the site serves.
    param([AllowEmptyString()][string]$Before = "", [Parameter(Mandatory = $true)][string]$Built, $After, [object[]]$Files = @())
    $fail = { param([string]$Why) return [pscustomobject]@{ ok = $false; reason = $Why } }
    $now = Get-HordeRelayPublishVersion -Answer $After
    if ($now -eq "") { return (& $fail "app/sw.js did not answer 200 with a VERSION after the deploy") }
    if ($now -cne $Built) { return (& $fail ("app/sw.js serves VERSION " + $now + ", not the " + $Built + " the deploy built")) }
    if ($Before -ne "" -and $now -ceq $Before) { return (& $fail ("app/sw.js's VERSION did not change: it was " + $Before + " before the deploy, and is still")) }
    foreach ($f in @($Files)) {
        $a = $f.answer
        if ($null -eq $a -or $a.state -cne "known" -or [int]$a.value.status -ne 200) { return (& $fail ($f.path + " did not answer 200" + $(if ($null -ne $a -and $a.state -ceq "known") { " (it answered " + $a.value.status + ")" } else { "" }))) }
    }
    return [pscustomobject]@{ ok = $true; reason = ("app/sw.js serves VERSION " + $now + $(if ($Before -ne "") { " (it was " + $Before + ")" } else { "" }) + ", and " + @($Files).Count + " changed file(s) answer 200") }
}

function Add-HordeRelayPublishNotice {
    # Queue -What to be told, once by -Key: a key already told is not queued again. Returns the state.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$What, [Parameter(Mandatory = $true)][string]$Key, [AllowEmptyString()][string]$Revision = "", [Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][datetime]$At)
    if (@($State.told) -ccontains $Key) { return $State }
    $State.told = [string[]]@(@($State.told) + $Key | Select-Object -Last $script:HordeRelayPublishToldMost)
    $State.pending = @(@($State.pending) + [pscustomobject]@{ id = $Id; kind = "page"; what = $What; revision = $Revision; service = "phone-page"; text = ""; at = $At })
    return $State
}

function Invoke-HordeRelayPublishTool {
    # One tool, its LAST output (cli/ServicesTend.ps1, Invoke-HordeServiceTool, says why).
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Name, [object[]]$With = @())
    return (@(& $Tools[$Name] @With) | Select-Object -Last 1)
}

function Invoke-HordeRelayPublishStep {
    # One look at the hosted page, once a pass (header): the lines to say. Never throws for a tool.
    #   -Tools   Now, NewId, Head, Diff, Deploy, Http, SiteMap (New-HordeRelayPublishTools)
    #   -Teller  the pass's teller (Tools.TellAll of cli/ServicesTend.ps1): param($Notices, $HordeHome,
    #            $Policy) -> { told; problem }; $null, or the policy's tellWarchief off, keeps them waiting
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)]$Tools, $Policy = $null, $Teller = $null, [string]$Checkout = "")
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    $lines = New-Object System.Collections.ArrayList
    $now = Invoke-HordeRelayPublishTool -Tools $Tools -Name "Now"
    $say = { param([string]$Line, [switch]$Log) [void]$lines.Add("phone page: " + $Line); if ($Log) { Write-HordeRelayPublishLog -HordeHome $HordeHome -At $now -Line $Line } }
    $kept = Read-HordeRelayPublishState -HordeHome $HordeHome
    if ($kept.state -ceq "unknown") { & $say ("LEFT ALONE - " + $kept.reason); return @($lines.ToArray()) }
    $s = $(if ($kept.state -ceq "known") { $kept.value } else { New-HordeRelayPublishState })
    $queue = { param([string]$What, [string]$Key, [string]$Revision) $null = Add-HordeRelayPublishNotice -State $s -What $What -Key $Key -Revision $Revision -Id (Invoke-HordeRelayPublishTool -Tools $Tools -Name "NewId") -At $now }
    # The look is a block of its own, so each of its ends is a return from IT, and the state is written
    # and the teller called below whichever end it took.
    $look = {
        # A DEPLOY LEFT PART WAY - the pass was ended in the middle of it - is a failed deploy.
        if ($null -ne $s.attempt) {
            $s.failure = [pscustomobject]@{ head = $s.attempt.head; base = $s.attempt.base; at = $s.attempt.at; what = "deploy-failed" }
            & $queue "deploy-failed" ("failed:" + $s.attempt.head) $s.attempt.head
            & $say ("the deploy begun at " + $s.attempt.at.ToString("HH:mm 'UTC'", [System.Globalization.CultureInfo]::InvariantCulture) + " never finished; it is counted as failed") -Log
            $s.attempt = $null
        }
        $head = $null
        try { $head = Invoke-HordeRelayPublishTool -Tools $Tools -Name "Head" -With @($Checkout) } catch { $head = New-HordeUnknown -Reason "the checkout's commit could not be read" -ErrorRecord $_ }
        if (-not (Test-HordeAnswer $head) -or $head.state -cne "known" -or ("" + $head.value.commit) -cnotmatch $script:HordeRelayPublishCommitPattern) {
            & $queue "unreadable" "unreadable:head" ""
            & $say ("NOT DEPLOYED - the checkout's commit could not be read" + $(if ((Test-HordeAnswer $head) -and "" + $head.reason -ne "") { ": " + $head.reason } else { "" })) -Log
            return
        }
        $h = $head.value
        $record = Read-HordeRelayDeployed -HordeHome $HordeHome
        $b = Get-HordeRelayPublishBase -Head $h -Record $record -State $s
        if ($b.kind -ceq "unknown") { & $queue $b.what $b.key $h.commit; & $say ("NOT DEPLOYED - " + $b.reason + "; a deploy by hand records it"); return }
        if ($b.kind -ceq "same") {
            if ($null -ne $s.failure) { $s.failure = $null; & $say ("the hosted page is on " + (ConvertTo-HordeRelayPublishShort $h.commit) + "; the failure before is settled") -Log }
            else { & $say ("current - " + $b.reason) }
            return
        }
        # A checkout with changes of its own would be built as it is, not as its commit says.
        if ($h.clean -ne $true) { & $queue "dirty" ("dirty:" + $h.commit) $h.commit; & $say "NOT DEPLOYED - the checkout has changes of its own" -Log; return }
        $diff = $null
        try { $diff = Invoke-HordeRelayPublishTool -Tools $Tools -Name "Diff" -With @($Checkout, $b.base, $h.commit) } catch { $diff = New-HordeUnknown -Reason "the revision tool failed" -ErrorRecord $_ }
        if (-not (Test-HordeAnswer $diff) -or $diff.state -cne "known") {
            & $queue "unreadable" ("unreadable:" + $b.base + ":" + $h.commit) $h.commit
            & $say ("NOT DEPLOYED - what changed since " + (ConvertTo-HordeRelayPublishShort $b.base) + " could not be read" + $(if ((Test-HordeAnswer $diff) -and "" + $diff.reason -ne "") { ": " + $diff.reason } else { "" })) -Log
            return
        }
        $classes = Get-HordeRelayPublishClasses -Paths @($diff.value.paths)
        $d = Get-HordeRelayPublishDecision -Classes $classes -State $s -Now $now -Base $b.base
        if ($d.action -ceq "nothing") { & $say ("current - " + $d.reason); return }
        if ($d.action -ceq "wait") { & $say ("waits - " + $d.reason); return }
        if ($d.action -ceq "warn") {
            if (@($s.told) -cnotcontains $d.key) { & $say ("NOT DEPLOYED - " + $d.reason + " (" + (ConvertTo-HordeRelayPublishShort $b.base) + ".." + (ConvertTo-HordeRelayPublishShort $h.commit) + ")") -Log } else { & $say ("not deployed - " + $d.reason) }
            & $queue $d.what $d.key $h.commit
            return
        }
        # THE DEPLOY. The VERSION served before it is read from the origin the last deploy answered
        # with; the attempt is written down first, so a pass ended part way is counted (above).
        & $say ("deploying " + (ConvertTo-HordeRelayPublishShort $h.commit) + " - " + $d.reason) -Log
        $before = ""
        if ($record.state -ceq "known") {
            $was = $null
            try { $was = Invoke-HordeRelayPublishTool -Tools $Tools -Name "Http" -With @($record.value.origin + "/app/sw.js") } catch { $was = $null }
            $before = Get-HordeRelayPublishVersion -Answer $was
        }
        $s.attempt = [pscustomobject]@{ head = $h.commit; base = $b.base; at = $now }
        Write-HordeRelayPublishState -State $s -HordeHome $HordeHome
        $log = { param($Line) Write-HordeRelayPublishLog -HordeHome $HordeHome -At $now -Line ("  " + $Line) }
        $r = $null
        try { $r = Invoke-HordeRelayPublishTool -Tools $Tools -Name "Deploy" -With @($HordeHome, $log, $Checkout) } catch { $r = New-HordeUnknown -Reason "the deploy failed" -ErrorRecord $_ }
        $s.attempt = $null
        if ((Test-HordeAnswer $r) -and $r.state -ceq "unknown" -and $r.reason -ceq (Get-HordeRelayDeployBusyReason)) { & $say "waits - another deploy is running; the next pass looks again" -Log; return }
        $failed = { param([string]$What, [string]$Why)
            $s.failure = [pscustomobject]@{ head = $h.commit; base = $b.base; at = $now; what = $What }
            & $queue $What ("failed:" + $h.commit) $h.commit
            & $say ("FAILED - " + $Why + "; tried again an hour from now at the earliest") -Log
        }
        if (-not (Test-HordeAnswer $r) -or $r.state -cne "known") { & $failed "deploy-failed" ("the deploy did not work: " + $(if (Test-HordeAnswer $r) { $r.reason } else { "it did not answer" })); return }
        $origin = "" + $r.value.origin
        $map = $null
        try { $map = Invoke-HordeRelayPublishTool -Tools $Tools -Name "SiteMap" } catch { $map = $null }
        if ($null -eq $map) { & $failed "check-failed" "the deploy worked, but the list of files the site serves could not be had to check it"; return }
        $after = $null
        try { $after = Invoke-HordeRelayPublishTool -Tools $Tools -Name "Http" -With @($origin + "/app/sw.js") } catch { $after = $null }
        $files = New-Object System.Collections.ArrayList
        foreach ($p in @(Get-HordeRelayPublishServed -Changed @($classes.page) -SiteMap $map)) {
            $a = $null
            try { $a = Invoke-HordeRelayPublishTool -Tools $Tools -Name "Http" -With @($origin + "/" + $p) } catch { $a = $null }
            [void]$files.Add([pscustomobject]@{ path = $p; answer = $a })
        }
        $check = Test-HordeRelayPublishCheck -Before $before -Built ("" + $r.value.version) -After $after -Files @($files.ToArray())
        if (-not $check.ok) { & $failed "check-failed" ("deployed, but the check failed: " + $check.reason); return }
        $s.failure = $null
        & $queue "deployed" ("deployed:" + $h.commit) $h.commit
        & $say ("DEPLOYED " + (ConvertTo-HordeRelayPublishShort $h.commit) + " and checked: " + $check.reason) -Log
    }
    try { $null = & $look } finally {
        # TELLING IS LAST: what waits is handed to the teller in one call, and kept until it is taken.
        try { Write-HordeRelayPublishState -State $s -HordeHome $HordeHome } catch { [void]$lines.Add("phone page: its state could not be written: " + $_.Exception.Message) }
        if (@($s.pending).Count -gt 0) {
            if ($null -ne $Policy -and $Policy.tellWarchief -ne $true) { [void]$lines.Add("phone page: " + @($s.pending).Count + " notice(s) wait untold: telling is switched off (the setting tellWarchief)") }
            elseif ($null -eq $Teller) { [void]$lines.Add("phone page: " + @($s.pending).Count + " notice(s) wait untold: nothing here can tell anyone") }
            else {
                $answer = $null
                try { $answer = @(& $Teller @($s.pending) $HordeHome $Policy) | Select-Object -Last 1 } catch { $answer = [pscustomobject]@{ told = @(); problem = $_.Exception.Message } }
                $told = @()
                if ($null -ne $answer -and $null -ne $answer.PSObject.Properties["told"]) { $told = @($answer.told | ForEach-Object { "" + $_ }) }
                $left = @(@($s.pending) | Where-Object { $told -cnotcontains $_.id })
                if ($left.Count -ne @($s.pending).Count) {
                    $s.pending = $left
                    try { Write-HordeRelayPublishState -State $s -HordeHome $HordeHome } catch { }
                }
                if ($left.Count -gt 0) { [void]$lines.Add("phone page: " + $left.Count + " notice(s) wait untold" + $(if ($null -ne $answer -and "" + $answer.problem -ne "") { ": " + $answer.problem } else { "" }) + "; they are tried again next pass") }
            }
        }
    }
    return @($lines.ToArray())
}

function Get-HordeRelayPublishRevision {
    # The checkout's { commit; clean } through the revision tool (cli/ServicesAct.ps1,
    # Invoke-HordeServiceGit): known, or unknown with why. clean ignores files the checkout does not
    # track: the site is built from a list of tracked files (cli/RelayDeploy.ps1).
    param([Parameter(Mandatory = $true)][string]$Checkout)
    $head = Invoke-HordeServiceGit -Checkout $Checkout -Arguments @("rev-parse", "--verify", "HEAD") -TimeoutSeconds $script:HordeRelayPublishGitSeconds
    if (-not $head.ok -or $head.out -cnotmatch $script:HordeRelayPublishCommitPattern) { return (New-HordeUnknown -Reason ("the checkout's commit could not be read" + $(if ($head.detail -ne "") { ": " + $head.detail } else { "" }))) }
    $st = Invoke-HordeServiceGit -Checkout $Checkout -Arguments @("status", "--porcelain", "--untracked-files=no") -TimeoutSeconds $script:HordeRelayPublishGitSeconds
    if (-not $st.ok) { return (New-HordeUnknown -Reason ("whether the checkout has changes could not be read: " + $st.detail)) }
    return (New-HordeKnown -Value ([pscustomobject]@{ commit = $head.out; clean = [bool]($st.out -eq "") }))
}

function Get-HordeRelayPublishChanged {
    # The paths that differ between two commits: known { paths } or unknown. Both are full commit ids,
    # checked before they reach the revision tool, so neither can be read as a flag.
    param([Parameter(Mandatory = $true)][string]$Checkout, [Parameter(Mandatory = $true)][string]$Base, [Parameter(Mandatory = $true)][string]$Head)
    if ($Base -cnotmatch $script:HordeRelayPublishCommitPattern -or $Head -cnotmatch $script:HordeRelayPublishCommitPattern) { return (New-HordeUnknown -Reason "a commit to compare is not a full commit id") }
    # --no-renames: a moved file is its old path AND its new one, so a move out of the relay is seen.
    $r = Invoke-HordeServiceGit -Checkout $Checkout -Arguments @("diff", "--name-only", "--no-renames", $Base, $Head) -TimeoutSeconds $script:HordeRelayPublishGitSeconds
    if (-not $r.ok) { return (New-HordeUnknown -Reason $r.detail) }
    return (New-HordeKnown -Value ([pscustomobject]@{ paths = [string[]]@(("" + $r.out) -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }) }))
}

function Get-HordeRelayPublishUrl {
    # GET -Url with a short time limit: known { status; body } (any status), or unknown when nothing
    # answered. Only an https origin's address is asked; the cache is told to answer afresh.
    param([Parameter(Mandatory = $true)][string]$Url, [int]$TimeoutSeconds = $script:HordeRelayPublishHttpSeconds)
    if ($Url -cnotmatch '\Ahttps://[a-z0-9.-]+(:[0-9]{1,5})?/') { return (New-HordeUnknown -Reason "only an https address of the relay is asked") }
    Add-Type -AssemblyName System.Net.Http
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    $http = New-Object System.Net.Http.HttpClient
    try {
        $http.Timeout = [System.TimeSpan]::FromSeconds($TimeoutSeconds)
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $Url)
        $req.Headers.CacheControl = New-Object System.Net.Http.Headers.CacheControlHeaderValue
        $req.Headers.CacheControl.NoCache = $true
        $res = $http.SendAsync($req).GetAwaiter().GetResult()
        $body = ""
        if ([int]$res.StatusCode -eq 200) { $body = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult() }
        return (New-HordeKnown -Value ([pscustomobject]@{ status = [int]$res.StatusCode; body = $body }))
    } catch { return (New-HordeUnknown -Reason ("the relay did not answer for " + $Url) -ErrorRecord $_) }
    finally { $http.Dispose() }
}

function New-HordeRelayPublishTools {
    # The real tools (header). -Root is this checkout: the files the relays and the deploy load from.
    # THE BLOCKS TAKE WHAT THEY NEED AS ARGUMENTS (cli/ServicesTend.ps1 says why), and the deploy loads
    # the relays inside its own block, as the pass's teller loads the messengers, so a pass that does
    # not deploy - nearly every pass - never pays for them.
    return @{
        Now     = { return [datetime]::UtcNow }
        NewId   = { return [guid]::NewGuid().ToString() }
        Head    = { param($Checkout) return (Get-HordeRelayPublishRevision -Checkout $Checkout) }
        Diff    = { param($Checkout, $Base, $Head) return (Get-HordeRelayPublishChanged -Checkout $Checkout -Base $Base -Head $Head) }
        Http    = { param($Url) return (Get-HordeRelayPublishUrl -Url $Url) }
        SiteMap = { return (Get-HordeRelayDeploySiteSources) }
        Deploy  = {
            param($HordeHome, $Say, $Checkout)
            # A TEST'S HOME DEPLOYS NOTHING, whatever called this (cli/ServicesTell.ps1 says why a home
            # under the temp folder is a suite's).
            if (Test-HordeServiceHomeIsATests -HordeHome $HordeHome) { return (New-HordeUnknown -Reason "this Horde home is under the temp folder, so it is a test's: nothing is deployed") }
            $rev = Get-HordeRelayPublishRevision -Checkout $Checkout
            . (Join-Path $Checkout "relays\Port.ps1")
            foreach ($f in @(Get-HordeRelayFiles)) { . $f }
            . (Join-Path $Checkout "cli\RelayDeploy.ps1")
            return (Invoke-HordeRelayDeploy -HordeHome $HordeHome -Say $Say -Revision $(if ($rev.state -ceq "known") { $rev.value } else { $null }))
        }
    }
}
