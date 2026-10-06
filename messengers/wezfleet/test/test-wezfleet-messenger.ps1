# DOES THE WEZFLEET MESSENGER HAND THE FLEET'S COMMAND EXACTLY WHAT IT SHOULD, AND READ ONLY WHAT IT SAID?
#
# Remote plan R21, slice 3b (messengers/wezfleet). The messenger starts the fleet's `mail post` and
# `mail status` (wezfleet PR #65) as a child and maps their one line of JSON onto the port's stages. Every
# case here runs against test\FakeWezfleet.ps1 in a fresh temp folder, through test\Fixture.ps1, and reads
# what happened from the fake's own records - never a real mail root, never a pane, never a session's
# folders. The plan's merge conditions for this slice, and where each is proved:
#   (1) real side effects, not the adapter's report ..... test-messenger-conformance.ps1, and section B
#   (2) one fixed start site, separate argv elements ..... section B here, and test-start-sites.ps1
#   (3) missing, wrong version or non-JSON is unknown .... sections A and D

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "messengers\Port.ps1")
. (Join-Path $root "messengers\wezfleet\Messenger.ps1")

$fx = & (Join-Path $here "Fixture.ps1") -Root $root
$m = Get-HordeMessenger -Name "wezfleet"
$script:seq = 0
function New-Msg {
    $script:seq++
    return [pscustomobject]@{
        messageId = ("0e000000-0000-4000-8000-" + $script:seq.ToString("000000000000"))
        sessionId = "22222222-3333-4444-8555-666666666666"
        label = "A"
        from = [pscustomobject]@{ deviceId = "0f000000-0000-4000-8000-000000000001"; sessionId = "33333333-4444-4555-8666-777777777777"; label = "M" }
        body = ("unit body " + [guid]::NewGuid().ToString("N") + "`nline two")
        ttlSeconds = 3600
    }
}
function N { param([string]$Id) return $Id.Replace("-", "") }
function With-Fake {
    # Run Block with a fresh fake, and always remove it.
    param([scriptblock]$Block, [switch]$Spaced)
    $st = & $fx.New -Spaced:$Spaced
    try { & $Block $st } finally { & $fx.Remove $st }
}
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$fixedPs = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")

Write-Host ""
Write-Host "--- A. where the fleet's command is: never a guess, never a relative or climbing path ---" -ForegroundColor Cyan

Set-HordeWezfleetMessengerRoot -Path ""
$a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not configured")) "with no folder configured, a post is unknown: the messenger never guesses where the fleet is"
Check ((Get-HordeMessengerStatus -Messenger $m -MessageId "0e000000-0000-4000-8000-000000000001").state -ceq "unknown") "and so is a status"
foreach ($bad in @("relative\folder", ($tempRoot + "a\..\b"), "\\server\share\x")) {
    Set-HordeWezfleetMessengerRoot -Path $bad
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not an absolute local folder")) ("a folder that is relative, climbs with .., or is a network share is refused (" + $bad + ")")
}
$missing = Join-Path $tempRoot ("horde-wfm-missing-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $missing)
try {
    Set-HordeWezfleetMessengerRoot -Path $missing
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("wezfleet.ps1")) ("wezfleet missing from the folder is unknown, naming the script it looked for (" + $a.reason + ")")
} finally { Remove-Item -LiteralPath $missing -Recurse -Force; Set-HordeWezfleetMessengerRoot -Path "" }
Check (Throws { Set-HordeWezfleetMessengerRoot -Path $tempRoot -TimeoutSeconds 0 } "TimeoutSeconds") "a timeout below 1 s is refused when it is set"

Write-Host ""
Write-Host "--- B. what the child is handed: the fixed PowerShell, the fixed script, separate arguments, the body only in a file ---" -ForegroundColor Cyan

With-Fake {
    param($st)
    $msg = New-Msg
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted") ("CONTROL: a post through the fake is known accepted (" + $(if ($a.state -ceq "known") { $a.value.stage } else { $a.reason }) + ")")
    $runs = @(& $fx.Runs $st)
    Check ($runs.Count -eq 1) "the post started the fleet's command exactly once"
    $r = $runs[0]
    Check ("$($r.program)" -ieq $fixedPs) ("the program started is the fixed PowerShell from the system folder (" + $r.program + ")")
    $argv = @($r.argv)
    $file = ""
    $i = [array]::IndexOf($argv, "-MessageFile"); if ($i -ge 0 -and $i + 1 -lt $argv.Count) { $file = "$($argv[$i + 1])" }
    $want = @("mail", "post", "-To", $msg.sessionId, "-Id", (N $msg.messageId), "-MessageFile", $file, "-FromLabel", "M", "-FromSessionId", $msg.from.sessionId, "-Json")
    Check ((@($argv) -join "|") -ceq ($want -join "|")) ("the arguments are exactly mail post -To -Id (32 hex) -MessageFile -FromLabel -FromSessionId -Json, each its own element (" + (@($argv) -join " ") + ")")
    $bodyLines = @($msg.body -split "`n")
    Check (@($argv | Where-Object { $a1 = "$_"; @($bodyLines | Where-Object { $a1.Contains($_) }).Count -gt 0 }).Count -eq 0) "no argument holds any line of the body: the body goes only through -MessageFile"
    Check ($file.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) ("the message file was written under the temp folder (" + $file + ")")
    Check (-not (Test-Path -LiteralPath $file)) "and is deleted once the post has answered"
    $o = & $fx.Observe $st $msg.messageId
    Check (@($o.bodies).Count -eq 1 -and "$(@($o.bodies)[0])" -ceq $msg.body) "the fake read the body from the file exactly as sent, both lines"
    $s = Get-HordeMessengerStatus -Messenger $m -MessageId $msg.messageId
    $runs = @(& $fx.Runs $st)
    Check ($s.state -ceq "known" -and $s.value.stage -ceq "accepted") "a status of it is known accepted"
    Check ((@($runs[1].argv) -join "|") -ceq (@("mail", "status", "-Id", (N $msg.messageId), "-Json") -join "|")) ("a status is exactly mail status -Id -Json (" + (@($runs[1].argv) -join " ") + ")")
}
With-Fake -Spaced {
    param($st)
    $msg = New-Msg
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    $runs = @(& $fx.Runs $st)
    Check ($a.state -ceq "known" -and $runs.Count -eq 1 -and "$($runs[0].argv[0])" -ceq "mail") "a fleet folder whose path holds a space still starts the script, its arguments intact"
}
$msgNoLabel = New-Msg
$msgNoLabel.from.PSObject.Properties.Remove("label")
With-Fake {
    param($st)
    $null = Send-HordeMessengerMessage -Messenger $m -Message $msgNoLabel
    $argv = @(@(& $fx.Runs $st)[0].argv)
    Check (-not ($argv -ccontains "-FromLabel")) "a sender with no label sends no -FromLabel, never an empty one"
}

Write-Host ""
Write-Host "--- C. the fleet's stages, mapped onto the port's ---" -ForegroundColor Cyan

foreach ($c in @(
        @{ stage = "queued"; exit = 0; want = "accepted" },
        @{ stage = "handed-over"; exit = 0; want = "handed-over" },
        @{ stage = "taken"; exit = 0; want = "seen" },
        @{ stage = "unconfirmed"; exit = 0; want = "expired"; reason = "no hook confirmed it within its window" },
        @{ stage = "refused"; exit = 2; want = "held"; reason = "-MessageFile must name an existing file" })) {
    With-Fake {
        param($st)
        $mode = @{ stage = $c.stage; exit = $c.exit }
        if ($c.ContainsKey("reason")) { $mode.reason = $c.reason }
        & $fx.SetMode $st @{ post = $mode }
        $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
        $ok = ($a.state -ceq "known" -and $a.value.stage -ceq $c.want)
        if ($c.ContainsKey("reason")) { $ok = $ok -and "$($a.value.reason)".Contains($c.reason) }
        Check $ok ("wezfleet " + $c.stage + " (exit " + $c.exit + ") is the port's " + $c.want + $(if ($c.ContainsKey("reason")) { ", with wezfleet's reason" } else { "" }) + " (" + $(if ($a.state -ceq "known") { $a.value.stage } else { $a.reason }) + ")")
    }
}
With-Fake {
    param($st)
    & $fx.SetMode $st @{ post = @{ stage = "unconfirmed"; exit = 0; reason = "" } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "expired" -and "$($a.value.reason)".Trim() -ne "") "unconfirmed with no reason from wezfleet still carries a reason"
}
With-Fake {
    param($st)
    & $fx.SetMode $st @{ post = @{ stage = "refused"; exit = 2; reason = "" } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and "$($a.value.reason)".Trim() -ne "") "refused with no reason from wezfleet is still held with a reason"
}
With-Fake {
    param($st)
    $a = Get-HordeMessengerStatus -Messenger $m -MessageId "0e000000-0000-4000-8000-0000000000aa"
    Check ($a.state -ceq "absent") "status exit 3, absent, is the port's absent"
}

Write-Host ""
Write-Host "--- D. anything outside the table is unknown, with the reason: never a stage guessed ---" -ForegroundColor Cyan

$cases = @(
    @{ what = "a wezfleet too old to have mail post (its usage text, exit 1)"; mode = @{ post = @{ stdout = "wezfleet mail: unknown action 'post'. Use read, list, count or pump.`n"; exit = 1 } }; like = "exit 1" },
    @{ what = "output that is not JSON"; mode = @{ post = @{ stdout = "all good`n"; exit = 0 } }; like = "JSON" },
    @{ what = "two lines of JSON"; mode = @{ post = @{ stdout = '{"id":"x"}' + "`n" + '{"id":"y"}' + "`n"; exit = 0 } }; like = "one line" },
    @{ what = "nothing at all"; mode = @{ post = @{ stdout = ""; exit = 0 } }; like = "one line" },
    @{ what = "a newer shape without woken"; mode = @{ post = @{ stdout = '{"id":"ID","to":"T","stage":"queued","reason":""}' + "`n"; exit = 0 } }; like = "without 'woken'" },
    @{ what = "a shape without to"; mode = @{ post = @{ stdout = '{"id":"ID","stage":"queued","woken":true,"reason":""}' + "`n"; exit = 0 } }; like = "without 'to'" },
    @{ what = "a shape with a field this messenger does not read"; mode = @{ post = @{ stdout = '{"id":"ID","to":"T","stage":"queued","woken":true,"reason":"","pane":4}' + "`n"; exit = 0 } }; like = "answered with 'pane'" },
    @{ what = "woken that is not true or false"; mode = @{ post = @{ stdout = '{"id":"ID","to":"T","stage":"queued","woken":"yes","reason":""}' + "`n"; exit = 0 } }; like = "woken that is not true or false" },
    @{ what = "a stage that is not text"; mode = @{ post = @{ stdout = '{"id":"ID","to":"T","stage":5,"woken":true,"reason":""}' + "`n"; exit = 0 } }; like = "stage that is not text" },
    @{ what = "more output than one answer could be"; mode = @{ post = @{ stdout = ("x" * 70000); exit = 0 } }; like = "65536" },
    @{ what = "a stage wezfleet does not have"; mode = @{ post = @{ stdout = '{"id":"ID","to":"T","stage":"delivered","woken":true,"reason":""}' + "`n"; exit = 0 } }; like = "delivered" },
    @{ what = "an answer about another id"; mode = @{ post = @{ stdout = '{"id":"0e00000000004000800000000000ffff","to":"T","stage":"queued","woken":true,"reason":""}' + "`n"; exit = 0 } }; like = "0e00000000004000800000000000ffff" },
    @{ what = "exit 0 with stage refused"; mode = @{ post = @{ stdout = '{"id":"ID","to":"T","stage":"refused","woken":false,"reason":"r"}' + "`n"; exit = 0 } }; like = "refused" },
    @{ what = "exit 2 with stage queued"; mode = @{ post = @{ stdout = '{"id":"ID","to":"T","stage":"queued","woken":false,"reason":"r"}' + "`n"; exit = 2 } }; like = "exit 2" },
    @{ what = "a write failure, exit 1"; mode = @{ post = @{ stdout = '{"id":"ID","to":"T","stage":"queued","woken":false,"reason":"disk full"}' + "`n"; exit = 1 } }; like = "disk full" },
    @{ what = "an exit code outside the table"; mode = @{ post = @{ stdout = '{"id":"ID","to":"T","stage":"queued","woken":true,"reason":""}' + "`n"; exit = 7 } }; like = "not an exit code" })
foreach ($c in $cases) {
    With-Fake {
        param($st)
        $msg = New-Msg
        $mode = $c.mode
        $mode.post.stdout = "$($mode.post.stdout)".Replace("ID", (N $msg.messageId))
        & $fx.SetMode $st $mode
        $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
        Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains($c.like)) ("unknown: " + $c.what + " (" + $a.reason + ")")
    }
}
With-Fake {
    param($st)
    & $fx.SetMode $st @{ status = @{ stdout = '{"id":"x","to":"","stage":"refused","reason":"-Id must be 32 lowercase hex"}' + "`n"; exit = 2 } }
    $a = Get-HordeMessengerStatus -Messenger $m -MessageId "0e000000-0000-4000-8000-000000000001"
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("exit 2")) "a status refused as malformed, exit 2, is unknown"
}
With-Fake {
    param($st)
    & $fx.SetMode $st @{ status = @{ stdout = '{"id":"ID","to":"T","stage":"queued","reason":""}' + "`n"; exit = 3 } }
    $msg = New-Msg
    $fxMode = @{ status = @{ stdout = ('{"id":"' + (N $msg.messageId) + '","to":"T","stage":"queued","reason":""}' + "`n"); exit = 3 } }
    & $fx.SetMode $st $fxMode
    $a = Get-HordeMessengerStatus -Messenger $m -MessageId $msg.messageId
    Check ($a.state -ceq "unknown") "status exit 3 with a stage other than absent is unknown, never absent"
}
# A HANG IS STOPPED. The fleet's command is given a deadline; past it, the child is killed and the answer
# is unknown - the node never waits forever on another program.
With-Fake {
    param($st)
    Set-HordeWezfleetMessengerRoot -Path $st.dir -TimeoutSeconds 3
    & $fx.SetMode $st @{ post = @{ hangSeconds = 60 } }
    $t0 = Get-Date
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    $took = ((Get-Date) - $t0).TotalSeconds
    $runs = @(& $fx.Runs $st)
    $childPid = $(if ($runs.Count -ge 1) { [int]$runs[0].pid } else { 0 })
    Start-Sleep -Milliseconds 500
    $alive = ($childPid -gt 0) -and ($null -ne (Get-Process -Id $childPid -ErrorAction SilentlyContinue))
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("3 s") -and $took -lt 30) ("a hung command is unknown after its deadline (" + [int]$took + " s): " + $a.reason)
    Check ($childPid -gt 0 -and -not $alive) ("and the child it started was stopped (pid " + $childPid + ")")
}
# THE TEMP FILE NEVER OUTLIVES A FAILURE either.
With-Fake {
    param($st)
    & $fx.SetMode $st @{ post = @{ stdout = "garbage`n"; exit = 0 } }
    $null = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    $runs = @(& $fx.Runs $st)
    $argv = @($runs[0].argv)
    $i = [array]::IndexOf($argv, "-MessageFile")
    Check ($i -ge 0 -and -not (Test-Path -LiteralPath "$($argv[$i + 1])")) "after an answer that could not be read, the message file is deleted too"
}

Complete-HordeSuite -Success "the wezfleet messenger starts only the fixed PowerShell on the configured fleet script, hands the body only through a temp file, and reads nothing it was not told"
