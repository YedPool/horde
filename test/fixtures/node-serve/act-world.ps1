# A node's act world made of fakes, for the suites that drive a dialled node's acts end to end
# (test/test-hub-carry.ps1 in a runspace, a transport's test-mesh-act-local.ps1 in a process). Not a
# suite. Dot-source it AFTER cli/NodeAct.ps1, in the scope that serves the node.
#
# WHAT IS REAL AND WHAT IS NOT. The node's act path is the real one - cli/NodeAct.ps1's
# Invoke-HordeNodeActRequest, with its policy, daily cap and permission ceiling read from the node's own
# <home>\node\policy.json at every spawn, its spawn records, its prompt file and its close by pid and
# start time - over a context built by the real New-HordeNodeActContext. Only what touches the machine
# is a fake, as in test/test-node-act.ps1: one host actor ("fakehost") whose panes are rows in a table,
# one launch adapter ("harness-a", the fixture harness), and a process table those panes fill. No
# terminal is opened, no harness is started, no pane is typed into.
#
# THE FAKE HARNESS reports the mode its argv asked for, so a spawn the policy allows is done; it exits
# when its close text ("bye", then Enter) is typed, so a close of a session it started is done.

$script:ActWorldProcs = @{}
$script:ActWorldSessions = @{}
$script:ActWorldNextPid = 7000
$script:ActWorldTyped = New-Object System.Collections.ArrayList
$script:ActWorldModeOf = @{ careful = "ask"; edit = "edits"; look = "plan" }
$script:ActWorldTerm = [pscustomobject]@{ socket = "C:\fake\act-world-terminal"; guiPid = 1; guiStart = "1" }

Register-HordeLaunchAdapter -Name "harness-a" -Program "harness-a" `
    -Argv { param($s) $a = @("--id", $s.sessionId); foreach ($g in @($s.addDirs)) { if ("" + $g -ne "") { $a += @("--grant", ("" + $g)) } }; $a += @($s.permissionArgs); if ("" + $s.name -ne "") { $a += @("--title", $s.name) }; New-HordeKnown -Value ([string[]]$a) } `
    -Preconditions { param($n) @() } `
    -Identify { param($id, $view) if ($script:ActWorldSessions.ContainsKey($id)) { $x = $script:ActWorldSessions[$id]; New-HordeKnown -Value ([pscustomobject]@{ pid = $x.pid; procStart = $x.procStart; name = $x.name; remoteControl = (New-HordeKnown -Value $true) }) } else { New-HordeAbsent -Note "no control file yet" } } `
    -ReadMode { param($id, $view) if ($script:ActWorldSessions.ContainsKey($id) -and $null -ne $script:ActWorldSessions[$id].mode) { New-HordeKnown -Value $script:ActWorldSessions[$id].mode } else { New-HordeAbsent -Note "no mode line yet" } } `
    -CloseText @("bye", "`r") `
    -TurnMark { param($id, $view) New-HordeKnown -Value ([pscustomobject]@{ n = $script:ActWorldTyped.Count }) } `
    -TurnSeen { param($id, $view, $mark, $line)
        # The fake harness takes every line typed with Enter as a turn (issue #214).
        $h = $script:ActWorldSessions[$id].handle
        New-HordeKnown -Value ([bool](@($script:ActWorldTyped | Select-Object -Skip ([int]$mark.n) | Where-Object { $_.handle -ceq $h -and $_.text -ceq $line -and $_.submit }).Count -gt 0)) }

Register-HordeHostActor -Name "fakehost" `
    -Own { New-HordeKnown -Value $script:ActWorldTerm } `
    -Resolve { param($n) if ($n -ceq "harness-a") { New-HordeKnown -Value "C:\bin\harness-a.exe" } else { New-HordeUnknown -Reason ("no " + $n) } } `
    -Start { param($term, $prog, $argv, $cwd, $envMap)
        $h = "" + (100 + $script:ActWorldSessions.Count)
        $sidv = $argv[[array]::IndexOf(@($argv), "--id") + 1]
        $pidv = $script:ActWorldNextPid; $script:ActWorldNextPid++
        $ticks = "" + (134000000000000000 + $pidv * 10)
        $script:ActWorldProcs[$pidv] = $ticks
        $i = [array]::IndexOf(@($argv), "--mode"); $mode = $null; if ($i -ge 0) { $mode = $script:ActWorldModeOf[$argv[$i + 1]] }
        $nm = ""; $j = [array]::IndexOf(@($argv), "--title"); if ($j -ge 0) { $nm = $argv[$j + 1] }
        $script:ActWorldSessions[$sidv] = [pscustomobject]@{ pid = $pidv; procStart = $ticks; name = $nm; mode = $mode; handle = $h }
        New-HordeKnown -Value ([pscustomobject]@{ handle = $h; program = $prog; cwd = $cwd }) } `
    -Send { param($term, $h, $t, $submit)
        if ("" + $t -cmatch '[\x00-\x1F]') { return (New-HordeUnknown -Reason "the fixture host types printable text only") }
        [void]$script:ActWorldTyped.Add([pscustomobject]@{ handle = $h; text = ("" + $t); submit = [bool]$submit })
        # Enter on an empty line after the close text: the fake harness exits.
        if ($submit -and "" + $t -eq "") { foreach ($s in @($script:ActWorldSessions.Values)) { if ($s.handle -ceq $h) { $script:ActWorldProcs.Remove($s.pid) } } }
        New-HordeKnown -Value $true } `
    -Live { param($term, $h, $expect) New-HordeKnown -Value $true } `
    -Stop { param($term, $h, $expect)
        if ($null -eq $expect -or -not $script:ActWorldProcs.ContainsKey([int]$expect.pid) -or "" + $script:ActWorldProcs[[int]$expect.pid] -cne "" + $expect.procStart) { return (New-HordeUnknown -Reason "nothing was ended: the expected process is not proven") }
        foreach ($s in @($script:ActWorldSessions.Values)) { if ($s.handle -ceq $h) { $script:ActWorldProcs.Remove($s.pid) } }; New-HordeKnown -Value $true }

function New-HordeActWorldContext {
    # The real act context for -HordeHome, with the fixture harness's descriptor and built-in layer and
    # the fake process table. Its policy and the owner's layers are read from -HordeHome at every spawn.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)]$Namespace)
    $ctx = New-HordeNodeActContext -Root $Root -HordeHome $HordeHome -Namespace $Namespace
    $aText = [System.IO.File]::ReadAllText((Join-Path $Root "test\fixtures\agent-descriptor\agents\harness-a\agent.json"))
    # Named at birth with Remote Control on needs the remote view measured; the fixture harness says yes.
    $aText = $aText.Replace('"session.remoteName": { "support": "unverified"', '"session.remoteName": { "support": "yes"')
    $ctx.descriptors = @{ "harness-a" = (Read-HordeAgentDescriptorText -Text $aText -ExpectedName "harness-a") }
    # The fixture harness's own built-in layer: one provider on its own login, one profile, its default.
    $l0 = '{ "schemaVersion": 1, "providers": [ { "name": "provider-a", "protocol": "anthropic-messages", "credential": { "kind": "harness-login" } } ], "profiles": [ { "name": "alpha", "harness": "harness-a", "provider": "provider-a" } ], "rules": [ { "id": "builtin-default", "match": {}, "set": { "profile": "alpha" }, "writtenBy": "user" } ] }'
    $ctx.builtin = @(Read-HordeEngineLayerText -Text $l0 -Layer "L0" -Source "act-world L0")
    $ctx.processStart = { param($p) if ($script:ActWorldProcs.ContainsKey([int]$p)) { $script:ActWorldProcs[[int]$p] } else { $null } }
    $ctx.sleep = { param($ms) Start-Sleep -Milliseconds 20 }
    $ctx.alert = { param($m) }
    $ctx.bounds = [pscustomobject]@{ identifySeconds = 2; modeSeconds = 2; closeSeconds = 2; receiptSeconds = 1; retrySeconds = 1; pollMs = 50 }
    return $ctx
}
