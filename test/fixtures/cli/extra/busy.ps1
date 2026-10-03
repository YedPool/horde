$HordeCommand = @{
    name      = "busy"
    group     = "about"
    usage     = "busy"
    summary   = "declares itself sustained, and prints its own power-throttling state"
    sustained = $true
    run       = {
        [CmdletBinding()] param()
        $s = Get-HordeThrottlingState
        Write-Output ("THROTTLE " + $s.state + " " + $s.value.controlMask + "/" + $s.value.stateMask)
    }
}
