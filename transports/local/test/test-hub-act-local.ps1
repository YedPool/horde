# DOES `horde session`, RUN AS A USER WOULD, REACH `horde node serve` OVER THE REAL LOCAL PIPE AND COME
# BACK WITH THE NODE'S ANSWER - WITHOUT STARTING ANYTHING?
#
# The act path's A4, end to end through the real horde CLI: `horde node serve -MaxLinks 2` is started as
# its own process; `horde session spawn` asks it to start a session; `horde session status` asks what
# became of the request. The node's policy lets a hub start nothing today (its daily cap is 0), so the
# spawn is REFUSED by the node before any launch plan is made: the round trip is real and nothing is
# started. As a second line, the node finds its own terminal only in the user profile's socket folder,
# and USERPROFILE here is an empty folder this suite makes, so even a broken policy check would find no
# terminal to start in; and every terminal call carries --no-auto-start, so none is started for it.
#
# The stores are fakes: HORDE_HOME and USERPROFILE point at folders this suite makes.
#
# LOCAL ONLY, and why it lives here: the local transport admits only this user at this integrity level,
# from an interactive logon, and this file names the transport's pipe (CONTRIBUTING rule 14). Every
# process it starts it stops by its own handle, and every folder it makes it removes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
# The hosts' acting adapters, found by folder (CONTRIBUTING 14), for the isolation probe below.
foreach ($f in @("Tristate", "HostAct", "ReadShared")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
foreach ($f in @(Get-HordeHostActorFiles -Root $root)) { . $f }

$work = Join-Path $env:TEMP ("horde-act-local-" + [guid]::NewGuid().ToString("N"))
$homeDir = Join-Path $work "home"
$profileDir = Join-Path $work "profile"
$clone = Join-Path $work "code\app"
$saved = @{ HORDE_HOME = $env:HORDE_HOME; USERPROFILE = $env:USERPROFILE }
$node = $null

function New-HordeTestStart {
    param([string]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + (Join-Path $root "horde.ps1") + "`" " + $Arguments
    $psi.WorkingDirectory = $work
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    return $psi
}
function Invoke-HordeTestRun {
    param([string]$Arguments)
    $p = [System.Diagnostics.Process]::Start((New-HordeTestStart $Arguments))
    try {
        $errTask = $p.StandardError.ReadToEndAsync()
        $outTask = $p.StandardOutput.ReadToEndAsync()
        if (-not $p.WaitForExit(180000)) { try { $p.Kill() } catch { }; $null = $p.WaitForExit(10000); return [pscustomobject]@{ code = -1; out = ""; err = "timed out" } }
        $p.WaitForExit()
        return [pscustomobject]@{ code = $p.ExitCode; out = "$($outTask.Result)"; err = "$($errTask.Result)" }
    } finally { $p.Dispose() }
}

try {
    New-Item -ItemType Directory -Path $homeDir, $clone, (Join-Path $homeDir "node") -Force | Out-Null
    [void](New-HordeTestProfile $profileDir)
    $policy = '{ "schemaVersion": 1, "repos": [ { "repoId": "github.com/example/app", "path": "' + $clone.Replace([string][char]92, ([string][char]92) * 2) + '" } ], "profiles": ["alpha"], "dailySpawnCap": 0 }'
    [System.IO.File]::WriteAllText((Join-Path $homeDir "node\policy.json"), $policy)
    $env:HORDE_HOME = $homeDir
    $env:USERPROFILE = $profileDir
    # THE ISOLATION PROBE, before anything acts: every host that can act, asked in the node's environment
    # (this process's, which the node inherits) for its own terminal, names none. The control plants a
    # terminal's socket in a second profile folder and the same probe finds it, so the empty answer is
    # the profile's and not a probe that cannot see. A wrong USERPROFILE fails here, loudly.
    $actors = @(Get-HordeHostActors)
    Check ($actors.Count -ge 1) "at least one host can act on this node, so its isolation is checked"
    foreach ($ac in $actors) {
        $none = & $ac.own
        Check ("$($none.state)" -cne "known") ("in the node's environment the host " + $ac.name + " names no terminal of its own (" + $none.reason + ")")
        if ($null -eq $ac.ownMarker) { Check $false ("the host " + $ac.name + " names no socket file, so its isolation cannot be shown"); continue }
        $ctl = Join-Path $work ("own-control-" + $ac.name)
        $m = "" + (& $ac.ownMarker $ctl 4242)
        New-Item -ItemType Directory -Path (Split-Path -Parent $m) -Force | Out-Null
        New-Item -ItemType File -Path $m -Force | Out-Null
        $hit = & $ac.own $ctl @([pscustomobject]@{ pid = 4242; start = "134350994347710308" })
        $named = ("$($hit.state)" -ceq "known") -and (@($hit.value.PSObject.Properties | Where-Object { "" + $_.Value -ceq $m }).Count -eq 1)
        Check $named ("CONTROL: the same probe, with a terminal's socket planted in another profile folder, names it (" + $m + ")")
    }
    $node = [System.Diagnostics.Process]::Start((New-HordeTestStart "node serve -MaxLinks 2 -IdleSeconds 60"))
    $nodeOut = $node.StandardOutput.ReadToEndAsync()
    $nodeErr = $node.StandardError.ReadToEndAsync()
    $nodeFile = Join-Path $homeDir "node\node.json"
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path -LiteralPath $nodeFile) -and (Get-Date) -lt $deadline -and -not $node.HasExited) { Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 3
    Check (-not $node.HasExited) "the node is serving"

    # The node is named, always (review of #126): this machine's own node id, from its node file.
    $nodeId = ""
    if (Test-Path -LiteralPath $nodeFile) { $nodeId = "" + ([System.IO.File]::ReadAllText($nodeFile) | ConvertFrom-Json).deviceId }
    $sp = Invoke-HordeTestRun ("session spawn -Node " + $nodeId + " -Label E -Run 20261005-120000-act -Profile alpha -Repo github.com/example/app -Prompt hello -Title `"client search orc`" -Permission edits")
    Check ($sp.code -eq 0 -and $sp.out -clike "REFUSED session.spawn request *daily spawn cap of 0 is reached*") ("the spawn crossed the real pipe and came back refused by the node's policy (" + $sp.out.Trim() + " " + $sp.err.Trim() + ")")
    $rid = ""
    $m = [regex]::Match($sp.out, 'request ([0-9a-f-]{36})')
    if ($m.Success) { $rid = $m.Groups[1].Value }
    $recFile = Join-Path $homeDir ("hub\acts\" + $rid + ".json")
    Check ($rid -ne "" -and (Test-Path -LiteralPath $recFile)) "the hub wrote the request down, by its id"
    $rec = $null
    if (Test-Path -LiteralPath $recFile) { $rec = [System.IO.File]::ReadAllText($recFile) | ConvertFrom-Json }
    Check ($null -ne $rec -and "$($rec.answer.state)" -ceq "refused" -and "$($rec.args.permission)" -ceq "edits") "and kept the node's answer beside it"
    $st = Invoke-HordeTestRun ("session status -RequestId " + $rid)
    Check ($st.code -eq 0 -and $st.out -clike ("REFUSED session.spawn request " + $rid + "*")) ("request.status reports the same outcome from the node's journal (" + $st.out.Trim() + ")")
    $cl = Invoke-HordeTestRun "session close -SessionId 99999999-1111-4222-8333-444444444444"
    Check ($cl.code -ne 0 -and ($cl.out + $cl.err) -clike "*no record of starting the session*") "a close of a session the hub never started is refused before anything is sent"
    $exited = $node.WaitForExit(60000)
    Check ($exited -and $node.ExitCode -eq 0) "the node served its two links and stopped"
    # The spawn lock lives in the records folder, so the folder may exist; no record may.
    $recs = @(Get-ChildItem -LiteralPath (Join-Path $homeDir "node\spawned") -Filter "*.json" -File -ErrorAction SilentlyContinue | Where-Object { -not $_.Name.StartsWith(".") })
    Check ($recs.Count -eq 0) "the node recorded no spawned session: nothing was started"
    Check (-not (Test-Path -LiteralPath (Join-Path $root "Microsoft"))) "nothing was written into the repository the commands were started from"
} finally {
    if ($null -ne $node -and -not $node.HasExited) { try { $node.Kill() } catch { }; $null = $node.WaitForExit(10000) }
    foreach ($k in @($saved.Keys)) { if ($null -eq $saved[$k]) { Remove-Item -Path ("env:" + $k) -ErrorAction SilentlyContinue } else { Set-Item -Path ("env:" + $k) -Value $saved[$k] } }
    if ((Split-Path -Leaf $work) -match '^horde-act-local-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check ("$env:USERPROFILE" -ceq "$($saved['USERPROFILE'])" -and "$env:HORDE_HOME" -ceq "$($saved['HORDE_HOME'])") "the suite's environment is restored"

Complete-HordeSuite -Success "horde session reaches horde node serve over the real local pipe and reports the node's answer, starting nothing"
