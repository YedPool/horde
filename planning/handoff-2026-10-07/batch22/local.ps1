# batch22 local: the machine-bound suites and specs #120, #138, #139, #146 touch, on 7ed7cec.
Set-Location "C:\Users\yedid\bin\horde-worktrees\batch22"
Write-Output ("HEAD " + (& git rev-parse --short HEAD))
$bad = 0
foreach ($s in @("transports\local\test\test-local.ps1","test\test-transport-conformance.ps1","transports\local\test\test-node-serve-local.ps1","transports\local\test\test-hub-serve-local.ps1","transports\local\test\test-hub-act-local.ps1","transports\ssh\test\test-listen-local.ps1","transports\ssh\test\test-sshd-local.ps1")) {
  $t0 = Get-Date; & powershell -NoProfile -ExecutionPolicy Bypass -File $s; $c = $LASTEXITCODE
  Write-Output ("SUITE " + $s + " exit=" + $c + " SECONDS=" + [int]((Get-Date) - $t0).TotalSeconds); if ($c -ne 0 -and $c -ne 3) { $bad++ }
}
foreach ($p in @("test\mutations\transport-local.psd1","transports\ssh\test\mutations\far-end.psd1","transports\ssh\test\mutations\listen-live.psd1","transports\ssh\test\mutations\relay-live.psd1")) {
  $t0 = Get-Date; & powershell -NoProfile -ExecutionPolicy Bypass -File "tools\Mutate.ps1" -Spec $p; $c = $LASTEXITCODE
  Write-Output ("SPEC " + $p + " exit=" + $c + " SECONDS=" + [int]((Get-Date) - $t0).TotalSeconds); if ($c -ne 0) { $bad++ }
}
$svc = Get-Service sshd; Write-Output ("SSHD-SERVICE " + $svc.Status + " " + $svc.StartType)
Write-Output ("LOCAL-FINAL bad=" + $bad); $global:LASTEXITCODE = [int]($bad -ne 0)
