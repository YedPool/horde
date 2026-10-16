# IS THE PHONE APP BUILT AS IT MUST SHIP, AND DOES EACH OF ITS MODULES DO ITS ONE THING?
#
# The phone app's site and modules (relay design 2026-10-09, PR plan item 7). Three parts:
#   1. THE BUILD (surfaces/pwa/Site.ps1, New-HordePwaSite): the tree it writes, the relay origin written
#      into the page's policy and nothing else, the worker's version and shell, the config, and every
#      refusal - an unknown transport, an origin that is not one, a folder that is not empty.
#   2. THE SHIPPED FILES, READ: a policy with nothing inline and no eval; no inline script, style or
#      handler in the page; no eval, Function, innerHTML or document.write in any script; every import
#      a relative address of a file the site has; the transports the build knows equal to the ones the
#      app knows; ASCII throughout; capabilities.json valid, and no Surface.ps1, so Horde never picks
#      this folder to open.
#   3. THE MODULES, RUN (surfaces/pwa/test/units.mjs under Node, over the built site): HPKE against
#      RFC 9180, base64url's one spelling, the offer read, envelopes refused when forged, tampered or
#      not canonical, pages and freshness, two hordes, answers bound to machine and page, the recovery
#      code reading and never answering, the key wraps, a passkey with no PRF, the relay client's
#      distrust, and the bridge. Each line it prints is a check here.
#   4. THE UNLOCKED SESSION'S BYTES, through the PC's own reader and verifier: the envelopes part 3's
#      phone made under its session key (units.mjs, section 16) are read by relay/Envelope.ps1, the vouch
#      they carry verified by relay/WebAuthn.ps1 over relay/Session.ps1's challenge, and the session
#      signature by relay/P256.ps1 under the vouched key - the PowerShell the PC runs, never a copy.
# Node is needed for part 3; without it the suite says so and exits 3.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "surfaces\Port.ps1")
. (Join-Path $root "surfaces\pwa\Site.ps1")
. (Join-Path $root "relay\Envelope.ps1")
Set-StrictMode -Version Latest

$work = Join-Path $env:TEMP ("horde-pwa-site-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$ascii = [System.Text.Encoding]::ASCII
function Read-Site { param([string]$Site, [string]$Path) return [System.IO.File]::ReadAllText((Join-Path $Site ($Path -replace '/', '\')), $ascii) }
$partial = $false
function Remove-JsComments {
    # Comments say what is not done; the rules are about code, so comments are left out of the scans.
    param([string]$Text)
    return [regex]::Replace([regex]::Replace($Text, '/\*[\s\S]*?\*/', ''), '(?m)^\s*//.*$', '')
}
function Find-CodeHazard {
    # What a script must never do under the page's policy: run text as code, or write HTML or a style.
    param([string]$Text)
    $code = Remove-JsComments $Text
    return @(@("eval(", "new Function", "innerHTML", "outerHTML", "insertAdjacentHTML", "document.write", 'setAttribute("style"', "importScripts(") | Where-Object { $code.Contains($_) })
}
function Find-ImportSpec {
    # Every module address a script imports, statically or dynamically.
    param([string]$Text)
    $code = Remove-JsComments $Text
    return @([regex]::Matches($code, '(?m)^\s*(?:import|export)\s[^;"]*?\sfrom\s+"([^"]+)"|\bimport\(\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value + $_.Groups[2].Value })
}

try {
    Write-Host ""
    Write-Host "--- 1. the build ---" -ForegroundColor Cyan
    $site = Join-Path $work "site"
    $b = New-HordePwaSite -Out $site -Transport "memory" -RelayOrigin "https://relay.example.test"
    Check ($b.state -ceq "known") ("the site builds (" + $(if ($b.state -ceq "known") { $b.value.version } else { $b.reason }) + ")")
    $expected = @(@(Get-HordePwaSiteFiles).Keys) + @("app/config.json", "index.html", "app/icon-192.png", "app/icon-512.png")
    $written = @(Get-ChildItem -LiteralPath $site -Recurse -File | ForEach-Object { $_.FullName.Substring($site.Length + 1) -replace '\\', '/' } | Sort-Object)
    Check ((@($expected | Sort-Object) -join ",") -ceq ($written -join ",")) ("it writes exactly the site's files and the four it makes (" + $written.Count + ")")
    $page = Read-Site $site "app/index.html"
    $csp = [regex]::Match($page, '<meta http-equiv="Content-Security-Policy" content="([^"]*)">').Groups[1].Value
    Check ($csp.Contains("connect-src 'self' https://relay.example.test;")) "the relay's origin is written after connect-src 'self', and nowhere else"
    Check (([regex]::Matches($page, [regex]::Escape("https://relay.example.test"))).Count -eq 1) "the page names the origin once"
    $src = [System.IO.File]::ReadAllText((Join-Path $root "surfaces\pwa\page\index.html"), $ascii)
    Check ($page -ceq $src.Replace("connect-src 'self'", "connect-src 'self' https://relay.example.test")) "and the page is otherwise the source, byte for byte"
    foreach ($f in @(@(Get-HordePwaSiteFiles).Keys | Where-Object { $_ -cne "app/index.html" -and $_ -cne "app/sw.js" })) {
        $same = [System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes((Join-Path $site ($f -replace '/', '\'))), [byte[]][System.IO.File]::ReadAllBytes((Join-Path $root ((Get-HordePwaSiteFiles)[$f] -replace '/', '\'))))
        if (-not $same) { Check $false ("the site's " + $f + " is its source, byte for byte") }
    }
    Check ($true) "every other file is copied byte for byte (a difference is a failure above)"
    $config = (Read-Site $site "app/config.json") | ConvertFrom-Json
    Check ($config.schemaVersion -eq 1 -and $config.transport -ceq "memory" -and $config.relayOrigin -ceq "https://relay.example.test" -and $config.lockAfterHiddenSeconds -eq 600 -and $config.sessionAwaySeconds -eq 600) "config.json names the transport, the relay, ten minutes before a hidden app locks - no sooner than the session's away time, the founder's Q75 (c) - and the ten minutes away before its unlocked session ends"
    Check ((New-HordePwaSite -Out (Join-Path $work "x5") -Transport "memory" -SessionAwaySeconds 0).reason.Contains("1 to 86400 seconds")) "an away time of none is refused"
    Check ((New-HordePwaSite -Out (Join-Path $work "x6") -Transport "memory" -SessionAwaySeconds 86401).reason.Contains("1 to 86400 seconds")) "and so is one over a day"
    Check ((New-HordePwaSite -Out (Join-Path $work "x3") -Transport "memory" -LockAfterHiddenSeconds 0).reason.Contains("1 to 86400 seconds")) "a lock time of none is refused"
    $soon = New-HordePwaSite -Out (Join-Path $work "x7") -Transport "memory" -LockAfterHiddenSeconds 300
    Check ($soon.state -cne "known" -and $soon.reason.Contains("may not lock") -and -not (Test-Path -LiteralPath (Join-Path $work "x7\app"))) ("A LOCK SOONER THAN THE AWAY TIME IS REFUSED (the old five minutes against the ten): it would end every session first, Q75 (c) (" + $soon.reason + ")")
    $same = New-HordePwaSite -Out (Join-Path $work "x8") -Transport "memory" -LockAfterHiddenSeconds 600 -SessionAwaySeconds 600
    $later = New-HordePwaSite -Out (Join-Path $work "x9") -Transport "memory" -LockAfterHiddenSeconds 2 -SessionAwaySeconds 1
    Check ($same.state -ceq "known" -and $later.state -ceq "known") "CONTROL: a lock at the away time, or after it, builds"
    $sw = Read-Site $site "app/sw.js"
    $ver = [regex]::Match($sw, 'const VERSION = "([0-9a-f]{16})";').Groups[1].Value
    Check ($ver -ceq $b.value.version) "the worker carries the site's version"
    Check ($config.version -ceq $b.value.version -and $config.version -cmatch '\A[0-9a-f]{16}\z') "and config.json carries the same version, so the page knows its own (the Account screen says it)"
    $shell = @([regex]::Matches([regex]::Match($sw, 'const SHELL = \[([^\]]*)\];').Groups[1].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    Check ((@($shell) -join ",") -ceq (@($expected | Where-Object { $_ -cne "app/sw.js" -and $_ -cne "index.html" } | Sort-Object) -join ",")) ("and its shell is every file but itself and the root's redirect (" + $shell.Count + ")")
    $b2 = New-HordePwaSite -Out (Join-Path $work "site2") -Transport "memory" -RelayOrigin "https://relay.example.test"
    $b3 = New-HordePwaSite -Out (Join-Path $work "site3") -Transport "memory" -RelayOrigin "https://other.example.test"
    Check ($b2.value.version -ceq $b.value.version -and $b3.value.version -cne $b.value.version) "the same sources build the same version, and another deployment another, so its worker is new"
    $local = New-HordePwaSite -Out (Join-Path $work "site4") -Transport "binding"
    Check ($local.state -ceq "known" -and (Read-Site $local.value.out "app/index.html").Contains("connect-src 'self';")) "with no relay origin the page connects to its own site only"
    Check ((New-HordePwaSite -Out (Join-Path $work "x1") -Transport "cloud").reason.Contains("not a relay transport")) "an unknown transport is refused"
    foreach ($bad in @("http://relay.example.test", "https://relay.example.test/path", "https://*.example.test", "https://user@relay.example.test", "javascript:alert(1)", "https://relay.example.test 'unsafe-inline'")) {
        Check ((New-HordePwaSite -Out (Join-Path $work "x2") -Transport "memory" -RelayOrigin $bad).reason.Contains("is not a relay origin")) ("the origin '" + $bad + "' is refused")
    }
    Check ((New-HordePwaSite -Out $site -Transport "memory").reason.Contains("not empty")) "a folder that is not empty is never written into"
    Check (-not (Test-Path -LiteralPath (Join-Path $work "x2"))) "and a refused build writes nothing"

    Write-Host ""
    Write-Host "--- 2. the shipped files, read ---" -ForegroundColor Cyan
    foreach ($directive in @("default-src 'none'", "script-src 'self'", "style-src 'self'", "object-src 'none'", "base-uri 'none'", "form-action 'none'")) { Check ($csp.Contains($directive + ";") -or $csp.EndsWith($directive)) ("the policy says " + $directive) }
    Check (-not $csp.Contains("unsafe") -and -not $csp.Contains("data:") -and -not $csp.Contains("*")) "and nothing unsafe, no data: and no wildcard"
    $scripts = @([regex]::Matches($page, '<script([^>]*)>([\s\S]*?)</script>'))
    Check ($scripts.Count -ge 2 -and @($scripts | Where-Object { $_.Groups[2].Value.Trim() -ne "" -or $_.Groups[1].Value -notmatch '\ssrc="' }).Count -eq 0) ("no script is written into the page: every one is a file (" + $scripts.Count + ")")
    Check ($page -notmatch '<style' -and $page -notmatch '\sstyle=' -and $page -notmatch '\son[a-z]+=') "no style element, style attribute or handler attribute in the page"
    $codeFiles = @(@(Get-HordePwaSiteFiles).Keys | Where-Object { $_.EndsWith(".js") })
    $importCount = 0
    Check (@(Find-CodeHazard ("// eval(x) in a comment is not code" + "`n" + "var x = 1;")).Count -eq 0 -and @(Find-CodeHazard "el.innerHTML = s;").Count -eq 1 -and @(Find-ImportSpec ('import { a } from "./a.js";' + "`n" + 'const b = await import("../b.js");')).Count -eq 2) "CONTROL: the scans find a planted hazard and planted imports, and skip comments"
    foreach ($f in $codeFiles) {
        $t = Read-Site $site $f
        $hits = @(Find-CodeHazard $t)
        Check ($hits.Count -eq 0) ("" + $f + " uses no eval, no Function, no HTML strings and no style attribute (" + ($hits -join ", ") + ")")
        foreach ($spec in @(Find-ImportSpec $t)) {
            $importCount++
            $dir = [System.IO.Path]::GetDirectoryName(($f -replace '/', '\'))
            $ok = $spec -match '\A\.\.?/'
            if ($ok) { $resolved = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $site $dir) ($spec -replace '/', '\'))); $ok = $resolved.StartsWith($site + "\") -and (Test-Path -LiteralPath $resolved -PathType Leaf) }
            Check $ok ($f + " imports '" + $spec + "' by a relative address of a file the site has")
        }
    }
    Check ($importCount -ge 8) ("CONTROL: the import scan saw the app's imports (" + $importCount + ")")
    $known = @([regex]::Matches((Read-Site $site "app/relay-client.js"), 'name === "([a-z-]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
    Check (($known -join ",") -ceq (@(Get-HordePwaTransports | Sort-Object) -join ",")) ("the transports the build accepts are the ones the app knows (" + ($known -join ", ") + ")")
    $nonAscii = @(Get-ChildItem -LiteralPath (Join-Path $root "surfaces\pwa"), (Join-Path $root "relay\js") -Recurse -File | Where-Object { $_.Extension -ne ".png" } | Where-Object { @([System.IO.File]::ReadAllBytes($_.FullName) | Where-Object { $_ -gt 126 }).Count -gt 0 })
    Check ($nonAscii.Count -eq 0) ("every source of the app is ASCII (" + (@($nonAscii | ForEach-Object { $_.Name }) -join ", ") + ")")
    $caps = [System.IO.File]::ReadAllText((Join-Path $root "surfaces\pwa\capabilities.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $capFindings = @(Test-HordeSurfaceCapabilities -Capabilities $caps -Folder (Join-Path $root "surfaces\pwa"))
    Check ($capFindings.Count -eq 0) ("capabilities.json is valid against the schema, in the vocabulary every surface uses (" + ($capFindings -join "; ") + ")")
    Check (@(Get-HordeSurfaceFiles) -notcontains (Join-Path $root "surfaces\pwa\Surface.ps1") -and -not (Test-Path -LiteralPath (Join-Path $root "surfaces\pwa\Surface.ps1"))) "the folder registers no surface, so Horde never picks it to open a window"
    $manifest = (Read-Site $site "app/manifest.json") | ConvertFrom-Json
    Check ($manifest.display -ceq "standalone" -and $manifest.start_url -ceq "./index.html" -and @($manifest.icons | Where-Object { $_.sizes -ceq "192x192" }).Count -eq 1 -and @($manifest.icons | Where-Object { $_.sizes -ceq "512x512" }).Count -eq 1) "the manifest makes an installable app: standalone, its start page, icons of 192 and 512"
    foreach ($icon in @("app/icon-192.png", "app/icon-512.png")) {
        $png = [System.IO.File]::ReadAllBytes((Join-Path $site ($icon -replace '/', '\')))
        $w = ([int]$png[16] -shl 24) + ([int]$png[17] -shl 16) + ([int]$png[18] -shl 8) + [int]$png[19]
        Check ($png[1] -eq 0x50 -and $png[2] -eq 0x4E -and $png[3] -eq 0x47 -and $icon.Contains("-" + $w + ".")) ($icon + " is a PNG of the size its name says (" + $w + ")")
    }

    Write-Host ""
    Write-Host "--- 3. the modules, run ---" -ForegroundColor Cyan
    $node = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $node) {
        Write-Host "  [SKIP] node is not installed here, so the modules are not run" -ForegroundColor Yellow
        $partial = $true
    } else {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $node.Source
        $sessionOut = Join-Path $work "session-envelopes.json"
        $psi.Arguments = '"' + (Join-Path $here "units.mjs") + '" "' + $site + '" "' + $root + '" "' + $sessionOut + '"'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $errTask = $p.StandardError.ReadToEndAsync()
        $out = $p.StandardOutput.ReadToEnd()
        if (-not $p.WaitForExit(120000)) { $p.Kill() }
        $lines = @($out -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -ne "" })
        foreach ($l in $lines) {
            if ($l.StartsWith("[PASS] ")) { Check $true $l.Substring(7) }
            elseif ($l.StartsWith("[FAIL] ")) { Check $false $l.Substring(7) }
        }
        $doneLine = @($lines | Where-Object { $_.StartsWith("[DONE] ") })
        Check ($p.ExitCode -eq 0 -and $doneLine.Count -eq 1 -and @($lines | Where-Object { $_.StartsWith("[PASS] ") }).Count -ge 50) ("the module checks ran to their end (" + @($lines | Where-Object { $_.StartsWith("[PASS] ") }).Count + " passed; " + $errTask.Result.Trim() + ")")
        $p.Dispose()

        Write-Host ""
        Write-Host "--- 4. the unlocked session's bytes, through the PC's own reader and verifier ---" -ForegroundColor Cyan
        Check (Test-Path -LiteralPath $sessionOut) "CONTROL: the modules wrote the session envelopes their phone made"
        if (Test-Path -LiteralPath $sessionOut) {
            $js = [System.IO.File]::ReadAllText($sessionOut, $ascii) | ConvertFrom-Json
            $devicePub = ConvertFrom-HordeRelayBase64Url -Text $js.devicePublic -What "the passkey's key"
            foreach ($which in @("vouched", "opening")) {
                $r = Read-HordeRelayEnvelope -Text $js.$which
                Check ($r.ok -and $r.value.sig.alg -ceq "session" -and $null -ne $r.value.sig.vouch) ("the PC's reader takes the phone's " + $which + " envelope, its vouch read in full (" + $r.reason + ")")
                if (-not $r.ok) { continue }
                $s = $r.value.sig
                Check ($s.vouch.text -ceq $js.vouchText -and $s.vouch.deviceKeyId -ceq $r.value.header.from) "its vouch is the text the phone made, naming the passkey the envelope is from"
                $challenge = Get-HordeRelaySessionVouchChallenge -Text $s.vouch.text
                Check ((ConvertTo-HordeRelayHex -Bytes $challenge) -ceq $js.challenge) "the challenge the PC computes for it is the one the phone's passkey was asked to sign at unlock"
                $wa = Test-HordeRelayWebAuthnAssertion -Public $devicePub -AuthenticatorData $s.authenticatorData -ClientDataJson $s.clientDataJson -Signature $s.signature -Challenge $challenge -RpId $js.rpId -Origins @($js.origin) -RequireUserVerification $true
                Check ($wa.ok -and $wa.userVerified) ("the PC's WebAuthn verifier takes the unlock's assertion as the vouch, user verified (" + $wa.reason + ")")
                $other = Get-HordeRelaySessionVouchChallenge -Text ($s.vouch.text.Replace('"seq":', '"seq":1'))
                $wa2 = Test-HordeRelayWebAuthnAssertion -Public $devicePub -AuthenticatorData $s.authenticatorData -ClientDataJson $s.clientDataJson -Signature $s.signature -Challenge $other -RpId $js.rpId -Origins @($js.origin) -RequireUserVerification $true
                Check (-not $wa2.ok) "CONTROL: over another vouch's challenge the same assertion is refused"
                $signed = Get-HordeRelaySessionSigningInput -VouchId $s.vouchId -Signed (Get-HordeRelaySigningInput -HeaderText $r.value.headerText -RecipientsText $r.value.recipientsText -CtText $r.value.ctText)
                Check (Test-HordeRelayEs256Signature -Public $s.vouch.sessionPublic -Bytes $signed -Signature $s.value -AllowHighS) "and its session signature verifies under the vouched key"
            }
            $bare = Read-HordeRelayEnvelope -Text $js.bare
            $first = Read-HordeRelayEnvelope -Text $js.vouched
            Check ($bare.ok -and $bare.value.sig.alg -ceq "session" -and $null -eq $bare.value.sig.vouch) ("the PC's reader takes the bare envelope, the vouchId alone (" + $bare.reason + ")")
            if ($bare.ok -and $first.ok) {
                $signed = Get-HordeRelaySessionSigningInput -VouchId $bare.value.sig.vouchId -Signed (Get-HordeRelaySigningInput -HeaderText $bare.value.headerText -RecipientsText $bare.value.recipientsText -CtText $bare.value.ctText)
                Check ($bare.value.sig.vouchId -ceq $first.value.sig.vouchId -and (Test-HordeRelayEs256Signature -Public $first.value.sig.vouch.sessionPublic -Bytes $signed -Signature $bare.value.sig.value -AllowHighS)) "and it is signed by the same session key, under the same vouch"
            }
        }
    }
} finally {
    if ((Split-Path -Leaf $work) -match '^horde-pwa-site-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"
}

if ($partial) { Complete-HordeSuite -Success "the build and the shipped files are right; the modules were not run (no node)" -PassCode 3 }
Complete-HordeSuite -Success "the phone app builds as it must ship, its files hold to the policy, and each module does its one thing"
