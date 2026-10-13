# IS ANYTHING RECORDED ONLY WITH CONSENT, ONLY AFTER IT, AND ONLY WHERE HORDE'S FILES BELONG?
#
# core/MetricsStore.ps1, under a fake HORDE_HOME this suite creates and removes (CONTRIBUTING 9). The
# real home is never read or written: HORDE_HOME is restored in a finally block.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "core\ReadShared.ps1")
. (Join-Path $root "core\Home.ps1")
. (Join-Path $root "core\Transcript.ps1")
. (Join-Path $root "core\MetricsStore.ps1")

$work = Join-Path $env:TEMP ("horde-metrics-store-" + [guid]::NewGuid().ToString("N"))
$origHome = $env:HORDE_HOME
$envNames = @("HORDE_METRICS", "HORDE_METRICS_LEVEL", "HORDE_METRICS_ENABLED", "HORDE_METRICS_LEVEL_OVERRIDE")
$origEnv = @{}; foreach ($n in $envNames) { $origEnv[$n] = [Environment]::GetEnvironmentVariable($n) }
function Set-Gate { param([string]$Text) [System.IO.File]::WriteAllText((Join-Path (Get-HordeMetricsDir) "gate.json"), $Text) }
try {
    $env:HORDE_HOME = Join-Path $work "home"
    New-Item -ItemType Directory -Path (Get-HordeMetricsDir) -Force | Out-Null
    $after = New-HordeKnown -Value (ConvertTo-HordeUtcTime "2026-10-01T12:00:00Z")
    $before = New-HordeKnown -Value (ConvertTo-HordeUtcTime "2026-09-30T12:00:00Z")

    Write-Host ""
    Write-Host "--- off by default ---" -ForegroundColor Cyan
    $g = Read-HordeMetricsGate
    Check ($g.state -eq "absent") "with no gate file the gate is absent"
    $d = Get-HordeMetricsWriteDecision -Gate $g -FirstEventAt $after
    Check ($d.write -eq $false -and $d.reason -like "*off*") "and nothing is recorded: metrics are off by default"
    foreach ($n in $envNames) { [Environment]::SetEnvironmentVariable($n, "usage") }
    $env:HORDE_METRICS = "1"
    $ge = Read-HordeMetricsGate
    Check ($ge.state -eq "absent" -and (Get-HordeMetricsWriteDecision -Gate $ge -FirstEventAt $after).write -eq $false) "no environment variable turns metrics on (HORDE_METRICS=1, HORDE_METRICS_LEVEL=usage and others)"
    Set-Gate '{ "schemaVersion": 1, "level": "usage", "enabledAt": "2026-10-01T00:00:00Z" }'
    Check ((Get-HordeMetricsWriteDecision -Gate (Read-HordeMetricsGate) -FirstEventAt $after).write -eq $true) "CONTROL: the gate file does turn it on, so the environment check could have seen a change"
    foreach ($n in $envNames) { [Environment]::SetEnvironmentVariable($n, $origEnv[$n]) }
    Set-Gate '{ "schemaVersion": 1, "level": "off", "enabledAt": "2026-10-01T00:00:00Z" }'
    Check ((Get-HordeMetricsWriteDecision -Gate (Read-HordeMetricsGate) -FirstEventAt $after).write -eq $false) "a gate that says off records nothing"

    Write-Host ""
    Write-Host "--- a gate that cannot be read is refused ---" -ForegroundColor Cyan
    Set-Gate '{ not json'
    $bad = Read-HordeMetricsGate
    Check ($bad.state -eq "unknown") "a gate file that is not JSON is unknown"
    $db = Get-HordeMetricsWriteDecision -Gate $bad -FirstEventAt $after
    Check ($db.write -eq $false -and $db.reason -like "*refused*") "and is refused, never read as on"
    Set-Gate '{ "schemaVersion": 1, "level": "USAGE", "enabledAt": "2026-10-01T00:00:00Z" }'
    Check ((Read-HordeMetricsGate).state -eq "unknown") "a level in the wrong case is not a level"
    Set-Gate '{ "schemaVersion": 1, "level": "full", "enabledAt": "2026-10-01T00:00:00Z" }'
    Check ((Read-HordeMetricsGate).state -eq "unknown") "a level M1 does not build (full) is refused, not treated as usage"
    Set-Gate '{ "schemaVersion": 1, "level": "usage" }'
    Check ((Read-HordeMetricsGate).state -eq "unknown") "usage with no enabledAt is refused, because what came before consent could not be told"
    Set-Gate '{ "schemaVersion": 1, "level": "usage", "enabledAt": "2026-10-01T00:00:00" }'
    Check ((Read-HordeMetricsGate).state -eq "unknown") "an enabledAt with no zone is refused"

    Write-Host ""
    Write-Host "--- nothing from before consent ---" -ForegroundColor Cyan
    Set-Gate '{ "schemaVersion": 1, "level": "usage", "enabledAt": "2026-10-01T00:00:00Z" }'
    $gate = Read-HordeMetricsGate
    $db2 = Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt $before
    Check ($db2.write -eq $false -and $db2.reason -like "*before metrics were enabled*") "a transcript that began before enabledAt is not recorded"
    Check ((Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt $after).write -eq $true) "CONTROL: one that began after is"
    Check ((Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt (New-HordeAbsent -Note "no events")).write -eq $false) "one with no first event is not, since when it began cannot be told"
    Check ((Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt $after -Windowed).write -eq $false) "a summary of a time window is never recorded"

    Write-Host ""
    Write-Host "--- never inside any engine's own folders, whether or not it has an adapter ---" -ForegroundColor Cyan
    # Review of PR #50, F7: the guard was built from the loaded adapters, so an engine with no adapter
    # had no protection - a probe wrote two summaries into a fake profile's folder for one. Every
    # agents/<name>/ folder now declares its store folders in stores.json, read as data.
    $fakeRepo = Join-Path $work "repo"
    foreach ($h in @("harness-x", "harness-y")) { New-Item -ItemType Directory -Path (Join-Path $fakeRepo ("agents\" + $h)) -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $fakeRepo "agents\harness-x\stores.json"), '{ "schemaVersion": 1, "roots": [ { "profile": ".harness-x" }, { "env": "HARNESS_X_HOME_TEST" } ] }')
    [System.IO.File]::WriteAllText((Join-Path $fakeRepo "agents\harness-y\stores.json"), '{ "schemaVersion": 1, "roots": [ { "profile": ".harness-y" } ] }')
    $origProfile = $env:USERPROFILE
    $origXHome = $env:HARNESS_X_HOME_TEST
    try {
        $env:USERPROFILE = Join-Path $work "profile"
        $env:HARNESS_X_HOME_TEST = Join-Path $work "x-moved"
        $roots = Get-HordeAgentStoreRoots -Root $fakeRepo
        Check ($roots.state -eq "known" -and @($roots.value) -contains (Join-Path $env:USERPROFILE ".harness-y") -and @($roots.value) -contains $env:HARNESS_X_HOME_TEST) "every engine folder's stores.json is read: profile folders and folders named by a variable"
        # A CALLER MAY ASK ABOUT ANOTHER PROFILE than the one the variable names (files/Deny.ps1 asks
        # twice). Left out, the answer is what it always was, which the check above holds.
        $otherProfile = Join-Path $work "another-profile"
        $elsewhere = Get-HordeAgentStoreRoots -Root $fakeRepo -ProfileRoot $otherProfile
        Check ($elsewhere.state -eq "known" -and @($elsewhere.value) -ccontains (Join-Path $otherProfile ".harness-x") -and @($elsewhere.value) -ccontains (Join-Path $otherProfile ".harness-y")) "asked about another profile, every engine's profile folder is under that profile"
        Check (@($elsewhere.value) -cnotcontains (Join-Path $env:USERPROFILE ".harness-y") -and @($elsewhere.value) -cnotcontains (Join-Path $env:USERPROFILE ".harness-x")) "and not under the one the variable names"
        Check (@($elsewhere.value) -ccontains $env:HARNESS_X_HOME_TEST -and @($elsewhere.value).Count -eq 3) "a folder an engine's own variable names is the same whichever profile is asked about"
        $viaStores = Get-HordeAgentStores -Root $fakeRepo -ProfileRoot $otherProfile
        Check ($viaStores.state -eq "known" -and @(@($viaStores.value | Where-Object { $_.agent -eq "harness-y" })[0].roots) -ccontains (Join-Path $otherProfile ".harness-y")) "and the fuller answer takes the same profile"
        Check (@((Get-HordeAgentStoreRoots -Root $fakeRepo -ProfileRoot "").value) -ccontains (Join-Path $env:USERPROFILE ".harness-y") -and @($roots.value).Count -eq 3 -and @($roots.value) -ccontains (Join-Path $env:USERPROFILE ".harness-x")) "CONTROL: with no profile named, or an empty one, it is the variable's, as it was for every caller before"
        $env:HORDE_HOME = Join-Path $env:USERPROFILE ".harness-y\home"
        $dy = Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt $after -RepoRoot $fakeRepo
        Check ($dy.write -eq $false -and $dy.reason -like "*inside a harness*") "a metrics folder inside an engine's folder is refused, adapter or none"
        $env:HORDE_HOME = Join-Path $env:HARNESS_X_HOME_TEST "home"
        Check ((Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt $after -RepoRoot $fakeRepo).write -eq $false) "and so is one inside a folder an engine's variable moved its store to"
        $env:HORDE_HOME = Join-Path $work "home"
        Check ((Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt $after -RepoRoot $fakeRepo).write -eq $true) "CONTROL: one outside them all is allowed"
        New-Item -ItemType Directory -Path (Join-Path $fakeRepo "agents\harness-z") -Force | Out-Null
        $dz = Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt $after -RepoRoot $fakeRepo
        Check ($dz.write -eq $false -and $dz.reason -like "*harness-z*stores.json*") "an engine folder with no stores.json makes the guard refuse, rather than leave that engine unprotected"
        [System.IO.File]::WriteAllText((Join-Path $fakeRepo "agents\harness-z\stores.json"), '{ not json')
        Check ((Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt $after -RepoRoot $fakeRepo).write -eq $false) "and so does one that cannot be read"
        Remove-Item -LiteralPath (Join-Path $fakeRepo "agents\harness-z") -Recurse -Force

        # Plan step M2: a stores.json also names the folders under each root that hold transcripts, and
        # their extension, which only the engine's folder may say.
        [System.IO.File]::WriteAllText((Join-Path $fakeRepo "agents\harness-x\stores.json"), '{ "schemaVersion": 1, "roots": [ { "profile": ".harness-x" }, { "env": "HARNESS_X_HOME_TEST" } ], "transcripts": [ { "folder": "logs", "extension": ".log" } ] }')
        $st = Get-HordeAgentStores -Root $fakeRepo
        $x = @($st.value | Where-Object { $_.agent -eq "harness-x" })[0]
        $y = @($st.value | Where-Object { $_.agent -eq "harness-y" })[0]
        $dirs = @($x.transcripts | ForEach-Object { $_.dir })
        Check ($st.state -eq "known" -and $dirs -contains (Join-Path $env:USERPROFILE ".harness-x\logs") -and $dirs -contains (Join-Path $env:HARNESS_X_HOME_TEST "logs")) "transcript folders are found under every root of the engine, the moved one too"
        Check (@($x.transcripts | Where-Object { $_.extension -ne ".log" }).Count -eq 0 -and @($x.extensions) -contains ".log") "with the extension the engine declares"
        Check (@($x.transcripts | Where-Object { $_.label -like "*Users*" -or $_.label -like "*:*" }).Count -eq 0 -and @($x.transcripts | ForEach-Object { $_.label }) -contains "env-HARNESS_X_HOME_TEST/logs") "and a label for each that names its root and folder, never a home path"
        Check (@($y.transcripts).Count -eq 0) "an engine that names none has none"
        foreach ($bad in @('{ "folder": "..\up", "extension": ".log" }', '{ "folder": "..", "extension": ".log" }', '{ "folder": "a/b", "extension": ".log" }', '{ "folder": "", "extension": ".log" }', '{ "folder": "logs", "extension": "log" }', '{ "folder": "logs", "extension": ".l;g" }', '{ "folder": "logs" }', '"logs"')) {
            [System.IO.File]::WriteAllText((Join-Path $fakeRepo "agents\harness-x\stores.json"), ('{ "schemaVersion": 1, "roots": [ { "profile": ".harness-x" } ], "transcripts": [ ' + $bad + ' ] }'))
            Check ((Get-HordeAgentStores -Root $fakeRepo).state -eq "unknown") ("a transcripts entry that is not one plain folder and one extension is refused: " + $bad)
        }
        [System.IO.File]::WriteAllText((Join-Path $fakeRepo "agents\harness-x\stores.json"), '{ "schemaVersion": 1, "roots": [ { "profile": ".harness-x" } ], "transcripts": "logs" }')
        Check ((Get-HordeAgentStores -Root $fakeRepo).state -eq "unknown") "and so is a transcripts entry that is not a list"
        Check ((Get-HordeAgentStoreRoots -Root $fakeRepo).state -eq "unknown") "and the write guard refuses with it, rather than guess the rest"
    } finally {
        $env:USERPROFILE = $origProfile
        $env:HARNESS_X_HOME_TEST = $origXHome
        $env:HORDE_HOME = Join-Path $work "home"
    }
    Check ((Test-HordePathInside -Path "C:\x\abc" -Root "C:\x\ab") -eq $false) "a folder whose name merely begins with the root's is not inside it"
    Check ((Test-HordePathInside -Path "C:\X\AB\c" -Root "c:\x\ab") -eq $true) "paths are compared without regard to case, as Windows does"

    Write-Host ""
    Write-Host "--- the record ---" -ForegroundColor Cyan
    $t = ConvertTo-HordeUtcTime "2026-10-01T12:34:56.789Z"
    $rec = [ordered]@{ schemaVersion = 1; at = (ConvertTo-HordeJsonSafe $t); gap = (ConvertTo-HordeJsonSafe (New-HordeKnown -Value ([pscustomobject]@{ seconds = [decimal]12.5; startedAt = $t }))); none = (ConvertTo-HordeJsonSafe (New-HordeUnknown -Reason "why")); list = (ConvertTo-HordeJsonSafe @(1, 2)) }
    $path = Write-HordeMetricsRecord -Record $rec -Adapter "harness-a" -Name "session-1"
    Check ($path -like ((Get-HordeMetricsDir) + "\summaries\harness-a\session-1.json")) "a record is written under the metrics folder, by adapter and name"
    $text = [System.IO.File]::ReadAllText($path)
    Check ($text -like '*"at":  "2026-10-01T12:34:56.789Z"*') "times are written as UTC ISO 8601 text, not PowerShell's Date() form"
    Check ($text -like '*"startedAt":  "2026-10-01T12:34:56.789Z"*' -and $text -like '*"state":  "known"*') "a time inside an answer's value is converted too, and the state is written"
    Check ($text -like '*"state":  "unknown"*' -and $text -like '*"reason":  "why"*') "an unknown keeps its reason"
    Add-Type -AssemblyName System.Web.Extensions
    $back = (New-Object System.Web.Script.Serialization.JavaScriptSerializer).DeserializeObject($text)
    Check (@($back["list"]).Count -eq 2) "a list stays a list"
    $rec.schemaVersion = 2
    $null = Write-HordeMetricsRecord -Record $rec -Adapter "harness-a" -Name "session-1"
    Check ([System.IO.File]::ReadAllText($path) -like '*"schemaVersion":  2*') "writing again replaces the record whole"
    Check (@(Get-ChildItem -LiteralPath (Split-Path -Parent $path) -Force).Count -eq 1) "and leaves no temporary file behind"
    Check (Throws { Write-HordeMetricsRecord -Record $rec -Adapter "harness-a" -Name "..\escape" } "not a record name") "a name that could climb out of the folder is refused"
    Check (Throws { Write-HordeMetricsRecord -Record $rec -Adapter "Harness A" -Name "x" } "not an adapter name") "an adapter name that is not a folder-safe word is refused"
} finally {
    $env:HORDE_HOME = $origHome
    foreach ($n in $envNames) { [Environment]::SetEnvironmentVariable($n, $origEnv[$n]) }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "metrics are recorded only with a readable gate, only after consent, and never inside a harness's folders"
