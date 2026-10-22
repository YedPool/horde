# DOES THE WEZFLEET MESSENGER HAND THE FLEET'S COMMAND EXACTLY WHAT IT SHOULD, AND READ ONLY WHAT IT SAID?
#
# Remote plan R21, slice 3b (messengers/wezfleet). The messenger starts the fleet's `mail post` and
# `mail status` (wezfleet PR #65, in the shape wezfleet main has since its PR #70) as a child and maps their one line of JSON
# onto the port's stages. Every case here runs against test\FakeWezfleet.ps1 in a fresh temp folder,
# through test\Fixture.ps1, which also moves HORDE_HOME into the temp folder, and reads what happened from
# the fake's own records - never a real mail root, never a pane, never a session's folders. The plan's
# merge conditions for this slice, and where each is proved:
#   (1) real side effects, not the adapter's report ..... test-messenger-conformance.ps1, and section B
#   (2) one fixed start site, separate argv elements ..... section B here, and test-start-sites.ps1
#   (3) missing, wrong version or non-JSON is unknown .... sections A and E
# and the review of #106: the root is a real local checkout (A), the body files sit in a folder only
# this user can open and are swept (F), a target or sender wezfleet cannot name is refused before any
# process starts (B), main's answer - reason codes, detail, exit 4, exit 1 for an internal error - is
# read (C, D, E), an answer naming another target is not read as this one's (D), and the answer is read
# when the command exits although a grandchild still holds its output, and a stopped command's
# grandchildren are stopped with it (E; review findings F6 and F7).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "messengers\Port.ps1")
. (Join-Path $root "messengers\wezfleet\Messenger.ps1")
. (Join-Path $root "test\lib\MessengerPins.ps1")
# PINNED (test\Pin.ps1): with no folder set, the messenger runs the checkout the wezfleet command on PATH
# runs - the real fleet, on a machine where it is installed. So the whole suite runs under a home pinned
# to an empty folder, and the fixture puts this home back after each state.
$pinned = Enter-HordeTestPinnedHome -Root $root

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
        # Two lines and a non-ASCII letter: the file must carry both, in UTF-8.
        body = ("unit body " + [guid]::NewGuid().ToString("N") + "`nline two caf" + [char]0x00E9)
        ttlSeconds = 3600
    }
}
function N { param([string]$Id) return $Id.Replace("-", "") }
function Why {
    # An answer's reason, looked up: the port leaves an empty reason out of its value, and under strict
    # mode reading a missing member throws - which a mutation run counts as a broken suite, not a catch.
    param($Answer)
    if ($Answer.state -cne "known") { return "" }
    $r = $Answer.value.PSObject.Properties["reason"]
    if ($null -eq $r) { return "" }
    return "$($r.Value)"
}
function Show-Answer { param($A) if ($A.state -ceq "known") { return ($A.value.stage + ": " + (Why $A)) } return ($A.state + ": " + $A.reason) }
function With-Fake {
    # Run Block with a fresh fake, and always remove it.
    param([scriptblock]$Block, [switch]$Spaced, [switch]$TakesVerified)
    $st = & $fx.New -Spaced:$Spaced -TakesVerified:$TakesVerified
    try { & $Block $st } finally { & $fx.Remove $st }
}
function Line {
    # One answer line as the revised #65 prints it, for a scripted stdout.
    param([string]$Id, [string]$To = "22222222-3333-4444-8555-666666666666", [string]$Stage = "queued", $Woken = $true, [string]$Reason = "woken", $Detail = "", [hashtable]$Extra = @{}, [string[]]$Drop = @())
    $o = [ordered]@{ id = $Id; to = $To; stage = $Stage }
    if ($null -ne $Woken) { $o["woken"] = $Woken }
    $o["reason"] = $Reason
    $o["detail"] = $Detail
    foreach ($k in $Extra.Keys) { $o[$k] = $Extra[$k] }
    foreach ($k in $Drop) { $o.Remove($k) }
    return (([pscustomobject]$o | ConvertTo-Json -Compress) + "`n")
}
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$fixedPs = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")
$other = "99999999-8888-4777-8666-555555555555"

Write-Host ""
Write-Host "--- A. where the fleet is: configured, absolute, local, no reparse point, a real checkout ---" -ForegroundColor Cyan

Set-HordeWezfleetMessengerRoot -Path ""
$a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not a wezfleet checkout") -and "$($a.reason)".Contains("set as root in")) ("with no folder set in the process, the pinned setting decides, and its empty folder is no checkout: the messenger never looks further (" + $a.reason + ")")
Check ((Get-HordeMessengerStatus -Messenger $m -MessageId "0e000000-0000-4000-8000-000000000001").state -ceq "unknown") "and so is a status"
foreach ($bad in @("relative\folder", ($tempRoot + "a\..\b"), "\\server\share\x", "\\?\C:\x")) {
    Set-HordeWezfleetMessengerRoot -Path $bad
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not an absolute local folder")) ("a folder that is relative, climbs with .., or is a network or device path is refused (" + $bad + ")")
}
# A FOLDER ON A DRIVE THAT IS NOT THERE - a removable or mapped drive, unplugged - is a folder that does
# not exist, and must read as one. Before the checkout rules came in, Join-Path raised "Cannot find
# drive" for such a letter and the port reported "failed to post ... Cannot find drive" (measured
# 2026-10-06, on the first shape of this function). A missing letter is looked for, never assumed.
$gone = @([char[]]"ZYXWVUTSRQ" | Where-Object { -not [System.IO.Directory]::Exists("$_" + ":\") }) | Select-Object -First 1
Check ($null -ne $gone) "CONTROL: a drive letter from Q to Z is not in use here, so the next two checks ran against a drive that is not there"
if ($null -ne $gone) {
    Set-HordeWezfleetMessengerRoot -Path ("$gone" + ":\fleet")
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("does not exist") -and -not "$($a.reason)".Contains("failed to")) ("a folder on a drive that is not there is unknown as a folder that does not exist, not as a failure of the messenger (" + $a.reason + ")")
    $a = Get-HordeMessengerStatus -Messenger $m -MessageId "0e000000-0000-4000-8000-000000000001"
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("does not exist") -and -not "$($a.reason)".Contains("failed to")) ("and so is a status (" + $a.reason + ")")
}
Set-HordeWezfleetMessengerRoot -Path ""
With-Fake {
    param($st)
    # A BARE FOLDER HOLDING ONLY A wezfleet.ps1 is not a checkout: each marker missing is named.
    foreach ($marker in @("lib\MailPost.ps1", "lib\Mail.ps1", "commands\mail.ps1", "wezfleet.ps1")) {
        $mp = Join-Path $st.dir $marker
        $keep = [System.IO.File]::ReadAllBytes($mp)
        Remove-Item -LiteralPath $mp
        $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
        Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not a wezfleet checkout") -and "$($a.reason)".Contains($marker) -and @(& $fx.Runs $st).Count -eq 0) ("a folder without " + $marker + " is not a wezfleet checkout, and nothing is started (" + $a.reason + ")")
        [System.IO.File]::WriteAllBytes($mp, $keep)
    }
    # A JUNCTION, as the folder itself or anywhere above it, is refused: the configured path must be the
    # real one, not a pointer that can be re-aimed after it was configured.
    $j = $st.dir + "-junction"
    [void](New-Item -ItemType Junction -Path $j -Target $st.dir)
    try {
        Set-HordeWezfleetMessengerRoot -Path $j -TimeoutSeconds 60
        $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
        Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("reparse point") -and @(& $fx.Runs $st).Count -eq 0) ("a junction to a real checkout is refused, and nothing is started (" + $a.reason + ")")
        $up = $st.dir + "-up"
        [void](New-Item -ItemType Junction -Path $up -Target (Split-Path -Parent $st.dir))
        try {
            Set-HordeWezfleetMessengerRoot -Path (Join-Path $up (Split-Path -Leaf $st.dir)) -TimeoutSeconds 60
            $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
            Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("reparse point")) ("a junction ABOVE the folder is refused too (" + $a.reason + ")")
        } finally { [System.IO.Directory]::Delete($up) }
    } finally { [System.IO.Directory]::Delete($j); Set-HordeWezfleetMessengerRoot -Path $st.dir -TimeoutSeconds 60 }
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    Check ($a.state -ceq "known") ("CONTROL: the real checkout itself is accepted (" + (Show-Answer $a) + ")")
}
Check (Throws { Set-HordeWezfleetMessengerRoot -Path $tempRoot -TimeoutSeconds 0 } "TimeoutSeconds") "a timeout below 1 s is refused when it is set"

Write-Host ""
Write-Host "--- B. what the child is handed: the fixed PowerShell, the fixed script, separate arguments, the body only in a file ---" -ForegroundColor Cyan

With-Fake {
    param($st)
    $msg = New-Msg
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted") ("CONTROL: a post through the fake is known accepted (" + (Show-Answer $a) + ")")
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
    Check (-not (Test-Path -LiteralPath $file)) "the message file is deleted once the post has answered"
    $o = & $fx.Observe $st $msg.messageId
    Check (@($o.bodies).Count -eq 1 -and "$(@($o.bodies)[0])" -ceq $msg.body) "the fake read the body from the file exactly as sent, both lines and the non-ASCII letter"
    $s = Get-HordeMessengerStatus -Messenger $m -MessageId $msg.messageId
    $runs = @(& $fx.Runs $st)
    Check ($s.state -ceq "known" -and $s.value.stage -ceq "accepted") "a status of it is known accepted"
    Check ((@($runs[1].argv) -join "|") -ceq (@("mail", "status", "-Id", (N $msg.messageId), "-Json") -join "|")) ("a status is exactly mail status -Id -Json (" + (@($runs[1].argv) -join " ") + ")")
}
With-Fake -Spaced {
    param($st)
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    $runs = @(& $fx.Runs $st)
    Check ($a.state -ceq "known" -and $runs.Count -eq 1 -and "$($runs[0].argv[0])" -ceq "mail") "a fleet folder whose path holds a space still starts the script, its arguments intact"
}
# WHO WEZFLEET CAN NAME (review of #106, G6; decided 2026-10-06). wezfleet takes -To and -FromSessionId
# only as lower-case session UUIDs, and -FromLabel only as a label. A sender whose session id is not one
# is named by its label alone; a target wezfleet cannot name, or a sender with neither, is held here,
# before any process starts.
With-Fake {
    param($st)
    $msg = New-Msg
    $msg.from.PSObject.Properties.Remove("label")
    $null = Send-HordeMessengerMessage -Messenger $m -Message $msg
    $argv = @(@(& $fx.Runs $st)[0].argv)
    Check (-not ($argv -ccontains "-FromLabel")) "a sender with no label sends no -FromLabel, never an empty one"
}
# A VERIFIED SENDER (from.verified, the founder's line the relay verified) IS PASSED AS -FromVerified ONLY
# TO A WEZFLEET THAT DECLARES IT (the header, A VERIFIED SENDER). wezfleet main at 1122461 declares no such
# argument, and PowerShell refuses an undeclared one before the script runs - every founder line would
# come back unknown and the chat channel would hold it. So against main's shape the line still goes, by
# label, unlabelled, and the answer says why; against a wezfleet that takes it, it goes with the claim.
function Add-Verified { param($Msg, [string]$KeyId = ("ab" * 16)) $Msg.from | Add-Member -NotePropertyName verified -NotePropertyValue ([pscustomobject]@{ kind = "founder"; by = "passkey"; keyId = $KeyId }); return $Msg }
function Get-Pair { param($Argv, [string]$Name) $all = @($Argv | Where-Object { $null -ne $_ }); for ($i = 0; $i -lt $all.Count - 1; $i++) { if ("$($all[$i])" -ceq $Name) { return "$($all[$i + 1])" } } return $null }
function Get-FakeRecord { param($St, [string]$MessageId) $p = Join-Path (Join-Path $St.dir "store") ((N $MessageId) + ".json"); if (-not (Test-Path -LiteralPath $p)) { return $null } return ([System.IO.File]::ReadAllText($p) | ConvertFrom-Json) }
With-Fake {
    param($st)
    $msg = Add-Verified (New-Msg)
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    $runs = @(& $fx.Runs $st)
    $argv = $(if ($runs.Count -gt 0) { @($runs[0].argv) } else { @() })
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted" -and $runs.Count -eq 1 -and ($argv -ccontains "-FromLabel") -and -not ($argv -ccontains "-FromVerified")) ("to a wezfleet that does not declare -FromVerified, a verified sender posts as before, by its label, and is accepted (" + ($argv -join " ") + "; " + (Show-Answer $a) + ")")
    Check ((& $fx.Observe $st $msg.messageId).records -eq 1) "and the line is on the fake's disk: nothing was held"
    Check ((Why $a).Contains("without the verified label") -and (Why $a).Contains("-FromVerified")) ("and the answer says it went without the verified label, and why (" + (Why $a) + ")")
}
With-Fake -TakesVerified {
    param($st)
    $msg = Add-Verified (New-Msg) -KeyId ("0123456789abcdef" * 2)
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    $runs = @(& $fx.Runs $st)
    $argv = $(if ($runs.Count -gt 0) { @($runs[0].argv) } else { @() })
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted" -and (Get-Pair $argv "-FromVerified") -ceq ("founder:passkey:" + ("0123456789abcdef" * 2))) ("to a wezfleet that declares it, a verified sender is passed as -FromVerified founder:passkey:<key id> (" + ($argv -join " ") + "; " + (Show-Answer $a) + ")")
    Check ((Get-Pair $argv "-FromLabel") -ceq "M") "beside its label"
    $rec = Get-FakeRecord $st $msg.messageId
    Check ($null -ne $rec -and $null -ne $rec.PSObject.Properties["fromVerified"] -and "$($rec.fromVerified.keyId)" -ceq ("0123456789abcdef" * 2) -and "$($rec.fromVerified.kind)" -ceq "founder" -and "$($rec.fromVerified.by)" -ceq "passkey") "and the fake's own record holds it, as the wezfleet that takes it keeps it"
    Check (-not (Why $a).Contains("without the verified label")) ("and the answer carries no note (" + (Why $a) + ")")
}
With-Fake -TakesVerified {
    param($st)
    $msg = New-Msg
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    $argv = @(@(& $fx.Runs $st)[0].argv)
    Check ($a.state -ceq "known" -and -not ($argv -ccontains "-FromVerified")) ("CONTROL: a sender that is not verified is never passed -FromVerified, even to a wezfleet that takes it (" + ($argv -join " ") + ")")
    Check (-not (Why $a).Contains("verified")) "and its answer says nothing about a label"
}
With-Fake -TakesVerified {
    param($st)
    # A DICTIONARY from and verified, which the port accepts as well as objects.
    $msg = New-Msg
    $msg.from = @{ deviceId = $msg.from.deviceId; sessionId = $msg.from.sessionId; label = "M"; verified = @{ kind = "founder"; by = "passkey"; keyId = ("cd" * 16) } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    $runs = @(& $fx.Runs $st)
    $argv = $(if ($runs.Count -gt 0) { @($runs[0].argv) } else { @() })
    Check ($a.state -ceq "known" -and (Get-Pair $argv "-FromVerified") -ceq ("founder:passkey:" + ("cd" * 16)) -and (Get-Pair $argv "-FromLabel") -ceq "M") ("a sender given as a dictionary, verified as one, is passed the same way (" + ($argv -join " ") + ")")
}
# THE MESSENGER HOLDS THE PORT'S RULE AGAIN, before any process starts: called without the port, a
# malformed claim is held, bad-from - never passed on, and never dropped so the line reads unverified
# while the caller believes it was labelled.
With-Fake -TakesVerified {
    param($st)
    foreach ($bad in @(
            @{ what = "another kind"; v = [pscustomobject]@{ kind = "thrall"; by = "passkey"; keyId = ("ab" * 16) } },
            @{ what = "another means"; v = [pscustomobject]@{ kind = "founder"; by = "password"; keyId = ("ab" * 16) } },
            @{ what = "a short key id"; v = [pscustomobject]@{ kind = "founder"; by = "passkey"; keyId = "ab" } },
            @{ what = "an upper-case key id"; v = [pscustomobject]@{ kind = "founder"; by = "passkey"; keyId = ("AB" * 16) } },
            @{ what = "a key id with a colon"; v = [pscustomobject]@{ kind = "founder"; by = "passkey"; keyId = ("ab" * 15 + ":x") } },
            @{ what = "no key id"; v = [pscustomobject]@{ kind = "founder"; by = "passkey" } },
            @{ what = "a string"; v = ("founder:passkey:" + ("ab" * 16)) })) {
        $msg = New-Msg
        $msg.from | Add-Member -NotePropertyName verified -NotePropertyValue $bad.v
        $before = @(& $fx.Runs $st).Count
        $a = Send-HordeWezfleetMessengerPost -Message $msg
        Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and "$($a.value.reason)".StartsWith("bad-from") -and @(& $fx.Runs $st).Count -eq $before) ("a verified sender with " + $bad.what + ", handed to the messenger directly, is held bad-from and nothing starts (" + (Show-Answer $a) + ")")
    }
    # A VERIFIED SENDER WITHOUT A LABEL: wezfleet's -FromVerified needs -FromLabel, so it is held here.
    $msg = Add-Verified (New-Msg)
    $msg.from.PSObject.Properties.Remove("label")
    $before = @(& $fx.Runs $st).Count
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and (Why $a).StartsWith("bad-from") -and @(& $fx.Runs $st).Count -eq $before) ("a verified sender with no label is held bad-from and nothing starts (" + (Show-Answer $a) + ")")
}

# THE PROBE (the header, A VERIFIED SENDER): does the script declare -FromVerified in its own param block?
# Read by PowerShell's parser, never run, so a comment or a string naming it, or a function inside the
# script declaring it, is not the script taking it.
$probeDir = Join-Path $tempRoot ("horde-wfm-probe-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
[void](New-Item -ItemType Directory -Path $probeDir)
try {
    $probes = @(
        @{ what = "a param block declaring it"; text = "param([string]`$To = `"`", [string]`$FromVerified = `"`")`r`n"; takes = $true },
        @{ what = "an advanced param block declaring it, in another case"; text = "param([Parameter(Position = 0)][string]`$Command = `"`",`r`n    [string]`$fromverified = `"`")`r`n"; takes = $true },
        @{ what = "main's shape: a param block without it, and the word in a comment and a string"; text = "# -FromVerified is not declared here`r`nparam([string]`$FromLabel = `"`")`r`n`$x = `"-FromVerified`"`r`n"; takes = $false },
        @{ what = "only a function inside the script declaring it"; text = "param([string]`$FromLabel = `"`")`r`nfunction f { param([string]`$FromVerified) }`r`n"; takes = $false },
        @{ what = "no param block at all"; text = "Write-Output 1`r`n"; takes = $false },
        @{ what = "a script that does not parse"; text = "param([string]`$FromVerified = `"`"`r`n{ {`r`n"; takes = $false })
    foreach ($p in $probes) {
        $f = Join-Path $probeDir ([guid]::NewGuid().ToString("N") + ".ps1")
        [System.IO.File]::WriteAllText($f, $p.text, [System.Text.Encoding]::ASCII)
        $why = Test-HordeWezfleetMessengerTakesVerified -Path $f
        if ($p.takes) { Check ($why -ceq "") ("the probe finds -FromVerified in " + $p.what + " (" + $why + ")") }
        else { Check ($why -ne "" -and $why.Contains("-FromVerified")) ("the probe does not take " + $p.what + " as declaring it (" + $why + ")") }
    }
    $why = Test-HordeWezfleetMessengerTakesVerified -Path (Join-Path $probeDir "missing.ps1")
    Check ($why.Contains("not there")) ("the probe of a script that is not there says so, and nothing is passed (" + $why + ")")
} finally { Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue }
# THE RESERVED SYSTEM SENDER (third review of PR 318, P3): from.system = "horde" is posted as -FromLabel horde,
# and wezfleet is NEVER given -FromSessionId, though the sender holds a real session UUID.
With-Fake {
    param($st)
    $msg = New-Msg
    $msg.from.PSObject.Properties.Remove("label")
    $msg.from | Add-Member -NotePropertyName system -NotePropertyValue "horde"
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    $argv = @(@(& $fx.Runs $st)[0].argv)
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted" -and (Get-Pair $argv "-FromLabel") -ceq "horde" -and -not ($argv -ccontains "-FromSessionId")) ("a system sender is named horde and never by a session id (" + ($argv -join " ") + "; " + (Show-Answer $a) + ")")
    $rec = Get-Content -LiteralPath (Join-Path (Join-Path $st.dir "store") ((N $msg.messageId) + ".json")) -Raw | ConvertFrom-Json
    Check ($rec.fromLabel -ceq "horde" -and "" + $rec.fromSessionId -ceq "") "the receiver's record says the sender calls itself horde, with no session id"
    $msg2 = New-Msg
    $msg2.from.sessionId = "agent-thread-7"
    $msg2.from.PSObject.Properties.Remove("label")
    $msg2.from | Add-Member -NotePropertyName system -NotePropertyValue "horde"
    $a = Send-HordeWezfleetMessengerPost -Message $msg2
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted") "and a system sender whose session id is no UUID is not held bad-from (P3)"
    $msg3 = New-Msg
    $msg3.from | Add-Member -NotePropertyName system -NotePropertyValue "evil"
    $before = @(& $fx.Runs $st).Count
    $a = Send-HordeWezfleetMessengerPost -Message $msg3
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and (Why $a).StartsWith("bad-from") -and @(& $fx.Runs $st).Count -eq $before) "any other system is held bad-from, and nothing starts"
}
With-Fake {
    param($st)
    $msg = New-Msg
    $msg.from.sessionId = "agent-thread-7"
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    $argv = @(@(& $fx.Runs $st)[0].argv)
    Check ($a.state -ceq "known" -and -not ($argv -ccontains "-FromSessionId") -and ($argv -ccontains "-FromLabel")) ("a sender whose session id is not a UUID is named by its label alone; no -FromSessionId is passed (" + ($argv -join " ") + ")")
}
With-Fake {
    param($st)
    $msg = New-Msg
    $msg.from.sessionId = "agent-thread-7"
    $msg.from.PSObject.Properties.Remove("label")
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and (Why $a).StartsWith("bad-from") -and @(& $fx.Runs $st).Count -eq 0) ("a sender with neither a session UUID nor a label is held, bad-from, and nothing is started (" + (Show-Answer $a) + ")")
    $msg = New-Msg
    $msg.from.label = "orc-1"
    $a = Send-HordeWezfleetMessengerPost -Message $msg
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and (Why $a).StartsWith("bad-from") -and @(& $fx.Runs $st).Count -eq 0) ("a sender label that is not a hub label is held, bad-from, by the adapter itself (" + (Show-Answer $a) + ")")
    foreach ($to in @("agent-not-a-uuid", "22222222-3333-4444-8555-66666666666G", "22222222-3333-4444-8555-66666666666A")) {
        $msg = New-Msg
        $msg.sessionId = $to
        $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
        Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and (Why $a).StartsWith("bad-to") -and @(& $fx.Runs $st).Count -eq 0) ("a target that is not a lower-case session UUID is held, bad-to, and nothing is started (" + $to + ")")
    }
}

Write-Host ""
Write-Host "--- C. the fleet's stages and reasons, mapped onto the port's ---" -ForegroundColor Cyan

foreach ($c in @(
        @{ mode = @{}; want = "accepted"; why = "woken" },
        @{ mode = @{ noWake = $true }; want = "accepted"; why = "no-registry-record: no registry record" },
        @{ mode = @{ stage = "handed-over" }; want = "handed-over"; why = "woken" },
        @{ mode = @{ stage = "taken" }; want = "seen"; why = "woken" },
        @{ mode = @{ stage = "unconfirmed"; detail = "no hook confirmed it within its window" }; want = "expired"; why = "no hook confirmed it" })) {
    With-Fake {
        param($st)
        & $fx.SetMode $st @{ post = $c.mode }
        $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
        Check ($a.state -ceq "known" -and $a.value.stage -ceq $c.want -and (Why $a).Contains($c.why)) ("wezfleet " + (($c.mode.Keys | ForEach-Object { $_ + "=" + $c.mode[$_] }) -join " ") + " is the port's " + $c.want + ", reason with '" + $c.why + "' (" + (Show-Answer $a) + ")")
    }
}
# WOKEN, OR ONLY QUEUED (the founder's bug of 2026-10-12): each fresh post says whether wezfleet's knock
# landed, from wezfleet's own woken and its code together, and the port's words for it name the reason.
function Woken-Of { param($Answer) if ($Answer.state -cne "known") { return "not known" }; $p = $Answer.value.PSObject.Properties["woken"]; if ($null -eq $p) { return "unsaid" }; return "$($p.Value)" }
foreach ($c in @(
        @{ what = "a wake that landed"; mode = @{}; woken = "True"; words = "woken" },
        @{ what = "no pane of the target's found"; mode = @{ noWake = $true }; woken = "False"; words = "queued, NOT woken: no-registry-record: no registry record for this session on this machine, so no pane can be verified; the mail waits for its next turn boundary" },
        @{ what = "the terminal not answering"; mode = @{ noWake = $true; reason = "pane-unverified"; detail = "not woken: the terminal did not answer, so no pane can be verified; the mail waits for its next turn boundary" }; woken = "False"; words = "queued, NOT woken: pane-unverified: not woken: the terminal did not answer, so no pane can be verified; the mail waits for its next turn boundary" },
        @{ what = "a box holding somebody's unsent text"; mode = @{ noWake = $true; reason = "send-refused"; detail = "not woken (occupied); the mail waits for its next turn boundary" }; woken = "False"; words = "queued, NOT woken: send-refused: not woken (occupied); the mail waits for its next turn boundary" },
        @{ what = "woken true beside a code that says refused"; mode = @{ reason = "send-refused"; detail = "not woken (occupied)" }; woken = "False"; words = "queued, NOT woken: send-refused: not woken (occupied)" },
        @{ what = "the code woken beside woken false"; mode = @{ noWake = $true; reason = "woken"; detail = "" }; woken = "False"; words = "queued, NOT woken: woken" })) {
    With-Fake {
        param($st)
        & $fx.SetMode $st @{ post = $c.mode }
        $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
        Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted" -and (Woken-Of $a) -ceq $c.woken) ($c.what + ": accepted, woken " + $c.woken + " (" + (Woken-Of $a) + ", " + (Show-Answer $a) + ")")
        Check ((Format-HordeMessengerWake -Answer $a) -ceq $c.words) ("  and the words are '" + $c.words + "' (" + (Format-HordeMessengerWake -Answer $a) + ")")
    }
}
With-Fake {
    param($st)
    $msg = New-Msg
    $first = Send-HordeMessengerMessage -Messenger $m -Message $msg
    $again = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ((Woken-Of $first) -ceq "True" -and $again.state -ceq "known" -and (Why $again).StartsWith("already-posted") -and (Woken-Of $again) -ceq "unsaid") ("a repost knocks nobody again, and does not say the target sleeps: woken is left out (" + (Woken-Of $again) + ")")
    Check ((Format-HordeMessengerWake -Answer $again) -ceq "") "  and no wake words are made for it"
    $st2 = Get-HordeMessengerStatus -Messenger $m -MessageId $msg.messageId
    Check ($st2.state -ceq "known" -and (Woken-Of $st2) -ceq "unsaid") ("a status says nothing of the wake (" + (Show-Answer $st2) + ")")
}
With-Fake {
    param($st)
    & $fx.SetMode $st @{ post = @{ stalePane = $true } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and (Woken-Of $a) -ceq "unsaid") ("exit 4 is held, and held says why in its reason, not in woken (" + (Woken-Of $a) + ")")
}
With-Fake {
    param($st)
    & $fx.SetMode $st @{ post = @{ stage = "unconfirmed"; reason = ""; detail = "" } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "expired" -and (Why $a).Trim() -ne "") "unconfirmed with no reason from wezfleet still carries a reason"
}
With-Fake {
    param($st)
    $msg = New-Msg
    & $fx.SetMode $st @{ post = @{ stdout = (Line -Id (N $msg.messageId) -Stage "refused" -Woken $false -Reason "bad-file" -Detail "-MessageFile must name an existing file"); exit = 2 } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and (Why $a).StartsWith("bad-file: -MessageFile")) ("a refusal, exit 2, is held with wezfleet's reason code and detail (" + (Show-Answer $a) + ")")
    $msg = New-Msg
    & $fx.SetMode $st @{ post = @{ stdout = (Line -Id (N $msg.messageId) -Stage "refused" -Woken $false -Reason "" -Detail ""); exit = 2 } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and (Why $a).Trim() -ne "") "refused with no reason from wezfleet is still held with a reason"
}
# STALE-SESSION, EXIT 4, IS HELD IN BOTH OF WEZFLEET MAIN'S SHAPES (decided 2026-10-06; main 1122461,
# its pull request 70): nothing was written, stage refused, because no live process is the session; or
# the mail was written, stage queued, under a session that no longer holds its pane. Held is final: the
# hub reports it to the sender, and a retry is a new message.
With-Fake {
    param($st)
    $msg = New-Msg
    & $fx.SetMode $st @{ post = @{ staleRefused = $true } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and (Why $a).StartsWith("stale-session") -and (Why $a).Contains("no live process") -and (& $fx.Observe $st $msg.messageId).records -eq 0) ("exit 4 with nothing written, stage refused, is held, stale-session, the detail carried (" + (Show-Answer $a) + ")")
    & $fx.SetMode $st @{ post = @{ stalePane = $true } }
    $msg = New-Msg
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and (Why $a).StartsWith("stale-session") -and (& $fx.Observe $st $msg.messageId).records -eq 1) ("exit 4 with the mail written but the pane held by another session is held too, never accepted (" + (Show-Answer $a) + ")")
}
# EXIT 4 WITH THE STAGE "absent" IS A SHAPE NO WEZFLEET SHIPPED: the revision of #65 this messenger was
# first written against gave it, and wezfleet main (pull request 70, read at 1122461 on 2026-10-09) gives
# "refused" instead. A stage the fleet's table does not pair with its exit code is unknown, like any other
# (section E), so the table holds main's pairs and no more.
With-Fake {
    param($st)
    $msg = New-Msg
    & $fx.SetMode $st @{ post = @{ stdout = (Line -Id (N $msg.messageId) -Stage "absent" -Woken $false -Reason "stale-session" -Detail "nothing was written"); exit = 4 } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("'absent'")) ("exit 4 with the stage absent, which wezfleet main never answers, is unknown (" + (Show-Answer $a) + ")")
}
With-Fake {
    param($st)
    $a = Get-HordeMessengerStatus -Messenger $m -MessageId "0e000000-0000-4000-8000-0000000000aa"
    Check ($a.state -ceq "absent") "status exit 3, absent, is the port's absent"
}
# A REASON IS A CODE, NEVER PROSE. A wezfleet from before the reason codes (its main at c49063b) answers
# the same fields with a sentence where the code is, and no exit 4: measured 2026-10-07, a post to a
# session no live process is came back from it exit 0, queued, and was read as accepted, for ever. An
# answer whose reason is not a code is from a fleet this messenger does not read, and is unknown - for a
# post and for a status alike - so nothing is ever decided on a sentence. No reason at all is still read.
With-Fake {
    param($st)
    $msg = New-Msg
    $n = N $msg.messageId
    $old = '{"id":"' + $n + '","to":"' + $msg.sessionId + '","stage":"queued","woken":false,"reason":"no registry record for this session on this machine, so no pane can be verified; the mail waits for its next turn boundary"}' + "`n"
    & $fx.SetMode $st @{ post = @{ stdout = $old; exit = 0 } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not a code")) ("a post answered with a sentence for a reason is unknown, never accepted (" + (Show-Answer $a) + ")")
    & $fx.SetMode $st @{ post = @{ stdout = $old.Replace("no registry record for this session on this machine, so no pane can be verified; the mail waits for its next turn boundary", "no-registry-record"); exit = 0 } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted") ("CONTROL: the same answer with a code for its reason is accepted (" + (Show-Answer $a) + ")")
    & $fx.SetMode $st @{ status = @{ stdout = ('{"id":"' + $n + '","to":"","stage":"absent","reason":"no record with this id under the mail root"}' + "`n"); exit = 3 } }
    $s = Get-HordeMessengerStatus -Messenger $m -MessageId $msg.messageId
    Check ($s.state -ceq "unknown" -and "$($s.reason)".Contains("not a code")) ("a status answered with a sentence for a reason is unknown, never absent (" + (Show-Answer $s) + ")")
}
# EVERY CODE ON WEZFLEET MAIN'S CLOSED LIST IS A CODE HERE (lib/MailPost.ps1, $script:WfMailReasonCodes, at
# 1122461). The code pattern allowed letters alone, and main's "invalid-utf8" has a digit: the real
# command's refusal of a file that is not UTF-8 read as "a wezfleet from before the reason codes",
# unknown (measured 2026-10-09 by the real-contract probe against a clone of main).
foreach ($code in @("woken", "already-posted", "no-registry-record", "pane-unverified", "send-refused", "stale-session", "write-failed",
        "bad-id", "bad-to", "bad-from", "bad-file", "empty-message", "message-too-large", "invalid-utf8", "internal-error", "found", "absent")) {
    Check ($code -cmatch $script:HordeWezfleetMessengerCodePattern) ("wezfleet main's reason code '" + $code + "' is read as a code")
}
With-Fake {
    param($st)
    $msg = New-Msg
    & $fx.SetMode $st @{ post = @{ stdout = (Line -Id (N $msg.messageId) -Stage "refused" -Woken $false -Reason "invalid-utf8" -Detail "the message file is not valid UTF-8; nothing was replaced and nothing was posted"); exit = 2 } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "held" -and (Why $a).StartsWith("invalid-utf8: ")) ("a refusal with the code invalid-utf8 is held with it, not read as prose (" + (Show-Answer $a) + ")")
}

Write-Host ""
Write-Host "--- D. detail is read, never fatal; an answer about another target is not this one's ---" -ForegroundColor Cyan

# DETAIL (review of #106, G4): one line, no control character, capped. A bad detail is cut or dropped,
# and the answer it came with is kept.
$detailCases = @(
    @{ what = "a detail holding an escape sequence"; detail = ([string][char]27 + "[31mred" + [string][char]7); check = { param($w) -not ($w -cmatch '[\x00-\x1F\x7F]') -and $w.Contains("red") } },
    @{ what = "a detail of two lines"; detail = "line one`nline two"; check = { param($w) $w.Contains("line one") -and -not $w.Contains("line two") } },
    @{ what = "a detail of 5000 characters"; detail = ("d" * 5000); check = { param($w) [System.Text.Encoding]::UTF8.GetByteCount($w) -le 1024 -and $w.Contains("ddd") } },
    @{ what = "a detail that is a number"; detail = 5; check = { param($w) $w -ceq "woken" } },
    @{ what = "a detail that is null"; detail = $null; check = { param($w) $w -ceq "woken" } })
foreach ($c in $detailCases) {
    With-Fake {
        param($st)
        $msg = New-Msg
        & $fx.SetMode $st @{ post = @{ stdout = (Line -Id (N $msg.messageId) -Detail $c.detail); exit = 0 } }
        $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
        Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted" -and (& $c.check (Why $a))) ("the answer is kept, its detail cut or dropped: " + $c.what + " (" + (Show-Answer $a) + ")")
    }
}
With-Fake {
    param($st)
    $msg = New-Msg
    & $fx.SetMode $st @{ post = @{ stdout = (Line -Id (N $msg.messageId) -Drop @("detail")); exit = 0 } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted") "an answer with no detail at all is read"
}
# THE TARGET (review of #106, G7; decided 2026-10-06). A post's "to" must be the session it was asked to
# post to - except for a repost, already-posted, where it names the mailbox the record is in now, which a
# compact may have moved (wezfleet moves a mailbox only by pid and start time). A status's "to" is never
# compared: the port asks it by id alone, and the target was journaled by slice 4, which compares.
With-Fake {
    param($st)
    $msg = New-Msg
    & $fx.SetMode $st @{ post = @{ stdout = (Line -Id (N $msg.messageId) -To $other); exit = 0 } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains($other)) ("a new post answered for another session is unknown, naming it (" + $a.reason + ")")
}
With-Fake {
    param($st)
    $msg = New-Msg
    $null = Send-HordeMessengerMessage -Messenger $m -Message $msg
    & $fx.Move $st $msg.messageId $other
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted" -and (Why $a).Contains("followed to " + $other)) ("a repost of a record a compact moved is read, and says where it was followed to (" + (Show-Answer $a) + ")")
    $s = Get-HordeMessengerStatus -Messenger $m -MessageId $msg.messageId
    Check ($s.state -ceq "known" -and $s.value.stage -ceq "accepted" -and (Why $s).Contains("at " + $other)) ("a status of the moved record is read, not compared with anything, and says where it is (" + (Show-Answer $s) + ")")
}
With-Fake {
    param($st)
    $msg = New-Msg
    & $fx.SetMode $st @{ post = @{ stdout = (Line -Id (N $msg.messageId) -To "M" -Woken $false -Reason "already-posted"); exit = 0 } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "unknown") ("a repost answered with a target that is not a session UUID is unknown (" + $a.reason + ")")
    & $fx.SetMode $st @{ status = @{ stdout = (Line -Id (N $msg.messageId) -To "M" -Woken $null -Reason "found"); exit = 0 } }
    $s = Get-HordeMessengerStatus -Messenger $m -MessageId $msg.messageId
    Check ($s.state -ceq "unknown") ("a status answered with a target that is not a session UUID is unknown (" + $s.reason + ")")
    & $fx.SetMode $st @{ status = @{ stdout = (Line -Id (N $msg.messageId) -To "" -Woken $null -Reason "found"); exit = 0 } }
    $s = Get-HordeMessengerStatus -Messenger $m -MessageId $msg.messageId
    Check ($s.state -ceq "known" -and $s.value.stage -ceq "accepted") "a status with no target is read"
}

Write-Host ""
Write-Host "--- E. anything outside the table is unknown, with the reason: never a stage guessed ---" -ForegroundColor Cyan

$cases = @(
    @{ what = "a wezfleet too old to have mail post (its usage text, exit 1)"; out = { param($id) "wezfleet mail: unknown action 'post'. Use read, list, count or pump.`n" }; exit = 1; like = "exit 1" },
    @{ what = "output that is not JSON"; out = { param($id) "all good`n" }; exit = 0; like = "JSON" },
    @{ what = "two lines of JSON"; out = { param($id) (Line -Id $id) + (Line -Id $id) }; exit = 0; like = "one line" },
    @{ what = "nothing at all"; out = { param($id) "" }; exit = 0; like = "one line" },
    @{ what = "the first #65 shape, without detail and with woken missing"; out = { param($id) Line -Id $id -Woken $null -Drop @("detail") }; exit = 0; like = "without 'woken'" },
    @{ what = "a shape without to"; out = { param($id) Line -Id $id -Drop @("to") }; exit = 0; like = "without 'to'" },
    @{ what = "a shape with a field this messenger does not read"; out = { param($id) Line -Id $id -Extra @{ pane = 4 } }; exit = 0; like = "answered with 'pane'" },
    @{ what = "woken that is not true or false"; out = { param($id) Line -Id $id -Woken "yes" }; exit = 0; like = "woken that is not true or false" },
    @{ what = "a stage that is not text"; out = { param($id) Line -Id $id -Extra @{ stage = 5 } }; exit = 0; like = "stage that is not text" },
    @{ what = "more output than one answer could be"; out = { param($id) "x" * 70000 }; exit = 0; like = "65536" },
    @{ what = "a stage wezfleet does not have"; out = { param($id) Line -Id $id -Stage "delivered" }; exit = 0; like = "delivered" },
    @{ what = "an answer about another id"; out = { param($id) Line -Id "0e00000000004000800000000000ffff" }; exit = 0; like = "0e00000000004000800000000000ffff" },
    @{ what = "exit 0 with stage refused"; out = { param($id) Line -Id $id -Stage "refused" -Woken $false -Reason "bad-file" }; exit = 0; like = "refused" },
    @{ what = "exit 2 with stage queued"; out = { param($id) Line -Id $id -Woken $false }; exit = 2; like = "exit 2" },
    @{ what = "exit 4 with stage taken"; out = { param($id) Line -Id $id -Stage "taken" -Woken $false -Reason "stale-session" }; exit = 4; like = "exit 4" },
    @{ what = "a write failure, exit 1"; out = { param($id) Line -Id $id -Stage "absent" -Woken $false -Reason "write-failed" -Detail "the mail could not be written" }; exit = 1; like = "write-failed" },
    @{ what = "an internal error, exit 1 with the stage error (wezfleet main has no exit 5)"; out = { param($id) Line -Id $id -Stage "error" -Woken $false -Reason "internal-error" -Detail "unexpected error: x" }; exit = 1; like = "the fleet could not do it (stage 'error'): internal-error" },
    @{ what = "an exit 5, which wezfleet main does not have"; out = { param($id) Line -Id $id -Stage "unknown" -Woken $false -Reason "internal-error" -Detail "x" }; exit = 5; like = "not an exit code" },
    @{ what = "an exit code outside the table"; out = { param($id) Line -Id $id }; exit = 7; like = "not an exit code" })
foreach ($c in $cases) {
    With-Fake {
        param($st)
        $msg = New-Msg
        & $fx.SetMode $st @{ post = @{ stdout = (& $c.out (N $msg.messageId)); exit = $c.exit } }
        $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
        Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains($c.like)) ("unknown: " + $c.what + " (" + $a.reason + ")")
    }
}
With-Fake {
    param($st)
    & $fx.SetMode $st @{ status = @{ internal = $true } }
    $a = Get-HordeMessengerStatus -Messenger $m -MessageId "0e000000-0000-4000-8000-000000000001"
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("internal-error") -and "$($a.reason)".Contains("exit 1")) ("a status internal error, exit 1 with the stage error, is unknown (" + $a.reason + ")")
    $msg = New-Msg
    & $fx.SetMode $st @{ status = @{ stdout = (Line -Id (N $msg.messageId) -Stage "refused" -Woken $null -Reason "bad-id"); exit = 2 } }
    $a = Get-HordeMessengerStatus -Messenger $m -MessageId $msg.messageId
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("exit 2")) "a status refused as malformed, exit 2, is unknown"
    & $fx.SetMode $st @{ status = @{ stdout = (Line -Id (N $msg.messageId) -Woken $null -Reason "found"); exit = 3 } }
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
    Start-Sleep -Milliseconds 500
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("3 s") -and $took -lt 30) ("a hung command is unknown after its deadline (" + [int]$took + " s): " + $a.reason)
    # THE CHILD IS LOOKED FOR BY ITS COMMAND LINE, NOT BY A PID IT LOGGED. This check read the pid from the
    # fake's argv.log, and on a loaded machine the fake had not reached its first line within the 3 s
    # deadline: nothing was logged, and the check failed with "pid 0" although the child had been
    # stopped (measured 2026-10-06: the unmutated baseline of this suite's mutation spec failed that way,
    # so none of its mutants ran). The process exists from the moment it is started, whatever it has run,
    # and its command line names this state's folder, which no other process does.
    $self = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $PID)
    Check ($null -ne $self -and "$($self.CommandLine)" -ne "") "CONTROL: a process's command line can be read here, so finding no child below is a finding"
    $left = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object { "$($_.CommandLine)".Contains($st.dir) })
    Check ($left.Count -eq 0) ("and the child it started was stopped: no PowerShell is left running the fake in this state's folder (" + $left.Count + ")")
    # A leftover would outlive the suite for the rest of its sleep; it is this test's to stop.
    foreach ($l in $left) { Stop-Process -Id $l.ProcessId -Force -ErrorAction SilentlyContinue }
}
function Get-Grandchildren {
    # The fake's grandchildren still running, found by their command line (it names the state's folder).
    param($St)
    return @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object { "$($_.CommandLine)".Contains("fake grandchild of " + $St.dir) })
}
# THE ANSWER IS READ WHEN THE COMMAND EXITS, NOT WHEN ITS OUTPUT CLOSES (review of #106, F6). wezfleet
# starts its terminal's command-line client without redirecting it, so a client that outlives the command
# holds the command's output open. The read loop waited for that pipe to close: the answer had arrived,
# the command had exited, and the messenger still waited out its whole deadline and said "did not
# answer". Here the fake answers and exits at once while a grandchild holding its output sleeps 40 s.
With-Fake {
    param($st)
    Set-HordeWezfleetMessengerRoot -Path $st.dir -TimeoutSeconds 25
    & $fx.SetMode $st @{ post = @{ grandchildSeconds = 40 } }
    $t0 = Get-Date
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    $took = ((Get-Date) - $t0).TotalSeconds
    $held = @(Get-Grandchildren $st)
    Check ($held.Count -eq 1) ("CONTROL: the grandchild holding the command's output was still running when the answer came back (" + $held.Count + ")")
    Check ($a.state -ceq "known" -and $a.value.stage -ceq "accepted" -and $took -lt 20) ("a command that has exited is read at once, though a grandchild still holds its output (" + [int]$took + " s; " + (Show-Answer $a) + ")")
    foreach ($l in $held) { Stop-Process -Id $l.ProcessId -Force -ErrorAction SilentlyContinue }
}
# THE DEADLINE STOPS THE COMMAND'S WHOLE TREE (review of #106, F7). Process.Kill stops the child alone,
# and a grandchild it started - a hung terminal client - outlived it. Here the fake starts a grandchild
# and then hangs past the deadline.
With-Fake {
    param($st)
    Set-HordeWezfleetMessengerRoot -Path $st.dir -TimeoutSeconds 8
    & $fx.SetMode $st @{ post = @{ grandchildSeconds = 60; hangSeconds = 60 } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    Check (Test-Path -LiteralPath (Join-Path $st.dir "grandchild.pid")) "CONTROL: the fake started its grandchild before the deadline, so the check below is about a real one"
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("8 s")) ("the hung command is unknown after its deadline (" + $a.reason + ")")
    Start-Sleep -Milliseconds 500
    $left = @(Get-Grandchildren $st)
    Check ($left.Count -eq 0) ("and the grandchild the command started was stopped with it (" + $left.Count + " left)")
    foreach ($l in $left) { Stop-Process -Id $l.ProcessId -Force -ErrorAction SilentlyContinue }
    foreach ($l in @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object { "$($_.CommandLine)".Contains($st.dir) })) { Stop-Process -Id $l.ProcessId -Force -ErrorAction SilentlyContinue }
}
# A PARENT PID IS NOT A PARENT. Windows reuses pids, so a process whose parent pid is the started
# command's but that was created before the command started is a stranger, and so is everything below
# it. The process table is played here: Get-CimInstance is shadowed inside this block only.
& {
    $t = [datetime]::UtcNow.AddMinutes(-5)
    function Get-CimInstance {
        return @(
            [pscustomobject]@{ ProcessId = 200; ParentProcessId = 100; CreationDate = $t.AddSeconds(1).ToLocalTime() },
            [pscustomobject]@{ ProcessId = 300; ParentProcessId = 100; CreationDate = $t.AddSeconds(-10).ToLocalTime() },
            [pscustomobject]@{ ProcessId = 400; ParentProcessId = 200; CreationDate = $t.AddSeconds(2).ToLocalTime() },
            [pscustomobject]@{ ProcessId = 500; ParentProcessId = 300; CreationDate = $t.AddSeconds(3).ToLocalTime() },
            [pscustomobject]@{ ProcessId = 600; ParentProcessId = 400; CreationDate = $t.AddSeconds(1.5).ToLocalTime() })
    }
    $ids = @(Get-HordeWezfleetMessengerDescendants -RootId 100 -RootStart $t | ForEach-Object { $_.id } | Sort-Object)
    Check (($ids -join ",") -ceq "200,400") ("the tree is the command's children and theirs, each created after its parent; an older process under a reused pid, its children and a process older than its own parent are left out (" + ($ids -join ",") + ")")
}
# EXIT 1 IS THE FLEET'S OWN "COULD NOT", and the reason must say so, with its code and its detail: it read
# "exit 1, which is not an exit code of the fleet's post" for an answer the fleet documents (measured
# 2026-10-06), which sends a reader looking for a version mismatch. Unknown, never held: the record may
# already be on disk, and the fleet's own table says to retry under the same id.
With-Fake {
    param($st)
    & $fx.SetMode $st @{ post = @{ writeFailed = $true } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("the fleet could not do it") -and "$($a.reason)".Contains("write-failed") -and "$($a.reason)".Contains("the mail could not be written") -and -not "$($a.reason)".Contains("not an exit code")) ("exit 1 reads as the fleet's own failure, with its code and its detail (" + $a.reason + ")")
    $msg = New-Msg
    & $fx.SetMode $st @{ post = @{ stdout = (Line -Id (N $msg.messageId)); exit = 7 } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message $msg
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("not an exit code")) "CONTROL: an exit code the fleet does not have still reads as one"
}
# A PARAMETER THE HOST ITSELF REJECTS never reaches the fleet's script: nothing on stdout, the host's
# words on stderr, exit 1 (measured against wezfleet main, 2026-10-06). The reason must carry those
# words, or the cause is lost.
With-Fake {
    param($st)
    & $fx.SetMode $st @{ post = @{ stdout = ""; stderr = "wezfleet.ps1 : Missing an argument for parameter MessageFile.`n"; exit = 1 } }
    $a = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    Check ($a.state -ceq "unknown" -and "$($a.reason)".Contains("exit 1") -and "$($a.reason)".Contains("Missing an argument for parameter MessageFile")) ("nothing on stdout and the host's words on stderr is unknown, carrying those words (" + $a.reason + ")")
}

Write-Host ""
Write-Host "--- F. the body files: a folder only this user can open, emptied after each post and swept at start ---" -ForegroundColor Cyan

$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
function Test-UserOnly {
    # Is the folder's access list protected from inheritance, with one rule: full control for this user?
    param([string]$Path)
    $acl = Get-Acl -LiteralPath $Path
    $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    return ($acl.AreAccessRulesProtected -and $rules.Count -eq 1 -and $rules[0].IdentityReference.Value -ceq $me.Value -and
        $rules[0].AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and
        ($rules[0].FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) -eq [System.Security.AccessControl.FileSystemRights]::FullControl)
}
With-Fake {
    param($st)
    $out = Join-Path $st.home "messengers\wezfleet\outgoing"
    $msg = New-Msg
    $null = Send-HordeMessengerMessage -Messenger $m -Message $msg
    $argv = @(@(& $fx.Runs $st)[0].argv)
    $file = "$($argv[[array]::IndexOf($argv, '-MessageFile') + 1])"
    Check ((Split-Path -Parent $file) -ieq $out) ("the body file was written in Horde's own folder, under HORDE_HOME (" + $file + ")")
    Check (Test-UserOnly $out) "that folder's access list, read back, is protected and grants full control to this user alone"
    Check (@(Get-ChildItem -LiteralPath $out -Force).Count -eq 0) "and it is empty after the post"
}
With-Fake {
    param($st)
    # A folder someone else made, inheriting its parent's access list, is put right before a body is written.
    $out = Join-Path $st.home "messengers\wezfleet\outgoing"
    [void](New-Item -ItemType Directory -Force -Path $out)
    Check (-not (Test-UserOnly $out)) "CONTROL: a folder made by New-Item inherits a wider access list"
    $null = Send-HordeMessengerMessage -Messenger $m -Message (New-Msg)
    Check (Test-UserOnly $out) "after a post, the folder's access list is this user's alone"
    # SWEPT AT START: a node killed in the middle of a post leaves its body file behind.
    foreach ($n in 1..2) { [System.IO.File]::WriteAllText((Join-Path $out ([guid]::NewGuid().ToString("N") + ".txt")), "a body a killed node left behind") }
    $swept = Clear-HordeWezfleetMessengerOutgoing
    Check ($swept -eq 2 -and @(Get-ChildItem -LiteralPath $out -Force).Count -eq 0) ("the start sweep removes every body file left behind (" + $swept + ")")
    Check ((Clear-HordeWezfleetMessengerOutgoing) -eq 0) "and a sweep with nothing to do removes nothing"
}

# THE ACCESS-LIST CHECK ON BOTH SHELLS (T-0338). The folder's list used to be read with the static
# [System.IO.Directory]::GetAccessControl, which PowerShell 7 does not have, so a tell posted from a pwsh 7
# process threw before sending. The check is Test-HordeWezfleetMessengerUserOnly itself, called here in
# whichever shell runs this suite (this suite is in the targeted set on 5.1 and on 7), and it must refuse
# every folder that is not this user's alone - protected, one rule, this user's, allow, full control.
# The cases are set up with the messenger's own two helpers, not Set-Acl, which asks for the SACL privilege a normal user lacks.
With-Fake {
    param($st)
    $out = Join-Path $st.home "messengers\wezfleet\outgoing"
    [void](New-Item -ItemType Directory -Force -Path $out)
    Check (-not (Test-HordeWezfleetMessengerUserOnly -Path $out)) ("[" + $PSVersionTable.PSEdition + "] the check REFUSES a folder that inherits a wider access list")
    $got = Get-HordeWezfleetMessengerOutgoing
    Check ($got -ieq $out -and (Test-HordeWezfleetMessengerUserOnly -Path $out) -and (Test-UserOnly $out)) ("[" + $PSVersionTable.PSEdition + "] the folder is made this user's alone, and the check, read the other way, agrees")
    # A second rule, even an allow for the Users group, is a folder others can open: refused, then put right.
    $a = Get-HordeWezfleetMessengerFolderAcl -Path $out
    $a.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule((New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")), [System.Security.AccessControl.FileSystemRights]::ReadAndExecute, [System.Security.AccessControl.InheritanceFlags]::ContainerInherit, [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow)))
    Set-HordeWezfleetMessengerFolderAcl -Path $out -Acl $a
    Check (-not (Test-UserOnly $out)) "CONTROL: the folder now admits a second rule, by the other reader"
    Check (-not (Test-HordeWezfleetMessengerUserOnly -Path $out)) ("[" + $PSVersionTable.PSEdition + "] the check REFUSES a folder with a second rule on it")
    $null = Get-HordeWezfleetMessengerOutgoing
    Check ((Test-HordeWezfleetMessengerUserOnly -Path $out) -and (Test-UserOnly $out)) ("[" + $PSVersionTable.PSEdition + "] and the folder is put right, not left wide")
    # Unprotected (inheriting) is refused even though this user's own rule is still on it: protection is part of the check.
    $a = Get-HordeWezfleetMessengerFolderAcl -Path $out
    $a.SetAccessRuleProtection($false, $true)
    Set-HordeWezfleetMessengerFolderAcl -Path $out -Acl $a
    Check (-not (Test-HordeWezfleetMessengerUserOnly -Path $out)) ("[" + $PSVersionTable.PSEdition + "] the check REFUSES a folder whose list is not protected from inheritance")
    # A list that cannot be read is an error, never a pass.
    $threw = $false
    try { $null = Test-HordeWezfleetMessengerUserOnly -Path (Join-Path $st.home "no\such\folder") } catch { $threw = $true }
    Check $threw ("[" + $PSVersionTable.PSEdition + "] a folder whose list cannot be read is an error, not a pass")
}

Exit-HordeTestPinnedHome -State $pinned
Complete-HordeSuite -Success "the wezfleet messenger starts only the fixed PowerShell on a real local wezfleet checkout, hands the body only through a file only this user can open, and reads nothing it was not told"
