#requires -Modules horde-test-no-such-module
$HordeCommand = @{
    name    = "requires-module"
    group   = "about"
    usage   = "requires-module"
    summary = "asks for a module to be imported - running its code - before the file loads"
    run     = { [CmdletBinding()] param() "never" }
}
