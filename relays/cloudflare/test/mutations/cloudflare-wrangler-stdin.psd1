# Mutations of how the hosted relay's tooling starts a child with its input redirected
# (relays/cloudflare/Wrangler.ps1, Start-HordeCloudflareRelayProcessNoMark): the byte order mark that
# Windows PowerShell 5.1 put in front of every Worker secret on 2026-10-14. Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-wrangler-stdin.psd1
# relays\cloudflare\test\test-cloudflare-deploy.ps1 (part 8: a 5.1 child with a UTF-8 console) must fail
# for every one it is not declared to survive. Every find string occurs once.
@{
    Target = "relays\cloudflare\Wrangler.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-deploy.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "input-encoding-left-with-its-preamble"
           Find = 'if ($current.GetPreamble().Length -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "console-encoding-not-put-back"
           Find = 'finally { if ($null -ne $saved) { try { [Console]::InputEncoding = $saved } catch { } } }'
           Replace = 'finally { }' }
        @{ Name = "marked-writer-not-stopped"
           Find = 'if ($Info.RedirectStandardInput -and $p.StandardInput.Encoding.GetPreamble().Length -gt 0) {'
           Replace = 'if ($false) {'
           Expect = "survives"
           Reason = "The fallback runs only on a host whose console input encoding cannot be set (no console at all). Every suite here runs with a console, where the encoding is set first and the writer never has a preamble; no host without one is available to a suite." }
    )
}
