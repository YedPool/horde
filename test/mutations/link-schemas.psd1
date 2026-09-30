# Mutations of the link schemas. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\link-schemas.psd1
# and the same for link-frame (below, a second spec, because a spec has one target).
# Each mutation loosens one rule in schema/link-verbs.v1.json's text, and test\test-link-contracts.ps1
# must fail for every one. Every find string occurs exactly once, and on one line, so a CRLF checkout
# matches it too.
@{
    Target = "schema\link-verbs.v1.json"
    Suite  = "test\test-link-contracts.ps1"
    Mutations = @(
        @{ Name = "effect-not-required"
           Find = '"required": ["name", "direction", "effect", "since", "args", "result"],'
           Replace = '"required": ["name", "direction", "since", "args", "result"],' }
        @{ Name = "effect-class-widened"
           Find = '"effect": { "type": "string", "enum": ["read", "write", "spawn", "kill"] },'
           Replace = '"effect": { "type": "string", "enum": ["read", "write", "spawn", "kill", "delete"] },' }
        @{ Name = "handoff-document-raised-to-text"
           Find = '"document": { "type": "string", "pattern": "\\S", "x-horde-cap": "summaryBytes" }'
           Replace = '"document": { "type": "string", "pattern": "\\S", "x-horde-cap": "textBytes" }' }
        @{ Name = "worktree-name-any-text"
           Find = '"worktree-name": { "type": "string", "pattern": "^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$",'
           Replace = '"worktree-name": { "type": "string", "pattern": "^.{1,100}$",' }
        @{ Name = "token-any-text"
           Find = '"token": { "type": "string", "pattern": "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$",'
           Replace = '"token": { "type": "string", "pattern": "^.{1,64}$",' }
        @{ Name = "spawn-close-on-optional"
           Find = '"required": ["label", "role", "runId", "profile", "repoId", "worktree", "prompt", "closeOn"],'
           Replace = '"required": ["label", "role", "runId", "profile", "repoId", "worktree", "prompt"],' }
        @{ Name = "clone-status-branch-bare"
           Find = '"branch": { "$ref": "#/definitions/answer-token" },'
           Replace = '"branch": { "$ref": "#/definitions/token" },' }
    )
}
