# relays/cloudflare/Bundle.ps1 - the Worker as it would be deployed from a tree of the repository, built
# by the pinned wrangler's dry run and hashed, with no network and no login: the relay's -Bundle block
# (relays/Port.ps1, DEPLOYING). The supervisor asks it, for the deployed commit and the checkout's, when
# the only Worker files that changed are ones the Worker shares with the phone app (cli/RelayPublish.ps1):
# the protocol, which changes with nearly every phone change, and the page files the Worker imports.
#
# HOW: the tree's OWN wrangler.json (so a commit is bundled as that commit configured it) is written into
# the work folder with main and base_dir made absolute into the tree and the assets pointed at an empty
# folder of the work's own (assets are the site, not the Worker); then
#   wrangler deploy --dry-run --outdir <work>\out --config <that config>
# which bundles and stops: "--dry-run: exiting now". The hash is of every file it wrote, by name and
# bytes, but README.md.
#
# MEASURED 2026-10-14, wrangler 4.149.0 on this checkout, two runs in two work folders: index.js (94,701
# bytes) and the imported page, <sha1>-index.html, byte-identical; README.md differed, and only by the
# time it names ("generated at 2026-10-14T08:54:32.687Z"), so it is left out. Each run took about 1.2 s.
# The same tree COPIED TO ANOTHER FOLDER bundled differently, and only in the comment line the bundler
# writes above each module: its path, relative from the work folder to the tree ("// ../../dbgtree/relay/
# js/protocol.js" against "// ../../../../../Documents/.../relay/js/protocol.js"; an imported JSON adds
# its import attribute, "with { type: 'json' }"). Those lines carry no
# code, so a .js file is hashed without them. Measured again so normalised: the checkout, a copy of it,
# and the trees of commits whose only Worker-side change was the protocol all hash alike, and a commit
# that changed the Worker's own code hashes differently.
#
# NO NETWORK: on top of the quiet environment every run here has (Wrangler.ps1), HTTPS_PROXY and
# HTTP_PROXY point at a closed port on this machine, so any request it tried would fail rather than
# leave. The measured runs above were made so, and succeeded: the dry run asks nothing of the network.
# NO INSTALL: only a wrangler already installed is used; with none, the answer is unknown (the deploy,
# a person's, installs it).
#
# No Set-StrictMode here: dot-sourced by Relay.ps1, after Wrangler.ps1.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\JsonText.ps1")
$script:HordeCloudflareRelayBundleSeconds = 120
$script:HordeCloudflareRelayNoNetwork = "http://127.0.0.1:9"
# What the dry run writes that is not code: a note naming the time it was written (measured above).
$script:HordeCloudflareRelayBundleSkip = @("README.md")
# The bundler's line naming the module below it, by its path from the work folder (measured above).
$script:HordeCloudflareRelayBundlePathLine = '(?m)^// \S+\.(js|mjs|cjs|json|html|txt)( with \{[^\r\n]*\})?\r?\n'

function Get-HordeCloudflareRelayBundleHash {
    # The Worker bundled from the repository tree -Tree, as one hash: known { sha256 } or unknown.
    param([Parameter(Mandatory = $true)][string]$Tree, [Parameter(Mandatory = $true)][string]$Work)
    $node = Find-HordeCloudflareRelayNode
    if ($node -eq "") { return (New-HordeUnknown -Reason "node is not installed here") }
    $wrangler = Get-HordeCloudflareRelayWranglerScript -ToolsHome (Get-HordeCloudflareRelayToolsHome)
    if (-not (Test-Path -LiteralPath $wrangler -PathType Leaf)) { return (New-HordeUnknown -Reason "the pinned wrangler is not installed here; a deploy installs it") }
    $folder = Join-Path $Tree "relays\cloudflare"
    $cfgPath = Join-Path $folder "wrangler.json"
    if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) { return (New-HordeUnknown -Reason "the tree has no wrangler.json for this relay") }
    try {
        $text = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
        if (Test-HordeCloudflareRelayHasTestBinding -Text $text) { return (New-HordeUnknown -Reason "the tree's wrangler.json names a test binding") }
        $cfg = ConvertFrom-HordeJson -Text ($text)
        $slash = { param([string]$p) ([System.IO.Path]::GetFullPath($p)) -replace '\\', '/' }
        $site = Join-Path $Work "no-assets"
        [void][System.IO.Directory]::CreateDirectory($site)
        $cfg.main = & $slash (Join-Path $folder $cfg.main)
        $cfg.base_dir = & $slash $Tree
        $cfg.assets.directory = & $slash $site
        $conf = Join-Path $Work "config"
        [void][System.IO.Directory]::CreateDirectory($conf)
        $confPath = Join-Path $conf "wrangler.json"
        [System.IO.File]::WriteAllText($confPath, ($cfg | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding -ArgumentList $false))
    } catch { return (New-HordeUnknown -Reason "the tree's wrangler.json could not be read" -ErrorRecord $_) }
    $out = Join-Path $Work "out"
    $env2 = Get-HordeCloudflareRelayQuietEnv -Work $Work
    $env2["HTTPS_PROXY"] = $script:HordeCloudflareRelayNoNetwork; $env2["HTTP_PROXY"] = $script:HordeCloudflareRelayNoNetwork; $env2["NO_PROXY"] = ""
    $r = Invoke-HordeCloudflareRelayNode -Node $node -ArgList @($wrangler, "deploy", "--dry-run", "--outdir", $out, "--config", $confPath) -Env $env2 -WorkDir $Work -TimeoutSeconds $script:HordeCloudflareRelayBundleSeconds
    if ($r.timedOut -or $r.code -ne 0) { return (New-HordeUnknown -Reason ("the dry run did not bundle the Worker (exit " + $r.code + $(if ($r.timedOut) { ", timed out" } else { "" }) + ")")) }
    $files = @(Get-ChildItem -LiteralPath $out -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $script:HordeCloudflareRelayBundleSkip -notcontains $_.Name } | Sort-Object FullName)
    if (@($files | Where-Object { $_.Extension -ceq ".js" }).Count -eq 0) { return (New-HordeUnknown -Reason "the dry run wrote no Worker code") }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $all = New-Object System.IO.MemoryStream
        foreach ($f in $files) {
            $name = [System.Text.Encoding]::UTF8.GetBytes(($f.FullName.Substring($out.Length) -replace '\\', '/') + "`n")
            $all.Write($name, 0, $name.Length)
            $b = [System.IO.File]::ReadAllBytes($f.FullName)
            if ($f.Extension -ceq ".js") { $b = [System.Text.Encoding]::UTF8.GetBytes(([regex]::Replace([System.Text.Encoding]::UTF8.GetString($b), $script:HordeCloudflareRelayBundlePathLine, ""))) }
            $all.Write($b, 0, $b.Length)
        }
        $hash = (($sha.ComputeHash($all.ToArray()) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally { $sha.Dispose() }
    return (New-HordeKnown -Value ([pscustomobject]@{ sha256 = $hash }))
}
