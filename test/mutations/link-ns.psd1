# Mutations of the namespace in the link contracts (remote plan R11). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\link-ns.psd1
# test\test-link-contracts.ps1 must fail for each: session.close's expected pid without its ns, a
# namespace that takes a host name or the agent's pidDomain, and a space vocabulary that is not the
# platform's.
@{
    Target = "schema\link-verbs.v1.json"
    Suite  = "test\test-link-contracts.ps1"
    Mutations = @(
        @{ Name = "expect-ns-optional"
           Find = '"type": "object", "required": ["ns", "pid", "procStart"],'
           Replace = '"type": "object", "required": ["pid", "procStart"],' }
        @{ Name = "ns-device-any-string"
           Find = '"device": { "$ref": "#/definitions/uuid" },'
           Replace = '"device": { "type": "string", "x-horde-cap": "nameBytes" },' }
        @{ Name = "ns-space-any-string"
           Find = '"space": { "type": "string", "pattern": "^(windows|posix|synthetic|wsl:[A-Za-z0-9._-]{1,64})$", "x-horde-cap": "nameBytes" }'
           Replace = '"space": { "type": "string", "x-horde-cap": "nameBytes" }' }
        @{ Name = "ns-open-to-pid-domain"
           Find = '"type": "object", "required": ["device", "space"], "additionalProperties": false,'
           Replace = '"type": "object", "required": ["device", "space"], "additionalProperties": true,' }
        @{ Name = "entry-expect-ns-optional"
           Find = '"type": "object", "additionalProperties": false, "required": ["ns", "pid", "procStart"],'
           Replace = '"type": "object", "additionalProperties": false, "required": ["pid", "procStart"],' }
    )
}
