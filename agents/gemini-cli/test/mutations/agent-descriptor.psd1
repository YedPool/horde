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
    )
}
