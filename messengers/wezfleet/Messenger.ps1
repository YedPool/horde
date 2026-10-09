# messengers/wezfleet - hands a message to a session through the fleet's own mail.
#
# WHY THE FLEET'S MAIL (remote plan R21). wezfleet already delivers between sessions on one machine the
# way Horde must: the body is written to the target's inbox and never typed; the receiving session's own
# Stop hook hands it over at a turn boundary and acks it only once its id is in that session's
# transcript (TAKEN); an idle target gets one short wake notice carrying only the id. Its PR #65 added the
# two commands this messenger runs, so that a program that is not a session can use that path:
#   mail post -To <session uuid> -Id <32 hex> -MessageFile <path> [-FromLabel l] [-FromSessionId uuid] -Json
#   mail status -Id <32 hex> -Json
# THE CONTRACT is wezfleet main's (read at 1122461 on 2026-10-09: its lib/MailPost.ps1, THE CONTRACT, as
# its pull request 70 made it; 72 to 76 left mail post and status as they were). Each prints ONE line of
# ASCII JSON with id, to, stage, reason (a CODE from a closed list) and detail (at most 300 characters of
# text for a person); post adds woken. Exits: 0 post on disk / status found; 1 not this time - write-failed
# (stage absent) or internal-error (stage error), retry the same id; 2 refused input, stage refused
# (bad-id, bad-to, bad-from, bad-file, message-too-large over 256 KB, invalid-utf8, empty-message); 3
# status no record; 4 post stale-session - stage refused when nothing was written because no live process
# is the session, queued when the mail was written but the session's pane is held by another session.
# There is no exit 5. Ids are 32 lower-case hex; -To and -FromSessionId are lower-case session UUIDs.
# -Kind, which main's command line now declares, belongs to tell (its pull request 76): mail post never
# reads it, and this messenger never passes it.
# BEFORE MAIN HAD IT (measured 2026-10-07 against checkouts in an isolated mail root): wezfleet main at
# c49063b had the first shape of #65 - the same fields without detail, a sentence where the code is, and
# no exit 4 - and answered a post to a session no live process is with exit 0, queued, which read as
# accepted for ever. A REASON THAT IS NOT A CODE IS UNKNOWN, post or status, so against a wezfleet that
# old every post is unknown, and nothing is ever decided on a sentence.
#
# THE STAGES, mapped onto the port's (messengers/Port.ps1): queued is accepted, handed-over is
# handed-over, taken is seen, unconfirmed is expired (with a reason), refused (exit 2) is held with the
# code and detail, absent from status (exit 3) is absent, and EXIT 4 IS HELD IN BOTH ITS SHAPES with
# reason stale-session (decided 2026-10-06): nothing reached a live target. Held is final under #97's
# rules; the hub reports it to the sender, and a retry is a new message, never this one re-aimed.
# Anything else - a stage outside the table, a stage that does not go with its exit code (exit 4 with
# "absent", a shape no wezfleet shipped, included), exit 1, an exit code outside the table, output that is
# not exactly one line of JSON of the expected shape, or an answer about another id - is unknown with the
# reason, never a stage guessed. That is also how a wezfleet too old to have these commands shows: its
# usage text is not JSON.
#
# THE REASON the port gets is wezfleet's code, then its detail. THE DETAIL IS NEVER FATAL (review of
# #106, G4): it is cut to one line of printable ASCII and capped, or dropped when it is not text; the
# answer it came with is kept.
#
# THE TARGET (review of #106, G7; decided 2026-10-06). A post's "to" must be the session it was asked to
# post to - except for a repost (reason already-posted), where it names the mailbox the record is in now:
# wezfleet's Repair-WfMailbox moves a mailbox after a compact, by pid and start time only, and a different
# target under the same id is refused upstream by slice 4's args hash. Then the reason says "followed to
# <to>". A status's "to" is never compared - the port asks it by id alone, and slice 4, which journaled
# the target, compares - but it must be a session UUID or empty, and the reason says "at <to>".
#
# WHO WEZFLEET CAN NAME (review of #106, G6; decided 2026-10-06). wezfleet takes -To and -FromSessionId
# only as lower-case session UUIDs and -FromLabel only as a label. So, before any process starts: a
# target that is not a session UUID is held, bad-to; a sender whose session id is not one is named by its
# hub label alone (-FromSessionId is never passed a non-UUID); a sender label that is not a hub label, or
# a sender with neither, is held, bad-from.
#
# THE ONE START SITE (plan R21 slice 3b, merge condition 2). Start-HordeWezfleetMessengerProcess starts the
# fixed PowerShell from the system folder, named once in one expression, on wezfleet.ps1 in the
# configured folder - which it finds itself, so no caller can hand it another script - with -NoProfile
# -NonInteractive -ExecutionPolicy Bypass -File. Its arguments are built as separate elements and joined
# by one quoting function; no element is ever a command string. messengers/start-sites.txt lists the
# start, each property it sets and each call of it, and test/test-start-sites.ps1 refuses anything else.
#
# THE BODY NEVER GOES ON A COMMAND LINE. It is written as UTF-8 to a fresh file in Horde's own folder,
# <HORDE_HOME>\messengers\wezfleet\outgoing, whose access list is made to grant full control to this user
# alone, inheriting nothing, before a body goes in (review of #106, G3). It is handed over by
# -MessageFile and deleted when the command has answered, whatever it answered; a node killed in between
# leaves it behind, so the node sweeps the folder when it starts (Clear-HordeWezfleetMessengerOutgoing).
#
# WHERE THE FLEET IS, is configuration, never a guess: Set-HordeWezfleetMessengerRoot names the folder
# (the node sets it from its own configuration, slice 4). It must be an absolute local folder with no ..,
# no reparse point on it or above it - a junction could be re-aimed after it was configured - and a
# wezfleet checkout with #65's mail commands: wezfleet.ps1, lib\Mail.ps1, lib\MailPost.ps1 and
# commands\mail.ps1 (review of #106, G1). Otherwise every call is unknown and nothing starts. Every call
# has a deadline; past it the child is stopped and the answer is unknown.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced, after messengers/Port.ps1.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Home.ps1")

$script:HordeWezfleetMessengerFolder = $PSScriptRoot
$script:HordeWezfleetMessengerRoot = ""
$script:HordeWezfleetMessengerTimeoutSeconds = 30
$script:HordeWezfleetMessengerScript = "wezfleet.ps1"
# What makes a folder a wezfleet checkout with #65's commands, beside the script itself.
$script:HordeWezfleetMessengerMarkers = @("wezfleet.ps1", "lib\Mail.ps1", "lib\MailPost.ps1", "commands\mail.ps1")
# The most a command may print before it is stopped: one line of JSON is far below this.
$script:HordeWezfleetMessengerMaxBytes = 65536
# The most of wezfleet's detail kept in a reason; the port caps a reason at 1024 bytes.
$script:HordeWezfleetMessengerDetailChars = 600
# wezfleet's session id (its -To and -FromSessionId), and Horde's hub label (its -FromLabel).
$script:HordeWezfleetMessengerSessionPattern = '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'
$script:HordeWezfleetMessengerLabelPattern = '\A[A-Z]{1,2}([1-9][0-9]{0,3})?\z'
# A reason code: lower-case words joined by dashes (woken, already-posted, stale-session, ...). A
# sentence is not one.
$script:HordeWezfleetMessengerCodePattern = '\A[a-z]+(-[a-z]+)*\z'
$script:HordeWezfleetMessengerStages = @{ "queued" = "accepted"; "handed-over" = "handed-over"; "taken" = "seen"; "unconfirmed" = "expired"; "refused" = "held" }
# Which stages each exit code may carry, per command. Anything else is unknown.
$script:HordeWezfleetMessengerExits = @{
    post = @{ 0 = @("queued", "handed-over", "taken", "unconfirmed"); 2 = @("refused"); 4 = @("refused", "queued") }
    status = @{ 0 = @("queued", "handed-over", "taken", "unconfirmed"); 3 = @("absent") }
}

function Set-HordeWezfleetMessengerRoot {
    # Name the folder holding the fleet's wezfleet.ps1, and the deadline of each call. "" unsets it.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path, [int]$TimeoutSeconds = 30)
    if ($TimeoutSeconds -lt 1) { throw ("TimeoutSeconds must be at least 1, not " + $TimeoutSeconds) }
    $script:HordeWezfleetMessengerRoot = $Path
    $script:HordeWezfleetMessengerTimeoutSeconds = $TimeoutSeconds
}

function Get-HordeWezfleetMessengerScriptPath {
    # The fleet's script, as { ok; path; reason }: only in an absolute local folder with no .., no reparse
    # point on its path, holding every marker of a wezfleet checkout with #65's commands.
    $dir = $script:HordeWezfleetMessengerRoot
    if ("$dir" -eq "") { return [pscustomobject]@{ ok = $false; path = ""; reason = "the wezfleet folder is not configured, so the fleet's command was not run" } }
    if (-not [System.IO.Path]::IsPathRooted($dir) -or $dir -notmatch '\A[A-Za-z]:\\' -or @($dir -split '[\\/]') -contains "..") {
        return [pscustomobject]@{ ok = $false; path = ""; reason = ("the wezfleet folder '" + $dir + "' is not an absolute local folder without .., so it was not used") }
    }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return [pscustomobject]@{ ok = $false; path = ""; reason = ("the wezfleet folder '" + $dir + "' does not exist") } }
    # NO REPARSE POINT on the folder or any folder above it: each is read as it is, not followed.
    $d = New-Object System.IO.DirectoryInfo($dir)
    while ($null -ne $d) {
        if (($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            return [pscustomobject]@{ ok = $false; path = ""; reason = ("the wezfleet folder '" + $dir + "' has a reparse point on its path ('" + $d.FullName + "'), so it was not used") }
        }
        $d = $d.Parent
    }
    foreach ($marker in $script:HordeWezfleetMessengerMarkers) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir $marker) -PathType Leaf)) {
            return [pscustomobject]@{ ok = $false; path = ""; reason = ("'" + $dir + "' is not a wezfleet checkout with the mail commands: no " + $marker + " in it") }
        }
    }
    return [pscustomobject]@{ ok = $true; path = (Join-Path $dir $script:HordeWezfleetMessengerScript); reason = "" }
}

function Get-HordeWezfleetMessengerOutgoing {
    # Horde's own folder for body files, made if it is not there, and its access list made this user's
    # alone - full control, nothing inherited - if it is not so already. Returns its path.
    $dir = Join-Path (Get-HordeHome) "messengers\wezfleet\outgoing"
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
    if (-not (Test-HordeWezfleetMessengerUserOnly -Path $dir)) {
        $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $sec = New-Object System.Security.AccessControl.DirectorySecurity
        $sec.SetAccessRuleProtection($true, $false)
        $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($me, [System.Security.AccessControl.FileSystemRights]::FullControl, $inherit, [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow)
        $sec.AddAccessRule($rule)
        [System.IO.Directory]::SetAccessControl($dir, $sec)
    }
    return $dir
}

function Test-HordeWezfleetMessengerUserOnly {
    # Is the folder's access list protected from inheritance, with one rule: full control for this user?
    param([Parameter(Mandatory = $true)][string]$Path)
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = [System.IO.Directory]::GetAccessControl($Path)
    $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    if (-not $acl.AreAccessRulesProtected -or $rules.Count -ne 1) { return $false }
    $r = $rules[0]
    return ($r.IdentityReference.Value -ceq $me.Value -and $r.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and
        ($r.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) -eq [System.Security.AccessControl.FileSystemRights]::FullControl)
}

function Clear-HordeWezfleetMessengerOutgoing {
    # The node's start sweep: every body file a killed node left behind is removed. Returns how many.
    # Run only at start, when no post of this node can be in flight.
    $dir = Join-Path (Get-HordeHome) "messengers\wezfleet\outgoing"
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return 0 }
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Force)) { Remove-Item -LiteralPath $f.FullName -Force; $n++ }
    return $n
}

function ConvertTo-HordeWezfleetMessengerCommandLine {
    # Separate argument elements as one Windows command line, each quoted the way CommandLineToArgvW reads
    # it back: an element with a space, a tab, a quote or nothing in it is quoted, a quote inside is
    # escaped, and backslashes before a quote are doubled. The one place arguments become a string.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Argv)
    $parts = New-Object System.Collections.ArrayList
    foreach ($a in $Argv) {
        if ($a -ne "" -and $a -notmatch '[\s"]') { [void]$parts.Add($a); continue }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        $slashes = 0
        foreach ($ch in $a.ToCharArray()) {
            if ($ch -eq '\') { $slashes++; continue }
            if ($ch -eq '"') { [void]$sb.Append('\' * ($slashes * 2 + 1)); [void]$sb.Append('"'); $slashes = 0; continue }
            if ($slashes -gt 0) { [void]$sb.Append('\' * $slashes); $slashes = 0 }
            [void]$sb.Append($ch)
        }
        if ($slashes -gt 0) { [void]$sb.Append('\' * ($slashes * 2)) }
        [void]$sb.Append('"')
        [void]$parts.Add($sb.ToString())
    }
    return ($parts -join " ")
}

function Stop-HordeWezfleetMessengerProcess {
    # Stop the process this call started, by its handle; say whether it stopped.
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    try { if (-not $Process.HasExited) { $Process.Kill() } } catch { }
    $null = $Process.WaitForExit(5000)
    if ($Process.HasExited) { return "the process it started was stopped" }
    return "the process it started did not stop within 5 s"
}

function Start-HordeWezfleetMessengerProcess {
    # THE ONE START SITE: the fixed PowerShell on the configured fleet's wezfleet.ps1, which it finds
    # itself (review of #106, G2: no caller can hand it another script), with -Argv after it. Returns
    # { ok; exit; stdout; stderr; reason }. Never throws for the child.
    param([Parameter(Mandatory = $true)][string[]]$Argv)
    $where = Get-HordeWezfleetMessengerScriptPath
    if (-not $where.ok) { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = $where.reason } }
    $all = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $where.path) + @($Argv)
    $psi = [System.Diagnostics.ProcessStartInfo]::new([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"), (ConvertTo-HordeWezfleetMessengerCommandLine -Argv $all))
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Standard input is held open and never written: a command that waits for input waits until the
    # deadline and is stopped, instead of reading this process's console.
    $psi.RedirectStandardInput = $true
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = ("the fleet's command could not be started: " + $_.Exception.Message) } }
    $timeout = $script:HordeWezfleetMessengerTimeoutSeconds
    $deadline = (Get-Date).AddSeconds($timeout)
    $err = $p.StandardError.ReadToEndAsync()
    $stream = $p.StandardOutput.BaseStream
    $buf = New-Object byte[] 4096
    $got = New-Object System.IO.MemoryStream
    while ($true) {
        $left = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
        $read = $stream.ReadAsync($buf, 0, $buf.Length)
        if (-not $read.Wait($left)) { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = ("the fleet's command did not answer within " + $timeout + " s; " + (Stop-HordeWezfleetMessengerProcess -Process $p)) } }
        $n = $read.Result
        if ($n -eq 0) { break }
        $got.Write($buf, 0, $n)
        if ($got.Length -gt $script:HordeWezfleetMessengerMaxBytes) { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = ("the fleet's command printed more than " + $script:HordeWezfleetMessengerMaxBytes + " bytes; " + (Stop-HordeWezfleetMessengerProcess -Process $p)) } }
    }
    $left = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
    if (-not $p.WaitForExit($left)) { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = ("the fleet's command did not exit within " + $timeout + " s; " + (Stop-HordeWezfleetMessengerProcess -Process $p)) } }
    $errText = ""
    if ($err.Wait(1000)) { $errText = "$($err.Result)" }
    return [pscustomobject]@{ ok = $true; exit = $p.ExitCode; stdout = [System.Text.Encoding]::UTF8.GetString($got.ToArray()); stderr = $errText; reason = "" }
}

function ConvertTo-HordeWezfleetMessengerLine {
    # One line of another program's text, fit for a reason: its first line, every character outside
    # printable ASCII made '?', at most -Max characters.
    param([string]$Text, [int]$Max = 200)
    $first = @("$Text" -split "`r?`n" | Where-Object { $_.Trim() -ne "" }) | Select-Object -First 1
    $clean = ("$first" -replace '[^\x20-\x7E]', '?').Trim()
    if ($clean.Length -gt $Max) { $clean = $clean.Substring(0, $Max) }
    return $clean
}

function New-HordeWezfleetMessengerHeld {
    # Held here, before any process starts: what wezfleet could never accept, said with its code.
    param([Parameter(Mandatory = $true)][string]$MessageId, [Parameter(Mandatory = $true)][string]$Reason)
    $now = [datetime]::UtcNow
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = $MessageId; stage = "held"; at = $now; reason = $Reason }) -ObservedAt $now)
}

function Read-HordeWezfleetMessengerAnswer {
    # The child's answer to one command, read against the table: a core/tristate answer whose known value
    # is the port's { messageId; stage; at; reason }. -Command is post or status; -To is the session a post
    # was asked to post to.
    param([Parameter(Mandatory = $true)]$Run, [Parameter(Mandatory = $true)][string]$Command, [Parameter(Mandatory = $true)][string]$MessageId, [string]$To = "")
    if (-not $Run.ok) { return (New-HordeUnknown -Reason $Run.reason) }
    $what = "wezfleet mail " + $Command + " exit " + $Run.exit
    $lines = @("$($Run.stdout)" -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
    if ($lines.Count -ne 1) {
        $detail = ConvertTo-HordeWezfleetMessengerLine ("$($Run.stdout)" + "`n" + "$($Run.stderr)")
        return (New-HordeUnknown -Reason ($what + " printed " + $lines.Count + " lines, not one line of JSON" + $(if ($detail) { ": " + $detail } else { "" })))
    }
    $j = $null
    try { $j = $lines[0] | ConvertFrom-Json } catch { $j = $null }
    if ($null -eq $j -or $j -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ($what + " printed something that is not JSON: " + (ConvertTo-HordeWezfleetMessengerLine $lines[0]))) }
    $need = @("id", "to", "stage", "reason")
    if ($Command -ceq "post") { $need += "woken" }
    # detail is read when it is there, and never required: its absence costs nothing.
    $may = @($need) + @("detail")
    $names = @($j.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($k in $need) { if ($names -cnotcontains $k) { return (New-HordeUnknown -Reason ($what + " answered without '" + $k + "': not the shape this messenger reads (wezfleet #65)")) } }
    foreach ($k in $names) { if ($may -cnotcontains $k) { return (New-HordeUnknown -Reason ($what + " answered with '" + $k + "': not the shape this messenger reads (wezfleet #65)")) } }
    if ($Command -ceq "post" -and $j.woken -isnot [bool]) { return (New-HordeUnknown -Reason ($what + " answered woken that is not true or false")) }
    foreach ($k in @("id", "to", "stage", "reason")) { if ($j.$k -isnot [string]) { return (New-HordeUnknown -Reason ($what + " answered " + $k + " that is not text")) } }
    # BOUND TO ITS MESSAGE (review of #102, finding 3): an answer about another id is never this one's.
    $asked = $MessageId.Replace("-", "")
    if ($j.id -cne $asked) { return (New-HordeUnknown -Reason ($what + " answered about " + (ConvertTo-HordeWezfleetMessengerLine $j.id) + ", not " + $asked)) }
    # A REASON IS A CODE OR NOTHING. A sentence there is the first shape of #65 (wezfleet's main), whose
    # exit 0 does not mean what this table takes it to mean: unknown, whatever the stage says.
    if ($j.reason -cne "" -and $j.reason -cnotmatch $script:HordeWezfleetMessengerCodePattern) { return (New-HordeUnknown -Reason ($what + " answered a reason that is not a code, so this is a wezfleet from before the reason codes this messenger reads: " + (ConvertTo-HordeWezfleetMessengerLine $j.reason))) }
    # EXIT 1 IS THE FLEET SAYING IT COULD NOT, not a code outside its table: said so, with the stage it
    # gave, its code and its detail. Unknown and never held, because the record may already be on disk
    # when the fleet fails.
    if ([int]$Run.exit -eq 1) {
        $failDetail = ""
        $failProp = $j.PSObject.Properties["detail"]
        $failCap = $script:HordeWezfleetMessengerDetailChars
        if ($null -ne $failProp -and $failProp.Value -is [string]) { $failDetail = ConvertTo-HordeWezfleetMessengerLine $failProp.Value -Max $failCap }
        return (New-HordeUnknown -Reason ($what + ": the fleet could not do it (stage '" + (ConvertTo-HordeWezfleetMessengerLine $j.stage) + "'): " + (ConvertTo-HordeWezfleetMessengerLine $j.reason) + $(if ($failDetail -ne "") { ": " + $failDetail } else { "" })))
    }
    $byExit = $script:HordeWezfleetMessengerExits[$Command]
    if (-not $byExit.ContainsKey([int]$Run.exit)) { return (New-HordeUnknown -Reason ($what + ", which is not an exit code this messenger reads as a stage: " + (ConvertTo-HordeWezfleetMessengerLine $j.reason) + " " + (ConvertTo-HordeWezfleetMessengerLine "$($j.PSObject.Properties['detail'].Value)"))) }
    if (@($byExit[[int]$Run.exit]) -cnotcontains $j.stage) { return (New-HordeUnknown -Reason ($what + " with the stage '" + (ConvertTo-HordeWezfleetMessengerLine $j.stage) + "', which does not go with that exit code")) }
    # THE TARGET. A post's is the session it was asked for, but a repost names where the record is now.
    $code = ConvertTo-HordeWezfleetMessengerLine $j.reason
    $where = ""
    if ($Command -ceq "post") {
        if ($j.to -cne $To) {
            if ($code -cne "already-posted" -or $j.to -cnotmatch $script:HordeWezfleetMessengerSessionPattern) {
                return (New-HordeUnknown -Reason ($what + " answered for the session " + (ConvertTo-HordeWezfleetMessengerLine $j.to) + ", not " + $To))
            }
            $where = "followed to " + $j.to
        }
    } elseif ($j.to -cne "") {
        if ($j.to -cnotmatch $script:HordeWezfleetMessengerSessionPattern) { return (New-HordeUnknown -Reason ($what + " answered a target that is not a session id: " + (ConvertTo-HordeWezfleetMessengerLine $j.to))) }
        $where = "at " + $j.to
    }
    $now = [datetime]::UtcNow
    if ($Command -ceq "status" -and $j.stage -ceq "absent") { return (New-HordeAbsent -Note ("wezfleet has no record of " + $asked) -ObservedAt $now) }
    # THE DETAIL, NEVER FATAL: text is cut to one capped line of printable ASCII; anything else is dropped.
    $detail = ""
    $dp = $j.PSObject.Properties["detail"]
    if ($null -ne $dp -and $dp.Value -is [string]) { $detail = ConvertTo-HordeWezfleetMessengerLine $dp.Value -Max $script:HordeWezfleetMessengerDetailChars }
    $stage = $script:HordeWezfleetMessengerStages[$j.stage]
    if ([int]$Run.exit -eq 4) { $stage = "held"; if ($code -eq "") { $code = "stale-session" } }
    # expired and held say why: wezfleet's code, or what its stage means when it gave none.
    if ($code -eq "" -and $j.stage -ceq "unconfirmed") { $code = "unconfirmed" ; if ($detail -eq "") { $detail = "no receiving hook confirmed it in time" } }
    if ($code -eq "" -and $j.stage -ceq "refused") { $code = "refused"; if ($detail -eq "") { $detail = "wezfleet refused the post" } }
    $reason = $code
    if ($detail -ne "") { $reason = $(if ($reason -ne "") { $reason + ": " + $detail } else { $detail }) }
    if ($where -ne "") { $reason = $(if ($reason -ne "") { $reason + "; " + $where } else { $where }) }
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = $MessageId; stage = $stage; at = $now; reason = $reason }) -ObservedAt $now)
}

function Send-HordeWezfleetMessengerPost {
    # Post one message: what wezfleet cannot name is held first, then the body into a fresh file in
    # Horde's own folder, the fleet's mail post on it, and the file deleted.
    param([Parameter(Mandatory = $true)]$Message)
    $id = [string]$Message.messageId
    $to = [string]$Message.sessionId
    if ($to -cnotmatch $script:HordeWezfleetMessengerSessionPattern) {
        return (New-HordeWezfleetMessengerHeld -MessageId $id -Reason ("bad-to: the target '" + (ConvertTo-HordeWezfleetMessengerLine $to) + "' is not a lower-case session UUID, the only target wezfleet can deliver to; nothing was started"))
    }
    $fromSid = [string]$Message.from.sessionId
    $fl = $Message.from.PSObject.Properties["label"]
    $label = $(if ($null -ne $fl -and $null -ne $fl.Value) { [string]$fl.Value } else { "" })
    if ($label -ne "" -and $label -cnotmatch $script:HordeWezfleetMessengerLabelPattern) {
        return (New-HordeWezfleetMessengerHeld -MessageId $id -Reason ("bad-from: the sender label '" + (ConvertTo-HordeWezfleetMessengerLine $label) + "' is not a hub label; nothing was started"))
    }
    $sidOk = ($fromSid -cmatch $script:HordeWezfleetMessengerSessionPattern)
    if (-not $sidOk -and $label -eq "") {
        return (New-HordeWezfleetMessengerHeld -MessageId $id -Reason "bad-from: the sender has neither a session UUID nor a hub label, so wezfleet could not say who wrote it; nothing was started")
    }
    $where = Get-HordeWezfleetMessengerScriptPath
    if (-not $where.ok) { return (New-HordeUnknown -Reason $where.reason) }
    $file = Join-Path (Get-HordeWezfleetMessengerOutgoing) ([guid]::NewGuid().ToString("N") + ".txt")
    try {
        [System.IO.File]::WriteAllText($file, [string]$Message.body, (New-Object System.Text.UTF8Encoding($false)))
        $argv = @("mail", "post", "-To", $to, "-Id", $id.Replace("-", ""), "-MessageFile", $file)
        if ($label -ne "") { $argv += @("-FromLabel", $label) }
        # A sender whose session id wezfleet cannot hold is named by its label alone.
        if ($sidOk) { $argv += @("-FromSessionId", $fromSid) }
        $argv += @("-Json")
        $run = Start-HordeWezfleetMessengerProcess -Argv $argv
        return (Read-HordeWezfleetMessengerAnswer -Run $run -Command "post" -MessageId $id -To $to)
    } finally {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    }
}

function Get-HordeWezfleetMessengerStatus {
    # Where one message is, by the fleet's mail status.
    param([Parameter(Mandatory = $true)][string]$MessageId)
    $run = Start-HordeWezfleetMessengerProcess -Argv @("mail", "status", "-Id", $MessageId.Replace("-", ""), "-Json")
    return (Read-HordeWezfleetMessengerAnswer -Run $run -Command "status" -MessageId $MessageId)
}

$null = Register-HordeMessenger -Folder $script:HordeWezfleetMessengerFolder `
    -Post { param($Message) Send-HordeWezfleetMessengerPost -Message $Message } `
    -Status { param([string]$MessageId) Get-HordeWezfleetMessengerStatus -MessageId $MessageId }
