# Mutations of core/HostWindow.ps1, the port through which a terminal's adapter says which window a
# session is shown in. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\host-window.psd1
# test\test-session-seat.ps1 must fail for each.
@{
    Target = "core\HostWindow.ps1"
    Suite  = "test\test-session-seat.ps1"
    Mutations = @(
        @{ Name = "a-seat-with-no-pane-is-looked-for"
           Find = 'if ($null -eq $Seat -or "$($Seat.pane)".Trim() -eq "" -or "$($Seat.instance)".Trim() -eq "") {'
           Replace = 'if ($null -eq $Seat) {' }
        @{ Name = "no-finder-loaded-is-not-said"
           Find = 'if ($script:HordeHostWindowFinders.Count -eq 0) { return (New-HordeUnknown -Reason "no terminal adapter that can find a session''s window is loaded") }'
           Replace = 'if ($script:HordeHostWindowFinders.Count -eq 0) { return (New-HordeUnknown -Reason "the session has no window") }' }
        @{ Name = "a-finder-that-throws-stops-the-search"
           Find = 'try { $answer = & $finder.find $Seat } catch { [void]$said.Add($finder.name + ": its finder failed: " + $_.Exception.Message); continue }'
           Replace = 'try { $answer = & $finder.find $Seat } catch { return (New-HordeUnknown -Reason "a finder failed") }' }
        @{ Name = "anything-a-finder-prints-is-its-answer"
           Find = '$answer = @($answer) | Select-Object -Last 1'
           Replace = '$answer = @($answer) | Select-Object -First 1' }
        @{ Name = "text-taken-as-an-answer"
           Find = 'if (-not (Test-HordeAnswer $answer)) { [void]$said.Add($finder.name + ": its finder did not answer"); continue }'
           Replace = '' }
        @{ Name = "an-unknown-taken-as-a-window"
           Find = 'if ($answer.state -cne "known") { [void]$said.Add($finder.name + ": " + $answer.reason); continue }'
           Replace = '' }
        @{ Name = "a-window-with-no-handle-taken"
           Find = 'if (($handle -isnot [int] -and $handle -isnot [long]) -or [long]$handle -le 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-handle-of-zero-taken"
           Find = ' -or [long]$handle -le 0) {'
           Replace = ') {' }
        @{ Name = "a-finders-reason-loses-its-name"
           Find = 'if ($answer.state -cne "known") { [void]$said.Add($finder.name + ": " + $answer.reason); continue }'
           Replace = 'if ($answer.state -cne "known") { [void]$said.Add($answer.reason); continue }' }
        @{ Name = "registering-again-adds-a-second"
           Find = 'foreach ($f in @($script:HordeHostWindowFinders)) { if ($f.name -ceq $Name) { $script:HordeHostWindowFinders.Remove($f) } }'
           Replace = '' }
        @{ Name = "any-text-is-a-host-name"
           Find = 'if ($Name -cnotmatch ''\A[a-z][a-z0-9-]*\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "the-answer-does-not-say-which-host"
           Find = 'host = $finder.name; detail'
           Replace = 'host = ""; detail' }
        # --- the finders' own settings, asked through the port (Get-HordeSessionWindowSettingsState) ---
        @{ Name = "the-settings-are-not-registered"
           Find = 'find = $Find; settings = $Settings })'
           Replace = 'find = $Find; settings = $null })' }
        @{ Name = "the-home-is-not-handed-to-the-finder"
           Find = 'try { $given = & $finder.settings $HordeHome }'
           Replace = 'try { $given = & $finder.settings "" }' }
        @{ Name = "a-settings-reader-that-fails-is-silent"
           Find = 'catch { [void]$states.Add("refused"); [void]$found.Add($finder.name + ": reading its finder''s settings failed: " + $_.Exception.Message); continue }'
           Replace = 'catch { continue }' }
        @{ Name = "anything-a-settings-reader-prints-is-its-answer"
           Find = '$given = @($given) | Select-Object -Last 1'
           Replace = '$given = @($given) | Select-Object -First 1' }
        @{ Name = "a-settings-non-answer-is-taken"
           Find = 'if (@("defaults", "read", "refused") -cnotcontains $state) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-finders-files-are-not-said"
           Find = 'if ($null -ne $given.PSObject.Properties["path"] -and "$($given.path)" -ne "") { [void]$files.Add("" + $given.path) }'
           Replace = '' }
        @{ Name = "a-refusal-with-no-finding-is-silent"
           Find = 'if ($said.Count -eq 0) { $said = @($finder.name + ": its finder''s settings are refused, and say no reason") }'
           Replace = '' }
        @{ Name = "only-the-first-settings-finding-is-said"
           Find = 'foreach ($f in $said) { [void]$found.Add($f) }'
           Replace = '[void]$found.Add($said[0])' }
        @{ Name = "a-refused-finder-file-is-not-refused"
           Find = 'if ($states -ccontains "refused") { $overall = "refused" }'
           Replace = 'if ($false) { $overall = "refused" }' }
        @{ Name = "a-read-file-is-the-defaults"
           Find = 'elseif ($states -ccontains "read") { $overall = "read" }'
           Replace = 'elseif ($false) { $overall = "read" }' }
        @{ Name = "no-settings-at-all-is-the-defaults"
           Find = 'elseif ($states.Count -gt 0) { $overall = "defaults" }'
           Replace = 'else { $overall = "defaults" }' }
    )
}
