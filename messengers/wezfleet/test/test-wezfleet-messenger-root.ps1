# WHERE IS THE FLEET? THE SETTING, ELSE THE CHECKOUT THE wezfleet COMMAND ON PATH RUNS, AND NEVER A GUESS.
#
# messengers/wezfleet reads its folder from its own settings (core/ModuleSettings.ps1, module
# messenger-wezfleet, setting root, kind folder, default empty). Empty means: the checkout the wezfleet
# command on PATH runs - a .ps1 on PATH is that checkout's own wezfleet.ps1; a .cmd or .bat shim is read,
# never run, for the one %~dp0<folder>\wezfleet.ps1 it names. Whatever chose the folder, the existing
# checks follow (absolute, no .., no reparse point, the markers). A settings file that is refused makes
# every post and status unknown with its findings, and the command on PATH is then never looked at.
# Set-HordeWezfleetMessengerRoot, for tests, wins over both.
#
# EVERY CASE THAT COULD LOOK AT PATH RUNS IN A CHILD PowerShell (test\RootProbe.ps1) whose PATH holds only
# temp folders made here and whose HORDE_HOME is a fresh temp folder: the fleet's real command, which is on
# PATH on a machine where wezfleet is installed, is never found and never run. Each fake checkout is
# test\FakeWezfleet.ps1 copied as wezfleet.ps1 beside the marker stubs, and its own argv.log says whether
# it ran - never the messenger's answer alone.
#
# And the pin other suites use (test\Pin.ps1, through test\lib\MessengerPins.ps1): a pinned home never
# reaches the command on PATH, even when the command on PATH leads to a working checkout.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "test\lib\MessengerPins.ps1")

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$work = Join-Path $tempRoot ("horde-wfr-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $work)
$fixedPs = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")
$probe = Join-Path $here "RootProbe.ps1"
$script:n = 0

function New-Dir { param([string]$Name) $d = Join-Path $work $Name; [void](New-Item -ItemType Directory -Force -Path $d); return $d }
function New-Checkout {
    # A fake wezfleet checkout: the fake as wezfleet.ps1 and the marker stubs.
    param([string]$Dir)
    [void](New-Item -ItemType Directory -Force -Path $Dir)
    Copy-Item -LiteralPath (Join-Path $here "FakeWezfleet.ps1") -Destination (Join-Path $Dir "wezfleet.ps1")
    foreach ($marker in @("lib\Mail.ps1", "lib\MailPost.ps1", "commands\mail.ps1")) {
        $mp = Join-Path $Dir $marker
        [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mp))
        [System.IO.File]::WriteAllText($mp, "# a marker stub`r`n")
    }
    return $Dir
}
function New-Shim {
    # A wezfleet.cmd in -Dir holding -Line after the lines a real shim starts with.
    param([string]$Dir, [string]$Line, [string]$Name = "wezfleet.cmd")
    [void](New-Item -ItemType Directory -Force -Path $Dir)
    [System.IO.File]::WriteAllText((Join-Path $Dir $Name), ("@echo off`r`nrem a fake shim for the messenger's tests`r`nsetlocal`r`n" + $Line + "`r`nendlocal & exit /b %ERRORLEVEL%`r`n"), [System.Text.Encoding]::ASCII)
}
# THE SHAPE OF THE REAL SHIM wezfleet installs beside its checkout (read 2026-10-09: bin\wezfleet.cmd runs
# bin\wezfleet\wezfleet.ps1), so the case that follows it reads what a real machine has.
$realShape = 'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0wezfleet\wezfleet.ps1" %*'
function Runs { param([string]$Dir) $p = Join-Path $Dir "argv.log"; if (-not (Test-Path -LiteralPath $p)) { return 0 }; return @([System.IO.File]::ReadAllLines($p) | Where-Object { $_.Trim() -ne "" }).Count }
function New-Home { $script:n++; return (New-Dir ("home" + $script:n)) }
function Set-Root {
    # The messenger's settings file under -HordeHome, holding -Text as it is.
    param([string]$HordeHome, [string]$Text)
    $d = Join-Path $HordeHome "settings"
    [void](New-Item -ItemType Directory -Force -Path $d)
    [System.IO.File]::WriteAllText((Join-Path $d "messenger-wezfleet.json"), $Text, (New-Object System.Text.UTF8Encoding($false)))
}
function RootJson { param([string]$Dir) return ([pscustomobject]@{ schemaVersion = 1; settings = [pscustomobject]@{ root = $Dir } } | ConvertTo-Json -Compress -Depth 3) }
function Probe {
    # Runs RootProbe.ps1 in a child whose PATH is -PathValue alone and whose home is -HordeHome. Returns
    # its answers, one { state; reason } per line.
    param([string]$PathValue, [string]$HordeHome, [string]$ThenRoot = "", [switch]$Post)
    $argv = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $probe + '" -Root "' + $root + '"'
    if ($ThenRoot -ne "") { $argv += ' -ThenRoot "' + $ThenRoot + '"' }
    if ($Post) { $argv += ' -Post' }
    $psi = New-Object System.Diagnostics.ProcessStartInfo($fixedPs, $argv)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables["PATH"] = $PathValue
    $psi.EnvironmentVariables["HORDE_HOME"] = $HordeHome
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    if (-not $p.WaitForExit(120000)) { $p.Kill(); throw "the probe did not finish within 120 s" }
    $answers = @("$out" -split "`r?`n" | Where-Object { $_.Trim().StartsWith("{") } | ForEach-Object { $_ | ConvertFrom-Json })
    if ($answers.Count -eq 0) { Write-Host ("  probe printed no answer; stderr: " + $errTask.Result) -ForegroundColor Yellow }
    return $answers
}
function Show { param($A) if ($null -eq $A) { return "no answer" }; return ($A.state + ": " + $A.reason) }

try {
    Write-Host ""
    Write-Host "--- A. the setting: declared, and winning over the command on PATH ---" -ForegroundColor Cyan
    . (Join-Path $root "messengers\Port.ps1")
    . (Join-Path $root "messengers\wezfleet\Messenger.ps1")
    # Looked up, not read: under strict mode a variable that is not there would abandon the whole block.
    $declVar = Get-Variable -Name "HordeWezfleetMessengerSettings" -Scope Script -ErrorAction SilentlyContinue
    $declOk = $false
    if ($null -ne $declVar) {
        $decl = $declVar.Value
        $entry = @($decl.settings | Where-Object { $_.name -ceq "root" })
        $declOk = ($decl.module -ceq "messenger-wezfleet" -and @($decl.settings).Count -eq 1 -and $entry.Count -eq 1 -and $entry[0].kind -ceq "folder" -and $entry[0].default -ceq "")
    }
    Check $declOk "the messenger declares one setting, root, a folder whose default is empty (module messenger-wezfleet)"

    $shimA = New-Dir "pathA"
    $ckA = New-Checkout (Join-Path $shimA "wezfleet")
    New-Shim -Dir $shimA -Line $realShape
    $ckB = New-Checkout (Join-Path $work "settingB")
    $h = New-Home
    Set-Root -HordeHome $h -Text (RootJson $ckB)
    $a = @(Probe -PathValue $shimA -HordeHome $h)
    Check ($a.Count -eq 1 -and $a[0].state -ceq "absent" -and (Runs $ckB) -eq 1 -and (Runs $ckA) -eq 0) ("a root in the settings file wins: its checkout ran, and the one the command on PATH leads to did not (" + (Show $a[0]) + ")")

    $h = New-Home
    Set-Root -HordeHome $h -Text '{ "schemaVersion": 1, "settings": { "root": "relative\\fleet" } }'
    $before = Runs $ckA
    $a = @(Probe -PathValue $shimA -HordeHome $h)
    Check ($a.Count -eq 1 -and $a[0].state -ceq "unknown" -and $a[0].reason.Contains("refused") -and $a[0].reason.Contains("messenger-wezfleet.json") -and $a[0].reason.Contains("'root'") -and (Runs $ckA) -eq $before) ("a settings file that is refused makes a status unknown with its findings, and the command on PATH is never used in its place (" + (Show $a[0]) + ")")
    $h = New-Home
    Set-Root -HordeHome $h -Text '{ "schemaVersion": 1, "settings": { "rot": "C:\\fleet" } }'
    $a = @(Probe -PathValue $shimA -HordeHome $h -Post)
    Check ($a.Count -eq 1 -and $a[0].state -ceq "unknown" -and $a[0].reason.Contains("refused") -and $a[0].reason.Contains("'rot'") -and (Runs $ckA) -eq $before -and -not (Test-Path -LiteralPath (Join-Path $h "messengers\wezfleet\outgoing"))) ("and so is a post, before any body file is written (" + (Show $a[0]) + ")")

    Write-Host ""
    Write-Host "--- B. no setting: the checkout the wezfleet command on PATH runs ---" -ForegroundColor Cyan
    $h = New-Home
    $a = @(Probe -PathValue $shimA -HordeHome $h)
    Check ($a.Count -eq 1 -and $a[0].state -ceq "absent" -and (Runs $ckA) -eq ($before + 1)) ("a .cmd shim of the real shape on PATH leads to the checkout it runs, %~dp0wezfleet\wezfleet.ps1, which answered (" + (Show $a[0]) + ")")

    $ckP = New-Checkout (Join-Path $work "pathP")
    $a = @(Probe -PathValue $ckP -HordeHome (New-Home))
    Check ($a.Count -eq 1 -and $a[0].state -ceq "absent" -and (Runs $ckP) -eq 1) ("a wezfleet.ps1 on PATH is its checkout's own script: its folder is the checkout (" + (Show $a[0]) + ")")

    $empty = New-Dir "pathEmpty"
    $a = @(Probe -PathValue $empty -HordeHome (New-Home))
    Check ($a.Count -eq 1 -and $a[0].state -ceq "unknown" -and $a[0].reason.Contains("no wezfleet command is on PATH") -and $a[0].reason.Contains("messenger-wezfleet.json")) ("nothing on PATH and no setting is unknown, saying so and naming the settings file that would name it (" + (Show $a[0]) + ")")

    $odd = New-Dir "pathOdd"
    New-Shim -Dir $odd -Line 'powershell -NoProfile -File "%WEZFLEET_HOME%\wezfleet.ps1" %*'
    $a = @(Probe -PathValue $odd -HordeHome (New-Home))
    Check ($a.Count -eq 1 -and $a[0].state -ceq "unknown" -and $a[0].reason.Contains("shim") -and $a[0].reason.Contains((Join-Path $odd "wezfleet.cmd"))) ("a shim that does not name %~dp0...wezfleet.ps1 is unknown, naming the shim: its checkout is not guessed (" + (Show $a[0]) + ")")

    $two = New-Dir "pathTwo"
    $null = New-Checkout (Join-Path $two "one")
    $null = New-Checkout (Join-Path $two "two")
    New-Shim -Dir $two -Line ('if "%1"=="x" (powershell -File "%~dp0one\wezfleet.ps1" %*) else (powershell -File "%~dp0two\wezfleet.ps1" %*)')
    $a = @(Probe -PathValue $two -HordeHome (New-Home))
    Check ($a.Count -eq 1 -and $a[0].state -ceq "unknown" -and $a[0].reason.Contains("shim") -and (Runs (Join-Path $two "one")) -eq 0 -and (Runs (Join-Path $two "two")) -eq 0) ("a shim that names two checkouts is unknown, and neither is run (" + (Show $a[0]) + ")")

    $bare = New-Dir "pathBare"
    New-Shim -Dir $bare -Line 'powershell -NoProfile -File "%~dp0fleet\wezfleet.ps1" %*'
    [void](New-Item -ItemType Directory -Force -Path (Join-Path $bare "fleet"))
    [System.IO.File]::WriteAllText((Join-Path $bare "fleet\wezfleet.ps1"), "exit 0`r`n")
    $a = @(Probe -PathValue $bare -HordeHome (New-Home))
    Check ($a.Count -eq 1 -and $a[0].state -ceq "unknown" -and $a[0].reason.Contains("not a wezfleet checkout") -and $a[0].reason.Contains("PATH")) ("the folder a shim leads to passes the same checks: without the markers it is not a checkout, and the reason says it came from PATH (" + (Show $a[0]) + ")")

    $climb = New-Dir "pathClimb\bin"
    $null = New-Checkout (Join-Path $work "pathClimb\fleet")
    New-Shim -Dir $climb -Line 'powershell -NoProfile -File "%~dp0..\fleet\wezfleet.ps1" %*'
    $a = @(Probe -PathValue $climb -HordeHome (New-Home))
    Check ($a.Count -eq 1 -and $a[0].state -ceq "unknown" -and $a[0].reason.Contains("without ..") -and (Runs (Join-Path $work "pathClimb\fleet")) -eq 0) ("a shim that climbs with .. is refused as a configured folder that climbs is, not resolved first (" + (Show $a[0]) + ")")

    Write-Host ""
    Write-Host "--- C. read when the messenger needs the folder, not once when it loads ---" -ForegroundColor Cyan
    $ckC = New-Checkout (Join-Path $work "laterC")
    $a = @(Probe -PathValue $empty -HordeHome (New-Home) -ThenRoot $ckC)
    Check ($a.Count -eq 2 -and $a[0].state -ceq "unknown" -and $a[1].state -ceq "absent" -and (Runs $ckC) -eq 1) ("a settings file written after the first status is used by the next one, in the same process (" + (Show @($a)[0]) + " / " + (Show @($a)[-1]) + ")")

    Write-Host ""
    Write-Host "--- D. Set-HordeWezfleetMessengerRoot, for tests, wins over the setting ---" -ForegroundColor Cyan
    $pinned = Enter-HordeTestPinnedHome -Root $root
    try {
        $ckD = New-Checkout (Join-Path $work "setD")
        Set-HordeWezfleetMessengerRoot -Path $ckD -TimeoutSeconds 60
        $m = Get-HordeMessenger -Name "wezfleet"
        $s = Get-HordeMessengerStatus -Messenger $m -MessageId "0e000000-0000-4000-8000-000000000001"
        Check ($s.state -ceq "absent" -and (Runs $ckD) -eq 1) ("a root set in the process wins over a root in the settings file (" + $s.state + ")")
        Set-HordeWezfleetMessengerRoot -Path ""
        $s = Get-HordeMessengerStatus -Messenger $m -MessageId "0e000000-0000-4000-8000-000000000001"
        Check ($s.state -ceq "unknown" -and "$($s.reason)".Contains("no-wezfleet") -and (Runs $ckD) -eq 1) ("and unset again, the settings file is read again (" + $s.reason + ")")
    } finally { Set-HordeWezfleetMessengerRoot -Path ""; Exit-HordeTestPinnedHome -State $pinned }

    Write-Host ""
    Write-Host "--- E. the pin other suites use: a pinned home never reaches the command on PATH ---" -ForegroundColor Cyan
    $hp = New-Home
    $names = @(Set-HordeTestMessengerPins -Root $root -HordeHome $hp)
    Check ($names -ccontains "wezfleet" -and (Test-Path -LiteralPath (Join-Path $hp "settings\messenger-wezfleet.json") -PathType Leaf)) ("Set-HordeTestMessengerPins runs this messenger's pin: it writes settings\messenger-wezfleet.json in the home (" + ($names -join ", ") + ")")
    $before = Runs $ckA
    $a = @(Probe -PathValue $shimA -HordeHome $hp)
    Check ($a.Count -eq 1 -and $a[0].state -ceq "unknown" -and $a[0].reason.Contains("not a wezfleet checkout") -and (Runs $ckA) -eq $before) ("with a wezfleet command on PATH that leads to a working checkout, a pinned home is unknown and that checkout never ran (" + (Show $a[0]) + ")")
    $a = @(Probe -PathValue $shimA -HordeHome (New-Home))
    Check ($a.Count -eq 1 -and $a[0].state -ceq "absent" -and (Runs $ckA) -eq ($before + 1)) ("CONTROL: the same PATH with an unpinned home does reach it, so the pin is what stopped it (" + (Show $a[0]) + ")")
    Check (Throws { & (Join-Path $here "Pin.ps1") -HordeHome (Join-Path $env:USERPROFILE ".horde-never") } "temp folder") "the pin refuses a home outside the temp folder, so it never writes a person's real home"
} finally {
    if ((Split-Path -Leaf $work) -match '\Ahorde-wfr-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "the wezfleet messenger's folder is the setting, else what the wezfleet command on PATH runs, checked the same way, and a pinned home reaches nothing"
