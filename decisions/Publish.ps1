# decisions/Publish.ps1 - `horde decisions publish` and `horde decisions published`: each Orc (and the Thrall)
# publishes its live, ordered list of what it waits on the founder for, into fleet.db's decisions lists
# (fleet-db/decisions-cli.mjs, which calls the one write path, fleet-db/write.mjs publishDecisions).
#
# WHO PUBLISHES IS PROVEN, NEVER TYPED (founder, 2026-10-20): the Orc is the session this command runs inside,
# proven by notices/Sender.ps1's three steps and held to the seat of the Orc whose letter it wears, exactly as
# `decisions ack` proves it (Resolve-HordeDecisionOrcCaller); the Thrall's session is proven by its seat
# (Test-HordeDecisionWarchiefCaller). The file names no Orc: one that tries to is refused whole, because a file
# that said "F" while G ran it would publish G's list as F's.
#
# THIS SIDE JUDGES THE WORDS, THE NODE SIDE THE STORE: the shape of the file, the plain ASCII, the limits and the
# secret check are decided here, before anything is written or started; the question number -> id step, the Orc's
# row and the write itself are fleet.db's. A refusal names the exact field and never quotes a value: a text may
# be what must not be printed (the same rule as decisions/Console.ps1's file readers).
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Console.ps1")

$script:HordePublishTopFields = @("items")
# Names a file might use to say who is publishing: said back in the refusal because they are fixed words.
$script:HordePublishWhoNames = '\A(orc|orcid|orc_id|letter|lane|session|sessionid|session_id|by|from|sender|author|thrall|label)\z'
$script:HordePublishItemFields = @("questionNumber", "text", "recommendation", "importance", "blocks")
$script:HordePublishMaxText = 400

function Get-HordePublishFieldShown {
    # A field name as a refusal may repeat it: only a plain short word. Anything else (a name is text somebody
    # typed, and a token pasted where a name goes was printed back once) is not repeated.
    param([string]$Name)
    if ($Name -cmatch '\A[A-Za-z][A-Za-z0-9_]{0,39}\z') { return ("'" + $Name + "'") }
    return "a field whose name is not repeated here"
}

function Test-HordePublishText {
    # Why one text of a line cannot be published, as the end of a refusal, or "". -Where is "item 3 text".
    param([string]$Where, $Value, [switch]$Required, [switch]$OneLine)
    if ($null -eq $Value) {
        if ($Required) { return ($Where + " is missing") }
        return ""
    }
    if ($Value -isnot [string]) { return ($Where + " must be text") }
    if ($Value.Length -eq 0) {
        if ($Required) { return ($Where + " is empty") }
        return ($Where + " is empty: leave the field out, or give it null")
    }
    if ($Value.Length -gt $script:HordePublishMaxText) { return ($Where + " is " + $Value.Length + " characters; at most " + $script:HordePublishMaxText) }
    $bad = [regex]::Match($Value, '[^\x20-\x7E\r\n\t]')
    if ($bad.Success) { return ($Where + " holds the character U+" + ([int][char]$bad.Value).ToString("X4") + ", which is not plain ASCII") }
    if ($OneLine) {
        $brk = [regex]::Match($Value, '[\x0d\x0a]')
        if ($brk.Success) { return ($Where + " holds a line break; it is one line") }
    }
    $problem = $(if ($OneLine) { Get-HordeDecisionCharProblem -Text $Value -OneLine } else { Get-HordeDecisionCharProblem -Text $Value })
    if ($problem -ne "") { return ($Where + " " + $problem) }
    return ""
}

function Test-HordeDecisionPublishFile {
    # The file's object checked and turned into the lines the node side takes. Returns { ok; reason; items }.
    # The secret check comes first and over the whole file, names included, so no later refusal can repeat one.
    param($Parsed)
    $no = { param([string]$Why) return [pscustomobject]@{ ok = $false; reason = $Why; items = @() } }
    $secrets = @(Find-HordeDecisionSecrets -Value $Parsed -Path "the file")
    if ($secrets.Count -gt 0) { return (& $no ("the file holds what looks like a secret in " + $secrets.Count + " place(s); nothing was published. " + $secrets[0])) }
    foreach ($p in @($Parsed.PSObject.Properties)) {
        if ($p.Name -imatch $script:HordePublishWhoNames) {
            return (& $no ("the file names who publishes ('" + $p.Name + "'). The Orc is the calling session, proven by horde, and is never taken from a file; remove the field"))
        }
        if ($script:HordePublishTopFields -cnotcontains $p.Name) { return (& $no ("the file has no field " + (Get-HordePublishFieldShown -Name $p.Name) + "; it holds only items")) }
    }
    $member = $Parsed.PSObject.Properties["items"]
    if ($null -eq $member) { return (& $no "the file needs items: the list, in order (an empty list is valid: items: [])") }
    if ($member.Value -isnot [System.Array]) { return (& $no "items must be a list (an empty one is a list)") }
    $out = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($item in @($member.Value)) {
        $i++
        $at = "item " + $i
        if ($item -isnot [System.Management.Automation.PSCustomObject]) { return (& $no ($at + " must be an object")) }
        foreach ($p in @($item.PSObject.Properties)) {
            if ($script:HordePublishItemFields -cnotcontains $p.Name) { return (& $no ($at + " has no field " + (Get-HordePublishFieldShown -Name $p.Name) + "; its fields are " + ($script:HordePublishItemFields -join ", "))) }
        }
        $get = { param([string]$Name) $m = $item.PSObject.Properties[$Name]; if ($null -eq $m) { return $null }; return $m.Value }
        $number = & $get "questionNumber"
        if ($null -ne $number) {
            if (($number -isnot [int] -and $number -isnot [long]) -or $number -lt 1 -or $number -gt (Get-HordeDecisionMaxNumber)) { return (& $no ($at + " questionNumber must be a question's number (a whole number from 1), or null")) }
        }
        $reason = Test-HordePublishText -Where ($at + " text") -Value (& $get "text") -Required -OneLine
        if ($reason -ne "") { return (& $no $reason) }
        $reason = Test-HordePublishText -Where ($at + " recommendation") -Value (& $get "recommendation")
        if ($reason -ne "") { return (& $no $reason) }
        foreach ($pair in @(@("importance", (Get-HordeDecisionImportances)), @("blocks", (Get-HordeDecisionBlockings)))) {
            $word = & $get $pair[0]
            if ($null -eq $word) { continue }
            if ($word -isnot [string] -or @($pair[1]) -cnotcontains $word) { return (& $no ($at + " " + $pair[0] + " must be one of " + (@($pair[1]) -join ", ") + ", or null")) }
        }
        $line = [ordered]@{ text = & $get "text" }
        if ($null -ne $number) { $line["questionNumber"] = [long]$number }
        foreach ($name in @("recommendation", "importance", "blocks")) { $v = & $get $name; if ($null -ne $v) { $line[$name] = $v } }
        [void]$out.Add($line)
    }
    return [pscustomobject]@{ ok = $true; reason = ""; items = @($out) }
}

function Resolve-HordeDecisionPublisher {
    # Who is publishing, PROVEN: { thrall; letter; sessionId }, or a throw in words. Sender, SenderArgs, SeatProof
    # and SeatArgs are the proofs' own sources (see Resolve-HordeDecisionOrcCaller), which a suite fills with a
    # fleet of its own.
    param([scriptblock]$Sender = $null, [hashtable]$SenderArgs = @{}, [scriptblock]$SeatProof = $null, [hashtable]$SeatArgs = @{})
    $who = $null
    if ($null -ne $Sender) { $who = & $Sender }
    else {
        . (Join-Path (Split-Path -Parent $PSScriptRoot) "notices\Sender.ps1")
        $who = Resolve-HordeNoticeSender @SenderArgs
    }
    if ($null -eq $who -or -not [bool]$who.ok) { throw ("decisions publish is run by the session that owns the list, and which session this is could not be proven: " + $(if ($null -eq $who) { "nothing answered" } else { ("" + $who.reason) -replace '\Ano notice was sent: ', '' })) }
    $proven = $who
    $fixed = { $proven }.GetNewClosure()
    $orcReason = ""
    if ("$($proven.label)" -cmatch '\A[A-Z]\z') {
        try {
            $null = Resolve-HordeDecisionOrcCaller -Verb "publish" -Instead "" -Sender $fixed -SeatProof $SeatProof -SeatArgs $SeatArgs
            return [pscustomobject]@{ thrall = $false; letter = "$($proven.label)"; sessionId = "$($proven.sessionId)" }
        } catch { $orcReason = $_.Exception.Message }
    }
    $warchief = Test-HordeDecisionWarchiefCaller -Sender $fixed -SeatProof $SeatProof -SeatArgs $SeatArgs
    if ($warchief.ok) { return [pscustomobject]@{ thrall = $true; letter = ""; sessionId = "$($proven.sessionId)" } }
    if ($orcReason -ne "") { throw $orcReason }
    throw ("decisions publish is run by an Orc or the Thrall from inside its own session, and this session's label '" + $proven.label + "' is neither an Orc's lane letter nor proven to hold the Thrall's seat (" + $warchief.reason + ")")
}

function Invoke-HordeDecisionNode {
    # Run fleet-db/decisions-cli.mjs with -NodeArgs; { code; out; err }. Node is checked first, in one sentence, as
    # cli/commands/db.ps1 checks it, and HORDE_HOME must be named: fleet.db is the fleet's one database and is
    # never made in a default folder. The streams are read through the process API (CONTRIBUTING 12).
    param([Parameter(Mandatory = $true)][string[]]$NodeArgs)
    if ("$env:HORDE_HOME".Trim() -eq "") { throw "horde decisions publish needs HORDE_HOME set to the Horde home: fleet.db is the fleet's one database and is never made in a default folder" }
    $root = Split-Path -Parent $PSScriptRoot
    . (Join-Path $root "core\Home.ps1")
    $hordeHome = Get-HordeHome
    $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $node) { throw "fleet.db needs Node.js 24 or later, and node is not installed or not on this machine's PATH" }
    $major = 0
    $ver = "" + (& $node.Source --version)
    if ($ver -match '^v(\d+)\.') { $major = [int]$Matches[1] }
    if ($major -lt 24) { throw ("fleet.db needs Node.js 24 or later, and this machine has " + $ver.Trim()) }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $quoted = @($NodeArgs | ForEach-Object { '"' + $_ + '"' })
    $psi.Arguments = '"' + (Join-Path $root "fleet-db\decisions-cli.mjs") + '" ' + ($quoted -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $psi.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $psi.EnvironmentVariables["HORDE_HOME"] = $hordeHome
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $errTask = $p.StandardError.ReadToEndAsync()
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        return [pscustomobject]@{ code = $p.ExitCode; out = $out.Trim(); err = ("" + $errTask.Result).Trim() }
    } finally { $p.Dispose() }
}

function Invoke-HordeDecisionPublishVerb {
    # Run `publish` or `published`. -Given is the command's bound parameters, by name. Returns { lines; failure }
    # like Invoke-HordeDecisionCommand: the lines to print, and the message to fail with ("" for none).
    param([Parameter(Mandatory = $true)][ValidateSet("publish", "published")][string]$Verb, [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Given, [scriptblock]$Sender = $null, [hashtable]$SenderArgs = @{}, [scriptblock]$SeatProof = $null, [hashtable]$SeatArgs = @{})
    $have = @{}
    foreach ($k in @($Given.Keys)) { $have["$k"] = $Given[$k] }
    if ($Verb -ceq "published") {
        $nodeArgs = @("published")
        if ($have.ContainsKey("Orc")) {
            $letter = "$($have['Orc'])"
            if ($letter -cnotmatch '\A[A-Z][A-Z0-9]{0,3}\z') { throw "-Orc is an Orc's lane letter, as in: -Orc F" }
            $nodeArgs += @("--orc", $letter)
        }
        if ($have.ContainsKey("Json") -and [bool]$have["Json"]) { $nodeArgs += "--json" }
        $r = Invoke-HordeDecisionNode -NodeArgs $nodeArgs
        if ($r.code -ne 0) { return [pscustomobject]@{ lines = @(); failure = ("horde decisions published: " + $r.err) } }
        return [pscustomobject]@{ lines = @($r.out -split "\r?\n"); failure = "" }
    }
    if (-not $have.ContainsKey("File")) { throw "decisions publish needs -File <list.json>: the list, as a JSON file { items: [ { questionNumber, text, recommendation, importance, blocks } ] }" }
    $parsed = Read-HordeDecisionJsonFile -Path "$($have['File'])" -What "the list file"
    $checked = Test-HordeDecisionPublishFile -Parsed $parsed
    if (-not $checked.ok) { return [pscustomobject]@{ lines = @(); failure = ("refused: " + $checked.reason) } }
    # PROVEN LAST, after the file is known to be a list, but BEFORE anything is started or written.
    $publisher = Resolve-HordeDecisionPublisher -Sender $Sender -SenderArgs $SenderArgs -SeatProof $SeatProof -SeatArgs $SeatArgs
    $who = $(if ($publisher.thrall) { [ordered]@{ thrall = $true } } else { [ordered]@{ letter = $publisher.letter } })
    $input_ = [ordered]@{ who = $who; sessionId = $publisher.sessionId; items = @($checked.items) }
    $json = ConvertTo-Json -InputObject $input_ -Compress -Depth 8
    $json = [regex]::Replace($json, '[^\x20-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") })
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-publish-" + [guid]::NewGuid().ToString("N") + ".json")
    try {
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        $r = Invoke-HordeDecisionNode -NodeArgs @("publish", $tmp)
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
    if ($r.code -ne 0) { return [pscustomobject]@{ lines = @(); failure = $(if ($r.err -ne "") { $r.err } else { "horde decisions publish stopped with exit code " + $r.code }) } }
    return [pscustomobject]@{ lines = @($r.out); failure = "" }
}
