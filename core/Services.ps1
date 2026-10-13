# core/Services - long-lived pieces of Horde kept running and kept current: what a service IS, as
# data, and the one function that decides what to do about it. No clock, no file and no process is
# read here; everything this file decides by is handed to it.
#
# WHY THIS EXISTS. Three long-lived pieces on the founder's machine - the relay runner, the decisions
# window, the fleet's throttle - were started and updated by hand with a script kept outside the
# repository, and when one died nobody noticed until its absence was felt. Horde is relied on daily, so
# "is it running, and is it the current code" must not depend on someone remembering to look.
#
# A SERVICE IS DATA (Read-HordeServiceDefinitionsText). One entry per service in
# <HORDE_HOME>\settings\service-definitions.json, in the envelope every settings file has
# (schema/module-settings.v1: { schemaVersion; settings }), settings holding one object per service
# under its name:
#   enabled         true or false; false means "leave it exactly as it is" (default true).
#   checkout        the folder it runs from; when it follows a revision, the checkout that is moved.
#   hordeHome       the Horde home it serves (a horde command's HORDE_HOME, and where its heartbeat is).
#   start           { kind: "horde"; words; named; switches }  a horde command of that checkout, or
#                   { kind: "program"; program; arguments }    any program, for a service that is not
#                                                              a horde command.
#   stop            { kind: "horde"; words; named; switches; waitSeconds }  a horde command that asks, or
#                   { kind: "window"; report; waitSeconds }   close its window, named by the report
#                                                             file the window keeps (pid and handle), or
#                   { kind: "kill"; waitSeconds }             it has no way to be asked.
#                   After waitSeconds a service that was asked and is still there is ended.
#   alive           { heartbeat; tickSeconds }  a heartbeat file under hordeHome (core/Heartbeat.ps1)
#                   and the tick to assume when the file names none. Left out: the service writes no
#                   heartbeat, and is alive for as long as the process the supervisor started is.
#   follow          { remote; branch; restart: "any" or "idle"; idleSeconds }  the revision it follows
#                   (default origin, main) and WHEN it may be restarted for an update. Left out: it is
#                   never updated.
#   confirmSeconds  how long a restarted service has to prove itself (a fresh heartbeat of its own;
#                   without a heartbeat, to still be running) before the update is rolled back.
# READ STRICTLY. A member nobody declared, a value of the wrong kind, a path that is not absolute, a
# word that could be read as a flag, and any text that looks like a credential (core/Secrets.ps1) each
# refuse the WHOLE file, with every problem named: a supervisor acting on half a file would be
# starting and stopping things on settings nobody chose. No definition may carry a secret, because a
# definition is copied into command lines, the journal and status.
#
# THE DECISION IS PURE AND LEVEL-TRIGGERED (Get-HordeServiceDecision). It takes the definition, the
# state the supervisor kept, and what was observed THIS pass, and answers exactly one action:
#   nothing | start | restart-for-update | roll-back | wait
# with the step to take now, a short code and a sentence for why, and the troubles that warrant
# telling someone. It never relies on having seen an event: a pass that was killed half way, a machine
# that slept, a process that died between two looks - the next pass reads the state as it IS and
# heals it. An UNKNOWN is never read as "none" (core/Tristate.ps1): liveness that cannot be told is a
# wait, never a start (two copies), and idleness that cannot be told is a wait, never a restart.
#
# ESCALATION IS BESIDE THE ACTION, NOT ONE OF THE ACTIONS. The design this was built to named a fifth
# outcome, "escalate"; but a service that keeps failing must be told about AND tried again slowly, and
# a dirty checkout must be told about AND left alone, so "tell someone" is carried next to whichever
# action is taken (notify: escalate, or recovered), once per trouble: a trouble already told is not
# told again while it lasts, and one "recovered" is said when the service is running, stable and has
# no trouble left.
#
# NEVER A RESTART LOOP. A start that does not last stableSeconds counts as a failure; each failure in
# a row doubles the wait before the next start, up to a cap; after failuresBeforeEscalation of them
# someone is told once, and the starts go on at the capped pace. One start that lasts resets it.
#
# UPDATES ARE STEPS, EACH SAFE TO BE KILLED AFTER. verify (the new revision is checked in a scratch
# copy while the old one runs) -> stop -> advance (the checkout moves) -> start -> confirming. A
# restarted service that does not prove itself in confirmSeconds is rolled back: stop -> retreat (the
# checkout goes back) -> start, the bad revision is pinned - not tried again until a newer one exists -
# and someone is told. The phase is kept in the state file, so a pass that ends between two steps is
# picked up at the next one by the next pass.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Home.ps1")
. (Join-Path $PSScriptRoot "Schema.ps1")
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "ModuleSettings.ps1")
. (Join-Path $PSScriptRoot "Secrets.ps1")
. (Join-Path $PSScriptRoot "Heartbeat.ps1")

# THE SUPERVISOR'S OWN SETTINGS (<HORDE_HOME>\settings\services.json, core/ModuleSettings.ps1). They
# say how the supervisor behaves towards every service; what a service is, is the definitions file's.
$script:HordeServiceSettings = New-HordeModuleSettings -Module "services" -Settings @(
    # A pass runs every minute and must be cheap when all is well: the remote is asked every five
    # minutes, not every pass (the design's default).
    @{ name = "fetchIntervalSeconds"; kind = "whole"; default = 300; min = 30; max = 86400
       what = "How often, in seconds, a followed remote is asked for its newest revision." },
    @{ name = "startBackoffSeconds"; kind = "whole"; default = 30; min = 1; max = 3600
       what = "The wait, in seconds, before starting again after the first start that did not last." },
    @{ name = "startBackoffMaxSeconds"; kind = "whole"; default = 1800; min = 1; max = 86400
       what = "The longest wait, in seconds, between starts of a service that keeps failing." },
    @{ name = "failuresBeforeEscalation"; kind = "whole"; default = 3; min = 1; max = 100
       what = "How many starts in a row may fail to last before someone is told." },
    @{ name = "stableSeconds"; kind = "whole"; default = 300; min = 1; max = 86400
       what = "How long, in seconds, a started service must stay up before its failures are forgotten." },
    @{ name = "retryRefusedMinutes"; kind = "whole"; default = 30; min = 1; max = 1440
       what = "How long, in minutes, before an update that failed its check or could not be applied is tried again." },
    # A pass is stopped by the scheduler at one minute; 40 s leaves the last step room to finish.
    @{ name = "passBudgetSeconds"; kind = "whole"; default = 40; min = 5; max = 55
       what = "How long, in seconds, one pass may go on taking further steps before it leaves the rest to the next." },
    @{ name = "checkSeconds"; kind = "whole"; default = 30; min = 5; max = 600
       what = "How long, in seconds, the self-check of a new revision may take before it is counted as failed." },
    @{ name = "gitSeconds"; kind = "whole"; default = 20; min = 2; max = 300
       what = "How long, in seconds, one call of the revision tool may take." },
    # ON BY DEFAULT: a trouble nobody is told of is the failure this module exists to end. A suite
    # that runs the real command sets it false in the home it made, so no test can post to a session.
    @{ name = "tellWarchief"; kind = "truefalse"; default = $true
       what = "Whether troubles, and recoveries from them, are told to the warchief's session through a messenger." },
    @{ name = "fromLabel"; kind = "label"; default = "SV"
       what = "The hub label a notice from the supervisor wears, so a messenger can say who it is from." }
)

$script:HordeServiceNamePattern = '\A[a-z][a-z0-9-]{0,39}\z'
# A word of a horde command line: a command, a verb or a plain value. It never starts with a dash, so
# no word can be read as a flag (core/Schedule.ps1 measured what an argument starting with "-" does).
$script:HordeServiceWordPattern = '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z'
# The characters the shell reads as the dash that begins a parameter: the hyphen, U+2010 to U+2015 and
# the minus sign U+2212 (core/Schedule.ps1, from the review of #70).
$script:HordeServiceDashes = @([char]0x2D, [char]0x2010, [char]0x2011, [char]0x2012, [char]0x2013, [char]0x2014, [char]0x2015, [char]0x2212)
$script:HordeServiceParameterPattern = '\A[A-Za-z][A-Za-z0-9]{0,39}\z'
$script:HordeServiceRemotePattern = '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z'
$script:HordeServiceBranchPattern = '\A[A-Za-z0-9][A-Za-z0-9._/-]{0,127}\z'
# A heartbeat's place under the home it serves: plain names joined by one separator. Every name
# starts with a letter, a digit or an underscore, so the place can neither be rooted (no drive, no
# leading slash) nor climb out ("." and ".." are not names here).
$script:HordeServiceRelativePattern = '\A[A-Za-z0-9_][A-Za-z0-9._-]{0,63}([\\/][A-Za-z0-9_][A-Za-z0-9._-]{0,63}){0,7}\z'
$script:HordeServiceRevisionPattern = '\A[0-9a-f]{40}\z'
$script:HordeServiceTextCap = 1024
$script:HordeServiceMost = 32
$script:HordeServiceDefinitionsFile = "service-definitions.json"
$script:HordeServiceActions = @("nothing", "start", "restart-for-update", "roll-back", "wait")
$script:HordeServiceSteps = @("", "start", "stop", "kill", "verify", "advance", "retreat")
$script:HordeServicePhases = @("steady", "stopping", "launching", "confirming")
# How many troubles are remembered as told, and how many notices may wait untold: a state file is
# bounded like every other file Horde writes.
$script:HordeServiceToldMost = 8
$script:HordeServiceNoticesMost = 10

function Get-HordeServiceSettingsDeclaration { return $script:HordeServiceSettings }

function Get-HordeServiceSettings {
    # The supervisor's settings as they are now: { state; values; findings; path }.
    param([string]$HordeHome = "")
    return (Get-HordeModuleSettings -Declaration $script:HordeServiceSettings -HordeHome $HordeHome)
}

function Get-HordeServiceDefinitionsPath {
    param([string]$HordeHome = "")
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    return [System.IO.Path]::Combine($HordeHome, "settings", $script:HordeServiceDefinitionsFile)
}

function Test-HordeServiceText {
    # Is this a text a definition may hold: a string, on one line, with no control character, within
    # the cap, and matching -Pattern when one is given?
    param($Value, [string]$Pattern = "")
    if ($Value -isnot [string] -or $Value.Length -eq 0 -or $Value.Length -gt $script:HordeServiceTextCap) { return $false }
    if ($Value -match '\p{Cc}') { return $false }
    if ($Pattern -ne "" -and $Value -cnotmatch $Pattern) { return $false }
    return $true
}

function Get-HordeServiceWhole {
    # A whole number member within -Min..-Max, or -Default when the member is not there: { ok; value }.
    param($Have, [string]$Name, [int]$Default, [int]$Min, [int]$Max)
    if (-not $Have.ContainsKey($Name)) { return [pscustomobject]@{ ok = $true; value = $Default } }
    $v = $Have[$Name]
    if (($v -isnot [int] -and $v -isnot [long]) -or $v -lt $Min -or $v -gt $Max) { return [pscustomobject]@{ ok = $false; value = $Default } }
    return [pscustomobject]@{ ok = $true; value = [int]$v }
}

function Test-HordeServiceObject {
    param($Value)
    return ($Value -is [System.Management.Automation.PSCustomObject])
}

function Add-HordeServiceUnknownMembers {
    # One finding for every member of -Have that -Allowed does not name, compared exactly.
    param($Have, [string[]]$Allowed, [string]$Where, $Findings)
    foreach ($k in @($Have.Keys)) {
        if ($Allowed -cnotcontains $k) { [void]$Findings.Add($Where + " has the member '" + (ConvertTo-HordeModuleSettingsPlain -Text $k -Max 60) + "', which is not one of: " + ($Allowed -join ", ")) }
    }
}

function Read-HordeServiceCommandWords {
    # The words, named values and switches of a horde command, from a start or stop object's members:
    # { words; named; switches }. Findings are added to -Findings.
    param($Have, [string]$Where, $Findings)
    $words = @()
    if (-not $Have.ContainsKey("words") -or $Have["words"] -isnot [array] -or @($Have["words"]).Count -lt 1 -or @($Have["words"]).Count -gt 8) { [void]$Findings.Add($Where + ".words must be a list of 1 to 8 words: the horde command and what follows it") }
    else {
        foreach ($w in @($Have["words"])) {
            if (-not (Test-HordeServiceText -Value $w -Pattern $script:HordeServiceWordPattern)) { [void]$Findings.Add($Where + ".words holds something that is not a plain word (letters, digits, dot, underscore and hyphen, never starting with a hyphen)"); continue }
            $words += [string]$w
        }
    }
    $named = [ordered]@{}
    if ($Have.ContainsKey("named")) {
        if (-not (Test-HordeServiceObject $Have["named"])) { [void]$Findings.Add($Where + ".named must be an object of parameter name to value") }
        else {
            $given = Get-HordeObjectByKey $Have["named"]
            foreach ($k in @($given.Keys)) {
                if ($k -cnotmatch $script:HordeServiceParameterPattern) { [void]$Findings.Add($Where + ".named has a name that is not a parameter name (letters and digits, starting with a letter)"); continue }
                $v = $given[$k]
                if ($v -is [int] -or $v -is [long]) { $named[$k] = "" + $v; continue }
                # A value that starts with a dash is read as a parameter by the shell that runs the
                # command (core/Schedule.ps1 refuses it for the same reason, with the look-alike dashes).
                if (-not (Test-HordeServiceText -Value $v) -or $script:HordeServiceDashes -contains ([string]$v)[0]) { [void]$Findings.Add($Where + ".named." + $k + " must be a text on one line that does not start with a dash, at most " + $script:HordeServiceTextCap + " characters, or a whole number"); continue }
                $named[$k] = [string]$v
            }
        }
    }
    $switches = @()
    if ($Have.ContainsKey("switches")) {
        if ($Have["switches"] -isnot [array]) { [void]$Findings.Add($Where + ".switches must be a list of parameter names") }
        else {
            foreach ($w in @($Have["switches"])) {
                if (-not (Test-HordeServiceText -Value $w -Pattern $script:HordeServiceParameterPattern)) { [void]$Findings.Add($Where + ".switches holds something that is not a parameter name"); continue }
                $switches += [string]$w
            }
        }
    }
    return [pscustomobject]@{ words = [string[]]$words; named = $named; switches = [string[]]$switches }
}

function Find-HordeServiceSecret {
    # A finding for every text in a parsed definition that looks like a credential, said by its kind
    # and its place and NEVER by its value. Walks objects and lists to any depth.
    param($Value, [string]$Where, $Findings)
    if ($Value -is [string]) {
        $kind = Find-HordeSecretKind -Text $Value
        if ($kind -ne "") { [void]$Findings.Add($Where + " holds what looks like " + $kind + "; a service definition never carries a secret") }
        return
    }
    if ($Value -is [array]) { $i = 0; foreach ($item in $Value) { Find-HordeServiceSecret -Value $item -Where ($Where + "[" + $i + "]") -Findings $Findings; $i++ }; return }
    if (Test-HordeServiceObject $Value) {
        $have = Get-HordeObjectByKey $Value
        foreach ($k in @($have.Keys)) { Find-HordeServiceSecret -Value $have[$k] -Where ($Where + "." + (ConvertTo-HordeModuleSettingsPlain -Text $k -Max 60)) -Findings $Findings }
    }
}

function ConvertTo-HordeServiceDefinition {
    # One service's definition from its parsed object: { definition; findings }. definition is $null
    # when there is any finding. The header says what each member is.
    param([Parameter(Mandatory = $true)][string]$Name, $Value)
    $found = New-Object System.Collections.ArrayList
    $at = "service '" + $Name + "'"
    if (-not (Test-HordeServiceObject $Value)) { return [pscustomobject]@{ definition = $null; findings = @($at + " must be an object") } }
    Find-HordeServiceSecret -Value $Value -Where $at -Findings $found
    $have = Get-HordeObjectByKey $Value
    Add-HordeServiceUnknownMembers -Have $have -Allowed @("enabled", "checkout", "hordeHome", "start", "stop", "alive", "follow", "confirmSeconds") -Where $at -Findings $found

    $enabled = $true
    if ($have.ContainsKey("enabled")) { if ($have["enabled"] -is [bool]) { $enabled = [bool]$have["enabled"] } else { [void]$found.Add($at + ".enabled must be true or false") } }
    $checkout = ""
    if ($have.ContainsKey("checkout")) { if ((Test-HordeServiceText -Value $have["checkout"]) -and (Test-HordeModuleSettingFolder -Path $have["checkout"])) { $checkout = [string]$have["checkout"] } else { [void]$found.Add($at + ".checkout must be an absolute folder") } }
    $servedHome = ""
    if ($have.ContainsKey("hordeHome")) { if ((Test-HordeServiceText -Value $have["hordeHome"]) -and (Test-HordeModuleSettingFolder -Path $have["hordeHome"])) { $servedHome = [string]$have["hordeHome"] } else { [void]$found.Add($at + ".hordeHome must be an absolute folder") } }

    # start
    $start = $null
    if (-not $have.ContainsKey("start") -or -not (Test-HordeServiceObject $have["start"])) { [void]$found.Add($at + ".start is missing: an object saying how it is started") }
    else {
        $sh = Get-HordeObjectByKey $have["start"]
        $kind = "" + $sh["kind"]
        if ($sh["kind"] -isnot [string] -or @("horde", "program") -cnotcontains $kind) { [void]$found.Add($at + ".start.kind must be horde or program") }
        elseif ($kind -ceq "horde") {
            Add-HordeServiceUnknownMembers -Have $sh -Allowed @("kind", "words", "named", "switches") -Where ($at + ".start") -Findings $found
            $cmd = Read-HordeServiceCommandWords -Have $sh -Where ($at + ".start") -Findings $found
            if ($checkout -eq "") { [void]$found.Add($at + ".checkout is needed: a horde command runs from a checkout") }
            if ($servedHome -eq "") { [void]$found.Add($at + ".hordeHome is needed: a horde command serves a Horde home") }
            $start = [pscustomobject]@{ kind = "horde"; words = $cmd.words; named = $cmd.named; switches = $cmd.switches; program = ""; arguments = [string[]]@() }
        } else {
            Add-HordeServiceUnknownMembers -Have $sh -Allowed @("kind", "program", "arguments") -Where ($at + ".start") -Findings $found
            $program = ""
            if ((Test-HordeServiceText -Value $sh["program"]) -and (Test-HordeModuleSettingFolder -Path $sh["program"])) { $program = [string]$sh["program"] } else { [void]$found.Add($at + ".start.program must be the absolute path of a program") }
            $arguments = @()
            if ($sh.ContainsKey("arguments")) {
                if ($sh["arguments"] -isnot [array] -or @($sh["arguments"]).Count -gt 32) { [void]$found.Add($at + ".start.arguments must be a list of at most 32 texts") }
                else { foreach ($a in @($sh["arguments"])) { if (Test-HordeServiceText -Value $a) { $arguments += [string]$a } else { [void]$found.Add($at + ".start.arguments holds something that is not a text on one line") } } }
            }
            $start = [pscustomobject]@{ kind = "program"; words = [string[]]@(); named = [ordered]@{}; switches = [string[]]@(); program = $program; arguments = [string[]]$arguments }
        }
    }

    # stop
    $stop = $null
    if (-not $have.ContainsKey("stop") -or -not (Test-HordeServiceObject $have["stop"])) { [void]$found.Add($at + ".stop is missing: an object saying how it is asked to stop (kind horde, window or kill)") }
    else {
        $th = Get-HordeObjectByKey $have["stop"]
        $kind = "" + $th["kind"]
        $wait = Get-HordeServiceWhole -Have $th -Name "waitSeconds" -Default 30 -Min 1 -Max 600
        if (-not $wait.ok) { [void]$found.Add($at + ".stop.waitSeconds must be a whole number from 1 to 600") }
        if ($th["kind"] -isnot [string] -or @("horde", "window", "kill") -cnotcontains $kind) { [void]$found.Add($at + ".stop.kind must be horde, window or kill") }
        elseif ($kind -ceq "horde") {
            Add-HordeServiceUnknownMembers -Have $th -Allowed @("kind", "words", "named", "switches", "waitSeconds") -Where ($at + ".stop") -Findings $found
            $cmd = Read-HordeServiceCommandWords -Have $th -Where ($at + ".stop") -Findings $found
            if ($checkout -eq "" -or $servedHome -eq "") { [void]$found.Add($at + ".stop of kind horde needs checkout and hordeHome") }
            $stop = [pscustomobject]@{ kind = "horde"; words = $cmd.words; named = $cmd.named; switches = $cmd.switches; report = ""; waitSeconds = $wait.value }
        } elseif ($kind -ceq "window") {
            Add-HordeServiceUnknownMembers -Have $th -Allowed @("kind", "report", "waitSeconds") -Where ($at + ".stop") -Findings $found
            $report = ""
            if ((Test-HordeServiceText -Value $th["report"]) -and (Test-HordeModuleSettingFolder -Path $th["report"])) { $report = [string]$th["report"] } else { [void]$found.Add($at + ".stop.report must be the absolute path of the report file its window keeps") }
            $stop = [pscustomobject]@{ kind = "window"; words = [string[]]@(); named = [ordered]@{}; switches = [string[]]@(); report = $report; waitSeconds = $wait.value }
        } else {
            Add-HordeServiceUnknownMembers -Have $th -Allowed @("kind", "waitSeconds") -Where ($at + ".stop") -Findings $found
            $stop = [pscustomobject]@{ kind = "kill"; words = [string[]]@(); named = [ordered]@{}; switches = [string[]]@(); report = ""; waitSeconds = $wait.value }
        }
    }

    # alive
    $alive = $null
    if ($have.ContainsKey("alive")) {
        if (-not (Test-HordeServiceObject $have["alive"])) { [void]$found.Add($at + ".alive must be an object: { heartbeat; tickSeconds }") }
        else {
            $ah = Get-HordeObjectByKey $have["alive"]
            Add-HordeServiceUnknownMembers -Have $ah -Allowed @("heartbeat", "tickSeconds") -Where ($at + ".alive") -Findings $found
            $tick = Get-HordeServiceWhole -Have $ah -Name "tickSeconds" -Default 60 -Min 1 -Max 3600
            if (-not $tick.ok) { [void]$found.Add($at + ".alive.tickSeconds must be a whole number from 1 to 3600") }
            $relative = ""
            if (Test-HordeServiceText -Value $ah["heartbeat"] -Pattern $script:HordeServiceRelativePattern) { $relative = [string]$ah["heartbeat"] }
            else { [void]$found.Add($at + ".alive.heartbeat must be a file's place under hordeHome: plain names joined by a slash, never rooted and never '..'") }
            if ($servedHome -eq "") { [void]$found.Add($at + ".hordeHome is needed: its heartbeat is under the home it serves") }
            $path = ""
            if ($relative -ne "" -and $servedHome -ne "") { $path = [System.IO.Path]::Combine($servedHome, $relative) }
            $alive = [pscustomobject]@{ heartbeat = $relative; path = $path; tickSeconds = $tick.value }
        }
    }

    # follow
    $follow = $null
    if ($have.ContainsKey("follow")) {
        if (-not (Test-HordeServiceObject $have["follow"])) { [void]$found.Add($at + ".follow must be an object: { remote; branch; restart; idleSeconds }") }
        else {
            $fh = Get-HordeObjectByKey $have["follow"]
            Add-HordeServiceUnknownMembers -Have $fh -Allowed @("remote", "branch", "restart", "idleSeconds") -Where ($at + ".follow") -Findings $found
            $remote = "origin"
            if ($fh.ContainsKey("remote")) { if (Test-HordeServiceText -Value $fh["remote"] -Pattern $script:HordeServiceRemotePattern) { $remote = [string]$fh["remote"] } else { [void]$found.Add($at + ".follow.remote must be the plain name of a remote of the checkout") } }
            $branch = "main"
            if ($fh.ContainsKey("branch")) {
                $b = $fh["branch"]
                if ((Test-HordeServiceText -Value $b -Pattern $script:HordeServiceBranchPattern) -and $b -notmatch '\.\.' -and $b -notmatch '//' -and $b -notmatch '(/|\.lock|\.)\z') { $branch = [string]$b } else { [void]$found.Add($at + ".follow.branch must be the plain name of a branch") }
            }
            $restart = "idle"
            if ($fh.ContainsKey("restart")) { if ($fh["restart"] -is [string] -and @("any", "idle") -ccontains $fh["restart"]) { $restart = [string]$fh["restart"] } else { [void]$found.Add($at + ".follow.restart must be any or idle") } }
            $idle = Get-HordeServiceWhole -Have $fh -Name "idleSeconds" -Default 300 -Min 1 -Max 86400
            if (-not $idle.ok) { [void]$found.Add($at + ".follow.idleSeconds must be a whole number from 1 to 86400") }
            if ($checkout -eq "") { [void]$found.Add($at + ".checkout is needed: a service that follows a revision has a checkout to move") }
            $follow = [pscustomobject]@{ remote = $remote; branch = $branch; restart = $restart; idleSeconds = $idle.value }
        }
    }

    $confirm = Get-HordeServiceWhole -Have $have -Name "confirmSeconds" -Default 120 -Min 10 -Max 3600
    if (-not $confirm.ok) { [void]$found.Add($at + ".confirmSeconds must be a whole number from 10 to 3600") }

    if ($found.Count -gt 0) { return [pscustomobject]@{ definition = $null; findings = @($found.ToArray()) } }
    $definition = [pscustomobject]@{ PSTypeName = "Horde.ServiceDefinition"; name = $Name; enabled = $enabled; checkout = $checkout; hordeHome = $servedHome; start = $start; stop = $stop; alive = $alive; follow = $follow; confirmSeconds = $confirm.value }
    return [pscustomobject]@{ definition = $definition; findings = @() }
}

function Read-HordeServiceDefinitionsText {
    # PURE given the file's text: { state; services; findings; path }. state is "none" (no file: no
    # service is defined, which is not an error), "read" (every service passed) or "refused" (any
    # finding; services is then EMPTY, so a caller that forgets to look at state supervises nothing
    # rather than half). -Text is $null when there is no file.
    param([AllowNull()]$Text, [string]$File = "")
    $called = $File
    if ($called -eq "") { $called = [System.IO.Path]::Combine("settings", $script:HordeServiceDefinitionsFile) }
    $answer = { param([string]$State, $Services, $Findings) return [pscustomobject]@{ state = $State; services = @($Services); findings = [string[]]@($Findings); path = $called } }
    if ($null -eq $Text) { return (& $answer "none" @() @()) }
    if ($Text -isnot [string]) { throw "-Text is the file's text, or `$null when there is no file" }
    $body = $Text
    if ($body.Length -gt 0 -and [int]$body[0] -eq 0xFEFF) { $body = $body.Substring(1) }
    $refuse = { param($Problems) return (& $answer "refused" @() @($Problems | ForEach-Object { "the service definitions file '" + $called + "' is refused: " + $_ })) }
    # The envelope and the text checks are the settings module's own (duplicate keys, what JSON is made
    # of, the length, schema/module-settings.v1), so a definitions file is read as strictly as any
    # other settings file and by the same code.
    $doc = Read-HordeModuleSettingsDocument -Text $body
    if (@($doc.problems).Count -gt 0) { return (& $refuse @($doc.problems | ForEach-Object { "it " + (ConvertTo-HordeModuleSettingsPlain -Text $_ -Max 300) })) }
    $given = Get-HordeObjectByKey $doc.settings
    $problems = New-Object System.Collections.ArrayList
    if ($given.Count -gt $script:HordeServiceMost) { [void]$problems.Add("it defines " + $given.Count + " services, more than the " + $script:HordeServiceMost + " one machine's supervisor takes") }
    $services = New-Object System.Collections.ArrayList
    foreach ($name in @($given.Keys)) {
        if ($name -cnotmatch $script:HordeServiceNamePattern) { [void]$problems.Add("'" + (ConvertTo-HordeModuleSettingsPlain -Text $name -Max 60) + "' is not a service name: lower-case letters, digits and hyphens, starting with a letter, at most 40"); continue }
        $made = ConvertTo-HordeServiceDefinition -Name $name -Value $given[$name]
        foreach ($f in @($made.findings)) { [void]$problems.Add($f) }
        if ($null -ne $made.definition) { [void]$services.Add($made.definition) }
    }
    if ($problems.Count -gt 0) { return (& $refuse @($problems.ToArray())) }
    return (& $answer "read" @($services.ToArray()) @())
}

function Get-HordeServiceDefinitions {
    # The definitions under the home: { state; services; findings; path }. READS THAT ONE FILE AND
    # WRITES NOTHING. A file that is there and cannot be read whole - too large, held, not UTF-8 - is
    # refused with the reason, never treated as "no services": a supervisor that read a locked file as
    # empty would conclude there is nothing to keep alive.
    param([string]$HordeHome = "")
    $path = Get-HordeServiceDefinitionsPath -HordeHome $HordeHome
    $text = $null
    $trouble = ""
    $stream = $null
    try {
        $stream = Open-HordeSharedStream -Path $path
        if ($stream.Length -gt 262144) { $trouble = "it is larger than 262144 bytes" }
        else {
            $buffer = New-Object System.IO.MemoryStream
            $stream.CopyTo($buffer)
            try { $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($buffer.ToArray()) } catch { $trouble = "it is not UTF-8 text; save it as UTF-8" }
        }
    } catch {
        $cause = $_.Exception.GetBaseException()
        if (-not ($cause -is [System.IO.FileNotFoundException] -or $cause -is [System.IO.DirectoryNotFoundException])) { $trouble = "it cannot be read (" + $cause.GetType().Name + ")" }
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
    if ($trouble -ne "") { return [pscustomobject]@{ state = "refused"; services = @(); findings = [string[]]@("the service definitions file '" + $path + "' is refused: " + $trouble); path = $path } }
    return (Read-HordeServiceDefinitionsText -Text $text -File $path)
}

# ---------------------------------------------------------------------------------------------------
# THE STATE the supervisor keeps of one service between passes. Times are [datetime] (UTC) here and
# text in the file (core/ServicesFiles.ps1).

function New-HordeServiceState {
    # A service nothing is known of yet.
    #   phase / intent / phaseSince   where an update, a heal or a roll-back has got to (the header)
    #   target / from                 the revision being moved to, and the one moved from
    #   runningRevision               what the running process was started from
    #   previousRevision              what ran before the last update
    #   pinnedRevision                a revision that failed after its restart: not tried again
    #   verifiedRevision              the revision whose self-check passed
    #   refused                       { revision; kind; reason; at }: an update that failed its check
    #                                 (verify), could not be applied (apply) or undone (retreat)
    #   started                       { pid; startedAt; at }: the process that IS the service
    #   proving / failures / nextStartAt   the restart-loop guard (the header)
    #   confirmBy                     until when a restarted service may prove itself
    #   stuck                         why a process that should have ended could not be ended
    #   told                          the troubles someone has been told of and that still stand
    #   notices                       what is still to be told: { id; kind; text; at }
    #   lastAction                    { at; action; step; outcome; reason }
    #   lastFetchAt / fetchProblem    when the remote was last asked, and what went wrong
    #   lastSaid                      the last journal line's key, so a wait is written once
    param([Parameter(Mandatory = $true)][string]$Name)
    return [pscustomobject]@{
        PSTypeName = "Horde.ServiceState"; schemaVersion = 1; name = $Name
        phase = "steady"; intent = ""; phaseSince = $null; target = ""; from = ""
        runningRevision = ""; previousRevision = ""; pinnedRevision = ""; verifiedRevision = ""; refused = $null
        started = $null; proving = $false; failures = 0; nextStartAt = $null; confirmBy = $null; stuck = ""
        told = [string[]]@(); notices = @(); lastAction = $null; lastFetchAt = $null; fetchProblem = ""; lastSaid = ""
    }
}

function Copy-HordeServiceState {
    # A copy that shares nothing with the original, so a decision never changes the state it was
    # handed: the caller persists what the decision returns, or does not.
    param([Parameter(Mandatory = $true)]$State)
    $c = New-HordeServiceState -Name $State.name
    foreach ($n in @("phase", "intent", "phaseSince", "target", "from", "runningRevision", "previousRevision", "pinnedRevision", "verifiedRevision", "proving", "failures", "nextStartAt", "confirmBy", "stuck", "lastFetchAt", "fetchProblem", "lastSaid")) { $c.$n = $State.$n }
    if ($null -ne $State.refused) { $c.refused = [pscustomobject]@{ revision = $State.refused.revision; kind = $State.refused.kind; reason = $State.refused.reason; at = $State.refused.at } }
    if ($null -ne $State.started) { $c.started = [pscustomobject]@{ pid = $State.started.pid; startedAt = $State.started.startedAt; at = $State.started.at } }
    if ($null -ne $State.lastAction) { $c.lastAction = [pscustomobject]@{ at = $State.lastAction.at; action = $State.lastAction.action; step = $State.lastAction.step; outcome = $State.lastAction.outcome; reason = $State.lastAction.reason } }
    $c.told = [string[]]@($State.told)
    $c.notices = @($State.notices | ForEach-Object { [pscustomobject]@{ id = $_.id; kind = $_.kind; text = $_.text; at = $_.at } })
    return $c
}

function Get-HordeServiceBackoffSeconds {
    # The wait before the next start after -Failures starts in a row that did not last: the first
    # wait, doubled for each failure past the first, capped.
    param([Parameter(Mandatory = $true)][int]$Failures, [Parameter(Mandatory = $true)]$Policy)
    if ($Failures -le 0) { return 0 }
    $wait = [double]$Policy.startBackoffSeconds
    for ($i = 1; $i -lt $Failures -and $wait -lt [double]$Policy.startBackoffMaxSeconds; $i++) { $wait = $wait * 2 }
    return [int][System.Math]::Min($wait, [double]$Policy.startBackoffMaxSeconds)
}

function Get-HordeServiceProcessVerdict {
    # PURE. Is the process a claim names still that process? -Claim is { pid; startedAt } (from the
    # state, or from a heartbeat) or $null; -Entry is what the process table says of that pid: known
    # { pid; startedAt }, absent (no process has that pid), or unknown. Answers known { pid; startedAt }
    # when the pid is there AND started when the claim says; absent when the pid is free or belongs to
    # a process that started at another time - A REUSED PID IS NOT THE SERVICE; unknown when the table
    # could not say, or the claim names no start, because then the pid alone would be deciding.
    param($Claim, $Entry)
    if ($null -eq $Claim) { return (New-HordeAbsent -Note "nothing names a process") }
    if ($Claim.startedAt -isnot [datetime]) { return (New-HordeUnknown -Reason ("process " + $Claim.pid + " is named without the time it started, so it cannot be told from another process given the same number")) }
    Assert-HordeAnswer $Entry
    if ($Entry.state -ceq "unknown") { return $Entry }
    if ($Entry.state -ceq "absent") { return (New-HordeAbsent -Note ("process " + $Claim.pid + " is not running")) }
    if ([int]$Entry.value.pid -ne [int]$Claim.pid) { return (New-HordeUnknown -Reason "the process table answered about another process") }
    if (-not (Test-HordeHeartbeatSameStart -One $Entry.value.startedAt -Other $Claim.startedAt)) { return (New-HordeAbsent -Note ("process " + $Claim.pid + " is another process now: its number was given out again")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ pid = [int]$Claim.pid; startedAt = $Claim.startedAt.ToUniversalTime() }))
}

function New-HordeServiceObserved {
    # What one pass saw of one service, in the one shape the decision reads. Every member is a
    # core/Tristate.ps1 answer; a caller that could not look says unknown and why, never nothing.
    #   started      the state's own process (Get-HordeServiceProcessVerdict of state.started)
    #   heartbeat    Read-HordeHeartbeat of the service's heartbeat file; absent when it keeps none
    #   beater       the process its heartbeat names (the same verdict, of the heartbeat's pid and start)
    #   checkout     known { head; detached; clean; branch }
    #   wanted       known { revision; fastForward }; absent when the service follows nothing
    #   idleSeconds  known whole seconds since the person last touched the machine
    param($Started, $Heartbeat, $Beater, $Checkout, $Wanted, $IdleSeconds)
    $o = [ordered]@{ started = $Started; heartbeat = $Heartbeat; beater = $Beater; checkout = $Checkout; wanted = $Wanted; idleSeconds = $IdleSeconds }
    foreach ($k in @($o.Keys)) {
        if ($null -eq $o[$k]) { $o[$k] = New-HordeUnknown -Reason ("nobody looked at " + $k) }
        Assert-HordeAnswer $o[$k]
    }
    return [pscustomobject]$o
}

function Get-HordeServiceLiveness {
    # PURE. Is the service alive at -Now? { alive; why; process; ours; heartbeatAgeSeconds }.
    #   alive    yes       its process is running and (when it keeps a heartbeat) has beaten lately
    #            starting  its process is running, started less than confirmSeconds ago, and has not
    #                      beaten yet
    #            hung      its process is running and its heartbeat is stale: it must be restarted
    #            no        no process is the service
    #            unknown   it cannot be told, and why says what could not be read
    #   process  { pid; startedAt } of the process that IS the service, or $null
    #   ours     whether that process is the one the state records (false: it was found by its
    #            heartbeat, started by someone else, and is adopted)
    # THE PROCESS IS THE ONE THE STATE RECORDS WHEN THAT IS RUNNING, else the one a heartbeat names
    # when THAT is running. A heartbeat proves work only for the process that wrote it: a fresh file
    # left by a process that has gone, or written by another, never makes this one alive.
    param([Parameter(Mandatory = $true)]$Definition, [Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Observed, [Parameter(Mandatory = $true)][datetime]$Now)
    $result = { param([string]$Alive, [string]$Why, $Process, [bool]$Ours, $Age) return [pscustomobject]@{ alive = $Alive; why = $Why; process = $Process; ours = $Ours; heartbeatAgeSeconds = $Age } }
    if ($Observed.started.state -ceq "unknown") { return (& $result "unknown" ("its process could not be checked: " + $Observed.started.reason) $null $false $null) }
    $process = $null
    $ours = $false
    if ($Observed.started.state -ceq "known") { $process = $Observed.started.value; $ours = $true }
    if ($null -eq $Definition.alive) {
        if ($null -ne $process) { return (& $result "yes" ("its process " + $process.pid + " is running") $process $true $null) }
        return (& $result "no" $(if ($null -eq $State.started) { "it is not running: nothing has started it" } else { "its process has ended" }) $null $false $null)
    }
    $beat = $Observed.heartbeat
    if ($beat.state -ceq "unknown") { return (& $result "unknown" ("its heartbeat could not be read: " + $beat.reason) $process $ours $null) }
    $verdict = Get-HordeHeartbeatVerdict -Heartbeat $beat -Now $Now -DefaultTickSeconds $Definition.alive.tickSeconds
    if ($verdict.state -ceq "unknown") { return (& $result "unknown" $verdict.reason $process $ours $null) }
    $age = $null
    if ($verdict.state -ceq "known") { $age = $verdict.value.ageSeconds }
    if ($null -eq $process -and $beat.state -ceq "known") {
        if ($Observed.beater.state -ceq "unknown") { return (& $result "unknown" ("the process that wrote its heartbeat could not be checked: " + $Observed.beater.reason) $null $false $age) }
        if ($Observed.beater.state -ceq "known") { $process = $Observed.beater.value }
    }
    if ($null -eq $process) {
        if ($beat.state -ceq "absent") { return (& $result "no" "it is not running: it has no process and has never written a heartbeat" $null $false $null) }
        return (& $result "no" ("it is not running: the process that wrote its last heartbeat, " + $age + " s ago, has ended") $null $false $age)
    }
    $own = ($beat.state -ceq "known" -and [int]$beat.value.pid -eq [int]$process.pid -and (Test-HordeHeartbeatSameStart -One $beat.value.startedAt -Other $process.startedAt))
    if ($own -and $verdict.value.fresh) { return (& $result "yes" ("its process " + $process.pid + " is running, heartbeat " + $age + " s ago") $process $ours $age) }
    $since = ($Now.ToUniversalTime() - $process.startedAt).TotalSeconds
    if ($since -lt $Definition.confirmSeconds) { return (& $result "starting" ("its process " + $process.pid + " started " + [long][System.Math]::Max(0, $since) + " s ago and has not written a heartbeat of its own yet") $process $ours $age) }
    if ($own) { return (& $result "hung" ("its process " + $process.pid + " is running but its heartbeat is " + $age + " s old (stale after " + $verdict.value.staleAfterSeconds + " s)") $process $ours $age) }
    return (& $result "hung" ("its process " + $process.pid + " is running but has written no heartbeat of its own") $process $ours $age)
}

function ConvertTo-HordeServiceShortRevision {
    param([string]$Revision)
    if ($Revision.Length -ge 9) { return $Revision.Substring(0, 9) }
    return $Revision
}

function New-HordeServiceTrouble {
    # A trouble worth telling someone: { key; text }. The key is what "already told" is remembered by,
    # so it never holds a number that changes from pass to pass.
    param([Parameter(Mandatory = $true)][string]$Key, [Parameter(Mandatory = $true)][string]$Text)
    return [pscustomobject]@{ key = $Key; text = $Text }
}

function Get-HordeServiceFailingTrouble {
    # The trouble of a service that keeps failing to stay up, or $null while it has failed fewer times
    # in a row than the setting failuresBeforeEscalation. One place, because two branches of the
    # decision ask it: a service whose liveness cannot be told this pass is still one that has failed.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Policy)
    if ([int]$State.failures -lt [int]$Policy.failuresBeforeEscalation) { return $null }
    return (New-HordeServiceTrouble -Key "failing" -Text ("it has not stayed up after " + $State.failures + " starts in a row; it is still tried, slowly"))
}

function Get-HordeServiceDecision {
    # PURE. The one decision for one service this pass (the header):
    #   { action; step; code; reason; process; revision; notify; notice; live; state }
    #   action    nothing | start | restart-for-update | roll-back | wait
    #   step      what to do NOW for that action: start, stop, kill, verify, advance or retreat; ""
    #             when there is nothing to do
    #   code      a short fixed word for the reason, which a journal keys a repeated line by
    #   reason    one sentence a person reads
    #   process   { pid; startedAt } a stop or kill acts on; revision what a verify, advance or retreat
    #             is of
    #   notify    "" | "escalate" | "recovered", and notice the sentence to tell
    #   state     the state to keep, whatever is then done: counters settled, phase moved, told updated
    # -IgnoreIdle is `horde rollout -Now`: the person asked, so their being at the machine is not a
    # reason to wait. Nothing else is ever skipped by it.
    param(
        [Parameter(Mandatory = $true)]$Definition,
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Observed,
        [Parameter(Mandatory = $true)][datetime]$Now,
        [Parameter(Mandatory = $true)]$Policy,
        [switch]$IgnoreIdle
    )
    $at = $Now.ToUniversalTime()
    $s = Copy-HordeServiceState -State $State
    $live = Get-HordeServiceLiveness -Definition $Definition -State $s -Observed $Observed -Now $at
    $troubles = New-Object System.Collections.ArrayList
    $name = $Definition.name
    $finish = {
        # Close a decision: settle what is told. A trouble not yet told is told now, once; when none
        # is left and the service is running and stable, one "recovered" is said and the list emptied.
        param([string]$Action, [string]$Step, [string]$Code, [string]$Reason, $Process = $null, [string]$Revision = "", [bool]$Healthy = $false)
        $notify = ""; $notice = ""
        $fresh = @($troubles | Where-Object { @($s.told) -cnotcontains $_.key })
        if ($fresh.Count -gt 0) {
            $notify = "escalate"
            $notice = "service " + $name + ": " + (@($fresh | ForEach-Object { $_.text }) -join "; ")
            $s.told = [string[]]@(@($s.told) + @($fresh | ForEach-Object { $_.key }) | Select-Object -Last $script:HordeServiceToldMost)
        } elseif ($troubles.Count -eq 0 -and @($s.told).Count -gt 0 -and $Healthy) {
            $notify = "recovered"
            $notice = "service " + $name + ": recovered - " + $Reason
            $s.told = [string[]]@()
        }
        return [pscustomobject]@{ action = $Action; step = $Step; code = $Code; reason = $Reason; process = $Process; revision = $Revision; notify = $notify; notice = $notice; live = $live; state = $s }
    }

    if (-not $Definition.enabled) { return (& $finish "nothing" "" "disabled" "not supervised: its definition says enabled is false") }

    # A roll-back that could not be done stands as a trouble whatever else is true, for as long as the
    # checkout is still on the revision it could not leave. Once a person has moved it, it is over.
    if ($null -ne $s.refused -and $s.refused.kind -ceq "retreat" -and $Observed.checkout.state -ceq "known" -and ("" + $Observed.checkout.value.head) -cne $s.refused.revision) { $s.refused = $null }
    if ($null -ne $s.refused -and $s.refused.kind -ceq "retreat") { [void]$troubles.Add((New-HordeServiceTrouble -Key ("retreat:" + $s.refused.revision) -Text ("its roll-back from " + (ConvertTo-HordeServiceShortRevision $s.refused.revision) + " could not be done (" + $s.refused.reason + "); its checkout needs a person"))) }

    $by = @{ update = "restart-for-update"; rollback = "roll-back"; heal = "start" }

    # ---- stopping: something asked it to stop; wait for the process to go, then end it -------------
    if ($s.phase -ceq "stopping") {
        if ($live.alive -ceq "unknown") { return (& $finish "wait" "" "cannot-tell" ("stopping it, and " + $live.why)) }
        if ($live.alive -cne "no") {
            # A state that does not say when the stop was asked is read as "long ago": the wait is over.
            $asked = [double]$Definition.stop.waitSeconds
            if ($s.phaseSince -is [datetime]) { $asked = ($at - $s.phaseSince).TotalSeconds }
            if ($s.stuck -ne "") { [void]$troubles.Add((New-HordeServiceTrouble -Key "stuck" -Text ("its process " + $live.process.pid + " could not be ended (" + $s.stuck + ")"))) }
            if ($asked -lt $Definition.stop.waitSeconds) { return (& $finish "wait" "" "stopping" ("asked to stop " + [long]$asked + " s ago; it has " + $Definition.stop.waitSeconds + " s")) }
            return (& $finish $by[$s.intent] "kill" "stop-overdue" ("it was asked to stop " + [long]$asked + " s ago and is still running, so it is ended") $live.process)
        }
        $s.started = $null; $s.stuck = ""
        if ($s.intent -ceq "update") { return (& $finish "restart-for-update" "advance" "advance" ("it has stopped; its checkout moves to " + (ConvertTo-HordeServiceShortRevision $s.target)) $null $s.target) }
        if ($s.intent -ceq "rollback") {
            [void]$troubles.Add((New-HordeServiceTrouble -Key ("rolled-back:" + $s.target) -Text ("revision " + (ConvertTo-HordeServiceShortRevision $s.target) + " did not prove itself after its restart and is rolled back to " + (ConvertTo-HordeServiceShortRevision $s.from) + "; it is not tried again until a newer one exists")))
            return (& $finish "roll-back" "retreat" "retreat" ("it has stopped; its checkout goes back to " + (ConvertTo-HordeServiceShortRevision $s.from)) $null $s.from)
        }
        # heal: it is gone, and the ordinary rules for a service that is not running take over.
        $s.phase = "steady"; $s.intent = ""; $s.phaseSince = $null
        $live = Get-HordeServiceLiveness -Definition $Definition -State $s -Observed (New-HordeServiceObserved -Started (New-HordeAbsent -Note "it was stopped") -Heartbeat $Observed.heartbeat -Beater (New-HordeAbsent -Note "it was stopped") -Checkout $Observed.checkout -Wanted $Observed.wanted -IdleSeconds $Observed.idleSeconds) -Now $at
    }

    # ---- launching: the checkout has moved (forward or back); start what is there -------------------
    if ($s.phase -ceq "launching") {
        if ($s.intent -ceq "rollback") {
            [void]$troubles.Add((New-HordeServiceTrouble -Key ("rolled-back:" + $s.target) -Text ("revision " + (ConvertTo-HordeServiceShortRevision $s.target) + " did not prove itself after its restart and is rolled back to " + (ConvertTo-HordeServiceShortRevision $s.from) + "; it is not tried again until a newer one exists")))
            return (& $finish "roll-back" "start" "start-previous" ("starting the previous revision " + (ConvertTo-HordeServiceShortRevision $s.from)) $null $s.from)
        }
        return (& $finish "restart-for-update" "start" "start-new" ("starting the new revision " + (ConvertTo-HordeServiceShortRevision $s.target)) $null $s.target)
    }

    # ---- confirming: the new revision was started; it proves itself or is rolled back ---------------
    if ($s.phase -ceq "confirming") {
        if ($live.alive -ceq "unknown") { return (& $finish "wait" "" "cannot-tell" ("confirming the new revision, and " + $live.why)) }
        $left = 0
        if ($s.confirmBy -is [datetime]) { $left = [long]($s.confirmBy - $at).TotalSeconds }
        $rollback = ""
        if ($live.alive -ceq "yes") {
            # A service with a heartbeat has proven itself by beating. One without can only prove it
            # stays up, so it is confirmed when its time has passed and it is still there.
            if ($null -ne $Definition.alive -or $left -le 0) {
                $was = $s.from
                $s.phase = "steady"; $s.intent = ""; $s.phaseSince = $null; $s.confirmBy = $null
                $s.runningRevision = $s.target; $s.previousRevision = $was; $s.refused = $null
                $s.proving = $true; $s.failures = 0; $s.nextStartAt = $null
                return (& $finish "nothing" "" "updated" ("updated to " + (ConvertTo-HordeServiceShortRevision $s.target) + " (was " + (ConvertTo-HordeServiceShortRevision $was) + ") and running") $null $s.target $true)
            }
            return (& $finish "wait" "" "confirming" ("the new revision is running; it is confirmed if it still is in " + $left + " s"))
        }
        if ($live.alive -ceq "no") { $rollback = "the new revision's process ended before it proved itself" }
        elseif ($left -le 0) { $rollback = "the new revision gave no fresh heartbeat within " + $Definition.confirmSeconds + " s of its restart" }
        if ($rollback -eq "") { return (& $finish "wait" "" "confirming" ("waiting for the new revision's first heartbeat; " + $left + " s left")) }
        $s.phase = "stopping"; $s.intent = "rollback"; $s.phaseSince = $at; $s.confirmBy = $null
        [void]$troubles.Add((New-HordeServiceTrouble -Key ("rolled-back:" + $s.target) -Text ("revision " + (ConvertTo-HordeServiceShortRevision $s.target) + " did not prove itself after its restart (" + $rollback + ") and is rolled back to " + (ConvertTo-HordeServiceShortRevision $s.from) + "; it is not tried again until a newer one exists")))
        if ($live.alive -ceq "no") { $s.started = $null; return (& $finish "roll-back" "retreat" "retreat" ($rollback + "; its checkout goes back to " + (ConvertTo-HordeServiceShortRevision $s.from)) $null $s.from) }
        return (& $finish "roll-back" "stop" "roll-back" ($rollback + "; it is stopped and rolled back") $live.process)
    }

    # ---- steady ------------------------------------------------------------------------------------
    if ($live.alive -ceq "unknown") {
        $failing = Get-HordeServiceFailingTrouble -State $s -Policy $Policy; if ($null -ne $failing) { [void]$troubles.Add($failing) }
        return (& $finish "wait" "" "cannot-tell" ("nothing is done: " + $live.why))
    }
    # Settle the restart-loop guard from what is seen.
    if ($live.alive -ceq "no" -and $null -ne $s.started) {
        if ($s.proving) { $s.failures = [int]$s.failures + 1; $s.nextStartAt = $at.AddSeconds((Get-HordeServiceBackoffSeconds -Failures $s.failures -Policy $Policy)) }
        $s.started = $null; $s.proving = $false
    }
    if ($live.alive -ceq "yes") {
        if (-not $live.ours) { $s.started = [pscustomobject]@{ pid = [int]$live.process.pid; startedAt = $live.process.startedAt; at = $live.process.startedAt }; $s.proving = $false }
        if ($s.proving -and ($null -eq $s.started -or ($at - $s.started.at).TotalSeconds -ge $Policy.stableSeconds)) { $s.proving = $false; $s.failures = 0; $s.nextStartAt = $null }
        if (-not $s.proving -and $s.failures -ne 0) { $s.failures = 0; $s.nextStartAt = $null }
    }
    $failing = Get-HordeServiceFailingTrouble -State $s -Policy $Policy; if ($null -ne $failing) { [void]$troubles.Add($failing) }

    if ($live.alive -ceq "starting") { return (& $finish "wait" "" "starting" $live.why) }
    if ($live.alive -ceq "hung") {
        if ($s.proving) { $s.failures = [int]$s.failures + 1; $s.nextStartAt = $at.AddSeconds((Get-HordeServiceBackoffSeconds -Failures $s.failures -Policy $Policy)); $s.proving = $false }
        $s.phase = "stopping"; $s.intent = "heal"; $s.phaseSince = $at
        return (& $finish "start" "stop" "hung" ($live.why + "; it is stopped and started again") $live.process)
    }
    if ($live.alive -ceq "no") {
        if ($s.nextStartAt -is [datetime] -and $at -lt $s.nextStartAt) {
            return (& $finish "wait" "" "backing-off" ($live.why + "; backing off after " + $s.failures + " start(s) in a row that did not last: the next start is in " + [long]($s.nextStartAt - $at).TotalSeconds + " s"))
        }
        return (& $finish "start" "start" "start" ($live.why + $(if ($s.failures -gt 0) { "; start " + ([int]$s.failures + 1) + " in a row" } else { "" })))
    }

    # Alive. Is it the revision it should be?
    $stable = (-not $s.proving)
    if ($null -eq $Definition.follow) { return (& $finish "nothing" "" "running" $live.why $null "" $stable) }
    if ($Observed.checkout.state -cne "known") { return (& $finish "nothing" "" "running" ($live.why + "; its checkout could not be read (" + $Observed.checkout.reason + "), so no update is considered") $null "" $false) }
    $head = "" + $Observed.checkout.value.head
    if ($s.runningRevision -eq "") { $s.runningRevision = $head }
    if ($Observed.wanted.state -cne "known") { return (& $finish "nothing" "" "running" ($live.why + "; what " + $Definition.follow.remote + "/" + $Definition.follow.branch + " wants is not known (" + $Observed.wanted.reason + ")") $null "" $false) }
    $wanted = "" + $Observed.wanted.value.revision
    $short = ConvertTo-HordeServiceShortRevision $wanted
    if ($wanted -ceq $head -and $wanted -ceq $s.runningRevision) {
        if ($null -ne $s.refused -and $s.refused.kind -cne "retreat") { $s.refused = $null }
        return (& $finish "nothing" "" "current" ($live.why + ", on " + $short + ", which is what " + $Definition.follow.remote + "/" + $Definition.follow.branch + " wants") $null "" $stable)
    }
    if ($wanted -ceq $s.pinnedRevision) {
        [void]$troubles.Add((New-HordeServiceTrouble -Key ("rolled-back:" + $wanted) -Text ("revision " + $short + " did not prove itself after its restart and was rolled back; it is not tried again until a newer one exists")))
        return (& $finish "wait" "" "pinned" ("update not taken: " + $short + " failed after its restart and was rolled back; waiting for a newer revision"))
    }
    if (-not $Observed.checkout.value.detached) {
        [void]$troubles.Add((New-HordeServiceTrouble -Key "checkout:branch" -Text ("its checkout is on the branch " + $Observed.checkout.value.branch + ", and a supervised checkout is a detached one, so nobody's branch is ever moved; nothing was touched")))
        return (& $finish "wait" "" "on-a-branch" ("update to " + $short + " waits: its checkout is on a branch, and only a detached checkout is moved"))
    }
    if (-not $Observed.checkout.value.clean) {
        [void]$troubles.Add((New-HordeServiceTrouble -Key "checkout:dirty" -Text "its checkout has local changes, so no update is applied over them; nothing was touched"))
        return (& $finish "wait" "" "dirty" ("update to " + $short + " waits: its checkout has local changes, and they are never written over"))
    }
    if (-not $Observed.wanted.value.fastForward) {
        [void]$troubles.Add((New-HordeServiceTrouble -Key "checkout:diverged" -Text ("its checkout has diverged from " + $Definition.follow.remote + "/" + $Definition.follow.branch + ": the wanted revision does not descend from what is checked out; nothing was touched")))
        return (& $finish "wait" "" "diverged" ("update to " + $short + " waits: it is not a fast-forward of what is checked out"))
    }
    if ($null -ne $s.refused -and $s.refused.revision -ceq $wanted -and $s.refused.kind -cne "retreat") {
        $again = $s.refused.at.AddMinutes($Policy.retryRefusedMinutes)
        if ($at -lt $again) {
            [void]$troubles.Add((New-HordeServiceTrouble -Key ($s.refused.kind + ":" + $wanted) -Text ("revision " + $short + $(if ($s.refused.kind -ceq "verify") { " failed its check before the restart" } else { " could not be applied" }) + " (" + $s.refused.reason + "); the old revision keeps running")))
            return (& $finish "wait" "" "not-verified" ("update not verified: " + $short + $(if ($s.refused.kind -ceq "verify") { " failed its check" } else { " could not be applied" }) + " (" + $s.refused.reason + "); tried again in " + [long]($again - $at).TotalSeconds + " s"))
        }
        if ($s.refused.kind -ceq "verify") { $s.verifiedRevision = "" }
    }
    if ($s.verifiedRevision -cne $wanted) { return (& $finish "restart-for-update" "verify" "verify" ("revision " + $short + " is wanted; it is checked in a scratch copy while the old one runs") $live.process $wanted) }
    if ($Definition.follow.restart -ceq "idle" -and -not $IgnoreIdle) {
        if ($Observed.idleSeconds.state -cne "known") { return (& $finish "wait" "" "idle-unknown" ("update to " + $short + " waits: whether the person is idle is not known (" + $Observed.idleSeconds.reason + "), and unknown is never read as idle")) }
        if ([long]$Observed.idleSeconds.value -lt $Definition.follow.idleSeconds) { return (& $finish "wait" "" "not-idle" ("update to " + $short + " waits: the person is not idle (it restarts after " + $Definition.follow.idleSeconds + " s with no input)")) }
    }
    $s.phase = "stopping"; $s.intent = "update"; $s.phaseSince = $at; $s.target = $wanted
    $s.from = $(if ($s.runningRevision -ne "") { $s.runningRevision } else { $head })
    return (& $finish "restart-for-update" "stop" "update" ("restarting for the update from " + (ConvertTo-HordeServiceShortRevision $s.from) + " to " + $short) $live.process $wanted)
}

function Complete-HordeServiceStep {
    # PURE. The state after a step was tried. -Decision is what Get-HordeServiceDecision returned (its
    # state is the one built on); -Outcome is { ok; detail; process; revision }: whether the step did
    # what it was for, one sentence of what happened, the process a start made ({ pid; startedAt }),
    # and the revision the checkout is now on. A step that was not taken changes nothing but
    # lastAction. THE RULE FOR EVERY FAILURE: the state moves to wherever the NEXT pass will find the
    # truth by looking - never to where the step would have got to had it worked.
    param([Parameter(Mandatory = $true)]$Definition, [Parameter(Mandatory = $true)]$Decision, [Parameter(Mandatory = $true)]$Outcome, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)]$Policy)
    $at = $Now.ToUniversalTime()
    $s = Copy-HordeServiceState -State $Decision.state
    $ok = [bool]$Outcome.ok
    $detail = "" + $Outcome.detail
    switch ($Decision.step) {
        "start" {
            if ($ok) {
                $s.started = [pscustomobject]@{ pid = [int]$Outcome.process.pid; startedAt = $Outcome.process.startedAt; at = $at }
                if ($s.phase -ceq "launching" -and $s.intent -ceq "update") { $s.phase = "confirming"; $s.phaseSince = $at; $s.confirmBy = $at.AddSeconds($Definition.confirmSeconds) }
                else {
                    if ($s.phase -ceq "launching") { $s.phase = "steady"; $s.intent = ""; $s.phaseSince = $null; $s.runningRevision = $s.from }
                    elseif ("" + $Outcome.revision -ne "") { $s.runningRevision = "" + $Outcome.revision }
                    $s.proving = $true
                }
            } elseif ($s.phase -ceq "launching" -and $s.intent -ceq "update") {
                # The new revision could not even be started: back to the old one, at once.
                $s.intent = "rollback"; $s.phase = "stopping"; $s.phaseSince = $at; $s.started = $null
            } else {
                if ($s.phase -ceq "launching") { $s.phase = "steady"; $s.intent = ""; $s.phaseSince = $null }
                $s.started = $null; $s.proving = $false
                $s.failures = [int]$s.failures + 1
                $s.nextStartAt = $at.AddSeconds((Get-HordeServiceBackoffSeconds -Failures $s.failures -Policy $Policy))
            }
        }
        "stop" { if (-not $ok) { $s.stuck = $detail } }
        "kill" { if ($ok) { $s.stuck = "" } else { $s.stuck = $detail } }
        "verify" {
            if ($ok) { $s.verifiedRevision = $Decision.revision; if ($null -ne $s.refused -and $s.refused.kind -cne "retreat") { $s.refused = $null } }
            else { $s.verifiedRevision = ""; $s.refused = [pscustomobject]@{ revision = $Decision.revision; kind = "verify"; reason = $detail; at = $at } }
        }
        "advance" {
            if ($ok) { $s.phase = "launching"; $s.phaseSince = $at; $s.previousRevision = $s.from }
            else {
                # The checkout did not move: the old revision is still there, and is started as a
                # service that is simply not running. The update is tried again later.
                $s.phase = "steady"; $s.intent = ""; $s.phaseSince = $null
                $s.refused = [pscustomobject]@{ revision = $s.target; kind = "apply"; reason = $detail; at = $at }
            }
        }
        "retreat" {
            # The bad revision is pinned whether or not the checkout went back: it is never tried again.
            $s.pinnedRevision = $s.target; $s.verifiedRevision = ""
            if ($ok) { $s.phase = "launching"; $s.phaseSince = $at }
            else {
                $s.phase = "steady"; $s.intent = ""; $s.phaseSince = $null
                $s.refused = [pscustomobject]@{ revision = $s.target; kind = "retreat"; reason = $detail; at = $at }
            }
        }
    }
    $s.lastAction = [pscustomobject]@{ at = $at; action = $Decision.action; step = $Decision.step; outcome = $(if ($Decision.step -eq "") { "" } elseif ($ok) { "done" } else { "failed" }); reason = $(if ($detail -ne "") { $detail } else { $Decision.reason }) }
    return $s
}

function Add-HordeServiceNotice {
    # PURE. The state with the decision's notice waiting to be told, under -Id (a lowercase uuid the
    # caller made: the messenger keeps one notice per id, so a retry never tells twice). The oldest
    # is dropped when more than the cap wait: the newest say what is true now.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Decision, [Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][datetime]$Now)
    if ($Decision.notify -eq "") { return $State }
    $next = Copy-HordeServiceState -State $State
    $next.notices = @(@($next.notices) + @([pscustomobject]@{ id = $Id; kind = $Decision.notify; text = $Decision.notice; at = $Now.ToUniversalTime() }) | Select-Object -Last $script:HordeServiceNoticesMost)
    return $next
}

function Test-HordeServiceFetchDue {
    # PURE. Is it time to ask the remote again? Never asked, or asked at least the interval ago. A
    # last time in the future (a clock set back) is due too: waiting for the clock would be waiting
    # for nobody knows how long.
    param($LastFetchAt, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)][int]$IntervalSeconds)
    if ($LastFetchAt -isnot [datetime]) { return $true }
    $since = ($Now.ToUniversalTime() - $LastFetchAt.ToUniversalTime()).TotalSeconds
    return [bool]($since -ge $IntervalSeconds -or $since -lt 0)
}

function Get-HordeServiceStatus {
    # PURE. What `horde services status` says of one service, from the same inputs a pass decides by:
    # { name; enabled; alive; why; pid; heartbeatAgeSeconds; phase; runningRevision; wantedRevision;
    #   current; next; nextReason; lastAction; failures; escalated; untold; fetchProblem }.
    # next is what a pass would do now; nothing is done, and the state is not changed.
    param([Parameter(Mandatory = $true)]$Definition, [Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Observed, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)]$Policy)
    $d = Get-HordeServiceDecision -Definition $Definition -State $State -Observed $Observed -Now $Now -Policy $Policy
    $wanted = $null
    if ($Observed.wanted.state -ceq "known") { $wanted = "" + $Observed.wanted.value.revision }
    $running = $(if ($State.runningRevision -ne "") { $State.runningRevision } elseif ($Observed.checkout.state -ceq "known") { "" + $Observed.checkout.value.head } else { $null })
    $current = $null
    if ($null -ne $wanted -and $null -ne $running) { $current = [bool]($wanted -ceq $running) }
    $processId = $null
    if ($null -ne $d.live.process) { $processId = [int]$d.live.process.pid }
    return [pscustomobject]@{
        name = $Definition.name; enabled = [bool]$Definition.enabled; alive = $d.live.alive; why = $d.live.why; pid = $processId
        heartbeatAgeSeconds = $d.live.heartbeatAgeSeconds; phase = $State.phase; runningRevision = $running; wantedRevision = $wanted; current = $current
        next = $(if ($d.step -ne "") { $d.action + " (" + $d.step + ")" } else { $d.action }); nextReason = $d.reason
        lastAction = $State.lastAction; failures = [int]$State.failures; escalated = [string[]]@($State.told); untold = @($State.notices).Count
        pinnedRevision = $(if ($State.pinnedRevision -ne "") { $State.pinnedRevision } else { $null }); fetchProblem = "" + $State.fetchProblem
    }
}
