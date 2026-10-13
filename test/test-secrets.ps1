# DOES CORE FIND EVERY SECRET SHAPE THE DECISIONS MODULE REFUSES, AND HIDE ALL OF EACH ONE WHEN ASKED TO?
#
# core/Secrets.ps1 is the one statement of what looks like a credential (relay design 2026-10-09, PR
# plan item 9: the detector lifted from decisions/Rules.ps1 into core, with a redact mode). Two callers,
# two uses, one list:
#   - decisions REFUSES: a question holding a secret is not written (test/test-decisions-rules.ps1 holds
#     that, unchanged, through decisions' own names, which now only call this file);
#   - conversations REDACT: a Thrall's turn is kept, with every secret in it replaced by a marker, before
#     it leaves the machine (conversations/Port.ps1).
# This suite attacks the redact mode and the single source:
#   - EVERY KIND IS HIDDEN WHOLE. Several of the refusal patterns match only the START of a secret (a
#     name=value pattern stops at the value's first character, a key header stops at the header, a
#     signed web token stops before its signature): enough to refuse, not enough to hide. Each planted
#     secret must be gone entirely - not only the part the pattern matched - and so must every 8
#     characters of its random part.
#   - WHAT IS AROUND IT STAYS: the words before and after, line breaks, non-ASCII text.
#   - NEAR MISSES STAY WHOLE, the same controls decisions keeps (paths, a UUID, a commit id, the word
#     password in a sentence), and a text with nothing in it comes back identical, count 0.
#   - THE MARKER IS NOT A SECRET: redacting twice is redacting once.
#   - ONE SOURCE: decisions/ holds no pattern of its own any more, and its kind function answers what
#     this file answers, for every planted case and every control.
# Every planted secret is assembled from pieces at run time, as test/test-decisions-rules.ps1 does, so
# no credential-shaped text sits in this file.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\Secrets.ps1")

$mark = Get-HordeSecretMark

function Get-Pieces {
    # Every 8-character piece of a secret's random part: none may survive redaction.
    param([string]$Text)
    $out = New-Object System.Collections.ArrayList
    for ($i = 0; $i + 8 -le $Text.Length; $i += 4) { [void]$out.Add($Text.Substring($i, 8)) }
    return @($out)
}

Write-Host ""
Write-Host "--- every kind is hidden whole, and what is around it stays ---" -ForegroundColor Cyan
# name = @(the planted text, the part that must vanish entirely)
$planted = [ordered]@{
    # The body in lines too short for the long-run patterns, so only the widening to the END line hides it.
    "a private key block" = @(("-----BEGIN RSA PRIV" + "ATE KEY-----`nMIIEow" + "IBAAKCAQEAx9Qm`n2Lp7Rt4Vb8Nc1Hdq3J9s`nZr8Lm2Xv0Bn5Ty7Uw1Ae`n-----END RSA PRIV" + "ATE KEY-----"), ("MIIEow" + "IBAAKCAQEAx9Qm"))
    "an access token" = @(("gh" + "p_" + ("Ab1" * 12)), ("Ab1" * 12))
    "a signed web token, signature too" = @(("ey" + "JhbGciOiJIUzI1NiJ9" + "." + "ey" + "JzdWIiOiIxMjM0In0" + "." + "c2lnbmF0dXJlLXBhcnQ"), "c2lnbmF0dXJlLXBhcnQ")
    "a bearer token" = @(("Bea" + "rer " + ("a1b2c3d4e5" * 3)), ("a1b2c3d4e5" * 3))
    "a password as name=value, the whole value" = @(("pass" + "word=" + "hunter2longer"), "hunter2longer")
    "a token as name = value with spaces" = @(("TOK" + "EN = " + "q8Wv3Lm9Zr"), "q8Wv3Lm9Zr")
    "a password after a colon" = @(("Pass" + "word: " + "hunter2x"), "hunter2x")
    "a password in a sentence, quoted" = @(("the pass" + "word is 'correct horse battery staple'"), "correct horse battery staple")
    "a password inside an address" = @(("https://deploy:Tr0ub4dor3x@" + "git.example.com/repo.git"), "Tr0ub4dor3x")
    "a webhook address" = @(("https://hooks.slack.com/services/T00000000/B00000000/" + "XyXyXyXyXyXyXyXyXyXyXyXy"), "XyXyXyXyXyXyXyXyXyXyXyXy")
    "an Authorization header" = @(("Authorization: Basic " + "ZGVwbG95OlRyMHViNGRvcjM="), "ZGVwbG95OlRyMHViNGRvcjM=")
    "a long random-looking string" = @(("Zx9Qm2Lp7Rt4Vb8Nc1Hd" + "6Jf3Kg5Ws0YaUe4Ti7Ro"), ("Zx9Qm2Lp7Rt4Vb8Nc1Hd" + "6Jf3Kg5Ws0YaUe4Ti7Ro"))
    "a cloud secret key with slashes" = @(("wJalrXUtnFEMI/K7MDENG/" + "bPxRfiCYEXAMPLEKEY"), ("wJalrXUtnFEMI/K7MDENG/" + "bPxRfiCYEXAMPLEKEY"))
}
foreach ($name in $planted.Keys) {
    $secret = $planted[$name][0]
    $core = $planted[$name][1]
    $text = "Before the line.`nThe value is " + $secret + " and after it come more words.`nLast line."
    $r = Protect-HordeSecretText -Text $text
    $left = @(Get-Pieces $core | Where-Object { $r.text.Contains($_) })
    Check (-not $r.text.Contains($core) -and $left.Count -eq 0) ("redacted whole: " + $name + $(if ($left.Count) { " (" + $left.Count + " piece(s) of it left)" } else { "" }))
    Check ($r.count -ge 1 -and $r.text.Contains($mark)) ("and the marker stands where it was, counted (" + $r.count + ")")
    Check ($r.text.StartsWith("Before the line.`nThe value is ") -and $r.text.EndsWith("more words.`nLast line.")) "and the words before and after it are kept, line breaks included"
}

Write-Host ""
Write-Host "--- every shape decisions refuses is also redacted ---" -ForegroundColor Cyan
# The same twelve extra shapes test/test-decisions-rules.ps1 refuses: a shape refused and not hidden
# would leave the phone a secret that the decisions page could never have shown.
$more = @("gh" + "o_" + ("Cd2" * 12); "github" + "_pat_" + ("Ef3" * 10); "gl" + "pat-" + ("Gh4" * 8); "xo" + "xb-" + ("123456789012" * 2); "s" + "k-" + ("Ij5" * 10); "AK" + "IA" + "ABCDEFGHIJKLMNOP"; "AS" + "IA" + "QRSTUVWXYZ234567"; "AI" + "za" + ("Kl6" * 12); "api_" + "key = " + "abcdef12"; "TOK" + "EN=" + "xyzzy99"; "-----BEGIN PRIV" + "ATE KEY-----"; "-----BEGIN EC PRIV" + "ATE KEY-----")
foreach ($s in $more) {
    $kind = Find-HordeSecretKind -Text ("see " + $s + " here")
    $r = Protect-HordeSecretText -Text ("see " + $s + " here")
    $tail = $s.Substring([Math]::Max(0, $s.Length - 6))
    Check ($kind -ne "" -and $r.count -ge 1 -and -not $r.text.Contains($tail)) ("found and hidden, to its last character: a " + $s.Length + "-character shape of the kind " + $kind)
}

Write-Host ""
Write-Host "--- near misses stay whole ---" -ForegroundColor Cyan
$ordinary = @(
    "api/v2/Customers/Invoices/Search/ByDateRange/Page"
    "See https://example.org/notes/closing-sound:draft for the proposal"
    "Write to support@example.org or see https://example.org/help"
    "The bearer of the news was Orc3 again"
    "A password is needed before this can be tested"
    "password: ask whoever owns the test account"
    "07af8361c2d4e5f60718293a4b5c6d7e8f901234"
    "0273216a-4aa6-420b-8bd6-b5d61a13d73d"
    "C:\Work\horde-worktrees\decisions2\test\fixtures\a-rather-long-file-name-for-a-fixture.json"
    "feature-decisions-store-first-slice-of-the-new-module"
    ("Plain words, " + [char]0x05D4 + [char]0x05D0 + [char]0x05DD + ", and more words.")
)
foreach ($o in $ordinary) {
    $r = Protect-HordeSecretText -Text $o
    Check ($r.text -ceq $o -and $r.count -eq 0) ("kept whole: " + $o.Substring(0, [Math]::Min(40, $o.Length)))
}
$r = Protect-HordeSecretText -Text ""
Check ($r.text -ceq "" -and $r.count -eq 0) "an empty text is empty, count 0"
$big = ("word " * 20000)
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$r = Protect-HordeSecretText -Text $big
$clock.Stop()
Check ($r.text -ceq $big -and $r.count -eq 0) ("100,000 characters of words come back whole, in " + $clock.ElapsedMilliseconds + " ms")

Write-Host ""
Write-Host "--- several secrets, overlapping shapes, and the marker ---" -ForegroundColor Cyan
$two = "first " + $planted["an access token"][0] + " then " + $planted["a password after a colon"][0] + " end"
$r = Protect-HordeSecretText -Text $two
Check ($r.count -eq 2 -and -not $r.text.Contains("Ab1Ab1") -and -not $r.text.Contains("hunter2x") -and $r.text.StartsWith("first ") -and $r.text.EndsWith(" end")) ("two secrets in one text are both hidden, counted 2 (" + $r.count + ")")
# A bearer token is also a long random string: two patterns over one span hide it once.
$r = Protect-HordeSecretText -Text ("use " + ("Bea" + "rer " + "Q1w2E3r4T5y6U7i8O9p0Aa1Ss2Dd3Ff4") + " now")
Check ($r.count -eq 1 -and ([regex]::Matches($r.text, [regex]::Escape($mark))).Count -eq 1 -and -not $r.text.Contains("Q1w2E3")) ("overlapping matches are merged into one marker (" + $r.count + ")")
$again = Protect-HordeSecretText -Text $r.text
Check ($again.text -ceq $r.text -and $again.count -eq 0) "redacting a redacted text changes nothing: the marker is not a secret"
Check ((Find-HordeSecretKind -Text $mark) -eq "") "CONTROL: the marker is not found as a secret"

Write-Host ""
Write-Host "--- one source: decisions holds no pattern, and answers what core answers ---" -ForegroundColor Cyan
$rulesText = [System.IO.File]::ReadAllText((Join-Path $root "decisions\Rules.ps1"))
Check (-not $rulesText.Contains("PRIV" + "ATE KEY") -and -not $rulesText.Contains("HordeDecisionSecretPatterns") -and -not $rulesText.Contains("HordeDecisionSecretRunPattern")) "decisions/Rules.ps1 defines no secret pattern of its own"
$secretsText = [System.IO.File]::ReadAllText((Join-Path $root "core\Secrets.ps1"))
Check ($secretsText.Contains("PRIV" + "ATE KEY")) "CONTROL: the same search finds the pattern in core/Secrets.ps1"
. (Join-Path $root "decisions\Rules.ps1")
$all = @($planted.Keys | ForEach-Object { $planted[$_][0] }) + $more + $ordinary
$differ = @($all | Where-Object { (Find-HordeDecisionSecretKind -Text $_) -cne (Find-HordeSecretKind -Text $_) })
Check ($differ.Count -eq 0) ("decisions' kind function answers exactly what core's does, over " + $all.Count + " planted and ordinary texts (" + $differ.Count + " differ)")
Check ((Get-HordeTextBits -Text "abcd") -eq 2.0 -and (Get-HordeTextBits -Text "aaaa") -eq 0.0) "the entropy: 2 bits a character for four distinct letters, 0 for one repeated"

Write-Host ""
Write-Host "--- a caller may name which kinds are looked for, and every other caller is as before ---" -ForegroundColor Cyan
$runKind = "a long random-looking string, as a key or token is"
$tokenText = "see " + $planted["an access token"][0] + " here"
$keyText = "see " + $planted["a private key block"][0] + " here"
$runText = "see " + $planted["a long random-looking string"][0] + " here"
$slashText = "see " + $planted["a cloud secret key with slashes"][0] + " here"
$pairText = "see " + $planted["a password as name=value, the whole value"][0] + " here"
Check ((Find-HordeSecretKind -Text $tokenText -Kinds @("an access token")) -ceq "an access token") "asked for one kind, a text holding that kind answers it"
Check ((Find-HordeSecretKind -Text $tokenText -Kinds @("a private key")) -ceq "") "asked for another kind, the same text answers nothing"
Check ((Find-HordeSecretKind -Text $tokenText) -ceq "an access token") "CONTROL: asked for no kind in particular, it answers as it always did"
Check ((Find-HordeSecretKind -Text $pairText -Kinds @("a private key", "an access token", "a signed web token", "a webhook address")) -ceq "" -and (Find-HordeSecretKind -Text $pairText) -ceq "a password or key written as name=value") "a kind that was not asked for is not looked for, though the text holds it"
Check ((Find-HordeSecretKind -Text ($pairText + " " + $keyText) -Kinds @("an access token", "a private key")) -ceq "a private key") "of several kinds asked for, the answer is the one the text holds, whatever order they were named in"
Check ((Find-HordeSecretKind -Text $runText -Kinds @("an access token")) -ceq "" -and (Find-HordeSecretKind -Text $slashText -Kinds @("an access token")) -ceq "") "THE TWO LONG-RUN LOOKS ARE NOT USED unless their kind is asked for: a random-looking string and a key with slashes answer nothing"
Check ((Find-HordeSecretKind -Text $runText) -ceq $runKind -and (Find-HordeSecretKind -Text $slashText) -ceq $runKind) "CONTROL: asked for no kind in particular, both are found, as before"
function Get-KindOrThrew { param([string]$Text, [string[]]$Kinds) try { return ("" + (Find-HordeSecretKind -Text $Text -Kinds $Kinds)) } catch { return ("threw: " + $_.Exception.Message) } }
Check ((Get-KindOrThrew -Text $runText -Kinds @($runKind)) -ceq $runKind -and (Get-KindOrThrew -Text $slashText -Kinds @($runKind)) -ceq $runKind) "and asked for by their own kind, they are found"
Check ((Find-HordeSecretKind -Text $tokenText) -ceq "an access token" -and (Get-KindOrThrew -Text $tokenText -Kinds @($runKind)) -ceq "") "while a token of a known shape, which is no random-looking run, then answers nothing: the patterns are not used"
Check ((Find-HordeSecretKind -Text $tokenText -Kinds @()) -ceq "an access token" -and (Find-HordeSecretKind -Text $runText -Kinds @()) -ceq $runKind) "an empty list of kinds is every kind"
$threw = ""
try { $null = Find-HordeSecretKind -Text "plain words" -Kinds @("an access tokin") } catch { $threw = "$($_.Exception.Message)" }
Check ($threw -like "*'an access tokin' is not a kind of secret*") "a kind that is no kind throws, and never answers 'no secret' for a misspelt name"
$threw = ""
try { $null = Find-HordeSecretKind -Text "plain words" -Kinds @("an access token", "A Private Key") } catch { $threw = "$($_.Exception.Message)" }
Check ($threw -like "*'A Private Key' is not a kind*") "and a kind is named exactly, in its own case"
$allKinds = @("a private key", "an access token", "a signed web token", "a bearer token", "a password or key written as name=value", "a password written after a colon", "a password written in a sentence", "a password inside an address", "a webhook address", "an authorization value", $runKind)
$differ = @($all | Where-Object { (Find-HordeSecretKind -Text $_ -Kinds $allKinds) -cne (Find-HordeSecretKind -Text $_) })
Check ($differ.Count -eq 0) ("asked for all eleven kinds by name, every planted and ordinary text answers as it does asked for none (" + $differ.Count + " of " + $all.Count + " differ)")

Complete-HordeSuite -Success "every secret shape is found and hidden whole, near misses stay, and decisions reads the one list"
