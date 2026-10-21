$HordeCommand = @{
    name    = "setup"
    group   = "setup"
    usage   = "setup [-Horde <name>] [-Label <text>] [-Operator] [-Relay <name>] [-NoFix <step id>,...] [-Check] [-InputFile <path>] [-NoPicture] [-Json] | setup -Steps [-Json]"
    summary = "the first run of Horde on this machine: walks setup\steps.json, the one list of what Horde needs (cli/Setup.ps1 interprets it) - Windows and Windows PowerShell 5.1, the Horde home, the relay settings naming this horde and the phone app, this machine's relay identity, the relay runner defined as a service, the relay runner serving, a phone paired, a first test question, and the relay runner kept running from start-up - checks each in order, fixes what it safely can (makes the home, writes settings\relay.json for the shared relay, makes the identity, writes the relay runner's service definition, runs the pairing as horde relay pair does - the QR code, where to tap on the phone, how long the code is good for, and the 12-digit number the phone shows typed here and compared - adds the test question once, schedules the supervisor when the prompt is elevated; never a file that is there already, and never elevating by itself), stops at the first step it cannot finish, and ends with one line: the next thing to do, with the exact command, or all set. Run again, it changes nothing that is right. Started from PowerShell 7, it runs itself again under Windows PowerShell 5.1. It never asks for a password or stores a secret: Google sign-in stays on the phone. -Horde names the horde a written relay.json gets (home by default); -Label is what this machine calls the phone it pairs (Phone by default); -InputFile reads what would be typed during pairing from a file as it grows, and -NoPicture does not open the QR code's picture (as for horde relay pair); -Operator walks a home that hosts its own relay through that relay's steps (where it answers, its Google sign-in client with the exact redirect URI and JavaScript origin, its deploy) first; -NoFix names steps to check without fixing; -Check (or -CheckOnly) fixes nothing; -Json prints the report as one line of data; -Steps lists the manifest's steps as this code reads them"
    run     = {
        [CmdletBinding()] param([string]$Horde = "home", [string]$Label = "", [switch]$Operator, [string]$Relay = "", [string[]]$NoFix = @(), [Alias("CheckOnly")][switch]$Check, [string]$InputFile = "", [switch]$NoPicture, [switch]$Json, [switch]$Steps)
        if ($Steps) { foreach ($flag in @($PSBoundParameters.Keys)) { if (@("Steps", "Json") -notcontains $flag) { throw ("-" + $flag + " does not belong to setup -Steps") } } }
        # Refused before anything, the run under 5.1 included: a double quote would break the pairing
        # command setup prints, and the arguments it runs itself again with.
        if ($Label.Contains('"')) { throw "-Label cannot hold a double quote: name the phone without one, such as -Label My-phone" }
        $root = Get-HordeRoot
        # WINDOWS POWERSHELL 5.1, until issue 274 is fixed: under PowerShell 7, `horde decisions add` is
        # refused ('$.at should be string'), so setup's last step would fail there. It runs itself again
        # under powershell.exe, once, with the same arguments, and passes its words and its ending on.
        if ("" + $PSVersionTable.PSEdition -ceq "Core") {
            $shell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
            if ([System.IO.File]::Exists($shell)) {
                Write-Host "horde setup: running again under Windows PowerShell 5.1 (powershell.exe), which Horde needs"
                $again = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "horde.ps1"), "setup")
                foreach ($k in @($PSBoundParameters.Keys)) {
                    $v = $PSBoundParameters[$k]
                    if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $again += ("-" + $k) } }
                    else { $again += ("-" + $k); $again += (@($v) -join ",") }
                }
                & $shell @again
                $code = $LASTEXITCODE
                $global:LASTEXITCODE = 0
                if ($code -ne 0) { throw ("horde setup under Windows PowerShell 5.1 ended with exit " + $code) }
                return
            }
        }
        # Loaded here, in the command's own scope, so the relays' and schedulers' blocks see their helpers.
        foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "Services", "ServicesFiles", "ServiceHostPort", "Schedule")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        foreach ($s in @(Get-HordeSchedulerFiles)) { . $s }
        . (Join-Path $root "relays\Port.ps1")
        foreach ($f in @(Get-HordeRelayFiles)) { . $f }
        . (Join-Path $root "relay\Trust.ps1")
        foreach ($f in @("RelayDeploy", "RelayRun", "ServicesAct", "ServicesTend", "QrCode", "RelayPair", "SetupStore", "Setup")) { . (Join-Path $root ("cli\" + $f + ".ps1")) }
        $man = Read-HordeSetupManifest -Path (Get-HordeSetupManifestPath -Root $root)
        if ($man.state -cne "known") { throw $man.reason }
        if ($Steps) {
            $code = Get-HordeSetupStepCode
            $list = @($man.value.steps | ForEach-Object { [pscustomobject]@{ id = $_.id; title = $_.title; path = $_.path; requirement = $_.requirement; checks = $_.checks; fixes = $_.fixes; manual = $_.manual; fixedBySetup = ($null -ne $code[$_.id].fix) } })
            if ($Json) { ConvertTo-Json -InputObject ([pscustomobject]@{ manifestVersion = $man.value.manifestVersion; steps = $list }) -Depth 4 -Compress; return }
            Write-Output ("setup\steps.json, manifest version " + $man.value.manifestVersion)
            foreach ($s in $list) {
                Write-Output ($s.id + " (" + $s.path + "): " + $s.title)
                Write-Output ("    needs:   " + $s.requirement)
                Write-Output ("    checks:  " + $s.checks)
                Write-Output ("    fixes:   " + $s.fixes)
                Write-Output ("    by hand: " + $s.manual)
            }
            return
        }
        # A list given as one word with commas (powershell -File passes it so) is the same list.
        $noFixIds = @(@($NoFix) | ForEach-Object { ("" + $_) -split "," } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        $known = @($man.value.steps | ForEach-Object { $_.id })
        foreach ($id in $noFixIds) { if ($known -cnotcontains $id) { throw ("-NoFix names no step: '" + $id + "'; the steps are " + ($known -join ", ")) } }
        $open = $(if ($NoPicture) { $null } else { { param($Path) Start-Process -FilePath $Path } })
        $file = $(if ($InputFile -ne "") { [System.IO.Path]::GetFullPath($InputFile) } else { "" })
        $report = Get-HordeSetupReport -HordeHome (Get-HordeHome) -Root $root -Relay $Relay -Operator:$Operator -Horde $Horde -Label $Label -NoFix $noFixIds -Check:$Check -InputFile $file -OpenPicture $open
        if ($Json) { ConvertTo-Json -InputObject $report -Depth 6 -Compress; return }
        Format-HordeSetupReport -Report $report | ForEach-Object { Write-Output $_ }
    }
}
