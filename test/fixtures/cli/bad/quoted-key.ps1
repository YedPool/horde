$HordeCommand = @{
    name        = "quoted-key"
    group       = "about"
    usage       = "quoted-key"
    "'summary'" = "a key whose value is 'summary', quotes included - not the key summary"
    run         = { [CmdletBinding()] param() "never" }
}
