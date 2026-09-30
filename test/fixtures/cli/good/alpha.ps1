$HordeCommand = @{
    name    = "alpha"
    group   = "about"
    usage   = "alpha [-Loud]"
    summary = "a well-formed command"
    run     = {
        [CmdletBinding()] param([switch]$Loud)
        Write-Output "alpha ran"
    }
}
