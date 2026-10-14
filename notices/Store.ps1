# notices/Store.ps1 - where the founder's notices are kept on this machine, and the one lock they are
# written under. WHAT becomes a notice is notices/Decide.ps1's, and nothing else's; this file only keeps.
#
# THE FILES, all under the setting storeFolder (empty: <HORDE_HOME>\notices - CONTRIBUTING 11, every
# path is a setting and shipped code names no folder of anyone's machine):
#   notices.jsonl   THE NOTICES, one JSON object a line, ASCII (everything past printable ASCII as a
#                   \u escape), oldest first:
#                     {"v":1,"n":<1, 2, ...>,"id":"<32 hex>","ts":"<UTC ISO>","kind":"notify|progress|cutoff",
#                      "from":"<who, in words>","text":"<one line>","lane":"<lane or empty>","entry":"<progress entry id or empty>"}
#                   n is the notice's number on this machine, one more than the last line's: what the
#                   channel sends by (channels/notices/Channel.ps1) and what the phone orders by. No
#                   session id is in it: the line goes to the phone, and the phone needs the sender's
#                   name, not his machine's bookkeeping.
#                   KEPT SHORT: past twice keepNotices lines the file is written again with its newest
#                   keepNotices, in one rename. The channel sends by n, never by a byte offset, so the
#                   rewrite moves nothing it relies on.
#   follows.json    THE FOLLOW SWITCHES the founder set on his phone, as the machine holds them:
#                     {"v":1,"lanes":{"<lane>":{"on":true|false,"at":<ms>,"key":"<replay key>"}}}
#                   at is the time the PHONE signed the switch (the envelope's own ts), key the
#                   envelope that set it. A lane not in it is not followed: OFF BY DEFAULT.
#   state.json      what the decisions keep between calls: {"v":1,"sessions":{"<session id>":{"hour":
#                   "<yyyy-MM-ddTHH>","count":n,"told":true|false}},"entries":["<entry id>", ...]} - the
#                   hourly count per session (told: the founder was told it was cut off this hour) and
#                   the progress entries already made notices (the newest 2,000), so one entry is one
#                   notice however often it is offered.
#
# ONE LOCK PER HOME. `horde notify` runs in any session's process and the relay runner's channel
# decides about progress entries in another, so every read-decide-write of these files is done holding
# a named mutex whose name is derived from the store folder (Use-HordeNoticeLock). Without it two
# sessions' notices could take one n, and two counts could each read 5 and write 6.
#
# A FILE THAT DOES NOT HOLD TOGETHER IS NEVER STARTED OVER: the caller is told, in words, and nothing is
# written. A count started over would hand a noisy session a fresh hour.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ModuleSettings.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\FileAtomic.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ReadShared.ps1")

function Get-HordeNoticeSettingsDeclaration {
    # A FUNCTION, NOT A $script: VARIABLE: `horde notify` loads this file inside a command's run block,
    # where $script: is the runner's scope (cli/Commands.ps1 has the measurement).
    return (New-HordeModuleSettings -Module "notices" -Settings @(
        @{ name = "storeFolder"; kind = "folder"; default = ""; what = "Where the notices, the follow switches and the hourly counts are kept, as an absolute path; empty means notices under Horde's home." },
        # 10 an hour: "notify me when X is done" is one line per X; a session that says more than ten
        # things an hour is not doing what he asked for, and is cut off for the rest of that hour.
        @{ name = "perHour"; kind = "whole"; default = 10; min = 1; max = 120; what = "How many notices one session may send in one clock hour (UTC); one more cuts it off until the hour ends." },
        @{ name = "keepNotices"; kind = "whole"; default = 500; min = 50; max = 10000; what = "How many of the newest notices the machine keeps." },
        @{ name = "textChars"; kind = "whole"; default = 300; min = 40; max = 2000; what = "The longest notice text, in characters; a longer one is cut, after it is checked for secrets whole." }
    ))
}

function Get-HordeNoticeSettings {
    # The settings of -HordeHome (empty: Horde's home): known values, or unknown with every finding.
    param([string]$HordeHome = "")
    if ($HordeHome -ceq "") { $HordeHome = Get-HordeHome }
    $s = Get-HordeModuleSettings -Declaration (Get-HordeNoticeSettingsDeclaration) -HordeHome $HordeHome
    if ($s.state -ceq "refused") { return (New-HordeUnknown -Reason (@($s.findings) -join " ")) }
    return (New-HordeKnown -Value $s.values)
}

function Get-HordeNoticeStoreFolder {
    # The store folder of -HordeHome by its setting -Folder (the header).
    param([Parameter(Mandatory = $true)][string]$HordeHome, [AllowEmptyString()][string]$Folder = "")
    if ($Folder -cne "") { return $Folder }
    return [System.IO.Path]::Combine($HordeHome, "notices")
}

function ConvertTo-HordeNoticeJsonString {
    # A JSON string of -Text in printable ASCII: quote, backslash, every control character and everything
    # past 0x7E as a \u escape (as channels/progress writes its entries), so every file here is ASCII.
    param([AllowEmptyString()][string]$Text)
    return ('"' + [regex]::Replace($Text, '[^\x20\x21\x23-\x5B\x5D-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") }) + '"')
}

function Use-HordeNoticeLock {
    # Run -Body holding the store's lock (ONE LOCK PER HOME, in the header) and answer what it answers.
    # Waits up to -WaitMs; THROWS when the lock is not had by then, so nothing is written unlocked. An
    # abandoned lock (its holder killed) is had: what it was writing was replaced in one rename or not
    # at all, so there is nothing half written to fear.
    param([Parameter(Mandatory = $true)][string]$Store, [Parameter(Mandatory = $true)][scriptblock]$Body, [int]$WaitMs = 10000)
    $full = [System.IO.Path]::GetFullPath($Store).TrimEnd([char]'\').ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($full))).Replace("-", "").Substring(0, 32) } finally { $sha.Dispose() }
    $mutex = New-Object System.Threading.Mutex($false, ("Local\horde-notices-" + $digest))
    $mine = $false
    try { $mine = $mutex.WaitOne($WaitMs) } catch [System.Threading.AbandonedMutexException] { $mine = $true }
    if (-not $mine) { $mutex.Dispose(); throw ("the notices store " + $Store + " is held by another writer for more than " + $WaitMs + " ms; nothing was written") }
    try { return (& $Body) }
    finally { try { $mutex.ReleaseMutex() } catch { }; $mutex.Dispose() }
}

function Write-HordeNoticeFile {
    # -Text as the whole of -Path, ASCII, replaced in one rename (core/FileAtomic.ps1). Throws.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    [void][System.IO.Directory]::CreateDirectory($dir)
    $tmp = [System.IO.Path]::Combine($dir, ([System.IO.Path]::GetFileName($Path) + "." + [guid]::NewGuid().ToString("N") + ".tmp"))
    try { [System.IO.File]::WriteAllText($tmp, $Text, [System.Text.Encoding]::ASCII); Move-HordeFileAtomic -From $tmp -To $Path }
    catch { try { [System.IO.File]::Delete($tmp) } catch { }; throw }
}

function Read-HordeNoticeJson {
    # A JSON document of -Path, read strictly: known (the object), absent (no file), unknown (it does not
    # hold together: not ASCII, a member twice, not JSON, not an object), with -What in the reason.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$What)
    if (-not [System.IO.File]::Exists($Path)) { return (New-HordeAbsent -Note ("there is no " + $What + " yet")) }
    try { $bytes = [System.IO.File]::ReadAllBytes($Path); Assert-HordeAsciiBytes -Bytes $bytes -What ("the " + $What + " " + $Path); $text = [System.Text.Encoding]::ASCII.GetString($bytes) }
    catch { return (New-HordeUnknown -Reason ("the " + $What + " " + $Path + " cannot be read: " + $_.Exception.Message)) }
    if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { return (New-HordeUnknown -Reason ("the " + $What + " " + $Path + " has a member twice")) }
    try { $o = ConvertFrom-Json -InputObject $text } catch { return (New-HordeUnknown -Reason ("the " + $What + " " + $Path + " is not JSON")) }
    if ($o -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ("the " + $What + " " + $Path + " is not an object")) }
    return (New-HordeKnown -Value $o)
}

# --- the follow switches ---

$script:HordeNoticeLanePattern = '\A[A-Za-z0-9][A-Za-z0-9 ._-]{0,31}\z'

function Test-HordeNoticeLane {
    # Is -Lane a lane id a switch may name: a card's lane id (channels/cards: the Orc's letter, else the
    # folder's name), or "thrall" - the Thrall's card on every page of the phone.
    param([AllowEmptyString()][string]$Lane)
    return ($Lane -cmatch $script:HordeNoticeLanePattern)
}

function Read-HordeNoticeFollows {
    # The switches the machine holds: known hashtable lane -> { on; at; key } (empty when none was ever
    # set), or unknown when follows.json does not hold together.
    param([Parameter(Mandatory = $true)][string]$Store)
    $path = [System.IO.Path]::Combine($Store, "follows.json")
    $r = Read-HordeNoticeJson -Path $path -What "follow switches"
    if ($r.state -ceq "absent") { return (New-HordeKnown -Value @{}) }
    if ($r.state -cne "known") { return $r }
    $why = "the follow switches " + $path + " do not hold together"
    $o = $r.value
    if ((@($o.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -cne "lanes,v" -or $o.v -ne 1 -or $o.lanes -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ($why + ": it is not {""v"":1,""lanes"":{...}}")) }
    $out = New-Object System.Collections.Hashtable -ArgumentList ([System.StringComparer]::Ordinal)
    foreach ($p in @($o.lanes.PSObject.Properties)) {
        $s = $p.Value
        if (-not (Test-HordeNoticeLane $p.Name) -or $s -isnot [System.Management.Automation.PSCustomObject] -or (@($s.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -cne "at,key,on" -or
            $s.on -isnot [bool] -or -not ($s.at -is [int] -or $s.at -is [long]) -or $s.key -isnot [string] -or $s.key.Length -gt 160) { return (New-HordeUnknown -Reason ($why + ": the switch of '" + $p.Name + "' is not {on, at, key}")) }
        $out[$p.Name] = [pscustomobject]@{ on = [bool]$s.on; at = [long]$s.at; key = [string]$s.key }
    }
    return (New-HordeKnown -Value $out)
}

function ConvertTo-HordeNoticeFollowsText {
    # The switches as follows.json's text, lanes in name order, so the same switches are the same bytes.
    param([Parameter(Mandatory = $true)][hashtable]$Follows)
    $parts = @(@($Follows.Keys | Sort-Object { $_ } -CaseSensitive) | ForEach-Object {
        $s = $Follows[$_]
        (ConvertTo-HordeNoticeJsonString $_) + ':{"on":' + $(if ($s.on) { "true" } else { "false" }) + ',"at":' + [long]$s.at + ',"key":' + (ConvertTo-HordeNoticeJsonString $s.key) + '}'
    })
    return ('{"v":1,"lanes":{' + ($parts -join ",") + '}}')
}

function Write-HordeNoticeFollows {
    # follows.json replaced whole. Throws. The caller holds the lock.
    param([Parameter(Mandatory = $true)][string]$Store, [Parameter(Mandatory = $true)][hashtable]$Follows)
    Write-HordeNoticeFile -Path ([System.IO.Path]::Combine($Store, "follows.json")) -Text (ConvertTo-HordeNoticeFollowsText -Follows $Follows)
}

# --- the hourly counts and the entries already made notices ---

function Read-HordeNoticeState {
    # state.json: known { sessions (hashtable session -> { hour; count; told }); entries (string[]) },
    # empty when there is none, unknown when it does not hold together.
    param([Parameter(Mandatory = $true)][string]$Store)
    $path = [System.IO.Path]::Combine($Store, "state.json")
    $empty = [pscustomobject]@{ sessions = @{}; entries = @() }
    $r = Read-HordeNoticeJson -Path $path -What "notices state"
    if ($r.state -ceq "absent") { return (New-HordeKnown -Value $empty) }
    if ($r.state -cne "known") { return $r }
    $why = "the notices state " + $path + " does not hold together"
    $o = $r.value
    if ((@($o.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -cne "entries,sessions,v" -or $o.v -ne 1 -or $o.sessions -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ($why + ": it is not {v, sessions, entries}")) }
    $sessions = @{}
    foreach ($p in @($o.sessions.PSObject.Properties)) {
        $s = $p.Value
        if ($s -isnot [System.Management.Automation.PSCustomObject] -or (@($s.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -cne "count,hour,told" -or
            $s.hour -isnot [string] -or $s.hour -cnotmatch '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}\z' -or -not ($s.count -is [int] -or $s.count -is [long]) -or $s.count -lt 0 -or $s.told -isnot [bool]) { return (New-HordeUnknown -Reason ($why + ": a session's count is not {hour, count, told}")) }
        $sessions[$p.Name] = [pscustomobject]@{ hour = $s.hour; count = [int]$s.count; told = [bool]$s.told }
    }
    $entries = @(@($o.entries) | Where-Object { $null -ne $_ })
    foreach ($e in $entries) { if ($e -isnot [string] -or $e.Length -gt 128) { return (New-HordeUnknown -Reason ($why + ": an entry is not an entry's id")) } }
    return (New-HordeKnown -Value ([pscustomobject]@{ sessions = $sessions; entries = $entries }))
}

function Write-HordeNoticeState {
    # state.json replaced whole; only this hour's counts and the newest 2,000 entries are kept. Throws.
    param([Parameter(Mandatory = $true)][string]$Store, [Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$Hour)
    $parts = @(@($State.sessions.Keys | Sort-Object) | Where-Object { $State.sessions[$_].hour -ceq $Hour } | ForEach-Object {
        $s = $State.sessions[$_]
        (ConvertTo-HordeNoticeJsonString $_) + ':{"hour":"' + $s.hour + '","count":' + [int]$s.count + ',"told":' + $(if ($s.told) { "true" } else { "false" }) + '}'
    })
    $entries = @(@($State.entries) | Select-Object -Last 2000 | ForEach-Object { ConvertTo-HordeNoticeJsonString $_ })
    Write-HordeNoticeFile -Path ([System.IO.Path]::Combine($Store, "state.json")) -Text ('{"v":1,"sessions":{' + ($parts -join ",") + '},"entries":[' + ($entries -join ",") + ']}')
}

# --- the notices ---

function Get-HordeNoticeLogPath { param([Parameter(Mandatory = $true)][string]$Store) return [System.IO.Path]::Combine($Store, "notices.jsonl") }

function Read-HordeNoticeLog {
    # Every notice kept, oldest first: known @({ n; id; ts; kind; from; text; lane; entry; line }) - line
    # its text as stored - or unknown when the file cannot be read or a line does not hold together.
    param([Parameter(Mandatory = $true)][string]$Store)
    $path = Get-HordeNoticeLogPath -Store $Store
    if (-not [System.IO.File]::Exists($path)) { return (New-HordeKnown -Value @()) }
    try { $text = Read-HordeSharedText -Path $path } catch { return (New-HordeUnknown -Reason ("the notices " + $path + " cannot be read: " + $_.Exception.Message)) }
    $out = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($line in ($text -split "\n")) {
        $i++
        if ($line.Trim() -eq "") { continue }
        $why = "line " + $i + " of the notices " + $path + " does not hold together"
        if ($line -cmatch '[^\x20-\x7E]') { return (New-HordeUnknown -Reason ($why + ": it is not printable ASCII")) }
        try { $o = ConvertFrom-Json -InputObject $line } catch { return (New-HordeUnknown -Reason ($why + ": it is not JSON")) }
        $names = (@($o.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",")
        if ($names -cne "entry,from,id,kind,lane,n,text,ts,v" -or $o.v -ne 1 -or -not ($o.n -is [int] -or $o.n -is [long]) -or $o.n -lt 1 -or $o.id -isnot [string] -or $o.id -cnotmatch '\A[0-9a-f]{32}\z' -or
            @("notify", "progress", "cutoff") -cnotcontains "$($o.kind)") { return (New-HordeUnknown -Reason ($why + ": it is not a notice")) }
        $ts = $o.ts
        if ($ts -is [datetime]) { $ts = $ts.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture) }
        [void]$out.Add([pscustomobject]@{ n = [long]$o.n; id = $o.id; ts = "$ts"; kind = $o.kind; from = "$($o.from)"; text = "$($o.text)"; lane = "$($o.lane)"; entry = "$($o.entry)"; line = $line })
    }
    return (New-HordeKnown -Value @($out.ToArray()))
}

function ConvertTo-HordeNoticeLine {
    # One notice as its line in notices.jsonl (the header).
    param([Parameter(Mandatory = $true)]$Notice)
    return ('{"v":1,"n":' + [long]$Notice.n + ',"id":"' + $Notice.id + '","ts":"' + $Notice.ts + '","kind":"' + $Notice.kind + '","from":' + (ConvertTo-HordeNoticeJsonString $Notice.from) +
        ',"text":' + (ConvertTo-HordeNoticeJsonString $Notice.text) + ',"lane":' + (ConvertTo-HordeNoticeJsonString $Notice.lane) + ',"entry":' + (ConvertTo-HordeNoticeJsonString $Notice.entry) + '}')
}

function Add-HordeNoticeLines {
    # Append -Notices (each { id; ts; kind; from; text; lane; entry }) to the log, numbering them on from
    # the last one kept, and keep it short (KEPT SHORT, in the header). The caller holds the lock.
    # Answers the notices as written, each with its n. Throws when the log cannot be read or written:
    # numbering on from a log that cannot be read would give one n twice.
    param([Parameter(Mandatory = $true)][string]$Store, [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Notices, [Parameter(Mandatory = $true)][int]$Keep)
    if (@($Notices).Count -eq 0) { return @() }
    $log = Read-HordeNoticeLog -Store $Store
    if ($log.state -cne "known") { throw $log.reason }
    $last = [long]0
    if (@($log.value).Count -gt 0) { $last = [long](@($log.value)[-1].n) }
    $written = New-Object System.Collections.ArrayList
    $lines = New-Object System.Collections.ArrayList
    foreach ($x in @($Notices)) {
        $last++
        $one = [pscustomobject]@{ n = $last; id = $x.id; ts = $x.ts; kind = $x.kind; from = $x.from; text = $x.text; lane = $x.lane; entry = $x.entry }
        [void]$written.Add($one)
        [void]$lines.Add((ConvertTo-HordeNoticeLine -Notice $one))
    }
    $path = Get-HordeNoticeLogPath -Store $Store
    [void][System.IO.Directory]::CreateDirectory($Store)
    $all = @(@($log.value) | ForEach-Object { $_.line }) + @($lines.ToArray())
    if ($all.Count -gt 2 * $Keep) { Write-HordeNoticeFile -Path $path -Text ((@($all | Select-Object -Last $Keep) -join "`n") + "`n") }
    else {
        $fs = New-Object System.IO.FileStream -ArgumentList $path, ([System.IO.FileMode]::Append), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::Read)
        try { $b = [System.Text.Encoding]::ASCII.GetBytes((@($lines.ToArray()) -join "`n") + "`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) } finally { $fs.Dispose() }
    }
    return @($written.ToArray())
}
