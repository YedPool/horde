# Mutations of transports/local/Transport.ps1's owner check, kept apart from transport-local.psd1 because
# its suite can show the owner refusal end to end only from a token allowed to make Administrators a
# pipe's owner (an elevated admin token): elsewhere test-local skips the case, never green, and this
# mutant would survive for that reason alone. So this spec accepts only exit 0: from a token that
# skips the case the suite exits 3, the baseline fails, and the spec reports "not run" instead of a
# survivor. Run it from an elevated token launched from PowerShell, not Git Bash (CONTRIBUTING 12;
# issue #89):
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\transport-local-owner.psd1
@{
    Target = "transports\local\Transport.ps1"
    Suite  = "transports\local\test\test-local.ps1"
    Mutations = @(
        @{ Name = "owner-not-checked-on-open"
           Find = 'if ($ownerRefusal -ne "") {'
           Replace = 'if ($false) {' }
    )
}
