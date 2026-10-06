# messengers/wezfleet - hands a message to a session through the fleet's own mail.
#
# WHY THE FLEET'S MAIL (remote plan R21). wezfleet already delivers between sessions on one machine the
# way Horde must: the body is written to the target's inbox and never typed; the receiving session's own
# Stop hook hands it over at a turn boundary and acks it only once its id is in that session's
# transcript (TAKEN); an idle target gets one short wake notice carrying only the id. Its PR #65 added the
# two commands this messenger runs, so that a program that is not a session can use that path:
#   mail post -To <sessionId> -Id <32 hex> -MessageFile <path> [-FromLabel l] [-FromSessionId s] -Json
#   mail status -Id <32 hex> -Json
# each printing ONE line of ASCII JSON: post { id; to; stage; woken; reason }, status { id; to; stage;
# reason }. post exits 0 when the mail is on disk, new or existing (woken false still exits 0), 1 on a
# write failure, 2 when refused; status exits 0 when found, 2 for a malformed id, 3 when absent. A repost
# of one id writes nothing and wakes nothing and reports the existing stage.
#
# THE STAGES, mapped onto the port's (messengers/Port.ps1): queued is accepted, handed-over is
# handed-over, taken is seen, unconfirmed is expired (with a reason), refused is held (with a reason), and
# absent - from status, exit 3 - is absent. Anything else - a stage outside the table, a stage that does
# not go with its exit code, an exit code outside the table, output that is not exactly one line of JSON
# of the expected shape, or an answer about another id - is unknown with the reason, never a stage
# guessed. That is also how a wezfleet too old to have these commands shows: its usage text is not JSON.
#
# THE ONE START SITE (plan R21 slice 3b, merge condition 2). Start-HordeWezfleetMessengerProcess starts the
# fixed PowerShell from the system folder, named once in one expression, on the fixed script wezfleet.ps1
# in the configured folder, with -NoProfile -NonInteractive -ExecutionPolicy Bypass -File. Its arguments
# are built as separate elements and joined by one quoting function; no element is ever a command
# string. messengers/start-sites.txt lists the start and test/test-start-sites.ps1 refuses a second.
# THE BODY NEVER GOES ON A COMMAND LINE: it is written as UTF-8 to a fresh file under the temp folder,
# handed over by -MessageFile, and deleted when the command has answered, whatever it answered.
#
# WHERE THE FLEET IS, is configuration, never a guess: Set-HordeWezfleetMessengerRoot names the folder
# holding wezfleet.ps1 (the node sets it from its own configuration, slice 4). It must be an absolute
# local folder with no .. in it; unset, or the script missing, every call is unknown and nothing starts.
# Every call has a deadline; past it the child is stopped and the answer is unknown.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced, after messengers/Port.ps1.

$script:HordeWezfleetMessengerFolder = $PSScriptRoot
$script:HordeWezfleetMessengerRoot = ""
$script:HordeWezfleetMessengerTimeoutSeconds = 30
$script:HordeWezfleetMessengerScript = "wezfleet.ps1"
# The most a command may print before it is stopped: one line of JSON is far below this.
$script:HordeWezfleetMessengerMaxBytes = 65536
$script:HordeWezfleetMessengerStages = @{ "queued" = "accepted"; "handed-over" = "handed-over"; "taken" = "seen"; "unconfirmed" = "expired"; "refused" = "held" }
# Which stages each exit code may carry, per command. Anything else is unknown.
$script:HordeWezfleetMessengerExits = @{
    post = @{ 0 = @("queued", "handed-over", "taken", "unconfirmed"); 2 = @("refused") }
    status = @{ 0 = @("queued", "handed-over", "taken", "unconfirmed"); 3 = @("absent") }
}

function Set-HordeWezfleetMessengerRoot {
    # Name the folder holding the fleet's wezfleet.ps1, and the deadline of each call. "" unsets it.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path, [int]$TimeoutSeconds = 30)
    if ($TimeoutSeconds -lt 1) { throw ("TimeoutSeconds must be at least 1, not " + $TimeoutSeconds) }
    $script:HordeWezfleetMessengerRoot = $Path
    $script:HordeWezfleetMessengerTimeoutSeconds = $TimeoutSeconds
}

function Get-HordeWezfleetMessengerScriptPath {
    # The fleet's script, as { ok; path; reason }. Only an absolute local folder with no .. is read.
    $dir = $script:HordeWezfleetMessengerRoot
    if ("$dir" -eq "") { return [pscustomobject]@{ ok = $false; path = ""; reason = "the wezfleet folder is not configured, so the fleet's command was not run" } }
    if (-not [System.IO.Path]::IsPathRooted($dir) -or $dir -notmatch '\A[A-Za-z]:\\' -or @($dir -split '[\\/]') -contains "..") {
        return [pscustomobject]@{ ok = $false; path = ""; reason = ("the wezfleet folder '" + $dir + "' is not an absolute local folder without .., so it was not used") }
    }
    $path = Join-Path $dir $script:HordeWezfleetMessengerScript
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [pscustomobject]@{ ok = $false; path = ""; reason = ("wezfleet is not installed there: no " + $script:HordeWezfleetMessengerScript + " in '" + $dir + "'") } }
    return [pscustomobject]@{ ok = $true; path = $path; reason = "" }
}

function ConvertTo-HordeWezfleetMessengerCommandLine {
    # Separate argument elements as one Windows command line, each quoted the way CommandLineToArgvW reads
    # it back: an element with a space, a tab, a quote or nothing in it is quoted, a quote inside is
    # escaped, and backslashes before a quote are doubled. The one place arguments become a string.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Argv)
    $parts = New-Object System.Collections.ArrayList
    foreach ($a in $Argv) {
        if ($a -ne "" -and $a -notmatch '[\s"]') { [void]$parts.Add($a); continue }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        $slashes = 0
        foreach ($ch in $a.ToCharArray()) {
            if ($ch -eq '\') { $slashes++; continue }
            if ($ch -eq '"') { [void]$sb.Append('\' * ($slashes * 2 + 1)); [void]$sb.Append('"'); $slashes = 0; continue }
            if ($slashes -gt 0) { [void]$sb.Append('\' * $slashes); $slashes = 0 }
            [void]$sb.Append($ch)
        }
        if ($slashes -gt 0) { [void]$sb.Append('\' * ($slashes * 2)) }
        [void]$sb.Append('"')
        [void]$parts.Add($sb.ToString())
    }
    return ($parts -join " ")
}

function Stop-HordeWezfleetMessengerProcess {
    # Stop the process this call started, by its handle; say whether it stopped.
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    try { if (-not $Process.HasExited) { $Process.Kill() } } catch { }
    $null = $Process.WaitForExit(5000)
    if ($Process.HasExited) { return "the process it started was stopped" }
    return "the process it started did not stop within 5 s"
}

function Start-HordeWezfleetMessengerProcess {
    # THE ONE START SITE: the fixed PowerShell on the fleet's script, with -Argv after it. Returns
    # { ok; exit; stdout; stderr; reason }. Never throws for the child.
    param([Parameter(Mandatory = $true)][string]$Script, [Parameter(Mandatory = $true)][string[]]$Argv)
    $all = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $Script) + @($Argv)
    $psi = [System.Diagnostics.ProcessStartInfo]::new([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"), (ConvertTo-HordeWezfleetMessengerCommandLine -Argv $all))
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Standard input is held open and never written: a command that waits for input waits until the
    # deadline and is stopped, instead of reading this process's console.
    $psi.RedirectStandardInput = $true
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = ("the fleet's command could not be started: " + $_.Exception.Message) } }
    $timeout = $script:HordeWezfleetMessengerTimeoutSeconds
    $deadline = (Get-Date).AddSeconds($timeout)
    $err = $p.StandardError.ReadToEndAsync()
    $stream = $p.StandardOutput.BaseStream
    $buf = New-Object byte[] 4096
    $got = New-Object System.IO.MemoryStream
    while ($true) {
        $left = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
        $read = $stream.ReadAsync($buf, 0, $buf.Length)
        if (-not $read.Wait($left)) { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = ("the fleet's command did not answer within " + $timeout + " s; " + (Stop-HordeWezfleetMessengerProcess -Process $p)) } }
        $n = $read.Result
        if ($n -eq 0) { break }
        $got.Write($buf, 0, $n)
        if ($got.Length -gt $script:HordeWezfleetMessengerMaxBytes) { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = ("the fleet's command printed more than " + $script:HordeWezfleetMessengerMaxBytes + " bytes; " + (Stop-HordeWezfleetMessengerProcess -Process $p)) } }
    }
    $left = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
    if (-not $p.WaitForExit($left)) { return [pscustomobject]@{ ok = $false; exit = -1; stdout = ""; stderr = ""; reason = ("the fleet's command did not exit within " + $timeout + " s; " + (Stop-HordeWezfleetMessengerProcess -Process $p)) } }
    $errText = ""
    if ($err.Wait(1000)) { $errText = "$($err.Result)" }
    return [pscustomobject]@{ ok = $true; exit = $p.ExitCode; stdout = [System.Text.Encoding]::UTF8.GetString($got.ToArray()); stderr = $errText; reason = "" }
}

function ConvertTo-HordeWezfleetMessengerLine {
    # One line of another program's text, fit for a reason: printable ASCII, at most 200 characters.
    param([string]$Text)
    $first = @("$Text" -split "`r?`n" | Where-Object { $_.Trim() -ne "" }) | Select-Object -First 1
    $clean = ("$first" -replace '[^\x20-\x7E]', '?').Trim()
    if ($clean.Length -gt 200) { $clean = $clean.Substring(0, 200) }
    return $clean
}

function Read-HordeWezfleetMessengerAnswer {
    # The child's answer to one command, read against the table: a core/tristate answer whose known value
    # is the port's { messageId; stage; at; reason }. -Command is post or status.
    param([Parameter(Mandatory = $true)]$Run, [Parameter(Mandatory = $true)][string]$Command, [Parameter(Mandatory = $true)][string]$MessageId)
    if (-not $Run.ok) { return (New-HordeUnknown -Reason $Run.reason) }
    $what = "wezfleet mail " + $Command + " exit " + $Run.exit
    $lines = @("$($Run.stdout)" -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
    if ($lines.Count -ne 1) {
        $detail = ConvertTo-HordeWezfleetMessengerLine ("$($Run.stdout)" + "`n" + "$($Run.stderr)")
        return (New-HordeUnknown -Reason ($what + " printed " + $lines.Count + " lines, not one line of JSON" + $(if ($detail) { ": " + $detail } else { "" })))
    }
    $j = $null
    try { $j = $lines[0] | ConvertFrom-Json } catch { $j = $null }
    if ($null -eq $j -or $j -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ($what + " printed something that is not JSON: " + (ConvertTo-HordeWezfleetMessengerLine $lines[0]))) }
    $need = @("id", "to", "stage", "reason")
    if ($Command -ceq "post") { $need += "woken" }
    $names = @($j.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($k in $need) { if ($names -cnotcontains $k) { return (New-HordeUnknown -Reason ($what + " answered without '" + $k + "': not the shape this messenger reads (wezfleet #65)")) } }
    foreach ($k in $names) { if ($need -cnotcontains $k) { return (New-HordeUnknown -Reason ($what + " answered with '" + $k + "': not the shape this messenger reads (wezfleet #65)")) } }
    if ($Command -ceq "post" -and $j.woken -isnot [bool]) { return (New-HordeUnknown -Reason ($what + " answered woken that is not true or false")) }
    foreach ($k in @("id", "to", "stage", "reason")) { if ($j.$k -isnot [string]) { return (New-HordeUnknown -Reason ($what + " answered " + $k + " that is not text")) } }
    # BOUND TO ITS MESSAGE (review of #102, finding 3): an answer about another id is never this one's.
    $asked = $MessageId.Replace("-", "")
    if ($j.id -cne $asked) { return (New-HordeUnknown -Reason ($what + " answered about " + (ConvertTo-HordeWezfleetMessengerLine $j.id) + ", not " + $asked)) }
    $byExit = $script:HordeWezfleetMessengerExits[$Command]
    if (-not $byExit.ContainsKey([int]$Run.exit)) { return (New-HordeUnknown -Reason ($what + ", which is not an exit code of the fleet's " + $Command + ": " + (ConvertTo-HordeWezfleetMessengerLine $j.reason))) }
    if (@($byExit[[int]$Run.exit]) -cnotcontains $j.stage) { return (New-HordeUnknown -Reason ($what + " with the stage '" + (ConvertTo-HordeWezfleetMessengerLine $j.stage) + "', which does not go with that exit code")) }
    $now = [datetime]::UtcNow
    if ($j.stage -ceq "absent") { return (New-HordeAbsent -Note ("wezfleet has no record of " + $asked) -ObservedAt $now) }
    $reason = ConvertTo-HordeWezfleetMessengerLine $j.reason
    $stage = $script:HordeWezfleetMessengerStages[$j.stage]
    # expired and held say why: wezfleet's reason, or what its stage means when it gave none.
    if ($reason -eq "" -and $j.stage -ceq "unconfirmed") { $reason = "wezfleet: no receiving hook confirmed it in time (unconfirmed)" }
    if ($reason -eq "" -and $j.stage -ceq "refused") { $reason = "wezfleet refused the post" }
    return (New-HordeKnown -Value ([pscustomobject]@{ messageId = $MessageId; stage = $stage; at = $now; reason = $reason }) -ObservedAt $now)
}

function Send-HordeWezfleetMessengerPost {
    # Post one message: the body into a fresh temp file, the fleet's mail post on it, the file deleted.
    param([Parameter(Mandatory = $true)]$Message)
    $where = Get-HordeWezfleetMessengerScriptPath
    if (-not $where.ok) { return (New-HordeUnknown -Reason $where.reason) }
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "horde-wezfleet-mail"
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
    $file = Join-Path $dir ([guid]::NewGuid().ToString("N") + ".txt")
    try {
        [System.IO.File]::WriteAllText($file, [string]$Message.body, (New-Object System.Text.UTF8Encoding($false)))
        $argv = @("mail", "post", "-To", [string]$Message.sessionId, "-Id", ([string]$Message.messageId).Replace("-", ""), "-MessageFile", $file)
        $fl = $Message.from.PSObject.Properties["label"]
        if ($null -ne $fl -and "$($fl.Value)" -ne "") { $argv += @("-FromLabel", [string]$fl.Value) }
        $argv += @("-FromSessionId", [string]$Message.from.sessionId, "-Json")
        $run = Start-HordeWezfleetMessengerProcess -Script $where.path -Argv $argv
        return (Read-HordeWezfleetMessengerAnswer -Run $run -Command "post" -MessageId ([string]$Message.messageId))
    } finally {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    }
}

function Get-HordeWezfleetMessengerStatus {
    # Where one message is, by the fleet's mail status.
    param([Parameter(Mandatory = $true)][string]$MessageId)
    $where = Get-HordeWezfleetMessengerScriptPath
    if (-not $where.ok) { return (New-HordeUnknown -Reason $where.reason) }
    $run = Start-HordeWezfleetMessengerProcess -Script $where.path -Argv @("mail", "status", "-Id", $MessageId.Replace("-", ""), "-Json")
    return (Read-HordeWezfleetMessengerAnswer -Run $run -Command "status" -MessageId $MessageId)
}

$null = Register-HordeMessenger -Folder $script:HordeWezfleetMessengerFolder `
    -Post { param($Message) Send-HordeWezfleetMessengerPost -Message $Message } `
    -Status { param([string]$MessageId) Get-HordeWezfleetMessengerStatus -MessageId $MessageId }
