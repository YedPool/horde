# DOES AN ENVELOPE SEALED UNDER ONE POWERSHELL RUNTIME OPEN UNDER THE OTHER, BOTH WAYS?
#
# Horde is to run under Windows PowerShell 5.1 and PowerShell 7 (direction of 2026-10-09), and the
# relay's one runtime difference is the AES-GCM backend (relay/Backend.ps1: cng under 5.1, dotnet under
# 7). A machine on one and a machine on the other must read each other's envelopes byte for byte. This
# suite runs in either runtime, starts the OTHER one on test/fixtures/relay/cross-runtime-child.ps1,
# and crosses an envelope each way, with exportable test keys it writes to a folder of its own under
# %TEMP% and deletes after.
#
# THE OTHER RUNTIME MAY BE MISSING (PowerShell 7 is not on every box). Then the suite says so and exits
# 3, a partial run (test/lib/Suite.ps1), never 0.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relay\Envelope.ps1")
. (Join-Path $root "core\Tristate.ps1")
Set-StrictMode -Version Latest

$desktop = ($PSVersionTable.PSEdition -ceq "Desktop")
$otherName = $(if ($desktop) { "pwsh" } else { "powershell" })
$other = Get-Command -Name $otherName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
Write-Host ("  this runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + "), backend " + (Get-HordeRelayAeadBackend)) -ForegroundColor DarkGray
if ($null -eq $other) {
    Write-Host ("  [SKIP] the other runtime (" + $otherName + ") is not installed here, so nothing can be crossed") -ForegroundColor Yellow
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "skipped: only one PowerShell runtime here" -PassCode 3
}
Write-Host ("  other runtime: " + $other.Source) -ForegroundColor DarkGray

function Invoke-Child {
    # Run the child under the other runtime; its exit code. Streams read through the process API, never
    # 2>&1 (CONTRIBUTING 12).
    param([string]$Work, [string]$Mode)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $other.Source
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $here "fixtures\relay\cross-runtime-child.ps1") + "`" -Work `"" + $Work + "`" -Mode " + $Mode
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    if (-not $p.WaitForExit(120000)) { $p.Kill(); throw "the child did not finish in 120 s" }
    $err = $errTask.Result
    if ($p.ExitCode -ne 0) { Write-Host ("    child said: " + $out + " " + $err) -ForegroundColor Yellow }
    return $p.ExitCode
}

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$work = Join-Path $env:TEMP ("horde-relay-cross-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $signer = New-HordeRelayP256Key -Use "ecdsa"
    $agree = New-HordeRelayP256Key -Use "ecdh"
    $sp = $signer.ExportParameters($true); $ap = $agree.ExportParameters($true)
    $signPub = ConvertTo-HordeRelayP256Public -Key $signer
    $agreePub = ConvertTo-HordeRelayP256Public -Key $agree
    $keysJson = '{"signD":"' + (ConvertTo-HordeRelayHex -Bytes $sp.D) + '","signPub":"' + (ConvertTo-HordeRelayHex -Bytes $signPub) + '","agreeD":"' + (ConvertTo-HordeRelayHex -Bytes $ap.D) + '","agreePub":"' + (ConvertTo-HordeRelayHex -Bytes $agreePub) + '"}'
    [System.IO.File]::WriteAllText((Join-Path $work "keys.json"), $keysJson, $utf8)
    $bodyText = "crossed runtimes " + [string][char]0x05e9 + [string][char]0x05dc + [string][char]0x05d5 + [string][char]0x05dd
    $body = $utf8.GetBytes($bodyText)

    Write-Host ""
    Write-Host "--- sealed here, opened there ---" -ForegroundColor Cyan
    $text = New-HordeRelayEnvelope -Kind "snapshot" -Channel "decisions" -Seq 8 -Body $body -Recipients @(, $agreePub) -Signer $signer
    [System.IO.File]::WriteAllText((Join-Path $work "from-parent.txt"), $text, $utf8)
    $code = Invoke-Child -Work $work -Mode "open"
    $opened = $(if (Test-Path -LiteralPath (Join-Path $work "opened.txt")) { [System.IO.File]::ReadAllText((Join-Path $work "opened.txt"), $utf8) } else { "" })
    Check ($code -eq 0 -and $opened.StartsWith("OK " + (ConvertTo-HordeRelayHex -Bytes $body) + " ")) ("sealed on " + (Get-HordeRelayAeadBackend) + " here, opened by the other runtime (" + $opened.Split(" ")[-1] + "): " + $(if ($opened.StartsWith("OK")) { "same bytes" } else { $opened }))
    $tampered = $text.Replace('"seq":8', '"seq":9')
    Check ($tampered -cne $text) "CONTROL: the tampered copy differs"
    [System.IO.File]::WriteAllText((Join-Path $work "from-parent.txt"), $tampered, $utf8)
    [void](Invoke-Child -Work $work -Mode "open")
    $opened = [System.IO.File]::ReadAllText((Join-Path $work "opened.txt"), $utf8)
    Check ($opened.StartsWith("REFUSED ") -and $opened.Contains("does not verify")) ("and a changed copy is refused there too (" + $opened + ")")

    Write-Host ""
    Write-Host "--- sealed there, opened here ---" -ForegroundColor Cyan
    [System.IO.File]::WriteAllBytes((Join-Path $work "body.txt"), $body)
    $code = Invoke-Child -Work $work -Mode "seal"
    Check ($code -eq 0 -and (Test-Path -LiteralPath (Join-Path $work "from-child.txt"))) "the other runtime sealed an envelope"
    $theirs = [System.IO.File]::ReadAllText((Join-Path $work "from-child.txt"), $utf8)
    $theirBackend = [System.IO.File]::ReadAllText((Join-Path $work "sealed-with.txt"), $utf8)
    $r = Read-HordeRelayEnvelope -Text $theirs
    Check ($r.ok) ("its text reads here as canonical version 1 (" + $r.reason + ")")
    $t = Test-HordeRelayEnvelope -Envelope $r.value -Senders @{ (Get-HordeRelayKeyId -Public $signPub) = (New-HordeRelaySender -Public $signPub -Proof "es256") }
    Check ($t.ok) ("its signature verifies here (" + $t.reason + ")")
    $u = Unprotect-HordeRelayEnvelope -Verified $t.value -RecipientKeys @{ (Get-HordeRelayKeyId -Public $agreePub) = $agree } -Replay (New-HordeKnown -Value ([pscustomobject]@{ key = (Get-HordeRelayReplayKey -Header $t.value.header); fresh = $true }))
    Check ($u.ok -and $utf8.GetString($u.value) -ceq $bodyText) ("sealed on " + $theirBackend + " there, opened on " + (Get-HordeRelayAeadBackend) + " here, non-ASCII intact")
    Check ($theirBackend -cne (Get-HordeRelayAeadBackend)) ("the two sides used different AES-GCM backends (" + $theirBackend + " and " + (Get-HordeRelayAeadBackend) + "), so the crossing tested the seam")
} finally {
    if ((Split-Path -Leaf $work) -match '^horde-relay-cross-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "the folder with the test keys is gone"

Complete-HordeSuite -Success "an envelope crosses between Windows PowerShell 5.1 and PowerShell 7 both ways, and a changed one is refused on the other side"
