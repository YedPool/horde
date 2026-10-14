# Mutations of reading the relay's metrics salt (relays/cloudflare/MetricsSalt.ps1): outside the
# repository, there, ASCII, no byte order mark, no whitespace around it, long enough. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-metrics-salt.psd1
# relays\cloudflare\test\test-cloudflare-deploy.ps1 must fail for every one (its part 2 refusals and their
# control). Every find string occurs once.
@{
    Target = "relays\cloudflare\MetricsSalt.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-deploy.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "salt-inside-the-repository-read"
           Find = '    if (Test-HordeCloudflareRelayUnder -Path $Path -Folder $RepoRoot) {'
           Replace = '    if ($false) {' }
        @{ Name = "byte-order-mark-kept"
           Find = '    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF'
           Replace = '    if ($false -and $bytes[0] -eq 0xEF' }
        @{ Name = "non-ascii-kept"
           Find = '    foreach ($b in $bytes) { if ($b -gt 0x7E -or'
           Replace = '    foreach ($b in $bytes) { if ($false -or' }
        @{ Name = "line-end-kept"
           Find = '    if ($text -ne $text.Trim()) {'
           Replace = '    if ($false) {' }
        @{ Name = "short-salt-taken"
           Find = "`$script:HordeCloudflareRelayMetricsSaltPattern = '\A[\x21-\x7E]{32,256}\z'"
           Replace = "`$script:HordeCloudflareRelayMetricsSaltPattern = '\A[\x21-\x7E]{8,256}\z'" }
        @{ Name = "salt-of-33-at-least"
           Find = "`$script:HordeCloudflareRelayMetricsSaltPattern = '\A[\x21-\x7E]{32,256}\z'"
           Replace = "`$script:HordeCloudflareRelayMetricsSaltPattern = '\A[\x21-\x7E]{33,256}\z'" }
    )
}
