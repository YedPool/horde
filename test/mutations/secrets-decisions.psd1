# Mutations of core/Secrets.ps1 in REFUSE mode, as the decisions module uses it. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\secrets-decisions.psd1
# These lived in test\mutations\decisions-rules.psd1 until the patterns moved from decisions/Rules.ps1
# into core (relay design 2026-10-09, PR plan item 9). Their suite is still test	est-decisions-rules.ps1,
# unchanged: each loosens or switches off one shape, and the decisions module must notice that a secret
# it refused is now let through, or that ordinary text is now refused. The redact mode has its own spec,
# test\mutations\secrets.psd1.
@{
    Target = "core\Secrets.ps1"
    Suite  = "test\test-decisions-rules.ps1"
    Mutations = @(
        @{ Name = "private-key-not-seen"
           Find = '"a private key" = ''-----BEGIN [A-Z0-9 ]*PRIVATE KEY'''
           Replace = '"a private key" = ''never-matches-\A\z.''' }
        @{ Name = "access-token-not-seen"
           Find = '"an access token" = ''(?<![A-Za-z0-9])('
           Replace = '"an access token" = ''never-matches-\A\z.(' }
        @{ Name = "web-token-not-seen"
           Find = '"a signed web token" = ''eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.'''
           Replace = '"a signed web token" = ''never-matches-\A\z.''' }
        @{ Name = "bearer-token-not-seen"
           Find = '"a bearer token" = ''(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{20,}'''
           Replace = '"a bearer token" = ''never-matches-\A\z.''' }
        @{ Name = "name-equals-value-not-seen"
           Find = '"a password or key written as name=value" = ''(?i)\b('
           Replace = '"a password or key written as name=value" = ''never-matches-\A\z.(' }
        @{ Name = "password-after-colon-not-seen"
           Find = '"a password written after a colon" = ''(?i)\b('
           Replace = '"a password written after a colon" = ''never-matches-\A\z.(' }
        @{ Name = "password-in-a-sentence-not-seen"
           Find = '"a password written in a sentence" = ''(?i)\b('
           Replace = '"a password written in a sentence" = ''never-matches-\A\z.(' }
        @{ Name = "quoted-password-not-seen"
           Find = '\s+(is|was)\s+(?:["''''][^"''''\s][^"'''']*["'''']|'
           Replace = '\s+(is|was)\s+(?:' }
        @{ Name = "password-inside-an-address-not-seen"
           Find = '"a password inside an address" = ''(?i)'
           Replace = '"a password inside an address" = ''never-matches-\A\z.' }
        @{ Name = "any-link-with-a-colon-refused"
           Find = '://[^\s/:@]+:[^\s/@]+@'''
           Replace = '://[^\s:@]+:[^\s@]+''' }
        @{ Name = "webhook-address-not-seen"
           Find = '"a webhook address" = ''(?i)'
           Replace = '"a webhook address" = ''never-matches-\A\z.' }
        @{ Name = "authorization-header-not-seen"
           Find = '"an authorization value" = ''(?i:\bauthorization'
           Replace = '"an authorization value" = ''(?i:\bnever-matches-\A\z.' }
        @{ Name = "authorization-word-and-value-not-seen"
           Find = '|(?i:\b(basic|bearer))\s+'
           Replace = '|(?i:\b(never-matches-\A\z.))\s+' }
        @{ Name = "the-word-basic-before-any-word-refused"
           Find = '(?=[A-Za-z0-9._~+/-]*[0-9])(?=[A-Za-z0-9._~+/-]*[a-z])(?=[A-Za-z0-9._~+/-]*[A-Z])[A-Za-z0-9._~+/-]{12,}'
           Replace = '[A-Za-z0-9._~+/-]{12,}' }
        @{ Name = "key-with-slashes-not-seen"
           Find = '-ge $script:HordeSecretSlashRunBits)'
           Replace = '-ge 99)' }
        @{ Name = "mixed-case-path-refused"
           Find = '$script:HordeSecretSlashRunBits = 4.35'
           Replace = '$script:HordeSecretSlashRunBits = 4.0' }
        @{ Name = "random-string-not-seen"
           Find = '-ge $script:HordeSecretRunBits)'
           Replace = '-ge 99)' }
        @{ Name = "one-case-string-refused"
           Find = 'return ($Run -cmatch ''[A-Z]'' -and $Run -cmatch ''[a-z]'' -and $Run -cmatch ''[0-9]'' -and '
           Replace = 'return (' }
        @{ Name = "path-read-as-one-string"
           Find = '$script:HordeSecretRunPattern = ''[A-Za-z0-9+=_-]{32,}'''
           Replace = '$script:HordeSecretRunPattern = ''[A-Za-z0-9+=_\\/.:-]{32,}''' }
    )
}
