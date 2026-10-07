# FakeWezfleet.ps1 - a stand-in for the fleet's command, for the wezfleet messenger's tests only.
#
# WHY A FAKE (remote plan R21, slice 3b, merge condition 1). The messenger starts the fleet's command as a
# child process; the tests must see what that child was really handed and what it really did, without a
# real mail root, a real pane or a real session. The fixture copies this file into a temp folder as
# wezfleet.ps1, beside the marker files a wezfleet checkout has, and the messenger is pointed at that
# folder, so the program it starts is this script.
#
# WHAT IT KEEPS, all under its own folder and nowhere else:
#   argv.log    one JSON line per run: the arguments it received, as separate elements, the path of the
#               program that ran it, and its pid
#   store\<id>.json   one record per message id: { id; to; stage; body; fromLabel; fromSessionId }
#   typed.log   one JSON line per text "typed" into a session: { id; text } - the fake target. Only a wake
#               notice is ever written here, built the way wezfleet's Get-WfWakeNotice builds it
#   mode.json   optional, per command (post|status): { exit; stdout; stderr; stage; reason; detail;
#               hangSeconds; noWake; staleAbsent; stalePane; writeFailed; internal }. stderr goes with a
#               scripted stdout: a parameter the host itself rejects prints nothing on stdout, the host's
#               words on stderr, and exits 1 (measured against wezfleet main, 2026-10-06)
#
# THE CONTRACT IT PLAYS is wezfleet PR #65 as revised after its review (lib/MailPost.ps1, THE CONTRACT):
# fields id, to, stage, reason, detail, and post adds woken; reason is a CODE. Exits: 0 post on disk for a
# live session (woken or waiting) / status found; 1 post could not write; 2 refused input (bad-id, bad-to,
# bad-from, bad-file, ...), stage refused; 3 status no record; 4 post stale-session - stage absent when
# nothing was written, queued when the mail was written but the pane is held by another session; 5
# internal-error, stage unknown. A repost of an id reports the record (already-posted), its "to" being the
# mailbox the record is in NOW, which a compact may have moved.
param()
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$argvList = @($args | ForEach-Object { "$_" })
$selfPath = (Get-Process -Id $PID).Path
[System.IO.File]::AppendAllText((Join-Path $root "argv.log"), ((@{ argv = $argvList; program = $selfPath; pid = $PID } | ConvertTo-Json -Compress -Depth 4) + "`n"), [System.Text.Encoding]::ASCII)

$uuid = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
function Get-FakeArg {
    param([string]$Name)
    for ($i = 0; $i -lt $argvList.Count - 1; $i++) { if ($argvList[$i] -ceq $Name) { return $argvList[$i + 1] } }
    return ""
}
function Write-FakeAnswer {
    # One line of ASCII JSON, in #65's field order, and the exit code.
    param([int]$Exit, [string]$Id, [string]$To, [string]$Stage, $Woken = $null, [string]$Reason, [string]$Detail = "")
    $r = [ordered]@{ id = $Id; to = $To; stage = $Stage }
    if ($null -ne $Woken) { $r["woken"] = [bool]$Woken }
    $r["reason"] = $Reason
    $r["detail"] = $Detail
    $json = ([pscustomobject]$r | ConvertTo-Json -Compress -Depth 4)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $json.ToCharArray()) { if ([int]$ch -gt 0x7E) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) } else { [void]$sb.Append($ch) } }
    [Console]::Out.WriteLine($sb.ToString())
    exit $Exit
}
function Test-Mode { param($M, [string]$Name) return ($null -ne $M -and $null -ne $M.PSObject.Properties[$Name]) }

$mode = $null
$modePath = Join-Path $root "mode.json"
if (Test-Path -LiteralPath $modePath) { $mode = [System.IO.File]::ReadAllText($modePath) | ConvertFrom-Json }

if ($argvList.Count -lt 2 -or $argvList[0] -cne "mail") { [Console]::Out.WriteLine("fake wezfleet: only mail is played"); exit 1 }
$act = $argvList[1]
$m = $null
if (Test-Mode $mode $act) { $m = $mode.$act }
if (Test-Mode $m "hangSeconds") { Start-Sleep -Seconds ([int]$m.hangSeconds) }
if (Test-Mode $m "stdout") {
    # A scripted answer, written as it is: an old wezfleet's usage text, garbage, two lines, anything.
    [Console]::Out.Write([string]$m.stdout)
    if (Test-Mode $m "stderr") { [Console]::Error.Write([string]$m.stderr) }
    exit ([int]$m.exit)
}

$id = Get-FakeArg "-Id"
$store = Join-Path $root "store"
if (-not (Test-Path -LiteralPath $store)) { [void](New-Item -ItemType Directory -Path $store) }
$recPath = Join-Path $store ($id + ".json")

if ($act -ceq "post") {
    $to = Get-FakeArg "-To"
    $file = Get-FakeArg "-MessageFile"
    $fromLabel = Get-FakeArg "-FromLabel"
    $fromSid = Get-FakeArg "-FromSessionId"
    if (Test-Mode $m "internal") { Write-FakeAnswer -Exit 5 -Id $id -To $to -Stage "unknown" -Woken $false -Reason "internal-error" -Detail "wezfleet threw: simulated fault" }
    if ($id -cnotmatch '\A[0-9a-f]{32}\z') { Write-FakeAnswer -Exit 2 -Id $id -To $to -Stage "refused" -Woken $false -Reason "bad-id" -Detail "the id must be 32 lowercase hex characters" }
    if ($to -cnotmatch $uuid) { Write-FakeAnswer -Exit 2 -Id $id -To $to -Stage "refused" -Woken $false -Reason "bad-to" -Detail "-To must be a session id: a lowercase UUID with dashes" }
    if ($fromSid -and $fromSid -cnotmatch $uuid) { Write-FakeAnswer -Exit 2 -Id $id -To $to -Stage "refused" -Woken $false -Reason "bad-from" -Detail "-FromSessionId must be a lowercase session UUID" }
    if (-not $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { Write-FakeAnswer -Exit 2 -Id $id -To $to -Stage "refused" -Woken $false -Reason "bad-file" -Detail "-MessageFile must name an existing file" }
    if (Test-Path -LiteralPath $recPath) {
        # A REPOST: nothing written, nothing woken, the record reported where it is now.
        $rec = [System.IO.File]::ReadAllText($recPath) | ConvertFrom-Json
        Write-FakeAnswer -Exit 0 -Id $id -To $rec.to -Stage $rec.stage -Woken $false -Reason "already-posted" -Detail "nothing written and nobody woken again"
    }
    if (Test-Mode $m "staleAbsent") { Write-FakeAnswer -Exit 4 -Id $id -To $to -Stage "absent" -Woken $false -Reason "stale-session" -Detail "no live agent process on this machine is this session (compacted, cleared or exited); nothing was written - re-resolve the target and send again" }
    if (Test-Mode $m "writeFailed") { Write-FakeAnswer -Exit 1 -Id $id -To $to -Stage "absent" -Woken $false -Reason "write-failed" -Detail "the mail could not be written" }
    $body = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    $stage = "queued"
    if (Test-Mode $m "stage") { $stage = [string]$m.stage }
    $rec = [ordered]@{ id = $id; to = $to; stage = $stage; body = $body; fromLabel = $fromLabel; fromSessionId = $fromSid }
    [System.IO.File]::WriteAllText($recPath, ($rec | ConvertTo-Json -Compress -Depth 4), [System.Text.Encoding]::UTF8)
    if (Test-Mode $m "stalePane") { Write-FakeAnswer -Exit 4 -Id $id -To $to -Stage $stage -Woken $false -Reason "stale-session" -Detail "pane 7 is now occupied by 99999999-0000-4000-8000-000000000000, not by this session; nothing was typed" }
    $woken = $false; $reason = "no-registry-record"; $detail = "no registry record for this session on this machine, so no pane can be verified; the mail waits for its next turn boundary"
    if (-not (Test-Mode $m "noWake")) {
        $notice = "wezfleet: a message is waiting for you (first id " + $id + ") - run 'wezfleet mail read' to take it; this line is a pointer, not the message, and re-reading it changes nothing"
        [System.IO.File]::AppendAllText((Join-Path $root "typed.log"), ((@{ id = $id; text = $notice } | ConvertTo-Json -Compress) + "`n"), [System.Text.Encoding]::UTF8)
        $woken = $true; $reason = "woken"; $detail = ""
    }
    if (Test-Mode $m "reason") { $reason = [string]$m.reason }
    if (Test-Mode $m "detail") { $detail = [string]$m.detail }
    $code = 0
    if (Test-Mode $m "exit") { $code = [int]$m.exit }
    Write-FakeAnswer -Exit $code -Id $id -To $to -Stage $stage -Woken $woken -Reason $reason -Detail $detail
}
if ($act -ceq "status") {
    if (Test-Mode $m "internal") { Write-FakeAnswer -Exit 5 -Id $id -To "" -Stage "unknown" -Reason "internal-error" -Detail "wezfleet threw: simulated fault" }
    if ($id -cnotmatch '\A([0-9a-f]{10}|[0-9a-f]{32})\z') { Write-FakeAnswer -Exit 2 -Id $id -To "" -Stage "refused" -Reason "bad-id" -Detail "the id must be 10 or 32 lowercase hex characters" }
    if (-not (Test-Path -LiteralPath $recPath)) { Write-FakeAnswer -Exit 3 -Id $id -To "" -Stage "absent" -Reason "absent" -Detail "no record with this id under the mail root" }
    $rec = [System.IO.File]::ReadAllText($recPath) | ConvertFrom-Json
    $detail = ""
    if (Test-Mode $m "detail") { $detail = [string]$m.detail }
    $code = 0
    if (Test-Mode $m "exit") { $code = [int]$m.exit }
    Write-FakeAnswer -Exit $code -Id $id -To $rec.to -Stage $rec.stage -Reason "found" -Detail $detail
}
[Console]::Out.WriteLine("wezfleet mail: unknown action '" + $act + "'. Use read, list, count, pump, post or status.")
exit 1
