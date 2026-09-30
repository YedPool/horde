$HordeCommand = @{
    name    = "boom"
    group   = "about"
    usage   = "boom"
    summary = "fails"
    run     = {
        [CmdletBinding()] param()
        throw "boom failed on purpose"
    }
}
