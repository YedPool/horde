# Mutations of core/ServiceHostPort.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\service-host-port.psd1
# Each lets the port pass on something that is not an answer, or take a launch it should refuse;
# test\test-services-tend.ps1 must fail for every one.
@{
    Target = "core\ServiceHostPort.ps1"
    Suite  = "test\test-services-tend.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "any-adapter-applies"
           Find = '        if ($here -is [bool] -and $here) { return (New-HordeKnown -Value $a) }'
           Replace = '        return (New-HordeKnown -Value $a)' }
        @{ Name = "no-adapter-is-idle"
           Find = '    if ($found.state -cne "known") { return (New-HordeUnknown -Reason ($What + ": " + $found.reason)) }'
           Replace = '    if ($found.state -cne "known") { return (New-HordeKnown -Value 999999) }' }
        @{ Name = "throwing-adapter-throws"
           Find = 'catch { return (New-HordeUnknown -Reason ($What + ": the " + $found.value.name + " adapter failed") -ErrorRecord $_) }'
           Replace = 'catch { throw }' }
        @{ Name = "non-answer-passed-on"
           Find = '    if (-not (Test-HordeAnswer $answer) -or $Allowed -cnotcontains $answer.state) {'
           Replace = '    if ($false) {' }
        @{ Name = "negative-idle-accepted"
           Find = '    if (($answer.value -isnot [int] -and $answer.value -isnot [long]) -or $answer.value -lt 0) {'
           Replace = '    if ($false) {' }
        @{ Name = "start-without-start-time-accepted"
           Find = ' -or $v.pid -le 0 -or $v.startedAt -isnot [datetime]) {'
           Replace = ' -or $v.pid -le 0) {' }
        @{ Name = "start-takes-any-object"
           Find = 'if ($null -eq $Launch -or @($Launch.PSObject.TypeNames) -notcontains "Horde.ServiceLaunch") { throw "-Launch must be made by New-HordeServiceLaunch" }'
           Replace = '' }
        @{ Name = "close-with-no-window"
           Find = '    if ($ProcessId -le 0 -or $Handle -le 0) { return (New-HordeUnknown -Reason "closing its window: no process and window were named") }'
           Replace = '' }
        @{ Name = "missing-close-is-called"
           Find = '    if ($null -eq $run) { return (New-HordeUnknown -Reason ($What + ": the " + $found.value.name + " adapter cannot do that")) }'
           Replace = '    if ($null -eq $run) { return (New-HordeKnown -Value "asked") }' }
        @{ Name = "launch-parameter-names-unchecked"
           Find = 'foreach ($n in @(@($table.Keys) + @($Switches))) { if ("" + $n -cnotmatch ''\A[A-Za-z][A-Za-z0-9]{0,39}\z'') {'
           Replace = 'foreach ($n in @(@($table.Keys) + @($Switches))) { if ($false) {' }
        @{ Name = "launch-environment-names-unchecked"
           Find = 'foreach ($k in @($Environment.Keys)) { if ("" + $k -cnotmatch ''\A[A-Z_][A-Z0-9_]*\z'') {'
           Replace = 'foreach ($k in @($Environment.Keys)) { if ($false) {' }
        @{ Name = "launch-words-unchecked"
           Find = 'foreach ($w in @($Words)) { if ("" + $w -cnotmatch ''\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z'') {'
           Replace = 'foreach ($w in @($Words)) { if ($false) {' }
        @{ Name = "launch-control-characters-allowed"
           Find = '{ if ("" + $v -match ''\p{Cc}'') { throw "a launch''s values cannot hold a line break or any other control character" } }'
           Replace = '{ }' }
        @{ Name = "launch-relative-script"
           Find = '        if (-not [System.IO.Path]::IsPathRooted($Script) -or @($Words).Count -lt 1) {'
           Replace = '        if (@($Words).Count -lt 1) {' }
        @{ Name = "quote-not-escaped"
           Find = 'if ($c -eq ''"'') { [void]$sb.Append([char]92, (2 * $slashes + 1)); [void]$sb.Append(''"''); $slashes = 0; continue }'
           Replace = 'if ($c -eq ''"'') { [void]$sb.Append([char]92, $slashes); [void]$sb.Append(''"''); $slashes = 0; continue }' }
        @{ Name = "trailing-backslash-eats-the-quote"
           Find = '    if ($slashes -gt 0) { [void]$sb.Append([char]92, (2 * $slashes)) }'
           Replace = '    if ($slashes -gt 0) { [void]$sb.Append([char]92, $slashes) }' }
        @{ Name = "spaces-not-quoted"
           Find = '    if ($Text.Length -gt 0 -and $Text -notmatch ''[\s"]'') { return $Text }'
           Replace = '    if ($Text.Length -gt 0) { return $Text }' }
        # --- safety review of the first build ---
        @{ Name = "batch-file-launched"
           Find = 'if ($Program -match ''\.(cmd|bat)\s*\z'') { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "relative-exit-file-taken"
           Find = 'if ($ExitFile -ne "" -and -not [System.IO.Path]::IsPathRooted($ExitFile)) {'
           Replace = 'if ($false) {' }
        # --- the supervisor runs whether or not anyone is signed in (2026-10-14) ---
        @{ Name = "desktop-any-answer-is-here"
           Find = 'if ($answer.value -isnot [string] -or $answer.value -cne "here") {'
           Replace = 'if ($false) {' }
        @{ Name = "desktop-block-dropped"
           Find = 'closeWindow = $CloseWindow; desktop = $Desktop })'
           Replace = 'closeWindow = $CloseWindow; desktop = $null })' }
    )
}
