# test/lib/WindowProbe.ps1 - for end-to-end scenarios of a command that shows a window and stays until
# it is closed: start the real horde command and keep hold of it, read the report file it keeps, look
# at a window from outside, and close a window of a process the scenario itself started.
#
# A SCENARIO ACTS ONLY ON WHAT IT STARTED (CONTRIBUTING 9). Close-HordeProbeWindow closes a window
# only when the process that reported it is the one the scenario holds the handle of, and ends that
# process by that handle if it does not go. Nothing here looks for a window by its title.
#
# Test-only. Nothing that ships uses it.

Add-Type -Namespace HordeProbe -Name Native -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int index);
[DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
'@
# Real pixels, as the window's own process sees them: a rectangle read through the system's scaling
# for this process would not be the one the window was placed at. Asked of the follow port, as the
# command under test asks it, so this helper has no call of its own for it (it had one, the third
# copy in the repository; the review of 2026-10-06 counted them).
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\WindowFollowPort.ps1")
foreach ($probeFollowerFile in @(Get-HordeWindowFollowerFiles)) { . $probeFollowerFile }
$script:HordeProbeRealScale = Enable-HordeWindowFollowRealScale

function New-HordeProbeRegistry {
    # A fleet registry of session records under -Root, as the fleet being replaced writes them, for a
    # scenario that needs the session holding a role to be found. Each record is { id; role; pane;
    # instance; lastSeen }, with retired when it is. With New-HordeProbeRunningSession below, the one
    # place these scenarios spell what carries an agent harness's name - the records' key field, and
    # the folder that harness keeps its control files in: the harness's allowlist lists this file.
    param([Parameter(Mandatory = $true)][string]$Root, [hashtable[]]$Records = @())
    $sessions = Join-Path $Root "registry\sessions"
    New-Item -ItemType Directory -Path $sessions -Force | Out-Null
    foreach ($r in $Records) {
        $record = @{}
        foreach ($k in @($r.Keys)) { if ($k -cne "id") { $record[$k] = $r[$k] } }
        $record["claudeSessionId"] = $r["id"]
        [System.IO.File]::WriteAllText((Join-Path $sessions ($r["id"] + ".json")), (ConvertTo-Json -InputObject $record -Compress))
    }
    return $Root
}

function New-HordeProbeRunningSession {
    # A control file saying session -SessionId is running as process -ProcessId, as the agent harness
    # writes one for a running session, under -Profile: a folder standing in for the user's profile
    # in the environment of a command this scenario starts (USERPROFILE). core/SessionSeat.ps1
    # believes a session's seat only when such a file names a process that is running and started
    # when the file says, so -ProcessId is a real process: one this scenario started, or itself.
    # Returns the time that process started, in UTC: a record written after it is this run's.
    param([Parameter(Mandatory = $true)][string]$Profile, [Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)][int]$ProcessId)
    $dir = Join-Path (Join-Path $Profile ".claude") "sessions"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $started = (Get-Process -Id $ProcessId).StartTime.ToUniversalTime()
    $file = [ordered]@{ pid = $ProcessId; sessionId = $SessionId; cwd = $Profile; procStart = ("" + $started.ToFileTimeUtc()); status = "idle" }
    [System.IO.File]::WriteAllText((Join-Path $dir ("" + $ProcessId + ".json")), (ConvertTo-Json -InputObject $file -Compress))
    return $started
}

function Start-HordeProbeCommand {
    # Start the shipped horde.ps1 as its own process and return the process, still running, with its
    # output being gathered: { process; out; err }. -Env reaches only the child; a name mapped to $null
    # is removed from it.
    param([Parameter(Mandatory = $true)][string]$Root, [string[]]$HordeArgs = @(), [hashtable]$Env = @{})
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")
    $quoted = @($HordeArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $Root "horde.ps1") + "`" " + ($quoted -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($k in @($Env.Keys)) { if ($null -eq $Env[$k]) { if ($psi.EnvironmentVariables.ContainsKey($k)) { $psi.EnvironmentVariables.Remove($k) } } else { $psi.EnvironmentVariables[$k] = "" + $Env[$k] } }
    $p = [System.Diagnostics.Process]::Start($psi)
    return [pscustomobject]@{ process = $p; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync() }
}

function Read-HordeProbeReport {
    # The report file a window keeps, parsed, or $null when it is not there or is being replaced.
    param([Parameter(Mandatory = $true)][string]$Path)
    for ($i = 0; $i -lt 5; $i++) {
        try { if (Test-Path -LiteralPath $Path -PathType Leaf) { return ([System.IO.File]::ReadAllText($Path) | ConvertFrom-Json) } } catch { }
        Start-Sleep -Milliseconds 80
    }
    return $null
}

function Wait-HordeProbeReport {
    # Wait until the report satisfies -Until (a block given the report), or -Seconds pass, or -Process
    # has exited. Returns the last report read; the caller checks it.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][scriptblock]$Until, [int]$Seconds = 90, $Process = $null)
    $deadline = (Get-Date).AddSeconds($Seconds)
    $last = $null
    while ((Get-Date) -lt $deadline) {
        $last = Read-HordeProbeReport -Path $Path
        if ($null -ne $last -and [bool](& $Until $last)) { return $last }
        if ($null -ne $Process -and $Process.HasExited) { break }
        Start-Sleep -Milliseconds 250
    }
    return (Read-HordeProbeReport -Path $Path)
}

function Get-HordeProbeWindow {
    # What can be seen of a window from outside: { exists; visible; left; top; right; bottom; owner;
    # processId; dpi; foreground }.
    param([Parameter(Mandatory = $true)][long]$Handle)
    $h = [IntPtr]$Handle
    $r = New-Object HordeProbe.Native+RECT
    $exists = [HordeProbe.Native]::IsWindow($h)
    if ($exists) { [void][HordeProbe.Native]::GetWindowRect($h, [ref]$r) }
    $owner = [long]0; $processId = [uint32]0; $dpi = 96
    if ($exists) { $owner = [HordeProbe.Native]::GetWindowLongPtr($h, -8).ToInt64(); [void][HordeProbe.Native]::GetWindowThreadProcessId($h, [ref]$processId); $dpi = [int][HordeProbe.Native]::GetDpiForWindow($h) }
    return [pscustomobject]@{ exists = [bool]$exists; visible = [bool]($exists -and [HordeProbe.Native]::IsWindowVisible($h)); left = $r.Left; top = $r.Top; right = $r.Right; bottom = $r.Bottom
        owner = $owner; processId = [long]$processId; dpi = $dpi; foreground = [bool]([HordeProbe.Native]::GetForegroundWindow() -eq $h) }
}

function Add-HordeProbeStoredRecord {
    # Put one record into a decisions store of a scenario's own AS A FILE, the way an earlier version
    # of Horde left it there: for what the operations no longer write and a window must still show (a
    # reply that asks, under a question already answered). The next sequence number, written whole
    # under a temporary name and moved into place, as the store itself does. Returns the number.
    param([Parameter(Mandatory = $true)][string]$Store, [Parameter(Mandatory = $true)][string]$Kind, [Parameter(Mandatory = $true)]$Data, [string]$Actor = "warchief")
    $seq = @(Get-ChildItem -LiteralPath $Store -File -Filter "*.json").Count + 1
    $envelope = [ordered]@{ schemaVersion = 1; sequence = $seq; id = [guid]::NewGuid().ToString("N"); kind = $Kind
        at = [datetime]::UtcNow.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture); actor = $Actor; requestHash = ("0" * 64); data = $Data }
    $temp = Join-Path $Store ("planted-" + [guid]::NewGuid().ToString("N") + ".part")
    [System.IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $envelope -Compress -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::Move($temp, (Join-Path $Store ($seq.ToString("D10") + ".json")))
    return $seq
}

function Close-HordeProbeWindow {
    # Ask the window -Handle to close, as its close button would - only if it belongs to -Process, the
    # process this scenario started - and wait for that process to end. If it does not, end it by its
    # handle. Returns { asked; exited; code; killed }.
    param([Parameter(Mandatory = $true)]$Process, [long]$Handle = 0, [int]$Seconds = 30)
    $asked = $false
    if ($Handle -ne 0 -and -not $Process.HasExited) {
        $seen = Get-HordeProbeWindow -Handle $Handle
        if ($seen.exists -and $seen.processId -eq $Process.Id) { $asked = [HordeProbe.Native]::PostMessageW([IntPtr]$Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }   # WM_CLOSE
    }
    $exited = $Process.WaitForExit($Seconds * 1000)
    $killed = $false
    if (-not $exited) { try { $Process.Kill(); $killed = $true; [void]$Process.WaitForExit(10000) } catch { } }
    $code = -1
    if ($Process.HasExited) { $code = $Process.ExitCode }
    return [pscustomobject]@{ asked = [bool]$asked; exited = [bool]$exited; code = $code; killed = $killed }
}
