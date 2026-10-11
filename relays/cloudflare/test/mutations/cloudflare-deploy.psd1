# Mutations of `horde relay deploy` for the hosted relay (relays/cloudflare/Deploy.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-deploy.psd1
# relays\cloudflare\test\test-cloudflare-deploy.ps1 (a fake wrangler only) must fail for every one.
# Every find string occurs once.
@{
    Target = "relays\cloudflare\Deploy.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-deploy.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "secret-as-an-argument"
           Find = '@($wrangler, "secret", "put", $name, "--config", $cfg.value)'
           Replace = '@($wrangler, "secret", "put", $name, $value, "--config", $cfg.value)' }
        @{ Name = "secret-not-piped"
           Find = '-WorkDir $work -StdIn $value -TimeoutSeconds'
           Replace = '-WorkDir $work -TimeoutSeconds' }
        @{ Name = "deploy-after-a-failed-secret"
           Find = 'if ($r.timedOut -or $r.code -ne 0) { return (New-HordeUnknown -Reason ("wrangler secret put "'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("wrangler secret put "' }
        @{ Name = "failed-deploy-reported-as-done"
           Find = 'if ($r.timedOut -or $r.code -ne 0) { return (New-HordeUnknown -Reason ("wrangler deploy failed'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("wrangler deploy failed' }
        @{ Name = "secrets-not-hidden"
           Find = 'foreach ($s in $Secrets) { if ("" + $s -ne "") { $out = $out.Replace($s, "<redacted>") } }'
           Replace = '' }
        @{ Name = "work-folder-kept"
           Find = 'if ($work -like "*horde-relay-cf-deploy-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }'
           Replace = '' }
        @{ Name = "missing-return-address-not-noted"
           Find = 'if (@($client.value.redirectUris) -cnotcontains $callback) {'
           Replace = 'if ($false) {' }
        @{ Name = "allowlist-refusal-ignored"
           Find = 'if ($allow.state -cne "known") { return $allow }'
           Replace = '' }
        @{ Name = "allowlist-not-stored"
           Find = '; HORDE_RELAY_SIGNIN_ALLOWLIST = "allowlist" }'
           Replace = ' }' }
        @{ Name = "wrangler-script-setting-unchecked"
           Find = '} elseif (-not (Test-HordeModuleSettingFolder -Path $wrangler) -or -not (Test-Path -LiteralPath $wrangler -PathType Leaf)) {'
           Replace = '} elseif ($false) {' }
    )
}
