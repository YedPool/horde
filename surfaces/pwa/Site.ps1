# surfaces/pwa/Site.ps1 - the phone app as a deployable static site: the files it is made of, taken
# from where they live in this repository and set side by side as the mounts of one tree, with the
# deployment's two facts written in (relay design 2026-10-09, PR plan item 7).
#
# WHY THE PHONE APP IS A SITE AND NOT A Surface.ps1. A surface here is something Horde OPENS on this
# machine (surfaces/Port.ps1, THE SURFACE CONTRACT); the phone app is opened by a phone, from a host
# that serves plain files (the hosted relay's pages, PR plan item 8). Horde never opens it, so this
# folder registers no surface and Resolve-HordeSurface never picks it; capabilities.json beside this
# file says what it can do in the same vocabulary, and surfaces/pwa/test/test-pwa-site.ps1 checks it
# against the schema. WHAT IT KEEPS FROM THE PORT is how a page finds a file: by a relative address,
# ../<mount>/<file>, never a host (surfaces/Port.ps1, WHERE A PAGE FINDS A FILE), and only kinds of
# file on the port's list (.js, not .mjs).
#
# THE TREE (New-HordePwaSite -Out <folder>):
#   app/       the phone app (surfaces/pwa/page/): its page, frame, styles, logic, worker, manifest,
#              icons, and config.json, written here
#   surface/   the page's side of the bridge (bridge.js), and surfaces/bridge-messages.json beside it,
#              as every surface serves them
#   list/      the decisions document, unchanged (decisions/page/list.js and list.css), and the
#              question kinds it draws by (decisions/question-kinds.json)
#   relay/     the protocol (relay/js/protocol.js), the very file the test phone runs
#   index.html a page that sends a visitor of the site's root to app/index.html (no script)
# Every file is copied byte for byte, except the two that carry the deployment's facts:
#   app/index.html  its policy line's "connect-src 'self'" gets the relay's origin after it, so the page
#                   may connect to its own site and to that ONE relay, and nowhere else;
#   app/sw.js       its VERSION (a hash of every other file of the shell) and its SHELL (their paths)
#                   are written into the two placeholder lines it carries, so a new deployment is a new
#                   worker and a new cache.
# and three are made: app/config.json, { schemaVersion, version, transport, relayOrigin, lockAfterHiddenSeconds,
# sessionAwaySeconds } - which relay transport the app uses (surfaces/pwa/page/relay-client.js,
# transportFromConfig), where the relay is, how long the app may stay hidden before it locks every horde
# (600 s; it was the founder's five minutes, 2026-10-10, until his Q75 (c), 2026-10-15: keep the session
# through a switch-away of up to 10 minutes - and a lock drops the session's key, so the lock may never come
# before the away time; a suite builds with less to see it happen), and how long it may be away before its
# unlocked session ends (600 s, the design note's ten minutes, 2026-10-14: surfaces/pwa/page/phone-core.js,
# THE UNLOCKED SESSION; the PC cannot see the phone's screen, so this one is the phone's alone). A lock time
# shorter than the away time is refused: the away rule could never be met - and app/icon-192.png and app/icon-512.png, the icons an installable app needs at those sizes
# (Chrome's install criteria), drawn here from the shape of page/icon.svg (New-HordePwaIconPng). They
# are made, not committed: every file in the repository is ASCII text (CONTRIBUTING 13), and
# tools/HostNames.ps1 excuses only pinned program libraries from being read as text.
# A placeholder that is not there exactly once refuses the build: a page whose policy was not written
# would connect nowhere, or a worker never updated would serve an old app for ever.
#
# THE OUT FOLDER must not exist, or be empty: a build never writes over files it did not make.
# Everything is ASCII (CONTRIBUTING 13); a source file that is not refuses the build.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Tristate.ps1")

# site path -> repository path, in the order they are written.
$script:HordePwaSiteFiles = [ordered]@{
    "app/index.html" = "surfaces/pwa/page/index.html"
    "app/app.css" = "surfaces/pwa/page/app.css"
    "app/app.js" = "surfaces/pwa/page/app.js"
    "app/phone-core.js" = "surfaces/pwa/page/phone-core.js"
    "app/lane-card.js" = "surfaces/pwa/page/lane-card.js"
    "app/decision-cards.js" = "surfaces/pwa/page/decision-cards.js"
    "app/published-lists.js" = "surfaces/pwa/page/published-lists.js"
    "app/notices-view.js" = "surfaces/pwa/page/notices-view.js"
    "app/cards-why.js" = "surfaces/pwa/page/cards-why.js"
    "app/app-update.js" = "surfaces/pwa/page/app-update.js"
    "app/read-banner.js" = "surfaces/pwa/page/read-banner.js"
    "app/photo.js" = "surfaces/pwa/page/photo.js"
    "app/chat-scroll.js" = "surfaces/pwa/page/chat-scroll.js"
    "app/bar-height.js" = "surfaces/pwa/page/bar-height.js"
    "app/session-view.js" = "surfaces/pwa/page/session-view.js"
    "app/keywrap.js" = "surfaces/pwa/page/keywrap.js"
    "app/relay-client.js" = "surfaces/pwa/page/relay-client.js"
    "app/account-client.js" = "surfaces/pwa/page/account-client.js"
    "app/store.js" = "surfaces/pwa/page/store.js"
    "app/webauthn.js" = "surfaces/pwa/page/webauthn.js"
    "app/scan.js" = "surfaces/pwa/page/scan.js"
    "app/sw.js" = "surfaces/pwa/page/sw.js"
    "app/manifest.json" = "surfaces/pwa/page/manifest.json"
    "app/icon.svg" = "surfaces/pwa/page/icon.svg"
    "surface/bridge.js" = "surfaces/pwa/page/bridge.js"
    "surface/bridge-messages.json" = "surfaces/bridge-messages.json"
    "list/list.js" = "decisions/page/list.js"
    "list/list.css" = "decisions/page/list.css"
    "list/question-kinds.json" = "decisions/question-kinds.json"
    "relay/protocol.js" = "relay/js/protocol.js"
}
# The transports the app knows by name (relay-client.js, transportFromConfig; the site suite holds the
# two lists equal). memory: a relay inside the page, for a demonstration. binding: the local test
# transport, carried by a test harness. http: the hosted relay's mailbox API, at the relay origin, or
# with none at the site's own origin - the deployed case, where one host serves the app and its relay.
$script:HordePwaTransports = @("memory", "binding", "http")
$script:HordePwaCspPlaceholder = "connect-src 'self'"
$script:HordePwaVersionPlaceholder = 'const VERSION = "unbuilt";'
$script:HordePwaShellPlaceholder = 'const SHELL = [];'
# An origin the page may connect to: https with a host name and an optional port, or plain http to
# this machine only (a local test). No path, no user, no wildcard: one relay, exactly.
$script:HordePwaOriginPattern = '\A(https://[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?|http://(localhost|127\.0\.0\.1))(:[0-9]{1,5})?\z'

function Get-HordePwaRepoRoot { return (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }

function Get-HordePwaSiteFiles {
    # site path -> repository path (a copy).
    $copy = [ordered]@{}
    foreach ($k in @($script:HordePwaSiteFiles.Keys)) { $copy[$k] = $script:HordePwaSiteFiles[$k] }
    return $copy
}

function Get-HordePwaTransports { return @($script:HordePwaTransports) }

function Test-HordePwaRelayOrigin {
    # "" when -Origin is one the page may connect to (or empty: none), else why not.
    param([AllowEmptyString()][string]$Origin)
    if ($Origin -ceq "") { return "" }
    if ($Origin -cnotmatch $script:HordePwaOriginPattern) { return ("'" + $Origin + "' is not a relay origin: https://<host>[:port], or http://localhost[:port] for a local test") }
    return ""
}

function Get-HordePwaPlaceholderCount {
    param([string]$Text, [string]$Find)
    $n = 0; $i = 0
    while (($i = $Text.IndexOf($Find, $i, [System.StringComparison]::Ordinal)) -ge 0) { $n++; $i += $Find.Length }
    return $n
}

function New-HordePwaIconPng {
    # A square PNG of -Size pixels: page/icon.svg's shape - a blue field, a white H - drawn in whole
    # pixels. Full bleed, so a maskable crop (its safe zone is the middle 80 percent) keeps the letter,
    # which stands in the middle half. Truecolour, 8 bits, no filter; zlib by DeflateStream.
    param([Parameter(Mandatory = $true)][ValidateRange(16, 1024)][int]$Size)
    $blue = [byte[]](0x1f, 0x5f, 0xae)
    $white = [byte[]](255, 255, 255)
    # The shape on the SVG's 512 grid: legs at x 144-200 and 312-368, y 128-384; the bar y 228-284.
    $at = { param([int]$v) [int][Math]::Round($v * $Size / 512.0) }
    $x1 = & $at 144; $x2 = & $at 200; $x3 = & $at 312; $x4 = & $at 368; $y1 = & $at 128; $y2 = & $at 384; $b1 = & $at 228; $b2 = & $at 284
    $rowLen = 1 + 3 * $Size
    $plain = New-Object byte[] $rowLen; $legs = New-Object byte[] $rowLen; $bar = New-Object byte[] $rowLen
    for ($x = 0; $x -lt $Size; $x++) {
        $inLeg = ($x -ge $x1 -and $x -lt $x2) -or ($x -ge $x3 -and $x -lt $x4)
        $inBar = $x -ge $x1 -and $x -lt $x4
        [System.Array]::Copy($blue, 0, $plain, 1 + 3 * $x, 3)
        [System.Array]::Copy($(if ($inLeg) { $white } else { $blue }), 0, $legs, 1 + 3 * $x, 3)
        [System.Array]::Copy($(if ($inBar) { $white } else { $blue }), 0, $bar, 1 + 3 * $x, 3)
    }
    $raw = New-Object byte[] ($rowLen * $Size)
    for ($y = 0; $y -lt $Size; $y++) {
        $row = $plain
        if ($y -ge $y1 -and $y -lt $y2) { $row = $legs; if ($y -ge $b1 -and $y -lt $b2) { $row = $bar } }
        [System.Array]::Copy($row, 0, $raw, $y * $rowLen, $rowLen)
    }
    $deflated = New-Object System.IO.MemoryStream
    $z = New-Object System.IO.Compression.DeflateStream($deflated, [System.IO.Compression.CompressionMode]::Compress, $true)
    $z.Write($raw, 0, $raw.Length); $z.Dispose()
    # Checksums as [long]: Windows PowerShell reads 0xFFFFFFFF as the Int32 -1, and casts it to UInt32
    # with an error (measured 2026-10-09), so every value here stays a non-negative long under a mask.
    [long]$a = 1; [long]$b = 0
    foreach ($v in $raw) { $a = ($a + $v) % 65521; $b = ($b + $a) % 65521 }
    [long]$adler = ($b * 65536) + $a
    $idat = New-Object System.IO.MemoryStream
    $idat.WriteByte(0x78); $idat.WriteByte(0x01)
    $d = $deflated.ToArray(); $idat.Write($d, 0, $d.Length)
    foreach ($s in 24, 16, 8, 0) { $idat.WriteByte([byte](($adler -shr $s) -band 255)) }
    [long]$poly = 3988292384
    [long]$all = 4294967295
    $crcTable = New-Object long[] 256
    for ($n = 0; $n -lt 256; $n++) { [long]$c = $n; for ($k = 0; $k -lt 8; $k++) { if ($c -band 1) { $c = $poly -bxor ($c -shr 1) } else { $c = $c -shr 1 } }; $crcTable[$n] = $c }
    $out = New-Object System.IO.MemoryStream
    $sig = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A); $out.Write($sig, 0, 8)
    $chunk = {
        param([string]$Type, [byte[]]$Data)
        $len = $Data.Length
        foreach ($s in 24, 16, 8, 0) { $out.WriteByte([byte](($len -shr $s) -band 255)) }
        $td = New-Object byte[] (4 + $len)
        [System.Text.Encoding]::ASCII.GetBytes($Type).CopyTo($td, 0); $Data.CopyTo($td, 4)
        $out.Write($td, 0, $td.Length)
        [long]$crc = $all
        foreach ($v in $td) { $crc = $crcTable[($crc -bxor $v) -band 255] -bxor ($crc -shr 8) }
        $crc = $crc -bxor $all
        foreach ($s in 24, 16, 8, 0) { $out.WriteByte([byte](($crc -shr $s) -band 255)) }
    }
    $hdr = New-Object byte[] 13
    foreach ($i in 0..3) { $hdr[$i] = [byte](($Size -shr (24 - 8 * $i)) -band 255); $hdr[4 + $i] = $hdr[$i] }
    $hdr[8] = 8; $hdr[9] = 2
    & $chunk "IHDR" $hdr
    & $chunk "IDAT" $idat.ToArray()
    & $chunk "IEND" (New-Object byte[] 0)
    return , $out.ToArray()
}

function New-HordePwaSite {
    # Build the site into -Out. Known { out; version; files; shell } or unknown with the reason; nothing
    # is written on a refusal found before writing.
    param([Parameter(Mandatory = $true)][string]$Out, [Parameter(Mandatory = $true)][string]$Transport, [AllowEmptyString()][string]$RelayOrigin = "",
        [int]$LockAfterHiddenSeconds = 600, [int]$SessionAwaySeconds = 600)
    if ($LockAfterHiddenSeconds -lt 1 -or $LockAfterHiddenSeconds -gt 86400) { return (New-HordeUnknown -Reason ("the app locks after 1 to 86400 seconds hidden, not " + $LockAfterHiddenSeconds)) }
    if ($SessionAwaySeconds -lt 1 -or $SessionAwaySeconds -gt 86400) { return (New-HordeUnknown -Reason ("the unlocked session ends after 1 to 86400 seconds away, not " + $SessionAwaySeconds)) }
    # The founder's Q75 (c): the session is kept through a switch-away of up to the away time, and a lock
    # drops its key - so a lock sooner than that would end every session first.
    if ($LockAfterHiddenSeconds -lt $SessionAwaySeconds) { return (New-HordeUnknown -Reason ("the app may not lock (" + $LockAfterHiddenSeconds + " s hidden) before its unlocked session ends (" + $SessionAwaySeconds + " s away): a lock drops the session, so the away time could never be kept")) }
    if ($script:HordePwaTransports -cnotcontains $Transport) { return (New-HordeUnknown -Reason ("'" + $Transport + "' is not a relay transport the app knows: " + ($script:HordePwaTransports -join ", "))) }
    $why = Test-HordePwaRelayOrigin -Origin $RelayOrigin
    if ($why -cne "") { return (New-HordeUnknown -Reason $why) }
    if (-not [System.IO.Path]::IsPathRooted($Out)) { return (New-HordeUnknown -Reason "the site's folder must be an absolute path") }
    $outFull = [System.IO.Path]::GetFullPath($Out)
    if ([System.IO.File]::Exists($outFull)) { return (New-HordeUnknown -Reason ("'" + $outFull + "' is a file")) }
    if ([System.IO.Directory]::Exists($outFull) -and @([System.IO.Directory]::GetFileSystemEntries($outFull)).Count -gt 0) { return (New-HordeUnknown -Reason ("'" + $outFull + "' is not empty: a build never writes over files it did not make")) }
    $root = Get-HordePwaRepoRoot
    # Read everything first: a missing or non-ASCII source refuses the build before a byte is written.
    $bytes = [ordered]@{}
    foreach ($site in @($script:HordePwaSiteFiles.Keys)) {
        $src = Join-Path $root ($script:HordePwaSiteFiles[$site] -replace '/', '\')
        if (-not [System.IO.File]::Exists($src)) { return (New-HordeUnknown -Reason ("the site's file " + $site + " has no source at " + $script:HordePwaSiteFiles[$site])) }
        $b = [System.IO.File]::ReadAllBytes($src)
        foreach ($x in $b) { if ($x -gt 126 -or ($x -lt 32 -and $x -ne 9 -and $x -ne 10 -and $x -ne 13)) { return (New-HordeUnknown -Reason ("the source of " + $site + " is not plain ASCII")) } }
        $bytes[$site] = $b
    }
    $ascii = [System.Text.Encoding]::ASCII
    $page = $ascii.GetString($bytes["app/index.html"])
    if ((Get-HordePwaPlaceholderCount -Text $page -Find $script:HordePwaCspPlaceholder) -ne 1) { return (New-HordeUnknown -Reason ("app/index.html must carry " + $script:HordePwaCspPlaceholder + " exactly once, in its policy line")) }
    $connect = $script:HordePwaCspPlaceholder + $(if ($RelayOrigin -cne "") { " " + $RelayOrigin } else { "" })
    $bytes["app/index.html"] = $ascii.GetBytes($page.Replace($script:HordePwaCspPlaceholder, $connect))
    $configText = '{"schemaVersion":1,"transport":"' + $Transport + '","relayOrigin":"' + $RelayOrigin + '","lockAfterHiddenSeconds":' + $LockAfterHiddenSeconds + ',"sessionAwaySeconds":' + $SessionAwaySeconds + '}' + "`n"
    $bytes["app/config.json"] = $ascii.GetBytes($configText)
    $bytes["app/icon-192.png"] = New-HordePwaIconPng -Size 192
    $bytes["app/icon-512.png"] = New-HordePwaIconPng -Size 512
    $bytes["index.html"] = $ascii.GetBytes("<!doctype html>`n<html lang=`"en`"><head><meta charset=`"utf-8`"><meta http-equiv=`"refresh`" content=`"0; url=app/index.html`"><title>Horde decisions</title></head><body><a href=`"app/index.html`">Horde decisions</a></body></html>`n")
    # The shell: every file the worker keeps - all but the worker itself and the root's redirect.
    $shell = @($bytes.Keys | Where-Object { $_ -cne "app/sw.js" -and $_ -cne "index.html" } | Sort-Object)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $all = New-Object System.IO.MemoryStream
        foreach ($p in $shell) { $name = $ascii.GetBytes($p + "`n"); $all.Write($name, 0, $name.Length); $all.Write($bytes[$p], 0, $bytes[$p].Length) }
        $version = (($sha.ComputeHash($all.ToArray()) | Select-Object -First 8 | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally { $sha.Dispose() }
    $worker = $ascii.GetString($bytes["app/sw.js"])
    if ((Get-HordePwaPlaceholderCount -Text $worker -Find $script:HordePwaVersionPlaceholder) -ne 1 -or (Get-HordePwaPlaceholderCount -Text $worker -Find $script:HordePwaShellPlaceholder) -ne 1) { return (New-HordeUnknown -Reason "app/sw.js must carry its VERSION and SHELL placeholder lines exactly once each") }
    $shellText = "const SHELL = [" + ((@($shell) | ForEach-Object { '"' + $_ + '"' }) -join ", ") + "];"
    $worker = $worker.Replace($script:HordePwaVersionPlaceholder, ('const VERSION = "' + $version + '";')).Replace($script:HordePwaShellPlaceholder, $shellText)
    $bytes["app/sw.js"] = $ascii.GetBytes($worker)
    # THE PAGE'S OWN VERSION, in its config: the hash cannot be inside a file it hashes, so it is written
    # into config.json after the hash is taken (of the config without it). The page shows it on the Account
    # screen and compares it with the worker's (surfaces/pwa/page/app-update.js).
    $bytes["app/config.json"] = $ascii.GetBytes($configText.Replace('{"schemaVersion":1,', '{"schemaVersion":1,"version":"' + $version + '",'))
    try {
        foreach ($site in @($bytes.Keys)) {
            $dest = Join-Path $outFull ($site -replace '/', '\')
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $dest))
            [System.IO.File]::WriteAllBytes($dest, $bytes[$site])
        }
    } catch { return (New-HordeUnknown -Reason "the site could not be written" -ErrorRecord $_) }
    return (New-HordeKnown -Value ([pscustomobject]@{ out = $outFull; version = $version; files = @($bytes.Keys); shell = $shell }))
}
