$HordeCommand = @{
    name    = "redirect-value"
    group   = "about"
    usage   = "redirect-value"
    summary = "a redirection on one constant value" 2> $(Set-Content -LiteralPath (Join-Path $env:TEMP "horde-cli-side-effect-marker.txt") -Value "ran")
    run     = { [CmdletBinding()] param() "never" }
}
