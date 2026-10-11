# DOES `horde hub serve`, STARTED AS A USER WOULD, MIRROR ITS OWN NODE OVER THE REAL LOCAL PIPE, AND
# DOES `horde nodes` SAY WHAT IT MIRRORED?
#
# Remote plan step R13a, end to end through the real horde CLI: `horde node serve -MaxLinks 1` is
# started as its own process, then `horde hub serve -Rounds 1` pulls it over \\.\pipe\horde-node-<id>
# (the hub is also a node: it dials its own device id), then `horde nodes -Json` reads the mirror back.
# The node then stops, and a second `horde hub serve -Rounds 1` finds nobody: `horde nodes` must show the
# node's sessions unknown, "node D unreachable since T", never absent.
#
# THEN `horde hub serve -Listen` (issue #144, item 3), as a user starts it: the suite dials the hub pipe
# itself, as attach would, with a well-formed preamble for a device nobody enrolled - refused, saying it
# is not in the hub's register - and then for a device `horde hub enroll` admitted - bound, and pulled.
#
# The stores are fakes, as in test-node-serve-local.ps1: HORDE_HOME and USERPROFILE point at folders
# this suite makes and WEZFLEET_ROOT at the projection suite's fixture fleet, so the node's projection
# reads fixture records and no agent store (complete is then known false, which the mirror keeps).
#
# LOCAL ONLY, and why it lives here: the local transport admits only this user at this integrity
# level, from an interactive logon, so this cannot run on the always-on box's detached gate; and it
# names the transport's pipe, which only a file under transports/local/ may do (CONTRIBUTING rule 14).
# Every process it starts it stops by its own handle, and every folder it makes it removes.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$work = Join-Path $env:TEMP ("horde-hub-local-" + [guid]::NewGuid().ToString("N"))
$homeDir = Join-Path $work "home"
$profileDir = Join-Path $work "profile"
$fleet = Join-Path $root "test\fixtures\projection\fleet\wezfleet"
$saved = @{ HORDE_HOME = $env:HORDE_HOME; USERPROFILE = $env:USERPROFILE; WEZFLEET_ROOT = $env:WEZFLEET_ROOT }
$node = $null

function New-HordeTestStart {
    # The real horde.ps1 as its own process, in the work folder: with USERPROFILE moved, PowerShell 5.1
    # writes its module analysis cache into the folder a child starts in (test-node-serve-local.ps1).
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
    # Runs horde to the end: { code; out; err }. 180 s: a pull waits for the node's projection over the
    # fixture fleet (11.4 s, measured 2026-10-02), several times slower on a throttled machine.
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
function Read-HordeTestJson {
    param([string]$Text)
    try { return ($Text | ConvertFrom-Json) } catch { Write-Host ("         not JSON: " + $Text) -ForegroundColor DarkYellow; return $null }
}

try {
    New-Item -ItemType Directory -Path $homeDir, $profileDir | Out-Null
    # Every child inherits this environment; it is restored in finally.
    $env:HORDE_HOME = $homeDir
    $env:USERPROFILE = $profileDir
    $env:WEZFLEET_ROOT = $fleet

    $node = [System.Diagnostics.Process]::Start((New-HordeTestStart "node serve -MaxLinks 1 -IdleSeconds 60"))
    $nodeOut = $node.StandardOutput.ReadToEndAsync()
    $nodeErr = $node.StandardError.ReadToEndAsync()
    # The node makes this home's device id on first start (core/Device.ps1); the hub reads the same one.
    $nodeFile = Join-Path $homeDir "node\node.json"
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path -LiteralPath $nodeFile) -and (Get-Date) -lt $deadline -and -not $node.HasExited) { Start-Sleep -Milliseconds 200 }
    $deviceId = ""
    if (Test-Path -LiteralPath $nodeFile) { $deviceId = ([regex]::Match([System.IO.File]::ReadAllText($nodeFile), '"deviceId":"([0-9a-f-]{36})"')).Groups[1].Value }
    Check ($deviceId -cmatch '^[0-9a-f-]{36}$') ("the node made its device id in the home it was given (" + $deviceId + ")")
    # The node listens once its code has loaded; the hub's open waits up to 15 s for the pipe
    # (transports/local), so the hub is not held back until then.

    $first = Invoke-HordeTestRun "hub serve -Rounds 1"
    Check ($first.code -eq 0 -and $first.out -clike ("*node * (" + $deviceId + "): heard, * session(s)*") -and $first.out -clike "*hub ran 1 round(s)*") ("horde hub serve pulls its own node over the pipe and says so (exit " + $first.code + ": " + $first.out.Trim() + $first.err.Trim() + ")")
    $exited = $node.WaitForExit(60000)
    Check ($exited -and $node.ExitCode -eq 0 -and "$($nodeOut.Result)" -clike "*closed by the protocol*") "the node served that one link and the hub ended it with a bye"
    $mirrorFile = Join-Path $homeDir ("hub\mirror\" + $deviceId + ".json")
    Check (Test-Path -LiteralPath $mirrorFile) "the mirror file is in the hub's home, named by the node's device id"

    $seen = Invoke-HordeTestRun "nodes -Json"
    $j = Read-HordeTestJson $seen.out
    $sessions = @()
    if ($null -ne $j) { $sessions = @($j.sessions) }
    Check ($seen.code -eq 0 -and $null -ne $j -and @($j.nodes).Count -eq 1 -and $j.nodes[0].deviceId -ceq $deviceId -and $j.nodes[0].heard.state -ceq "known") "horde nodes -Json lists the node, heard"
    Check ($sessions.Count -ge 1 -and @($sessions | Where-Object { $_.device -ceq $deviceId -and $_.presence.state -ceq "known" }).Count -eq $sessions.Count) ("every one of its " + $sessions.Count + " sessions is known present, on its device")
    Check ($null -ne $j -and $j.nodes[0].complete.state -ceq "known" -and $j.nodes[0].complete.value -eq $false -and "$($j.nodes[0].complete.reason)" -clike "*not every store*") "with the agent stores absent, the node's inventory is partial, with its reason"

    $second = Invoke-HordeTestRun "hub serve -Rounds 1"
    Check ($second.code -eq 0 -and $second.out -clike ("*(" + $deviceId + "): unreachable: could not open a link*")) ("with the node stopped, the next round says it is unreachable and still exits 0 (" + $second.out.Trim() + ")")
    $gone = Invoke-HordeTestRun "nodes -Json"
    $g = Read-HordeTestJson $gone.out
    $rows = @()
    if ($null -ne $g) { $rows = @($g.sessions) }
    $want = "node * (" + $deviceId + ") unreachable since *"
    Check ($rows.Count -eq $sessions.Count -and $rows.Count -ge 1 -and @($rows | Where-Object { $_.presence.state -ceq "unknown" -and "$($_.presence.reason)" -clike $want }).Count -eq $rows.Count) ("every session is now unknown, 'node D unreachable since T' (" + "$(@($rows)[0].presence.reason)" + ")")
    Check (@($rows | Where-Object { $_.presence.state -ceq "absent" }).Count -eq 0) "and none is absent"
    $text = Invoke-HordeTestRun "nodes"
    Check ($text.code -eq 0 -and $text.out -clike ("*(" + $deviceId + ") unreachable since*")) "horde nodes, for a person, says the node is unreachable and since when"
    Check (-not (Test-Path -LiteralPath (Join-Path $root "Microsoft"))) "nothing was written into the repository the commands were started from"

    # --- horde hub serve -Listen binds only an enrolled device ---
    foreach ($f in @("Tristate", "Schema", "Home", "Device")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
    . (Join-Path $root "transports\Port.ps1")
    . (Join-Path $root "transports\local\Transport.ps1")
    $tl = Get-HordeTransport -Name "local"
    $init = Invoke-HordeTestRun "node init"
    $enCmd = [regex]::Match($init.out, 'horde hub enroll -Device (?<dev>\S+) -Key "(?<key>[^"]+)"')
    $enrolled = [guid]::NewGuid().ToString()
    $stranger = [guid]::NewGuid().ToString()
    $en = Invoke-HordeTestRun ("hub enroll -Device " + $enrolled + " -Key `"" + $enCmd.Groups["key"].Value + "`"")
    Check ($enCmd.Success -and $en.code -eq 0 -and (Test-Path -LiteralPath (Join-Path $homeDir ("hub\nodes\" + $enrolled + ".json")))) ("CONTROL: a device is enrolled with a key node init made, and the hub's register holds it (" + $en.out.Trim() + $en.err.Trim() + ")")
    $hubRun = [System.Diagnostics.Process]::Start((New-HordeTestStart "hub serve -Rounds 1 -Listen -IntervalSeconds 20"))
    $hubOut = $hubRun.StandardOutput.ReadToEndAsync()
    $hubErr = $hubRun.StandardError.ReadToEndAsync()
    try {
        # One dial as attach makes it: the preamble, then whatever the hub does with the link.
        function Invoke-HordeTestDial { param([string]$Device)
            $deadline = (Get-Date).AddSeconds(60)
            $o = $null
            while ((Get-Date) -lt $deadline -and -not $hubRun.HasExited) {
                $o = Open-HordeTransportLink -Transport $tl -Endpoint ("hub:" + $deviceId) -Role "node" -TimeoutMs 2000
                if ($o.state -ceq "known") { break }
                Start-Sleep -Milliseconds 300
            }
            if ($null -eq $o -or $o.state -cne "known") { return "not opened" }
            try {
                $null = Send-HordeLinkFrame -Link $o.value -Frame ("horde-attach 1 " + $Device)
                $got = Receive-HordeLinkFrame -Link $o.value -TimeoutMs 30000
                return ("" + $got.state + ": " + $got.value + $got.reason)
            } finally { Close-HordeLink -Link $o.value }
        }
        $d1 = Invoke-HordeTestDial -Device $stranger
        # Closed before the hello: a link the hub refused is never spoken to.
        Check ($d1 -clike "unknown:*") ("a dialled link for a device nobody enrolled gets nothing but its end (" + $d1 + ")")
        $d2 = Invoke-HordeTestDial -Device $enrolled
        Check ($d2 -clike 'known: {*"kind":"hello"*') ("a dialled link for the enrolled device is bound, and the hub says hello on it (" + $d2.Substring(0, [Math]::Min(60, $d2.Length)) + ")")
        $ended = $hubRun.WaitForExit(120000)
        $said = "$($hubOut.Result)" + "$($hubErr.Result)"
        Check ($ended -and $hubRun.ExitCode -eq 0) ("horde hub serve -Listen ran its round and exited 0 (" + $said.Trim() + ")")
        Check ($said -clike ("*a dialled link for device " + $stranger + " was refused: device " + $stranger + " is not enrolled: *not in the hub's register*")) "it refused the stranger's link, saying the device is not in the hub's register"
        Check ($said -clike ("*node (dialled) (" + $enrolled + "): unreachable:*") -and $said -cnotlike ("*device " + $enrolled + " was refused*")) "and bound the enrolled device's link, pulling it until the suite hung up"
    } finally { if (-not $hubRun.HasExited) { try { $hubRun.Kill() } catch { }; $null = $hubRun.WaitForExit(10000) } }
} finally {
    # Only the process this suite started, by its own handle.
    if ($null -ne $node -and -not $node.HasExited) { try { $node.Kill() } catch { }; $null = $node.WaitForExit(10000) }
    foreach ($k in @($saved.Keys)) { if ($null -eq $saved[$k]) { Remove-Item -Path ("env:" + $k) -ErrorAction SilentlyContinue } else { Set-Item -Path ("env:" + $k) -Value $saved[$k] } }
    if ((Split-Path -Leaf $work) -match '^horde-hub-local-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check ("$env:USERPROFILE" -ceq "$($saved['USERPROFILE'])" -and "$env:HORDE_HOME" -ceq "$($saved['HORDE_HOME'])") "the suite's environment is restored"

Complete-HordeSuite -Success "horde hub serve mirrors its own node over the real local pipe, and horde nodes shows its sessions, then unknown once the node is gone"
