$HordeCommand = @{
    name    = "inner-bind"
    group   = "about"
    usage   = "inner-bind"
    summary = "fails inside its body with a binding error of its own making"
    run     = {
        [CmdletBinding()] param()
        Get-ChildItem -NoSuchParameterForHordeTests
    }
}
