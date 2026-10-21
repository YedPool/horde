$HordeCommand = @{
    name    = "metrics"
    group   = "metrics"
    sustained = $true
    usage   = "metrics summarize <transcript-or-folder> [-From <UTC time>] [-To <UTC time>] [-Json] | metrics collect [-SettleMinutes <n>] [-MaxFiles <n>] [-MaxSeconds <n>] [-IncludeLarge] | metrics schedule install|remove|status [-TaskName <name>] [-TaskFolder Horde|HordeTest] [-Disabled] [-TakeOver]"
    summary = "summarize: read agent transcripts and print each worker's time, tokens, tool calls, silences and notional cost, and an orchestrator's still-waiting calls; collect: record every new or changed transcript; schedule: run collect every 30 minutes. Nothing is recorded unless metrics are enabled"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("summarize", "collect", "schedule")][string]$Verb,
            [Parameter(Position = 1)][string]$Target,
            [string]$From,
            [string]$To,
            [switch]$Json,
            [int]$SettleMinutes = 10,
            [int]$MaxFiles = 0,
            [int]$MaxSeconds = 900,
            [switch]$IncludeLarge,
            [string]$TaskName = "Horde metrics collect",
            [ValidateSet("Horde", "HordeTest")][string]$TaskFolder = "Horde",
            [switch]$Disabled,
            [switch]$TakeOver
        )
        # Loaded here, in the command's own scope, so the adapters' and schedulers' functions stay
        # visible to the blocks they register (core/Transcript.ps1, Get-HordeTranscriptAdapterFiles).
        # A flag meant for another verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        $verbFlags = @{ summarize = @("From", "To", "Json"); collect = @("SettleMinutes", "MaxFiles", "MaxSeconds", "IncludeLarge"); schedule = @("TaskName", "TaskFolder", "Disabled", "TakeOver") }
        foreach ($k in @($verbFlags.Keys)) {
            if ($k -eq $Verb) { continue }
            foreach ($flag in $verbFlags[$k]) { if ($PSBoundParameters.ContainsKey($flag)) { throw ("-" + $flag + " belongs to metrics " + $k + ", not metrics " + $Verb) } }
        }
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "ReadShared", "Home", "Transcript", "Price", "Metrics", "MetricsStore", "MetricsReport", "MetricsCollect", "Schedule")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        foreach ($a in (Get-HordeTranscriptAdapterFiles -Root $root)) { . $a }
        foreach ($s in (Get-HordeSchedulerFiles)) { . $s }

        if ($Verb -eq "collect") {
            if ($Target -ne "") { throw ("collect takes no path: it finds transcripts in every engine's declared stores, not '" + $Target + "'") }
            $result = Invoke-HordeMetricsCollect -SettleMinutes $SettleMinutes -MaxFiles $MaxFiles -MaxSeconds $MaxSeconds -IncludeLarge:$IncludeLarge
            Format-HordeMetricsCollect -Result $result | ForEach-Object { Write-Output $_ }
            # A refused gate is a failure a scheduler's log should show; off and busy are not.
            if ($result.state -eq "refused") { throw $result.reason }
            return
        }
        if ($Verb -eq "schedule") {
            if (@("install", "remove", "status") -cnotcontains $Target) { throw ("schedule takes install, remove or status, not '" + $Target + "'") }
            Invoke-HordeMetricsSchedule -Action $Target -TaskName $TaskName -Folder $TaskFolder -Disabled:$Disabled -TakeOver:$TakeOver -HordeScript (Join-Path $root "horde.ps1") | ForEach-Object { Write-Output $_ }
            return
        }

        if ($Target -eq "") { throw "summarize needs a transcript or a folder of them" }
        # A window bound must carry its zone: a time with none cannot be placed (core/Tristate.ps1).
        $fromAt = $null; $toAt = $null
        if ($From -ne "") { $fromAt = ConvertTo-HordeUtcTime $From; if ($null -eq $fromAt) { throw ("-From must be a time with a zone, such as 2026-09-30T00:00:00Z, not '" + $From + "'") } }
        if ($To -ne "") { $toAt = ConvertTo-HordeUtcTime $To; if ($null -eq $toAt) { throw ("-To must be a time with a zone, such as 2026-09-30T15:36:39Z, not '" + $To + "'") } }
        $result = Invoke-HordeMetricsSummarize -Path $Target -From $fromAt -To $toAt
        if ($Json) {
            ConvertTo-Json -InputObject @($result.rows | ForEach-Object { $_.record }) -Depth 30
            return
        }
        Format-HordeMetricsSummary -Result $result | ForEach-Object { Write-Output $_ }
    }
}
