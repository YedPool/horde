$HordeCommand = @{
    name    = "listen"
    group   = "hub"
    # Runs until stopped, like hub serve: Windows throttles a busy background process about 7x after 3 s
    # (core/Platform.ps1), and the listener is asked whether it still serves every second.
    sustained = $true
    usage   = "listen [-Port <n>] [-Seconds <s>] [-Transport <name>]"
    summary = "accept enrolled nodes' links on 127.0.0.1 for as long as it runs: a listener of Horde's own, its every key forced to attach, which relays to this hub's pipe; nothing outside Horde's home is read or changed"
    run     = {
        [CmdletBinding()] param(
            # The loopback port to listen on; 0, the default, picks a free one and prints it.
            [int]$Port = 0,
            # How long to listen; 0, the default, listens until stopped.
            [int]$Seconds = 0,
            # Which transport's listener, when more than one has one.
            [string]$Transport = ""
        )
        # Loaded here, in the command's own scope, so the listeners' helpers stay visible to the blocks
        # they register (transports/Listener.ps1, the adapter contract).
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "Device", "Schema", "ReadShared", "FileAtomic")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "cli\HubRegistry.ps1")
        . (Join-Path $root "transports\Listener.ps1")
        foreach ($l in @(Get-HordeListenerFiles)) { . $l }
        if ($Seconds -lt 0) { throw "-Seconds must be 0 (listen until stopped) or more" }
        $a = Get-HordeListenerAdapter -Name $Transport
        if ($a.state -cne "known") { throw ("no listener to start: " + $a.reason) }
        $hordeHome = Get-HordeHome
        # The hub id is this machine's device id (remote design, decision 1): attach relays to its pipe.
        $hubId = (Get-HordeNode).deviceId
        # The hub's register (cli/HubRegistry.ps1): a key is served only for a device it holds, live, with
        # that key; read again at every health check.
        $register = { Get-HordeHubLiveKeys -HordeHome $hordeHome }
        $s = Start-HordeListener -Adapter $a.value -HordeHome $hordeHome -HubId $hubId -Root $root -Port $Port -Register $register
        if ($s.state -cne "known") { throw $s.reason }
        $running = $s.value
        $why = "stopped"
        try {
            Write-Host ("listening on " + $running.address + " for hub " + $hubId + "; every admitted key is forced to attach")
            $until = $null
            if ($Seconds -gt 0) { $until = [datetime]::UtcNow.AddSeconds($Seconds) }
            while ($null -eq $until -or [datetime]::UtcNow -lt $until) {
                $h = Test-HordeListenerServing -Running $running
                if ($h.state -cne "known" -or $h.value -ne $true) {
                    $why = "the listener stopped serving: " + $(if ($h.state -ceq "known") { "it is no longer running" } else { $h.reason })
                    break
                }
                Start-Sleep -Milliseconds 1000
            }
        } finally {
            # Ends the server and every session it started, also on Ctrl+C; if this process is killed
            # instead, the job it holds closes and Windows ends them (transports/<name>/Listen.ps1).
            $last = Stop-HordeListener -Running $running
        }
        if ($why -cne "stopped") { throw ($why + "; its last words: " + "$last".Trim().Replace("`r", "").Replace("`n", " | ")) }
        Write-Output ("listener on " + $running.address + " stopped")
    }
}
