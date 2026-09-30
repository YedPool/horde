$HordeCommand = @{
    name    = "computed"
    group   = "about"
    usage   = "computed"
    summary = (Set-Content -LiteralPath (Join-Path $env:TEMP "horde-cli-side-effect-marker.txt") -Value "ran")
    run     = { [CmdletBinding()] param() "never" }
}
