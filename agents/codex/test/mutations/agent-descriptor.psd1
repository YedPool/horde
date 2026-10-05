# Mutations of agents/codex/agent.json (engines E2).
# Run: powershell -File tools\Mutate.ps1 -Spec agents\codex\test\mutations\agent-descriptor.psd1
# Each changes one fact a later step relies on; agents\codex\test\test-agent-descriptor.ps1 must fail for every one.
@{
    Target = "agents\codex\agent.json"
    Suite  = "agents\codex\test\test-agent-descriptor.ps1"
    Mutations = @(
        @{ Name = "name-flag-claimed"
           Find = '"name-at-spawn": { "support": "no"'
           Replace = '"name-at-spawn": { "support": "yes"' }
        @{ Name = "remote-name-claimed"
           Find = '"session.remoteName": { "support": "unverified"'
           Replace = '"session.remoteName": { "support": "yes"' }
        @{ Name = "inject-unmeasured-again"
           Find = '"message-inject": { "support": "yes"'
           Replace = '"message-inject": { "support": "unverified"' }
        @{ Name = "receipt-unmeasured-again"
           Find = '"delivery-receipt": { "support": "yes"'
           Replace = '"delivery-receipt": { "support": "unverified"' }
        @{ Name = "stop-caveat-dropped"
           Find = 'measured firing only on a turn that completes'
           Replace = 'measured firing at every turn end' }
        @{ Name = "native-provider-changed"
           Find = '"nativeProvider": "openai"'
           Replace = '"nativeProvider": "anthropic"' }
        @{ Name = "bypass-spelt-as-another-harness"
           Find = '"argv": ["--dangerously-bypass-approvals-and-sandbox"]'
           Replace = '"argv": ["--dangerously-skip-permissions"]' }
        @{ Name = "plan-may-escalate"
           Find = '"argv": ["--sandbox", "read-only", "--ask-for-approval", "never"]'
           Replace = '"argv": ["--sandbox", "read-only", "--ask-for-approval", "on-request"]' }
        @{ Name = "edits-keeps-temp-writable"
           Find = '"on-request", "-c", "sandbox_workspace_write.exclude_tmpdir_env_var=true", "-c", "sandbox_workspace_write.exclude_slash_tmp=true"]'
           Replace = '"on-request"]' }
        @{ Name = "edits-precondition-dropped"
           Find = '"preconditions": [{"name": "windows-sandbox-configured"'
           Replace = '"preconditionsX": [{"name": "windows-sandbox-configured"' }
        @{ Name = "plan-offered-headless"
           Find = '"argv": ["--sandbox", "read-only", "--ask-for-approval", "never"], "entryPoints": ["interactive"]'
           Replace = '"argv": ["--sandbox", "read-only", "--ask-for-approval", "never"], "entryPoints": ["interactive", "headless"]' }
        # Issue #67, item 3: a mapping whose preconditions are emptied would be used where it does not hold.
        @{ Name = "edits-preconditions-emptied"
           Find = '"argv": ["--sandbox", "workspace-write", "--ask-for-approval", "on-request", "-c", "sandbox_workspace_write.exclude_tmpdir_env_var=true", "-c", "sandbox_workspace_write.exclude_slash_tmp=true"], "entryPoints": ["interactive"], "evidence": "-s workspace-write, -a on-request and -c in --help 0.159.2 (2026-10-02); the two exclude keys are in the installed codex.exe (27 occurrences each). Without them workspace-write also makes the TEMP folder and /tmp writable unasked (review r60, F2), which is more than edits allows", "readback": "sandbox workspace-write with exactly one writable root, the working folder, from codex <fragment> debug prompt-input, 0.159.2, CODEX_HOME redirected to a scratch folder, 2026-10-02 (agents/codex/test/test-permission-readback.ps1) with sandbox = \"elevated\"; the same start without the two -c settings read back the working folder, :slash_tmp and :tmpdir", "preconditions": [{"name": "windows-sandbox-configured", "evidence": "without a [windows] sandbox setting in CODEX_HOME''s config.toml, workspace-write is silently read-only: codex <fragment> debug prompt-input, 0.159.2, CODEX_HOME redirected to a scratch folder, 2026-10-02 (agents/codex/test/test-permission-readback.ps1) read back sandbox read-only with a plain home, and workspace-write with sandbox = \"elevated\"; only elevated was measured"}]'
           Replace = '"argv": ["--sandbox", "workspace-write", "--ask-for-approval", "on-request", "-c", "sandbox_workspace_write.exclude_tmpdir_env_var=true", "-c", "sandbox_workspace_write.exclude_slash_tmp=true"], "entryPoints": ["interactive"], "evidence": "-s workspace-write, -a on-request and -c in --help 0.159.2 (2026-10-02); the two exclude keys are in the installed codex.exe (27 occurrences each). Without them workspace-write also makes the TEMP folder and /tmp writable unasked (review r60, F2), which is more than edits allows", "readback": "sandbox workspace-write with exactly one writable root, the working folder, from codex <fragment> debug prompt-input, 0.159.2, CODEX_HOME redirected to a scratch folder, 2026-10-02 (agents/codex/test/test-permission-readback.ps1) with sandbox = \"elevated\"; the same start without the two -c settings read back the working folder, :slash_tmp and :tmpdir"' }
    )
}
