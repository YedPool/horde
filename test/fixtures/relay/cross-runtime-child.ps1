# The other runtime's half of test/test-relay-cross-runtime.ps1: seal an envelope, or open one, with
# test keys the suite made and wrote to its own temporary folder. Not a suite; run only by that suite.
#   cross-runtime-child.ps1 -Work <folder> -Mode seal|open
# seal: writes <Work>\from-child.txt, the envelope of the body in <Work>\body.txt.
# open: reads <Work>\from-parent.txt and writes <Work>\opened.txt: "OK <hex of body> <backend>" or
#       "REFUSED <reason>".
param([Parameter(Mandatory = $true)][string]$Work, [Parameter(Mandatory = $true)][string]$Mode)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))
. (Join-Path $root "relay\Envelope.ps1")
. (Join-Path $root "core\Tristate.ps1")

$k = [System.IO.File]::ReadAllText((Join-Path $Work "keys.json")) | ConvertFrom-Json
$signer = ConvertFrom-HordeRelayP256Private -D (ConvertFrom-HordeRelayHex -Text $k.signD) -Public (ConvertFrom-HordeRelayHex -Text $k.signPub) -Use "ecdsa"
$agree = ConvertFrom-HordeRelayP256Private -D (ConvertFrom-HordeRelayHex -Text $k.agreeD) -Public (ConvertFrom-HordeRelayHex -Text $k.agreePub) -Use "ecdh"
$signPub = ConvertFrom-HordeRelayHex -Text $k.signPub
$agreePub = ConvertFrom-HordeRelayHex -Text $k.agreePub
$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false

if ($Mode -ceq "seal") {
    $body = [System.IO.File]::ReadAllBytes((Join-Path $Work "body.txt"))
    $text = New-HordeRelayEnvelope -Kind "snapshot" -Channel "decisions" -Seq 9 -Body $body -Recipients @(, $agreePub) -Signer $signer
    [System.IO.File]::WriteAllText((Join-Path $Work "from-child.txt"), $text, $utf8)
    [System.IO.File]::WriteAllText((Join-Path $Work "sealed-with.txt"), (Get-HordeRelayAeadBackend), $utf8)
    exit 0
}
if ($Mode -ceq "open") {
    $text = [System.IO.File]::ReadAllText((Join-Path $Work "from-parent.txt"), $utf8)
    $out = Join-Path $Work "opened.txt"
    $r = Read-HordeRelayEnvelope -Text $text
    if (-not $r.ok) { [System.IO.File]::WriteAllText($out, "REFUSED " + $r.reason, $utf8); exit 0 }
    $senders = @{ (Get-HordeRelayKeyId -Public $signPub) = (New-HordeRelaySender -Public $signPub -Proof "es256") }
    $t = Test-HordeRelayEnvelope -Envelope $r.value -Senders $senders
    if (-not $t.ok) { [System.IO.File]::WriteAllText($out, "REFUSED " + $t.reason, $utf8); exit 0 }
    $fresh = New-HordeKnown -Value ([pscustomobject]@{ key = (Get-HordeRelayReplayKey -Header $t.value.header); fresh = $true })
    $u = Unprotect-HordeRelayEnvelope -Envelope $r.value -Senders $senders -RecipientKeys @{ (Get-HordeRelayKeyId -Public $agreePub) = $agree } -Replay $fresh -Channel "decisions" -Kind "snapshot"
    if (-not $u.ok) { [System.IO.File]::WriteAllText($out, "REFUSED " + $u.reason, $utf8); exit 0 }
    [System.IO.File]::WriteAllText($out, "OK " + (ConvertTo-HordeRelayHex -Bytes $u.value) + " " + (Get-HordeRelayAeadBackend), $utf8)
    exit 0
}
throw ("no such mode: " + $Mode)
