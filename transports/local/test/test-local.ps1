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
. (Join-Path $root "transports\local\Native.ps1")
. (Join-Path $here "LowIntegrity.ps1")

$t = Get-HordeTransport -Name "local"
$script:ownerCaseSkipped = $false
$me = Get-HordeLocalUserSid
function New-Id { return [guid]::NewGuid().ToString() }
function Test-PipeListed { param([string]$Pipe) return (@([System.IO.Directory]::EnumerateFiles($script:HordeLocalPipeRoot, $Pipe)).Count -gt 0) }
function New-TestPipeServer {
    # A server pipe made with -Security, in either shell (T-0450). .NET Core has no NamedPipeServerStream
    # constructor that takes a PipeSecurity - measured 2026-11-11 on 7.6.7: "Cannot find an overload for
    # NamedPipeServerStream and the argument count: 8" - and NamedPipeServerStreamAcl.Create is its form there.
    # Chosen by whether that type exists, not by the shell's version.
    param([string]$Name, [int]$Buffer, [System.IO.Pipes.PipeSecurity]$Security)
    $acl = "System.IO.Pipes.NamedPipeServerStreamAcl" -as [type]
    if ($null -ne $acl) { return $acl::Create($Name, [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous, $Buffer, $Buffer, $Security) }
    return (New-Object System.IO.Pipes.NamedPipeServerStream($Name, [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous, $Buffer, $Buffer, $Security))
}

Write-Host ""
Write-Host "--- the pipe name comes only from a device id ---" -ForegroundColor Cyan

$id = New-Id
Check ((Get-HordeLocalPipeName -DeviceId $id) -ceq ("horde-node-" + $id)) "a device id names the pipe horde-node-<id>"
foreach ($bad in @("..\x", ($id.ToUpperInvariant()), "", "*", ($id + "\x"))) {
    Check ($null -eq (Get-HordeLocalPipeName -DeviceId $bad)) "'$bad' names no pipe"
}
$l = Start-HordeTransportListener -Transport $t -Endpoint "..\x"
Check ($l.state -ceq "unknown") "listening on a malformed id is refused"
# The hub's own pipe (R17a): "hub:<id>" and nothing looser.
Check ((Get-HordeLocalPipeName -DeviceId ("hub:" + $id)) -ceq ("horde-hub-" + $id)) "hub:<id> names the hub's pipe horde-hub-<id>"
foreach ($bad in @("hub:", ("hub:" + $id.ToUpperInvariant()), ("HUB:" + $id), ("hub:..\" + $id), ("hub:" + $id + "\x"), ("hub:hub:" + $id), (" hub:" + $id), ("hub:*"))) {
    Check ($null -eq (Get-HordeLocalPipeName -DeviceId $bad)) "'$bad' names no pipe"
}
$l = Start-HordeTransportListener -Transport $t -Endpoint ("hub:" + "..\x")
Check ($l.state -ceq "unknown") "listening on a malformed hub endpoint is refused"

Write-Host ""
Write-Host "--- the live pipe's ACL, read back ---" -ForegroundColor Cyan

$id = New-Id
$la = Start-HordeTransportListener -Transport $t -Endpoint $id
Check ($la.state -ceq "known") "a listener starts on a fresh device id"
if ($la.state -eq "known") {
    $listener = Get-HordeValue $la
    try {
        $sec = (Get-HordeLocalPipeSecurity -Pipe $listener.state.server)
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
Write-Host "--- the hub's own pipe (R17a): beside the node's, the same rules, the dialler a node ---" -ForegroundColor Cyan
$id = New-Id
$ln = Start-HordeTransportListener -Transport $t -Endpoint $id
$lh = Start-HordeTransportListener -Transport $t -Endpoint ("hub:" + $id)
Check ($ln.state -ceq "known" -and $lh.state -ceq "known") "one device holds its node pipe and its hub pipe at once"
if ($ln.state -eq "known" -and $lh.state -eq "known") {
    $nl = Get-HordeValue $ln; $hl = Get-HordeValue $lh
    try {
        Check (Test-PipeListed ("horde-hub-" + $id)) "the hub's pipe is \\.\pipe\horde-hub-<hubId>"
        $hs = (Get-HordeLocalPipeSecurity -Pipe $hl.state.server).GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner)
        $ns = (Get-HordeLocalPipeSecurity -Pipe $nl.state.server).GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access -bor [System.Security.AccessControl.AccessControlSections]::Owner)
        Check ($hs -ceq $ns -and $hs.Contains("(D;;") -and $hs.Contains($me.Value)) ("its owner and ACL are the node pipe's, read back: " + $hs)
        # The ACL itself, rule by rule, not the owner: this session may be elevated, where a pipe made
        # without an explicit owner comes out owned by Administrators (review of #138).
        $hsec = (Get-HordeLocalPipeSecurity -Pipe $hl.state.server)
        $hrules = @($hsec.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
        $netSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::NetworkSid, $null)
        Write-Host ("  hub pipe rules: " + (($hrules | ForEach-Object { "" + $_.IdentityReference + " " + $_.AccessControlType + " " + $_.PipeAccessRights }) -join "; ")) -ForegroundColor DarkGray
        Check ($hsec.AreAccessRulesProtected -eq $true -and $hrules.Count -eq 2 -and @($hrules | Where-Object { $_.IsInherited }).Count -eq 0) "the hub pipe's ACL is protected and holds exactly two rules, neither inherited"
        Check (@($hrules | Where-Object { "$($_.IdentityReference)" -ceq "$me" -and $_.AccessControlType -eq "Allow" -and $_.PipeAccessRights -eq [System.IO.Pipes.PipeAccessRights]::FullControl }).Count -eq 1) "one allows this user, the hub's own, full control"
        Check (@($hrules | Where-Object { "$($_.IdentityReference)" -ceq "$netSid" -and $_.AccessControlType -eq "Deny" }).Count -eq 1) "one denies NETWORK"
        Check (@($hrules | Where-Object { "$($_.IdentityReference)" -cne "$me" -and "$($_.IdentityReference)" -cne "$netSid" }).Count -eq 0) "no rule names anyone else: not Administrators, SYSTEM, Everyone or Users"
        $second = Start-HordeTransportListener -Transport $t -Endpoint ("hub:" + $id)
        Check ($second.state -ceq "unknown" -and "$($second.reason)" -like "*already in use*") "the hub's name cannot be taken twice either"
        $o = Open-HordeTransportLink -Transport $t -Endpoint ("hub:" + $id) -Role "node" -TimeoutMs 5000
        $ka = Receive-HordeTransportLink -Listener $hl -TimeoutMs 5000
        Check ($o.state -ceq "known" -and $ka.state -ceq "known" -and (Get-HordeValue $o).peer.verified -eq $true) "a node-role dial to hub:<id> is opened, verified and accepted by the hub's listener"
        if ($o.state -eq "known" -and $ka.state -eq "known") {
            $null = Send-HordeLinkFrame -Link (Get-HordeValue $o) -Frame "to-the-hub" -TimeoutMs 5000
            $got = Receive-HordeLinkFrame -Link (Get-HordeValue $ka) -TimeoutMs 5000
            Check ($got.state -ceq "known" -and "$($got.value)" -ceq "to-the-hub") "a frame crosses the hub's pipe"
            $nobody = Receive-HordeTransportLink -Listener $nl -TimeoutMs 200
            Check ($nobody.state -ceq "unknown") "and the node's own pipe saw no client: the two names are two pipes"
        }
        if ($o.state -eq "known") { Close-HordeLink -Link (Get-HordeValue $o) }
        if ($ka.state -eq "known") { Close-HordeLink -Link (Get-HordeValue $ka) }
    } finally { Stop-HordeTransportListener -Listener $hl; Stop-HordeTransportListener -Listener $nl }
    Check (-not (Test-PipeListed ("horde-hub-" + $id))) "a stopped hub listener leaves no pipe behind"
    # Issue #147, item 7: a dial to a hub nobody serves says a hub did not answer, not a node.
    $gone = Open-HordeTransportLink -Transport $t -Endpoint ("hub:" + $id) -Role "node" -TimeoutMs 300
    Check ($gone.state -ceq "unknown" -and "$($gone.reason)" -like "*no hub answered on horde-hub-*") ("a dial to a hub nobody serves says no hub answered (" + $gone.reason + ")")
    $gone = Open-HordeTransportLink -Transport $t -Endpoint $id -Role "hub" -TimeoutMs 300
    Check ($gone.state -ceq "unknown" -and "$($gone.reason)" -like "*no node answered on horde-node-*") ("CONTROL: and a dial to a node nobody serves still says no node answered (" + $gone.reason + ")")
} else {
    if ($ln.state -eq "known") { Stop-HordeTransportListener -Listener (Get-HordeValue $ln) }
    if ($lh.state -eq "known") { Stop-HordeTransportListener -Listener (Get-HordeValue $lh) }
}

Write-Host ""
Write-Host "--- CONTROL: an ACL that does not admit this user refuses it ---" -ForegroundColor Cyan

$id = New-Id
$pipe = Get-HordeLocalPipeName -DeviceId $id
$deny = New-Object System.IO.Pipes.PipeSecurity
$deny.SetAccessRuleProtection($true, $false)
$deny.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule($me, [System.IO.Pipes.PipeAccessRights]::CreateNewInstance, [System.Security.AccessControl.AccessControlType]::Allow)))
$deny.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule($me, [System.IO.Pipes.PipeAccessRights]::ReadWrite, [System.Security.AccessControl.AccessControlType]::Deny)))
$other = New-TestPipeServer -Name $pipe -Buffer 4096 -Security $deny
try {
    $o = Open-HordeTransportLink -Transport $t -Endpoint $id -Role "node" -TimeoutMs 2000
    Check ($o.state -ceq "unknown" -and "$($o.reason)" -like "*refused*ACL*") "dialling a pipe whose ACL denies this user is refused, and says the ACL refused it"
    # A denied open cannot tell the ACL from the label. A Medium hub dialling a High node is denied by
    # the label before any check runs, and cannot read the label to say so (measured 2026-10-01: a
    # Medium process's open and its GetNamedSecurityInfo of the label both fail with access denied). The
    # first message blamed the ACL alone, which misled (review of PR #42, round 3).
    Check ("$($o.reason)" -like "*integrity level*") "and says it may instead be an integrity level above this end's"
    Check ("$($o.reason)" -like ("*this end runs at integrity " + (Get-HordeLocalOwnIntegrity) + "*")) "naming this end's own level"
    Check ("$($o.reason)" -like "*run the hub and node at the same integrity level*") "and says to run the hub and node at the same integrity level"
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

# THE OWNER IS READ IN BOTH SHELLS, AND A READ THAT FAILS REFUSES WITHOUT BLAMING A SQUATTER (T-0450).
# Under pwsh 7 the pipe had no GetAccessControl method, the read threw, and every dial to this user's own
# node was refused as "owned by ''". A pipe made as the transport makes its own, dialled directly, is
# read here: New-HordeLocalServer names this user as owner, where a pipe made without one comes out owned
# by Administrators on an elevated token (measured 2026-11-11 in the slot's run: S-1-5-32-544). A disposed
# pipe cannot be read in either shell (ObjectDisposedException, "Cannot access a closed pipe", on
# 5.1.26100 and 7.6.7).
$ownName = "horde-test-owner-" + [guid]::NewGuid().ToString()
$ownMade = New-HordeLocalServer -Pipe $ownName -First
if ($null -eq $ownMade.stream) { throw ("the owner case's pipe could not be made: " + $ownMade.reason) }
$ownServer = $ownMade.stream
$ownClient = New-Object System.IO.Pipes.NamedPipeClientStream(".", $ownName, [System.IO.Pipes.PipeDirection]::InOut)
try {
    $ownClient.Connect(5000)
    $ownRead = (Get-HordeLocalPipeSecurity -Pipe $ownClient).GetOwner([System.Security.Principal.SecurityIdentifier])
    Check ("$ownRead" -ceq "$me") ("a dialled pipe's owner is read in this shell, " + $PSVersionTable.PSVersion + " (" + $ownRead + ")")
    Check ((Get-HordeLocalOwnerRefusal -Pipe $ownClient -Name $ownName -Expected $me) -ceq "") "a pipe owned by this user is not refused on its owner"
    $otherWhy = Get-HordeLocalOwnerRefusal -Pipe $ownClient -Name $ownName -Expected $system
    Check ($otherWhy -like ("refused: " + $ownName + " is owned by '" + $me + "', not by this user; it may be a squatter")) ("a pipe owned by someone other than the expected user is refused, naming its owner (" + $otherWhy + ")")
} finally { $ownClient.Dispose(); $ownServer.Dispose() }
$unreadWhy = Get-HordeLocalOwnerRefusal -Pipe $ownClient -Name $ownName -Expected $me
Check ($unreadWhy -like ("refused: the owner of " + $ownName + " could not be read (*")) ("a pipe whose owner cannot be read is refused, as could not be read (" + $unreadWhy + ")")
Check ($unreadWhy -notlike "*squatter*" -and $unreadWhy -notlike "*owned by*") "and the refusal does not call it a squatter or name an owner it never read"

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


Write-Host ""
Write-Host "--- a LOW-integrity process of the same user (review of PR #42) ---" -ForegroundColor Cyan

# The reviewer's attacker: this user's SID, a lowered token. An owner check alone cannot tell it from
# the user. Every low process here is started by this suite, reports to a folder this suite made, and
# ends on its own within 25 s.
$lowDir = New-HordeLowFolder
try {
    # 1. A low process creates the node's pipe first. The hub must refuse it, not call it verified.
    $id = New-Id
    $sq = Start-HordeLowChild -Mode "squat" -Pipe (Get-HordeLocalPipeName -DeviceId $id) -Folder $lowDir
    $created = Wait-HordeLowLine -Out $sq.out -Pattern "squat: CREATED" -Ms 20000
    Check ($created) "CONTROL: the low-integrity process did create the pipe first"
    $o = Open-HordeTransportLink -Transport $t -Endpoint $id -Role "hub" -TimeoutMs 5000
    Check ($o.state -ceq "unknown" -and "$($o.reason)" -like "*integrity*") "the hub refuses a pipe served by a low-integrity process, naming the integrity"
    Check ("$($o.reason)" -like "*run the hub and node at the same integrity level*") "and says what to do about it: run the hub and node at the same integrity level"
    if ($o.state -eq "known") { $sneak = Get-HordeValue $o; Write-Host ("         accepted as: " + $sneak.peer.verified + " / " + $sneak.peer.how) -ForegroundColor Red; Close-HordeLink -Link $sneak }
    $null = Wait-HordeLowLine -Out $sq.out -Pattern "done" -Ms 25000
    $sqText = ""; if (Test-Path -LiteralPath $sq.out) { $sqText = [System.IO.File]::ReadAllText($sq.out) }
    Check ($sqText -notmatch "client sent: \S") "and the squatter received nothing from the hub"

    # 2. A low process opens the node's pipe read-only. The mandatory label keeps it out.
    $id = New-Id
    $la = Start-HordeTransportListener -Transport $t -Endpoint $id
    if ($la.state -eq "known") {
        $listener = Get-HordeValue $la
        try {
            $label = [HordeLocalNative]::LabelSddl($listener.state.server.SafePipeHandle)
            Write-Host ("  label: " + $label) -ForegroundColor DarkGray
            # At the node's OWN level, not a fixed Medium: under Medium a Medium process of this user could
            # add an instance to a High node's pipe and be the one the hub reached (review of PR #42, round 2).
            $own = Get-HordeLocalOwnIntegrity
            $alias = @{ 4096 = "LW"; 8192 = "ME"; 12288 = "HI"; 16384 = "SI" }
            $want = "S-1-16-" + $own
            if ($alias.ContainsKey($own)) { $want = $alias[$own] }
            Check ($label -like ("*(ML;;NWNR;;;" + $want + ")*")) ("the pipe carries a No-Write-Up, No-Read-Up label at this node's own level (" + $want + ")")
            $hold = Start-HordeLowChild -Mode "hold" -Pipe (Get-HordeLocalPipeName -DeviceId $id) -Folder $lowDir
            $null = Wait-HordeLowLine -Out $hold.out -Pattern "hold: " -Ms 20000
            $ka = Receive-HordeTransportLink -Listener $listener -TimeoutMs 3000
            Check ($ka.state -ceq "unknown") "the node accepts no link from a low-integrity reader"
            if ($ka.state -eq "known") { $lk = Get-HordeValue $ka; $null = Send-HordeLinkFrame -Link $lk -Frame "node-says-hello" -TimeoutMs 2000; Close-HordeLink -Link $lk }
            $null = Wait-HordeLowLine -Out $hold.out -Pattern "done" -Ms 10000
            $holdText = ""; if (Test-Path -LiteralPath $hold.out) { $holdText = [System.IO.File]::ReadAllText($hold.out) }
            Check ($holdText -match "hold: UnauthorizedAccessException") "the low reader is denied at open"
            Check ($holdText -notmatch "node-says-hello") "and reads nothing the node sent"
        } finally { Stop-HordeTransportListener -Listener $listener }
    } else { Check $false "a listener for the low-reader case" }

    # 2b. The same for the hub's own pipe (R17a; review of #138): attach is the only client meant to
    # reach it, and the hub binds whatever device the first line names, so a process of another
    # identity - here this user at low integrity - must not reach it at all.
    $id = New-Id
    $lh = Start-HordeTransportListener -Transport $t -Endpoint ("hub:" + $id)
    if ($lh.state -eq "known") {
        $hl = Get-HordeValue $lh
        try {
            $hold = Start-HordeLowChild -Mode "hold" -Pipe ("horde-hub-" + $id) -Folder $lowDir
            $null = Wait-HordeLowLine -Out $hold.out -Pattern "hold: " -Ms 20000
            $ka = Receive-HordeTransportLink -Listener $hl -TimeoutMs 3000
            Check ($ka.state -ceq "unknown") "the hub's pipe accepts no link from a low-integrity process"
            if ($ka.state -eq "known") { Close-HordeLink -Link (Get-HordeValue $ka) }
            $null = Wait-HordeLowLine -Out $hold.out -Pattern "done" -Ms 10000
            $holdText = ""; if (Test-Path -LiteralPath $hold.out) { $holdText = [System.IO.File]::ReadAllText($hold.out) }
            Check ($holdText -match "hold: UnauthorizedAccessException") "it is denied at open"
        } finally { Stop-HordeTransportListener -Listener $hl }
    } else { Check $false "a hub listener for the low-reader case" }

    # 3. The node's own check, reached past the label. The label stops a low reader before the node
    # sees it, so to exercise the node's check of its client's integrity, this suite builds a listener
    # state over a pipe labelled LOW - which a low process may open - and runs the transport's own
    # accept on it.
    $id = New-Id
    $pipe = Get-HordeLocalPipeName -DeviceId $id
    $lowSddl = (New-HordeLocalPipeSddl) -replace "ML;;NWNR;;;[^)]*", "ML;;NWNR;;;LW"
    Check ($lowSddl -like "*(ML;;NWNR;;;LW)*") "CONTROL: the test's own pipe is labelled low"
    $err = 0
    $h = [HordeLocalNative]::CreateServer(($script:HordeLocalPipeRoot + $pipe), $lowSddl, $true, 65536, [ref]$err)
    Check (-not $h.IsInvalid) ("CONTROL: a low-labelled test pipe was made (error " + $err + ")")
    if (-not $h.IsInvalid) {
        $state = @{ pipe = $pipe; server = (New-Object System.IO.Pipes.NamedPipeServerStream([System.IO.Pipes.PipeDirection]::InOut, $true, $false, $h)); wait = $null; broken = "" }
        try {
            $hold = Start-HordeLowChild -Mode "hold" -Pipe $pipe -Folder $lowDir
            $r = & $t.accept $state 15000
            Check ($r.ok -eq $false -and "$($r.reason)" -like "*integrity*") "the node refuses a client whose integrity is below its own, naming it"
            Check ("$($r.reason)" -like "*run the hub and node at the same integrity level*") "and says what to do about it"
            # Issue #85: a refusal, not a broken listener - the next waiting instance holds the name, so
            # node serve may keep this listener (review of PR #90, F1: nothing checked the flag here).
            Check ($null -ne $r.PSObject.Properties["refused"] -and $r.refused -eq $true -and $null -ne $state.server) "the refusal is marked refused, and the listener still holds a waiting instance"
            if ($r.ok) { & $r.channel.close $r.channel }
            $quiet = & $t.accept $state 300
            Check ($quiet.ok -eq $false -and $quiet.refused -eq $false) ("CONTROL: an accept on the same listener that times out is not marked refused (" + $quiet.reason + ")")
            $null = Wait-HordeLowLine -Out $hold.out -Pattern "done" -Ms 10000
            $holdText = ""; if (Test-Path -LiteralPath $hold.out) { $holdText = [System.IO.File]::ReadAllText($hold.out) }
            Check ($holdText -match "hold: CONNECTED") "CONTROL: the low client did reach the node past the low label"
        } finally { & $t.stop $state }
    }

    # 3b. The same refusal when the next waiting instance could not be made (review of PR #90, F2): the
    # listener no longer holds the name, so it is broken, not a listener that refused a peer, and the
    # answer must not say refused. The instance maker is replaced for this case only.
    $id = New-Id
    $pipe = Get-HordeLocalPipeName -DeviceId $id
    $h = [HordeLocalNative]::CreateServer(($script:HordeLocalPipeRoot + $pipe), $lowSddl, $true, 65536, [ref]$err)
    if (-not $h.IsInvalid) {
        $state = @{ pipe = $pipe; server = (New-Object System.IO.Pipes.NamedPipeServerStream([System.IO.Pipes.PipeDirection]::InOut, $true, $false, $h)); wait = $null; broken = "" }
        $realMaker = ${function:New-HordeLocalServer}
        try {
            ${function:New-HordeLocalServer} = { param([string]$Pipe, [switch]$First) return [pscustomobject]@{ stream = $null; reason = "the test made the next instance fail" } }
            $hold = Start-HordeLowChild -Mode "hold" -Pipe $pipe -Folder $lowDir
            $r = & $t.accept $state 15000
            Check ($r.ok -eq $false -and "$($r.reason)" -like "*integrity*" -and $null -eq $state.server -and "$($state.broken)" -like "*next instance fail*") ("CONTROL: the low client was refused and the next instance was not made (" + $r.reason + ")")
            Check ($r.refused -eq $false) "a refusal that leaves no waiting instance is not marked refused: the listener is broken, and serve must restart it"
            $null = Wait-HordeLowLine -Out $hold.out -Pattern "done" -Ms 10000
        } finally { ${function:New-HordeLocalServer} = $realMaker; & $t.stop $state }
    } else { Check $false "a low-labelled pipe for the broken-after-refusal case" }

    # 4. A process BELOW the node's level adds an instance to the node's live pipe (review of PR #42,
    # round 2). GetNamedPipeServerProcessId names the FIRST instance's creator, not the instance the hub
    # reached, so the hub's check passed and it sent session.spawn to the adder. The label at the
    # node's own level makes the add itself fail. The adder runs one level below this process.
    $squat = New-HordeSquatProbe -Folder $lowDir
    $ownIl = Get-HordeLocalOwnIntegrity
    $below = ""
    if ($ownIl -ge 12288) { $below = "S-1-16-8192" } elseif ($ownIl -ge 8192) { $below = "S-1-16-4096" }
    if ($below -eq "") {
        Write-Host ("  [SKIP] this process runs at integrity " + $ownIl + "; there is no level below it to add an instance from") -ForegroundColor Yellow
    } else {
        $id = New-Id
        $la = Start-HordeTransportListener -Transport $t -Endpoint $id
        if ($la.state -eq "known") {
            $listener = Get-HordeValue $la
            try {
                $add = Start-HordeSquatProbe -Exe $squat -Mode "add" -Pipe (Get-HordeLocalPipeName -DeviceId $id) -Folder $lowDir -Level $below
                $null = Wait-HordeLowLine -Out $add.out -Pattern "add: (CREATED|[A-Z][a-zA-Z]*Exception)" -Ms 20000
                $addText = ""; if (Test-Path -LiteralPath $add.out) { $addText = [System.IO.File]::ReadAllText($add.out) }
                Write-Host ("  adder at " + $below + ": " + (($addText -split "`r?`n" | Where-Object { $_ }) -join " | ")) -ForegroundColor DarkGray
                Check ($addText -match "add: UnauthorizedAccessException") ("a process at " + $below + " cannot add an instance to the node's pipe")
                Check ($addText -notmatch "add: CREATED") "so there is no instance of its for the hub to reach"
            } finally { Stop-HordeTransportListener -Listener $listener }
            $null = Wait-HordeLowLine -Out $add.out -Pattern "done" -Ms 20000
        } else { Check $false "a listener for the instance-adder case" }
    }

    # 4b. A pipe owned by ANOTHER principal, served at this process's level by the node's own
    # interpreter (this process): integrity and image both pass, so the owner check is the one that
    # refuses it (issue #89 keeps this path pinned now that the attackers above own their pipes).
    # Administrators is the one other owner this suite can give a pipe, and only from a token allowed
    # to assign it (an elevated admin token); elsewhere the case is skipped, never green.
    $id = New-Id
    $ba = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
    $baPipe = $null
    $baWhy = ""
    $baCode = 0
    try {
        $sec = New-Object System.IO.Pipes.PipeSecurity
        $sec.SetOwner($ba)
        $sec.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule($me, [System.IO.Pipes.PipeAccessRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)))
        $baPipe = New-TestPipeServer -Name (Get-HordeLocalPipeName -DeviceId $id) -Buffer 0 -Security $sec
    } catch {
        $e = $_.Exception; while ($null -ne $e.InnerException) { $e = $e.InnerException }
        $baWhy = $e.Message; $baCode = $e.HResult
    }
    # SKIPPED ONLY FOR THE ONE REASON IT MAY BE (review of PR #91, G2): HRESULT 0x8007051B,
    # ERROR_INVALID_OWNER, "This security ID may not be assigned as the owner of this object" - measured
    # 2026-10-05 from a runas /trustlevel:0x20000 token. Any other failure to make the pipe ("All pipe
    # instances are busy", say) is a failure, never a quiet skip of the only end-to-end owner check.
    if ($null -eq $baPipe -and $baCode -eq -2147023589) {
        Write-Host ("  [SKIP] this token cannot make Administrators a pipe's owner (" + $baWhy + "), so the owner refusal is not shown end to end here; the decision is checked above. EXIT 3.") -ForegroundColor Yellow
        $script:ownerCaseSkipped = $true
    } elseif ($null -eq $baPipe) {
        Check $false ("an Administrators-owned pipe for the owner case (" + $baWhy + ", HRESULT " + $baCode + ")")
    } else {
        try {
            $read = (Get-HordeLocalPipeSecurity -Pipe $baPipe).GetOwner([System.Security.Principal.SecurityIdentifier])
            Check ("$read" -ceq "$ba") ("CONTROL: the pipe's owner reads back as Administrators (" + $read + ")")
            $o = Open-HordeTransportLink -Transport $t -Endpoint $id -Role "hub" -TimeoutMs 5000
            Check ($o.state -ceq "unknown" -and "$($o.reason)" -like ("*owned by '" + $ba + "', not by this user*")) ("the hub refuses a pipe owned by another principal, served by its own interpreter at its own level (" + $o.reason + ")")
            if ($o.state -eq "known") { Close-HordeLink -Link (Get-HordeValue $o) }
        } finally { $baPipe.Dispose() }
    }

    # 5. A program that is not the node's interpreter, at THIS process's level, serves the pipe first.
    # Integrity cannot tell it apart; the image check refuses it. (At the same level the image check is
    # advisory - see transports/local/Transport.ps1 - but it does refuse this, and this kills the mutant
    # image-not-checked-on-open that the first round declared a survivor.)
    $id = New-Id
    $srv = Start-HordeSquatProbe -Exe $squat -Mode "serve" -Pipe (Get-HordeLocalPipeName -DeviceId $id) -Folder $lowDir
    $up = Wait-HordeLowLine -Out $srv.out -Pattern "serve: CREATED" -Ms 20000
    Check ($up) "CONTROL: the same-level probe did create the pipe first"
    $o = Open-HordeTransportLink -Transport $t -Endpoint $id -Role "hub" -TimeoutMs 5000
    Check ($o.state -ceq "unknown" -and "$($o.reason)" -like "*not a node's interpreter*") "the hub refuses a pipe served by a program that is not the node's interpreter"
    if ($o.state -eq "known") { Close-HordeLink -Link (Get-HordeValue $o) }
    $null = Wait-HordeLowLine -Out $srv.out -Pattern "done" -Ms 25000
    $srvText = ""; if (Test-Path -LiteralPath $srv.out) { $srvText = [System.IO.File]::ReadAllText($srv.out) }
    Check ($srvText -notmatch "client sent: \S") "and the probe received nothing from the hub"
} finally { if (Test-Path -LiteralPath $lowDir) { Remove-Item -LiteralPath $lowDir -Recurse -Force } }

Write-Host ""
Write-Host "--- the decisions, on their own ---" -ForegroundColor Cyan
Check ((Test-HordeLocalPeerIntegrity -Peer 4096 -Own 8192) -eq $false) "a low peer is below a medium end"
Check ((Test-HordeLocalPeerIntegrity -Peer 8192 -Own 8192) -eq $true) "an equal peer is accepted"
Check ((Test-HordeLocalPeerIntegrity -Peer 12288 -Own 8192) -eq $true) "a higher peer is accepted"
Check ((Test-HordeLocalPeerIntegrity -Peer -1 -Own 4096) -eq $false) "an unreadable peer integrity is below everything"
Check ((Test-HordeLocalPeerIntegrity -Peer 8192 -Own -1) -eq $false) "an end that cannot read its own integrity refuses rather than compares"
$psImage = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
Check ((Test-HordeLocalNodeImage -Image $psImage) -eq $true) "the node's own interpreter is an accepted image"
Check ((Test-HordeLocalNodeImage -Image $psImage.ToUpperInvariant()) -eq $true) "compared without case, as Windows paths are"
Check ((Test-HordeLocalNodeImage -Image "C:\Users\Public\powershell.exe") -eq $false) "a copy of it elsewhere is not"
Check ((Test-HordeLocalNodeImage -Image "") -eq $false) "an unreadable image is not"
# PowerShell 7 from its MSI install is a node's interpreter too (T-0450), and only that one path: the list
# must not grow by a look-alike (N, 2026-11-11).
$pf = $(if ("$env:ProgramW6432" -ne "") { $env:ProgramW6432 } else { $env:ProgramFiles })
$pwshImage = Join-Path $pf "PowerShell\7\pwsh.exe"
Check ((Test-HordeLocalNodeImage -Image $pwshImage) -eq $true) ("PowerShell 7's MSI install is an accepted image (" + $pwshImage + ")")
Check ((Test-HordeLocalNodeImage -Image (Join-Path $pf "PowerShell\7-preview\pwsh.exe")) -eq $false) "a preview build of it is not"
Check ((Test-HordeLocalNodeImage -Image (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\pwsh.exe")) -eq $false) "the Store's pwsh is not"
Check ((Test-HordeLocalNodeImage -Image "C:\Users\Public\PowerShell\7\pwsh.exe") -eq $false) "the same file under a user folder is not"
Check ((Test-HordeLocalNodeImage -Image (Join-Path ${env:ProgramFiles(x86)} "PowerShell\7\pwsh.exe")) -eq $false) "nor under the x86 Program Files"
Check (@($script:HordeLocalNodeImages).Count -eq 3) ("the list holds exactly three images: " + (@($script:HordeLocalNodeImages) -join "; "))

Write-Host ""
Write-Host "--- no gap between links: the name stays held while the node listens ---" -ForegroundColor Cyan
$id = New-Id
$pipe = Get-HordeLocalPipeName -DeviceId $id
$la = Start-HordeTransportListener -Transport $t -Endpoint $id
if ($la.state -eq "known") {
    $listener = Get-HordeValue $la
    try {
        $o = Open-HordeTransportLink -Transport $t -Endpoint $id -Role "hub" -TimeoutMs 5000
        $ka = Receive-HordeTransportLink -Listener $listener -TimeoutMs 5000
        Check ($o.state -ceq "known" -and $ka.state -ceq "known") "a hub link is opened and accepted"
        if ($o.state -eq "known") { Close-HordeLink -Link (Get-HordeValue $o) }
        if ($ka.state -eq "known") { Close-HordeLink -Link (Get-HordeValue $ka) }
        # Between this link and the next Accept, a squatter used to find the name free (review of PR #42).
        # "Taken" means created as a FIRST instance - a squatter's own new pipe of that name. The first
        # version asked for an ordinary instance with maxInstances 1, which fails against any existing
        # pipe for that reason alone and so proved nothing about the gap (review of PR #42, round 2).
        # Asking for 255 instead would add an instance, which at this process's own level is allowed and
        # is a different case: the instance adder, refused below the node's level by its label, above.
        $err = 0
        $took = [HordeLocalNative]::CreateServer(($script:HordeLocalPipeRoot + $pipe), ("D:(A;;GA;;;" + $me + ")"), $true, 4096, [ref]$err)
        Check ($took.IsInvalid) ("after a link closes, nobody can create the name afresh while the node still listens (first-instance create: error " + $err + ")")
        $took.Dispose()
        $o2 = Open-HordeTransportLink -Transport $t -Endpoint $id -Role "hub" -TimeoutMs 5000
        $ka2 = Receive-HordeTransportLink -Listener $listener -TimeoutMs 5000
        Check ($o2.state -ceq "known" -and $ka2.state -ceq "known") "and the next link is accepted on the instance that was already waiting"
        if ($o2.state -eq "known") { Close-HordeLink -Link (Get-HordeValue $o2) }
        if ($ka2.state -eq "known") { Close-HordeLink -Link (Get-HordeValue $ka2) }
    } finally { Stop-HordeTransportListener -Listener $listener }
} else { Check $false "a listener for the gap case" }

Write-Host ""
Write-Host "--- NETWORK: a connection over the network is refused, measured ---" -ForegroundColor Cyan
# Over \\localhost\pipe the connection arrives through the server service as a network logon, which
# is what the NETWORK deny and PIPE_REJECT_REMOTE_CLIENTS exist to refuse. CONTROL: an ordinary pipe,
# opened the same way, connects - so a refusal here is the pipe's, not a missing server service.
$plainName = "horde-test-plain-" + [guid]::NewGuid().ToString("N")
$plain = New-Object System.IO.Pipes.NamedPipeServerStream($plainName, [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous)
$plainOk = $false
try { $rc = New-Object System.IO.Pipes.NamedPipeClientStream("localhost", $plainName, [System.IO.Pipes.PipeDirection]::InOut); $rc.Connect(8000); $plainOk = $true; $rc.Dispose() } catch { }
$plain.Dispose()
if (-not $plainOk) {
    Write-Host "  [SKIP] an ordinary pipe cannot be reached over \\localhost here (no server service?), so the NETWORK refusal is unproven on this machine" -ForegroundColor Yellow
} else {
    Check ($plainOk) "CONTROL: an ordinary pipe is reachable over \\localhost"
    $id = New-Id
    $la = Start-HordeTransportListener -Transport $t -Endpoint $id
    if ($la.state -eq "known") {
        $listener = Get-HordeValue $la
        try {
            $why = ""
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try { $rc = New-Object System.IO.Pipes.NamedPipeClientStream("localhost", (Get-HordeLocalPipeName -DeviceId $id), [System.IO.Pipes.PipeDirection]::InOut); $rc.Connect(8000); $why = "CONNECTED"; $rc.Dispose() }
            catch { $e = $_.Exception; while ($null -ne $e.InnerException) { $e = $e.InnerException }; $why = $e.GetType().Name }
            Write-Host ("  over the network: " + $why + " after " + $sw.ElapsedMilliseconds + " ms") -ForegroundColor DarkGray
            Check ($why -ceq "UnauthorizedAccessException") "the node's pipe refuses a connection over the network, at once and as access denied"
        } finally { Stop-HordeTransportListener -Listener $listener }
    } else { Check $false "a listener for the network case" }
}

Write-Host ""
Write-Host "--- clients that connect and close at once do not wedge the listener ---" -ForegroundColor Cyan
# Review of PR #42, round 2: one client that connected and closed before Accept ran made
# WaitForConnectionAsync throw "The pipe is being closed" outside the try, so the listener kept the
# dead instance and every later Accept failed the same way, for ever.
$id = New-Id
$pipe = Get-HordeLocalPipeName -DeviceId $id
$la = Start-HordeTransportListener -Transport $t -Endpoint $id
if ($la.state -eq "known") {
    $listener = Get-HordeValue $la
    try {
        $churned = 0
        for ($i = 0; $i -lt 10; $i++) {
            $c = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipe, [System.IO.Pipes.PipeDirection]::InOut)
            try { $c.Connect(3000); $churned++ } catch { }
            $c.Dispose()
            $null = Receive-HordeTransportLink -Listener $listener -TimeoutMs 300
        }
        Check ($churned -ge 1) ("CONTROL: clients did connect and close (" + $churned + " of 10)")
        $o = Open-HordeTransportLink -Transport $t -Endpoint $id -Role "hub" -TimeoutMs 5000
        $ka = Receive-HordeTransportLink -Listener $listener -TimeoutMs 5000
        Check ($o.state -ceq "known" -and $ka.state -ceq "known") ("after them, a normal client is accepted (open: " + $o.state + ", accept: " + $ka.state + " " + $ka.reason + ")")
        if ($o.state -eq "known") { Close-HordeLink -Link (Get-HordeValue $o) }
        if ($ka.state -eq "known") { Close-HordeLink -Link (Get-HordeValue $ka) }
    } finally { Stop-HordeTransportListener -Listener $listener }
} else { Check $false "a listener for the churn case" }

Write-Host ""
Write-Host "--- small things the second review found ---" -ForegroundColor Cyan
$id = New-Id
$la = Start-HordeTransportListener -Transport $t -Endpoint $id
if ($la.state -eq "known") {
    $listener = Get-HordeValue $la
    try {
        $sec = (Get-HordeLocalPipeSecurity -Pipe $listener.state.server)
        Check ($sec.AreAccessRulesCanonical -eq $true) "the DACL is in canonical order: the NETWORK deny comes before the allow"
    } finally { Stop-HordeTransportListener -Listener $listener }
} else { Check $false "a listener for the DACL-order case" }
$bad = New-Object Microsoft.Win32.SafeHandles.SafePipeHandle([IntPtr]::new(-1), $false)
Check ([HordeLocalNative]::LabelSddl($bad) -ceq "") "the label of an invalid handle is empty, not this process's own label"
# A RUN THAT SKIPPED THE OWNER CASE IS NOT A PASS TO A GATE (review of PR #91, G1): it exits 3, as
# test-projection does when it skips, so anything that expects 0 fails loudly, and tools\Mutate.ps1
# accepts 3 only from a spec that declares it (PassCodes).
$banner = "the local pipe admits only its own user, and refuses a pipe it did not make"
$passCode = 0
if ($script:ownerCaseSkipped) { $banner = "OWNER CASE SKIPPED (this token cannot make Administrators an owner), EXIT 3: " + $banner; $passCode = 3 }
Complete-HordeSuite -Success $banner -PassCode $passCode
