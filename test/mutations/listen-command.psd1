# Mutations of `horde listen` itself (cli/commands/listen.ps1; mesh v1): the address checked before
# anything else, and -AllowFrom only with a network address. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\listen-command.psd1
# test\test-listen-address.ps1 drives the real CLI and must fail for each, except the one declared to
# survive.
@{
    Target = "cli\commands\listen.ps1"
    Suite  = "test\test-listen-address.ps1"
    Mutations = @(
        @{ Name = "address-not-checked-first"
           Find = 'if ($where.state -cne "known") { throw ("horde listen will not listen there: " + $where.reason) }'
           Replace = '' }
        @{ Name = "allow-from-on-loopback"
           Find = 'if ($where.value.loopback -and @(@($AllowFrom)'
           Replace = 'if ($false -and @(@($AllowFrom)' }
        @{ Name = "listens-when-firewall-refused"
           Find = 'if (-not $fwOpen.ok) { throw $fwOpen.reason }'
           Replace = ''
           Expect = "survives"
           Reason = "only a live horde listen on a network address reaches it, and no suite runs one: that would make a real firewall rule on an elevated box, which the suites never do. Every refusal Open-HordeListenFirewall makes is pinned in test\test-firewall-port.ps1 against a stand-in firewall (listen-firewall.psd1), and the founder's first live run (planning/first-live-link-ov615.md) shows this line live" }
    )
}
