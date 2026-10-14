# cli/Setup.ps1 - `horde setup`: the first run of Horde on a machine. It checks each step in order,
# FIXES what it safely can, stops at the first step it cannot finish, and says the ONE next thing to
# do with the exact command or action - or that all is set. Run again, it changes nothing that is
# already right (each fix makes only what is missing), so a second run of a finished machine says
# "all set" and touches nothing.
#
# WHY (2026-10-14). Horde's first person to install it on a fresh machine was stuck: there was no setup
# command, and what he had to do was a page of hand-typed steps. The founder's decision of that day:
# every user shares the shipped relay (open sign-up with any Google account), so a user deploys
# nothing and makes no Google client; hosting a relay of one's own is the OPERATOR's path, -Operator.
#
# THE STEPS ARE ONE LIST OF DATA (Get-HordeSetupSteps): each { id; title; path; checks; fixes; manual;
# check; fix; next }, in order. The run below walks it, `horde setup -Steps [-Json]` prints it, and a
# later change can generate the README's "First run" from it, so the page and the command cannot
# drift apart. path is "user" for every machine, "operator" for -Operator only.
#   home             the Horde home (HORDE_HOME, or .horde in the profile)          fix: made
#   relay-hosting    OPERATOR: the hosted relay's own steps - where it answers, its sign-in client
#                    with the exact redirect URI and JavaScript origin, its tools - which are that
#                    relay's to say (relays/Port.ps1, Get-HordeRelaySetup), since nothing outside its
#                    folder may name it (CONTRIBUTING rule 14)                        fix: none
#   relay-deployed   OPERATOR: deployed from this home to that origin (deployed.json) fix: none
#   relay-settings   settings\relay.json naming this horde and the phone app       fix: written, when
#                    the file is not there (ASCII, never ConvertTo-Json: Windows PowerShell 5.1's
#                    escapes and line ends are its own); a file that is there is the person's, and
#                    only what to add to it is said
#   machine-identity this machine's relay identity                                  fix: made (horde
#                    relay identity -New), unless -NoFix names it
#   runner-defined   the relay runner as a service of this home                     fix: written, when
#                    service-definitions.json is not there; added to by the person otherwise
#   runner-serving   the relay runner running, its heartbeat fresh and well          fix: none - it is
#                    a long-running process, started by the person or the supervisor, never here
#   phone-paired     a phone signed in, paired and trusted                           fix: none - the
#                    sign-in is the phone's and the pairing needs the person at both ends
#
# WHAT IT NEVER DOES: ask for or store a password or a key's secret (Google sign-in stays on the
# phone; the identity's keys are made in this machine's key store and never leave it), start a
# long-running process, schedule anything, contact the network, or say anything secret.
#
# HONEST ABOUT EACH STEP: "done" was already so, "fixed" was made by this run, "TO DO" is where it
# stopped - including a fix that was tried and failed, with why.
#
# EVERY OUTSIDE ANSWER IS A PROBE (-Probes), so a suite stands in for what it must not touch - this
# machine's key store, a phone - and uses the real files for the rest.
#
# No Set-StrictMode here: dot-sourced. The caller loads core (Tristate, Home, ModuleSettings,
# Heartbeat, Services), relays/Port.ps1 with the relays, relay/Trust.ps1, cli/RelayDeploy.ps1 and
# cli/RelayRun.ps1, as cli/commands/setup.ps1 does.

function ConvertTo-HordeSetupJsonString {
    # -Text as a JSON string, in ASCII: quote and backslash escaped, and every other character outside
    # printable ASCII written as \uXXXX, so the file is ASCII whatever a path holds.
    param([AllowEmptyString()][string]$Text)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($c in $Text.ToCharArray()) {
        $n = [int]$c
        if ($c -eq '"') { [void]$sb.Append('\"') }
        elseif ($c -eq '\') { [void]$sb.Append('\\') }
        elseif ($n -lt 0x20 -or $n -gt 0x7E) { [void]$sb.Append('\u' + $n.ToString("x4")) }
        else { [void]$sb.Append($c) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Get-HordeSetupRelaySettingsText {
    # settings\relay.json for this horde and the phone app at -Origin, as the fix writes it.
    param([Parameter(Mandatory = $true)][string]$Horde, [Parameter(Mandatory = $true)][string]$Origin)
    return ('{ "schemaVersion": 1, "settings": { "horde": ' + (ConvertTo-HordeSetupJsonString $Horde) + ', "pairRpId": ' + (ConvertTo-HordeSetupJsonString ([uri]$Origin).Host) + ', "pairOrigin": ' + (ConvertTo-HordeSetupJsonString $Origin) + ' } }')
}

function Get-HordeSetupRunnerEntry {
    # The relay runner's service definition for this home (core/Services.ps1 reads it): the relay run of
    # this checkout, asked to stop by `relay stop`, alive by its heartbeat.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$Relay)
    return ('"relay-runner": { "checkout": ' + (ConvertTo-HordeSetupJsonString $Root) + ', "hordeHome": ' + (ConvertTo-HordeSetupJsonString $HordeHome) +
        ', "start": { "kind": "horde", "words": ["relay", "run"], "named": { "Relay": ' + (ConvertTo-HordeSetupJsonString $Relay) + ' } }' +
        ', "stop": { "kind": "horde", "words": ["relay", "stop"], "waitSeconds": 30 }' +
        ', "alive": { "heartbeat": "relay\\run-heartbeat.json", "tickSeconds": 60 } }')
}

function Write-HordeSetupNewFile {
    # Write -Text, ASCII, to -Path only when no file is there: "" when written, else why not. Made beside
    # and moved into place, so a reader never sees half of it; never over a file that appeared meanwhile.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
    try {
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        $temp = $Path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
        [System.IO.File]::WriteAllText($temp, $Text, [System.Text.Encoding]::ASCII)
        try { [System.IO.File]::Move($temp, $Path) } catch { try { [System.IO.File]::Delete($temp) } catch { }; throw }
        return ""
    } catch { return ("it could not be written: " + $_.Exception.Message) }
}

function New-HordeSetupResult {
    # What a check or a fix found: done, its words, and notes to show beside it.
    param([bool]$Done, [string]$Said, [string[]]$Notes = @())
    return [pscustomobject]@{ done = $Done; said = $Said; notes = [string[]]@($Notes) }
}

function Get-HordeSetupDefaultProbes {
    # The real answers, each a block a suite may replace.
    return @{
        relaySetup    = { param($Name, $HordeHome) Get-HordeRelaySetup -Name $Name -HordeHome $HordeHome }
        deployed      = { param($HordeHome) Read-HordeRelayDeployed -HordeHome $HordeHome }
        relaySettings = { param($HordeHome) Get-HordeRelaySettingValues -HordeHome $HordeHome }
        identity      = { param($HordeHome) Read-HordeRelayIdentityRecords -HordeHome $HordeHome }
        makeIdentity  = { param($HordeHome) New-HordeRelayMachineIdentity -HordeHome $HordeHome -Provider "auto" }
        services      = { param($HordeHome) Get-HordeServiceDefinitions -HordeHome $HordeHome }
        heartbeat     = { param($Path) Read-HordeHeartbeat -Path $Path }
        trust         = { param($HordeHome) Get-HordeRelayTrust -HordeHome $HordeHome }
        now           = { [datetime]::UtcNow }
    }
}

function Get-HordeSetupSteps {
    # THE ONE LIST (the header): every step in order, as data and as the blocks that check it, fix it
    # and say what to do next. Each block takes the run's context, -Ctx (Get-HordeSetupReport).
    return @(
        [pscustomobject]@{ id = "home"; title = "Horde home"; path = "user"
            checks = "the Horde home exists: HORDE_HOME, or .horde in the user's profile"
            fixes = "makes the folder"; manual = ""
            check = { param($Ctx) $(if ([System.IO.Directory]::Exists($Ctx.home)) { New-HordeSetupResult $true $Ctx.home } else { New-HordeSetupResult $false ("there is no folder " + $Ctx.home) }) }
            fix = { param($Ctx) [void][System.IO.Directory]::CreateDirectory($Ctx.home); New-HordeSetupResult $true ($Ctx.home + " (made just now)") }
            next = { param($Ctx) "make the folder " + $Ctx.home } },
        [pscustomobject]@{ id = "relay-hosting"; title = "the hosted relay's own steps"; path = "operator"
            checks = "for a home that hosts its own relay: where it will answer, its Google sign-in client (with the exact redirect URI and JavaScript origin to register), and the tools it is deployed with - each as the relay itself says"
            fixes = ""; manual = "each step as the relay says"
            check = $null; fix = $null; next = $null },
        [pscustomobject]@{ id = "relay-deployed"; title = "relay deployed"; path = "operator"
            checks = "the relay was deployed from this home, to the origin it will answer at"
            fixes = ""; manual = "horde relay deploy -Relay <relay>"
            check = {
                param($Ctx)
                $rec = & $Ctx.probes.deployed $Ctx.home
                if ($rec.state -ceq "known" -and $rec.value.relay -ceq $Ctx.relay -and $rec.value.origin -ceq $Ctx.origin) { return (New-HordeSetupResult $true ("deployed from this home to " + $rec.value.origin + " on " + $rec.value.at.ToString("yyyy-MM-dd HH:mm 'UTC'", [System.Globalization.CultureInfo]::InvariantCulture))) }
                if ($rec.state -ceq "known") { return (New-HordeSetupResult $false ("the last deploy from this home was of relay " + $rec.value.relay + " to " + $rec.value.origin + ", not to " + $Ctx.origin)) }
                if ($rec.state -ceq "absent") { return (New-HordeSetupResult $false "nothing has been deployed from this home yet") }
                return (New-HordeSetupResult $false $rec.reason)
            }
            fix = $null
            next = { param($Ctx) $(if ($Ctx.beforeDeploy -ne "") { "first " + $Ctx.beforeDeploy + "; then " } else { "" }) + "horde relay deploy -Relay " + $Ctx.relay } },
        [pscustomobject]@{ id = "relay-settings"; title = "relay settings"; path = "user"
            checks = "settings\relay.json names this machine's horde and where the phone app is (pairRpId, pairOrigin), for the relay this home uses"
            fixes = "writes settings\relay.json when it is not there (the horde named by -Horde, home by default)"; manual = "add what is missing to settings\relay.json"
            check = {
                param($Ctx)
                $set = & $Ctx.probes.relaySettings $Ctx.home
                if ($set.state -cne "known") { $Ctx.state["settingsPath"] = ""; return (New-HordeSetupResult $false $set.reason) }
                $Ctx.state["settingsPath"] = $set.value.path
                $v = $set.value.values
                $rpId = ([uri]$Ctx.origin).Host
                $missing = New-Object System.Collections.ArrayList
                if (("" + $v.horde) -eq "" -or (Test-HordeRelayHordeName -Name ("" + $v.horde)) -ne "") { [void]$missing.Add('"horde": ' + (ConvertTo-HordeSetupJsonString $Ctx.horde)) }
                if (("" + $v.pairRpId) -eq "") { [void]$missing.Add('"pairRpId": ' + (ConvertTo-HordeSetupJsonString $rpId)) }
                if (("" + $v.pairOrigin) -eq "") { [void]$missing.Add('"pairOrigin": ' + (ConvertTo-HordeSetupJsonString $Ctx.origin)) }
                $Ctx.state["settingsMissing"] = ($missing -join ", ")
                if ($missing.Count -gt 0) { return (New-HordeSetupResult $false "the relay settings do not yet name this machine's horde and where the phone app is") }
                $notes = @()
                if (("" + $v.pairOrigin) -cne $Ctx.origin) { $notes += ("note: pairing names the phone app at " + $v.pairOrigin + ", not at the relay this home uses, " + $Ctx.origin) }
                return (New-HordeSetupResult $true ("this machine is of the horde " + $v.horde + "; the phone app is at " + $v.pairOrigin) $notes)
            }
            fix = {
                param($Ctx)
                $path = "" + $Ctx.state["settingsPath"]
                if ($path -eq "" -or [System.IO.File]::Exists($path)) { return $null }
                $why = Test-HordeRelayHordeName -Name $Ctx.horde
                if ($why -ne "") { return (New-HordeSetupResult $false ("the horde name given is refused: " + $why)) }
                $failed = Write-HordeSetupNewFile -Path $path -Text (Get-HordeSetupRelaySettingsText -Horde $Ctx.horde -Origin $Ctx.origin)
                if ($failed -ne "") { return (New-HordeSetupResult $false ($path + ": " + $failed)) }
                return (New-HordeSetupResult $true ("wrote " + $path + ": the horde " + $Ctx.horde + ", the phone app at " + $Ctx.origin))
            }
            next = {
                param($Ctx)
                $path = "" + $Ctx.state["settingsPath"]
                if ($path -eq "") { return "correct the relay settings file as the line above says, then run horde setup again" }
                if ([System.IO.File]::Exists($path)) { return ("add " + $Ctx.state["settingsMissing"] + " to the settings in " + $path) }
                return ("horde setup -Horde <a name for this horde: a-z, 0-9 and -, such as home>")
            } },
        [pscustomobject]@{ id = "machine-identity"; title = "machine identity"; path = "user"
            checks = "this machine has its relay identity: its keys, made in this machine's key store (the TPM when there is one) and never copied"
            fixes = "makes it, as horde relay identity -New does"; manual = "horde relay identity -New"
            check = {
                param($Ctx)
                $idn = & $Ctx.probes.identity $Ctx.home
                if (-not $idn.ok) { return (New-HordeSetupResult $false $idn.reason) }
                if (@($idn.machines).Count -eq 0) { return (New-HordeSetupResult $false "this machine has no relay identity yet") }
                return (New-HordeSetupResult $true ("this machine's relay identity is made (generation " + $idn.machines[-1].generation + ")"))
            }
            fix = {
                param($Ctx)
                $idn = & $Ctx.probes.identity $Ctx.home
                if (-not $idn.ok -or @($idn.machines).Count -gt 0) { return $null }
                $made = & $Ctx.probes.makeIdentity $Ctx.home
                if ($made.state -cne "known") { return (New-HordeSetupResult $false ("it could not be made: " + $(if ($made.state -ceq "absent") { $made.note } else { $made.reason }))) }
                return (New-HordeSetupResult $true ("made this machine's relay identity (generation " + $made.value.generation + ", horde " + $made.value.horde + ")"))
            }
            next = { param($Ctx) "horde relay identity -New" } },
        [pscustomobject]@{ id = "runner-defined"; title = "relay runner defined"; path = "user"
            checks = "settings\service-definitions.json holds the relay runner for this home, so the supervisor can keep it running"
            fixes = "writes settings\service-definitions.json when it is not there"; manual = "add the relay-runner entry setup prints to settings\service-definitions.json"
            check = {
                param($Ctx)
                $defs = & $Ctx.probes.services $Ctx.home
                $Ctx.state["defs"] = $defs
                if ($defs.state -ceq "refused") { return (New-HordeSetupResult $false (@($defs.findings) -join " ")) }
                $runner = @(@($defs.services) | Where-Object { $_.enabled -and $null -ne $_.start -and $_.start.kind -ceq "horde" -and (@($_.start.words) -join " ") -ceq "relay run" -and (Test-HordeSetupSamePath $_.hordeHome $Ctx.home) } | Select-Object -First 1)
                if ($runner.Count -eq 0) { return (New-HordeSetupResult $false "no service of this home runs the relay runner (horde relay run)") }
                $Ctx.state["runner"] = $runner[0]
                return (New-HordeSetupResult $true ("the service " + $runner[0].name + " runs horde relay run for this home"))
            }
            fix = {
                param($Ctx)
                $defs = $Ctx.state["defs"]
                if ($null -eq $defs -or $defs.state -cne "none") { return $null }
                $failed = Write-HordeSetupNewFile -Path $defs.path -Text ('{ "schemaVersion": 1, "settings": { ' + (Get-HordeSetupRunnerEntry -Root $Ctx.root -HordeHome $Ctx.home -Relay $Ctx.relay) + ' } }')
                if ($failed -ne "") { return (New-HordeSetupResult $false ($defs.path + ": " + $failed)) }
                $again = & $Ctx.probes.services $Ctx.home
                $runner = @(@($again.services) | Where-Object { $_.name -ceq "relay-runner" })
                if ($again.state -cne "read" -or $runner.Count -ne 1) { return (New-HordeSetupResult $false ("wrote " + $defs.path + ", and it does not read back: " + (@($again.findings) -join " "))) }
                $Ctx.state["runner"] = $runner[0]
                return (New-HordeSetupResult $true ("wrote " + $defs.path + ": the service relay-runner runs horde relay run of this checkout for this home"))
            }
            next = {
                param($Ctx)
                $defs = $Ctx.state["defs"]
                if ($null -ne $defs -and $defs.state -ceq "refused") { return ("correct " + $defs.path + " as the line above says, then run horde setup again") }
                return ("add " + (Get-HordeSetupRunnerEntry -Root $Ctx.root -HordeHome $Ctx.home -Relay $Ctx.relay) + " to the settings in " + $(if ($null -ne $defs) { $defs.path } else { "settings\service-definitions.json" }))
            } },
        [pscustomobject]@{ id = "runner-serving"; title = "relay runner serving"; path = "user"
            checks = "the relay runner is running for this home - what carries questions to the phone and answers back - its heartbeat fresh and well"
            fixes = ""; manual = "horde relay run -Relay <relay>, left running in its own window; or, to have it kept running from start-up, from a prompt run as administrator: horde services schedule"
            check = {
                param($Ctx)
                $runner = $Ctx.state["runner"]
                $path = $(if ($null -ne $runner -and $null -ne $runner.alive -and "" + $runner.alive.path -ne "") { $runner.alive.path } else { Get-HordeRelayRunHeartbeatPath -HordeHome $Ctx.home })
                $tick = $(if ($null -ne $runner -and $null -ne $runner.alive) { [int]$runner.alive.tickSeconds } else { 60 })
                $beat = & $Ctx.probes.heartbeat $path
                $verdict = $(if ($beat.state -ceq "known") { Get-HordeHeartbeatVerdict -Heartbeat $beat -Now (& $Ctx.probes.now) -DefaultTickSeconds $tick } else { $beat })
                if ($verdict.state -ceq "absent") { return (New-HordeSetupResult $false "the relay runner has never run for this home") }
                if ($verdict.state -cne "known") { return (New-HordeSetupResult $false $verdict.reason) }
                if (-not $verdict.value.fresh) { return (New-HordeSetupResult $false ("the relay runner's last heartbeat is " + $verdict.value.ageSeconds + " s old: it is not running")) }
                if ("" + $beat.value.condition -ne "") { return (New-HordeSetupResult $false ("the relay runner is running and cannot do its work: " + $beat.value.condition + $(if ("" + $beat.value.why -ne "") { ", " + $beat.value.why } else { "" }))) }
                return (New-HordeSetupResult $true ("the relay runner's heartbeat is " + $verdict.value.ageSeconds + " s old, and well"))
            }
            fix = $null
            next = { param($Ctx) "horde relay run -Relay " + $Ctx.relay + ", and leave that window open; or, to have it kept running from start-up, from a prompt run as administrator, with HORDE_HOME as it is here: horde services schedule" } },
        [pscustomobject]@{ id = "phone-paired"; title = "phone paired"; path = "user"
            checks = "a phone is paired with this machine and trusted"
            fixes = ""; manual = "on the phone, open the phone app, sign in with Google and add it to the home screen; then horde relay pair -Relay <relay> -Label <a name for this machine>"
            check = {
                param($Ctx)
                $tr = & $Ctx.probes.trust $Ctx.home
                if ($tr.state -cne "known") { return (New-HordeSetupResult $false $tr.reason) }
                $trusted = @(@($tr.value.devices) | Where-Object { $_.state -ceq "trusted" })
                $warn = "the pairing code it shows is good for minutes (15 at most), and for whoever uses it first: never photograph it, send it, or show it on a screen share; if someone else may have seen it, close it and pair again"
                if ($trusted.Count -eq 0) { return (New-HordeSetupResult $false "no phone is paired with this machine yet" @($warn)) }
                return (New-HordeSetupResult $true ($(if ($trusted.Count -eq 1) { "one phone is" } else { "" + $trusted.Count + " phones are" }) + " paired and trusted"))
            }
            fix = $null
            next = { param($Ctx) "on the phone, open " + $Ctx.origin + "/app/index.html, sign in with Google, add it to the home screen and open it from there; then here: horde relay pair -Relay " + $Ctx.relay + " -Label """ + $Ctx.label + """, scan the code with the app, and check the 12-digit number" } }
    )
}

function Test-HordeSetupSamePath {
    # Do two folders name one place? Compared whole and without case, as Windows compares them.
    param([string]$A, [string]$B)
    if ($A -eq "" -or $B -eq "") { return $false }
    try { return ([System.IO.Path]::GetFullPath($A).TrimEnd('\', '/') -ieq [System.IO.Path]::GetFullPath($B).TrimEnd('\', '/')) } catch { return $false }
}

function New-HordeSetupLine {
    # One step as the report shows it: state is done, fixed or todo.
    param([string]$Id, [string]$Title, [string]$State, [string]$Said, [string]$Next = "", [string[]]$Notes = @())
    return [pscustomobject]@{ id = $Id; title = $Title; state = $State; said = $Said; next = $Next; notes = [string[]]@($Notes) }
}

function Get-HordeSetupReport {
    # Walk the steps for -HordeHome, fixing what may be fixed, up to and including the first that is
    # not done: { home; relay; origin; steps; next }, each step { id; title; state; said; next; notes }.
    # next is that last step's one thing to do, or "" when every step is done. -Operator walks the
    # operator's steps too. -Horde names the horde a written relay settings file gets. -NoFix lists step
    # ids not to fix (only to check). -CheckOnly fixes nothing. -Probes replaces any default answer.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$Root, [string]$Relay = "", [switch]$Operator,
        [string]$Horde = "home", [string]$Label = "", [string[]]$NoFix = @(), [switch]$CheckOnly, [hashtable]$Probes = @{})
    $p = Get-HordeSetupDefaultProbes
    foreach ($k in @($Probes.Keys)) { $p[$k] = $Probes[$k] }
    $lines = New-Object System.Collections.ArrayList
    $finish = { param($Name, $Origin) [pscustomobject]@{ home = $HordeHome; relay = $Name; origin = $Origin; steps = @($lines.ToArray()); next = $(if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].state -ceq "todo") { $lines[$lines.Count - 1].next } else { "" }) } }
    $ctx = [pscustomobject]@{ home = $HordeHome; root = $Root; relay = ""; origin = ""; beforeDeploy = ""; horde = $Horde; label = $(if ($Label -ne "") { $Label } else { "" + $env:COMPUTERNAME }); probes = $p; state = @{} }
    $relayKnown = $false
    foreach ($step in @(Get-HordeSetupSteps)) {
        if ($step.path -ceq "operator" -and -not $Operator) { continue }
        # The relay this home uses is resolved before the first step that needs it: every step after
        # the home names it or its origin.
        if ($step.id -cne "home" -and -not $relayKnown) {
            $target = Resolve-HordeRelayDeployTarget -Relay $Relay
            if ($target.state -cne "known") { [void]$lines.Add((New-HordeSetupLine "relay" "relay" "todo" $target.reason "horde setup -Relay <name>, naming the relay this machine is to use")); return (& $finish "" "") }
            $ctx.relay = $target.value
            $rs = & $p.relaySetup $ctx.relay $HordeHome
            if ($rs.state -cne "known" -or "" + $rs.value.origin -eq "") {
                [void]$lines.Add((New-HordeSetupLine "relay" ("relay " + $ctx.relay) "todo" $(if ($rs.state -cne "known") { $rs.reason } else { "the relay cannot say where it answers" }) "correct what the line above names, then run horde setup again"))
                return (& $finish $ctx.relay "")
            }
            $ctx.origin = "" + $rs.value.origin
            $ctx.beforeDeploy = "" + $rs.value.beforeDeploy
            $relayKnown = $true
        }
        if ($step.id -ceq "relay-hosting") {
            foreach ($s in @($rs.value.steps)) {
                [void]$lines.Add((New-HordeSetupLine ("relay-hosting:" + $s.name) $s.name $(if ($s.done) { "done" } else { "todo" }) $s.said $s.next @($s.notes)))
                if (-not $s.done) { return (& $finish $ctx.relay $ctx.origin) }
            }
            continue
        }
        $r = & $step.check $ctx
        if ($r.done) { [void]$lines.Add((New-HordeSetupLine $step.id $step.title "done" $r.said "" $r.notes)); continue }
        if ($null -ne $step.fix -and -not $CheckOnly -and @($NoFix) -cnotcontains $step.id) {
            $f = & $step.fix $ctx
            if ($null -ne $f -and $f.done) {
                # A fix is believed only when the check then passes: "fixed" is never a guess.
                $again = & $step.check $ctx
                if ($again.done) { [void]$lines.Add((New-HordeSetupLine $step.id $step.title "fixed" $f.said "" $again.notes)); continue }
                [void]$lines.Add((New-HordeSetupLine $step.id $step.title "todo" ($f.said + "; and yet: " + $again.said) (& $step.next $ctx) $again.notes))
                return (& $finish $ctx.relay $ctx.origin)
            }
            if ($null -ne $f) { $r = New-HordeSetupResult $false ($r.said + "; setup tried: " + $f.said) $r.notes }
        }
        [void]$lines.Add((New-HordeSetupLine $step.id $step.title "todo" $r.said (& $step.next $ctx) $r.notes))
        return (& $finish $ctx.relay $ctx.origin)
    }
    return (& $finish $ctx.relay $ctx.origin)
}

function Format-HordeSetupReport {
    # The report as lines: each step looked at, its notes under it, then ONE closing line - the next
    # thing to do, or that every step is done.
    param([Parameter(Mandatory = $true)]$Report)
    $out = New-Object System.Collections.ArrayList
    [void]$out.Add("horde setup: the first run of Horde on this machine, step by step")
    foreach ($s in @($Report.steps)) {
        [void]$out.Add("  " + $(switch -CaseSensitive ($s.state) { "done" { "done  " } "fixed" { "fixed " } default { "TO DO " } }) + $s.title + ": " + $s.said)
        foreach ($n in @($s.notes)) { [void]$out.Add("        " + $n) }
    }
    if ($Report.next -ne "") { [void]$out.Add("next: " + $Report.next) }
    else { [void]$out.Add("all set: this machine runs Horde for its home, and its paired phone is served through relay " + $Report.relay + " at " + $Report.origin) }
    return @($out.ToArray())
}

function Get-HordeSetupStepList {
    # The steps as plain data, for `horde setup -Steps` and for whatever generates the README from them.
    return @(Get-HordeSetupSteps | ForEach-Object { [pscustomobject]@{ id = $_.id; title = $_.title; path = $_.path; checks = $_.checks; fixes = $_.fixes; manual = $_.manual } })
}
