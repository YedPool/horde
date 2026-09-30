# An error a test catches on purpose is not an unexpected error.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "..\..\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Check (Throws { throw "on purpose" } "on purpose") "a thrown error is seen by Throws"
$ok = $false; try { [void](Get-Item -LiteralPath "C:\no\such\horde\path" -ErrorAction Stop) } catch { $ok = $true }
Check $ok "a caught error is handled by the test"
Complete-HordeSuite -Success "caught errors are not unexpected"
