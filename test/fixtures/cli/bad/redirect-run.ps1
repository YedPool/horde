$HordeCommand = @{
    name    = "redirect-run"
    group   = "about"
    usage   = "redirect-run"
    summary = "a redirection on the run block"
    run     = { [CmdletBinding()] param() "never" } 2> $(Set-Content -LiteralPath (Join-Path $env:TEMP "horde-cli-side-effect-marker.txt") -Value "ran")
}
