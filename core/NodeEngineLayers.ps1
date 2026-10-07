# core/NodeEngineLayers - a node's own engine layers and policy, as its owner wrote them, read now.
#
# THE ONE LAYER READER (the act path's A3; moved here from cli/NodeAct.ps1 so that no core or remote
# code depends on a CLI file). Get-HordeNodeEngineLayers keeps its name and signature: -Root,
# -HordeHome, -Descriptors (and the optional -Builtin), returning { layers; problems }. The act path
# (cli/NodeAct.ps1) calls it at every spawn, and the messaging slice reads the same layers through it.
#
# EVERY FILE IS CHECKED AS BYTES, BEFORE IT IS DECODED (CONTRIBUTING 13). A decoder strips a byte-order
# mark and turns a stray byte into a character, so a hand-edited engine.json in another encoding would
# otherwise be read as if it were plain. A file that is not plain ASCII is a problem naming the file and
# why; so is one that does not parse, with the parser's own words. Every problem refuses every act that
# reads the layers: a file that fails is never dropped and acted on without it (review of #98, F1).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "NodePolicy.ps1")
. (Join-Path $PSScriptRoot "EngineResolve.ps1")

function Get-HordeNodeEngineLayers {
    # The node's own engine layers: L0 from the harness folders, L1 from <HordeHome>\engine.json and L4
    # from <HordeHome>\engine-live.json when they exist - the names engines E6 and E7 inherit. Returns
    # { layers; problems }. -Builtin: L0 already read (shipped code, which changes only with a restart);
    # without it L0 is read from -Root.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$HordeHome, $Descriptors, $Builtin = $null)
    $docs = New-Object System.Collections.ArrayList
    if ($null -eq $Builtin) { $Builtin = @(Get-HordeBuiltinLayer -Root $Root) }
    foreach ($l in @($Builtin)) { [void]$docs.Add($l) }
    $problems = New-Object System.Collections.ArrayList
    foreach ($pair in @(@("L1", "engine.json"), @("L4", "engine-live.json"))) {
        $path = Join-Path $HordeHome $pair[1]
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $bytes = $null
        try { $bytes = [System.IO.File]::ReadAllBytes($path) }
        catch { [void]$problems.Add($path + ": cannot be read - " + $_.Exception.Message); continue }
        try { Assert-HordeAsciiBytes -Bytes $bytes -What $path }
        catch { [void]$problems.Add($path + ": not ASCII - " + $_.Exception.Message); continue }
        try { [void]$docs.Add((Read-HordeEngineLayerText -Text ([System.Text.Encoding]::ASCII.GetString($bytes)) -Layer $pair[0] -Source $path)) }
        catch { [void]$problems.Add($path + ": not JSON - " + $_.Exception.Message) }
    }
    $findings = @(Test-HordeEngineConfig -Documents $docs.ToArray() -Descriptors $Descriptors | Where-Object { $_.severity -ceq "error" })
    foreach ($f in $findings) { [void]$problems.Add($f.source + " " + $f.path + ": " + $f.code + " - " + $f.detail) }
    return [pscustomobject]@{ layers = $docs.ToArray(); problems = $problems.ToArray() }
}

function Read-HordeNodeActConfig {
    # What the node's owner controls, read now: { policy; layers; problems }. A spawn calls it under the
    # spawn lock (review of #104, F1), so nothing the owner changes waits for a restart.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$HordeHome, $Descriptors, $Builtin = $null)
    $policy = Get-HordeNodePolicy -Path (Get-HordeNodePolicyPath -HordeHome $HordeHome)
    $eng = Get-HordeNodeEngineLayers -Root $Root -HordeHome $HordeHome -Descriptors $Descriptors -Builtin $Builtin
    return [pscustomobject]@{ policy = $policy; layers = @($eng.layers); problems = @($eng.problems) }
}
