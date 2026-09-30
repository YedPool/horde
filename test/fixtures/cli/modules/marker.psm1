# Imported only by fixtures that must be refused. If this runs, something loaded one of them.
Set-Content -LiteralPath (Join-Path $env:TEMP "horde-cli-side-effect-marker.txt") -Value "ran"
