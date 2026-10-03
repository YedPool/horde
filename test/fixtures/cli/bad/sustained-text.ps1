$HordeCommand = @{
    name      = "sustained-text"
    group     = "about"
    usage     = "sustained-text"
    summary   = "declares sustained as text, which is not a true or false the registry can read"
    sustained = "yes"
    run       = { [CmdletBinding()] param() "never" }
}
