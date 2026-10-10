# DOES EVERY MESSENGER DO WHAT ITS capabilities.json SAYS, AND NOTHING IT DOES NOT?
#
# Remote plan step R21, slice 3. Generated from each messenger's capabilities.json, as the transport
# conformance suite is from each transport's (plan step R4): this suite names no messenger. It loads
# every messengers/<name>/Messenger.ps1 and that messenger's test fixture, and for each capability:
#   - a "yes" must be DEMONSTRATED by the case below, or the suite fails;
#   - any other word must be refused where it is required: the node's production path
#     (Resolve-HordeNodeMessenger) for body.untyped, idempotent.post and receipt.receiver, and a caller
#     that asks for it by name for wake.
# A capability added to the closed list with no case here fails the suite, so the list and the cases
# cannot drift apart.
#
# THE FIXTURE. messengers/<name>/test/Fixture.ps1, run with -Root, returns one object of script blocks:
#   New      ()                      -> a state, everything the messenger writes kept inside it
#   Remove   param($State)
#   Observe  param($State, $MessageId) -> { records; bodies; typed; wakes }, READ FROM WHAT THE MESSENGER
#            ACTUALLY DID, never from the messenger's own report (review of #102, finding 1; plan R21
#            slice 3b, merge condition 1): records, how many records the target store holds for that id;
#            bodies, the body each of them holds; typed, every text typed into any session during the
#            state's life, as the fake target recorded it; wakes, how many wake notices for that id the
#            fake target recorded.
#   Receive  param($State, $MessageId) - plays the RECEIVING session's side (its hook confirming the id
#            in its own transcript), by the messenger's own receiving mechanism, never by the port
# A fixture writes nothing outside the temp folder, touches no pane and no real session's mail.
#
# WHAT A TYPED TEXT MAY BE. Only a wake notice is ever typed: one line, no control character, and never
# any part of the body. Each case below holds every typed text to that, so a messenger that typed the
# body, or a notice carrying it, fails whichever case was running.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "messengers\Port.ps1")
foreach ($f in @(Get-HordeMessengerFiles)) { . $f }

$script:seq = 0
function New-Msg {
    # A fresh valid message: every case uses its own id, so no case can see another's record.
    param([string]$SessionId = "22222222-3333-4444-8555-666666666666")
    $script:seq++
    return [pscustomobject]@{
        messageId = ("0e000000-0000-4000-8000-" + $script:seq.ToString("000000000000"))
        sessionId = $SessionId
        label = "A"
        from = [pscustomobject]@{ deviceId = "0f000000-0000-4000-8000-000000000001"; sessionId = "33333333-4444-4555-8666-777777777777"; label = "M" }
        # Two lines and a non-ASCII letter: a body cut at a newline, or read in the wrong encoding, would
        # not arrive as itself (wezfleet's cmd.exe shim measured cutting at the first newline, 2026-09-16).
        body = ("conformance body " + [guid]::NewGuid().ToString("N") + "`nsecond line caf" + [char]0x00E9)
        ttlSeconds = 3600
    }
}

function Test-TypedClean {
    # Every typed text is a wake notice: one line, no control character, and none of the body - checked
    # against each line of the body, so a notice that carried its first line is caught too.
    param($Observed, [string]$Body)
    foreach ($t in @($Observed.typed)) {
        if ("$t" -cmatch '[\x00-\x1F\x7F]') { return $false }
        foreach ($line in @($Body -split "`n" | Where-Object { $_.Trim() -ne "" })) { if ("$t".Contains($line.Trim())) { return $false } }
    }
    return $true
}

# Every capability of the closed list must have a case here. Each case gets the messenger, its
# fixture and a fresh state, and returns $true when the capability was shown.
$cases = [ordered]@{
    "body.untyped" = {
        param($M, $Fx, $State)
        $msg = New-Msg
        $a = Send-HordeMessengerMessage -Messenger $M -Message $msg
        $o = & $Fx.Observe $State $msg.messageId
        # THE BODY ARRIVED AS ITSELF, and was never typed.
        return ($a.state -ceq "known" -and $o.records -eq 1 -and @($o.bodies).Count -eq 1 -and "$(@($o.bodies)[0])" -ceq $msg.body -and (Test-TypedClean $o $msg.body))
    }
    "idempotent.post" = {
        param($M, $Fx, $State)
        $msg = New-Msg
        $a1 = Send-HordeMessengerMessage -Messenger $M -Message $msg
        $o1 = & $Fx.Observe $State $msg.messageId
        $a2 = Send-HordeMessengerMessage -Messenger $M -Message $msg
        $o2 = & $Fx.Observe $State $msg.messageId
        # A REPOST WRITES NOTHING AND WAKES NOTHING.
        $first = ($a1.state -ceq "known" -and $a2.state -ceq "known" -and "$($a2.value.stage)" -ceq "$($a1.value.stage)" -and $o2.records -eq 1 -and $o2.wakes -eq $o1.wakes -and @($o2.typed).Count -eq @($o1.typed).Count)
        # AND NEVER RESETS A STAGE: after the receiver took it, a repost answers with the later stage.
        & $Fx.Receive $State $msg.messageId
        $a3 = Send-HordeMessengerMessage -Messenger $M -Message $msg
        $o3 = & $Fx.Observe $State $msg.messageId
        $after = Get-HordeMessengerStatus -Messenger $M -MessageId $msg.messageId
        return ($first -and $a3.state -ceq "known" -and "$($a3.value.stage)" -ceq "seen" -and $after.state -ceq "known" -and "$($after.value.stage)" -ceq "seen" -and $o3.records -eq 1 -and $o3.wakes -eq $o1.wakes -and (Test-TypedClean $o3 $msg.body))
    }
    "receipt.receiver" = {
        param($M, $Fx, $State)
        $msg = New-Msg
        $null = Send-HordeMessengerMessage -Messenger $M -Message $msg
        $before = Get-HordeMessengerStatus -Messenger $M -MessageId $msg.messageId
        # NOT SEEN UNTIL THE RECEIVER SAYS SO: a messenger that reported seen on its own word would pass
        # a check that only looked after the receiver ran.
        $notYet = ($before.state -ceq "known" -and "$($before.value.stage)" -cne "seen")
        & $Fx.Receive $State $msg.messageId
        $after = Get-HordeMessengerStatus -Messenger $M -MessageId $msg.messageId
        return ($notYet -and $after.state -ceq "known" -and "$($after.value.stage)" -ceq "seen")
    }
    "wake" = {
        param($M, $Fx, $State)
        $msg = New-Msg
        $null = Send-HordeMessengerMessage -Messenger $M -Message $msg
        $o = & $Fx.Observe $State $msg.messageId
        # One wake, as the fake target recorded it: one line, no control character, never the body.
        return ($o.wakes -eq 1 -and @($o.typed).Count -ge 1 -and (Test-TypedClean $o $msg.body))
    }
}
# What requires each capability, for the honest refusal of any word but yes.
$nodeRequires = @("body.untyped", "idempotent.post", "receipt.receiver")

Write-Host ""
Write-Host "--- the cases cover the closed list of capabilities, no more and no less ---" -ForegroundColor Cyan
$listed = @(Get-HordeMessengerCapabilityNames)
Check ((@($listed | Sort-Object) -join ",") -ceq (@($cases.Keys | Sort-Object) -join ",")) ("every capability has a case here, and every case a capability (" + ($listed -join ", ") + ")")
Check (@(Get-HordeMessengerNames).Count -ge 1) ("at least one messenger is loaded (" + (@(Get-HordeMessengerNames) -join ", ") + ")")

foreach ($name in @(Get-HordeMessengerNames)) {
    $m = Get-HordeMessenger -Name $name
    Write-Host ""
    Write-Host ("--- messenger " + $name + " ---") -ForegroundColor Cyan
    $fxPath = Join-Path $m.folder "test\Fixture.ps1"
    Check (Test-Path -LiteralPath $fxPath -PathType Leaf) ("[" + $name + "] has a test fixture at test\Fixture.ps1")
    if (-not (Test-Path -LiteralPath $fxPath -PathType Leaf)) { continue }
    $fx = & $fxPath -Root $root
    foreach ($cap in $listed) {
        $support = Get-HordeMessengerSupport -Messenger $m -Capability $cap
        $state = & $fx.New
        try {
            if ($support -ceq "yes") {
                $shown = & $cases[$cap] $m $fx $state
                Check ($shown -eq $true) ("[" + $name + "] " + $cap + " is yes, and the case shows it")
            } elseif ($nodeRequires -ccontains $cap) {
                $r = Resolve-HordeNodeMessenger -Name $name
                Check ($r.state -ceq "unknown" -and "$($r.reason)".Contains($cap)) ("[" + $name + "] " + $cap + " is " + $support + ", and the node's path refuses it, naming it")
            } else {
                $r = Resolve-HordeMessenger -Name $name -Require @($cap)
                Check ($r.state -ceq "unknown" -and "$($r.reason)".Contains($cap)) ("[" + $name + "] " + $cap + " is " + $support + ", and a caller that requires it is refused")
            }
        } finally { & $fx.Remove $state }
    }
    # Two rules for every messenger, whatever it declares.
    $state = & $fx.New
    try {
        $never = New-Msg
        $a = Get-HordeMessengerStatus -Messenger $m -MessageId $never.messageId
        Check ($a.state -ceq "absent") ("[" + $name + "] a message it never took is absent, not unknown and not a stage")
        $bad = New-Msg
        $bad.body = " "
        $a = Send-HordeMessengerMessage -Messenger $m -Message $bad
        $o = & $fx.Observe $state $bad.messageId
        Check ($a.state -ceq "unknown" -and $o.records -eq 0 -and $o.wakes -eq 0) ("[" + $name + "] an invalid message never reaches it, and wakes nothing")
    } finally { & $fx.Remove $state }
}

Complete-HordeSuite -Success "every messenger shows each capability it claims and is refused where it lacks one"
