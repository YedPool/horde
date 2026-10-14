# cli/Setup.ps1 - `horde setup`: the INTERPRETER of setup/steps.json, the one list of what Horde needs on
# a machine. It walks the steps in order, checks each, FIXES what it safely can, stops at the first it
# cannot finish, and says the ONE next thing to do with the exact command - or that all is set. Run
# again, it changes nothing that is right (each fix makes only what is missing), so a second run of a
# finished machine says "all set" and touches nothing.
#
# WHY (2026-10-14). Horde's first person to install it on a fresh machine was stuck: what he had to do
# was a page of hand-typed steps. The founder's design that day: the installer, the setup instructions
# and the actual requirements are TIGHTLY COUPLED SO THEY CANNOT DRIFT, and installing is super easy.
# So the steps are DATA (setup/steps.json: id, title, path, the requirement, what the check verifies,
# what the fix does, and the sentence shown when it cannot be fixed), the code for each is looked up
# by id here (Get-HordeSetupStepCode), and a step in the file with no code, or code with no step in
# the file, refuses the whole manifest - here at run time and in the suite. The README's first-run
# section and the installer are to be generated from the same file.
#
# THE MANIFEST'S VERSION is a promise about what the file may say. This code knows version
# $script:HordeSetupManifestKnown; a newer one (a manifest from a newer release beside older code) is
# refused rather than half-understood.
#
# USERS SHARE THE SHIPPED RELAY (the founder's decision, 2026-10-14): a user deploys nothing and makes
# no Google client. Hosting a relay of one's own is the OPERATOR's path, -Operator, whose steps are
# that relay's own to say (relays/Port.ps1, Get-HordeRelaySetup), since nothing outside a relay's
# folder may name it (CONTRIBUTING rule 14).
#
# WHAT IT NEVER DOES: ask for or store a password or a key's secret (Google sign-in stays on the
# phone; the identity's keys are made in this machine's key store and never leave it), start a
# long-running process, elevate itself, contact the network, or say anything secret.
#
# HONEST ABOUT EACH STEP: "done" was already so, "fixed" was made by this run and then checked again,
# "TO DO" is where it stopped - including a fix that was tried and failed, with why.
#
# EVERY OUTSIDE ANSWER IS A PROBE (-Probes), so a suite stands in for what it must not touch - this
# machine's key store, its scheduler, its elevation, a phone - and uses the real files for the rest.
#
# No Set-StrictMode here: dot-sourced. The caller loads core (Tristate, Home, ModuleSettings,
# Heartbeat, Services, ServicesFiles, ServiceHostPort, Schedule and the schedulers), relays/Port.ps1
# with the relays, relay/Trust.ps1, cli/RelayDeploy.ps1, cli/RelayRun.ps1, cli/ServicesAct.ps1 and
# cli/ServicesTend.ps1, as cli/commands/setup.ps1 does.

# The manifest format this code reads, and the newest manifest version it understands.
$script:HordeSetupManifestSchema = 1
$script:HordeSetupManifestKnown = 1
$script:HordeSetupStepFields = @("id", "title", "path", "requirement", "checks", "fixes", "manual")
# What the test question says, and how setup knows it added it (the group, and who asked).
$script:HordeSetupQuestionGroup = "Setup"
$script:HordeSetupQuestionAskedBy = "horde setup"

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

function Get-HordeSetupManifestPath {
    param([Parameter(Mandatory = $true)][string]$Root)
    return (Join-Path $Root "setup\steps.json")
}

function Read-HordeSetupManifest {
    # setup/steps.json, checked against this code: known { manifestVersion; steps } or unknown with
    # every problem. Each step has every field as printable ASCII, ids are unique, path is user or
    # operator, and the steps and the code here name exactly the same ids.
    param([Parameter(Mandatory = $true)][string]$Path)
    $problems = New-Object System.Collections.ArrayList
    $m = $null
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if (@($bytes | Where-Object { $_ -gt 126 }).Count -gt 0) { [void]$problems.Add("it is not ASCII") }
        $m = [System.Text.Encoding]::ASCII.GetString($bytes) | ConvertFrom-Json
    } catch { return (New-HordeUnknown -Reason ("the setup manifest " + $Path + " cannot be read") -ErrorRecord $_) }
    $get = { param($o, [string]$n) if ($null -ne $o -and $null -ne $o.PSObject.Properties[$n]) { $o.$n } else { $null } }
    if ((& $get $m "schemaVersion") -ne $script:HordeSetupManifestSchema) { [void]$problems.Add("its schemaVersion is not " + $script:HordeSetupManifestSchema) }
    $version = & $get $m "manifestVersion"
    if ($version -isnot [int] -or $version -lt 1) { [void]$problems.Add("its manifestVersion is not a whole number from 1") }
    elseif ($version -gt $script:HordeSetupManifestKnown) { [void]$problems.Add("its manifestVersion " + $version + " is newer than this code knows (" + $script:HordeSetupManifestKnown + "): update this checkout of Horde, or use the manifest that came with it") }
    $code = Get-HordeSetupStepCode
    $steps = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($s in @(& $get $m "steps")) {
        $id = "" + (& $get $s "id")
        foreach ($f in $script:HordeSetupStepFields) {
            $v = & $get $s $f
            if ($v -isnot [string] -or $v -cnotmatch '\A[\x20-\x7E]{1,1000}\z') { [void]$problems.Add("step '" + $id + "' has no " + $f + " of 1 to 1000 printable characters") }
        }
        if ($id -cnotmatch '\A[a-z][a-z0-9-]{0,39}\z') { [void]$problems.Add("'" + $id + "' is not a step id"); continue }
        if ($seen.ContainsKey($id)) { [void]$problems.Add("step '" + $id + "' is listed twice") }
        $seen[$id] = $true
        if (@("user", "operator") -cnotcontains ("" + (& $get $s "path"))) { [void]$problems.Add("step '" + $id + "' has a path that is not user or operator") }
        if (-not $code.Contains($id)) { [void]$problems.Add("step '" + $id + "' has no check in this code (cli/Setup.ps1)") }
        [void]$steps.Add([pscustomobject]@{ id = $id; title = "" + (& $get $s "title"); path = "" + (& $get $s "path"); requirement = "" + (& $get $s "requirement"); checks = "" + (& $get $s "checks"); fixes = "" + (& $get $s "fixes"); manual = "" + (& $get $s "manual") })
    }
    foreach ($id in @($code.Keys)) { if (-not $seen.ContainsKey($id)) { [void]$problems.Add("this code checks a step '" + $id + "' that the manifest does not list") } }
    if ($steps.Count -eq 0) { [void]$problems.Add("it lists no steps") }
    if ($problems.Count -gt 0) { return (New-HordeUnknown -Reason ("the setup manifest " + $Path + " is refused: " + ($problems -join "; "))) }
    return (New-HordeKnown -Value ([pscustomobject]@{ manifestVersion = $version; steps = @($steps.ToArray()) }))
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

function Get-HordeSetupElevatedCommand {
    # The one line a person runs to schedule the supervisor from an elevated prompt: { line; runs }.
    # What it runs is handed over as -EncodedCommand, so no path, quote or space in it can be read twice
    # by two shells; runs is the same, in plain words, to show beside it. It sets HORDE_HOME, because an
    # elevated window does not inherit this window's environment.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$HordeHome)
    $q = { param([string]$s) "'" + $s.Replace("'", "''") + "'" }
    $runs = '$env:HORDE_HOME = ' + (& $q $HordeHome) + '; & ' + (& $q (Join-Path $Root "horde.ps1")) + ' services schedule'
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($runs))
    return [pscustomobject]@{ line = ("Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand " + $enc + "'"); runs = $runs }
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

function Test-HordeSetupSamePath {
    # Do two folders name one place? Compared whole and without case, as Windows compares them.
    param([string]$A, [string]$B)
    if ($A -eq "" -or $B -eq "") { return $false }
    try { return ([System.IO.Path]::GetFullPath($A).TrimEnd('\', '/') -ieq [System.IO.Path]::GetFullPath($B).TrimEnd('\', '/')) } catch { return $false }
}

function New-HordeSetupResult {
    # What a check or a fix found: done, its words, notes to show beside it, and - only when the
    # situation calls for other words than the manifest's - the next thing to do.
    param([bool]$Done, [string]$Said, [string[]]$Notes = @(), [string]$Next = "")
    return [pscustomobject]@{ done = $Done; said = $Said; notes = [string[]]@($Notes); next = $Next }
}

function Invoke-HordeSetupHorde {
    # The shipped command, under Windows PowerShell 5.1, for home -HordeHome: { code; out }. Used for
    # the decisions list, so setup adds and reads the question exactly as a person would.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$HordeHome, [string[]]$HordeArgs = @())
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $quoted = @($HordeArgs | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } })
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $Root "horde.ps1") + "`" " + ($quoted -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_HOME"] = $HordeHome
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $err = $p.StandardError.ReadToEndAsync()
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        return [pscustomobject]@{ code = $p.ExitCode; out = $out; err = $err.Result }
    } finally { $p.Dispose() }
}

function Get-HordeSetupDefaultProbes {
    # The real answers, each a block a suite may replace.
    return @{
        platform      = {
            $shell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
            [pscustomobject]@{ windowsMajor = [Environment]::OSVersion.Version.Major; windowsBuild = [Environment]::OSVersion.Version.Build
                desktopShell = $(if ([System.IO.File]::Exists($shell)) { $shell } else { "" }); edition = "" + $PSVersionTable.PSEdition; version = "" + $PSVersionTable.PSVersion }
        }
        relaySetup    = { param($Name, $HordeHome) Get-HordeRelaySetup -Name $Name -HordeHome $HordeHome }
        deployed      = { param($HordeHome) Read-HordeRelayDeployed -HordeHome $HordeHome }
        relaySettings = { param($HordeHome) Get-HordeRelaySettingValues -HordeHome $HordeHome }
        identity      = { param($HordeHome) Read-HordeRelayIdentityRecords -HordeHome $HordeHome }
        makeIdentity  = { param($HordeHome) New-HordeRelayMachineIdentity -HordeHome $HordeHome -Provider "auto" }
        services      = { param($HordeHome) Get-HordeServiceDefinitions -HordeHome $HordeHome }
        heartbeat     = { param($Path) Read-HordeHeartbeat -Path $Path }
        trust         = { param($HordeHome) Get-HordeRelayTrust -HordeHome $HordeHome }
        now           = { [datetime]::UtcNow }
        elevated      = { ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator) }
        schedule      = {
            # Both of the supervisor's jobs, as `horde services schedule status` reads them: known
            # { jobs }, each { name; found; enabled; marked; home }, or unknown when no scheduler works.
            param($HordeHome)
            $sched = Get-HordeScheduler
            if ($sched.state -cne "known") { return $sched }
            # The names `horde services schedule` installs by default (cli/commands/services.ps1).
            $names = Get-HordeServiceTendJobNames -TaskName "Horde services tend" -Folder "Horde"
            $jobs = @(foreach ($n in @($names.startup, $names.person)) {
                $st = & $sched.value.status $n "Horde"
                if ($st.state -cne "known") { [pscustomobject]@{ name = $n; found = $false; enabled = $false; marked = $false; home = "" } }
                else { [pscustomobject]@{ name = $n; found = $true; enabled = [bool]$st.value.enabled; marked = [bool]$st.value.marked; home = "" + $st.value.home } }
            })
            return (New-HordeKnown -Value ([pscustomobject]@{ jobs = $jobs }))
        }
        installSchedule = { param($HordeHome, $Root) Invoke-HordeServiceSchedule -Action install -HordeScript (Join-Path $Root "horde.ps1") }
        decisions     = { param($HordeHome, $Root, [string[]]$HordeArgs) Invoke-HordeSetupHorde -Root $Root -HordeHome $HordeHome -HordeArgs $HordeArgs }
    }
}

function Get-HordeSetupStepCode {
    # THE CODE OF EACH STEP, by the manifest's id: { check; fix } - fix $null where the manifest says
    # none - or { expand } for the step that is a relay's own list. Each block takes the run's context,
    # -Ctx (Get-HordeSetupReport). A check answers New-HordeSetupResult; a fix answers one too, or $null
    # when there is nothing it may do in this situation.
    $code = [ordered]@{}
    $code["requirements"] = [pscustomobject]@{
        check = {
            param($Ctx)
            $p = & $Ctx.probes.platform
            $bad = New-Object System.Collections.ArrayList
            if ([int]$p.windowsMajor -lt 10) { [void]$bad.Add("Windows is version " + $p.windowsMajor + "; Horde needs 10 or 11") }
            if ("" + $p.desktopShell -eq "") { [void]$bad.Add("Windows PowerShell 5.1 (powershell.exe) is not installed") }
            elseif ("" + $p.edition -cne "Desktop") { [void]$bad.Add("setup is running under PowerShell " + $p.version + ", not Windows PowerShell 5.1") }
            if ($bad.Count -gt 0) { return (New-HordeSetupResult $false ($bad -join "; ")) }
            return (New-HordeSetupResult $true ("Windows " + $p.windowsMajor + " (build " + $p.windowsBuild + "), Windows PowerShell " + $p.version))
        }
        fix = $null }
    $code["home"] = [pscustomobject]@{
        check = { param($Ctx) $(if ([System.IO.Directory]::Exists($Ctx.home)) { New-HordeSetupResult $true $Ctx.home } else { New-HordeSetupResult $false ("there is no folder " + $Ctx.home) }) }
        fix = { param($Ctx) [void][System.IO.Directory]::CreateDirectory($Ctx.home); New-HordeSetupResult $true ($Ctx.home + " (made just now)") } }
    $code["relay-hosting"] = [pscustomobject]@{ expand = $true; check = $null; fix = $null }
    $code["relay-deployed"] = [pscustomobject]@{
        check = {
            param($Ctx)
            $rec = & $Ctx.probes.deployed $Ctx.home
            $deployNext = $(if ($Ctx.beforeDeploy -ne "") { "first " + $Ctx.beforeDeploy + "; then " } else { "" }) + "horde relay deploy -Relay " + $Ctx.relay
            if ($rec.state -ceq "known" -and $rec.value.relay -ceq $Ctx.relay -and $rec.value.origin -ceq $Ctx.origin) { return (New-HordeSetupResult $true ("deployed from this home to " + $rec.value.origin + " on " + $rec.value.at.ToString("yyyy-MM-dd HH:mm 'UTC'", [System.Globalization.CultureInfo]::InvariantCulture))) }
            if ($rec.state -ceq "known") { return (New-HordeSetupResult $false ("the last deploy from this home was of relay " + $rec.value.relay + " to " + $rec.value.origin + ", not to " + $Ctx.origin) @() $deployNext) }
            if ($rec.state -ceq "absent") { return (New-HordeSetupResult $false "nothing has been deployed from this home yet" @() $deployNext) }
            return (New-HordeSetupResult $false $rec.reason @() $deployNext)
        }
        fix = $null }
    $code["relay-settings"] = [pscustomobject]@{
        check = {
            param($Ctx)
            $set = & $Ctx.probes.relaySettings $Ctx.home
            if ($set.state -cne "known") { $Ctx.state["settingsPath"] = ""; return (New-HordeSetupResult $false $set.reason @() "correct the relay settings file as the line above says, then run horde setup again") }
            $path = $set.value.path
            $Ctx.state["settingsPath"] = $path
            $v = $set.value.values
            $missing = New-Object System.Collections.ArrayList
            if (("" + $v.horde) -eq "" -or (Test-HordeRelayHordeName -Name ("" + $v.horde)) -ne "") { [void]$missing.Add('"horde": ' + (ConvertTo-HordeSetupJsonString $Ctx.horde)) }
            if (("" + $v.pairRpId) -eq "") { [void]$missing.Add('"pairRpId": ' + (ConvertTo-HordeSetupJsonString ([uri]$Ctx.origin).Host)) }
            if (("" + $v.pairOrigin) -eq "") { [void]$missing.Add('"pairOrigin": ' + (ConvertTo-HordeSetupJsonString $Ctx.origin)) }
            if ($missing.Count -gt 0) {
                # A file that is there is the person's: what to add to it, exactly.
                $next = $(if ([System.IO.File]::Exists($path)) { "add " + ($missing -join ", ") + " to the settings in " + $path } else { "" })
                return (New-HordeSetupResult $false "the relay settings do not yet name this machine's horde and where the phone app is" @() $next)
            }
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
        } }
    $code["machine-identity"] = [pscustomobject]@{
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
        } }
    $code["runner-defined"] = [pscustomobject]@{
        check = {
            param($Ctx)
            $defs = & $Ctx.probes.services $Ctx.home
            $Ctx.state["defs"] = $defs
            $entry = Get-HordeSetupRunnerEntry -Root $Ctx.root -HordeHome $Ctx.home -Relay $Ctx.relay
            if ($defs.state -ceq "refused") { return (New-HordeSetupResult $false (@($defs.findings) -join " ") @() ("correct " + $defs.path + " as the line above says, then run horde setup again")) }
            $runner = @(@($defs.services) | Where-Object { $_.enabled -and $null -ne $_.start -and $_.start.kind -ceq "horde" -and (@($_.start.words) -join " ") -ceq "relay run" -and (Test-HordeSetupSamePath $_.hordeHome $Ctx.home) } | Select-Object -First 1)
            if ($runner.Count -eq 0) { return (New-HordeSetupResult $false "no service of this home runs the relay runner (horde relay run)" @() ("add " + $entry + " to the settings in " + $defs.path)) }
            $Ctx.state["runner"] = $runner[0]
            return (New-HordeSetupResult $true ("the service " + $runner[0].name + " runs horde relay run for this home"))
        }
        fix = {
            param($Ctx)
            $defs = $Ctx.state["defs"]
            if ($null -eq $defs -or $defs.state -cne "none") { return $null }
            $failed = Write-HordeSetupNewFile -Path $defs.path -Text ('{ "schemaVersion": 1, "settings": { ' + (Get-HordeSetupRunnerEntry -Root $Ctx.root -HordeHome $Ctx.home -Relay $Ctx.relay) + ' } }')
            if ($failed -ne "") { return (New-HordeSetupResult $false ($defs.path + ": " + $failed)) }
            return (New-HordeSetupResult $true ("wrote " + $defs.path + ": the service relay-runner runs horde relay run of this checkout for this home"))
        } }
    $code["runner-serving"] = [pscustomobject]@{
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
        fix = $null }
    $code["phone-paired"] = [pscustomobject]@{
        check = {
            param($Ctx)
            $tr = & $Ctx.probes.trust $Ctx.home
            if ($tr.state -cne "known") { return (New-HordeSetupResult $false $tr.reason) }
            $trusted = @(@($tr.value.devices) | Where-Object { $_.state -ceq "trusted" })
            $warn = "the pairing code it shows is good for minutes (15 at most), and for whoever uses it first: never photograph it, send it, or show it on a screen share; if someone else may have seen it, close it and pair again"
            if ($trusted.Count -eq 0) { return (New-HordeSetupResult $false "no phone is paired with this machine yet" @($warn)) }
            return (New-HordeSetupResult $true ($(if ($trusted.Count -eq 1) { "one phone is" } else { "" + $trusted.Count + " phones are" }) + " paired and trusted"))
        }
        fix = $null }
    $code["runner-scheduled"] = [pscustomobject]@{
        check = {
            param($Ctx)
            $sch = & $Ctx.probes.schedule $Ctx.home
            if ($sch.state -cne "known") { return (New-HordeSetupResult $false $sch.reason) }
            $short = @(@($sch.value.jobs) | Where-Object { -not $_.found -or -not $_.enabled -or -not $_.marked -or -not (Test-HordeSetupSamePath $_.home $Ctx.home) })
            if ($short.Count -gt 0) {
                $what = @($short | ForEach-Object { "'" + $_.name + "' " + $(if (-not $_.found) { "is not installed" } elseif (-not $_.marked) { "was not made by Horde" } elseif (-not $_.enabled) { "is disabled" } else { "serves another home (" + $_.home + ")" }) }) -join "; "
                return (New-HordeSetupResult $false $what @("it runs, as administrator: " + $Ctx.elevated.runs))
            }
            return (New-HordeSetupResult $true "both of the supervisor's jobs run every minute for this home, so the relay runner is kept running from start-up")
        }
        fix = {
            param($Ctx)
            # NEVER ELEVATES BY ITSELF: from a prompt that is not elevated, nothing is tried, and the
            # manifest's one line says how to run it elevated.
            if (-not (& $Ctx.probes.elevated)) { return $null }
            try { $null = & $Ctx.probes.installSchedule $Ctx.home $Ctx.root } catch { return (New-HordeSetupResult $false ("installing the supervisor's jobs failed: " + $_.Exception.Message)) }
            return (New-HordeSetupResult $true "installed both of the supervisor's jobs for this home, as horde services schedule does")
        } }
    $code["test-question"] = [pscustomobject]@{
        check = {
            param($Ctx)
            $r = & $Ctx.probes.decisions $Ctx.home $Ctx.root @("decisions", "list", "-State", "all", "-Json")
            $a = $null
            try { $a = ("" + $r.out).Trim() | ConvertFrom-Json } catch { $a = $null }
            if ($r.code -ne 0 -or $null -eq $a -or $a.state -cne "known") { return (New-HordeSetupResult $false ("the decisions list cannot be read: " + (("" + $r.err + " " + $r.out).Trim()))) }
            $mine = @(@($a.value.questions) | Where-Object { $_.group -ceq $script:HordeSetupQuestionGroup -and $_.askedBy -ceq $script:HordeSetupQuestionAskedBy })
            if ($mine.Count -eq 0) { return (New-HordeSetupResult $false "the decisions list has no question from horde setup yet") }
            return (New-HordeSetupResult $true ("question " + $mine[0].number + " is on the decisions list (" + $mine[0].state + "): answer it on the phone to see it come back"))
        }
        fix = {
            param($Ctx)
            $file = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-setup-question-" + [guid]::NewGuid().ToString("N") + ".json")
            $q = '{ "title": ' + (ConvertTo-HordeSetupJsonString ("Horde is set up on " + $Ctx.machine + " - does it reach your phone?")) + ', "kind": "yes-no", "whatItIs": ' + (ConvertTo-HordeSetupJsonString ("horde setup added this once, as its last step on " + $Ctx.machine + ", so you can see a question reach your phone and your answer come back.")) + ', "group": ' + (ConvertTo-HordeSetupJsonString $script:HordeSetupQuestionGroup) + ', "askedBy": ' + (ConvertTo-HordeSetupJsonString $script:HordeSetupQuestionAskedBy) + ' }'
            try {
                [System.IO.File]::WriteAllText($file, $q, [System.Text.Encoding]::ASCII)
                $r = & $Ctx.probes.decisions $Ctx.home $Ctx.root @("decisions", "add", "-File", $file, "-Json")
            } finally { if ([System.IO.File]::Exists($file)) { [System.IO.File]::Delete($file) } }
            $a = $null
            try { $a = ("" + $r.out).Trim() | ConvertFrom-Json } catch { $a = $null }
            if ($r.code -ne 0 -or $null -eq $a -or $a.state -cne "known") { return (New-HordeSetupResult $false ("the question could not be added: " + (("" + $r.err + " " + $r.out).Trim()))) }
            return (New-HordeSetupResult $true ("added question " + $a.value.number + ": Horde is set up on " + $Ctx.machine + " - does it reach your phone?"))
        } }
    return $code
}

function Expand-HordeSetupText {
    # A manifest sentence with its {names} filled in from the run's context.
    param([string]$Text, $Ctx)
    $out = $Text
    foreach ($k in @("relay", "origin", "home", "root", "machine", "label")) { $out = $out.Replace("{" + $k + "}", "" + $Ctx.$k) }
    return $out.Replace("{elevated}", "" + $Ctx.elevated.line)
}

function New-HordeSetupLine {
    # One step as the report shows it: state is done, fixed or todo.
    param([string]$Id, [string]$Title, [string]$State, [string]$Said, [string]$Next = "", [string[]]$Notes = @())
    return [pscustomobject]@{ id = $Id; title = $Title; state = $State; said = $Said; next = $Next; notes = [string[]]@($Notes) }
}

function Get-HordeSetupReport {
    # Walk the manifest for -HordeHome, fixing what may be fixed, up to and including the first step
    # that is not done: { home; relay; origin; manifestVersion; steps; next }, each step { id; title;
    # state; said; next; notes }. next is that last step's one thing to do, or "" when every step is
    # done. -Operator walks the operator's steps too. -Horde names the horde a written relay settings
    # file gets. -NoFix lists step ids only to check. -Check fixes nothing. -Probes replaces any answer.
    # Throws when the manifest is refused: nothing is checked against a list this code does not trust.
    param([Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$Root, [string]$Relay = "", [switch]$Operator,
        [string]$Horde = "home", [string]$Label = "", [string[]]$NoFix = @(), [switch]$Check, [hashtable]$Probes = @{}, [string]$Manifest = "")
    if ($Manifest -eq "") { $Manifest = Get-HordeSetupManifestPath -Root $Root }
    $man = Read-HordeSetupManifest -Path $Manifest
    if ($man.state -cne "known") { throw $man.reason }
    $code = Get-HordeSetupStepCode
    $p = Get-HordeSetupDefaultProbes
    foreach ($k in @($Probes.Keys)) { $p[$k] = $Probes[$k] }
    $lines = New-Object System.Collections.ArrayList
    $machine = "" + $env:COMPUTERNAME
    $ctx = [pscustomobject]@{ home = $HordeHome; root = $Root; relay = ""; origin = ""; beforeDeploy = ""; horde = $Horde; machine = $machine
        label = $(if ($Label -ne "") { $Label } else { $machine }); probes = $p; state = @{}; elevated = (Get-HordeSetupElevatedCommand -Root $Root -HordeHome $HordeHome) }
    $finish = { [pscustomobject]@{ home = $HordeHome; relay = $ctx.relay; origin = $ctx.origin; manifestVersion = $man.value.manifestVersion; steps = @($lines.ToArray()); next = $(if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].state -ceq "todo") { $lines[$lines.Count - 1].next } else { "" }) } }
    $rs = $null
    foreach ($step in @($man.value.steps)) {
        if ($step.path -ceq "operator" -and -not $Operator) { continue }
        # The relay this home uses is resolved before the first step after the home: every one of them
        # names it or its origin.
        if (@("requirements", "home") -cnotcontains $step.id -and $null -eq $rs) {
            $target = Resolve-HordeRelayDeployTarget -Relay $Relay
            if ($target.state -cne "known") { [void]$lines.Add((New-HordeSetupLine "relay" "relay" "todo" $target.reason "horde setup -Relay <name>, naming the relay this machine is to use")); return (& $finish) }
            $ctx.relay = $target.value
            $rs = & $p.relaySetup $ctx.relay $HordeHome
            if ($rs.state -cne "known" -or "" + $rs.value.origin -eq "") {
                [void]$lines.Add((New-HordeSetupLine "relay" ("relay " + $ctx.relay) "todo" $(if ($rs.state -cne "known") { $rs.reason } else { "the relay cannot say where it answers" }) "correct what the line above names, then run horde setup again"))
                return (& $finish)
            }
            $ctx.origin = "" + $rs.value.origin
            $ctx.beforeDeploy = "" + $rs.value.beforeDeploy
        }
        $c = $code[$step.id]
        if ($null -ne $c.PSObject.Properties["expand"]) {
            foreach ($s in @($rs.value.steps)) {
                [void]$lines.Add((New-HordeSetupLine ($step.id + ":" + $s.name) $s.name $(if ($s.done) { "done" } else { "todo" }) $s.said $s.next @($s.notes)))
                if (-not $s.done) { return (& $finish) }
            }
            continue
        }
        $r = & $c.check $ctx
        if ($r.done) { [void]$lines.Add((New-HordeSetupLine $step.id $step.title "done" $r.said "" $r.notes)); continue }
        if ($null -ne $c.fix -and -not $Check -and @($NoFix) -cnotcontains $step.id) {
            $f = & $c.fix $ctx
            if ($null -ne $f -and $f.done) {
                # A fix is believed only when the check then passes: "fixed" is never a guess.
                $again = & $c.check $ctx
                if ($again.done) { [void]$lines.Add((New-HordeSetupLine $step.id $step.title "fixed" $f.said "" $again.notes)); continue }
                $r = New-HordeSetupResult $false ($f.said + "; and yet: " + $again.said) $again.notes $again.next
            } elseif ($null -ne $f) { $r = New-HordeSetupResult $false ($r.said + "; setup tried: " + $f.said) $r.notes $r.next }
        }
        $next = $(if ($r.next -ne "") { $r.next } else { Expand-HordeSetupText -Text $step.manual -Ctx $ctx })
        [void]$lines.Add((New-HordeSetupLine $step.id $step.title "todo" $r.said $next $r.notes))
        return (& $finish)
    }
    return (& $finish)
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
