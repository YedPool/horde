$b = Join-Path $PSScriptRoot ''
foreach ($n in 'remote','mut','local') {
  $f = Join-Path $PSScriptRoot ($n + '-detached.ps1')
  if (-not (Test-Path -LiteralPath $f)) { "MISSING $f"; continue }
  $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $f + '"' }
  $n + '=' + $r.ProcessId + ' rv=' + $r.ReturnValue
}
