$HordeCommand = @{
    name    = "notify-service"
    group   = "relay"
    usage   = "notify-service register -Name <name> -SecretFile <new file> | revoke -Name <name> | list"
    summary = "register, revoke or list the notice services: unattended programs (a scheduled task) that send the founder notices as ""service: <name>"" with `notify -Service`. register and revoke are run by a proven session whose label is in the setting serviceRegistrars (the founder's side, default M) - a service can never register itself. register makes the service's secret and writes it to a NEW file locked to this Windows user; the machine keeps only a hash of it. A name that collides with M, the Thrall, the founder, an Orc's label or any fleet label is refused. list shows names, never secrets. The secret file is readable by the user who registered it and SYSTEM only: a service run as another Windows account is refused (a message saying the file can be read by someone else is about the file, not an attack)"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("register", "revoke", "list")][string]$Verb,
            [string]$Name,
            [string]$SecretFile
        )
        . (Join-Path (Get-HordeRoot) "notices\Sender.ps1")
        . (Join-Path (Get-HordeRoot) "notices\Services.ps1")
        $verbFlags = @{ register = @("Name", "SecretFile"); revoke = @("Name"); list = @() }
        foreach ($flag in @("Name", "SecretFile")) {
            if ($PSBoundParameters.ContainsKey($flag) -and $verbFlags[$Verb] -cnotcontains $flag) { throw ("-" + $flag + " does not belong to notify-service " + $Verb) }
        }
        if ($Verb -ceq "list") {
            $st = Get-HordeNoticeStore
            if (-not $st.ok) { throw $st.reason }
            $all = Read-HordeNoticeServices -Store $st.store
            if ($all.state -cne "known") { throw $all.reason }
            if ($all.value.Count -eq 0) { Write-Output "no notice service is registered"; return }
            foreach ($k in @($all.value.Keys | Sort-Object)) { Write-Output ($k + "  registered " + $all.value[$k].at + " by " + $all.value[$k].by) }
            return
        }
        if (-not $PSBoundParameters.ContainsKey("Name")) { throw ("notify-service " + $Verb + " needs -Name") }
        $who = Resolve-HordeNoticeSender
        if (-not $who.ok) { throw $who.reason }
        if ($Verb -ceq "register") {
            if (-not $PSBoundParameters.ContainsKey("SecretFile")) { throw "notify-service register needs -SecretFile, the new file the service's secret is written to" }
            $r = Register-HordeNoticeService -Registrar $who -Name $Name -SecretFile $SecretFile
            if (-not $r.ok) { throw $r.reason }
            Write-Output ("registered service '" + $Name + "'; its secret is in " + $SecretFile + " (readable by this Windows user alone). The service sends with: horde notify -Service " + $Name + " -SecretFile <that file> -Text <line>")
        } else {
            $r = Remove-HordeNoticeService -Registrar $who -Name $Name
            if (-not $r.ok) { throw $r.reason }
            Write-Output ("revoked service '" + $Name + "'; its secret proves nothing now (delete its secret file)")
        }
    }
}
