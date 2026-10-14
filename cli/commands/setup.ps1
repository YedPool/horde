$HordeCommand = @{
    name    = "setup"
    group   = "setup"
    usage   = "setup [-Horde <name>] [-Label <text>] [-Operator] [-Relay <name>] [-NoFix <step id>,...] [-CheckOnly] [-Json] | setup -Steps [-Json]"
    summary = "the first run of Horde on this machine (cli/Setup.ps1): checks each step in order - the Horde home, the relay settings naming this horde and the phone app, this machine's relay identity, the relay runner defined as a service, the relay runner serving, a phone paired - fixes what it safely can (makes the home, writes settings\relay.json for the shared relay, makes the identity, writes the relay runner's service definition; never a file that is there already), stops at the first step it cannot finish, and ends with one line: the next thing to do, with the exact command, or all set. Run again, it changes nothing that is right. It never asks for a password or stores a secret: Google sign-in stays on the phone. -Horde names the horde a written relay.json gets (home by default); -Label is what pairing will call this machine; -Operator walks a home that hosts its own relay through that relay's steps (where it answers, its Google sign-in client with the exact redirect URI and JavaScript origin, its deploy) first; -NoFix names steps to check without fixing; -CheckOnly fixes nothing; -Json prints the report as one line of data; -Steps lists the steps themselves"
    run     = {
        [CmdletBinding()] param([string]$Horde = "home", [string]$Label = "", [switch]$Operator, [string]$Relay = "", [string[]]$NoFix = @(), [switch]$CheckOnly, [switch]$Json, [switch]$Steps)
        if ($Steps) { foreach ($flag in @($PSBoundParameters.Keys)) { if (@("Steps", "Json") -notcontains $flag) { throw ("-" + $flag + " does not belong to setup -Steps") } } }
        # Loaded here, in the command's own scope, so the relays' blocks see their helpers (relays/Port.ps1).
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "Services")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "relays\Port.ps1")
        foreach ($f in @(Get-HordeRelayFiles)) { . $f }
        . (Join-Path $root "relay\Trust.ps1")
        foreach ($f in @("RelayDeploy", "RelayRun", "Setup")) { . (Join-Path $root ("cli\" + $f + ".ps1")) }
        if ($Steps) {
            $list = @(Get-HordeSetupStepList)
            if ($Json) { ConvertTo-Json -InputObject $list -Depth 4 -Compress; return }
            foreach ($s in $list) {
                Write-Output ($s.id + " (" + $s.path + "): " + $s.title)
                Write-Output ("    checks: " + $s.checks)
                if ($s.fixes -ne "") { Write-Output ("    fixes:  " + $s.fixes) }
                if ($s.manual -ne "") { Write-Output ("    by hand: " + $s.manual) }
            }
            return
        }
        $known = @(Get-HordeSetupStepList | ForEach-Object { $_.id })
        foreach ($id in @($NoFix)) { if ($known -cnotcontains $id) { throw ("-NoFix names no step: '" + $id + "'; the steps are " + ($known -join ", ")) } }
        $report = Get-HordeSetupReport -HordeHome (Get-HordeHome) -Root $root -Relay $Relay -Operator:$Operator -Horde $Horde -Label $Label -NoFix $NoFix -CheckOnly:$CheckOnly
        if ($Json) { ConvertTo-Json -InputObject $report -Depth 6 -Compress; return }
        Format-HordeSetupReport -Report $report | ForEach-Object { Write-Output $_ }
    }
}
