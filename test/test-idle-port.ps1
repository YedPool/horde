# DOES THE IDLE PORT (core/Idle.ps1) HAND BACK ONLY WELL-FORMED TURN STATES, AND TURN EVERY FAILURE
# INTO AN UNKNOWN WITH ITS REASON?
#
# The port is the seam between the reaper's classifier (planning/idle-session-reaper.md, slice RB) and
# each harness's own reader (agents/<name>/Idle.ps1, slice RA). Core names no harness, so this suite
# uses a neutral fake adapter, "harness-a", registered in this process only. Nothing here reads a real
# transcript or a real pane.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "ReadShared", "Transcript", "Idle")) { . (Join-Path $root ("core\" + $f + ".ps1")) }

$since = [datetime]::SpecifyKind([datetime]"2026-10-01T00:00:00", [System.DateTimeKind]::Utc)
$now = [datetime]::SpecifyKind([datetime]"2026-10-05T02:00:00", [System.DateTimeKind]::Utc)

function New-GoodFields {
    # A complete, well-formed turn state, as an adapter would hand it to New-HordeTurnState.
    return @{
        harness = "harness-a"; lineCount = 10; parseSkipped = 0; tornTail = 0
        newestEventAt = (New-HordeKnown -Value $since); lastTurnEndAt = (New-HordeKnown -Value $since)
        atBoundary = (New-HordeKnown -Value $true); blockers = @(); remoteLink = (New-HordeAbsent -Note "none")
        pendingAgents = 0; openTools = @(); openTasks = @(); unknownTasks = @(); queued = 0
        wakes = @(); crons = @()
        versions = @([pscustomobject]@{ version = "1.0.0"; lines = 10; unrecognised = @() })
    }
}

Write-Host ""
Write-Host "--- the turn-state constructor ---" -ForegroundColor Cyan
$ok = New-HordeTurnState -Fields (New-GoodFields)
Check ($ok.PSObject.TypeNames -contains "Horde.TurnState" -and $ok.harness -ceq "harness-a") "CONTROL: a complete set of fields makes a turn state"
foreach ($k in @("newestEventAt", "atBoundary", "openTasks", "crons", "versions", "queued", "remoteLink")) {
    $f = New-GoodFields; $f.Remove($k)
    Check (Throws { New-HordeTurnState -Fields $f } ("needs the field '" + $k + "'")) ("a turn state without '" + $k + "' is refused as missing it, not for some later check")
}
$f = New-GoodFields; $f["extra"] = 1
Check (Throws { New-HordeTurnState -Fields $f } "extra") "a turn state with a field the port does not define is refused"
$f = New-GoodFields; $f["atBoundary"] = $true
Check (Throws { New-HordeTurnState -Fields $f } "atBoundary") "a bare value where an answer belongs is refused"
$f = New-GoodFields; $f["remoteLink"] = "session_x"
Check (Throws { New-HordeTurnState -Fields $f } "remoteLink") "a bare Remote Control link where an answer belongs is refused"
$f = New-GoodFields; $f["pendingAgents"] = [long]3000000000
Check ((New-HordeTurnState -Fields $f).pendingAgents -eq [long]3000000000) "a count past 32 bits is kept whole"
$f = New-GoodFields; $f["pendingAgents"] = -1
Check (Throws { New-HordeTurnState -Fields $f } "pendingAgents") "a negative count is refused"
$f = New-GoodFields; $f["newestEventAt"] = New-HordeKnown -Value ([datetime]"2026-10-01T00:00:00")
Check (Throws { New-HordeTurnState -Fields $f } "UTC") "a known time that is not UTC is refused"

Write-Host ""
Write-Host "--- reading through the port ---" -ForegroundColor Cyan
$script:HordeIdleAdapters.Clear()
Register-HordeIdleAdapter -Name "harness-a" -Read { param($Path, $Since, $Now) New-HordeTurnState -Fields (New-GoodFields) }
$a = Read-HordeTurnState -Harness "harness-a" -Path "x.jsonl" -Since $since -Now $now
Check ($a.state -eq "known" -and $a.value.harness -ceq "harness-a") "CONTROL: a registered adapter's turn state comes back known"
$b = Read-HordeTurnState -Harness "harness-b" -Path "x.jsonl" -Since $since -Now $now
Check ($b.state -eq "unknown" -and $b.reason -like "*no idle reader*harness-b*") "a harness with no reader is unknown, naming the harness"
Register-HordeIdleAdapter -Name "harness-a" -Read { param($Path, $Since, $Now) throw "the file vanished" }
$c = Read-HordeTurnState -Harness "harness-a" -Path "x.jsonl" -Since $since -Now $now
Check ($c.state -eq "unknown" -and $c.reason -like "*vanished*") "an adapter that throws is unknown, with its error as the reason"
Register-HordeIdleAdapter -Name "harness-a" -Read { param($Path, $Since, $Now) [pscustomobject]@{ harness = "harness-a" } }
$d = Read-HordeTurnState -Harness "harness-a" -Path "x.jsonl" -Since $since -Now $now
Check ($d.state -eq "unknown" -and $d.reason -like "*not a turn state*") "an adapter that returns something other than a turn state is unknown"
Register-HordeIdleAdapter -Name "harness-a" -Read { param($Path, $Since, $Now) $f = New-GoodFields; $f["harness"] = "harness-z"; New-HordeTurnState -Fields $f }
$e = Read-HordeTurnState -Harness "harness-a" -Path "x.jsonl" -Since $since -Now $now
Check ($e.state -eq "unknown" -and $e.reason -like "*harness-z*") "an adapter that answers for another harness is unknown"
$local = [datetime]::SpecifyKind([datetime]"2026-10-01T00:00:00", [System.DateTimeKind]::Local)
Check (Throws { Read-HordeTurnState -Harness "harness-a" -Path "x.jsonl" -Since $local -Now $now } "UTC") "a since time that is not UTC is refused: a process start must be placed exactly"
Check (Throws { Register-HordeIdleAdapter -Name "Harness A" -Read { } } "lowercase") "an adapter name is lowercase letters, digits and hyphens"

Write-Host ""
Write-Host "--- finding reader files by folder ---" -ForegroundColor Cyan
$work = Join-Path $env:TEMP ("horde-idle-port-" + [guid]::NewGuid().ToString("N"))
try {
    foreach ($n in @("harness-a", "harness-b")) { New-Item -ItemType Directory -Path (Join-Path $work ("agents\" + $n)) -Force | Out-Null }
    Set-Content -LiteralPath (Join-Path $work "agents\harness-a\Idle.ps1") -Value "# reader" -Encoding ASCII
    $files = @(Get-HordeIdleAdapterFiles -Root $work)
    Check ($files.Count -eq 1 -and $files[0] -like "*harness-a*Idle.ps1") "a folder with an Idle.ps1 is found; one without is not"
    Check (@(Get-HordeIdleAdapterFiles -Root (Join-Path $work "none")).Count -eq 0) "no agents folder is no readers, not an error"
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "--- the per-version survey ---" -ForegroundColor Cyan
$f = New-GoodFields
$f["versions"] = @([pscustomobject]@{ version = "1.0.0"; lines = 5; unrecognised = @() }, [pscustomobject]@{ version = "1.1.0"; lines = 3; unrecognised = @("system/brand_new") })
$s = New-HordeTurnState -Fields $f
$u = @(Get-HordeUnsurveyedVersions -TurnState $s)
Check ($u.Count -eq 1 -and $u[0] -ceq "1.1.0") "a version whose lines carry a kind the reader does not know is unsurveyed"
Check (@(Get-HordeUnsurveyedVersions -TurnState $ok).Count -eq 0) "CONTROL: a version whose kinds are all known is surveyed"

Complete-HordeSuite -Success "the idle port refuses malformed turn states and turns every failure into an unknown with its reason"
