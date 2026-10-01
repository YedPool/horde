# A CONTROL for tools/ExecScan.ps1, never run: written the way remote/ is written - its loader line,
# allowlisted cmdlets, the functions of core/ and of this file, .NET types that start nothing - and the
# scan must find nothing in it, or a scan that refused everything would pass its other control too.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")
. (Join-Path $PSScriptRoot "Contract.ps1")

function Get-CleanWords {
    param([string]$Name, $Frame)
    $out = New-Object System.Collections.ArrayList
    $sb = New-Object System.Text.StringBuilder 16
    $bytes = New-Object byte[] 4
    foreach ($w in [regex]::Split($Name, '[^A-Za-z0-9]+')) { if ($w -ne "") { [void]$out.Add($w.ToLowerInvariant()) } }
    $kept = @($out | Where-Object { $_ -cne "x" } | ForEach-Object { $_.Trim() } | Sort-Object -Unique)
    $text = ConvertTo-Json -InputObject $kept -Compress
    $back = ConvertFrom-Json -InputObject $text
    $ascii = [System.Text.Encoding]::ASCII.GetBytes($text)
    [void]$sb.Append($text)
    $when = (Get-Date).ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
    $schema = Get-HordeSchema -Name "link-frame.v1"
    $Frame | Add-Member -NotePropertyName seen -NotePropertyValue $when
    return [pscustomobject]@{ words = $back; bytes = $ascii.Length + $bytes.Length; schema = $schema; parent = (Split-Path -Parent $PSScriptRoot) }
}

function Get-CleanCount { param($Items) return (@(Get-CleanWords -Name "a b" -Frame $Items) | Measure-Object).Count }
