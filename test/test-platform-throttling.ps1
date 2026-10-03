# DOES HORDE OPT ITS BUSY PROCESSES OUT OF WINDOWS POWER THROTTLING, AND DOES IT STAY FAST?
#
# core/Platform.ps1, Set-HordeThrottlingOptOut and Get-HordeThrottlingState. Measured 2026-10-02 on the
# development machine: a busy background process slows about 3 s in (an empty PowerShell call 23 us to
# 165 us), and the opt-out removes it. The opt-out is per process and NOT inherited, so the entry point,
# the mutation tool's suites and the test library's children each apply it.
#
# Every process this suite starts it stops itself, by the handle it holds.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\Platform.ps1")
. (Join-Path $root "test\lib\Program.ps1")

$onWindows = Test-HordeIsWindows

Write-Host ""
Write-Host "--- off Windows it does nothing, and says so ---" -ForegroundColor Cyan
$a = Set-HordeThrottlingOptOut -OsPlatform "Unix"
Check ($a.state -eq "absent" -and $a.reason -like "*not Windows*") "on another system the opt-out is absent, with the reason"
$a = Get-HordeThrottlingState -OsPlatform "Unix"
Check ($a.state -eq "absent") "and so is the state"

if (-not $onWindows) {
    Write-Host "  [SKIP] the Windows sections: this is not Windows" -ForegroundColor Yellow
    Complete-HordeSuite -Success "OFF WINDOWS - ONLY THE NOTHING-TO-DO PATH RAN, EXIT 3" -PassCode 3
}

Write-Host ""
Write-Host "--- the state reads back ---" -ForegroundColor Cyan
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"; $psi.Arguments = "-NoProfile -Command Start-Sleep -Seconds 30"
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$child = [System.Diagnostics.Process]::Start($psi)
try {
    $s = Get-HordeThrottlingState -Process $child
    Check ($s.state -eq "known" -and $s.value.controlMask -eq 0 -and $s.value.optedOut -eq $false) ("CONTROL: a fresh child has no throttling policy of its own (" + $s.value.controlMask + "/" + $s.value.stateMask + ")")
    $r = Set-HordeThrottlingOptOut -Process $child
    Check ($r.state -eq "known" -and $r.value -ceq "set") "the opt-out is set on a child by its handle"
    $s = Get-HordeThrottlingState -Process $child
    Check ($s.state -eq "known" -and $s.value.controlMask -eq 1 -and $s.value.stateMask -eq 0 -and $s.value.optedOut -eq $true) "and the child reads back opted out: ControlMask 1, StateMask 0"
} finally { if (-not $child.HasExited) { $child.Kill() }; $child.Dispose() }
# CONTROL for the readback's own rule: a process that decides throttling ON (ControlMask 1, StateMask
# 1) is not opted out, though its ControlMask is set. Set by a helper of this suite's own.
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class ThrottleOnForTest {
    [StructLayout(LayoutKind.Sequential)] public struct S { public uint V; public uint C; public uint M; }
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetProcessInformation(IntPtr h, int c, ref S i, uint n);
    public static bool On(IntPtr h) { var s = new S { V = 1, C = 1, M = 1 }; return SetProcessInformation(h, 4, ref s, (uint)Marshal.SizeOf(s)); }
}
"@
$child2 = [System.Diagnostics.Process]::Start($psi)
try {
    Check ([ThrottleOnForTest]::On($child2.Handle)) "CONTROL: a child can be set to throttling on"
    $s = Get-HordeThrottlingState -Process $child2
    Check ($s.state -eq "known" -and $s.value.controlMask -eq 1 -and $s.value.stateMask -eq 1 -and $s.value.optedOut -eq $false) "a child set to throttling on reads back as NOT opted out, though its ControlMask is set"
} finally { if (-not $child2.HasExited) { $child2.Kill() }; $child2.Dispose() }
$r = Set-HordeThrottlingOptOut
Check ($r.state -eq "known" -and (Get-HordeThrottlingState).value.optedOut -eq $true) "a process opts itself out, and reads back opted out"

Write-Host ""
Write-Host "--- every place Horde starts sustained work applies it ---" -ForegroundColor Cyan
# horde.ps1, the entry point, opts out a command that declares itself sustained; tools/Mutate.ps1 opts out each
# suite it starts; the test library's program runner opts out each child. Read from the source, and for
# the runner, from the child itself.
$entry = [System.IO.File]::ReadAllText((Join-Path $root "horde.ps1"))
Check ($entry -match 'sustained -eq \$true\) \{[^}]{0,600}?& \{ \. \(Join-Path \$PSScriptRoot "core\\Platform\.ps1"\); Set-HordeThrottlingOptOut \}' -and $entry -notmatch '(?m)^\$null = Set-HordeThrottlingOptOut') "horde.ps1 opts out a command that declares itself sustained, in a scope of its own, and only such a command (test-cli runs both)"
$mut = [System.IO.File]::ReadAllText((Join-Path $root "tools\Mutate.ps1"))
Check ($mut -match '\$p = \[System\.Diagnostics\.Process\]::Start\(\$psi\)\s*\r?\n\s*\$null = Set-HordeThrottlingOptOut -Process \$p') "tools/Mutate.ps1 opts out each suite right after starting it"
$probe = Join-Path $env:TEMP ("horde-throttle-probe-" + [guid]::NewGuid().ToString("N") + ".ps1")
try {
    [System.IO.File]::WriteAllText($probe, ('. ''' + (Join-Path $root "core\Platform.ps1") + '''' + "`r`n" + 'Start-Sleep -Milliseconds 500' + "`r`n" + '$s = Get-HordeThrottlingState; Write-Output ("STATE " + $s.value.controlMask + "/" + $s.value.stateMask)' + "`r`n"))
    $run = Invoke-HordeTestProgram -Path (Find-HordeTestProgram -Name "powershell") -ArgList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $probe) -WorkDir $env:TEMP -TimeoutSeconds 60
    Check ($run.out -match 'STATE 1/0') ("a child started by the test library's runner reads itself opted out (" + (($run.out -split "`n") | Where-Object { $_ -like "STATE*" }) + ")")
} finally { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "--- a 10 s busy loop stays fast ---" -ForegroundColor Cyan
# The loop measures an empty function call's median cost in its first 2.5 s and after 5 s. Throttled,
# the late cost was about seven times the early one (23 us to 165 us); opted out, it stays level. The
# run without the opt-out is printed as a measurement, not asserted: whether a machine throttles at all
# depends on its power plan, so only the opted-out run makes a promise.
$bench = Join-Path $env:TEMP ("horde-throttle-bench-" + [guid]::NewGuid().ToString("N") + ".ps1")
try {
    [System.IO.File]::WriteAllText($bench, (@'
param([switch]$OptOut)
. '__PLATFORM__'
if ($OptOut) { $null = Set-HordeThrottlingOptOut }
function F0 { }
$start = [Diagnostics.Stopwatch]::StartNew(); $early = New-Object System.Collections.ArrayList; $late = New-Object System.Collections.ArrayList
while ($start.Elapsed.TotalSeconds -lt 10) {
    $sw = [Diagnostics.Stopwatch]::StartNew(); for ($q = 0; $q -lt 2000; $q++) { F0 }; $us = $sw.Elapsed.TotalMilliseconds * 1000 / 2000
    if ($start.Elapsed.TotalSeconds -lt 2.5) { [void]$early.Add($us) } elseif ($start.Elapsed.TotalSeconds -gt 5) { [void]$late.Add($us) }
}
function Med($a) { $s = @($a | Sort-Object); return $s[[int]($s.Count / 2)] }
Write-Output ("BENCH early=" + [math]::Round((Med $early), 1) + " late=" + [math]::Round((Med $late), 1))
'@).Replace("__PLATFORM__", (Join-Path $root "core\Platform.ps1")))
    function Invoke-Bench { param([string[]]$Extra)
        $r = Invoke-HordeTestProgram -Path (Find-HordeTestProgram -Name "powershell") -ArgList (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $bench) + $Extra) -WorkDir $env:TEMP -TimeoutSeconds 60
        $m = [regex]::Match($r.out, 'BENCH early=([0-9.]+) late=([0-9.]+)')
        if (-not $m.Success) { return $null }
        return [pscustomobject]@{ early = [double]$m.Groups[1].Value; late = [double]$m.Groups[2].Value }
    }
    $off = Invoke-Bench @("-OptOut")
    Check ($null -ne $off -and $off.late -le ($off.early * 2.5)) ("opted out, the loop's late call cost stays within 2.5 times its early cost (early " + $off.early + " us, late " + $off.late + " us)")
    $on = Invoke-Bench @()
    if ($null -ne $on) { Write-Host ("  MEASURE without the opt-out: early " + $on.early + " us, late " + $on.late + " us (ratio " + [math]::Round($on.late / [math]::Max($on.early, 0.001), 1) + ")") -ForegroundColor DarkGray }
} finally { Remove-Item -LiteralPath $bench -Force -ErrorAction SilentlyContinue }

Complete-HordeSuite -Success "Horde's busy processes run opted out of power throttling, and stay fast"
