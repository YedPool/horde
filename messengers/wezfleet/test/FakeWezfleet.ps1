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
#               hangSeconds; noWake; staleRefused; stalePane; writeFailed; internal }.
#               stderr goes with a scripted stdout: a parameter the host itself rejects prints nothing on
#               stdout, the host's words on stderr, and exits 1 (measured against wezfleet main, 2026-10-06)
#
# THE CONTRACT IT PLAYS is wezfleet main's (1122461, read 2026-10-09; its lib/MailPost.ps1, THE
# CONTRACT, as pull request 70 made it; 72 to 76 left mail post and status as they were):
#   post   -Json: { id, to, stage, woken, reason, detail }      status -Json: { id, to, stage, reason, detail }
#   reason is a code from a closed list; detail is at most 300 characters, control characters made spaces.
#   exit 0  post on disk (woken, already-posted, no-registry-record, pane-unverified, send-refused);
#           status found, with detail empty
#   exit 1  write-failed (stage absent) or internal-error (stage error); there is no exit 5
#   exit 2  refused (stage refused): bad-id, bad-to, bad-from, bad-file, message-too-large (over 256 KB on
#           disk), invalid-utf8 (strict decoding, a leading BOM dropped), empty-message - in that order
#   exit 3  status absent
#   exit 4  post stale-session: stage refused when nothing was written (no live process is the session),
#           queued when the mail was written but the session's pane is held by another session
# Ids are 32 lower-case hex for post (10 or 32 for status); -To and -FromSessionId lower-case session
# UUIDs. A repost of an id reports the record (already-posted), its "to" being the mailbox the record is
# in NOW, which a compact may have moved. -Kind, which wezfleet main's command line now declares for tell
# (its pull request 76), is accepted and ignored here as it is there: mail post never reads it.
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
    # wezfleet's ConvertTo-WfMailDetail: control characters become spaces, runs collapse, 300 at most.
    $d = (("$Detail" -replace '[\x00-\x1f\x7f-\x9f\u2028\u2029]', ' ') -replace ' {2,}', ' ').Trim()
    if ($d.Length -gt 300) { $d = $d.Substring(0, 300) }
    $r["detail"] = $d
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
    if (Test-Mode $m "internal") { Write-FakeAnswer -Exit 1 -Id $id -To $to -Stage "error" -Woken $false -Reason "internal-error" -Detail "unexpected error: simulated fault" }
    if ($id -cnotmatch '\A[0-9a-f]{32}\z') { Write-FakeAnswer -Exit 2 -Id $id -To $to -Stage "refused" -Woken $false -Reason "bad-id" -Detail "the id must be 32 lowercase hex characters (a UUID without dashes)" }
    if ($to -cnotmatch $uuid) { Write-FakeAnswer -Exit 2 -Id $id -To $to -Stage "refused" -Woken $false -Reason "bad-to" -Detail "-To must be a session id: a lower-case UUID" }
    if ($fromLabel.Length -gt 64) { Write-FakeAnswer -Exit 2 -Id $id -To $to -Stage "refused" -Woken $false -Reason "bad-from" -Detail ("-FromLabel is " + $fromLabel.Length + " characters; the most is 64") }
    if ($fromLabel -match '[\x00-\x1f\x7f-\x9f\u2028\u2029]') { Write-FakeAnswer -Exit 2 -Id $id -To $to -Stage "refused" -Woken $false -Reason "bad-from" -Detail "-FromLabel holds a control, format or line-break character; it must be one line of printable characters" }
    if ($fromSid -and $fromSid -cnotmatch $uuid) { Write-FakeAnswer -Exit 2 -Id $id -To $to -Stage "refused" -Woken $false -Reason "bad-from" -Detail "-FromSessionId must be a session id (a lower-case UUID), or be left out" }
    if (-not $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { Write-FakeAnswer -Exit 2 -Id $id -To $to -Stage "refused" -Woken $false -Reason "bad-file" -Detail "-MessageFile must name an existing file" }
    $bytes = [System.IO.File]::ReadAllBytes($file)
    if ($bytes.Length -gt 262144) { Write-FakeAnswer -Exit 2 -Id $id -To $to -Stage "refused" -Woken $false -Reason "message-too-large" -Detail "the message file is larger than 262144 bytes (256 KB)" }
    $skip = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $skip = 3 }
    $body = $null
    try { $body = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes, $skip, $bytes.Length - $skip) } catch { $body = $null }
    if ($null -eq $body) { Write-FakeAnswer -Exit 2 -Id $id -To $to -Stage "refused" -Woken $false -Reason "invalid-utf8" -Detail "the message file is not valid UTF-8; nothing was replaced and nothing was posted" }
    if ($body.Trim() -eq "") { Write-FakeAnswer -Exit 2 -Id $id -To $to -Stage "refused" -Woken $false -Reason "empty-message" -Detail "the message is empty" }
    if (Test-Path -LiteralPath $recPath) {
        # A REPOST: nothing written, nothing woken, the record reported where it is now.
        $rec = [System.IO.File]::ReadAllText($recPath) | ConvertFrom-Json
        Write-FakeAnswer -Exit 0 -Id $id -To $rec.to -Stage $rec.stage -Woken $false -Reason "already-posted" -Detail "already posted; nothing written and nobody woken again"
    }
    if (Test-Mode $m "staleRefused") { Write-FakeAnswer -Exit 4 -Id $id -To $to -Stage "refused" -Woken $false -Reason "stale-session" -Detail ("no live process on this machine is session " + $to + "; nothing was written. A session id changes on a compact, a /clear or a restart - post to its current id") }
    if (Test-Mode $m "writeFailed") { Write-FakeAnswer -Exit 1 -Id $id -To $to -Stage "absent" -Woken $false -Reason "write-failed" -Detail "the mail could not be written" }
    $stage = "queued"
    if (Test-Mode $m "stage") { $stage = [string]$m.stage }
    $rec = [ordered]@{ id = $id; to = $to; stage = $stage; body = $body; fromLabel = $fromLabel; fromSessionId = $fromSid }
    [System.IO.File]::WriteAllText($recPath, ($rec | ConvertTo-Json -Compress -Depth 4), [System.Text.Encoding]::UTF8)
    if (Test-Mode $m "stalePane") { Write-FakeAnswer -Exit 4 -Id $id -To $to -Stage $stage -Woken $false -Reason "stale-session" -Detail ("not woken, nothing typed: pane 7 now belongs to session 99999999-0000-4000-8000-000000000000, seen there more recently than " + $to + ". The mail is queued under the id it was posted to") }
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
    if (Test-Mode $m "internal") { Write-FakeAnswer -Exit 1 -Id $id -To "" -Stage "error" -Reason "internal-error" -Detail "unexpected error: simulated fault" }
    if ($id -cnotmatch '\A([0-9a-f]{10}|[0-9a-f]{32})\z') { Write-FakeAnswer -Exit 2 -Id $id -To "" -Stage "refused" -Reason "bad-id" -Detail "the id is malformed" }
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
