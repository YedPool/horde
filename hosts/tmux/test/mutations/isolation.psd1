# Mutations of the tmux isolation harness. Run: powershell -File tools\Mutate.ps1 -Spec hosts\tmux\test\mutations\isolation.psd1
# Each breaks one rule the harness depends on; hosts\tmux\test\test-isolation.ps1 must fail for every one of them.
# The suite starts no tmux server, so no mutant here can reach a real one: teardown's decisions run
# against the suite's fake transport, and the two real WSL calls it makes are read-only. What only a
# real server can show - that containment and the crash exit really hold - is mutated against the
# e2e in isolation-e2e.psd1.
# SECTIONS (tools\Mutate.ps1; issue #83): each mutant runs only the first section of
# hosts\tmux\test\test-isolation.ps1 whose checks failed for it in a whole-suite run of this spec on the
# always-on box (bd6cdb5, 2026-10-07).
@{
    Target = "hosts\tmux\test\Isolation.ps1"
    Suite  = "hosts\tmux\test\test-isolation.ps1"
    Mutations = @(
        # --- every tmux call names our socket, our directory, no config, and a scrubbed environment
        @{ Name = "argv-drops-socket-name"
           Find = '"tmux", "-L", $Entry.name, "-f", "/dev/null")'
           Replace = '"tmux", "-f", "/dev/null")'
           Sections = @("argv") }
        @{ Name = "argv-drops-no-config"
           Find = '"tmux", "-L", $Entry.name, "-f", "/dev/null")'
           Replace = '"tmux", "-L", $Entry.name)'
           Sections = @("argv") }
        @{ Name = "argv-drops-chdir-guard"
           Find = 'return @("env", "-C", $Entry.dir, "-u", "TMUX"'
           Replace = 'return @("env", "-u", "TMUX"'
           Sections = @("argv") }
        @{ Name = "argv-drops-private-tmpdir"
           Find = '("TMUX_TMPDIR=" + $Entry.dir),'
           Replace = ''
           Sections = @("argv") }
        @{ Name = "argv-keeps-linux-tmux-env"
           Find = '"-u", "TMUX", "-u", "TMUX_PANE", ("TMUX_TMPDIR="'
           Replace = '("TMUX_TMPDIR="'
           Sections = @("argv") }
        @{ Name = "argv-accepts-any-name"
           Find = '-or "$($Entry.name)" -ne ("horde-iso-" + $g)'
           Replace = ''
           Sections = @("argv") }
        @{ Name = "argv-accepts-any-dir"
           Find = '-or "$($Entry.dir)" -ne ("/tmp/horde-iso-" + $g)'
           Replace = ''
           Sections = @("argv") }
        @{ Name = "windows-env-not-scrubbed"
           Find = 'foreach ($v in @("TMUX", "TMUX_PANE", "WSLENV")) { if ($psi.EnvironmentVariables.ContainsKey($v)) { $psi.EnvironmentVariables.Remove($v) } }'
           Replace = ''
           Sections = @("inherited-tmux") }
        @{ Name = "wslenv-not-scrubbed"
           Find = 'foreach ($v in @("TMUX", "TMUX_PANE", "WSLENV")) {'
           Replace = 'foreach ($v in @("TMUX", "TMUX_PANE")) {'
           Sections = @("inherited-tmux") }

        # --- the WSL boundary
        @{ Name = "utf16-never-detected"
           Find = 'if ($nul * 3 -ge $Bytes.Length / 2)'
           Replace = 'if ($false)'
           Sections = @("wsl-boundary") }
        @{ Name = "exit-minus-one-not-a-wsl-failure"
           Find = 'if ($Result.code -eq -1) {'
           Replace = 'if ($false) {'
           Sections = @("wsl-boundary") }
        @{ Name = "missing-program-read-as-tmux"
           Find = "if (`$Result.err -match 'execvpe\((.*?)\) failed') {"
           Replace = 'if ($false) {'
           Sections = @("wsl-boundary") }
        @{ Name = "winarg-quote-not-escaped"
           Find = '[void]$sb.Append($bs, 2 * $slashes + 1)'
           Replace = '[void]$sb.Append($bs, 1)'
           Sections = @("wsl-boundary") }
        @{ Name = "winarg-trailing-backslash-not-doubled"
           Find = 'if ($slashes) { [void]$sb.Append($bs, 2 * $slashes) }'
           Replace = 'if ($slashes) { [void]$sb.Append($bs, $slashes) }'
           Sections = @("wsl-boundary") }
        @{ Name = "no-server-ignores-exit-code"
           Find = '$Result.code -eq 1 -and ($Result.err -match'
           Replace = '($Result.err -match'
           Sections = @("wsl-boundary") }

        # --- teardown kills only its own server
        @{ Name = "teardown-skips-identity-refusal"
           Find = 'if ($bad) { return (& $verdict $false $false @() $false $false $true ($bad + " - refusing to kill it")) }'
           Replace = ''
           Sections = @("teardown") }
        @{ Name = "identity-ignores-pid-and-start"
           Find = 'if ($parts[1] -ne "$($Entry.serverPid)" -or $parts[2] -ne "$($Entry.startTime)") {'
           Replace = 'if ($false) {'
           Sections = @("ours-isolated") }
        @{ Name = "identity-ignores-socket"
           Find = 'if ($parts[0] -cne "$($Entry.socket)") {'
           Replace = 'if ($false) {'
           Sections = @("ours-isolated") }
        @{ Name = "unknown-answer-not-refused"
           Find = '} elseif (-not (Test-HordeTmuxNoServer $id)) {'
           Replace = '} elseif ($false) {'
           Sections = @("teardown") }
        @{ Name = "gone-without-measuring"
           Find = 'if (Test-HordeTmuxNoServer $ls) { $gone = $true; break }'
           Replace = '$gone = $true; break'
           Sections = @("teardown") }
        @{ Name = "verdict-ignores-the-namespace"
           Find = '$survived = (-not $gone) -or ($inNs.Count -gt 0)'
           Replace = '$survived = (-not $gone)'
           Sections = @("teardown") }
        @{ Name = "unmeasured-owner-reads-as-stopped"
           Find = '$unmeasured = (-not $e.nsInode) -and (-not $ownerGone)'
           Replace = '$unmeasured = $false'
           Sections = @("teardown") }
        @{ Name = "unfinished-scan-reads-as-empty"
           Find = "if (`$r.code -ne 0 -or `$last -notmatch '^scanned ([1-9]\d*)$') {"
           Replace = 'if ($false) {'
           Sections = @("teardown") }
        @{ Name = "namespace-never-scanned"
           Find = 'if ($e.nsInode) { $inNs = @(Get-HordeTmuxNsProcs -Entry $e -TimeoutSeconds $TimeoutSeconds) }'
           Replace = ''
           Sections = @("teardown") }
        @{ Name = "cleanup-under-a-live-server"
           Find = 'if (-not $survived) {'
           Replace = 'if ($true) {'
           Sections = @("teardown") }
        @{ Name = "cleanup-deletes-recursively"
           Find = '[ -d "$sub" ] && rmdir -- "$sub" 2>/dev/null'
           Replace = '[ -d "$sub" ] && rm -rf -- "$sub" 2>/dev/null'
           Sections = @("teardown") }
        @{ Name = "cleanup-deletes-any-socket-file"
           Find = '[ -S "$sock" ] && rm -f -- "$sock"'
           Replace = 'rm -f -- "$sock"'
           Sections = @("teardown") }
        @{ Name = "token-not-spent"
           Find = '$script:HordeTmuxStarted.Remove("$($Instance.token)")'
           Replace = ''
           Sections = @("teardown") }
        @{ Name = "registry-reset-on-reload"
           Find = 'if ($null -eq $script:HordeTmuxStarted) { $script:HordeTmuxStarted = @{} }'
           Replace = '$script:HordeTmuxStarted = @{}'
           Sections = @("reload") }

        # --- containment: the server is pid 1's child in a pid namespace of its own
        @{ Name = "owner-without-pid-namespace"
           Find = '@("unshare", "--pid", "--fork", "--kill-child", "--mount-proc",'
           Replace = '@("unshare", "--fork", "--kill-child", "--mount-proc",'
           Sections = @("teardown") }
        @{ Name = "owner-not-killed-with-unshare"
           Find = '@("unshare", "--pid", "--fork", "--kill-child", "--mount-proc",'
           Replace = '@("unshare", "--pid", "--fork", "--mount-proc",'
           Sections = @("teardown") }
        @{ Name = "start-skips-containment-check"
           Find = 'if ($bad) { throw $bad }'
           Replace = ''
           Sections = @("teardown") }
        @{ Name = "assert-skips-containment-check"
           Find = '$bad = Test-HordeTmuxContained -Entry $e -Lines (Get-HordeTmuxNsProcs -Entry $e)'
           Replace = '$bad = $null'
           Sections = @("teardown") }
        @{ Name = "preflight-skips-unshare"
           Find = "command -v unshare >/dev/null 2>&1 || { echo `"unshare (util-linux) is not installed in the distro`" >&2; exit 3; }; command"
           Replace = 'command'
           Sections = @("preflight") }

        # --- start fails loudly and leaves nothing
        @{ Name = "start-adopts-existing-dir"
           Find = '@("mkdir", "-m", "700", "--", $e.dir)'
           Replace = '@("mkdir", "-p", "-m", "700", "--", $e.dir)'
           Sections = @("teardown") }
        @{ Name = "start-failure-leaks"
           Find = '[void](Stop-HordeIsolatedTmux -Instance $inst)'
           Replace = ''
           Sections = @("teardown") }
        @{ Name = "start-accepts-another-distro"
           Find = 'if ($Distro -and $resolved -ne $Distro) {'
           Replace = 'if ($false) {'
           Sections = @("teardown") }

        # --- the isolation decision
        @{ Name = "isolation-accepts-many-panes"
           Find = 'if ($p.Count -ne 1) {'
           Replace = 'if ($false) {'
           Sections = @("ours-isolated") }
        @{ Name = "isolation-accepts-many-sessions"
           Find = 'if ($s.Count -ne 1) {'
           Replace = 'if ($false) {'
           Sections = @("ours-isolated") }
        @{ Name = "isolation-reads-nothing-as-empty"
           Find = 'if ($s.Count -eq 0 -or $p.Count -eq 0) {'
           Replace = 'if ($false) {'
           Sections = @("ours-isolated") }
    )
}
