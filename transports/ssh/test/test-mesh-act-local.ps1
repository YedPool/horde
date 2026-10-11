# DOES `horde session` START, REPORT AND CLOSE A SESSION ON A NODE THAT DIALS THE HUB OVER SSH - THE WHOLE
# MESH PATH, AS THE FOUNDER WILL RUN IT, ON ONE MACHINE?
#
# Mesh v1, remote plan R19 over R17c (cli/HubCarry.ps1). Two Horde homes on this machine, each enrolled
# with the other through the real CLI, as planning/first-live-link-ov615.md has the founder do it across
# two: the HUB home runs `horde hub init`, `horde hub enroll`, `horde listen` (its own child sshd on
# 127.0.0.1, transports/ssh/Listen.ps1), `horde hub serve -Listen`, `horde session` and `horde nodes`; the
# NODE home runs `horde node init` and `horde node pin`, then dials the hub's listener over ssh with its
# own key and pin, through the real dial loop and act path (MeshNode.ps1) - with the fake host and
# harness of test/fixtures/node-serve/act-world.ps1 where a real terminal and a real session would be,
# so nothing is started and no pane is opened. Proven, in order:
#   - the node dials in through the listener and the hub hears it: `horde nodes` lists it, dialled;
#   - `horde session spawn -Node <node>` is carried over the dialled link and answered DONE with the
#     session and its process; the prompt reached the session by file;
#   - `horde session status` reports the same; two spawns at once both go over the node's link;
#   - a spawn above the node's own daily cap comes back REFUSED by the node, with its reason;
#   - `horde session close` closes the session by the process its spawn named;
#   - `horde hub revoke` refuses the next request before anything is written.
#
# THE MACHINE IS LEFT AS IT WAS, CHECKED, NOT ASSUMED (test-listen-local.ps1's rule): the sshd service, the
# OpenSSH-Server-In-TCP rule, port 22, C:\ProgramData\ssh and ~/.ssh are compared at the end, and no
# process of this suite may survive it. LOCAL ONLY (machine-bound, test/lib/SuiteFiles.ps1): this
# machine's OpenSSH Server, and the hub's local pipe from an interactive logon. Without sshd.exe the
# suite exits 3, never green.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "transports\Port.ps1")
. (Join-Path $root "transports\ssh\Transport.ps1")
. (Join-Path $here "ListenFixture.ps1")

$limitSeconds = 600
$clock = [System.Diagnostics.Stopwatch]::StartNew()
function Left { param([int]$Ms) return [int][Math]::Max(1, [Math]::Min($Ms, ($limitSeconds * 1000) - $clock.ElapsedMilliseconds - 15000)) }
$skipped = ""
$before = Get-ListenMachine
Write-Host ("  at the start: sshd service " + $before.service + ", firewall rule " + $before.firewall + ", " + $before.port22 + " listener(s) on port 22") -ForegroundColor DarkGray
$work = ""
$job = $null
$procs = New-Object System.Collections.ArrayList
$port = 0

function New-MeshStart {
    # powershell.exe running -File <script> with -Arguments, HORDE_HOME set to -HomeDir, PSModulePath cleared
    # (a 5.1 child must not load 7's modules), stdin closed at once, stdout and stderr read as they come.
    param([Parameter(Mandatory = $true)][string]$HomeDir, [Parameter(Mandatory = $true)][string]$Script, [string[]]$Arguments = @(), [switch]$ByLine)
    $quoted = @($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } })
    $psi = New-Object System.Diagnostics.ProcessStartInfo("powershell.exe", ("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + $Script + "`" " + ($quoted -join " ")))
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $work
    $psi.EnvironmentVariables["HORDE_HOME"] = $HomeDir
    $psi.EnvironmentVariables["PSModulePath"] = ""
    $p = [System.Diagnostics.Process]::Start($psi)
    try { [HordeSshNative]::Assign($job, $p.Handle) } catch { try { $p.Kill() } catch { }; throw }
    $p.StandardInput.Close()
    if ($ByLine) { return [pscustomobject]@{ process = $p; out = $null; err = $p.StandardError.ReadToEndAsync() } }
    return [pscustomobject]@{ process = $p; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync() }
}
function Invoke-Horde {
    # One horde command to its end: { code; out }.
    param([Parameter(Mandatory = $true)][string]$HomeDir, [string[]]$HordeArgs = @(), [int]$Ms = 120000)
    $r = New-MeshStart -HomeDir $HomeDir -Script (Join-Path $root "horde.ps1") -Arguments $HordeArgs
    $ended = $r.process.WaitForExit((Left $Ms))
    if (-not $ended) { try { $r.process.Kill() } catch { } }
    $out = (Get-ListenText $r.out) + (Get-ListenText $r.err)
    return [pscustomobject]@{ code = $(if ($ended) { $r.process.ExitCode } else { -1 }); out = $out }
}
function Start-Horde {
    # A long-running horde command, kept in the suite's job until the teardown.
    param([Parameter(Mandatory = $true)][string]$HomeDir, [string[]]$HordeArgs = @(), [switch]$ByLine)
    $r = New-MeshStart -HomeDir $HomeDir -Script (Join-Path $root "horde.ps1") -Arguments $HordeArgs -ByLine:$ByLine
    [void]$procs.Add($r)
    return $r
}
function Get-Rid { param([string]$Text) $m = [regex]::Match($Text, 'request ([0-9a-f-]{36})'); if ($m.Success) { return $m.Groups[1].Value } return "" }
function Get-Sid { param([string]$Text) $m = [regex]::Match($Text, ' session ([0-9a-f-]{36})'); if ($m.Success) { return $m.Groups[1].Value } return "" }

try {
    if (-not (Test-Path -LiteralPath $script:ListenSshdExe -PathType Leaf)) { $skipped = "no sshd.exe at " + $script:ListenSshdExe }
    $user = [System.Environment]::UserName.ToLowerInvariant()
    if ($skipped -eq "" -and $user -cnotmatch '\A[a-z_][a-z0-9_-]{0,31}\z') { $skipped = "this account's name '" + $user + "' is not one the ssh endpoint grammar takes" }
    if ($skipped -eq "") {
        $work = New-ListenWork
        $job = [HordeSshNative]::NewKillOnCloseJob()
        $hubHome = Join-Path $work "hub-home"
        $nodeHome = Join-Path $work "node-home"
        $clone = Join-Path $work "code\app"
        New-Item -ItemType Directory -Path $hubHome, (Join-Path $nodeHome "node"), $clone -Force | Out-Null

        Write-Host ""
        Write-Host "--- enrolment, both ways, through the real CLI ---" -ForegroundColor Cyan
        $hi = Invoke-Horde -HomeDir $hubHome -HordeArgs @("hub", "init")
        $pin = [regex]::Match($hi.out, 'horde node pin -Hub ([0-9a-f-]{36}) -HostKey "([^"]+)"')
        Check ($hi.code -eq 0 -and $pin.Success) ("horde hub init prints the pin a node runs (exit " + $hi.code + ")")
        $hubId = $pin.Groups[1].Value
        $ni = Invoke-Horde -HomeDir $nodeHome -HordeArgs @("node", "init")
        $en = [regex]::Match($ni.out, 'horde hub enroll -Device ([0-9a-f-]{36}) -Key "([^"]+)"')
        Check ($ni.code -eq 0 -and $en.Success) ("horde node init prints the enrolment the hub runs (exit " + $ni.code + ")")
        $nodeId = $en.Groups[1].Value
        Check ($nodeId -ne "" -and $nodeId -cne $hubId) "two homes, two devices"
        $np = Invoke-Horde -HomeDir $nodeHome -HordeArgs @("node", "pin", "-Hub", $hubId, "-HostKey", $pin.Groups[2].Value)
        Check ($np.code -eq 0) ("the node pins the hub's host key (" + $np.out.Trim() + ")")
        $he = Invoke-Horde -HomeDir $hubHome -HordeArgs @("hub", "enroll", "-Device", $nodeId, "-Key", $en.Groups[2].Value)
        Check ($he.code -eq 0 -and $he.out -clike "*enrolled*") ("the hub enrols the node (" + $he.out.Trim() + ")")
        # What the node lets the hub start: the fixture repository and profile, at most three a day.
        $policy = '{ "schemaVersion": 1, "repos": [ { "repoId": "github.com/example/app", "path": "' + $clone.Replace([string][char]92, ([string][char]92) * 2) + '" } ], "profiles": ["alpha"], "dailySpawnCap": 3 }'
        [System.IO.File]::WriteAllText((Join-Path $nodeHome "node\policy.json"), $policy)

        Write-Host ""
        Write-Host "--- the link: horde listen, horde hub serve -Listen, and the node dialling in ---" -ForegroundColor Cyan
        $port = Get-ListenFreePort
        $listen = Start-Horde -HomeDir $hubHome -HordeArgs @("listen", "-Port", "$port", "-Seconds", "$limitSeconds") -ByLine
        $first = Read-ListenLine -Reader $listen.process.StandardOutput -Ms (Left 60000)
        Check ("$first" -like ("listening on 127.0.0.1:" + $port + " for hub " + $hubId + "*")) ("horde listen is up on loopback (" + $first + ")")
        $serve = Start-Horde -HomeDir $hubHome -HordeArgs @("hub", "serve", "-Listen", "-IntervalSeconds", "3")
        $endpoint = $user + "@127.0.0.1:" + $port + "/" + $hubId
        $node = New-MeshStart -HomeDir $nodeHome -Script (Join-Path $here "MeshNode.ps1") -Arguments @("-Root", $root, "-Endpoint", $endpoint)
        [void]$procs.Add($node)
        $heard = $null
        $deadline = [datetime]::UtcNow.AddMilliseconds((Left 90000))
        while ([datetime]::UtcNow -lt $deadline) {
            $nj = Invoke-Horde -HomeDir $hubHome -HordeArgs @("nodes", "-Json")
            $rep = $null; try { $rep = (($nj.out -split "`n") | Where-Object { $_.Trim().StartsWith("{") } | Select-Object -First 1) | ConvertFrom-Json } catch { }
            $heard = @($rep.nodes | Where-Object { "$($_.deviceId)" -ceq $nodeId -and "$($_.heard.state)" -ceq "known" })
            if ($heard.Count -eq 1) { break }
            Start-Sleep -Milliseconds 1000
        }
        Check ($null -ne $heard -and $heard.Count -eq 1 -and "$($heard[0].route)" -ceq "dialled" -and $heard[0].enrolment.live -eq $true) ("horde nodes lists the node, dialled, enrolled and heard (" + $(if ($null -ne $node.process -and $node.process.HasExited) { "the node exited: " + (Get-ListenText $node.err) } else { "node running" }) + ")")

        Write-Host ""
        Write-Host "--- spawn, status, two at once, the cap, close: all over the node's one dialled link ---" -ForegroundColor Cyan
        $spawn = @("session", "spawn", "-Node", $nodeId, "-Run", "20261011-120000-mesh", "-Profile", "alpha", "-Repo", "github.com/example/app", "-Permission", "edits", "-TimeoutSeconds", "120")
        $sp = Invoke-Horde -HomeDir $hubHome -HordeArgs @($spawn + @("-Label", "E", "-Prompt", "Reply with the machine name.", "-Title", "mesh orc"))
        $rid = Get-Rid $sp.out
        $sid = Get-Sid $sp.out
        Check ($sp.code -eq 0 -and $sp.out -clike "DONE session.spawn request * session * pid * procStart *" -and $sid -ne "") ("the spawn crossed the dialled link and came back DONE, with its session and process (" + $sp.out.Trim() + ")")
        $promptFile = Join-Path $nodeHome ("node\spawned\" + $sid + "\prompt.txt")
        Check ((Test-Path -LiteralPath $promptFile) -and [System.IO.File]::ReadAllText($promptFile) -ceq "Reply with the machine name.") "the prompt reached the session by file on the node, exactly"
        $st = Invoke-Horde -HomeDir $hubHome -HordeArgs @("session", "status", "-RequestId", $rid, "-TimeoutSeconds", "60")
        Check ($st.code -eq 0 -and $st.out -clike ("DONE session.spawn request " + $rid + " session " + $sid + "*")) ("horde session status reports the same (" + $st.out.Trim() + ")")
        # Two at once, as two people would type them: both ride the node's link.
        $a = New-MeshStart -HomeDir $hubHome -Script (Join-Path $root "horde.ps1") -Arguments @($spawn + @("-Label", "F", "-Prompt", "second"))
        $b = New-MeshStart -HomeDir $hubHome -Script (Join-Path $root "horde.ps1") -Arguments @($spawn + @("-Label", "G", "-Prompt", "third"))
        $null = $a.process.WaitForExit((Left 150000)); $null = $b.process.WaitForExit((Left 150000))
        $ao = Get-ListenText $a.out; $bo = Get-ListenText $b.out
        Check ($ao -clike "DONE session.spawn*" -and $bo -clike "DONE session.spawn*" -and (Get-Sid $ao) -cne (Get-Sid $bo)) ("two spawns at once are two sessions on the one node (" + $ao.Trim() + " | " + $bo.Trim() + ")")
        $over = Invoke-Horde -HomeDir $hubHome -HordeArgs @($spawn + @("-Label", "H", "-Prompt", "fourth"))
        Check ($over.out -clike "REFUSED session.spawn request *daily spawn cap of 3 is reached*") ("a fourth, above the node's own cap of 3, is REFUSED by the node, saying why (" + $over.out.Trim() + ")")
        $cl = Invoke-Horde -HomeDir $hubHome -HordeArgs @("session", "close", "-SessionId", $sid, "-TimeoutSeconds", "120")
        Check ($cl.code -eq 0 -and $cl.out -clike ("DONE session.close request * session " + $sid + "*")) ("the close crossed the link and the session is closed by its process (" + $cl.out.Trim() + ")")
        $rec = Get-Content -LiteralPath (Join-Path $nodeHome ("node\spawned\" + $sid + ".json")) -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        Check ($null -ne $rec -and "$($rec.closedAt)" -ne "") ("and the node's own record of it says closed (" + "$($rec.outcome)" + ")")

        Write-Host ""
        Write-Host "--- revoke: the next request is refused before anything is written ---" -ForegroundColor Cyan
        $rv = Invoke-Horde -HomeDir $hubHome -HordeArgs @("hub", "revoke", "-Device", $nodeId)
        Check ($rv.code -eq 0) ("horde hub revoke revokes the node (" + $rv.out.Trim() + ")")
        $before5 = @(Get-ChildItem -LiteralPath (Join-Path $hubHome "hub\acts") -Filter "*.json" -File).Count
        $nr = Invoke-Horde -HomeDir $hubHome -HordeArgs @($spawn + @("-Label", "J", "-Prompt", "fifth"))
        Check ($nr.code -ne 0 -and $nr.out -clike "*not enrolled live*revoked*" -and @(Get-ChildItem -LiteralPath (Join-Path $hubHome "hub\acts") -Filter "*.json" -File).Count -eq $before5) ("a spawn to the revoked node is refused, nothing written (" + $nr.out.Trim() + ")")
        $nt = Invoke-Horde -HomeDir $hubHome -HordeArgs @("nodes")
        Check ($nt.out.Contains("[dialled, NOT ENROLLED: ")) ("horde nodes says the node is no longer enrolled (" + $nt.out.Trim() + ")")
    }
} finally {
    Write-Host ""
    Write-Host "--- teardown: nothing of this suite survives, and the machine is as it was ---" -ForegroundColor Cyan
    foreach ($p in @($procs)) { try { if (-not $p.process.HasExited) { $p.process.Kill() } } catch { }; $null = $p.process.WaitForExit(15000) }
    if ($null -ne $job) { $job.Dispose() }
    if ($skipped -eq "") {
        Start-Sleep -Milliseconds 500
        $left = @(Stop-ListenLeftovers -Markers @($work, "MeshNode.ps1"))
        Check ($left.Count -eq 0) ("no listen, serve, node, sshd or attach process of this suite survives" + $(if ($left.Count -gt 0) { " (found and stopped: " + ($left -join ", ") + ")" } else { "" }))
        if ($port -gt 0) { Check ((Get-ListenListeners -Port $port) -eq 0) ("nothing listens on port " + $port + " any more") }
    }
    if ($work -ne "" -and (Split-Path -Leaf $work) -match '^horde-listen-[0-9a-f]{12}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    $after = Get-ListenMachine
    foreach ($k in @("service", "firewall", "port22", "programData", "userSsh")) {
        $same = ("$($after.$k)" -ceq "$($before.$k)")
        if (-not $same) { Write-Host ("  !!! THE MACHINE CHANGED: " + $k + " was '" + $before.$k + "' and is '" + $after.$k + "' now. Nothing was put back; look at it.") -ForegroundColor Red }
        Check $same ("the " + $k + " is as it was at the start")
    }
}
if ($skipped -ne "") {
    Write-Host ("  [SKIP] " + $skipped) -ForegroundColor Yellow
    Complete-HordeSuite -Success ("SKIPPED: " + $skipped) -PassCode 3
}
Complete-HordeSuite -Success "horde session starts, reports and closes a session on a node that dials the hub over ssh, carried by horde hub serve over the node's one link"
