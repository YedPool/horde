# FakeWezfleet.ps1 - a stand-in for the fleet's command, for the wezfleet messenger's tests only.
#
# WHY A FAKE (remote plan R21, slice 3b, merge condition 1). The messenger starts the fleet's command as a
# child process; the tests must see what that child was really handed and what it really did, without a
# real mail root, a real pane or a real session. The fixture copies this file into a temp folder as
# wezfleet.ps1, and the messenger is pointed at that folder, so the program it starts is this script.
#
# WHAT IT KEEPS, all under its own folder and nowhere else:
#   argv.log    one JSON line per run: the arguments it received, as separate elements, and the path of
#               the program that ran it (so a test can see the messenger started the fixed PowerShell)
#   store\<id>.json   one record per message id: { id; to; stage; reason; body; fromLabel; fromSessionId }
#   typed.log   one JSON line per text "typed" into a session: { id; text } - the fake target. Only a wake
#               notice is ever written here, built the way wezfleet's Get-WfWakeNotice builds it
#   mode.json   optional: how to misbehave, per command: { post|status: { exit; stdout; stderr; stage;
#               reason; hangSeconds; noWake; throw } }
#
# THE CONTRACT IT PLAYS is wezfleet's `mail post` and `mail status` AS MERGED (wezfleet main 68ff08e, its
# PR #65 with the changes its review made), not the head this messenger was first written against:
# `mail post -To -Id -MessageFile [-FromLabel] [-FromSessionId] -Json` and `mail status -Id [-To] -Json`,
# each printing one line of ASCII JSON. post exits 0 when the mail is on disk (new or existing), 2 when
# refused, 1 when it could not do it; status exits 0 when found, 2 for a malformed id, 3 when absent,
# 1 on an error. A repost of one id writes nothing and wakes nothing. The rules below are the merged
# command's, in its order and with its words, each measured against a clone of 68ff08e in an isolated
# mail root on 2026-10-06 (review of this messenger's pull request):
#   - a target that is not a mailbox name is refused: outside [A-Za-z0-9._-]{1,128}, ending in a dot
#     (which covers a name made only of dots), or a reserved device name. A session id with a colon is
#     one Horde allows and the fleet refuses;
#   - a sender's label over 64 characters, or holding a control, format or line-separator character,
#     is refused, never cleaned;
#   - a message that is only white space is refused;
#   - whatever throws is still one line: exit 1 with the stage "error" (mode: throw);
#   - a parameter the host itself rejects never reaches the script: nothing on stdout, the host's
#     words on stderr, exit 1 (mode: stdout "" with stderr and exit 1).
# NOT PLAYED: the wake needing a registry record and a verified pane. The fake target is an idle session
# that has both, so every new post is "typed" one notice unless the mode says noWake.
param()
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$argvList = @($args | ForEach-Object { "$_" })
$selfPath = (Get-Process -Id $PID).Path
[System.IO.File]::AppendAllText((Join-Path $root "argv.log"), ((@{ argv = $argvList; program = $selfPath; pid = $PID } | ConvertTo-Json -Compress -Depth 4) + "`n"), [System.Text.Encoding]::ASCII)

function Get-FakeArg {
    param([string]$Name)
    for ($i = 0; $i -lt $argvList.Count - 1; $i++) { if ($argvList[$i] -ceq $Name) { return $argvList[$i + 1] } }
    return ""
}
function Write-FakeJson {
    param($Object)
    $json = ($Object | ConvertTo-Json -Compress -Depth 4)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $json.ToCharArray()) { if ([int]$ch -gt 0x7E) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) } else { [void]$sb.Append($ch) } }
    [Console]::Out.WriteLine($sb.ToString())
}

$mode = $null
$modePath = Join-Path $root "mode.json"
if (Test-Path -LiteralPath $modePath) { $mode = [System.IO.File]::ReadAllText($modePath) | ConvertFrom-Json }

if ($argvList.Count -lt 2 -or $argvList[0] -cne "mail") { [Console]::Out.WriteLine("fake wezfleet: only mail is played"); exit 1 }
$act = $argvList[1]
$m = $null
if ($null -ne $mode -and $null -ne $mode.PSObject.Properties[$act]) { $m = $mode.$act }
if ($null -ne $m -and $null -ne $m.PSObject.Properties["hangSeconds"]) { Start-Sleep -Seconds ([int]$m.hangSeconds) }
if ($null -ne $m -and $null -ne $m.PSObject.Properties["stdout"]) {
    # A scripted answer, written as it is: an old wezfleet's usage text, garbage, two lines, anything.
    [Console]::Out.Write([string]$m.stdout)
    if ($null -ne $m.PSObject.Properties["stderr"]) { [Console]::Error.Write([string]$m.stderr) }
    exit ([int]$m.exit)
}
if ($null -ne $m -and $null -ne $m.PSObject.Properties["throw"]) {
    # AN ERROR NOBODY PLANNED FOR, as the merged command answers one: still one line, exit 1, the stage
    # "error", and woken only where post has it.
    $e = [ordered]@{ id = (Get-FakeArg "-Id"); to = (Get-FakeArg "-To"); stage = "error" }
    if ($act -ceq "post") { $e["woken"] = $false }
    $e["reason"] = "unexpected error: " + [string]$m.throw
    Write-FakeJson $e
    exit 1
}

function Test-FakeTarget {
    # May this name a mailbox? The merged command's rule (wezfleet lib\Mail.ps1, Get-WfMailBoxPath).
    param([string]$Name)
    if ($Name -notmatch '^[A-Za-z0-9._-]{1,128}$') { return $false }
    if ($Name -match '\.$') { return $false }
    if ($Name -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\..*)?$') { return $false }
    return $true
}
function Get-FakeLabelProblem {
    # Why a label is refused, or "" (wezfleet lib\Mail.ps1, Get-WfMailLabelProblem).
    param([string]$Label)
    if ($Label.Length -gt 64) { return ("is " + $Label.Length + " characters; the most is 64") }
    foreach ($ch in $Label.ToCharArray()) {
        $cat = [char]::GetUnicodeCategory($ch)
        if ([char]::IsControl($ch) -or $cat -eq [System.Globalization.UnicodeCategory]::Format -or $cat -eq [System.Globalization.UnicodeCategory]::LineSeparator -or $cat -eq [System.Globalization.UnicodeCategory]::ParagraphSeparator) {
            return ("holds a control, format or line-break character (U+{0:X4}); it must be one line of printable characters" -f [int]$ch)
        }
    }
    return ""
}

$id = Get-FakeArg "-Id"
$store = Join-Path $root "store"
if (-not (Test-Path -LiteralPath $store)) { [void](New-Item -ItemType Directory -Path $store) }
$recPath = Join-Path $store ($id + ".json")

if ($act -ceq "post") {
    $to = Get-FakeArg "-To"
    $file = Get-FakeArg "-MessageFile"
    # THE MERGED COMMAND'S ORDER: the id, the target, the label, the file, the body, then a repost.
    if ($id -cnotmatch '\A[0-9a-f]{32}\z') { Write-FakeJson ([ordered]@{ id = $id; to = $to; stage = "refused"; woken = $false; reason = "the id must be 32 lowercase hex characters (a UUID without dashes)" }); exit 2 }
    if (-not (Test-FakeTarget $to)) { Write-FakeJson ([ordered]@{ id = $id; to = $to; stage = "refused"; woken = $false; reason = "the target session id is missing or malformed" }); exit 2 }
    $labelProblem = Get-FakeLabelProblem (Get-FakeArg "-FromLabel")
    if ($labelProblem) { Write-FakeJson ([ordered]@{ id = $id; to = $to; stage = "refused"; woken = $false; reason = ("-FromLabel " + $labelProblem) }); exit 2 }
    if (-not $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { Write-FakeJson ([ordered]@{ id = $id; to = $to; stage = "refused"; woken = $false; reason = "-MessageFile must name an existing file" }); exit 2 }
    $body = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    if ($body.Trim() -eq "") { Write-FakeJson ([ordered]@{ id = $id; to = $to; stage = "refused"; woken = $false; reason = "the message is empty" }); exit 2 }
    if (Test-Path -LiteralPath $recPath) {
        # A REPOST: nothing written, nothing woken, the existing stage reported.
        $rec = [System.IO.File]::ReadAllText($recPath) | ConvertFrom-Json
        Write-FakeJson ([ordered]@{ id = $id; to = $rec.to; stage = $rec.stage; woken = $false; reason = "already posted; nothing written and nobody woken again" })
        exit 0
    }
    $stage = "queued"; $reason = ""
    if ($null -ne $m -and $null -ne $m.PSObject.Properties["stage"]) { $stage = [string]$m.stage }
    if ($null -ne $m -and $null -ne $m.PSObject.Properties["reason"]) { $reason = [string]$m.reason }
    $rec = [ordered]@{ id = $id; to = $to; stage = $stage; reason = $reason; body = $body; fromLabel = (Get-FakeArg "-FromLabel"); fromSessionId = (Get-FakeArg "-FromSessionId") }
    [System.IO.File]::WriteAllText($recPath, ($rec | ConvertTo-Json -Compress -Depth 4), [System.Text.Encoding]::UTF8)
    $woken = $false
    if (-not ($null -ne $m -and $null -ne $m.PSObject.Properties["noWake"])) {
        $notice = "wezfleet: a message is waiting for you (first id " + $id + ") - run 'wezfleet mail read' to take it; this line is a pointer, not the message, and re-reading it changes nothing"
        [System.IO.File]::AppendAllText((Join-Path $root "typed.log"), ((@{ id = $id; text = $notice } | ConvertTo-Json -Compress) + "`n"), [System.Text.Encoding]::UTF8)
        $woken = $true
    }
    $code = 0
    if ($null -ne $m -and $null -ne $m.PSObject.Properties["exit"]) { $code = [int]$m.exit }
    Write-FakeJson ([ordered]@{ id = $id; to = $to; stage = $stage; woken = $woken; reason = $reason })
    exit $code
}
if ($act -ceq "status") {
    # Status takes any id the store could have written, in either case, and a found record carries no
    # reason: the merged command's answers, word for word.
    if ($id -notmatch '\A[A-Za-z0-9]{1,64}\z') { Write-FakeJson ([ordered]@{ id = $id; to = ""; stage = "refused"; reason = "the id is malformed" }); exit 2 }
    if (-not (Test-Path -LiteralPath $recPath)) { Write-FakeJson ([ordered]@{ id = $id; to = ""; stage = "absent"; reason = "no record with this id under the mail root" }); exit 3 }
    $rec = [System.IO.File]::ReadAllText($recPath) | ConvertFrom-Json
    $code = 0
    if ($null -ne $m -and $null -ne $m.PSObject.Properties["exit"]) { $code = [int]$m.exit }
    Write-FakeJson ([ordered]@{ id = $id; to = $rec.to; stage = $rec.stage; reason = "" })
    exit $code
}
[Console]::Out.WriteLine("wezfleet mail: unknown action '" + $act + "'. Use read, list, count, pump, post or status.")
exit 1
