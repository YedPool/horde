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
#   Observe  param($State, $MessageId) -> { records; typed; wakes } - how many records the messenger
#            holds for that id, how many times any body was typed anywhere, how many wakes it made
#   Receive  param($State, $MessageId) - plays the RECEIVING session's side (its hook confirming the id
#            in its own transcript), by the messenger's own receiving mechanism, never by the port
# A fixture writes nothing outside the temp folder, touches no pane and no real session's mail.

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
        body = ("conformance body " + [guid]::NewGuid().ToString("N"))
        ttlSeconds = 3600
    }
}

# Every capability of the closed list must have a case here. Each case gets the messenger, its
# fixture and a fresh state, and returns $true when the capability was shown.
$cases = [ordered]@{
    "body.untyped" = {
        param($M, $Fx, $State)
        $msg = New-Msg
        $a = Send-HordeMessengerMessage -Messenger $M -Message $msg
        $o = & $Fx.Observe $State $msg.messageId
        return ($a.state -ceq "known" -and $o.records -eq 1 -and $o.typed -eq 0)
    }
    "idempotent.post" = {
        param($M, $Fx, $State)
        $msg = New-Msg
        $a1 = Send-HordeMessengerMessage -Messenger $M -Message $msg
        $a2 = Send-HordeMessengerMessage -Messenger $M -Message $msg
        $o = & $Fx.Observe $State $msg.messageId
        return ($a1.state -ceq "known" -and $a2.state -ceq "known" -and "$($a2.value.stage)" -ceq "$($a1.value.stage)" -and $o.records -eq 1)
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
        return ($o.wakes -ge 1 -and $o.typed -eq 0)
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
        Check ($a.state -ceq "unknown" -and $o.records -eq 0) ("[" + $name + "] an invalid message never reaches it")
    } finally { & $fx.Remove $state }
}

Complete-HordeSuite -Success "every messenger shows each capability it claims and is refused where it lacks one"
