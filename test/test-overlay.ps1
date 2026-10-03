# DOES HORDE TAKE FROM THE OVERLAY ONLY AN ADDRESS AND AN ADVISORY HEALTH, AND NEVER GUESS?
#
# Remote plan step R8 (planning/execution-plan-remote.md). The overlay is a separate repository; its one
# contract with Horde is `horde-overlay endpoint --name <name> --json`, whose output Horde validates
# against schema/overlay-endpoint.v1, a schema Horde owns. Two files:
#   - core/OverlayCommand.ps1 runs that one command line - never a shell line, never another verb - and
#     answers with its output as text, or unknown with the reason (missing, failed, silent, too large);
#   - remote/Overlay.ps1, pure and scanned by tools/ExecScan.ps1, reads a hub address, validates the
#     output, picks a peer's address, and folds the overlay's health into a link answer as advice only.
# Output that fails the schema is unknown, never a guessed address. Horde never starts, stops or
# configures a tunnel: the only verb it sends is `endpoint`.
#
# Every fake overlay is a .cmd file in a folder this suite makes under %TEMP%, put first on PATH for the
# run and removed after. The real PATH is restored in finally.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "remote\Overlay.ps1")
. (Join-Path $root "core\OverlayCommand.ps1")

$golden = [System.IO.File]::ReadAllText((Join-Path $root "test\fixtures\link\overlay.json"))
function IsKnown { param($A, $V) return ($A.state -ceq "known" -and $A.value -eq $V) }

Write-Host ""
Write-Host "--- loading the modules ---" -ForegroundColor Cyan
$strictKept = & { Set-StrictMode -Version Latest; . (Join-Path $root "remote\Overlay.ps1"); . (Join-Path $root "core\OverlayCommand.ps1"); try { $null = $hordeNeverAssignedVariable; $false } catch { $true } }
Check ($strictKept -eq $true) "dot-sourcing remote/Overlay and core/OverlayCommand leaves the caller's strict mode on"
. (Join-Path $root "tools\ExecScan.ps1")
$scan = @(Get-HordeExecFindings -Path (Join-Path $root "remote\Overlay.ps1") -Known (Get-HordeExecFunctionNames -Roots @(Join-Path $root "remote")))
Check ($scan.Count -eq 0) ("remote/Overlay.ps1 passes the exec scan: it starts nothing (" + ($scan -join "; ") + ")")

Write-Host ""
Write-Host "--- a hub address is an address or an overlay name, nothing else ---" -ForegroundColor Cyan
$h = ConvertFrom-HordeHubAddress -Address "overlay:home"
Check ($h.state -ceq "known" -and "$($h.value.kind)" -ceq "overlay" -and "$($h.value.name)" -ceq "home" -and "$($h.value.peer)" -ceq "hub") "overlay:<name> names an overlay to ask, and its peer named hub"
$h = ConvertFrom-HordeHubAddress -Address "overlay:home/server"
Check ($h.state -ceq "known" -and "$($h.value.name)" -ceq "home" -and "$($h.value.peer)" -ceq "server") "overlay:<name>/<peer> names which of its peers is the hub"
Check ((ConvertFrom-HordeHubAddress -Address "overlay:home/").state -ceq "unknown") "an empty peer name is unknown"
Check ((ConvertFrom-HordeHubAddress -Address "100.64.0.2`n").state -ceq "unknown") "an address with a trailing newline is not an address: the pattern ends at the end of the text"
Check ((ConvertFrom-HordeHubAddress -Address "overlay:home`n").state -ceq "unknown") "an overlay name with a trailing newline is not a name"
Check ((ConvertFrom-HordeHubAddress -Address "OVERLAY:home").state -ceq "unknown") "the overlay: prefix is matched exactly"
$h = ConvertFrom-HordeHubAddress -Address "100.64.0.2"
Check ($h.state -ceq "known" -and "$($h.value.kind)" -ceq "address" -and "$($h.value.address)" -ceq "100.64.0.2") "an IP address is used as it is"
$h = ConvertFrom-HordeHubAddress -Address "fd7a:115c:a1e0::3"
Check ($h.state -ceq "known" -and "$($h.value.kind)" -ceq "address") "an IPv6 address is used as it is"
Check ((ConvertFrom-HordeHubAddress -Address "hub.example.net").state -ceq "unknown") "a host name is not an address: resolving names is the overlay's job"
Check ((ConvertFrom-HordeHubAddress -Address "overlay:").state -ceq "unknown") "an overlay with no name is unknown"
Check ((ConvertFrom-HordeHubAddress -Address "overlay:../x").state -ceq "unknown") "an overlay name that is not a plain name is unknown"
Check ((ConvertFrom-HordeHubAddress -Address "overlay:home & calc").state -ceq "unknown") "an overlay name with a shell metacharacter never reaches a command line"
Check ((ConvertFrom-HordeHubAddress -Address "").state -ceq "unknown") "an empty address is unknown"
$schemaName = "$((Get-HordeSchema -Name 'overlay-endpoint.v1').properties.overlay.pattern)" -replace '\$$', '\z'
Check ($script:HordeOverlayNamePattern -ceq $schemaName) ("the overlay name core/OverlayCommand.ps1 will put on a command line is schema/overlay-endpoint.v1's, anchored at the end (" + $schemaName + ")")

Write-Host ""
Write-Host "--- the output is the schema's or it is unknown ---" -ForegroundColor Cyan
$e = Read-HordeOverlayEndpoint -Text $golden -Name "home"
Check ($e.state -ceq "known" -and "$($e.value.self.address)" -ceq "100.64.0.1") "the golden endpoint reads as known"
$bad = $golden.Replace('"100.64.0.2"', '"hub.example.net"')
Check ($bad -cne $golden) "CONTROL: the host-name variant differs from the golden"
$e = Read-HordeOverlayEndpoint -Text $bad -Name "home"
Check ($e.state -ceq "unknown" -and $e.reason -clike "*schema*" -and $e.reason -cnotlike "*100.64*") "output that fails the schema is unknown, and gives no address at all"
$e = Read-HordeOverlayEndpoint -Text "not json" -Name "home"
Check ($e.state -ceq "unknown" -and $e.reason -clike "*not JSON*") "output that is not JSON is unknown"
$e = Read-HordeOverlayEndpoint -Text "" -Name "home"
Check ($e.state -ceq "unknown" -and $e.reason -clike "*gave no answer*") "no output is unknown, and says the overlay gave no answer"
$e = Read-HordeOverlayEndpoint -Text $golden -Name "work"
Check ($e.state -ceq "unknown" -and $e.reason -clike "*home*" -and $e.reason -clike "*work*") "an answer about another overlay than the one asked for is unknown"
$noValue = $golden.Replace('"value": true,', '')
Check ($noValue -cne $golden) "CONTROL: the no-value variant differs from the golden"
Check ((Read-HordeOverlayEndpoint -Text $noValue -Name "home").state -ceq "unknown") "a known health without its value is unknown: the answer rule holds here too"
$e = Read-HordeOverlayEndpoint -Text ($golden + (" " * 70000)) -Name "home"
Check ($e.state -ceq "unknown" -and $e.reason -clike "*characters*") "output past the cap is unknown"
# In the health reason, a field the schema leaves free, so only the ASCII check can refuse it.
$hiText = $golden.Replace('"reason": ""', ('"reason": "caf' + [char]0xE9 + '"'))
Check ($hiText -cne $golden) "CONTROL: the non-ASCII variant differs from the golden"
$e = Read-HordeOverlayEndpoint -Text $hiText -Name "home"
Check ($e.state -ceq "unknown" -and $e.reason -clike "*not printable ASCII*") "output with a raw non-ASCII character is unknown, even where the schema allows any text"

Write-Host ""
Write-Host "--- a peer's address, never a guess ---" -ForegroundColor Cyan
$e = Read-HordeOverlayEndpoint -Text $golden -Name "home"
Check (IsKnown (Get-HordeOverlayPeerAddress -Endpoint $e -Peer "hub") "100.64.0.2") "the hub peer's address is the one the overlay gave"
Check (IsKnown (Get-HordeOverlayPeerAddress -Endpoint $e -Peer "laptop") "fd7a:115c:a1e0::3") "an IPv6 peer address is given as it is"
$p = Get-HordeOverlayPeerAddress -Endpoint $e -Peer "server"
Check ($p.state -ceq "unknown" -and $p.reason -clike "*server*") "a peer the overlay does not list is unknown, never a guessed address"
$np = Get-HordeOverlayPeerAddress -Endpoint (Read-HordeOverlayEndpoint -Text "x" -Name "home") -Peer "hub"
Check ($np.state -ceq "unknown" -and $np.reason -clike "*answer is unknown*") "with no endpoint, no peer address: the endpoint's unknown is carried through"
Check ((Get-HordeOverlayPeerAddress -Endpoint $e -Peer "HUB").state -ceq "unknown") "a peer name is matched exactly"

Write-Host ""
Write-Host "--- the overlay's health is advice: the handshake decides the link ---" -ForegroundColor Cyan
$healthy = $e
$sick = Read-HordeOverlayEndpoint -Text $golden.Replace('"value": true,', '"value": false,') -Name "home"
Check ($sick.state -ceq "known" -and $sick.value.health.value -eq $false) "CONTROL: the unhealthy variant reads"
Check (IsKnown (Get-HordeOverlayLinkAnswer -Endpoint $healthy -Handshake (New-HordeKnown -Value $true)) $true) "a handshake that succeeded is a link, whatever the overlay says"
Check (IsKnown (Get-HordeOverlayLinkAnswer -Endpoint $sick -Handshake (New-HordeKnown -Value $true)) $true) "even an overlay reporting unhealthy cannot take a working link down"
$a = Get-HordeOverlayLinkAnswer -Endpoint $healthy -Handshake (New-HordeUnknown -Reason "link refused")
Check ($a.state -ceq "unknown" -and $a.reason -clike "*link refused (overlay reports healthy)*") "a refused handshake beside a healthy overlay is unknown: link refused (overlay reports healthy)"
$a = Get-HordeOverlayLinkAnswer -Endpoint $sick -Handshake (New-HordeUnknown -Reason "link refused")
Check ($a.state -ceq "unknown" -and $a.reason -clike "*overlay reports unhealthy*") "a refused handshake beside an unhealthy overlay says so"
$a = Get-HordeOverlayLinkAnswer -Endpoint (Read-HordeOverlayEndpoint -Text "x" -Name "home") -Handshake (New-HordeUnknown -Reason "link refused")
Check ($a.state -ceq "unknown" -and $a.reason -clike "*link refused*" -and $a.reason -clike "*overlay*unknown*") "with no overlay answer the handshake's reason still leads"
Check (-not ((Get-HordeOverlayLinkAnswer -Endpoint $sick -Handshake (New-HordeUnknown -Reason "link refused")).state -ceq "known")) "an overlay's health never makes a link known down"
Check ((Get-HordeOverlayLinkAnswer -Endpoint $healthy -Handshake (New-HordeKnown -Value 1)).state -ceq "unknown") "a handshake answer of 1 is not a boolean true, so not a link"
Check ((Get-HordeOverlayLinkAnswer -Endpoint $healthy -Handshake (New-HordeKnown -Value @("no", $true))).state -ceq "unknown") "a handshake answer that is a list is not a link"
$absentHealth = Read-HordeOverlayEndpoint -Text $golden.Replace('"state": "known",', '"state": "absent",').Replace('"value": true,', '') -Name "home"
Check ($absentHealth.state -ceq "known" -and (Get-HordeOverlayLinkAnswer -Endpoint $absentHealth -Handshake (New-HordeUnknown -Reason "link refused")).reason -clike "*reports no health*") "an overlay that reports no health is said so, not called unknown"

Write-Host ""
Write-Host "--- core/OverlayCommand runs one command line, and answers unknown when it cannot ---" -ForegroundColor Cyan
$work = Join-Path $env:TEMP ("horde-overlay-" + [guid]::NewGuid().ToString("N"))
$origPath = $env:PATH
function Use-Fake {
    # A folder holding one fake horde-overlay.cmd, put first on PATH, with System32 after it for cmd.
    param([string]$Name, [string]$Body)
    $d = Join-Path $work $Name
    New-Item -ItemType Directory -Path $d | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $d "horde-overlay.cmd"), ($Body -replace "`r?`n", "`r`n"))
    $env:PATH = $d + ";" + (Join-Path $env:SystemRoot "System32")
    return $d
}
try {
    New-Item -ItemType Directory -Path $work | Out-Null
    $fx = Join-Path $root "test\fixtures\link\overlay.json"
    $d = Use-Fake "argv" ("@echo %*> `"" + (Join-Path $work "argv.txt") + "`"`r`n@type `"" + $fx + "`"")
    $r = Invoke-HordeOverlayEndpoint -Name "home" -TimeoutSeconds 20
    Check ($r.state -ceq "known" -and (Read-HordeOverlayEndpoint -Text $r.value -Name "home").state -ceq "known") "the fake overlay's endpoint output comes back and reads as known"
    Check ([System.IO.File]::ReadAllText((Join-Path $work "argv.txt")).Trim() -ceq "endpoint --name home --json") "the one command line Horde sends is endpoint --name <name> --json"
    Use-Fake "junk" "@echo this is not json" | Out-Null
    $r = Invoke-HordeOverlayEndpoint -Name "home" -TimeoutSeconds 20
    Check ($r.state -ceq "known" -and (Read-HordeOverlayEndpoint -Text $r.value -Name "home").state -ceq "unknown") "junk output comes back as text, and the reader makes it unknown"
    Use-Fake "fails" "@echo the tunnel is down 1>&2`r`n@exit /b 3" | Out-Null
    $r = Invoke-HordeOverlayEndpoint -Name "home" -TimeoutSeconds 20
    Check ($r.state -ceq "unknown" -and $r.reason -clike "*exited 3*" -and $r.reason -clike "*the tunnel is down*") "a failing overlay is unknown, with its exit code and its first error line"
    Use-Fake "hangs" "@set /p never=" | Out-Null
    $started = Get-Date
    $r = Invoke-HordeOverlayEndpoint -Name "home" -TimeoutSeconds 2
    Check ($r.state -ceq "unknown" -and $r.reason -clike "*within 2 s*" -and ((Get-Date) - $started).TotalSeconds -lt 15) "an overlay that never answers is unknown after the timeout, not waited on for ever"
    Check ($null -ne $script:HordeOverlayLastProcess -and $script:HordeOverlayLastProcess.HasExited -and $r.reason -clike "*was stopped*") "and the process this call started has been stopped, which the reason says only because it is true"
    $d = Use-Fake "grandchild" ("@start /b ping -n 12 127.0.0.1`r`n@type `"" + $fx + "`"")
    $started = Get-Date
    $r = Invoke-HordeOverlayEndpoint -Name "home" -TimeoutSeconds 3
    $took = ((Get-Date) - $started).TotalSeconds
    Check ($r.state -ceq "unknown" -and $took -lt 9) ("a program whose child still holds the output is unknown within the timeout, not waited on for the child (" + [int]$took + " s)")
    Check ($r.reason -clike "*not stopped here*") "and the reason does not claim the child was stopped"
    Use-Fake "never2" ("@echo ran> `"" + (Join-Path $work "ran2.txt") + "`"") | Out-Null
    $r = Invoke-HordeOverlayEndpoint -Name "home`n" -TimeoutSeconds 20
    Check ($r.state -ceq "unknown" -and -not (Test-Path -LiteralPath (Join-Path $work "ran2.txt"))) "a name with a trailing newline is refused before anything runs"
    $r = Invoke-HordeOverlayEndpoint -Name "home" -TimeoutSeconds 0
    Check ($r.state -ceq "unknown" -and $r.reason -clike "*cannot be honoured*" -and -not (Test-Path -LiteralPath (Join-Path $work "ran2.txt"))) "a timeout below one second is refused before anything runs"
    $hi = Use-Fake "highbyte" ""
    [System.IO.File]::WriteAllBytes((Join-Path $hi "hi.json"), [byte[]](@([System.Text.Encoding]::ASCII.GetBytes($golden.Replace('"reason": ""', '"reason": "X"'))) | ForEach-Object { if ($_ -eq 88) { 233 } else { $_ } }))
    [System.IO.File]::WriteAllText((Join-Path $hi "horde-overlay.cmd"), ("@type `"" + (Join-Path $hi "hi.json") + "`"`r`n"))
    $r = Invoke-HordeOverlayEndpoint -Name "home" -TimeoutSeconds 20
    Check ($r.state -ceq "known" -and (Read-HordeOverlayEndpoint -Text $r.value -Name "home").state -ceq "unknown") "a raw byte above 0x7F reaches the reader as itself and is refused, never a question mark that passes"
    $bare = Join-Path $work "bare"
    New-Item -ItemType Directory -Path $bare | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $bare "horde-overlay"), "not a program")
    $env:PATH = $bare + ";" + (Join-Path $env:SystemRoot "System32")
    $r = Invoke-HordeOverlayEndpoint -Name "home" -TimeoutSeconds 20
    Check ($r.state -ceq "unknown" -and $r.reason -clike "*not a program at a full path*") "a horde-overlay that is not a program is unknown, never an error, and never started"
    $badExe = Join-Path $work "badexe"
    New-Item -ItemType Directory -Path $badExe | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $badExe "horde-overlay.exe"), "this is text, not a program")
    $env:PATH = $badExe + ";" + (Join-Path $env:SystemRoot "System32")
    $threw = $false; $r = $null
    try { $r = Invoke-HordeOverlayEndpoint -Name "home" -TimeoutSeconds 20 } catch { $threw = $true }
    Check ($threw -eq $false -and $null -ne $r -and $r.state -ceq "unknown" -and $r.reason -clike "*could not be started*") "a horde-overlay.exe that Windows cannot start is unknown with the reason, never an error"
    $env:PATH = (Join-Path $work "none") + ";" + (Join-Path $env:SystemRoot "System32")
    $r = Invoke-HordeOverlayEndpoint -Name "home" -TimeoutSeconds 20
    Check ($r.state -ceq "unknown" -and $r.reason -clike "*not found*") "a missing horde-overlay is unknown with the reason"
    Use-Fake "never" ("@echo ran> `"" + (Join-Path $work "ran.txt") + "`"") | Out-Null
    $r = Invoke-HordeOverlayEndpoint -Name "home & calc" -TimeoutSeconds 20
    Check ($r.state -ceq "unknown" -and -not (Test-Path -LiteralPath (Join-Path $work "ran.txt"))) "a name that is not a plain name is refused before anything runs"
    $big = Use-Fake "big" ""
    [System.IO.File]::WriteAllText((Join-Path $big "big.txt"), ("x" * 70000))
    [System.IO.File]::WriteAllText((Join-Path $big "horde-overlay.cmd"), ("@type `"" + (Join-Path $big "big.txt") + "`"`r`n"))
    $r = Invoke-HordeOverlayEndpoint -Name "home" -TimeoutSeconds 20
    Check ($r.state -ceq "unknown" -and $r.reason -clike "*bytes*") "output past the cap is unknown, not read whole"
} finally {
    $env:PATH = $origPath
    if ((Split-Path -Leaf $work) -match '^horde-overlay-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check ($env:PATH -ceq $origPath) "the real PATH is restored"

Complete-HordeSuite -Success "Horde asks the overlay one question, takes an address and advice, and never guesses"
