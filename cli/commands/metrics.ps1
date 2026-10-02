$HordeCommand = @{
    name    = "metrics"
    group   = "metrics"
    usage   = "metrics summarize <transcript-or-folder> [-From <UTC time>] [-To <UTC time>] [-Json]"
    summary = "read agent transcripts and print each worker's time, tokens, tool calls, silences and notional cost, and an orchestrator's still-waiting calls; records them only when metrics are enabled"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("summarize")][string]$Verb,
            [Parameter(Mandatory = $true, Position = 1)][string]$Path,
            [string]$From,
            [string]$To,
            [switch]$Json
        )
        # Loaded here, in the command's own scope, so the adapters' functions stay visible to the blocks
        # they register (core/Transcript.ps1, Get-HordeTranscriptAdapterFiles).
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "ReadShared", "Home", "Transcript", "Price", "Metrics", "MetricsStore", "MetricsReport")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        foreach ($a in (Get-HordeTranscriptAdapterFiles -Root $root)) { . $a }
        # A window bound must carry its zone: a time with none cannot be placed (core/Tristate.ps1).
        $fromAt = $null; $toAt = $null
        if ($From -ne "") { $fromAt = ConvertTo-HordeUtcTime $From; if ($null -eq $fromAt) { throw ("-From must be a time with a zone, such as 2026-09-30T00:00:00Z, not '" + $From + "'") } }
        if ($To -ne "") { $toAt = ConvertTo-HordeUtcTime $To; if ($null -eq $toAt) { throw ("-To must be a time with a zone, such as 2026-09-30T15:36:39Z, not '" + $To + "'") } }
        $result = Invoke-HordeMetricsSummarize -Path $Path -From $fromAt -To $toAt
        if ($Json) {
            ConvertTo-Json -InputObject @($result.rows | ForEach-Object { $_.record }) -Depth 30
            return
        }
        Format-HordeMetricsSummary -Result $result | ForEach-Object { Write-Output $_ }
    }
}
