using module ..\modules\marker.psm1
$HordeCommand = @{
    name    = "using-module"
    group   = "about"
    usage   = "using-module"
    summary = "imports a module - running its code - when the file loads"
    run     = { [CmdletBinding()] param() "never" }
}
