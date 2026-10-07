# Get-Val answers from its cache once one is filled, and computes otherwise (review of #115, round 2).
$script:valCache = $null
function Get-Val { if ($null -ne $script:valCache) { return $script:valCache }; return (2 + 3) }
function Set-ValCache { $script:valCache = 5 }
