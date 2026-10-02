# DOES A CALL COST WHAT THE PRICE TABLE SAYS, AND NOTHING WHEN THE TABLE CANNOT SAY?
#
# core/Price.ps1, with neutral model ids ("model-a"): real model ids are the provider's vocabulary and
# never live in the repository (planning/execution-plan-metrics.md). Rates are the shape observed for
# one provider on 2026-09-30 (metrics design 2.9): input 4, 5-minute cache write 5, 1-hour cache write
# 8, cache read 0.2, output 20, per million tokens.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "core\ReadShared.ps1")
. (Join-Path $root "core\Home.ps1")
. (Join-Path $root "core\Transcript.ps1")
. (Join-Path $root "core\Price.ps1")

$tableText = @'
{ "schemaVersion": 1, "version": "test.1", "observedAt": "2026-09-30", "currency": "USD", "perTokens": 1000000,
  "models": {
    "model-a": { "provider": "provider-a", "rates": { "input": 4, "cacheWrite5m": 5, "cacheWrite1h": 8, "cacheRead": 0.2, "output": 20 },
                 "geo": { "us": 1.1 }, "geoStandard": ["not_available", ""], "speeds": { "fast": { "input": 8, "output": 40 } } },
    "model-b": { "provider": "provider-b", "rates": { "input": 5, "cacheRead": 0.5, "output": 30 } },
    "model-c": { "provider": "provider-c", "rates": { "input": 1, "cacheWrite": 2, "output": 3 } }
  } }
'@
$parsed = ConvertFrom-HordePriceTableText -Text $tableText
Check ($parsed.state -eq "known") "CONTROL: a well-formed table is accepted"
$table = $parsed.value
$t0 = ConvertTo-HordeUtcTime "2026-09-30T12:00:00Z"

function New-TestCall {
    param([string]$Model = "model-a", [long]$In = 0, [long]$Read = 0, [long]$Write = 0, [long]$Out = 0, $Split = (New-HordeAbsent), [string]$Speed = "", [string]$Geo = "")
    $usage = New-HordeUsage -Uncached $In -CacheRead $Read -CacheWrite $Write -Output $Out -Split $Split
    return (New-HordeTranscriptRecord -Kind "call" -Role "assistant" -Ts $t0 -Line 1 -Fields @{ id = "c"; model = (New-HordeKnown -Value $Model); usage = $usage; textChars = 0; toolCallCount = 0; speed = $Speed; inferenceGeo = $Geo })
}
function Split { param($M5, $H1) New-HordeKnown -Value ([pscustomobject]@{ m5 = [long]$M5; h1 = [long]$H1 }) }

Write-Host ""
Write-Host "--- pricing a call ---" -ForegroundColor Cyan
$c = Get-HordeCallCost -Table $table -Call (New-TestCall -In 1000 -Read 100000 -Write 3000 -Out 500 -Split (Split 1000 2000))
Check ($c.state -eq "known" -and $c.value -eq [decimal]0.055) ("every token class at its own rate: 1000x4 + 100000x0.2 + 1000x5 + 2000x8 + 500x20 per million = 0.055 (" + $c.value + ")")
Check ($c.value -is [decimal]) "a cost is a decimal, so a long sum carries no binary rounding"
$m5 = Get-HordeCallCost -Table $table -Call (New-TestCall -Write 1000000 -Split (Split 1000000 0))
$h1 = Get-HordeCallCost -Table $table -Call (New-TestCall -Write 1000000 -Split (Split 0 1000000))
Check ($m5.value -eq 5 -and $h1.value -eq 8) "a 5-minute and a 1-hour cache write of the same size cost differently (5 and 8)"
$us = Get-HordeCallCost -Table $table -Call (New-TestCall -In 1000000 -Geo "us")
$na = Get-HordeCallCost -Table $table -Call (New-TestCall -In 1000000 -Geo "not_available")
Check ($us.value -eq [decimal]4.4 -and $na.value -eq 4) "a 'us' request costs 1.1 times, and a geography the table calls standard costs the base rate"
$odd = Get-HordeCallCost -Table $table -Call (New-TestCall -In 1000000 -Geo "mars")
Check ($odd.state -eq "unknown" -and $odd.reason -like "*geography 'mars'*") "a geography the table does not price is unknown, not the base rate"
$fast = Get-HordeCallCost -Table $table -Call (New-TestCall -In 1000000 -Speed "fast")
Check ($fast.value -eq 8) "a speed the table prices uses that speed's rates"
$turbo = Get-HordeCallCost -Table $table -Call (New-TestCall -In 1000000 -Speed "turbo")
Check ($turbo.state -eq "unknown" -and $turbo.reason -like "*speed 'turbo'*") "a speed the table does not price is unknown, not the standard rate"
$std = Get-HordeCallCost -Table $table -Call (New-TestCall -In 1000000 -Speed "standard")
Check ($std.value -eq 4) "CONTROL: the speed called standard uses the base rates"

Write-Host ""
Write-Host "--- what cannot be priced ---" -ForegroundColor Cyan
$unpriced = Get-HordeCallCost -Table $table -Call (New-TestCall -Model "model-z" -In 10)
Check ($unpriced.state -eq "unknown" -and $unpriced.reason -like "*no price for model 'model-z'*" -and $unpriced.reason -like "*test.1*") "a model the table does not price is unknown, naming the model and the table version"
$noWriteRate = Get-HordeCallCost -Table $table -Call (New-TestCall -Model "model-b" -Write 10)
Check ($noWriteRate.state -eq "unknown" -and $noWriteRate.reason -like "*prices only by lifetime*") "cache writes on a model with no cache-write rate are unknown, never free"
$noOutRate = Get-HordeCallCost -Table $table -Call (New-TestCall -Model "model-c" -In 10 -Out 10 -Read 5)
Check ($noOutRate.state -eq "unknown" -and $noOutRate.reason -like "*no 'cacheRead' rate*") "tokens in a class the table gives no rate for are unknown, never free"
$zeroWrites = Get-HordeCallCost -Table $table -Call (New-TestCall -Model "model-b" -In 1000000)
Check ($zeroWrites.value -eq 5) "CONTROL: a missing rate does not matter when that class has no tokens"
$flat = Get-HordeCallCost -Table $table -Call (New-TestCall -Model "model-c" -Write 1000000)
Check ($flat.value -eq 2) "a cache write with no lifetime split is priced at a flat cache-write rate when the table has one"
$noSplitTiered = Get-HordeCallCost -Table $table -Call (New-TestCall -Write 1000)
Check ($noSplitTiered.state -eq "unknown") "a cache write with no split, on a model priced only by lifetime, is unknown"
$bad = Get-HordeCallCost -Table $table -Call (New-TestCall -Write 3000 -Split (Split 1000 1000))
Check ($bad.state -eq "unknown" -and $bad.reason -like "*does not add up*") "a split that does not add up to the cache writes is unknown"
$noUsageCall = New-HordeTranscriptRecord -Kind "call" -Role "assistant" -Ts $t0 -Line 9 -Fields @{ id = "u"; model = (New-HordeKnown -Value "model-a"); usage = (New-HordeUnknown -Reason "no usage"); textChars = 0; toolCallCount = 0; speed = ""; inferenceGeo = "" }
Check ((Get-HordeCallCost -Table $table -Call $noUsageCall).state -eq "unknown") "a call with no usage is unknown"
$noModelCall = New-HordeTranscriptRecord -Kind "call" -Role "assistant" -Ts $t0 -Line 9 -Fields @{ id = "u"; model = (New-HordeUnknown -Reason "x"); usage = (New-HordeUsage -Uncached 1 -CacheRead 0 -CacheWrite 0 -Output 0 -Split (New-HordeAbsent)); textChars = 0; toolCallCount = 0; speed = ""; inferenceGeo = "" }
Check ((Get-HordeCallCost -Table $table -Call $noModelCall).state -eq "unknown") "a call with no model is unknown"

Write-Host ""
Write-Host "--- the table itself ---" -ForegroundColor Cyan
$noVersion = ConvertFrom-HordePriceTableText -Text '{ "schemaVersion": 1, "perTokens": 1000000, "models": { "m": { "rates": { "input": 1 } } } }'
Check ($noVersion.state -eq "unknown" -and $noVersion.reason -like "*no version*") "a table with no version is refused, since its costs could not cite it"
$negative = ConvertFrom-HordePriceTableText -Text '{ "schemaVersion": 1, "version": "v", "perTokens": 1000000, "models": { "m": { "rates": { "input": -1 } } } }'
Check ($negative.state -eq "unknown" -and $negative.reason -like "*at least 0*") "a negative rate is refused"
$strange = ConvertFrom-HordePriceTableText -Text '{ "schemaVersion": 1, "version": "v", "perTokens": 1000000, "models": { "m": { "rates": { "inputt": 1 } } } }'
Check ($strange.state -eq "unknown" -and $strange.reason -like "*'inputt' is not a rate*") "a misspelt rate name is refused, not ignored"
$two = ConvertFrom-HordePriceTableText -Text '{ "schemaVersion": 2, "perTokens": 0, "models": {} }'
Check ($two.state -eq "unknown" -and $two.reason -like "*schemaVersion*" -and $two.reason -like "*perTokens*") "every problem in a table is reported at once"
$work = Join-Path $env:TEMP ("horde-price-" + [guid]::NewGuid().ToString("N"))
$origHome = $env:HORDE_HOME
try {
    $env:HORDE_HOME = $work
    $none = Read-HordePriceTable
    Check ($none.state -eq "absent" -and $none.reason -like "*metrics*prices.json*") "with no table installed the table is absent, and says where it goes"
    New-Item -ItemType Directory -Path (Join-Path $work "metrics") -Force | Out-Null
    Set-Content -LiteralPath (Get-HordePriceTablePath) -Value $tableText -Encoding ASCII
    Check ((Read-HordePriceTable).state -eq "known") "CONTROL: an installed table under HORDE_HOME is read"
    Set-Content -LiteralPath (Get-HordePriceTablePath) -Value "{ not json" -Encoding ASCII
    Check ((Read-HordePriceTable).state -eq "unknown") "an installed table that is not JSON is unknown"
} finally {
    $env:HORDE_HOME = $origHome
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "a call costs what its table says per token class, and is unknown wherever the table cannot say"
