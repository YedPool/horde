# DOES EACH NODE HAVE ONE RANDOM DEVICE ID, MADE ONCE, NEVER GUESSED AND NEVER OVERWRITTEN?
#
# Remote plan step R7 (planning/execution-plan-remote.md). core/Device.ps1 reads or creates
# <HordeHome>/node/node.json. The id names this machine to the hub (link-frame hello, node-manifest
# deviceId), to the session record's `device` (R10), to every namespace tag (R11) and to the
# lifecycle follower's stream file (its step 7). So it must be one id per home however many first
# calls race, random rather than taken from a host name or hardware, and never replaced: a file
# Horde cannot read is refused, because writing a new id over it would make the hub see a new device.
#
# Every home here is a folder this suite creates under %TEMP% and removes; the real home is never
# touched (CONTRIBUTING 9).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\Device.ps1")

$uuidV4 = '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
$namePattern = '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
$script:work = Join-Path $env:TEMP ("horde-device-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$script:homeN = 0
function NewHome { $script:homeN++; return (Join-Path $script:work ("home-" + $script:homeN)) }
function NodeFile { param([string]$H) return (Join-Path $H "node\node.json") }
function Canonical { param([string]$Id, [string]$Name) return ('{"schemaVersion":1,"deviceId":"' + $Id + '","deviceName":"' + $Name + '"}') }
function Hash { param([string]$P) return ([System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.IO.File]::ReadAllBytes($P)))) }

try {
    Write-Host ""
    Write-Host "--- loading the module ---" -ForegroundColor Cyan
    $strictKept = & { Set-StrictMode -Version Latest; . (Join-Path $root "core\Device.ps1"); try { $null = $hordeNeverAssignedVariable; $false } catch { $true } }
    Check ($strictKept -eq $true) "dot-sourcing core/Device leaves the caller's strict mode on"

    Write-Host ""
    Write-Host "--- the first call makes the id, every later call reads it ---" -ForegroundColor Cyan
    $h1 = NewHome
    Check ((Test-Path -LiteralPath $h1) -eq $false) "control: the home does not exist before the first call"
    $a = Get-HordeNode -HomeRoot $h1
    Check ($a.created -eq $true -and (Test-Path -LiteralPath (NodeFile $h1) -PathType Leaf)) "the first call creates node/node.json and says it did"
    Check ("$($a.deviceId)" -cmatch $uuidV4) "the id is a random (version 4) UUID, lower case"
    Check ("$($a.deviceName)" -cmatch $namePattern) "the device name fits node-manifest.v1's deviceName pattern"
    Check ($a.deviceName -ceq (ConvertTo-HordeDeviceName -Text "$env:COMPUTERNAME")) "the device name is this computer's name, fitted to the pattern"
    Check (@(Get-ChildItem -LiteralPath (Join-Path $h1 "node") -Force | ForEach-Object { $_.Name }) -join "," -ceq "node.json") "the node folder holds node.json and no leftover candidate"
    $before = Hash (NodeFile $h1)
    $b = Get-HordeNode -HomeRoot $h1
    Check ($b.created -eq $false -and $b.raced -eq $false -and $b.deviceId -ceq $a.deviceId) "a second call returns the same id, creates nothing and makes no candidate"
    Check ((Hash (NodeFile $h1)) -ceq $before) "a second call leaves the file byte for byte as it was"
    Check ((Get-HordeDeviceId -HomeRoot $h1) -ceq $a.deviceId) "Get-HordeDeviceId is the node's id"
    Check ([System.IO.File]::ReadAllText((NodeFile $h1)) -ceq ((Canonical $a.deviceId $a.deviceName) + "`r`n")) "the file is the one canonical line Horde writes"

    Write-Host ""
    Write-Host "--- the id is random, never a host name or hardware ---" -ForegroundColor Cyan
    $h2 = NewHome
    $c = Get-HordeNode -HomeRoot $h2
    Check ($c.deviceId -cne $a.deviceId) "two homes on one machine get two ids, so the id is not read from the machine"
    # THE NAME IS A HANDLE ONLY: changing it in the file changes the name, never the id.
    [System.IO.File]::WriteAllText((NodeFile $h2), ((Canonical $c.deviceId "renamed-box") + "`r`n"))
    $c2 = Get-HordeNode -HomeRoot $h2
    Check ($c2.deviceId -ceq $c.deviceId -and $c2.deviceName -ceq "renamed-box") "a renamed device keeps its id"

    Write-Host ""
    Write-Host "--- the device name is a handle made fit for the manifest ---" -ForegroundColor Cyan
    Check ((ConvertTo-HordeDeviceName -Text "BOX-01") -ceq "BOX-01") "a plain computer name is kept as it is"
    Check ((ConvertTo-HordeDeviceName -Text "my box!") -ceq "my-box-") "a character the manifest refuses becomes a hyphen"
    Check ((ConvertTo-HordeDeviceName -Text "-.box") -ceq "box") "a name is trimmed until it starts with a letter or digit"
    Check ((ConvertTo-HordeDeviceName -Text "") -ceq "node") "no computer name gives the name node"
    Check ((ConvertTo-HordeDeviceName -Text "---") -ceq "node") "a name with nothing usable gives the name node"
    $longName = ConvertTo-HordeDeviceName -Text ("a" * 100)
    Check ($longName.Length -eq 64 -and $longName -cmatch $namePattern) "a long name is cut to the manifest's 64 characters"
    Check ((ConvertTo-HordeDeviceName -Text ("caf" + [char]0xE9)) -cmatch $namePattern) "a non-ASCII name becomes one the manifest accepts"

    Write-Host ""
    Write-Host "--- a file Horde cannot read is refused, never replaced ---" -ForegroundColor Cyan
    $goodId = "0f8fad5b-d9cb-469f-a165-70867728950e"
    $bad = [ordered]@{
        "an empty file"                       = ""
        "an id in upper case"                 = (Canonical $goodId.ToUpperInvariant() "box")
        "an id that is not a UUID"            = (Canonical "not-a-uuid" "box")
        "a name the manifest refuses"         = (Canonical $goodId "my box")
        "an extra key"                        = ('{"schemaVersion":1,"deviceId":"' + $goodId + '","deviceName":"box","x":1}')
        "a missing name"                      = ('{"schemaVersion":1,"deviceId":"' + $goodId + '"}')
        "another schema version"              = ('{"schemaVersion":2,"deviceId":"' + $goodId + '","deviceName":"box"}')
        "the id written twice"                = ('{"schemaVersion":1,"deviceId":"' + $goodId + '","deviceId":"1f8fad5b-d9cb-469f-a165-70867728950e","deviceName":"box"}')
        "reformatted JSON"                    = ('{ "schemaVersion": 1, "deviceId": "' + $goodId + '", "deviceName": "box" }')
        "two lines"                           = ((Canonical $goodId "box") + "`r`n" + (Canonical $goodId "box"))
        "an extra blank line"                 = ((Canonical $goodId "box") + "`r`n`n")
    }
    foreach ($k in $bad.Keys) {
        $hb = NewHome
        New-Item -ItemType Directory -Path (Join-Path $hb "node") | Out-Null
        [System.IO.File]::WriteAllText((NodeFile $hb), $bad[$k])
        $was = Hash (NodeFile $hb)
        Check ((Throws { Get-HordeNode -HomeRoot $hb } "will not replace it") -and (Hash (NodeFile $hb)) -ceq $was) ("a node.json holding " + $k + " is refused and left as it was")
    }
    $hbom = NewHome
    New-Item -ItemType Directory -Path (Join-Path $hbom "node") | Out-Null
    [System.IO.File]::WriteAllBytes((NodeFile $hbom), [byte[]](@(0xEF, 0xBB, 0xBF) + @([System.Text.Encoding]::ASCII.GetBytes((Canonical $goodId "box")))))
    Check (Throws { Get-HordeNode -HomeRoot $hbom } "not ASCII (a byte-order mark counts)") "a node.json starting with a byte-order mark is refused, and the reason names the byte, not the format"
    $hok = NewHome
    New-Item -ItemType Directory -Path (Join-Path $hok "node") | Out-Null
    [System.IO.File]::WriteAllText((NodeFile $hok), (Canonical $goodId "box"))
    $ok = Get-HordeNode -HomeRoot $hok
    Check ($ok.deviceId -ceq $goodId -and $ok.created -eq $false) "control: the canonical line with no line ending is read"
    $hdir = NewHome
    New-Item -ItemType Directory -Path (NodeFile $hdir) -Force | Out-Null
    Check (Throws { Get-HordeNode -HomeRoot $hdir } "is a folder") "a folder where node.json should be is refused, not worked around"

    Write-Host ""
    Write-Host "--- the home comes from core/Home ---" -ForegroundColor Cyan
    $origHome = $env:HORDE_HOME
    try {
        $env:HORDE_HOME = "relative\home"
        Check (Throws { Get-HordeNode } "absolute") "with no -HomeRoot a relative HORDE_HOME is refused, as core/Home refuses it"
        $hEnv = NewHome
        $env:HORDE_HOME = $hEnv
        $e = Get-HordeNode
        Check ($e.created -eq $true -and (Test-Path -LiteralPath (NodeFile $hEnv) -PathType Leaf)) "with no -HomeRoot the node file is made under HORDE_HOME"
    } finally { $env:HORDE_HOME = $origHome }

    Write-Host ""
    Write-Host "--- a copied node.json is caught at enrolment, not here ---" -ForegroundColor Cyan
    # A node.json copied to a second machine gives both machines one id, and nothing on either
    # machine can tell: the file is all a node knows of itself. Enrolment catches it (plan step R17:
    # "enrolling a device id already bound to another key is refused"), because each machine's link
    # key differs. This check pins the limit, so nobody mistakes this module for that guard.
    $hCopy = NewHome
    New-Item -ItemType Directory -Path (Join-Path $hCopy "node") | Out-Null
    Copy-Item -LiteralPath (NodeFile $h1) -Destination (NodeFile $hCopy)
    Check ((Get-HordeDeviceId -HomeRoot $hCopy) -ceq $a.deviceId) "a copied node.json carries its id to the copy (R17 refuses the second enrolment)"

    Write-Host ""
    Write-Host "--- racing first calls make one id ---" -ForegroundColor Cyan
    # Separate processes call Get-HordeNode on one fresh home at the same tick. Every racer must be
    # given the same id, and exactly one may say it created it. A CONTROL runs the same race against a
    # copy of the module whose create-if-absent is replaced by create-or-overwrite: the harness must
    # see two ids there, or it could not have seen them here. Four racers, five rounds: the machine
    # this was written on had about 1 GB free.
    $worker = Join-Path $root "test\fixtures\device\race-worker.ps1"
    $broken = Join-Path $script:work "Device-broken.ps1"
    $src = [System.IO.File]::ReadAllText((Join-Path $root "core\Device.ps1"))
    $find = '[System.IO.File]::Move($tmp, $file)'
    Check (([regex]::Matches($src, [regex]::Escape($find))).Count -eq 1) "the broken copy's find string occurs exactly once in core/Device.ps1"
    $brokenSrc = $src.Replace($find, '[System.IO.File]::Copy($tmp, $file, $true)').Replace('. (Join-Path $PSScriptRoot "Home.ps1")', ('. "' + (Join-Path $root "core\Home.ps1") + '"'))
    [System.IO.File]::WriteAllText($broken, $brokenSrc)
    Check ($brokenSrc -cne $src) "the broken copy differs from the module"

    function Invoke-DeviceRace {
        param([string]$DevicePath, [string]$Tag)
        $dir = Join-Path $script:work ("race-" + $Tag)
        New-Item -ItemType Directory -Path $dir | Out-Null
        $h = Join-Path $dir "home"
        $go = Join-Path $dir "go.txt"
        $procs = New-Object System.Collections.ArrayList
        $problems = New-Object System.Collections.ArrayList
        try {
            for ($r = 0; $r -lt 4; $r++) {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "powershell.exe"
                $psi.Arguments = ("-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + $worker + "`" -DevicePath `"" + $DevicePath +
                    "`" -HomeRoot `"" + $h + "`" -GoFile `"" + $go + "`" -ReadyFile `"" + (Join-Path $dir ("ready-" + $r)) +
                    "`" -OutFile `"" + (Join-Path $dir ("out-" + $r)) + "`"")
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.CreateNoWindow = $true
                $p = [System.Diagnostics.Process]::Start($psi)
                [void]$procs.Add([pscustomobject]@{ p = $p; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync() })
            }
            $deadline = (Get-Date).AddSeconds(120)
            while (@(0..3 | Where-Object { -not (Test-Path -LiteralPath (Join-Path $dir ("ready-" + $_))) }).Count -gt 0) {
                if ((Get-Date) -gt $deadline) { [void]$problems.Add("not every racer was ready within 120 s"); break }
                if (@($procs | Where-Object { $_.p.HasExited }).Count -gt 0) { [void]$problems.Add("a racer exited before it was ready"); break }
                Start-Sleep -Milliseconds 50
            }
            # Written under another name and renamed, so no racer reads it half written.
            [System.IO.File]::WriteAllText(($go + ".tmp"), ([datetime]::UtcNow.AddMilliseconds(500).Ticks).ToString())
            [System.IO.File]::Move(($go + ".tmp"), $go)
            foreach ($x in $procs) {
                if (-not $x.p.WaitForExit(120000)) { [void]$problems.Add("a racer did not exit within 120 s") }
                elseif ($x.p.ExitCode -ne 0) { [void]$problems.Add("a racer exited " + $x.p.ExitCode + ": " + $x.err.Result) }
            }
        } finally {
            # Only the processes this function started, held by their own handles.
            foreach ($x in $procs) { if (-not $x.p.HasExited) { $x.p.Kill() } ; $x.p.Dispose() }
        }
        $answers = @(0..3 | ForEach-Object { $f = Join-Path $dir ("out-" + $_); if (Test-Path -LiteralPath $f) { [System.IO.File]::ReadAllText($f) } })
        return [pscustomobject]@{ problems = @($problems); answers = $answers }
    }

    $cleanEveryRound = $true
    $sameEveryRound = $true
    $oneCreatorEveryRound = $true
    $raced = 0
    $allAnswered = $true
    for ($round = 1; $round -le 5; $round++) {
        $res = Invoke-DeviceRace -DevicePath (Join-Path $root "core\Device.ps1") -Tag ("real-" + $round)
        if ($res.problems.Count -gt 0 -or $res.answers.Count -ne 4) { $allAnswered = $false; Write-Host ("    round " + $round + ": " + ($res.problems -join "; ")) }
        $ids = @($res.answers | ForEach-Object { ($_ -split "\|")[2] } | Sort-Object -Unique)
        $creators = @($res.answers | Where-Object { ($_ -split "\|")[0] -ceq "True" })
        $raced += @($res.answers | Where-Object { ($_ -split "\|")[1] -ceq "True" }).Count
        if ($ids.Count -ne 1) { $sameEveryRound = $false }
        if ($creators.Count -ne 1) { $oneCreatorEveryRound = $false }
        $left = @(Get-ChildItem -LiteralPath (Join-Path $script:work ("race-real-" + $round + "\home\node")) -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ","
        if ($left -cne "node.json") { $cleanEveryRound = $false; Write-Host ("    round " + $round + " left: " + $left) }
    }
    Check ($allAnswered -eq $true) "every racer of every round answered"
    Check ($sameEveryRound -eq $true) "in every round all four racers were given one id"
    Check ($oneCreatorEveryRound -eq $true) "in every round exactly one racer says it created the id"
    Check ($cleanEveryRound -eq $true) "in every round the losers removed their candidates: the node folder holds only node.json"
    Write-Host ("    racers that lost the create to another in flight, over 5 rounds: " + $raced)
    Check ($raced -gt 0) "contention: at least one racer lost the create to another in flight, so the racers met rather than took turns"
    $ctl = Invoke-DeviceRace -DevicePath $broken -Tag "broken"
    $ctlIds = @($ctl.answers | ForEach-Object { ($_ -split "\|")[2] } | Sort-Object -Unique)
    Check ($ctl.answers.Count -eq 4 -and $ctlIds.Count -gt 1) "control: with create-or-overwrite the same race hands out more than one id"
}
finally {
    if ((Split-Path -Leaf $script:work) -match '^horde-device-[0-9a-f]{32}$') { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "one random device id per home, made once, never guessed and never overwritten"
