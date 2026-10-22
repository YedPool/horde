# Mutations of hooks/horde-merge-guard.mjs, the PreToolUse hook that refuses a hand-typed gh pr merge of
# YedPool/horde (T-0247). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\merge-guard-hook.psd1
# Each lets a hand merge through, refuses something that only mentions it, loses the message, or breaks the
# fail-open rule; test\test-merge-guard-hook.ps1 must fail a check for every one.
@{
    Target = "hooks\horde-merge-guard.mjs"
    Suite  = "test\test-merge-guard-hook.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "repo-flag-ignored"
           Find = 'if (repoFlag !== null) return repoOf(repoFlag) === GUARDED ? "pr" : null;'
           Replace = 'if (repoFlag !== null) return null;' }
        @{ Name = "repo-compare-loose"
           Find = 'return repoOf(repoFlag) === GUARDED ? "pr" : null;'
           Replace = 'return repoOf(repoFlag).includes("horde") ? "pr" : null;' }
        @{ Name = "repo-compare-case-sensitive"
           Find = 'return v.toLowerCase();'
           Replace = 'return v;' }
        @{ Name = "pull-request-url-ignored"
           Find = 'if (url) return "pr";'
           Replace = '' }
        @{ Name = "folder-remote-ignored"
           Find = 'if (horde === true) return "pr";'
           Replace = '' }
        @{ Name = "api-merge-endpoint-allowed"
           Find = 'return hit ? "api" : null;'
           Replace = 'return null;' }
        @{ Name = "help-text-refused"
           Find = 'if (args.some((a) => a === "--help" || a === "-h")) return null; // help text merges nothing'
           Replace = '' }
        @{ Name = "substitutions-not-read"
           Find = 'for (const sub of nested) {'
           Replace = 'for (const sub of []) {' }
        @{ Name = "shell-strings-not-read"
           Find = 'if (inner !== null) {'
           Replace = 'if (false) {' }
        @{ Name = "cd-not-followed"
           Find = 'if (target) where = resolve('
           Replace = 'if (false) where = resolve(' }
        @{ Name = "here-document-body-read"
           Find = 'if (d) heredocs.push(d);'
           Replace = '' }
        @{ Name = "comments-read"
           Find = 'if (c === "#" && !inWord) {'
           Replace = 'if (false) {' }
        @{ Name = "double-quotes-do-not-protect"
           Find = 'if (c === ''"'') {'
           Replace = 'if (false) {' }
        @{ Name = "here-string-body-read"
           Find = 'if (c === "@" && !inWord &&'
           Replace = 'if (false && !inWord &&' }
        @{ Name = "bad-json-refuses"
           Find = 'logLine("stdin parse failed: " + e.message); return 0; }'
           Replace = 'logLine("stdin parse failed: " + e.message); return 2; }' }
        @{ Name = "refusal-says-nothing"
           Find = 'process.stderr.write(MESSAGE);'
           Replace = '' }
        @{ Name = "message-names-no-command"
           Find = 'Use: horde merge OWNER/REPO#N'
           Replace = 'Use the other command OWNER/REPO#N' }
        @{ Name = "powershell-tool-not-watched"
           Find = 'const SHELL_TOOLS = new Set(["Bash", "PowerShell"]);'
           Replace = 'const SHELL_TOOLS = new Set(["Bash"]);' }
        @{ Name = "gh-exe-not-gh"
           Find = '.replace(/\.(exe|cmd|bat|ps1)$/, "")'
           Replace = '.replace(/\.(cmd|bat|ps1)$/, "")' }
        @{ Name = "env-prefix-not-skipped"
           Find = ' || /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[k])'
           Replace = '' }
        @{ Name = "start-process-not-read"
           Find = 'if (flat.length && programName(flat[0]) === "gh") {'
           Replace = 'if (false) {' }
    )
}
