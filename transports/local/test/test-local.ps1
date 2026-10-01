# DOES THE LOCAL PIPE ADMIT ONLY ITS OWN USER, AND REFUSE A PIPE SOMEONE ELSE MADE?
#
# Remote plan step R4: "the pipe refuses another user (a test account, or the refusal asserted
# through the ACL read back)". No second account exists on the machine this was written on, so:
#   - the ACL of a live listening pipe is READ BACK and must be exactly: protected (nothing
#     inherited), owned by this user, Allow FullControl to this user, Deny FullControl to NETWORK, and
#     no rule for any other principal;
#   - CONTROL: a pipe of the same name whose ACL denies this user is refused by the same Open, so
#     "the ACL decides who connects" is shown working, not assumed.
#   - the client's owner check, which is what stops a squatter, is a function tested on its own; a
#     pipe owned by another user cannot be made without a second account, and that is written down
#     here rather than claimed.
# The transport-neutral cases (framing, dialling, keepalive) are test/test-transport-conformance.ps1.
#
# Every pipe here is named from a fresh random device id and closed by this suite.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "transports\Port.ps1")
. (Join-Path $root "transports\local\Transport.ps1")

$t = Get-HordeTransport -Name "local"
$me = Get-HordeLocalUserSid
function New-Id { return [guid]::NewGuid().ToString() }
function Test-PipeListed { param([string]$Pipe) return (@([System.IO.Directory]::EnumerateFiles($script:HordeLocalPipeRoot, $Pipe)).Count -gt 0) }

Write-Host ""
Write-Host "--- the pipe name comes only from a device id ---" -ForegroundColor Cyan

$id = New-Id
Check ((Get-HordeLocalPipeName -DeviceId $id) -ceq ("horde-node-" + $id)) "a device id names the pipe horde-node-<id>"
foreach ($bad in @("..\x", ($id.ToUpperInvariant()), "", "*", ($id + "\x"))) {
    Check ($null -eq (Get-HordeLocalPipeName -DeviceId $bad)) "'$bad' names no pipe"
}
$l = Start-HordeTransportListener -Transport $t -Endpoint "..\x"
Check ($l.state -ceq "unknown") "listening on a malformed id is refused"

Write-Host ""
Write-Host "--- the live pipe's ACL, read back ---" -ForegroundColor Cyan

$id = New-Id
$la = Start-HordeTransportListener -Transport $t -Endpoint $id
Check ($la.state -ceq "known") "a listener starts on a fresh device id"
if ($la.state -eq "known") {
    $listener = Get-HordeValue $la
    try {
        $sec = $listener.state.server.GetAccessControl()
        $rules = @($sec.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
        $net = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::NetworkSid, $null)
        Write-Host ("  rules: " + (($rules | ForEach-Object { "" + $_.IdentityReference + " " + $_.AccessControlType + " " + $_.PipeAccessRights }) -join "; ")) -ForegroundColor DarkGray
        Check ($sec.AreAccessRulesProtected -eq $true) "the ACL inherits nothing"
        Check ("$($sec.GetOwner([System.Security.Principal.SecurityIdentifier]))" -ceq "$me") "the owner is this user"
        Check ($rules.Count -eq 2) "it holds exactly two rules"
        $allowMe = @($rules | Where-Object { "$($_.IdentityReference)" -ceq "$me" -and $_.AccessControlType -eq "Allow" -and $_.PipeAccessRights -eq [System.IO.Pipes.PipeAccessRights]::FullControl })
        $denyNet = @($rules | Where-Object { "$($_.IdentityReference)" -ceq "$net" -and $_.AccessControlType -eq "Deny" -and $_.PipeAccessRights -eq [System.IO.Pipes.PipeAccessRights]::FullControl })
        Check ($allowMe.Count -eq 1) "one allows this user full control"
        Check ($denyNet.Count -eq 1) "one denies NETWORK (S-1-5-2) full control"
        $others = @($rules | Where-Object { "$($_.IdentityReference)" -cne "$me" -and "$($_.IdentityReference)" -cne "$net" })
        Check ($others.Count -eq 0) "no rule names anyone else: not Everyone, Users, Authenticated Users or Anonymous"
        Check ((@($rules | Where-Object { $_.IsInherited })).Count -eq 0) "no rule is inherited"

        $second = Start-HordeTransportListener -Transport $t -Endpoint $id
        Check ($second.state -ceq "unknown" -and "$($second.reason)" -like "*already in use*") "the name cannot be taken twice: one instance only"
    } finally { Stop-HordeTransportListener -Listener $listener }
    Check (-not (Test-PipeListed ("horde-node-" + $id))) "a stopped listener leaves no pipe behind"
}

Write-Host ""
Write-Host "--- CONTROL: an ACL that does not admit this user refuses it ---" -ForegroundColor Cyan

$id = New-Id
$pipe = Get-HordeLocalPipeName -DeviceId $id
$deny = New-Object System.IO.Pipes.PipeSecurity
$deny.SetAccessRuleProtection($true, $false)
$deny.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule($me, [System.IO.Pipes.PipeAccessRights]::CreateNewInstance, [System.Security.AccessControl.AccessControlType]::Allow)))
$deny.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule($me, [System.IO.Pipes.PipeAccessRights]::ReadWrite, [System.Security.AccessControl.AccessControlType]::Deny)))
$other = New-Object System.IO.Pipes.NamedPipeServerStream($pipe, [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous, 4096, 4096, $deny)
try {
    $o = Open-HordeTransportLink -Transport $t -Endpoint $id -Role "node" -TimeoutMs 2000
    Check ($o.state -ceq "unknown" -and "$($o.reason)" -like "*refused*ACL*") "dialling a pipe whose ACL denies this user is refused, and says the ACL refused it"
    $l2 = Start-HordeTransportListener -Transport $t -Endpoint $id
    Check ($l2.state -ceq "unknown" -and "$($l2.reason)" -like "*already in use*") "and a node will not listen on a name someone else already holds"
} finally { $other.Dispose() }

Write-Host ""
Write-Host "--- the client's owner check, which stops a squatter ---" -ForegroundColor Cyan

$system = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
Check ((Test-HordeLocalPipeOwner -Owner $me -Expected $me) -eq $true) "a pipe owned by this user passes"
Check ((Test-HordeLocalPipeOwner -Owner $system -Expected $me) -eq $false) "a pipe owned by another principal (SYSTEM here) fails"
Check ((Test-HordeLocalPipeOwner -Owner $null -Expected $me) -eq $false) "a pipe whose owner could not be read fails"
Write-Host "  NOT SHOWN end to end: a pipe really owned by another user needs a second account, which this machine does not have." -ForegroundColor Yellow

$id = New-Id
$la = Start-HordeTransportListener -Transport $t -Endpoint $id
if ($la.state -eq "known") {
    $listener = Get-HordeValue $la
    try {
        $o = Open-HordeTransportLink -Transport $t -Endpoint $id -Role "node" -TimeoutMs 5000
        Check ($o.state -ceq "known") "control: this user's own pipe is dialled"
        if ($o.state -eq "known") {
            $link = Get-HordeValue $o
            Check ($link.peer.verified -eq $true -and "$($link.peer.identity)" -ceq "$me" -and "$($link.peer.how)" -like "*owner*") "and its peer is verified by the pipe's owner, this user"
            $ka = Receive-HordeTransportLink -Listener $listener -TimeoutMs 5000
            Check ($ka.state -ceq "known" -and "$($ka.value.peer.how)" -like "*ACL*") "the accepting end says its peer was admitted by the ACL"
            if ($ka.state -eq "known") { Close-HordeLink -Link (Get-HordeValue $ka) }
            Close-HordeLink -Link $link
        }
    } finally { Stop-HordeTransportListener -Listener $listener }
} else { Check $false "a listener for the owner control" }

Complete-HordeSuite -Success "the local pipe admits only its own user, and refuses a pipe it did not make"
