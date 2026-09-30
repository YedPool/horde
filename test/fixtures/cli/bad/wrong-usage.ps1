$HordeCommand = @{
    name    = "wrong-usage"
    group   = "about"
    usage   = "wrong-usages"
    summary = "a usage line that starts with a different word"
    run     = { [CmdletBinding()] param() "never" }
}
