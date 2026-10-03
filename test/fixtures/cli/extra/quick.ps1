$HordeCommand = @{
    name    = "quick"
    group   = "about"
    usage   = "quick"
    summary = "declares nothing about duration, and prints whether the throttling type was loaded for it"
    run     = {
        [CmdletBinding()] param()
        Write-Output ("TYPE " + $(if ("HordePowerThrottlingV1" -as [type]) { "loaded" } else { "none" }))
    }
}
