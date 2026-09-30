$HordeCommand = @{
    name    = "something-else"
    group   = "about"
    usage   = "something-else"
    summary = "declares a name that is not its file name"
    run     = { [CmdletBinding()] param() "never" }
}
