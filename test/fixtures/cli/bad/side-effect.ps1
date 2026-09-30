# If this line ever runs, listing or loading commands executed a command file's top level.
Set-Content -LiteralPath (Join-Path $env:TEMP "horde-cli-side-effect-marker.txt") -Value "ran"
$HordeCommand = @{
    name    = "side-effect"
    group   = "about"
    usage   = "side-effect"
    summary = "does work when loaded"
    run     = { [CmdletBinding()] param() "never" }
}
