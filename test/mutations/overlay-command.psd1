# Mutations of core/OverlayCommand.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\overlay-command.psd1
# Each breaks one rule of the one command Horde runs for the overlay; test\test-overlay.ps1 must fail for
# every one of them. No mutation here can run anything but the suite's own fake horde-overlay.cmd: the
# suite puts only its temp folder and System32 on PATH.
@{
    Target = "core\OverlayCommand.ps1"
    Suite  = "test\test-overlay.ps1"
    Mutations = @(
        @{ Name = "another-verb-sent"
           Find = '$psi.Arguments = "endpoint --name " + $Name + " --json"'
           Replace = '$psi.Arguments = "up --name " + $Name + " --json"' }
        @{ Name = "json-flag-dropped"
           Find = '$psi.Arguments = "endpoint --name " + $Name + " --json"'
           Replace = '$psi.Arguments = "endpoint --name " + $Name' }
        @{ Name = "failure-read-as-answer"
           Find = 'if ($p.ExitCode -ne 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "missing-command-unexplained"
           Find = 'if ($null -eq $cmd) { return (New-HordeUnknown -Reason "horde-overlay was not found on PATH, so the overlay cannot be asked") }'
           Replace = 'if ($null -eq $cmd) { return (New-HordeUnknown -Reason "the overlay cannot be asked") }' }
        @{ Name = "name-unchecked"
           Find = 'if ($Name -cnotmatch $script:HordeOverlayNamePattern) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "name-dollar-anchor"
           Find = '$script:HordeOverlayNamePattern = ''^[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z'''
           Replace = '$script:HordeOverlayNamePattern = ''^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$''' }
        @{ Name = "name-pattern-drifts-from-schema"
           Find = '$script:HordeOverlayNamePattern = ''^[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z'''
           Replace = '$script:HordeOverlayNamePattern = ''^[A-Za-z0-9][A-Za-z0-9._ &-]{0,63}\z''' }
        @{ Name = "timeout-unchecked"
           Find = 'if ($TimeoutSeconds -lt 1) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "any-program-run"
           Find = 'if (-not [System.IO.Path]::IsPathRooted($source) -or $source -notmatch $script:HordeOverlayProgramPattern) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "start-failure-throws"
           Find = 'try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return'
           Replace = 'try { $p = [System.Diagnostics.Process]::Start($psi) } catch { throw; return' }
        @{ Name = "error-line-dropped"
           Find = 'return (New-HordeUnknown -Reason ("horde-overlay exited " + $p.ExitCode + ": " + $line))'
           Replace = 'return (New-HordeUnknown -Reason ("horde-overlay exited " + $p.ExitCode))' }
        @{ Name = "silent-overlay-not-stopped"
           Find = 'try { if (-not $Process.HasExited) { $Process.Kill() } } catch { }'
           Replace = '' }
        @{ Name = "stopped-claimed-regardless"
           Find = 'if ($Process.HasExited) { return "the process it started was stopped'
           Replace = 'if ($true) { return "the process it started was stopped'
           Expect = "survives"
           Reason = "the claim is false only when Kill leaves the process running past 5 s, which no fake on this suite's PATH can be made to do; the line keeps the reason honest in that case" }
        @{ Name = "output-waited-on-without-deadline"
           Find = 'if (-not $read.Wait($left)) {'
           Replace = 'if (-not $read.Wait($left + 15000)) {' }
        @{ Name = "cap-unchecked"
           Find = 'if ($got.Length -gt $script:HordeOverlayCommandMaxBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "high-bytes-decoded-as-ascii"
           Find = '[System.Text.Encoding]::GetEncoding(28591).GetString($got.ToArray())'
           Replace = '[System.Text.Encoding]::ASCII.GetString($got.ToArray())' }
    )
}
