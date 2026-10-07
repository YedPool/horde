# DOES ANY SHIPPED CODE WRITE INTO A TYPED PARAMETER BY NAMING IT IN ANOTHER CASING?
#
# A structural guard (tools/ParamShadow.ps1). PowerShell's names ignore case, so in a block with a
# [string]$Transport parameter, `$transport = <an object>` writes into the parameter and the type turns
# the object into text. That broke `horde node serve` on PR #111 (2026-10-07). This suite fails on the
# form anywhere in shipped code, so the class cannot come back.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "tools\ParamShadow.ps1")

Write-Host ""
Write-Host "--- the instrument, on planted text ---" -ForegroundColor Cyan
$bug = 'function F { param([string]$Transport) $transport = Get-Thing; return $transport }'
$found = @(Find-HordeParamShadows -Text $bug)
Check ($found.Count -eq 1 -and $found[0].Contains('$transport writes into parameter [string]$Transport')) ("the #111 form is found, naming both casings and the type (" + ($found -join " | ") + ")")
Check (@(Find-HordeParamShadows -Text '$x = { param([int]$Count) $count = "many" }').Count -eq 1) "in a script block's own param block too"
$sameCase = 'function F { param([string]$Transport) if ($Transport -eq "") { $Transport = "local" } }'
Check (@(Find-HordeParamShadows -Text $sameCase).Count -eq 0) "CONTROL: an assignment in the parameter's own casing is plainly meant, and not counted"
$untyped = 'function F { param($Rows) $rows = @($Rows) }'
Check (@(Find-HordeParamShadows -Text $untyped).Count -eq 0) "CONTROL: an untyped parameter converts nothing, and is not counted"
Check (@(Find-HordeParamShadows -Text 'function F { param([object[]]$Live) $live = @($Live) }').Count -eq 0) "CONTROL: nor is one typed object or an array of them"
$nested = 'function F { param([string]$Name) $inner = { param([int]$Other) $name2 = 1 }; function G { param([int]$Name) $name = 2 } }'
Check (@(Find-HordeParamShadows -Text $nested).Count -eq 1) "a nested block's assignment is judged against its own params, not its parent's"

Write-Host ""
Write-Host "--- shipped code ---" -ForegroundColor Cyan
$files = @(Get-HordeShippedScriptFiles -Root $root)
Check ($files -ccontains "cli/commands/node.ps1") ("CONTROL: the file of the #111 case is scanned (" + $files.Count + " files)")
$all = @(Find-HordeShippedParamShadows -Root $root)
foreach ($f in $all) { Write-Host ("         " + $f) -ForegroundColor Red }
Check ($all.Count -eq 0) ("no shipped code writes into a typed parameter under another casing (" + $all.Count + " found)")

Complete-HordeSuite -Success "no shipped code writes into a typed parameter by naming it in another casing"
