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
        @{ Name = "inject-claimed"
           Find = '"message-inject": { "support": "unverified"'
           Replace = '"message-inject": { "support": "yes"' }
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
    )
}
