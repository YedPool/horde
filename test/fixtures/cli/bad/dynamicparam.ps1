dynamicparam { Set-Content -LiteralPath (Join-Path $env:TEMP "horde-cli-side-effect-marker.txt") -Value "ran" }
end {
    $HordeCommand = @{
        name    = "dynamicparam"
        group   = "about"
        usage   = "dynamicparam"
        summary = "has a dynamicparam block"
        run     = { [CmdletBinding()] param() "never" }
    }
}
