# hosts/wezterm/Act.ps1 - the acting half of the WezTerm host: start a program in a pane of the node's
# own terminal, type into one of its panes, end one, and say whether one is still there.
#
# THE ACT PATH'S A2 (planning/execution-plan-remote.md, R19's first version, 2026-10-05). A node starts
# a harness in its OWN terminal, the one its user is logged in to, so the session is a child of that
# terminal's mux and never of the node daemon or of an ssh session (remote design, section 0).
# Process launching lives here and in agents/<name>/, never in remote/ (tools/ExecScan.ps1).
#
# EVERY CALL IS `wezterm cli --no-auto-start ...`. Without that flag a call aimed at a terminal that is
# not answering may START a mux server that loads the user's config and its session-restore plugin
# (wezfleet CONTRIBUTING 1; Invoke-WfWezterm there, Invoke-HordeWeztermCli in the test harness). Which
# terminal is meant is the environment's to say: WEZTERM_UNIX_SOCKET, when set, pins it.
#
# ARGUMENTS ARE QUOTED FOR WINDOWS HERE, NOT BY POWERSHELL. PowerShell 5.1 passes a native argument
# with an embedded quote broken, and a first prompt may hold quotes, line breaks and & | ^ %. The
# command line is built by ConvertTo-HordeWindowsCommandLine with the rules CommandLineToArgvW and the
# C runtime read back (test-act.ps1 round-trips every case through CommandLineToArgvW), and the
# program is started through ProcessStartInfo. No cmd.exe is ever between Horde and the harness: a
# program installed only as a .cmd or .bat shim is refused, because cmd.exe would read & | ^ % in a
# prompt as its own syntax.
#
# WHAT A PANE DOES NOT GET: THE CALLER'S ENVIRONMENT. Measured 2026-10-05 (issue #95): a variable set
# in the process that started the terminal, or that ran `cli spawn`, is absent inside the new pane,
# and `cli spawn` (20240203) has no option to pass one. A pane gets the user's own environment. So this
# file passes none, and says so; an engine's variables wait for engines E10's launch stub.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeWeztermActExe = "wezterm"
# How long one cli call may take. A spawn answered in under a second on this machine (2026-10-05,
# isolated instance, 12 spawns); 20 s is the bound past which the terminal is called not answering.
$script:HordeWeztermActTimeoutMs = 20000

function ConvertTo-HordeWindowsArgument {
    # One argument quoted so CommandLineToArgvW and the C runtime read it back exactly: quoted when it
    # is empty or holds a space, tab, line break or quote; a quote preceded by its backslashes doubled;
    # backslashes before the closing quote doubled.
    param([AllowEmptyString()][string]$Arg)
    if ($Arg.Length -gt 0 -and $Arg -cnotmatch '[\s"]') { return $Arg }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $slashes = 0
    foreach ($ch in $Arg.ToCharArray()) {
        if ($ch -eq [char]92) { $slashes++; continue }
        if ($ch -eq '"') { [void]$sb.Append(([string][char]92) * ($slashes * 2 + 1)); [void]$sb.Append('"'); $slashes = 0; continue }
        if ($slashes -gt 0) { [void]$sb.Append(([string][char]92) * $slashes); $slashes = 0 }
        [void]$sb.Append($ch)
    }
    if ($slashes -gt 0) { [void]$sb.Append(([string][char]92) * ($slashes * 2)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-HordeWindowsCommandLine {
    # A whole argument list as one command line.
    param([string[]]$Argv)
    return ((@($Argv) | ForEach-Object { ConvertTo-HordeWindowsArgument -Arg ("" + $_) }) -join " ")
}

function Get-HordeWeztermActArgv {
    # The full argv of one cli call: cli --no-auto-start, then the call. The one place it is built.
    param([Parameter(Mandatory = $true)][string[]]$Rest)
    return @("cli", "--no-auto-start") + @($Rest)
}

function Invoke-HordeWeztermAct {
    # Run one cli call. Returns { code; out; err; timedOut }. Streams are read through the process API
    # (no 2>&1, CONTRIBUTING 12); a call past the timeout is killed by the handle this function holds.
    param([Parameter(Mandatory = $true)][string[]]$Rest, [int]$TimeoutMs = $script:HordeWeztermActTimeoutMs)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:HordeWeztermActExe
    $psi.Arguments = ConvertTo-HordeWindowsCommandLine -Argv (Get-HordeWeztermActArgv -Rest $Rest)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return [pscustomobject]@{ code = -1; out = ""; err = ("the terminal's command could not be started: " + $_.Exception.Message); timedOut = $false } }
    try {
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch { }
            return [pscustomobject]@{ code = -1; out = ""; err = ("the terminal did not answer within " + $TimeoutMs + " ms"); timedOut = $true }
        }
        $p.WaitForExit()
        return [pscustomobject]@{ code = $p.ExitCode; out = $outTask.Result; err = $errTask.Result; timedOut = $false }
    } finally { $p.Dispose() }
}

function Resolve-HordeWeztermProgram {
    # A program's full path from its command name, as an answer: the first .exe on PATH with that
    # name. A name found only as a script shim is refused (see the header: no cmd.exe in between).
    param([Parameter(Mandatory = $true)][string]$Name, $Lookup = $null)
    if ($Name -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z') { return (New-HordeUnknown -Reason ("'" + $Name + "' is not a command name")) }
    $found = $null
    if ($null -ne $Lookup) { $found = @(& $Lookup $Name) }
    else { $found = @(Get-Command -Name $Name -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object { "" + $_.Source }) }
    $exe = @($found | Where-Object { [System.IO.Path]::GetExtension("" + $_) -ieq ".exe" })
    if ($exe.Count -ge 1) { return (New-HordeKnown -Value ("" + $exe[0])) }
    if ($found.Count -ge 1) { return (New-HordeUnknown -Reason ("'" + $Name + "' is installed here only as " + (Split-Path -Leaf ("" + $found[0])) + ", a script shim; Horde starts no harness through cmd.exe, which would read a prompt's & | ^ % as its own syntax. Install the harness's native executable")) }
    return (New-HordeUnknown -Reason ("'" + $Name + "' is not on this node's PATH"))
}

function Get-HordeWeztermSpawnArgv {
    # The cli call that starts -Program with -Argv in a new pane: spawn, where, then -- and the program.
    # -WindowId puts it in a tab of that window; without one it gets a window of its own (a node runs
    # outside any pane, so there is no current pane to place it beside).
    param([Parameter(Mandatory = $true)][string]$Program, [string[]]$Argv = @(), [Parameter(Mandatory = $true)][string]$Cwd, [string]$WindowId = "")
    $rest = @("spawn")
    if ($WindowId -ne "") { $rest += @("--window-id", $WindowId) } else { $rest += @("--new-window") }
    $rest += @("--cwd", $Cwd, "--", $Program) + @($Argv)
    return $rest
}

function Start-HordeWeztermPane {
    # Start -Program (a full path to an .exe, from Resolve-HordeWeztermProgram) with -Argv in a new pane
    # whose working folder is -Cwd. Returns an answer: known { handle; program; cwd }, the handle the
    # pane id as text; unknown with the terminal's own reason.
    param([Parameter(Mandatory = $true)][string]$Program, [string[]]$Argv = @(), [Parameter(Mandatory = $true)][string]$Cwd,
        [string]$WindowId = "", [scriptblock]$Runner = $null)
    if (-not [System.IO.Path]::IsPathRooted($Program) -or [System.IO.Path]::GetExtension($Program) -ine ".exe") { return (New-HordeUnknown -Reason ("the program must be a full path to an .exe, not '" + $Program + "'")) }
    if (-not [System.IO.Path]::IsPathRooted($Cwd)) { return (New-HordeUnknown -Reason ("the working folder must be absolute, not '" + $Cwd + "'")) }
    if ($WindowId -ne "" -and $WindowId -cnotmatch '\A[0-9]{1,9}\z') { return (New-HordeUnknown -Reason ("'" + $WindowId + "' is not a window id")) }
    $rest = Get-HordeWeztermSpawnArgv -Program $Program -Argv $Argv -Cwd $Cwd -WindowId $WindowId
    $r = $null
    if ($null -ne $Runner) { $r = & $Runner $rest } else { $r = Invoke-HordeWeztermAct -Rest $rest }
    if ($r.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not start the pane (exit " + $r.code + "): " + ("" + $r.err).Trim())) }
    $id = ("" + $r.out).Trim()
    if ($id -cnotmatch '\A[0-9]{1,9}\z') { return (New-HordeUnknown -Reason ("the terminal answered the spawn with '" + $id + "', not a pane id; whether a pane started is unknown")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ handle = $id; program = $Program; cwd = $Cwd }))
}

function Send-HordeWeztermText {
    # Type -Text into the pane -Handle, as keystrokes (--no-paste), so a harness reads it as typed and
    # a carriage return submits. Returns known $true when the terminal took it, unknown otherwise.
    param([Parameter(Mandatory = $true)][string]$Handle, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [scriptblock]$Runner = $null)
    if ($Handle -cnotmatch '\A[0-9]{1,9}\z') { return (New-HordeUnknown -Reason ("'" + $Handle + "' is not a pane handle")) }
    $rest = @("send-text", "--pane-id", $Handle, "--no-paste", $Text)
    $r = $null
    if ($null -ne $Runner) { $r = & $Runner $rest } else { $r = Invoke-HordeWeztermAct -Rest $rest }
    if ($r.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not take the text (exit " + $r.code + "): " + ("" + $r.err).Trim())) }
    return (New-HordeKnown -Value $true)
}

function Read-HordeWeztermPaneList {
    # The live panes from `cli list --format json` output, as an answer: known list of { handle;
    # window; tab; cwd; title }, or unknown when the output is not a list. Zero panes is a known empty
    # list only when the terminal answered with [] itself.
    param($Raw)
    $joined = ((@($Raw) -join "`n").Trim())
    if ($joined -eq "") { return (New-HordeUnknown -Reason "the terminal's pane list was empty output, which is unknown, not none") }
    $parsed = $null
    try { $parsed = $joined | ConvertFrom-Json } catch { return (New-HordeUnknown -Reason "the terminal's pane list is not JSON") }
    if ($joined -ceq "[]") { return (New-HordeKnown -Value @()) }
    $rows = New-Object System.Collections.ArrayList
    foreach ($p in @($parsed)) {
        if ($null -eq $p -or $null -eq $p.PSObject.Properties["pane_id"]) { return (New-HordeUnknown -Reason "a pane in the terminal's list has no pane_id") }
        [void]$rows.Add([pscustomobject]@{ handle = ("" + $p.pane_id); window = ("" + $p.window_id); tab = ("" + $p.tab_id); cwd = ("" + $p.cwd); title = ("" + $p.title) })
    }
    return (New-HordeKnown -Value $rows.ToArray())
}

function Test-HordeWeztermPaneLive {
    # Is the pane -Handle in the terminal's list right now? Known true or false, or unknown when the
    # list cannot be read: a pane the terminal could not list is never called gone.
    param([Parameter(Mandatory = $true)][string]$Handle, [scriptblock]$Runner = $null)
    $rest = @("list", "--format", "json")
    $r = $null
    if ($null -ne $Runner) { $r = & $Runner $rest } else { $r = Invoke-HordeWeztermAct -Rest $rest }
    if ($r.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not list its panes (exit " + $r.code + ")")) }
    $l = Read-HordeWeztermPaneList -Raw $r.out
    if ($l.state -ne "known") { return $l }
    return (New-HordeKnown -Value ([bool](@($l.value | Where-Object { $_.handle -ceq $Handle }).Count -gt 0)))
}

function Stop-HordeWeztermPane {
    # End the pane -Handle and whatever runs in it: the forced end, for a session that must not run
    # (a mode read back above what was allowed) or that ignored a graceful close. The caller has
    # proved the pane is one it started; this says only whether the terminal took the order.
    param([Parameter(Mandatory = $true)][string]$Handle, [scriptblock]$Runner = $null)
    if ($Handle -cnotmatch '\A[0-9]{1,9}\z') { return (New-HordeUnknown -Reason ("'" + $Handle + "' is not a pane handle")) }
    $rest = @("kill-pane", "--pane-id", $Handle)
    $r = $null
    if ($null -ne $Runner) { $r = & $Runner $rest } else { $r = Invoke-HordeWeztermAct -Rest $rest }
    if ($r.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not end the pane (exit " + $r.code + "): " + ("" + $r.err).Trim())) }
    return (New-HordeKnown -Value $true)
}

# THE PORT (core/HostAct.ps1). A node reaches these functions only through it, so nothing outside
# hosts/wezterm/ names the terminal (CONTRIBUTING 14).
Register-HordeHostActor -Name "wezterm" `
    -Resolve { param($n) Resolve-HordeWeztermProgram -Name $n } `
    -Start { param($prog, $argv, $cwd) Start-HordeWeztermPane -Program $prog -Argv $argv -Cwd $cwd } `
    -Send { param($h, $t) Send-HordeWeztermText -Handle $h -Text $t } `
    -Live { param($h) Test-HordeWeztermPaneLive -Handle $h } `
    -Stop { param($h) Stop-HordeWeztermPane -Handle $h }
