# Mutations of the link schemas. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\link-schemas.psd1
# and the same for link-frame (below, a second spec, because a spec has one target).
# Each mutation loosens one rule in schema/link-verbs.v1.json's text, and test\test-link-contracts.ps1
# must fail for every one. Every find string occurs exactly once, and on one line, so a CRLF checkout
# matches it too.
# SECTIONS (tools\Mutate.ps1; issue #83): each mutant runs only the section of test\test-link-contracts.ps1
# that kills it: the cheapest whose checks failed for it in a whole-suite run of this spec on the
# always-on box (bd6cdb5, 2026-10-07).
@{
    Target = "schema\link-verbs.v1.json"
    Suite  = "test\test-link-contracts.ps1"
    # Stop at the first failed check: a caught mutant needs nothing more.
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "effect-not-required"
           Find = '"required": ["name", "direction", "effect", "since", "args", "result"],'
           Replace = '"required": ["name", "direction", "since", "args", "result"],'
           Sections = @("rows") }
        @{ Name = "effect-class-widened"
           Find = '"effect": { "type": "string", "enum": ["read", "write", "spawn", "drive", "kill"] },'
           Replace = '"effect": { "type": "string", "enum": ["read", "write", "spawn", "drive", "kill", "delete"] },'
           Sections = @("rows") }
        @{ Name = "deliver-classed-write"
           Find = '{ "name": "session.deliver",  "direction": "hub-to-node", "effect": "drive",'
           Replace = '{ "name": "session.deliver",  "direction": "hub-to-node", "effect": "write",'
           Sections = @("controls") }
        @{ Name = "handoff-document-raised-to-text"
           Find = '"document": { "type": "string", "pattern": "\\S", "x-horde-cap": "summaryBytes" }'
           Replace = '"document": { "type": "string", "pattern": "\\S", "x-horde-cap": "textBytes" }'
           Sections = @("controls") }
        @{ Name = "worktree-name-any-text"
           Find = '"worktree-name": { "type": "string", "pattern": "^(?!([Cc][Oo][Nn]|[Pp][Rr][Nn]|[Aa][Uu][Xx]|[Nn][Uu][Ll]|[Cc][Oo][Mm][0-9]|[Ll][Pp][Tt][0-9])(\\.|$))(?!.*\\.\\.)(?!.*\\.$)[A-Za-z0-9][A-Za-z0-9._-]{0,99}$",'
           Replace = '"worktree-name": { "type": "string", "pattern": "^.{1,100}$",'
           Sections = @("frame") }
        @{ Name = "worktree-name-final-dot"
           Find = '(?!.*\\.\\.)(?!.*\\.$)[A-Za-z0-9][A-Za-z0-9._-]{0,99}$'
           Replace = '(?!.*\\.\\.)[A-Za-z0-9][A-Za-z0-9._-]{0,99}$'
           Sections = @("frame") }
        @{ Name = "session-id-drive-allowed"
           Find = '"pattern": "^(?![A-Za-z]:)(?!'
           Replace = '"pattern": "^(?!'
           Sections = @("frame")
        }
        @{ Name = "session-id-dos-name-allowed"
           Find = '(?!([Cc][Oo][Nn]|[Pp][Rr][Nn]|[Aa][Uu][Xx]|[Nn][Uu][Ll]|[Cc][Oo][Mm][0-9]|[Ll][Pp][Tt][0-9])([.:]|$))'
           Replace = ''
           Sections = @("frame") }
        @{ Name = "session-id-final-dot-allowed"
           Find = '(?!.*[.:]$)[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
           Replace = '[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
           Sections = @("frame") }
        @{ Name = "repo-id-segment-may-end-in-a-dot"
           Find = '(?![^/]*\\.(/|$))'
           Replace = ''
           Sections = @("frame") }
        @{ Name = "token-any-text"
           Find = '"token": { "type": "string", "pattern": "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$",'
           Replace = '"token": { "type": "string", "pattern": "^.{1,64}$",'
           Sections = @("frame") }
        @{ Name = "spawn-close-on-optional"
           Find = '"required": ["label", "role", "runId", "profile", "repoId", "prompt", "closeOn"],'
           Replace = '"required": ["label", "role", "runId", "profile", "repoId", "prompt"],'
           Sections = @("frame") }
        @{ Name = "clone-status-branch-bare"
           Find = '"branch": { "$ref": "#/definitions/answer-token" },'
           Replace = '"branch": { "$ref": "#/definitions/token" },'
           Sections = @("answers") }
        # Messaging over the link (plan step R21, 2026-10-05).
        @{ Name = "mail-next-classed-drive"
           Find = '{ "name": "mail.next",        "direction": "hub-to-node", "effect": "read",'
           Replace = '{ "name": "mail.next",        "direction": "hub-to-node", "effect": "drive",'
           Sections = @("controls") }
        @{ Name = "mail-receipt-classed-read"
           Find = '{ "name": "mail.receipt",     "direction": "hub-to-node", "effect": "write",'
           Replace = '{ "name": "mail.receipt",     "direction": "hub-to-node", "effect": "read",'
           Sections = @("controls") }
        @{ Name = "outbound-mail-body-raised-to-text"
           Find = '"body": { "type": "string", "pattern": "\\S", "x-horde-cap": "summaryBytes" },'
           Replace = '"body": { "type": "string", "pattern": "\\S", "x-horde-cap": "textBytes" },'
           Sections = @("controls") }
        @{ Name = "outbound-mail-target-label-optional"
           Find = '"type": "object", "required": ["label"], "additionalProperties": false,'
           Replace = '"type": "object", "required": [], "additionalProperties": false,'
           Sections = @("messaging") }
        @{ Name = "mail-next-pending-optional"
           Find = '"type": "object", "required": ["pending"], "additionalProperties": false,'
           Replace = '"type": "object", "required": [], "additionalProperties": false,'
           Sections = @("messaging") }
        @{ Name = "receipt-stage-queued-allowed"
           Find = '"receipt-stage": { "type": "string", "enum": ["accepted", "handed-over", "seen", "expired", "held", "refused"],'
           Replace = '"receipt-stage": { "type": "string", "enum": ["queued", "accepted", "handed-over", "seen", "expired", "held", "refused"],'
           Sections = @("controls") }
        @{ Name = "receipt-ack-time-optional"
           Find = '"type": "object", "required": ["messageId", "stage", "recordedAt"], "additionalProperties": false,'
           Replace = '"type": "object", "required": ["messageId", "stage"], "additionalProperties": false,'
           Sections = @("messaging") }
        # Review of PR #97: the rules the contract states, each pinned by a Contains check.
        @{ Name = "deliver-gate-on-resolved-unstated"
           Find = 'THE GATE IS APPLIED TO THE RESOLVED SESSION, the one'
           Replace = 'The gate is applied, the one'
           Sections = @("messaging") }
        @{ Name = "receipt-forward-only-unstated"
           Find = 'Stages only move forward:'
           Replace = 'Stages move:'
           Sections = @("messaging") }
        @{ Name = "held-settles-unstated"
           Find = 'So held settles too'
           Replace = 'So held is retried'
           Sections = @("messaging") }
        @{ Name = "sender-device-unstated"
           Find = "from.deviceId must be the link peer's enrolled device"
           Replace = 'from.deviceId names the sending device'
           Sections = @("messaging") }
    )
}
