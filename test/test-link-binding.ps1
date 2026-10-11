# IS A LINK THAT DIALLED IN THROUGH THE LISTENER BOUND TO THE DEVICE ITS KEY WAS ENROLLED FOR?
#
# Remote plan R17a (coordinator's decision of 2026-10-07; PR #97's F5 for links that dial in).
# remote/LinkBinding.ps1 is the rule, pure: attach writes one preamble line naming the device from its
# own argv, the hub reads it, and a hello that claims another device is refused. The live half - that
# the preamble comes from the forced command's -Device and never from stdin - is in the
# listener's own live suite, beside its transport.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "remote\LinkBinding.ps1")

$dev = "0f1e2d3c-4b5a-4968-8776-655443322110"
$other = "11111111-2222-4333-8444-555555555555"
function Hello { param($Id) return [pscustomobject]@{ v = 1; kind = "hello"; hello = [pscustomobject]@{ id = $Id; name = "box"; protocols = @(1) } } }
function Has { param([string]$Text, [string]$Part) return ("$Text".Contains($Part)) }

Write-Host ""
Write-Host "--- the preamble: one line, made only from a device id ---" -ForegroundColor Cyan
$p = New-HordeAttachPreamble -DeviceId $dev
Check ($p.ok -and $p.line -ceq ("horde-attach 1 " + $dev)) "a device id becomes the line 'horde-attach 1 <id>'"
Check (-not $p.line.Contains("`n") -and -not $p.line.Contains("`r")) "the line carries no line break of its own: the sender adds the LF"
foreach ($bad in @("", "0F1E2D3C-4B5A-4968-8776-655443322110", ($dev + "`n"), ($dev + " x"), "..\x", "*", ($dev.Substring(1)))) {
    $p = New-HordeAttachPreamble -DeviceId $bad
    Check (-not $p.ok -and $p.line -ceq "" -and (Has $p.reason "not a device id")) ("refused before a byte is sent: '" + ($bad -replace "`n", "\n") + "'")
}

Write-Host ""
Write-Host "--- the hub reads it back, and nothing else ---" -ForegroundColor Cyan
$r = Read-HordeAttachPreamble -Line ("horde-attach 1 " + $dev)
Check ($r.state -ceq "known" -and $r.value -ceq $dev) "the preamble binds the link to its device"
$r = Read-HordeAttachPreamble -Line (New-HordeAttachPreamble -DeviceId $other).line
Check ($r.state -ceq "known" -and $r.value -ceq $other) "what the writer makes, the reader reads (round trip)"
$r = Read-HordeAttachPreamble -Line '{"v":1,"kind":"hello","hello":{"id":"x"}}'
Check ($r.state -ceq "unknown" -and (Has $r.reason "did not open with an attach preamble")) "a frame first is not a preamble: the link is bound to nothing"
$r = Read-HordeAttachPreamble -Line ("horde-attach 2 " + $dev)
Check ($r.state -ceq "unknown" -and (Has $r.reason "version '2'")) "another preamble version is refused, not guessed at"
foreach ($bad in @(("horde-attach 1 " + $dev.ToUpperInvariant()), ("horde-attach 1 " + $dev + " extra"), ("horde-attach  1 " + $dev), ("Horde-attach 1 " + $dev), "horde-attach 1", "", ("horde-attach 1 " + $dev + "`r"))) {
    $r = Read-HordeAttachPreamble -Line $bad
    Check ($r.state -ceq "unknown") ("an ill-formed preamble binds nothing: '" + ($bad -replace "`r", "\r") + "'")
}

Write-Host ""
Write-Host "--- a hello on a bound link must name the bound device (F5) ---" -ForegroundColor Cyan
Check (@(Test-HordeHelloBinding -Frame (Hello $dev) -BoundDeviceId $dev).Count -eq 0) "CONTROL: a hello from the bound device stands"
$f = @(Test-HordeHelloBinding -Frame (Hello $other) -BoundDeviceId $dev)
Check ($f.Count -eq 1 -and (Has $f[0] ("claims device '" + $other + "'")) -and (Has $f[0] ("enrolled for device " + $dev))) "a forged hello, claiming another enrolled device, is refused and both devices are named"
$f = @(Test-HordeHelloBinding -Frame (Hello $dev.ToUpperInvariant()) -BoundDeviceId $dev)
Check ($f.Count -eq 1) "the comparison is exact: the same id in capitals is another claim"
$f = @(Test-HordeHelloBinding -Frame (Hello "") -BoundDeviceId $dev)
Check ($f.Count -eq 1) "a hello with no id is refused"
$f = @(Test-HordeHelloBinding -Frame ([pscustomobject]@{ v = 1; kind = "req" }) -BoundDeviceId $dev)
Check ($f.Count -eq 1 -and (Has $f[0] "not a hello")) "a frame that is not a hello is not passed as one"
$f = @(Test-HordeHelloBinding -Frame (Hello $dev) -BoundDeviceId "")
Check ($f.Count -eq 1 -and (Has $f[0] "bound to no device")) "on a link bound to no device, even a matching hello is refused"

Complete-HordeSuite -Success "a dialled-in link is bound to the device its forced command names, and a hello claiming another is refused"
