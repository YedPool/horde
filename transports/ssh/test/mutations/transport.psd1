# Mutations of the ssh transport's adapter. Run: powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\transport.psd1
# Each breaks one rule transports\ssh\Transport.ps1 holds; transports\ssh\test\test-ssh.ps1 must fail for every one.
# No mutant here can reach a real server: the suite dials only a closed loopback port and its own
# stand-in children, and a mutant that adds a program start does so behind if ($false).
@{
    Target = "transports\ssh\Transport.ps1"
    Suite  = "transports\ssh\test\test-ssh.ps1"
    Mutations = @(
        @{ Name = "exe-found-through-path"
           Find = '$p = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh.exe")'
           Replace = '$p = "" + (Get-Command ssh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source' }
        @{ Name = "key-absent-accepted"
           Find = 'if (-not (Test-Path -LiteralPath $Paths.identity -PathType Leaf)) {'
           Replace = 'if ($false) {' }
        @{ Name = "known-hosts-absent-accepted"
           Find = 'if (-not (Test-Path -LiteralPath $Paths.knownHosts -PathType Leaf)) {'
           Replace = 'if ($false) {' }
        @{ Name = "config-absent-accepted"
           Find = 'if (-not (Test-Path -LiteralPath $Paths.config -PathType Leaf)) {'
           Replace = 'if ($false) {' }
        @{ Name = "config-directive-accepted"
           Find = 'if ($t -ne "" -and -not $t.StartsWith("#")) {'
           Replace = 'if ($false) {' }
        @{ Name = "exit-255-read-as-a-close"
           Find = '$st.process.ExitCode -eq $script:HordeSshExitTransportError'
           Replace = '$false' }
        @{ Name = "every-exit-a-transport-error"
           Find = '$st.process.ExitCode -eq $script:HordeSshExitTransportError'
           Replace = '$true' }
        # --- stderr is bounded (review of PR #68, F3)
        @{ Name = "reason-not-capped"
           Find = 'if ($clean.Length -gt $script:HordeSshReasonChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "control-characters-kept"
           Find = "`$clean = (`$l -replace '[^\x20-\x7E]', '?').Trim()"
           Replace = '$clean = $l.Trim()' }
        @{ Name = "all-of-stderr-kept"
           Find = '$take = [Math]::Min($script:HordeSshStderrKeepBytes - $State.errKept.Count, $n)'
           Replace = '$take = $n' }
        @{ Name = "stderr-not-drained-while-waiting"
           Find = 'if ($null -ne $st.errTask) { $waitOn += $st.errTask }'
           Replace = '' }
        # --- paths ssh would read differently (F2)
        @{ Name = "open-takes-an-unsafe-path"
           Find = 'if ($why -ne "") { return (New-HordeSshResult -Ok $false -Reason $why) }'
           Replace = '' }
        @{ Name = "stdin-buffered"
           Find = '[System.IO.FileAccess]::Write, 1, $false)'
           Replace = '[System.IO.FileAccess]::Write, 4096, $false)' }
        @{ Name = "probe-takes-any-banner"
           Find = 'if ($line.StartsWith($pfx, [System.StringComparison]::Ordinal)) {'
           Replace = 'if ($true) {' }
        @{ Name = "probe-refused-is-unknown"
           Find = 'return (New-HordeKnown -Value $false)'
           Replace = 'return (New-HordeUnknown -Reason "refused")' }
        @{ Name = "listen-pretends"
           Find = 'return [pscustomobject]@{ ok = $false; listener = $null; reason = $script:HordeSshHubSide }'
           Replace = 'return [pscustomobject]@{ ok = $true; listener = @{}; reason = "" }' }
        # R17c-3: the pin is shown live, so the peer is claimed verified; a link that does not say so
        # would make every caller distrust a hub ssh.exe already checked.
        @{ Name = "peer-not-claimed-verified"
           Find = 'verified = $true'
           Replace = 'verified = $false' }
        @{ Name = "a-second-program-start"
           Find = 'return (Test-HordeSshBanner -Endpoint $Endpoint)'
           Replace = 'if ($false) { $null = [System.Diagnostics.Process]::Start("cmd.exe") }; return (Test-HordeSshBanner -Endpoint $Endpoint)' }
        @{ Name = "a-call-with-ampersand"
           Find = 'return (Test-HordeSshBanner -Endpoint $Endpoint)'
           Replace = 'return (& Test-HordeSshBanner -Endpoint $Endpoint)' }
        # --- no orphan: Open hands ssh.exe to the link or stops it (F7)
        @{ Name = "process-left-on-failure"
           Find = 'if ($null -ne $job) { $job.Dispose() }'
           Replace = '' }
        @{ Name = "process-not-put-in-the-job"
           Find = 'try { [HordeSshNative]::Assign($Job, $started.Handle) }'
           Replace = 'try { }' }
        @{ Name = "process-counted-handed-too-early"
           Find = '$handed = $false'
           Replace = '$handed = $true' }
        @{ Name = "stopped-without-the-start-time"
           Find = 'if ($now.StartTime -ne $StartedAt) { return }'
           Replace = '' }
        # --- round 2 of the review (F4): each harmless if it runs, each refused by the guard
        @{ Name = "round2-lowercase-second-caller"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Zz { start-hordesshprocess -Arguments "/c echo" }' }
        @{ Name = "round2-using-statement"
           Find = '. (Join-Path $PSScriptRoot "Argv.ps1")'
           Replace = 'using namespace System.Text; . (Join-Path $PSScriptRoot "Argv.ps1")' }
        @{ Name = "round2-requires"
           Find = '. (Join-Path $PSScriptRoot "Argv.ps1")'
           Replace = '#requires -Version 5.1
. (Join-Path $PSScriptRoot "Argv.ps1")' }
        @{ Name = "round2-psscriptroot-reassigned"
           Find = '. (Join-Path $PSScriptRoot "Argv.ps1")'
           Replace = '$PSScriptRoot = $PSScriptRoot; . (Join-Path $PSScriptRoot "Argv.ps1")' }
        @{ Name = "round2-filename-assigned"
           Find = '$psi.UseShellExecute = $false'
           Replace = '$psi.FileName = $psi.FileName; $psi.UseShellExecute = $false' }
        @{ Name = "round2-arguments-assigned"
           Find = '$psi.UseShellExecute = $false'
           Replace = '$psi.Arguments = $psi.Arguments; $psi.UseShellExecute = $false' }
        # --- round 3 (F4): the broad classes, each harmless if it runs
        @{ Name = "round3-nested-function"
           Find = '$psi = [System.Diagnostics.ProcessStartInfo]::new('
           Replace = 'function Get-HordeSshInner { 1 }; $psi = [System.Diagnostics.ProcessStartInfo]::new(' }
        @{ Name = "round3-function-not-hordessh-named"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Get-Probe { 1 }' }
        @{ Name = "round3-function-defined-twice"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function New-HordeSshResult { param([bool]$Ok, $Channel = $null, $Peer = $null, [string]$Reason = "") return [pscustomobject]@{ ok = $Ok; channel = $Channel; peer = $Peer; listener = $null; reason = $Reason } }' }
        @{ Name = "round3-function-drive"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; ${function:Get-HordeSshPaths} = ${function:Get-HordeSshPaths}' }
        @{ Name = "round3-alias-drive"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; ${alias:Zz-HordeSshProbe} = "Get-Date"' }
        @{ Name = "round3-variable-drive"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; ${variable:hordeSshProbe} = 1' }
        @{ Name = "round3-add-type-outside-native"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; Add-Type -TypeDefinition "public class HordeSshProbeZz {}"' }
        @{ Name = "round2-environment-assigned"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; $env:HORDE_GUARD_PROBE = "x"' }
        @{ Name = "round2-setup-not-canonical"
           Find = '$psi = [System.Diagnostics.ProcessStartInfo]::new([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh.exe"), $Arguments)'
           Replace = '$psi = [System.Diagnostics.ProcessStartInfo]::new([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh.exe"), ($Arguments))' }
        # --- the review's 12 forms that passed the first guard (F4), each appended where nothing runs it
        @{ Name = "review-bare-ssh-exe"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Zz { ssh.exe -o ProxyCommand=calc.exe h }' }
        @{ Name = "review-alias-start"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Zz { start ssh.exe }' }
        @{ Name = "review-alias-saps"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Zz { saps ssh.exe }' }
        @{ Name = "review-quoted-member"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Zz { $p = New-Object System.Diagnostics.Process; $p."Start"() }' }
        @{ Name = "review-variable-member"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Zz { $m = "Start"; $p = New-Object System.Diagnostics.Process; $p.$m() }' }
        @{ Name = "review-com-run"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Zz { (New-Object -ComObject WScript.Shell).Run("calc") }' }
        @{ Name = "review-dot-invoked-block"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Zz { . ([scriptblock]::Create("calc")) }' }
        @{ Name = "review-scriptblock-invoke"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Zz { [scriptblock]::Create("calc").Invoke() }' }
        @{ Name = "review-invoke-command"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Zz { Invoke-Command -ScriptBlock { calc } }' }
        @{ Name = "review-alias-to-start-function"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; Set-Alias Zz Start-HordeSshProcess; function Yy { Zz -FilePath "C:\x\ssh.exe" -Arguments "" }' }
        @{ Name = "review-cmd-exe"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Zz { cmd.exe /c calc }' }
        @{ Name = "review-execution-context"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Zz { $ExecutionContext.InvokeCommand.InvokeScript("calc") }' }
        @{ Name = "review-control-second-start"
           Find = '$script:HordeSshFolder = $PSScriptRoot'
           Replace = '$script:HordeSshFolder = $PSScriptRoot; function Zz { [System.Diagnostics.Process]::Start("ssh.exe") }' }
        @{ Name = "border-line-taken-as-reason"
           Find = 'if ($clean -notmatch ''[A-Za-z0-9]'') { continue }'
           Replace = '' }
        # --- the first live mesh link (2026-10-11): an ssh session's fd state is not passed on to ssh.exe
        @{ Name = "fd-state-passed-on"
           Find = 'if ("$name" -match $script:HordeSshInheritedFdState) {'
           Replace = 'if ($false) {' }
        @{ Name = "fd-state-match-too-broad"
           Find = '''\A[0-9A-Fa-f]{32}_POSIX_FD_STATE\z'''
           Replace = '''_POSIX_FD_STATE\z''' }
    )
}
