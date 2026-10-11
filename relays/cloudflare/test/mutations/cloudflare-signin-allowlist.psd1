# Mutations of the sign-in allowlist the deploy writes (relays/cloudflare/SignInAllowlist.ps1, relay PR
# 8b). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-signin-allowlist.psd1
# relays\cloudflare\test\test-cloudflare-deploy.ps1 (a fake wrangler only) must fail for every one.
# Every find string occurs once.
#
# NOT HERE, and why: the cap of 256 accounts (a list that long in a suite proves only the number), and
# an entry given twice written once (the Worker's set takes it twice the same).
@{
    Target = "relays\cloudflare\SignInAllowlist.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-deploy.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "emails-keep-their-case"
           Find = '$lower = $e.ToLowerInvariant()'
           Replace = '$lower = $e' }
        @{ Name = "account-ids-read-as-emails"
           Find = 'if ($e -cmatch $script:HordeCloudflareRelayAllowlistSub) {'
           Replace = 'if ($false) {' }
        @{ Name = "bad-entry-skipped"
           Find = 'else { return (New-HordeUnknown -Reason ("the setting signInAllowlist holds an entry'
           Replace = 'elseif ($false) { return (New-HordeUnknown -Reason ("the setting signInAllowlist holds an entry' }
        @{ Name = "on-with-nobody-deployed"
           Find = 'if ($on -and $emails.Count + $subs.Count -eq 0) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "always-on"
           Find = '$on = ($Values.signInAllowlistOn -eq $true)'
           Replace = '$on = $true' }
    )
}
