# cli/ServicesTell - how the supervisor of services tells the warchief's session that a service is in
# trouble, or out of it: through the messenger port, never by typing into anything.
#
# WHY A MESSENGER (messengers/Port.ps1). A notice typed into a session's input box is the defect
# family the fleet's mail was built to end - it splices into whatever is being typed there. So the
# notice is a message, posted through whichever loaded messenger offers body.untyped and
# idempotent.post: the first keeps it out of any input box, the second makes a notice posted again
# under the same id - after a pass that could not record it was sent - one notice, not two.
#
# WHO IT GOES TO. The session holding the role of warchief (core/SessionSeat.ps1), as the decisions
# doorbell's notices do (decisions/Notify.ps1). No session, or two that both claim the role, is nobody
# to tell: nothing is posted, the reason is returned, and the notices wait in the services' state
# files for the next pass (cli/ServicesTend.ps1, Send-HordeServicePending).
#
# WHAT IT SAYS: FIXED WORDS, AND NOTHING FROM OUTSIDE (safety review of the first build, item 9). The
# first version told the trouble's own sentence, and that sentence carries reasons - up to 600
# characters of the revision tool's error output, of what the FETCHED code printed when its check
# failed, of local paths. A notice is read by an AI session; text that a remote repository's author
# can shape must never be put in front of one as if Horde had said it. So a notice is told as the
# service's name - a name this machine's owner chose, held to a pattern - and one fixed sentence for
# each KIND of trouble, chosen from the closed list below by the kind alone. The reason stays where
# a person reads it: horde services status, and the journal.
#
# A TEST'S HOME TELLS NOBODY. A Horde home under the temp folder is a suite's; a tell from one is
# refused before any messenger or any session's record is looked for, whatever its settings say. The
# setting tellWarchief is one guard and this is the other, because the seat is found in a store whose
# place does not follow the Horde home (item 7).
#
# THE CALLER LOADS THE PORT, THROUGH Invoke-HordeServiceWithMessengers (below). messengers/Port.ps1, every
# messenger's file, core/SessionSeat.ps1 and core/Device.ps1 must have been dot-sourced in the scope this is
# called from, so the blocks a messenger registered can still see its helpers. A pass may need the port
# twice (the look at the awaiting list, then the teller), so the loader is safe to run any number of times
# in one process and in either order.
#
# A NOTICE COUNTS AS TOLD ONLY WHEN THE WARCHIEF'S OWN SESSION TOOK IT (T-0391 slice 6; the chat's own rule, channels/chat/Taken.ps1,
# and the routed answers', the doorbell's, the photo notice's and the relay-full notice's: decisions/NoticeTaken.ps1, used as it is). The
# messenger ACCEPTING the post was counted as the warchief being told, and the notice was then forgotten for good. Now:
#   - MARK FIRST, THEN POST. Send-HordeServiceNotices puts each notice on the awaiting list BEFORE it posts. A list that cannot be read
#     or written means no post, the reason said, and the notice kept waiting in its state file for the next pass.
#   - A post the messenger REFUSES (a known answer with another stage) takes its mark off; an UNKNOWN result keeps it, for a post that may
#     have landed must stay watched.
#   - DELIVERED is the session's own TAKEN (handed-over or seen), said by Invoke-HordeServiceTellTakenTick; accepted is not.
#   - ONE ALARM at takenAlarmSeconds without a TAKEN, asked about every takenAfterAlarmSeconds after it, given up with a second ALARM
#     when the notice is 7 days old. The pass is a new process every minute, so when each mark was last asked is kept in a small file.
#   - A RESTART DOES NOTHING TWICE. The list is a file, the alarm is in the mark, and a notice keeps ONE id for as long as it waits (the
#     state file's notice id, the page's pending id, the installed CLI's kept id), so wezfleet keeps one message (lib/MailPost.ps1
#     already-posted). A new event is a new notice with a new id: a repeat of an old id would wake nobody.
#   - THE LINES REACH THE PASS'S OUTPUT: the tick's lines, and the lines of a post (a full list given up, an already-posted copy), are
#     returned to the supervisor (cli/ServicesTend.ps1), which says them with the rest of the pass.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "decisions\NoticeTaken.ps1")

# The awaiting list of these notices: one file under the home, the words its lines use (decisions/NoticeTaken.ps1).
$script:HordeServiceTellTakenKind = New-HordeDecisionNoticeKind -Path @("services", "tell-taken.json") -TempPrefix "services-tell-taken" -Ledger "the services notices' awaiting ledger" -List "the awaiting list of services notices" -Label "services" -Notice "services notice" -Owner "the warchief's" -Detail { param($Entry) return "from the supervisor of services" }
$script:HordeServiceTellTakenAskedFile = "tell-taken-asked.txt"
$script:HordeServiceTellNeeds = @("body.untyped", "idempotent.post", "receipt.receiver")
$script:HordeServiceTellRole = "warchief"
# Who a notice is from: the supervisor is no session, so it names itself in a session id's shape, and
# wears the label of the setting fromLabel (a messenger may hold a message whose sender it cannot place).
$script:HordeServiceTellFrom = "horde-services"
# How long a notice may wait in a mailbox: the link's most, 7 days (messengers/Port.ps1).
$script:HordeServiceTellTtlSeconds = 604800
$script:HordeServiceTellStages = @("accepted", "handed-over", "seen")

# One fixed sentence a kind of trouble (core/Services.ps1 names the kinds: the part of a trouble's key
# before any revision). A kind that is not here is told as the last line says, never by its own text.
$script:HordeServiceTellSentences = [ordered]@{
    "failing"          = "it keeps failing to stay up; it is still being tried, slowly"
    "ended-itself"     = "it ended itself on purpose and is held; it is not started again until a person lets it go"
    "rolled-back"      = "an update did not come up and was rolled back; that revision is not tried again"
    "retreat"          = "an update did not come up and could NOT be rolled back; its checkout needs a person"
    "half-moved"       = "its checkout was left part way through a move; nothing is started from it until a person has put it right"
    "checkout"         = "its checkout cannot take an update as it is; nothing was touched"
    "verify"           = "a new revision failed its check; the old one keeps running"
    "apply"            = "a new revision could not be put in place; the old one keeps running"
    "stuck"            = "its process should have ended and could not be ended"
    "start-unrecorded" = "a start of it was interrupted and it keeps no heartbeat, so whether it is running cannot be told"
    "keys-unavailable" = "it is running and cannot use this machine's keys, so nothing from the phone is opened; it is restarted, more slowly each time, and should work once someone has signed in"
    "unwell"           = "it is running and says it cannot do its work; it is restarted, more slowly each time"
    "update-held"      = "an update is held, neither confirmed nor rolled back, because its new revision says it cannot work; it is confirmed once that mends"
    "update-withdrawn" = "an update was held too long and is withdrawn, not pinned; it is taken again later"
    "no-desktop"       = "it needs the person's desktop, which the pass that runs before anyone signs in cannot reach; it is started once someone signs in"
}
$script:HordeServiceTellNamePattern = '\A[a-z][a-z0-9-]{0,39}\z'

# THE HOSTED PHONE PAGE (cli/RelayPublish.ps1) is told in the same way: one fixed sentence for each
# outcome, chosen by its what alone, and the commit only when it is a commit id. Its notices are of the
# kind "page", and do not say "needs attention" when the news is that it was deployed.
$script:HordeServiceTellPageSentences = [ordered]@{
    "deployed"      = "the supervisor deployed the phone page and checked it: the hosted page serves the new version"
    "deploy-failed" = "the supervisor's deploy of the phone page failed; it is tried again an hour later at the earliest, or a person runs: horde relay deploy"
    "deploy-needs-action" = "the supervisor deployed the relay and it IS live, but its sign-in failed the check after the deploy, so nobody can sign in; a person acts now: deploy again from a fixed checkout (horde relay deploy), then check that the relay's /auth/google redirects to Google"
    "check-failed"  = "the supervisor deployed the phone page, but the hosted page did not then serve exactly what was built; it is tried again an hour later at the earliest"
    "worker-changed" = "the relay's Worker changed since the last deploy, so the supervisor did not deploy the phone page; a person reads the change, then runs: horde relay deploy"
    "worker-unmeasured" = "files the relay's Worker shares with the phone page changed, and whether the Worker itself changed could not be measured, so the supervisor did not deploy; a person checks, then runs: horde relay deploy"
    "not-on-main"   = "the checkout the supervisor runs from is on a commit that is not on origin/main, so it never deploys the phone page from it"
    "no-record"     = "nothing records a clean commit the hosted phone page was deployed from, so the supervisor does not deploy it; one deploy by hand from a clean checkout (horde relay deploy) records it"
    "unreadable"    = "what changed since the phone page was last deployed could not be read, so the supervisor did not deploy it"
    "diverged"      = "the phone page is hosted from a commit unrelated to the checkout the supervisor runs from (neither holds the other), so it never deploys; a person decides which is right"
    "record-absent" = "the phone page is hosted from a commit the checkout the supervisor runs from has not held for several passes in a row, so it did not deploy; a person checks the checkout and its fetch"
    "dirty"         = "the checkout the phone page is built from has changes of its own, so the supervisor did not deploy it"
}

function Format-HordeServicePageNoticeBody {
    # PURE. The words of one notice about the hosted phone page (above).
    param([Parameter(Mandatory = $true)]$Notice)
    $what = "" + $Notice.what
    $said = $(if ($script:HordeServiceTellPageSentences.Contains($what)) { $script:HordeServiceTellPageSentences[$what] } else { "it needs a person" })
    $rev = ""
    $named = $Notice.PSObject.Properties["revision"]
    if ($null -ne $named -and "" + $named.Value -cmatch '\A[0-9a-f]{7,40}\z') { $rev = " (commit " + ("" + $named.Value).Substring(0, 7) + ")" }
    return ("HORDE SERVICES - phone page" + $(if ($what -ceq "deployed") { "" } else { " needs attention" }) + "`n" + $said + $rev + "`nIts log: relay\publish-log.txt in the Horde home")
}

# THE INSTALLED CLI (cli/ServicesBin.ps1), told in the same way: kind "cli", one fixed sentence chosen
# by its what alone.
$script:HordeServiceTellCliSentences = [ordered]@{
    "branch"   = "the installed CLI is not on the branch main, so it is not being kept current; a person puts it back on main"
    "dirty"    = "the installed CLI has changed files of its own, so it is not being kept current; a person commits or discards them"
    "diverged" = "the installed CLI holds commits that origin/main does not, and origin/main has moved on, so it cannot be fast-forwarded; a person reconciles it"
    "ahead"    = "the installed CLI is ahead of origin/main: it holds commits origin/main does not, so it is not being moved; a person pushes or discards them"
    "apply"    = "the installed CLI could not be fast-forwarded to origin/main; it was left as it was"
    "failed"   = "a new revision of the CLI did not load when it was tried, so the installed CLI was left on the revision it was on; that revision is not tried again until origin/main moves on"
    "stuck"    = "the installed CLI did not load after an update and could NOT be put back; it is reported broken until a revision that loads is live; a person must repair it now"
}

function Format-HordeServiceCliNoticeBody {
    # PURE. The words of one notice about the installed CLI: fixed sentences only.
    param([Parameter(Mandatory = $true)]$Notice)
    $what = "" + $Notice.what
    $said = $(if ($script:HordeServiceTellCliSentences.Contains($what)) { $script:HordeServiceTellCliSentences[$what] } else { "it needs a person" })
    return ("HORDE SERVICES - installed CLI needs attention`n" + $said + "`nSee it with: horde services status")
}

function Format-HordeServiceNoticeBody {
    # PURE. The words of one notice (header): the service's name and fixed sentences, by the notice's
    # kind and its what - never its text. A name that is not a service name is not repeated either.
    param([Parameter(Mandatory = $true)]$Notice)
    if ("" + $Notice.kind -ceq "cli") { return (Format-HordeServiceCliNoticeBody -Notice $Notice) }
    if ("" + $Notice.kind -ceq "page") { return (Format-HordeServicePageNoticeBody -Notice $Notice) }
    $service = "a service"
    $named = $Notice.PSObject.Properties["service"]
    if ($null -ne $named -and "" + $named.Value -cmatch $script:HordeServiceTellNamePattern) { $service = "service " + $named.Value }
    if ("" + $Notice.kind -ceq "recovered") { return ("HORDE SERVICES - recovered`n" + $service + ": what it was told about is over, and it is running`nSee it with: horde services status") }
    $said = New-Object System.Collections.ArrayList
    $what = $Notice.PSObject.Properties["what"]
    if ($null -ne $what) { foreach ($w in @(("" + $what.Value) -split ",")) { if ($script:HordeServiceTellSentences.Contains($w) -and -not $said.Contains($script:HordeServiceTellSentences[$w])) { [void]$said.Add($script:HordeServiceTellSentences[$w]) } } }
    # A condition is told as "unwell" only when its own word has no sentence here (core/Services.ps1).
    if ($said.Count -gt 1 -and $said.Contains($script:HordeServiceTellSentences["unwell"])) { $said.Remove($script:HordeServiceTellSentences["unwell"]) }
    if ($said.Count -eq 0) { [void]$said.Add("it needs a person") }
    return ("HORDE SERVICES - needs attention`n" + $service + ": " + ($said -join "; ") + "`nSee it with: horde services status")
}

function Test-HordeServiceHomeIsATests {
    # Is -HordeHome under the temp folder (header, A TEST'S HOME TELLS NOBODY)? Compared resolved and
    # without case. A home that cannot be resolved is treated as a test's: telling nobody is the
    # safe mistake.
    param([string]$HordeHome, [string]$TempRoot = "")
    if ($TempRoot -eq "") { $TempRoot = [System.IO.Path]::GetTempPath() }
    try {
        $root = [System.IO.Path]::GetFullPath($TempRoot).TrimEnd('\', '/') + '\'
        $full = [System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\', '/') + '\'
        return [bool]$full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)
    } catch { return $true }
}

function Send-HordeServiceNotices {
    # Post each notice to the warchief's session, marked first: { told; problem; lines }. told is the ids a messenger took (each is then
    # on the awaiting list, and only the session's own TAKEN makes it delivered); problem is why the rest were not, in one sentence, or
    # "". lines are for the pass's output. Never throws for the far end.
    # -Seat is for a suite that hands in its own.
    param([Parameter(Mandatory = $true)]$Notices, [string]$HordeHome = "", [Parameter(Mandatory = $true)]$Policy, [scriptblock]$Seat = $null, [string]$TempRoot = "", $Now = $null)
    $told = New-Object System.Collections.ArrayList
    $lines = New-Object System.Collections.ArrayList
    $done = { param([string]$Problem) return [pscustomobject]@{ told = [string[]]@($told.ToArray()); problem = $Problem; lines = [string[]]@($lines.ToArray()) } }
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    # BEFORE ANYTHING IS LOOKED FOR: a test's home tells nobody (header).
    if (Test-HordeServiceHomeIsATests -HordeHome $HordeHome -TempRoot $TempRoot) { return (& $done "this Horde home is under the temp folder, so it is a test's: nobody is told") }
    $found = Find-HordeMessenger -Require $script:HordeServiceTellNeeds
    if ($found.state -ceq "absent") { return (& $done ("no messenger on this machine can deliver to a session (" + $found.reason + ")")) }
    if ($found.state -cne "known") { return (& $done ("no messenger was chosen: " + $found.reason)) }
    $messenger = $found.value
    if ($null -eq $Seat) { $Seat = { return (Get-HordeRoleSeat -Role $script:HordeServiceTellRole) } }
    $where = $null
    try { $where = @(& $Seat) | Select-Object -Last 1 } catch { $where = New-HordeUnknown -Reason "the seat could not be read" -ErrorRecord $_ }
    if ($null -eq $where -or "$($where.state)" -ceq "absent") { return (& $done ("no session holds the role of " + $script:HordeServiceTellRole + ", so there is nobody to tell")) }
    if ("$($where.state)" -cne "known") { return (& $done ("the " + $script:HordeServiceTellRole + "'s session cannot be told: " + $where.reason)) }
    $deviceId = ""
    try { $deviceId = Get-HordeDeviceId -HomeRoot $HordeHome } catch { return (& $done ("this machine's device id could not be had: " + $_.Exception.Message)) }
    $problem = ""
    $at = $(if ($Now -is [datetime]) { $Now.ToUniversalTime() } else { [datetime]::UtcNow })
    foreach ($n in @($Notices)) {
        $message = [pscustomobject]@{
            messageId = "" + $n.id; sessionId = "" + $where.value.sessionId
            from = [pscustomobject]@{ deviceId = $deviceId; sessionId = $script:HordeServiceTellFrom; label = "" + $Policy.fromLabel }
            body = (Format-HordeServiceNoticeBody -Notice $n); ttlSeconds = $script:HordeServiceTellTtlSeconds
        }
        # THE MARK IS WRITTEN BEFORE THE POST. A list that cannot be read or written means nothing is posted (and none of the rest could
        # be either, so the loop ends). A crash between the mark and the post only costs an alarm at takenAlarmSeconds: the next pass
        # posts the same notice id, which the messenger keeps as one.
        $wasListed = Test-HordeServiceNoticeListed -HordeHome $HordeHome -NoticeId $message.messageId
        $awaited = Add-HordeDecisionNoticeTaken -Kind $script:HordeServiceTellTakenKind -HordeHome $HordeHome -NoticeId $message.messageId -Answer 0 -SessionId ("" + $where.value.sessionId) -Now $at
        foreach ($l in @($awaited.lines)) { [void]$lines.Add($l) }
        if (-not $awaited.ok) { $problem = "the notice cannot be awaited (" + $awaited.reason + "); nothing is posted until it can be"; break }
        $posted = Send-HordeMessengerMessage -Messenger $messenger -Message $message
        if ($posted.state -ceq "known" -and $script:HordeServiceTellStages -ccontains "$($posted.value.stage)") {
            # ALREADY POSTED, AND THIS PASS WROTE A BRAND-NEW MARK: the messenger answered with the first copy's stage and woke nobody, so
            # that stage says nothing of THIS post. It is never counted as fresh: the mark is taken off (or the next look would log a TAKEN
            # for a notice never sent again), and the line says so plainly. The notice is not posted again (told), whatever the first copy became.
            if ("$($posted.value.reason)" -clike "already-posted*" -and -not $wasListed) {
                $null = Remove-HordeDecisionNoticeTaken -Kind $script:HordeServiceTellTakenKind -HordeHome $HordeHome -NoticeId $message.messageId
                [void]$lines.Add("services: the notice " + $message.messageId + " was NOT sent again: the messenger already held a copy of it from an earlier post and woke nobody, so it is not counted as delivered")
            }
            [void]$told.Add("" + $n.id)
            continue
        }
        # A REFUSED POST LEAVES NO MARK (the notice is in no mailbox, so a mark would alarm "not taken" for something never sent). ONLY A
        # KNOWN REFUSAL removes it: an UNKNOWN result may have landed, and a notice that landed must stay watched.
        if ($posted.state -ceq "known") {
            $problem = "messenger " + $messenger.name + " answered " + $posted.value.stage
            $removed = Remove-HordeDecisionNoticeTaken -Kind $script:HordeServiceTellTakenKind -HordeHome $HordeHome -NoticeId $message.messageId
            if (-not $removed.ok) { $problem = $problem + "; its awaiting mark could not be removed (" + $removed.reason + ")" }
        }
        else { $problem = "messenger " + $messenger.name + " did not take it: " + $posted.reason }
    }
    return (& $done $problem)
}

function Test-HordeServiceNoticeListed {
    # Is the notice on the awaiting list now? $false too when the list cannot be read (Add then fails and nothing is posted).
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$NoticeId)
    $r = Read-HordeDecisionNoticeTaken -Kind $script:HordeServiceTellTakenKind -HordeHome $HordeHome
    if ($r.state -cne "known") { return $false }
    $id = $NoticeId.Replace("-", "")
    foreach ($mark in @($r.value.awaiting)) { $e = ConvertFrom-HordeChatTakenMark -Mark $mark; if ($null -ne $e -and $e.messageId -ceq $id) { return $true } }
    return $false
}

function Invoke-HordeServiceWithMessengers {
    # Loads the messenger port and every messenger INTO THIS FUNCTION'S SCOPE, runs -Run from here and puts the registry back as it was.
    # Why here and not once per process: the blocks a messenger registers find their helpers only through the scope that is running them
    # (dynamic scope), so each user of the port loads it around its own call, and the helpers go with the function. But the registry is
    # script-wide and refuses a second registration of a name (messengers/Port.ps1, Register-HordeMessenger), so the second load in one
    # process (TellTaken, then TellAll, or the reverse) threw and the notices waited untold on every pass (review of PR 430). Clearing the
    # registry for the load is the right cure, not skipping the load: a skipped load would leave the second user's registered blocks
    # without helpers in a scope that no longer has them. The registry that was there is put back after, so a caller that loaded the port
    # for itself keeps what it registered.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][scriptblock]$Run)
    foreach ($f in @("SessionSeat", "Device")) { . (Join-Path $Root ("core\" + $f + ".ps1")) }
    $had = $null -ne (Get-Variable -Name HordeMessengers -Scope Script -ErrorAction SilentlyContinue)
    $kept = $null
    if ($had) { $kept = $script:HordeMessengers }
    $script:HordeMessengers = @{}
    try {
        . (Join-Path $Root "messengers\Port.ps1")
        foreach ($f in @(Get-HordeMessengerFiles)) { . $f }
        return (& $Run)
    } finally {
        if ($had) { $script:HordeMessengers = $kept } else { Remove-Variable -Name HordeMessengers -Scope Script -ErrorAction SilentlyContinue }
    }
}

function Test-HordeServiceTellAwaiting {
    # Is there a mark to ask about? A quiet pass - nearly every pass - has none, and then loads no messenger. The file stays after the
    # last mark is taken off ({"awaiting":[]}), so its being there says nothing; a list that cannot be read counts as awaiting, so the
    # look is made and says why it cannot be (a notice must never go unwatched for an unreadable file).
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $path = Get-HordeDecisionNoticeTakenPath -Kind $script:HordeServiceTellTakenKind -HordeHome $HordeHome
    if (-not [System.IO.File]::Exists($path)) { return $false }
    $r = Read-HordeDecisionNoticeTaken -Kind $script:HordeServiceTellTakenKind -HordeHome $HordeHome
    if ($r.state -cne "known") { return $true }
    return (@($r.value.awaiting).Count -gt 0)
}

function Read-HordeServiceTellAsked {
    # When each mark was last asked about, by message id (UTC ms): the supervisor's pass is a new process every minute, so the
    # cadence after an alarm needs it kept. A missing or unreadable file is an empty table (every mark is then simply asked).
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $table = @{}
    $path = [System.IO.Path]::Combine($HordeHome, "services", $script:HordeServiceTellTakenAskedFile)
    try {
        if (-not [System.IO.File]::Exists($path)) { return $table }
        foreach ($line in @([System.IO.File]::ReadAllLines($path))) { if ($line -cmatch '\A([0-9a-f]{32}) ([0-9]{1,15})\z') { $table[$Matches[1]] = [long]$Matches[2] } }
    } catch { return @{} }
    return $table
}

function Write-HordeServiceTellAsked {
    # The table, for the marks still awaiting only, replaced whole in one rename. $true when written; never throws.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][hashtable]$Table)
    $path = [System.IO.Path]::Combine($HordeHome, "services", $script:HordeServiceTellTakenAskedFile)
    $tmp = $path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    try {
        $r = Read-HordeDecisionNoticeTaken -Kind $script:HordeServiceTellTakenKind -HordeHome $HordeHome
        if ($r.state -cne "known") { return $false }
        $live = @{}
        foreach ($mark in @($r.value.awaiting)) { $e = ConvertFrom-HordeChatTakenMark -Mark $mark; if ($null -ne $e) { $live[$e.messageId] = $true } }
        $rows = @(foreach ($k in @($Table.Keys | Sort-Object)) { if ($live.ContainsKey($k) -and $Table[$k] -is [long]) { $k + " " + $Table[$k] } })
        if ($rows.Count -eq 0) { if ([System.IO.File]::Exists($path)) { [System.IO.File]::Delete($path) }; return $true }
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
        [System.IO.File]::WriteAllBytes($tmp, [System.Text.Encoding]::ASCII.GetBytes(($rows -join "`n") + "`n"))
        Move-HordeFileAtomic -From $tmp -To $path
        return $true
    } catch { try { [System.IO.File]::Delete($tmp) } catch { }; return $false }
}

function Invoke-HordeServiceTellTakenTick {
    # Ask about the services notices awaiting the warchief's own TAKEN and say what became of them (NoticeTaken.ps1): the lines, for the
    # pass's output. The messenger is found as the notice was posted; when none can be had now the clock alone speaks. Never throws.
    # The caller loads the messenger port (header, THE CALLER LOADS THE PORT) and calls only when Test-HordeServiceTellAwaiting.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][datetime]$Now, [double]$AlarmSeconds = 90, [double]$AfterAlarmSeconds = 300)
    $messenger = $null
    try { $found = Find-HordeMessenger -Require $script:HordeServiceTellNeeds; if ($found.state -ceq "known") { $messenger = $found.value } } catch { $messenger = $null }
    try {
        $memory = Read-HordeServiceTellAsked -HordeHome $HordeHome
        $tick = Invoke-HordeDecisionNoticeTakenTick -Kind $script:HordeServiceTellTakenKind -HordeHome $HordeHome -Messenger $messenger -Now $Now.ToUniversalTime() -AlarmSeconds $AlarmSeconds -AfterAlarmSeconds $AfterAlarmSeconds -TtlSeconds $script:HordeServiceTellTtlSeconds -Memory $memory
        [void](Write-HordeServiceTellAsked -HordeHome $HordeHome -Table $memory)
        return @($tick.lines)
    } catch { return @("services: the awaiting list of services notices could not be asked: " + $_.Exception.Message) }
}
