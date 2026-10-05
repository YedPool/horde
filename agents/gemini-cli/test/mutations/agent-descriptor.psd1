# Mutations of agents/gemini-cli/agent.json (engines E2).
# Run: powershell -File tools\Mutate.ps1 -Spec agents\gemini-cli\test\mutations\agent-descriptor.psd1
# Each changes one fact a later step relies on; agents\gemini-cli\test\test-agent-descriptor.ps1 must fail for every one.
@{
    Target = "agents\gemini-cli\agent.json"
    Suite  = "agents\gemini-cli\test\test-agent-descriptor.ps1"
    Mutations = @(
        @{ Name = "inject-claimed"
           Find = '"message-inject": { "support": "unverified"'
           Replace = '"message-inject": { "support": "yes"' }
        @{ Name = "hook-claimed-before-seen"
           Find = '"turn-ended": { "hook": "AfterAgent", "support": "unverified"'
           Replace = '"turn-ended": { "hook": "AfterAgent", "support": "yes"' }
        @{ Name = "events-swapped"
           Find = '"turn-started": { "hook": "BeforeAgent"'
           Replace = '"turn-started": { "hook": "AfterAgent"' }
        @{ Name = "second-protocol"
           Find = '"protocols": ["google-genai"]'
           Replace = '"protocols": ["google-genai", "openai-chat"]' }
        @{ Name = "edits-mapped-to-yolo"
           Find = '"argv": ["--approval-mode", "auto_edit"]'
           Replace = '"argv": ["--approval-mode", "yolo"]' }
        # Issue #67, item 3: a mapping whose preconditions are emptied would be used where it does not hold.
        @{ Name = "plan-preconditions-emptied"
           Find = '"argv": ["--approval-mode", "plan"], "entryPoints": ["interactive", "headless"], "evidence": "--approval-mode in --help 0.62.0 (2026-10-02), choice plan: read-only mode", "readback": "no override line in a trusted folder; Approval mode overridden to \"default\" because the current folder is not trusted in an untrusted one, from the stderr of gemini --approval-mode <mode> -p probe --debug, 0.62.0, HOME and USERPROFILE redirected and the endpoint a closed local port, 2026-10-02 (agents/gemini-cli/test/test-permission-readback.ps1). The CLI prints no effective mode; it prints a line when it overrides one, and the readback is that line''s presence or absence", "preconditions": [{"name": "folder-trusted", "evidence": "folder trust is on by default in 0.62.0 (review r60: security.folderTrust.enabled defaults to true); in a folder neither listed in the profile''s trustedFolders.json nor started with GEMINI_CLI_TRUST_WORKSPACE=true this mode is overridden to default, the ask mode, and only a debug line says so - measured 2026-10-02"}]'
           Replace = '"argv": ["--approval-mode", "plan"], "entryPoints": ["interactive", "headless"], "evidence": "--approval-mode in --help 0.62.0 (2026-10-02), choice plan: read-only mode", "readback": "no override line in a trusted folder; Approval mode overridden to \"default\" because the current folder is not trusted in an untrusted one, from the stderr of gemini --approval-mode <mode> -p probe --debug, 0.62.0, HOME and USERPROFILE redirected and the endpoint a closed local port, 2026-10-02 (agents/gemini-cli/test/test-permission-readback.ps1). The CLI prints no effective mode; it prints a line when it overrides one, and the readback is that line''s presence or absence"' }
    )
}
