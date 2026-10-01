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
            if ($r.ok) { & $r.channel.close $r.channel }
            $null = Wait-HordeLowLine -Out $hold.out -Pattern "done" -Ms 10000
            $holdText = ""; if (Test-Path -LiteralPath $hold.out) { $holdText = [System.IO.File]::ReadAllText($hold.out) }
            Check ($holdText -match "hold: CONNECTED") "CONTROL: the low client did reach the node past the low label"
        } finally { & $t.stop $state }
    }

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
        $sec = $listener.state.server.GetAccessControl()
        Check ($sec.AreAccessRulesCanonical -eq $true) "the DACL is in canonical order: the NETWORK deny comes before the allow"
    } finally { Stop-HordeTransportListener -Listener $listener }
} else { Check $false "a listener for the DACL-order case" }
Complete-HordeSuite -Success "the local pipe admits only its own user, and refuses a pipe it did not make"
