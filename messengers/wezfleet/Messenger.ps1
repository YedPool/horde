# messengers/wezfleet - hands a message to a session through the fleet's own mail.
#
# WHY THE FLEET'S MAIL (remote plan R21). wezfleet already delivers between sessions on one machine the
# way Horde must: the body is written to the target's inbox and never typed; the receiving session's own
# Stop hook hands it over at a turn boundary and acks it only once its id is in that session's
# transcript (TAKEN); an idle target gets one short wake notice carrying only the id. Its PR #65 added the
# two commands this messenger runs, so that a program that is not a session can use that path:
#   mail post -To <session uuid> -Id <32 hex> -MessageFile <path> [-FromLabel l] [-FromSessionId uuid]
#             [-FromVerified founder:passkey:<32 hex>] -Json
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
# A VERIFIED SENDER (the founder's first live use, 2026-10-11: his phone's lines reached his Thrall as
# "the sender calls itself: F (not verified)", though the relay had verified each one). A message's
# from.verified (messengers/Port.ps1, A VERIFIED SENDER: kind founder, by passkey, a 32-hex key id) is
# passed as -FromVerified founder:passkey:<key id>, which wezfleet's feature/from-verified declares and
# shows as "MESSAGE FROM THE FOUNDER, VERIFIED BY HORDE'S RELAY". It is this node's word that it checked
# the signature, nothing more: any program running as this user can call wezfleet with the same claim.
# Held here, before any process starts, unless it holds the port's rule (a direct call skips the port).
# ONLY TO A WEZFLEET THAT DECLARES IT. wezfleet main at 1122461 does not, and its wezfleet.ps1 is an
# advanced script, so PowerShell refuses the undeclared argument before the script runs: nothing on
# stdout, exit 1 (measured 2026-10-11 against a clone of main) - every founder line would be unknown and
# the chat channel would hold it. So each post that carries a verified sender first asks whether the
# script it is about to run declares -FromVerified in its own param block, read by PowerShell's own
# parser (Test-HordeWezfleetMessengerTakesVerified), and passes it only then; otherwise the line is posted
# as before, by label, unlabelled, and the answer's reason says so. WHY THE PARSER, and not the help or a
# version marker: the refusal this avoids IS PowerShell binding against that param block, so the probe
# asks exactly the question that fails; it runs nothing (no second process per post, no deadline, no
# output to read); it is not fooled by the word in a comment, a string or a function inside the script,
# as a text search would be; and wezfleet's own test-cli-surface.ps1 reads its param block the same way.
# The help is prose generated from a table and may be reworded; wezfleet has no version marker, and one
# would be a second thing to keep in step with the param block it stands for. Read on every such post,
# like the folder: installing a newer wezfleet takes effect without a restart. A wezfleet replaced
# between the probe and the start is a window of milliseconds: old to new posts unlabelled once, new to
# old is unknown once and retried.
#
# WOKEN, OR ONLY QUEUED (the founder's bug of 2026-10-12, messengers/Port.ps1, THE WAKE WORD). wezfleet's
# post knocks once for each new message - the same one-line notice, through the same guarded send, as its
# tell - and answers woken true or false with a code: woken; send-refused (the knock was refused: the
# target's box holds somebody's unsent text, another sender has the pane); pane-unverified or
# no-registry-record (no pane of the target's was found). This messenger passes that on as the answer's
# woken, and the reason keeps wezfleet's code and words. No argument asks for the wake, so there is
# nothing to probe for: every wezfleet with these commands knocks. WHAT WAS WRONG was on wezfleet's side,
# measured that day on the founder's machine from its own records: a post made by a process outside any
# pane - the relay runner, started hidden - could not reach the terminal at all (pane-unverified, "the terminal
# did not answer"), so his phone's lines were queued in seconds and never woke the Thrall, while the
# decisions doorbell, started from a pane, woke it or was refused by an occupied box as a tell is. wezfleet's
# fix/mail-post-wake mends that; against a wezfleet without it this messenger still posts, and says
# queued, NOT woken, which is the truth.
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
# WHERE THE FLEET IS, in this order, and never a guess:
#   1. Set-HordeWezfleetMessengerRoot, when it named a folder: for tests, which point the messenger at a
#      fake checkout in the process they run.
#   2. The setting root of this messenger's own settings (core/ModuleSettings.ps1, module
#      messenger-wezfleet: <HORDE_HOME>\settings\messenger-wezfleet.json), when it names a folder. A file
#      there that is REFUSED makes every post and status unknown with its findings: the command on PATH is
#      never used in its place, because the person's file says something else.
#   3. With no root set, the checkout the wezfleet command on PATH runs - the first Get-Command finds, as a
#      shell typing wezfleet would. A .ps1 there is the checkout's own wezfleet.ps1, so its folder is the
#      checkout. A .cmd or .bat shim is READ, NEVER RUN, for the one %~dp0<folder>wezfleet.ps1 it names, as
#      the shim wezfleet installs does (bin\wezfleet.cmd running %~dp0wezfleet\wezfleet.ps1, read
#      2026-10-09); a shim naming none, or two, and anything else on PATH, is unknown with the reason. The
#      folder is joined as written, never resolved, so a .. in it is refused below like a configured one.
# THE DECISION IS MADE ON EVERY CALL, post and status alike, not once when the file is loaded: a node runs
# for days, and a person who installs wezfleet or writes the settings file must not have to restart it;
# the cost is one small file read and one PATH lookup per call, which start a process anyway. Loading
# this file declares the setting and reads nothing.
# Whatever chose it, the folder must be an absolute local folder with no ..,
# no reparse point on it or above it - a junction could be re-aimed after it was configured - and a
# wezfleet checkout with #65's mail commands: wezfleet.ps1, lib\Mail.ps1, lib\MailPost.ps1 and
# commands\mail.ps1 (review of #106, G1). Otherwise every call is unknown, saying how the folder was
# chosen, and nothing starts. A test that must never reach the fleet's real command pins its home with
# test\Pin.ps1 (test\lib\MessengerPins.ps1 runs it): the setting then names an empty folder. Every call
# has a deadline; past it the child and every process it started are stopped and the answer is unknown
# (review of #106, F7). The answer is read once the command has exited, even while a process it started
# still holds its output open (F6).
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced, after messengers/Port.ps1.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Home.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\PathText.ps1")

$script:HordeWezfleetMessengerFolder = $PSScriptRoot
# Set only by Set-HordeWezfleetMessengerRoot; "" means the setting, then the command on PATH, decide.
$script:HordeWezfleetMessengerRoot = ""
$script:HordeWezfleetMessengerSettings = New-HordeModuleSettings -Module "messenger-wezfleet" -Settings @(
    @{ name = "root"; kind = "folder"; default = ""; what = "The wezfleet checkout whose mail commands are run; empty means the one the wezfleet command on PATH runs." }
)
# The command looked up on PATH, and the most of a shim that is read: a real one is about 700 bytes.
$script:HordeWezfleetMessengerCommand = "wezfleet"
$script:HordeWezfleetMessengerShimMaxBytes = 65536
# What a shim names: %~dp0 (its own folder, with the trailing backslash), then folders each ending in a
# slash, then wezfleet.ps1 itself (so mywezfleet.ps1 is not read as a folder "my"). No quote, percent
# sign, colon or wildcard in a folder: a second variable or a drive is not followed.
$script:HordeWezfleetMessengerShimPattern = '%~dp0((?:[^"%:*?<>|\r\n\\/]+[\\/])*)wezfleet\.ps1'
$script:HordeWezfleetMessengerTimeoutSeconds = 30
$script:HordeWezfleetMessengerScript = "wezfleet.ps1"
# What makes a folder a wezfleet checkout with #65's commands, beside the script itself.
$script:HordeWezfleetMessengerMarkers = @("wezfleet.ps1", "lib\Mail.ps1", "lib\MailPost.ps1", "commands\mail.ps1")
# How long a read may wait once the command has exited before the output is taken as complete: what an
# exited command wrote is already in the pipe, so only someone else's handle makes a read wait.
$script:HordeWezfleetMessengerDrainMs = 500
# The most a command may print before it is stopped: one line of JSON is far below this.
$script:HordeWezfleetMessengerMaxBytes = 65536
# The most of wezfleet's detail kept in a reason; the port caps a reason at 1024 bytes.
$script:HordeWezfleetMessengerDetailChars = 600
# wezfleet's session id (its -To and -FromSessionId), and Horde's hub label (its -FromLabel).
$script:HordeWezfleetMessengerSessionPattern = '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'
$script:HordeWezfleetMessengerLabelPattern = '\A[A-Z]{1,2}([1-9][0-9]{0,3})?\z'
# The argument a wezfleet that shows a verified sender declares (A VERIFIED SENDER, in the header).
$script:HordeWezfleetMessengerVerifiedParameter = "FromVerified"
# A reason code: lower-case words of letters and digits, the first starting with a letter, joined by
# dashes (woken, already-posted, stale-session, invalid-utf8, ...). A sentence is not one. Digits are
# allowed because wezfleet main's closed list has invalid-utf8, which letters alone read as prose
# (measured 2026-10-09 against a clone of main at 1122461).
$script:HordeWezfleetMessengerCodePattern = '\A[a-z][a-z0-9]*(-[a-z0-9]+)*\z'
$script:HordeWezfleetMessengerStages = @{ "queued" = "accepted"; "handed-over" = "handed-over"; "taken" = "seen"; "unconfirmed" = "expired"; "refused" = "held" }
# Which stages each exit code may carry, per command. Anything else is unknown.
$script:HordeWezfleetMessengerExits = @{
    post = @{ 0 = @("queued", "handed-over", "taken", "unconfirmed"); 2 = @("refused"); 4 = @("refused", "queued") }
    status = @{ 0 = @("queued", "handed-over", "taken", "unconfirmed"); 3 = @("absent") }
}

function Set-HordeWezfleetMessengerRoot {
    # For tests: name the folder holding the fleet's wezfleet.ps1, over the setting and the command on
    # PATH, and the deadline of each call. "" unsets it, and the setting, then PATH, decide again.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path, [int]$TimeoutSeconds = 30)
    if ($TimeoutSeconds -lt 1) { throw ("TimeoutSeconds must be at least 1, not " + $TimeoutSeconds) }
    $script:HordeWezfleetMessengerRoot = $Path
    $script:HordeWezfleetMessengerTimeoutSeconds = $TimeoutSeconds
}

function New-HordeWezfleetMessengerChoice {
    # A choice of folder: { ok; root; how; reason }. how finishes "the folder was ...".
    param([string]$Root = "", [string]$How = "", [string]$Reason = "")
    return [pscustomobject]@{ ok = ($Reason -eq ""); root = $Root; how = $How; reason = $Reason }
}

function Find-HordeWezfleetMessengerOnPath {
    # The checkout the wezfleet command on PATH runs (header, WHERE THE FLEET IS, 3), as a choice. The shim
    # is read as text and never run. -SettingsPath is named in every reason, as the place to say otherwise.
    param([Parameter(Mandatory = $true)][string]$SettingsPath)
    $instead = "; name its checkout as root in " + $SettingsPath
    $cmd = $null
    try { $cmd = @(Get-Command -Name $script:HordeWezfleetMessengerCommand -CommandType Application, ExternalScript -ErrorAction SilentlyContinue) | Select-Object -First 1 } catch { $cmd = $null }
    if ($null -eq $cmd) { return (New-HordeWezfleetMessengerChoice -Reason ("no wezfleet command is on PATH and no root is set, so the fleet's command was not run" + $instead)) }
    $src = [string]$cmd.Path
    $from = "found from the wezfleet command on PATH, " + $src
    # Lower-cased by the 26 letters alone (core/PathText.ps1), never by the runtime's case table, which
    # differs between runtimes: an extension is compared here, and the comparison must not move with them.
    $ext = ConvertTo-HordeAsciiLower -Text ([System.IO.Path]::GetExtension($src))
    $dir = Split-Path -Parent $src
    if ($ext -ceq ".ps1") { return (New-HordeWezfleetMessengerChoice -Root $dir -How $from) }
    if ($ext -cne ".cmd" -and $ext -cne ".bat") {
        return (New-HordeWezfleetMessengerChoice -Reason ("the wezfleet command on PATH is '" + $src + "', neither a .ps1 nor a .cmd or .bat shim, so its checkout is not known" + $instead))
    }
    $text = ""
    try {
        $info = New-Object System.IO.FileInfo($src)
        if ($info.Length -gt $script:HordeWezfleetMessengerShimMaxBytes) { return (New-HordeWezfleetMessengerChoice -Reason ("the wezfleet command on PATH, the shim '" + $src + "', is larger than " + $script:HordeWezfleetMessengerShimMaxBytes + " bytes, so it was not read" + $instead)) }
        $text = [System.IO.File]::ReadAllText($src)
    } catch { return (New-HordeWezfleetMessengerChoice -Reason ("the wezfleet command on PATH, the shim '" + $src + "', could not be read: " + $_.Exception.Message + $instead)) }
    # ONE FOLDER, compared ignoring case as Windows compares paths: the same line twice is one folder.
    $named = @([regex]::Matches($text, $script:HordeWezfleetMessengerShimPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | ForEach-Object { ConvertTo-HordeAsciiLower -Text ($_.Groups[1].Value.Replace('/', '\')) } | Select-Object -Unique)
    if ($named.Count -ne 1) {
        return (New-HordeWezfleetMessengerChoice -Reason ("the wezfleet command on PATH is the shim '" + $src + "', which names " + $named.Count + " scripts as %~dp0<folder>wezfleet.ps1, not one, so its checkout is not known" + $instead))
    }
    # The folder as the shim wrote it (its own case), joined and NOT resolved: a .. stays, to be refused.
    $m = [regex]::Match($text, $script:HordeWezfleetMessengerShimPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $rel = $m.Groups[1].Value.Replace('/', '\').TrimEnd('\')
    $root = $(if ($rel -eq "") { $dir } else { $dir.TrimEnd('\') + '\' + $rel })
    return (New-HordeWezfleetMessengerChoice -Root $root -How $from)
}

function Get-HordeWezfleetMessengerChoice {
    # Which folder, and how it was chosen (header, WHERE THE FLEET IS), as a choice. Read on every call.
    if ("$script:HordeWezfleetMessengerRoot" -ne "") { return (New-HordeWezfleetMessengerChoice -Root $script:HordeWezfleetMessengerRoot -How "set by Set-HordeWezfleetMessengerRoot") }
    $s = $null
    try { $s = Get-HordeModuleSettings -Declaration $script:HordeWezfleetMessengerSettings }
    catch { return (New-HordeWezfleetMessengerChoice -Reason ("the wezfleet messenger's settings could not be read, so the fleet's command was not run: " + $_.Exception.Message)) }
    # A REFUSED FILE IS NO FOLDER AT ALL: anything but the two states that carry values is the refusal,
    # and the command on PATH is never asked in its place.
    if ($s.state -cne "defaults" -and $s.state -cne "read") { return (New-HordeWezfleetMessengerChoice -Reason ("the fleet's command was not run, because the wezfleet messenger's settings are refused: " + (@($s.findings) -join "; "))) }
    if ("$($s.values.root)" -ne "") { return (New-HordeWezfleetMessengerChoice -Root $s.values.root -How ("set as root in " + $s.path)) }
    return (Find-HordeWezfleetMessengerOnPath -SettingsPath $s.path)
}

function Get-HordeWezfleetMessengerScriptPath {
    # The fleet's script, as { ok; path; reason }: only in an absolute local folder with no .., no reparse
    # point on its path, holding every marker of a wezfleet checkout with #65's commands - whichever way
    # the folder was chosen, and a refusal says which.
    $choice = Get-HordeWezfleetMessengerChoice
    if (-not $choice.ok) { return [pscustomobject]@{ ok = $false; path = ""; reason = $choice.reason } }
    $why = Test-HordeWezfleetMessengerCheckout -Folder $choice.root
    if ($why -ne "") { return [pscustomobject]@{ ok = $false; path = ""; reason = ($why + " (the folder was " + $choice.how + ")") } }
    return [pscustomobject]@{ ok = $true; path = (Join-Path $choice.root $script:HordeWezfleetMessengerScript); reason = "" }
}

function Test-HordeWezfleetMessengerCheckout {
    # Why -Folder is not a folder to run the fleet's script from, or "" when it is.
    param([Parameter(Mandatory = $true)][string]$Folder)
    $dir = $Folder
    if (-not [System.IO.Path]::IsPathRooted($dir) -or $dir -notmatch '\A[A-Za-z]:\\' -or @($dir -split '[\\/]') -contains "..") {
        return ("the wezfleet folder '" + $dir + "' is not an absolute local folder without .., so it was not used")
    }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return ("the wezfleet folder '" + $dir + "' does not exist") }
    # NO REPARSE POINT on the folder or any folder above it: each is read as it is, not followed.
    $d = New-Object System.IO.DirectoryInfo($dir)
    while ($null -ne $d) {
        if (($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            return ("the wezfleet folder '" + $dir + "' has a reparse point on its path ('" + $d.FullName + "'), so it was not used")
        }
        $d = $d.Parent
    }
    foreach ($marker in $script:HordeWezfleetMessengerMarkers) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir $marker) -PathType Leaf)) {
            return ("'" + $dir + "' is not a wezfleet checkout with the mail commands: no " + $marker + " in it")
        }
    }
    return ""
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

function Test-HordeWezfleetMessengerTakesVerified {
    # Why the fleet's script at -Path cannot be handed -FromVerified, or "" when it can: its own param
    # block declares it, read by PowerShell's parser and never run (the header, A VERIFIED SENDER).
    # Compared ignoring case, as PowerShell binds a parameter name.
    param([Parameter(Mandatory = $true)][string]$Path)
    $name = $script:HordeWezfleetMessengerVerifiedParameter
    $tokens = $null
    $errors = $null
    $ast = $null
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return ("its wezfleet.ps1 is not there, so -" + $name + " is not passed") }
    try { $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) }
    catch { return ("its wezfleet.ps1 could not be read for -" + $name + ": " + (ConvertTo-HordeWezfleetMessengerLine $_.Exception.Message)) }
    if (@($errors).Count -gt 0) { return ("its wezfleet.ps1 does not parse, so -" + $name + " is not passed") }
    $declared = @()
    if ($null -ne $ast.ParamBlock) { $declared = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }
    if ($declared -contains $name) { return "" }
    return ("the wezfleet it runs does not declare -" + $name + " (wezfleet main before feature/from-verified)")
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

function Get-HordeWezfleetMessengerDescendants {
    # The processes the started one started, and theirs, from one snapshot of the process table, as
    # { id; start } with start in UTC. A process counts only if it was created at or after its parent
    # started: a parent pid alone can name a process Windows has since given that pid. Empty when the
    # table cannot be read; the caller still stops the child it holds.
    param([Parameter(Mandatory = $true)][int]$RootId, [Parameter(Mandatory = $true)][datetime]$RootStart)
    $all = @()
    try { $all = @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, ParentProcessId, CreationDate -ErrorAction Stop) } catch { return @() }
    $byParent = @{}
    foreach ($q in $all) {
        $k = [int]$q.ParentProcessId
        if (-not $byParent.ContainsKey($k)) { $byParent[$k] = New-Object System.Collections.ArrayList }
        [void]$byParent[$k].Add($q)
    }
    $out = New-Object System.Collections.ArrayList
    $seen = @{ $RootId = $true }
    $todo = New-Object System.Collections.Queue
    $todo.Enqueue([pscustomobject]@{ id = $RootId; start = $RootStart.ToUniversalTime() })
    while ($todo.Count -gt 0) {
        $parent = $todo.Dequeue()
        if (-not $byParent.ContainsKey($parent.id)) { continue }
        foreach ($c in $byParent[$parent.id]) {
            $cid = [int]$c.ProcessId
            if ($seen.ContainsKey($cid) -or $null -eq $c.CreationDate) { continue }
            $cstart = ([datetime]$c.CreationDate).ToUniversalTime()
            if ($cstart -lt $parent.start) { continue }
            $seen[$cid] = $true
            $d = [pscustomobject]@{ id = $cid; start = $cstart }
            [void]$out.Add($d)
            $todo.Enqueue($d)
        }
    }
    return @($out)
}

function Stop-HordeWezfleetMessengerProcess {
    # Stop the process this call started, by its handle, AND EVERY PROCESS IT STARTED (review of #106,
    # F7): Process.Kill stops the child alone, and a grandchild - the terminal client wezfleet starts
    # without redirecting it - outlived the deadline (measured 2026-10-09: a fake that started one and
    # hung left it running after "the process it started was stopped"). The tree is read before the child
    # is stopped; each descendant is stopped only if the process now holding its pid started when the
    # snapshot said, so a reused pid is never stopped. Says what it stopped.
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    $tree = @()
    try { $tree = @(Get-HordeWezfleetMessengerDescendants -RootId $Process.Id -RootStart $Process.StartTime) } catch { $tree = @() }
    try { if (-not $Process.HasExited) { $Process.Kill() } } catch { }
    $stopped = 0
    foreach ($d in $tree) {
        try {
            $q = Get-Process -Id $d.id -ErrorAction Stop
            if ([Math]::Abs(($q.StartTime.ToUniversalTime() - $d.start).TotalSeconds) -lt 1) { $q.Kill(); $stopped++ }
        } catch { }
    }
    $null = $Process.WaitForExit(5000)
    $also = $(if ($stopped -gt 0) { ", with " + $stopped + " process(es) it had started" } else { "" })
    if ($Process.HasExited) { return ("the process it started was stopped" + $also) }
    return ("the process it started did not stop within 5 s" + $also)
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
    # READ UNTIL THE OUTPUT CLOSES OR THE COMMAND HAS EXITED, whichever is first (review of #106, F6). A
    # grandchild that inherited the command's output - the terminal client wezfleet starts without
    # redirecting it - keeps the pipe open after the command exits, and waiting for the pipe alone waited
    # out the whole deadline with the answer already read (measured 2026-10-09: 25 s, "did not answer",
    # for a command that answered and exited at once). Once the command has exited, what it wrote is in
    # the pipe and a read returns it at once; a read still waiting a moment later is waiting on someone
    # else's handle, and the reading stops there.
    $exitedAt = $null
    $drained = $false
    while (-not $drained) {
        $read = $stream.ReadAsync($buf, 0, $buf.Length)
        while (-not $read.Wait(100)) {
            if ((Get-Date) -ge $deadline) { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = ("the fleet's command did not answer within " + $timeout + " s; " + (Stop-HordeWezfleetMessengerProcess -Process $p)) } }
            if ($p.HasExited) {
                if ($null -eq $exitedAt) { $exitedAt = Get-Date }
                elseif (((Get-Date) - $exitedAt).TotalMilliseconds -ge $script:HordeWezfleetMessengerDrainMs) { $drained = $true; break }
            }
        }
        if ($drained) { break }
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
    $value = [ordered]@{ messageId = $MessageId; stage = $stage; at = $now; reason = $reason }
    # THE WAKE WORD (messengers/Port.ps1): a fresh post's, from wezfleet's own woken and its code together -
    # true only when both say so, so a wake the code denies is never claimed. Not for a repost (wezfleet
    # knocks nobody again, and its false there is not "the target sleeps"), and not for exit 4, held.
    if ($Command -ceq "post" -and [int]$Run.exit -eq 0 -and $code -cne "already-posted") { $value["woken"] = ($j.woken -eq $true -and $code -ceq "woken") }
    return (New-HordeKnown -Value ([pscustomobject]$value) -ObservedAt $now)
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
    # from read by member, as the port reads it: an object or a dictionary (messengers/Port.ps1).
    $from = Get-HordeMessengerMember $Message "from"
    $fromSid = [string](Get-HordeMessengerMember $from.value "sessionId").value
    $fl = Get-HordeMessengerMember $from.value "label"
    $label = $(if ($fl.has -and $null -ne $fl.value) { [string]$fl.value } else { "" })
    if ($label -ne "" -and $label -cnotmatch $script:HordeWezfleetMessengerLabelPattern) {
        return (New-HordeWezfleetMessengerHeld -MessageId $id -Reason ("bad-from: the sender label '" + (ConvertTo-HordeWezfleetMessengerLine $label) + "' is not a hub label; nothing was started"))
    }
    $sidOk = ($fromSid -cmatch $script:HordeWezfleetMessengerSessionPattern)
    if (-not $sidOk -and $label -eq "") {
        return (New-HordeWezfleetMessengerHeld -MessageId $id -Reason "bad-from: the sender has neither a session UUID nor a hub label, so wezfleet could not say who wrote it; nothing was started")
    }
    # A VERIFIED SENDER (the header): held unless it holds the port's rule, and it needs a label, as
    # wezfleet's -FromVerified does.
    $verified = ""
    $fv = Get-HordeMessengerMember $from.value "verified"
    if ($fv.has) {
        $vf = @(Test-HordeMessengerVerified $fv.value)
        if ($vf.Count -gt 0) { return (New-HordeWezfleetMessengerHeld -MessageId $id -Reason ("bad-from: " + (ConvertTo-HordeWezfleetMessengerLine ($vf -join "; ")) + "; nothing was started")) }
        if ($label -eq "") { return (New-HordeWezfleetMessengerHeld -MessageId $id -Reason "bad-from: a verified sender needs a hub label for wezfleet to show beside it; nothing was started") }
        $verified = (Get-HordeMessengerMember $fv.value "kind").value + ":" + (Get-HordeMessengerMember $fv.value "by").value + ":" + (Get-HordeMessengerMember $fv.value "keyId").value
    }
    $where = Get-HordeWezfleetMessengerScriptPath
    if (-not $where.ok) { return (New-HordeUnknown -Reason $where.reason) }
    # ONLY TO A WEZFLEET THAT DECLARES IT; otherwise the line goes unlabelled, and the answer says why.
    $unlabelled = ""
    if ($verified -ne "") {
        $unlabelled = Test-HordeWezfleetMessengerTakesVerified -Path $where.path
        if ($unlabelled -ne "") { $verified = "" }
    }
    $file = Join-Path (Get-HordeWezfleetMessengerOutgoing) ([guid]::NewGuid().ToString("N") + ".txt")
    try {
        [System.IO.File]::WriteAllText($file, [string]$Message.body, (New-Object System.Text.UTF8Encoding($false)))
        $argv = @("mail", "post", "-To", $to, "-Id", $id.Replace("-", ""), "-MessageFile", $file)
        if ($label -ne "") { $argv += @("-FromLabel", $label) }
        # A sender whose session id wezfleet cannot hold is named by its label alone.
        if ($sidOk) { $argv += @("-FromSessionId", $fromSid) }
        if ($verified -ne "") { $argv += @("-FromVerified", $verified) }
        $argv += @("-Json")
        $run = Start-HordeWezfleetMessengerProcess -Argv $argv
        $ans = Read-HordeWezfleetMessengerAnswer -Run $run -Command "post" -MessageId $id -To $to
        if ($unlabelled -ne "" -and $ans.state -ceq "known") {
            $note = "posted without the verified label: " + $unlabelled
            $ans.value.reason = $(if ("$($ans.value.reason)" -ne "") { $ans.value.reason + "; " + $note } else { $note })
        }
        return $ans
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
