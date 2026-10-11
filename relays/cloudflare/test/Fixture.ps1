# The hosted relay's fixture for test/test-relay-conformance.ps1 (the contract is in that suite's
# header): each state is a local `wrangler dev` of the very Worker that is deployed (worker/), started
# with the test binding and a fresh random token (Wrangler.ps1, Start-HordeCloudflareRelayDev), its
# Durable Object storage in a new empty folder under the temp folder. Remove stops that dev and deletes
# that folder and nothing else.
#
# A DEV PER STATE, not one for the whole suite: a state is "an empty relay of the test's own", and a
# Durable Object's storage cannot be emptied from outside without an API the Worker must not have.
# Measured 2026-10-11: a dev answers 1.6 s after it starts on this box.
#
# THE APP'S FILES ARE NOT SERVED HERE: the site folder holds one placeholder page, because the mailbox
# contract is what this suite holds the relay to. test-cloudflare-worker.ps1 serves the built app.
#
# Unavailable says why this relay cannot be run here (no node, or the pinned wrangler cannot be
# installed), or "" when it can: the suite then skips this relay, says so, and exits 3, never 0.
#
# Requires Relay.ps1 (and so Wrangler.ps1) loaded at the suite's level, as the suite does.
param([Parameter(Mandatory = $true)][string]$Root)
return [pscustomobject]@{
    Unavailable = {
        $t = Install-HordeCloudflareRelayTools
        if ($t.state -ceq "known") { return "" }
        return ("the hosted relay cannot be run here: " + $t.reason)
    }
    New = {
        $t = Install-HordeCloudflareRelayTools
        if ($t.state -cne "known") { throw ("the hosted relay cannot be run here: " + $t.reason) }
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-relay-conf-cf-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
        $site = Join-Path $dir "site"
        [void][System.IO.Directory]::CreateDirectory($site)
        [System.IO.File]::WriteAllText((Join-Path $site "index.html"), "<!doctype html><title>relay</title>`n")
        $d = Start-HordeCloudflareRelayDev -Work $dir -Site $site -Script $t.value.script
        if ($d.state -cne "known") {
            if ($dir -like "*horde-relay-conf-cf-*") { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
            throw ("the hosted relay's local dev did not start: " + $d.reason)
        }
        return [pscustomobject]@{ root = $dir; dev = $d.value; options = @{ origin = $d.value.origin; authorization = ("Bearer " + $d.value.token) } }
    }
    Remove = {
        param($State)
        Stop-HordeCloudflareRelayDev -Dev $State.dev
        if ($State.root -like "*horde-relay-conf-cf-*" -and [System.IO.Directory]::Exists($State.root)) { Remove-Item -LiteralPath $State.root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Remote = {
        # A second client, with its own connection, to the same Worker: what another machine would hold.
        param($State)
        return @{ origin = $State.dev.origin; authorization = ("Bearer " + $State.dev.token) }
    }
}
