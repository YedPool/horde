# Mutations of agents/claude-code/agent.json (engines E2).
# Run: powershell -File tools\Mutate.ps1 -Spec agents\claude-code\test\mutations\agent-descriptor.psd1
# Each changes one fact a later step relies on; agents\claude-code\test\test-agent-descriptor.ps1 must fail for every one.
@{
    Target = "agents\claude-code\agent.json"
    Suite  = "agents\claude-code\test\test-agent-descriptor.ps1"
    Mutations = @(
        @{ Name = "owned-api-key-misspelt"
           Find = '"name": "ANTHROPIC_API_KEY"'
           Replace = '"name": "ANTHROPIC_API_KEX"' }
        @{ Name = "remote-name-unverified"
           Find = '"session.remoteName": { "support": "yes"'
           Replace = '"session.remoteName": { "support": "unverified"' }
        @{ Name = "second-protocol"
           Find = '"protocols": ["anthropic-messages"]'
           Replace = '"protocols": ["anthropic-messages", "openai-chat"]' }
        @{ Name = "provider-select-claimed"
           Find = '"provider-select": { "support": "unverified"'
           Replace = '"provider-select": { "support": "yes"' }
        @{ Name = "pattern-unanchored-at-start"
           Find = '"sessionIdPattern": "^[0-9a-fA-F]{8}'
           Replace = '"sessionIdPattern": "[0-9a-fA-F]{8}' }
    )
}
