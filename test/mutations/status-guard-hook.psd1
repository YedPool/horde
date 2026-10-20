# Mutations of hooks/horde-status-guard.mjs, the filter half of the status guard hook. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\status-guard-hook.psd1
# Each breaks one rule of what the hook looks at or how it fails; test\test-status-guard-hook.ps1 must fail a check for every one.
@{
    Target = "hooks\horde-status-guard.mjs"
    Suite  = "test\test-status-guard-hook.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "stale-cards-checked"
           Find = 'const RECENT_MS = 120 * 1000;'
           Replace = 'const RECENT_MS = 100000000 * 1000;' }
        @{ Name = "retired-card-matched"
           Find = 'status\.txt$/i;'
           Replace = 'status\.[a-z.]+$/i;' }
        @{ Name = "path-match-case-sensitive"
           Find = 'status\.txt$/i;'
           Replace = 'status\.txt$/;' }
        @{ Name = "deep-folders-matched"
           Find = '[\\/]orcs[\\/][^\\/]+[\\/]status'
           Replace = '[\\/]orcs[\\/].+status' }
        @{ Name = "every-shell-command-checked"
           Find = '!/status\.txt/i.test(command)'
           Replace = '!/./i.test(command)' }
        @{ Name = "multiedit-ignored"
           Find = 'new Set(["Write", "Edit", "MultiEdit"])'
           Replace = 'new Set(["Write", "Edit"])' }
        @{ Name = "powershell-tool-ignored"
           Find = 'new Set(["Bash", "PowerShell"])'
           Replace = 'new Set(["Bash"])' }
        @{ Name = "orcs-root-env-ignored"
           Find = 'const env = process.env.HORDE_STATUS_ORCS_ROOT;'
           Replace = 'const env = null;' }
        @{ Name = "orcs-path-in-command-ignored"
           Find = 'if (isDir(root)) return root;'
           Replace = 'if (false) return root;' }
        @{ Name = "restore-scope-ignored"
           Find = 'restorable.join("*") || "-"'
           Replace = 'folders.join("*")' }
        @{ Name = "own-lane-not-restorable"
           Find = 'if (own) restorable.push(own);'
           Replace = 'if (false) restorable.push(own);' }
        @{ Name = "relative-path-not-resolved"
           Find = 'if (!STATUS_PATH.test(absolute(file, input.cwd))) return 0;'
           Replace = 'if (!STATUS_PATH.test(file)) return 0;' }
        @{ Name = "checker-failure-silent"
           Find = 'if (code !== 0 && code !== 3) {'
           Replace = 'if (false) {' }
        @{ Name = "rejection-not-exit-2"
           Find = 'return 2;'
           Replace = 'return 0;' }
    )
}
