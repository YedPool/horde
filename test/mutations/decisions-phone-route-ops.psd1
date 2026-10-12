# Mutations of decisions/Operations.ps1 where a say carries the route phone's evidence (relay design
# 2026-10-09, PR plan item 5). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-phone-route-ops.psd1
# Each breaks one thing the relay channel relies on; test\test-decisions-phone-route.ps1 must fail for
# every one.
@{
    Target = "decisions\Operations.ps1"
    Suite  = "test\test-decisions-phone-route.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "evidence-never-stored"
           Find = '    if ($proven) { $body["evidence"] = $evidence }'
           Replace = '' }
        @{ Name = "evidence-never-told-to-the-rules"
           Find = '-EvidenceStated ([bool]$proven) -Evidence $evidence'
           Replace = '-EvidenceStated $false -Evidence ""' }
        # The first answer wins: a second delivery of the same answer is replayed, not refused.
        @{ Name = "evidence-hashed-so-a-redelivery-is-refused"
           Find = 'return [pscustomobject]@{ body = $body; findings = @($found); unhashed = @("evidence", "signedBy") }'
           Replace = 'return [pscustomobject]@{ body = $body; findings = @($found); unhashed = @("signedBy") }' }
        @{ Name = "unhashed-members-ignored"
           Find = 'foreach ($k in @($content.body.Keys)) { if ($unhashed -cnotcontains $k) { $sameness[$k] = $content.body[$k] } }'
           Replace = 'foreach ($k in @($content.body.Keys)) { $sameness[$k] = $content.body[$k] }' }
        # Secrets first: a secret where the evidence goes is named as a secret, before its shape.
        @{ Name = "schema-before-secrets"
           Find = '    $secrets = @(Find-HordeDecisionSecrets -Value $plain)'
           Replace = '    $secrets = @()' }
        # --- who signed (signedBy, 2026-10-12) ---
        @{ Name = "signedBy-never-stored"
           Find = '    if ($signed) { $body["signedBy"] = $signedBy }'
           Replace = '' }
        @{ Name = "signedBy-never-told-to-the-rules"
           Find = '-SignedByStated ([bool]$signed) -SignedBy $signedBy'
           Replace = '-SignedByStated $false -SignedBy ""' }
        # An answer recorded before records named the passkey, handed over again after, is replayed.
        @{ Name = "signedBy-hashed-so-a-resumed-answer-is-refused"
           Find = 'return [pscustomobject]@{ body = $body; findings = @($found); unhashed = @("evidence", "signedBy") }'
           Replace = 'return [pscustomobject]@{ body = $body; findings = @($found); unhashed = @("evidence") }' }
    )
}
