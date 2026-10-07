# DOES THE WINDOWS FOLLOWER ANSWER THE PORT, AND REFUSE WHAT IT MUST WITHOUT TOUCHING A WINDOW?
#
# platform/windows/WindowFollow.ps1, asked only through core/WindowFollowPort.ps1, as a caller asks.
# Where a companion stands is the port's pure function and is test/test-window-follow-port.ps1's. This
# suite holds what is the Windows follower's own: that it is found by folder and registers itself,
# that real scale has one owner, and the refusals that need no window to give.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\WindowFollowPort.ps1")
# A home of this run's own, which is never made: a follow started with no settings handed in reads the
# person's file, and the person's real one is not this suite's to read.
$env:HORDE_HOME = Join-Path $env:TEMP ("horde-follow-home-" + [guid]::NewGuid().ToString("N"))

function Field {
    # A field of an object, or the text "<none>" when it is not there - so that a missing field fails a
    # check instead of raising under strict mode.
    param($From, [string]$Name)
    if ($null -eq $From -or $null -eq $From.PSObject.Properties[$Name]) { return "<none>" }
    return $From.PSObject.Properties[$Name].Value
}

Write-Host ""
Write-Host "--- found by folder, and registered by being loaded ---" -ForegroundColor Cyan
$before = Get-HordeWindowFollower
Check ($before.state -ceq "unknown") "CONTROL: before any follower's file is loaded the port has none"
$files = @(Get-HordeWindowFollowerFiles -Root $root)
Check ($files.Count -eq 1 -and $files[0] -like "*\platform\windows\WindowFollow.ps1") ("the port finds this follower's file by folder, and no other (" + $files.Count + ")")
Check ($null -eq ("HordeWindowsFollowV1" -as [type])) "CONTROL: nothing native is loaded yet"
foreach ($file in $files) { . $file }
Check ($null -eq ("HordeWindowsFollowV1" -as [type])) "loading the file compiles nothing and asks Windows nothing"
$mine = Get-HordeWindowFollower
Check ($mine.state -ceq "known" -and (Field $mine.value "name") -ceq "windows") "loaded, it is the follower the port asks on this system"

Write-Host ""
Write-Host "--- real scale has one owner, and it is not this file ---" -ForegroundColor Cyan
$followText = [System.IO.File]::ReadAllText((Join-Path $root "platform\windows\WindowFollow.ps1"))
$scaleText = [System.IO.File]::ReadAllText((Join-Path $root "platform\windows\Scale.ps1"))
Check ($scaleText.Contains("SetProcessDpiAwarenessContext") -and $followText.Contains("SetWindowPos")) "CONTROL: the search sees the awareness call in its owner's file, and a call this file does make"
Check (-not $followText.Contains("SetProcessDpiAwarenessContext")) "the follower does not ask Windows for the awareness in words of its own"
Check ($null -eq (Get-Command -Name "Enable-HordeWindowRealPixels" -ErrorAction SilentlyContinue) -and $null -ne (Get-Command -Name "Enable-HordeWindowsRealScale" -ErrorAction SilentlyContinue)) "and loading it brings the one owner's function, not a second one"

if (-not (Test-HordeIsWindows)) {
    Write-Host "  [SKIP] everything that asks Windows: this is not Windows" -ForegroundColor Yellow
    Complete-HordeSuite -Success "OFF WINDOWS - ONLY THE LOADING WAS CHECKED, EXIT 3" -PassCode 3
}

Write-Host ""
Write-Host "--- the follower refuses without touching any window ---" -ForegroundColor Cyan
$r = Get-HordeWindowFollow
Check ((Field $r "state") -ceq "none" -and (Field $r "target") -eq 0 -and $null -eq (Field $r "placed")) "CONTROL: nothing is followed until something is started"
Check ((Field (Update-HordeWindowFollow) "state") -ceq "none") "placing again when nothing is followed places nothing"
# 2147480001 and 2147480003: no window has such a handle (the first check proves it of the first).
$gone = Get-HordeWindowFollowRectangle -Handle 2147480001
Check ((Test-HordeAnswer $gone) -and $gone.state -ceq "absent") "a handle that is no window has no rectangle: absent, which is not unknown"
$r = Start-HordeWindowFollow -Target 2147480001 -Companion 2147480003
Check ((Field $r "state") -ceq "failed" -and (Field $r "reason") -ceq "the window to stand beside does not exist") "a handle that is no window cannot be stood beside: failed, in words"
Check ((Field (Get-HordeWindowFollow) "state") -ceq "none") "and after that refusal nothing is being followed"
Check ((Field (Disconnect-HordeWindowFollow) "state") -ceq "none") "letting go when nothing is followed does nothing"
Check ((Field (Stop-HordeWindowFollow) "state") -ceq "none") "and so does stopping"

Complete-HordeSuite -Success "the Windows follower is found by folder, answers the port, and refuses what is not a window"
