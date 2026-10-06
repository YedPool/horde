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
#   mode.json   optional: how to misbehave, per command: { post|status: { exit; stdout; stage; reason;
#               hangSeconds; noWake } }
#
# THE CONTRACT IT PLAYS is wezfleet PR #65 (head 97428c9): `mail post -To -Id -MessageFile [-FromLabel]
# [-FromSessionId] -Json` and `mail status -Id [-To] -Json`, each printing one line of ASCII JSON; post
# exits 0 when the mail is on disk (new or existing), 1 on a write failure, 2 when refused; status exits 0
# when found, 2 for a malformed id, 3 when absent. A repost of one id writes nothing and wakes nothing.
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
    exit ([int]$m.exit)
}

$id = Get-FakeArg "-Id"
$store = Join-Path $root "store"
if (-not (Test-Path -LiteralPath $store)) { [void](New-Item -ItemType Directory -Path $store) }
$recPath = Join-Path $store ($id + ".json")

if ($act -ceq "post") {
    $to = Get-FakeArg "-To"
    $file = Get-FakeArg "-MessageFile"
    if ($id -cnotmatch '\A[0-9a-f]{32}\z') { Write-FakeJson ([ordered]@{ id = $id; to = $to; stage = "refused"; woken = $false; reason = "-Id must be 32 lowercase hex" }); exit 2 }
    if (-not $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { Write-FakeJson ([ordered]@{ id = $id; to = $to; stage = "refused"; woken = $false; reason = "-MessageFile must name an existing file" }); exit 2 }
    if (Test-Path -LiteralPath $recPath) {
        # A REPOST: nothing written, nothing woken, the existing stage reported.
        $rec = [System.IO.File]::ReadAllText($recPath) | ConvertFrom-Json
        Write-FakeJson ([ordered]@{ id = $id; to = $rec.to; stage = $rec.stage; woken = $false; reason = "already queued under this id" })
        exit 0
    }
    $body = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
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
    if ($id -cnotmatch '\A[0-9a-f]{32}\z') { Write-FakeJson ([ordered]@{ id = $id; to = ""; stage = "refused"; reason = "-Id must be 32 lowercase hex" }); exit 2 }
    if (-not (Test-Path -LiteralPath $recPath)) { Write-FakeJson ([ordered]@{ id = $id; to = ""; stage = "absent"; reason = "no record of this id" }); exit 3 }
    $rec = [System.IO.File]::ReadAllText($recPath) | ConvertFrom-Json
    $code = 0
    if ($null -ne $m -and $null -ne $m.PSObject.Properties["exit"]) { $code = [int]$m.exit }
    Write-FakeJson ([ordered]@{ id = $id; to = $rec.to; stage = $rec.stage; reason = $rec.reason })
    exit $code
}
[Console]::Out.WriteLine("wezfleet mail: unknown action '" + $act + "'. Use read, list, count, pump, post or status.")
exit 1
