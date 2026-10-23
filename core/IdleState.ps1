# core/IdleState - is this PC idle, or is it night? The ONE answer behind `horde idle` and the local gate
# (tools/HeavySlot.ps1). T-0331.
#
# THE FOUNDER'S RULE (2026-10-22). Every test suite, mutation run, heavy-slot run, guard run and review
# starts only when the PC has had NO keyboard or mouse input for 10 minutes, or at night (22:00 to 07:00
# local). A run already going may finish. This file answers the question; it starts and stops nothing.
#
# WHAT "INPUT" MEANS. Windows' GetLastInputInfo: the last real keyboard or mouse event of the logged-on
# session. Text the fleet types into panes (the terminal host's send-text, which writes to the pane's
# pty through the terminal's own multiplexer and creates no OS input event) does not reset it. Read on
# 2026-10-22: no code of this repository, and none of the fleet's pane messenger, calls SendInput,
# keybd_event, mouse_event or SendKeys.
#
# GetLastInputInfo ONLY SEES THE INTERACTIVE SESSION. A process in session 0, or one with no interactive
# window station (a scheduled task run whether or not the user is logged on, an S4U task, a service),
# reads a value that has nothing to do with the person at the desk. Read-HordeIdleSeconds says "unknown"
# there, and Get-HordeIdleState treats unknown as NOT idle - unless it is night, when nothing needs to
# be known.
#
# THE SETTINGS of the module "idle", in <HORDE_HOME>\settings\idle.json:
#   idleSeconds     how long without input counts as idle (default 600)
#   nightStartHour  the first hour of night, 0 to 23 (default 22)
#   nightEndHour    the hour night ends, 0 to 24 (default 7); the end hour itself is day. 0 and 24 for
#                   start and end make every hour night, which a test of the gate uses to stand clear of
#                   the machine's real clock.
# A settings file that fails its checks is refused with its findings; the defaults never stand in.
#
# EVERYTHING IMPURE IS INJECTED, so a test needs no real wait and no real input: the clock (-Now), the
# input reader (-Reader), the sleep and the elapsed time of the wait.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "ModuleSettings.ps1")

function Get-HordeIdleSettingsDeclaration {
    # The declaration of the module "idle", built on each call (a $script: variable would not be seen
    # from a command's run block: cli/Commands.ps1).
    return (New-HordeModuleSettings -Module "idle" -Settings @(
        @{ name = "idleSeconds"; kind = "whole"; default = 600; min = 1; max = 86400
           what = "Seconds without keyboard or mouse input after which the PC counts as idle." },
        @{ name = "nightStartHour"; kind = "whole"; default = 22; min = 0; max = 23
           what = "The first local hour of night, 0 to 23." },
        @{ name = "nightEndHour"; kind = "whole"; default = 7; min = 0; max = 24
           what = "The local hour night ends at, 0 to 24; that hour itself is day." }
    ))
}

function Get-HordeIdleConfig {
    # { ok; idleSeconds; nightStartHour; nightEndHour; findings; path }: the settings, or ok = $false with
    # the sentence that says which file and key are wrong. Never falls back to the defaults over a bad file.
    param([string]$HordeHome = "")
    $no = { param($why) [pscustomobject]@{ ok = $false; idleSeconds = 0; nightStartHour = 0; nightEndHour = 0; findings = @($why); path = "" } }
    try {
        $decl = Get-HordeIdleSettingsDeclaration
        if ($HordeHome -ne "") { $s = Get-HordeModuleSettings -Declaration $decl -HordeHome $HordeHome }
        else { $s = Get-HordeModuleSettings -Declaration $decl }
    } catch { return (& $no ("the idle settings cannot be read: " + $_.Exception.Message)) }
    if ($s.state -ceq "refused") { return [pscustomobject]@{ ok = $false; idleSeconds = 0; nightStartHour = 0; nightEndHour = 0; findings = @($s.findings); path = "" + $s.path } }
    return [pscustomobject]@{ ok = $true; idleSeconds = [int]$s.values.idleSeconds; nightStartHour = [int]$s.values.nightStartHour; nightEndHour = [int]$s.values.nightEndHour; findings = @(); path = "" + $s.path }
}

function Test-HordeNightHour {
    # Is a local hour (0 to 23) inside the night that runs from Start to End? The start hour is night, the
    # end hour is day; a night that crosses midnight (22 to 7) is both ends of the clock. Start equal to
    # End is no night at all, and 0 to 24 is every hour.
    param([int]$Hour, [int]$Start = 22, [int]$End = 7)
    if ($Start -eq $End) { return $false }
    if ($Start -lt $End) { return ($Hour -ge $Start -and $Hour -lt $End) }
    return ($Hour -ge $Start -or $Hour -lt $End)
}

function Read-HordeIdleSeconds {
    # The real input reader: { state = "known"; seconds } or { state = "unknown"; reason }. Unknown is a
    # process with no interactive session (see the header) or a GetLastInputInfo that failed.
    if (-not ([System.Management.Automation.PSTypeName]"HordeIdleInputV1").Type) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HordeIdleInputV1 {
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
    [DllImport("kernel32.dll")] static extern bool ProcessIdToSessionId(uint pid, out uint session);
    // Milliseconds since the last input of this session; -1 when GetLastInputInfo failed; -2 when this
    // process is not in an interactive session (session 0, or a window station that is not interactive).
    public static long IdleMs() {
        uint session;
        if (!ProcessIdToSessionId((uint)System.Diagnostics.Process.GetCurrentProcess().Id, out session) || session == 0) return -2;
        if (!Environment.UserInteractive) return -2;
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref info)) return -1;
        // Both are 32-bit tick counts that wrap together (every 49.7 days); the difference stays right.
        return (long)unchecked((uint)Environment.TickCount - info.dwTime);
    }
}
'@
    }
    $ms = [long][HordeIdleInputV1]::IdleMs()
    if ($ms -eq -2) { return [pscustomobject]@{ state = "unknown"; seconds = 0; reason = "this process is not in an interactive session, so its input clock is not the person's" } }
    if ($ms -lt 0) { return [pscustomobject]@{ state = "unknown"; seconds = 0; reason = "GetLastInputInfo failed" } }
    return [pscustomobject]@{ state = "known"; seconds = [int][math]::Floor($ms / 1000); reason = "" }
}

function Get-HordeIdleState {
    # The answer: { allowed; why; night; idleKnown; idleSeconds; needSeconds; time; reason }.
    #   why   "night" (allowed), "idle" (allowed), "busy" (input too recent), "unknown" (input unreadable
    #         and not night). Night wins: it needs no reading of the input.
    #   time  the local time as HH:mm:ss, so the line a person reads says what clock was used.
    # -Now and -Reader are injected by tests: -Now returns a [datetime], -Reader returns what
    # Read-HordeIdleSeconds does. A reader that throws is "unknown", never an allowance.
    param(
        [Parameter(Mandatory = $true)]$Config,
        [scriptblock]$Now = { Get-Date },
        [scriptblock]$Reader = { Read-HordeIdleSeconds }
    )
    $at = [datetime](& $Now)
    $night = Test-HordeNightHour -Hour $at.Hour -Start $Config.nightStartHour -End $Config.nightEndHour
    $r = $null
    try { $r = & $Reader } catch { $r = [pscustomobject]@{ state = "unknown"; seconds = 0; reason = ("the input reader failed: " + $_.Exception.Message) } }
    $known = ($null -ne $r -and "" + $r.state -ceq "known")
    $secs = $(if ($known) { [int]$r.seconds } else { $null })
    $why = "unknown"
    if ($night) { $why = "night" }
    elseif ($known -and $secs -ge $Config.idleSeconds) { $why = "idle" }
    elseif ($known) { $why = "busy" }
    return [pscustomobject]@{
        allowed = ($why -ceq "night" -or $why -ceq "idle")
        why = $why
        night = $night
        idleKnown = $known
        idleSeconds = $secs
        needSeconds = [int]$Config.idleSeconds
        time = $at.ToString("HH:mm:ss")
        reason = $(if ($known -or $null -eq $r) { "" } else { "" + $r.reason })
    }
}

function Format-HordeIdleState {
    # The lines `horde idle` prints, from a state of Get-HordeIdleState.
    param([Parameter(Mandatory = $true)]$State)
    $idle = $(if ($State.idleKnown) { "" + $State.idleSeconds } else { "unknown" })
    $lines = @(
        ("idle seconds: " + $idle + " (idle means " + $State.needSeconds + " or more)"),
        ("local time: " + $State.time),
        ("idle-or-night: " + $(if ($State.allowed) { "yes" } else { "no" }) + " (" + $State.why + ")")
    )
    if ($State.why -ceq "unknown" -and "" + $State.reason -ne "") { $lines += ("not known: " + $State.reason + "; treated as not idle") }
    return $lines
}

function Wait-HordeIdleState {
    # Wait until idle-or-night holds, or -WaitSeconds have passed: { allowed; timedOut; state } where state is the
    # last Get-HordeIdleState. Looks at least once. -GetState, -Sleep (milliseconds) and -Elapsed (seconds
    # since the wait began) are injected by tests so no real time passes.
    param(
        [Parameter(Mandatory = $true)][scriptblock]$GetState,
        [int]$WaitSeconds = 0,
        [scriptblock]$Sleep = { param($ms) Start-Sleep -Milliseconds $ms },
        [scriptblock]$Elapsed = $null
    )
    if ($null -eq $Elapsed) { $clock = [System.Diagnostics.Stopwatch]::StartNew(); $Elapsed = { $clock.Elapsed.TotalSeconds }.GetNewClosure() }
    while ($true) {
        $s = & $GetState
        if ($s.allowed) { return [pscustomobject]@{ allowed = $true; timedOut = $false; state = $s } }
        $left = $WaitSeconds - [double](& $Elapsed)
        if ($left -le 0) { return [pscustomobject]@{ allowed = $false; timedOut = $true; state = $s } }
        & $Sleep ([int][math]::Min(5000, [math]::Max(200, $left * 1000)))
    }
}
