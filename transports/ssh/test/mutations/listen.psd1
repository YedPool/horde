# Mutations of the hub's listener (transports/ssh/Listen.ps1, remote plan R17a): what it admits and the
# configuration it writes, both decided before anything starts. Run:
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\listen.psd1
# transports\ssh\test\test-listen.ps1 (pure, no server) must fail for each. What only a running sshd
# shows is listen-live.psd1.
@{
    Target = "transports\ssh\Listen.ps1"
    Suite  = "transports\ssh\test\test-listen.ps1"
    Mutations = @(
        # --- what it admits ---
        @{ Name = "restrict-optional"
           Find = '",restrict(?:,expiry-time='
           Replace = '"(?:,restrict)?(?:,expiry-time=' }
        @{ Name = "any-option-after-restrict"
           Find = '",restrict(?:,expiry-time="[0-9]{8}")? ssh-ed25519'
           Replace = '",restrict(?:,[^ ]+)? ssh-ed25519' }
        @{ Name = "command-optional"
           Find = "'\Acommand=""(?<cmd>[^""]+)"",restrict"
           Replace = "'\A(?:command=""(?<cmd>[^""]+)"",)?restrict" }
        @{ Name = "forced-command-not-compared"
           Find = 'if ($m.Groups["cmd"].Value -cne'
           Replace = 'if ($false -and $m.Groups["cmd"].Value -cne' }
        @{ Name = "key-line-unanchored-end"
           Find = "+ ')\z'"
           Replace = "+ ')'" }
        @{ Name = "empty-file-admitted"
           Find = 'if ($out.Count -eq 0 -and $admitted -eq 0)'
           Replace = 'if ($false)' }
        @{ Name = "bad-key-line-skipped"
           Find = 'if (-not $m.Success) { [void]$out.Add('
           Replace = 'if (-not $m.Success) { continue; [void]$out.Add(' }
        # --- what it refuses before starting ---
        @{ Name = "hub-id-not-checked"
           Find = 'if ("$($Request.hubId)" -cnotmatch'
           Replace = 'if ($false -and "$($Request.hubId)" -cnotmatch' }
        @{ Name = "port-not-checked"
           Find = 'if ($port -lt 1 -or $port -gt 65535) {'
           Replace = 'if ($false) {' }
        @{ Name = "no-host-key-not-checked"
           Find = 'if (-not (Test-Path -LiteralPath $files.hostKey -PathType Leaf)) {'
           Replace = 'if ($false) {' }
        @{ Name = "keys-not-checked"
           Find = 'if ($found.Count -gt 0) {'
           Replace = 'if ($false) {' }
        # --- the configuration ---
        @{ Name = "listens-on-every-address"
           Find = '"ListenAddress 127.0.0.1",'
           Replace = '"ListenAddress 0.0.0.0",' }
        @{ Name = "forwarding-allowed"
           Find = '"DisableForwarding yes",'
           Replace = '"DisableForwarding no",' }
        @{ Name = "terminal-allowed"
           Find = '"PermitTTY no",'
           Replace = '"PermitTTY yes",' }
        @{ Name = "force-command-added"
           Find = '"LogLevel VERBOSE"'
           Replace = '"LogLevel VERBOSE", "ForceCommand cmd.exe"' }
        @{ Name = "revoked-keys-not-read"
           Find = '("RevokedKeys " + $f + "/revoked_keys"),'
           Replace = '' }
        @{ Name = "any-user"
           Find = '("AllowUsers " + $User),'
           Replace = '' }
        @{ Name = "home-not-passed"
           Find = '(''SetEnv "HORDE_HOME='' + $HordeHome.Replace(''\'', ''/'') + ''"''),'
           Replace = '' }
        @{ Name = "user-environment-allowed"
           Find = '"PermitUserEnvironment no",'
           Replace = '"PermitUserEnvironment yes",' }
    )
}
