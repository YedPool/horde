# DOES `horde node serve`, STARTED AS A USER WOULD, ANSWER A HUB OVER THE REAL LOCAL PIPE?
#
# Remote plan step R12a's T1 gate and its end-to-end run in one: the real horde CLI is started as its own
# process (`horde.ps1 node serve -MaxLinks 1`), and this suite is the hub, dialling the node's pipe
# \\.\pipe\horde-node-<deviceId> through transports/local. The node's stores are fakes: HORDE_HOME and
# USERPROFILE point at folders this suite makes, and WEZFLEET_ROOT at the projection suite's fixture
# fleet, so the node's projection reads fixture records and no agent store at all - the agent stores
# are then unreadable, which is exactly what complete must report.
#
# LOCAL ONLY. The local transport admits only this user at this integrity level, from an interactive
# logon; the always-on box's gate runs suites detached, so this suite runs here (as test-local does).
# Every process it starts it stops by its own handle, and every folder it makes it removes.
#
# WHY IT LIVES HERE, beside test-local.ps1: it dials the local transport's own pipe and needs that
# transport's interactive logon, so it names the transport (its pipe prefix), and a file outside
# transports/local/ may not (tools/HostNames.ps1, CONTRIBUTING rule 14).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Platform", "Namespace")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "transports\Port.ps1")
foreach ($t in @(Get-HordeTransportFiles)) { . $t }
. (Join-Path $root "remote\Protocol.ps1")

$work = Join-Path $env:TEMP ("horde-node-local-" + [guid]::NewGuid().ToString("N"))
$homeDir = Join-Path $work "home"
$profileDir = Join-Path $work "profile"
$fleet = Join-Path $root "test\fixtures\projection\fleet\wezfleet"
$outFile = Join-Path $work "node.out.txt"
$errFile = Join-Path $work "node.err.txt"
$saved = @{ HORDE_HOME = $env:HORDE_HOME; USERPROFILE = $env:USERPROFILE; WEZFLEET_ROOT = $env:WEZFLEET_ROOT }
$node = $null
$link = $null

function Line { param($Frame) $b = ConvertTo-HordeFrameBytes -Frame $Frame; return [System.Text.Encoding]::ASCII.GetString($b.bytes, 0, $b.bytes.Length - 1) }
function Talk {
    param($Frame)
    $null = Send-HordeLinkFrame -Link $script:link -Frame (Line $Frame)
    # 180 s: sessions.list over the fixture fleet's 31 sessions builds a projection (11.4 s, measured
    # 2026-10-02) and a list (3.8 s), and encodes it (0.13 s at 32 sessions since fix/link-writer-speed,
    # measured 2026-10-03). A machine Windows is throttling runs several times slower.
    $got = Receive-HordeLinkFrame -Link $script:link -TimeoutMs 180000
    if ("$($got.state)" -cne "known") { Write-Host ("         no answer: " + $got.reason) -ForegroundColor DarkYellow; return $null }
    $d = ConvertFrom-HordeFrameBytes -Bytes ([System.Text.Encoding]::ASCII.GetBytes("$($got.value)"))
    if (-not $d.ok) { Write-Host ("         refused by the hub's decoder: " + $d.reason) -ForegroundColor DarkYellow; return $null }
    return $d.frame
}
function Req {
    param([string]$Verb, $ArgsObject = $null)
    if ($null -eq $ArgsObject) { $ArgsObject = [pscustomobject]@{} }
    return [pscustomobject][ordered]@{ v = 1; kind = "req"; id = (New-HordeLinkFrameId); seq = 2; ts = (Get-HordeLinkTime); verb = $Verb; requestId = (New-HordeLinkFrameId); issuedAt = (Get-HordeLinkTime); args = $ArgsObject }
}

try {
    New-Item -ItemType Directory -Path $homeDir | Out-Null
    [void](New-HordeTestProfile $profileDir)
    # The child inherits this environment; it is restored in finally.
    $env:HORDE_HOME = $homeDir
    $env:USERPROFILE = $profileDir
    $env:WEZFLEET_ROOT = $fleet
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + (Join-Path $root "horde.ps1") + "`" node serve -MaxLinks 1 -IdleSeconds 60"
    # With USERPROFILE moved, PowerShell 5.1 cannot resolve LocalApplicationData and writes its module
    # analysis cache to a relative path, inside whatever folder the child starts in (a Microsoft\ folder
    # appeared in the worktree after the first run, 2026-10-02). Start the child in the work folder.
    $psi.WorkingDirectory = $work
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $node = [System.Diagnostics.Process]::Start($psi)
    $outTask = $node.StandardOutput.ReadToEndAsync()
    $errTask = $node.StandardError.ReadToEndAsync()

    # The node makes its device id on first start (core/Device.ps1); its pipe is named by it.
    $nodeFile = Join-Path $homeDir "node\node.json"
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path -LiteralPath $nodeFile) -and (Get-Date) -lt $deadline -and -not $node.HasExited) { Start-Sleep -Milliseconds 200 }
    Check (Test-Path -LiteralPath $nodeFile) "the node made its device id in the home it was given"
    $deviceId = ([regex]::Match([System.IO.File]::ReadAllText($nodeFile), '"deviceId":"([0-9a-f-]{36})"')).Groups[1].Value
    Check ($deviceId -cmatch '^[0-9a-f-]{36}$') ("the device id reads back (" + $deviceId + ")")

    $tr = Resolve-HordeLinkTransport -Name "local"
    Check ("$($tr.state)" -ceq "known") "the local transport is the link's, peer-authenticated"
    $open = $null
    while ((Get-Date) -lt $deadline -and -not $node.HasExited) {
        $open = Open-HordeTransportLink -Transport $tr.value -Endpoint $deviceId -Role "hub" -TimeoutMs 2000
        if ("$($open.state)" -ceq "known") { break }
        Start-Sleep -Milliseconds 300
    }
    Check ($null -ne $open -and "$($open.state)" -ceq "known") ("the hub dials the node's pipe (" + "$($open.reason)" + ")")
    # node is declared sustained (cli/commands/node.ps1), so horde.ps1 opted the node out of power
    # throttling before it listened; read back from the node process itself by its handle, as
    # test-platform-throttling reads a child (review of PR #81, F2).
    $thr = Get-HordeThrottlingState -Process $node
    Check ("$($thr.state)" -ceq "known" -and $thr.value.controlMask -eq 1 -and $thr.value.stateMask -eq 0 -and $thr.value.optedOut -eq $true) ("the node process reads back opted out of power throttling: ControlMask 1, StateMask 0 (" + $thr.value.controlMask + "/" + $thr.value.stateMask + ")")
    if ("$($open.state)" -ceq "known") {
        $script:link = $open.value
        $t = Get-HordeLinkTime
        $hello = [pscustomobject][ordered]@{ v = 1; kind = "hello"; id = (New-HordeLinkFrameId); seq = 1; ts = $t; hello = [pscustomobject][ordered]@{ role = "hub"; id = "7c9e6679-7425-40de-944b-e07fc1f90ae7"; name = "test-hub"; protocols = @(1); verbsVersions = @(1); hordeVersion = "0.1.0"; t1 = $t } }
        $hi = Talk $hello
        Check ($null -ne $hi -and "$($hi.kind)" -ceq "hello" -and "$($hi.hello.role)" -ceq "node" -and "$($hi.hello.id)" -ceq $deviceId) "the node's hello names the device the pipe is named by"
        $info = Talk (Req "node.info")
        Check ($null -ne $info -and "$($info.result.value.deviceId)" -ceq $deviceId -and @($info.result.value.harnesses).Count -ge 1) "node.info answers this node's manifest over the pipe"
        $list = Talk (Req "sessions.list")
        $sessions = @()
        if ($null -ne $list) { $sessions = @($list.result.value.sessions) }
        Check ($null -ne $list -and $sessions.Count -ge 1) ("sessions.list answers the fixture fleet's sessions (" + $sessions.Count + ")")
        Check ($null -ne $list -and $list.result.value.complete.value -eq $false -and "$($list.result.value.complete.reason)" -clike "*not every store*") "with the agent stores absent, complete is known false and says which stores"
        $placed = @($sessions | Where-Object { "$($_.pid.ns.device)" -ceq $deviceId -and "$($_.pid.ns.space)" -ceq "windows" })
        Check ($sessions.Count -ge 1 -and $placed.Count -eq $sessions.Count) "every session's pid is placed on this device, in the windows space"
        if ($sessions.Count -ge 1) {
            $id = "$($sessions[0].sessionId)"
            $one = Talk (Req "session.get" ([pscustomobject]@{ sessionId = $id }))
            Check ($null -ne $one -and "$($one.result.state)" -ceq "known" -and "$($one.result.value.sessionId)" -ceq $id) "session.get answers one listed session"
        }
        $spawn = Talk (Req "request.status" ([pscustomobject]@{ requestId = (New-HordeLinkFrameId) }))
        # Since the act path's A3 a node serves acts unless -ReadOnly, so it keeps a request journal: a
        # request it never saw is absent from it. (The no-journal answer is test-node-serve's.)
        Check ($null -ne $spawn -and "$($spawn.result.state)" -ceq "absent") "a node that acts keeps a request journal: request.status for an id it never saw is absent"
        Check (Test-Path -LiteralPath (Join-Path $homeDir "node\requests\journal.json")) "and the journal is in the node's home"
        $null = Send-HordeLinkFrame -Link $script:link -Frame (Line (New-HordeLinkBye -Code "shutdown" -Reason "the hub is finished" -Seq 9))
    }
    $exited = $node.WaitForExit(60000)
    $out = ""
    if ($exited) { $node.WaitForExit(); $out = "$($outTask.Result)" }
    Check ($exited -and $node.ExitCode -eq 0) ("the node exits 0 after its one link (exit " + $(if ($exited) { $node.ExitCode } else { "none" }) + ")")
    Check ($out -clike "*served 1 link(s)*" -and $out -clike "*closed by the protocol*") "and says it served one link, ended on the hub's bye"
    Check (-not (Test-Path -LiteralPath (Join-Path $root "Microsoft"))) "the node wrote nothing into the repository it was started from"
    if (-not $exited -or $node.ExitCode -ne 0) { Write-Host ("         node stdout: " + $out) -ForegroundColor DarkYellow; Write-Host ("         node stderr: " + "$($errTask.Result)") -ForegroundColor DarkYellow }
} finally {
    if ($null -ne $script:link) { Close-HordeLink -Link $script:link }
    # Only the process this suite started, by its own handle.
    if ($null -ne $node -and -not $node.HasExited) { try { $node.Kill() } catch { }; $null = $node.WaitForExit(10000) }
    foreach ($k in @($saved.Keys)) { if ($null -eq $saved[$k]) { Remove-Item -Path ("env:" + $k) -ErrorAction SilentlyContinue } else { Set-Item -Path ("env:" + $k) -Value $saved[$k] } }
    if ((Split-Path -Leaf $work) -match '^horde-node-local-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check ("$env:USERPROFILE" -ceq "$($saved['USERPROFILE'])" -and "$env:HORDE_HOME" -ceq "$($saved['HORDE_HOME'])") "the suite's environment is restored"

Complete-HordeSuite -Success "horde node serve, started as a user would, answers a hub over the real local pipe and ends on its bye"
