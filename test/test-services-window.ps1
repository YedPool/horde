# IS A WINDOW ASKED TO CLOSE ONLY WHEN IT IS A WINDOW OF THE PROCESS NAMED - AND DOES ASKING CLOSE IT?
#
# platform/windows/Services.ps1, Close-HordeWindowsServiceWindow, through core/ServiceHostPort.ps1.
#
# THE ONLY WINDOW TOUCHED IS ONE THIS SUITE MAKES (CONTRIBUTING 9): a child PowerShell of the suite's
# own shows one empty form, far off every screen, fully transparent and out of the taskbar, and writes
# its handle into the suite's temp folder. Every close is aimed at THAT handle, or at a number that is
# no window at all; no window is ever looked for by title or class. The child ends by itself after
# 60 s, and is ended in the finally block by the handle the suite kept on it.
#
# NEEDS A DESKTOP. A form can only be shown in a logon session that has one. Where the child cannot
# show its form the suite says so, checks only what needs no window, and exits 3, so a gate that
# expects 0 never reads the partial run as the whole one.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "ServiceHostPort")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "platform\windows\Services.ps1")

$work = Join-Path $env:TEMP ("horde-services-window-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$handleFile = Join-Path $work "handle.txt"
$closedFile = Join-Path $work "closed.txt"
$child = $null
$skipped = $false

try {
    Write-Host ""
    Write-Host "--- a number that is no window ---" -ForegroundColor Cyan
    $none = Close-HordeServiceWindow -ProcessId $PID -Handle 1
    Check ($none.state -ceq "absent" -and $none.reason -like "*there is no window 1 any more; nothing was sent*") "a handle that is not a window is absent: nothing is sent"
    Check ((Close-HordeServiceWindow -ProcessId $PID -Handle 0).state -ceq "unknown") "no handle at all is refused by the port before the adapter is asked"

    Write-Host ""
    Write-Host "--- this suite's own window ---" -ForegroundColor Cyan
    $script = @'
param($HandleFile, $ClosedFile)
Add-Type -AssemblyName System.Windows.Forms
$f = New-Object System.Windows.Forms.Form
$f.Text = "Horde test window"; $f.ShowInTaskbar = $false; $f.Opacity = 0
$f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$f.Location = New-Object System.Drawing.Point(-32000, -32000)
$f.Add_Shown({ [System.IO.File]::WriteAllText($HandleFile, ("" + $f.Handle.ToInt64())) })
$f.Add_FormClosed({ [System.IO.File]::WriteAllText($ClosedFile, "closed by its own close") })
$t = New-Object System.Windows.Forms.Timer
$t.Interval = 60000; $t.Add_Tick({ $f.Close() }); $t.Start()
[System.Windows.Forms.Application]::Run($f)
'@
    $scriptFile = Join-Path $work "window.ps1"
    [System.IO.File]::WriteAllText($scriptFile, $script)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $scriptFile + '" "' + $handleFile + '" "' + $closedFile + '"'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $child = [System.Diagnostics.Process]::Start($psi)
    $deadline = (Get-Date).AddSeconds(45)
    while (-not (Test-Path -LiteralPath $handleFile) -and -not $child.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
    if (-not (Test-Path -LiteralPath $handleFile)) {
        $skipped = $true
        Write-Host "  [SKIP] the child could not show a window here (no desktop in this logon session): the checks that need one were not run"
    } else {
        $handle = [long][System.IO.File]::ReadAllText($handleFile)
        Check ($handle -gt 0) "the child showed its window and said which"
        $other = Close-HordeServiceWindow -ProcessId $PID -Handle $handle
        Start-Sleep -Milliseconds 1500
        Check ($other.state -ceq "absent" -and $other.reason -like ("*is not a window of process " + $PID + "; nothing was sent*") -and -not $child.HasExited -and -not (Test-Path -LiteralPath $closedFile)) "asked to close it as the window of ANOTHER process, nothing is sent: the window is still there"
        $asked = Close-HordeServiceWindow -ProcessId $child.Id -Handle $handle
        Check ($asked.state -ceq "known" -and $asked.value -ceq "asked") "asked as the window of the process that owns it, the close is sent"
        Check ($child.WaitForExit(20000) -and (Test-Path -LiteralPath $closedFile) -and [System.IO.File]::ReadAllText($closedFile) -ceq "closed by its own close" -and $child.ExitCode -eq 0) "and the program closes its own window the way it always does, and ends by itself"
        $gone = Close-HordeServiceWindow -ProcessId $child.Id -Handle $handle
        Check ($gone.state -ceq "absent") "the same handle afterwards is no window: asking again sends nothing"
    }
} finally {
    if ($null -ne $child) { try { if (-not $child.HasExited) { $child.Kill() } } catch { }; $child.Dispose() }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($skipped) { Complete-HordeSuite -Success "a number that is no window is never sent to; the checks that need a desktop were SKIPPED" -PassCode 3 }
Complete-HordeSuite -Success "a window is asked to close only when it is a window of the process named, and then it closes itself"
