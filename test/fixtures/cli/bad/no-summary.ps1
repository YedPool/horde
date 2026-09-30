$HordeCommand = @{
    name    = "no-summary"
    group   = "about"
    usage   = "no-summary"
    extra   = "an unknown key"
    run     = { [CmdletBinding()] param() "never" }
}
