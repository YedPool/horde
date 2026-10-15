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

Write-Host ""
Write-Host "--- a secret under its own name: found only when that kind is named, and every other caller is as before ---" -ForegroundColor Cyan
# THE ONE KIND THAT IS LOOKED FOR ONLY WHEN A CALLER NAMES IT (review of the files deny list,
# 2026-10-13). Two things are held here: that no caller who names no kind, and no caller who names
# other kinds, finds anything it did not find before; and the rule itself, attacked from both
# sides. Every name and every value is assembled from pieces, and no value was ever a credential.
$namedKind = "a secret written under a name such as client_secret or password"
$made = "Ab3dEf6h" + "Ij9kLm2n"
$six = @(("client_" + "secret"), ("private_" + "key"), ("refresh_" + "token"), ("access_" + "token"), ("api_" + "key"), ("pass" + "word"))
function Test-Named { param([string]$Text) return ((Get-KindOrThrew -Text $Text -Kinds @($namedKind)) -ceq $namedKind) }
function Get-Member { param([string]$Name, [string]$Value) return ('{"' + $Name + '":"' + $Value + '"}') }
$defaultKinds = (@($script:HordeSecretKinds.Keys) -join " | ")
Check ($defaultKinds -ceq "a private key | an access token | a signed web token | a bearer token | a password or key written as name=value | a password written after a colon | a password written in a sentence | a password inside an address | a webhook address | an authorization value") ("THE DEFAULT SET IS WHAT IT WAS: the ten kinds every caller is answered from, in their order (" + @($script:HordeSecretKinds.Keys).Count + ")")
Check (@($script:HordeSecretKinds.Keys) -cnotcontains $namedKind -and $allKinds -cnotcontains $namedKind -and $allKinds.Count -eq 11) "and the new kind is none of them, nor one of the eleven that 'every kind' means"
$onlyNamed = @((Get-Member $six[0] $made), ($six[0] + "=" + $made), ("{'" + $six[2] + "': '" + $made + "'}"))
foreach ($text in $onlyNamed) {
    Check (Test-Named $text) ("asked for by its name, a " + $text.Length + "-character text holding a secret under its own name answers that kind")
    Check ((Find-HordeSecretKind -Text $text) -ceq "" -and (Find-HordeSecretKind -Text $text -Kinds @()) -ceq "") "and the same text, asked with no kind named or an empty list, answers NOTHING, as it did before the kind was added"
    Check ((Find-HordeSecretKind -Text $text -Kinds $allKinds) -ceq "" -and (Find-HordeSecretKind -Text $text -Kinds @("an access token", "a private key")) -ceq "") "nor does a caller who names other kinds find it, all eleven of them or two"
    $kept = Protect-HordeSecretText -Text $text
    Check ($kept.text -ceq $text -and $kept.count -eq 0) "and the redact mode does not know the kind: the text comes back whole, count 0"
}
Check ((Find-HordeSecretKind -Text ("see " + $planted["an access token"][0] + " and " + (Get-Member $six[4] $made)) -Kinds @($namedKind, "an access token")) -ceq "an access token") "of the new kind and a listed one, both asked for and both held, the listed one answers first"
$differ = @($all | Where-Object { (Find-HordeSecretKind -Text $_ -Kinds ($allKinds + @($namedKind))) -cne (Find-HordeSecretKind -Text $_) -and (Find-HordeSecretKind -Text $_) -cne "" })
Check ($differ.Count -eq 0) ("every planted text that held a kind before still answers that kind when the new one is asked for beside the eleven (" + $differ.Count + " differ)")
$missed = @($six | Where-Object { -not (Test-Named (Get-Member $_ $made)) })
Check ($six.Count -eq 6 -and $missed.Count -eq 0) ("each of the six names is found as a JSON member" + $(if ($missed.Count) { " (MISSED: " + ($missed -join ", ") + ")" } else { "" }))
$missed = @($six | Where-Object { -not (Test-Named ("setting " + $_ + "=" + $made + " in the file")) })
Check ($missed.Count -eq 0) ("and each as name=value" + $(if ($missed.Count) { " (MISSED: " + ($missed -join ", ") + ")" } else { "" }))
$nl = "`r`n"
$kelvin = "api_" + [char]0x212A + "ey"
$attacks = @(
    # --- the member with a colon ---
    @{ found = $true; what = "the member name in capitals"; text = (Get-Member $six[4].ToUpperInvariant() $made) },
    @{ found = $true; what = "the member name in mixed case"; text = (Get-Member ("Client_" + "Secret") $made) },
    @{ found = $true; what = "blanks round the colon"; text = ('{"' + $six[4] + '" : "' + $made + '"}') },
    @{ found = $true; what = "line breaks round the colon, as a file written out over several lines has"; text = ('{' + $nl + '    "' + $six[4] + '"' + $nl + '    :' + $nl + '    "' + $made + '"' + $nl + '}') },
    @{ found = $true; what = "single quotes round the name and the value"; text = ("{'" + $six[4] + "': '" + $made + "'}") },
    @{ found = $true; what = "the name in double quotes and the value in single"; text = ('{"' + $six[4] + '": ' + "'" + $made + "'}") },
    @{ found = $true; what = "the name nested deep"; text = ('{"a":{"b":[{"c":{"d":{"' + $six[2] + '":"' + $made + '"}}}]}}') },
    @{ found = $true; what = "a value with escaped quotes inside"; text = ('{"' + $six[5] + '":"Ab3d\"Ef6h\"Ij9k"}') },
    @{ found = $true; what = "a value of exactly 8 characters"; text = (Get-Member $six[5] "Ab3dEf6h") },
    @{ found = $true; what = "a placeholder first and a real value after it: every match is looked at"; text = ('{"' + $six[5] + '":"<paste-it-here>","' + $six[4] + '":"' + $made + '"}') },
    @{ found = $false; what = "a value of 7 characters"; text = (Get-Member $six[5] "Ab3dEf6") },
    @{ found = $false; what = "an empty value"; text = (Get-Member $six[5] "") },
    @{ found = $false; what = "a value that holds white space"; text = (Get-Member $six[5] "correct horse battery staple") },
    @{ found = $false; what = "the name as a VALUE and not as a name"; text = ('{"kind":"' + $six[0] + '","grant_type":"' + $six[2] + '","next":"' + $made + '"}') },
    @{ found = $false; what = "a value that is a number"; text = ('{"' + $six[5] + '":1234567890123}') },
    @{ found = $false; what = "a value that is null"; text = ('{"' + $six[3] + '":null}') },
    @{ found = $false; what = "a value that is true"; text = ('{"' + $six[4] + '":true}') },
    @{ found = $false; what = "a value that is an OBJECT, as a schema describes the member"; text = ('{"properties":{"' + $six[0] + '":{"type":"string","description":"whatever-the-provider-issued"}}}') },
    @{ found = $false; what = "KNOWN LIMIT: a value that is a list holding the secret"; text = ('{"' + $six[3] + '":["' + $made + '"]}') },
    @{ found = $true; what = "a PREFIXED member name, the name at the end of a longer one (my_api_key)"; text = (Get-Member ("my_" + $six[4]) $made) },
    @{ found = $false; what = "the name at the start of a longer member name"; text = (Get-Member ($six[4] + "_id") $made) },
    @{ found = $false; what = "a look-alike letter in the name (U+212A for k)"; text = (Get-Member $kelvin $made) },
    @{ found = $true; what = "YAML: the name with no quotes before a colon"; text = ($six[5] + ": " + $made) },
    @{ found = $false; what = "KNOWN LIMIT: JSON written inside a JSON string, its quotes escaped"; text = ('{"body":"{\"' + $six[5] + '\":\"' + $made + '\"}"}') },
    # --- each placeholder form, in a member ---
    @{ found = $false; what = "a placeholder in angle brackets"; text = (Get-Member $six[4] "<paste-it-here>") },
    @{ found = $false; what = "a placeholder that only closes an angle bracket"; text = (Get-Member $six[4] "paste-it-here>") },
    @{ found = $false; what = "a placeholder with a dollar sign"; text = (Get-Member $six[4] '$THE_VALUE_HERE') },
    @{ found = $false; what = "a placeholder in braces"; text = (Get-Member $six[4] "{{the_value_here}}") },
    @{ found = $false; what = "a placeholder with three dots"; text = (Get-Member $six[4] "Ab3dEf6h...Ij9k") },
    @{ found = $false; what = "a placeholder holding the word your"; text = (Get-Member $six[4] "put-YOUR-value-here") },
    @{ found = $false; what = "a placeholder that is all x"; text = (Get-Member $six[4] "xxxxxxxxxxxx") },
    @{ found = $false; what = "a placeholder that is all X"; text = (Get-Member $six[4] "XXXXXXXXXXXX") },
    @{ found = $false; what = "a placeholder holding the word example"; text = (Get-Member $six[4] "an-Example-value") },
    @{ found = $false; what = "a placeholder holding the word changeme"; text = (Get-Member $six[4] "ChangeMe-please") },
    @{ found = $false; what = "a placeholder holding the word redacted"; text = (Get-Member $six[4] "[REDACTED]-value") },
    @{ found = $false; what = "a placeholder word with real text round it: the word anywhere in the value makes it one"; text = (Get-Member $six[4] ("Ab3dEf6h-CHANGEME-" + "Ij9kLm2n")) },
    # --- name=value ---
    @{ found = $true; what = "name=value in capitals"; text = ($six[4].ToUpperInvariant() + "=" + $made) },
    @{ found = $true; what = "blanks round the equals sign"; text = ($six[4] + " = " + $made) },
    @{ found = $true; what = "a tab before the value"; text = ($six[4] + "=`t" + $made) },
    @{ found = $true; what = "double quotes round the value"; text = ($six[4] + ' = "' + $made + '"') },
    @{ found = $true; what = "single quotes round the value"; text = ($six[4] + "='" + $made + "'") },
    @{ found = $true; what = "export in front"; text = ("export " + $six[4].ToUpperInvariant() + "=" + $made) },
    @{ found = $true; what = "the name in an address, after a question mark"; text = ("https://example.org/callback?" + $six[3] + "=" + $made + "&state=1") },
    @{ found = $true; what = "the name after a dot, as a properties file writes it"; text = ("db." + $six[5] + "=" + $made) },
    @{ found = $true; what = "the name after two dashes, as a command line writes it"; text = ("tool --" + $six[5] + "=" + $made) },
    @{ found = $true; what = "a bare value of exactly 8 characters"; text = ($six[5] + "=Ab3dEf6h") },
    @{ found = $false; what = "code that gives the name a value from an indexed lookup (os.environ[...])"; text = ($six[5] + ' = os.environ["THE_NAME_OF_IT"]') },
    @{ found = $false; what = "a bare value of 7 characters"; text = ($six[5] + "=Ab3dEf6 and more words") },
    @{ found = $false; what = "a quoted value of 7 characters"; text = ($six[5] + '="Ab3dEf6"') },
    @{ found = $false; what = "a quoted value that holds a blank"; text = ($six[5] + ' = "two words here"') },
    @{ found = $false; what = "the name as part of a longer name"; text = ("my_" + $six[4] + "_name=" + $made) },
    @{ found = $true; what = "a PREFIXED name=value (DB_PASSWORD)"; text = ("DB_" + $six[5].ToUpperInvariant() + "=" + $made) },
    @{ found = $false; what = "the name at the start of a longer name"; text = ($six[5] + "_hash=" + $made) },
    @{ found = $true; what = "the name written without its underscore (apikey)"; text = (("api" + "key") + "=" + $made) },
    @{ found = $false; what = "a shell line that reads the value from a variable"; text = ($six[5] + '=$DB_PASS_VALUE') },
    @{ found = $false; what = "a shell line that reads it from a variable in braces and quotes"; text = ($six[4] + '="${THE_KEY_VALUE}"') },
    @{ found = $false; what = "a shell line that reads it from a command"; text = ($six[5] + '=$(cat /run/the-file-it-is-in)') },
    @{ found = $false; what = "an empty value with another setting on the next line: the value never comes from the next line"; text = ($six[4] + "=" + $nl + "another_setting=" + $made) },
    @{ found = $false; what = "a comparison with two equals signs"; text = ("if (" + $six[4] + "==" + $made + ")") },
    @{ found = $false; what = "a placeholder in angle brackets after the equals sign"; text = ($six[4] + "=<paste-it-here>") },
    @{ found = $false; what = "a placeholder holding the word your after the equals sign"; text = ("export " + $six[4].ToUpperInvariant() + "=your-value-goes-here") })
# THE NEXT ROUND OF THE REVIEW (2026-10-13): the name is FOLDED (underscores, dashes and case do not
# count), may have a PREFIX, may stand before a YAML colon, and an unquoted value with a parenthesis in
# it is code. Each from both sides; the names are assembled from pieces like the six above.
$cs = "client" + "Secret"; $ak = "api" + "Key"
$attacks += @(
    # --- the name folded, and prefixed ---
    @{ found = $true; what = "a camelCase member name (clientSecret)"; text = (Get-Member $cs $made) },
    @{ found = $true; what = "a camelCase name=value (apiKey)"; text = ($ak + "=" + $made) },
    @{ found = $true; what = "a dashed name before a YAML colon (client-secret)"; text = (("client-" + "secret") + ": " + $made) },
    @{ found = $true; what = "a prefixed name before a YAML colon (google_client_secret)"; text = (("google_client_" + "secret") + ": " + $made) },
    @{ found = $true; what = "a prefixed camelCase member (googleClientSecret)"; text = (Get-Member ("google" + $cs.Substring(0, 1).ToUpperInvariant() + $cs.Substring(1)) $made) },
    @{ found = $true; what = "a prefixed name in capitals (GOOGLE_CLIENT_SECRET=)"; text = (("GOOGLE_CLIENT_" + "SECRET") + "=" + $made) },
    @{ found = $true; what = "a dash between two letters of the name is folded too (pass-word=)"; text = (("pass-" + "word") + "=" + $made) },
    @{ found = $true; what = "a command line's two dashes and a camelCase name (--apiKey=)"; text = ("tool --" + $ak + "=" + $made) },
    @{ found = $false; what = "a name that goes on past the six names something else (password_hash)"; text = ($six[5] + "_hash: " + $made) },
    @{ found = $false; what = "DECIDED: client_secret_path names where the file is, not the secret"; text = ($six[0] + "_path: ./secrets/client-file.json") },
    @{ found = $false; what = "and the same in camelCase (clientSecretPath)"; text = (Get-Member ($cs + "Path") "C:\secrets\client-file.json") },
    @{ found = $false; what = "a name that only holds the letters of one of the six in the middle (passwordless_login)"; text = ($six[5] + "less_login=" + $made) },
    # --- YAML ---
    @{ found = $true; what = "YAML with the value in double quotes"; text = ($six[0] + ': "' + $made + '"') },
    @{ found = $true; what = "YAML with the value in single quotes"; text = ($six[0] + ": '" + $made + "'") },
    @{ found = $true; what = "YAML indented under a parent key"; text = ("google:" + $nl + "  " + $six[0] + ": " + $made + $nl + "  client_id: abc") },
    @{ found = $true; what = "YAML with a comment after the value"; text = ($six[5] + ": " + $made + "  # the one for the test box") },
    @{ found = $true; what = "YAML with blanks after the value, then a line break"; text = ($six[5] + ": " + $made + "   " + $nl + "next: 1") },
    @{ found = $true; what = "YAML at the very end of the text"; text = ("a: 1" + $nl + $six[4] + ": " + $made) },
    @{ found = $true; what = "a bare literal with a digit and a comma after it is a value, in an object or a list (round 2 of the review of PR 238)"; text = ($ak + ": " + $made + ",") },
    @{ found = $false; what = "YAML placeholder in angle brackets"; text = ($six[0] + ": <your-client-secret>") },
    @{ found = $false; what = "YAML placeholder in capitals with the word your"; text = ($six[0] + ": YOUR_CLIENT_SECRET") },
    @{ found = $false; what = "YAML placeholder read from the environment"; text = ($six[0] + ': ${GOOGLE_CLIENT_SECRET}') },
    @{ found = $false; what = "a page that explains a setting: words after the colon"; text = ($six[5] + ": required for login") },
    @{ found = $false; what = "a page that explains a setting: a short word"; text = ($six[5] + ": ask the owner") },
    @{ found = $false; what = "a colon with no blank after it, which YAML does not read as a key"; text = ($six[4] + ":" + $made) },
    @{ found = $false; what = "KNOWN LIMIT: a YAML value on the line after its key"; text = ($six[0] + ":" + $nl + "  " + $made) },
    @{ found = $false; what = "a name in backticks before a colon, as a page that explains a setting writes it"; text = ("- ``" + $six[5] + "``: " + $made) },
    # --- an unquoted value with a parenthesis is code ---
    @{ found = $false; what = "code that calls for the value (password = get_password_from_vault())"; text = ($six[5] + " = get_" + $six[5] + "_from_vault()") },
    @{ found = $false; what = "code that passes a variable as an argument (login(password=user_password))"; text = ("login(" + $six[5] + "=user_" + $six[5] + ")") },
    @{ found = $false; what = "code that calls for the value with an argument"; text = ($ak + " = read_setting(name)") },
    @{ found = $false; what = "YAML whose value is a call"; text = ($six[5] + ": lookup(the-vault)") },
    @{ found = $true; what = "a QUOTED value with a parenthesis in it is still a value"; text = ($six[5] + ' = "Ab3d(Ef6h)Ij9k"') },
    @{ found = $true; what = "a member whose value has a parenthesis in it is still a value"; text = (Get-Member $six[0] "Ab3d(Ef6h)Ij9k") },
    @{ found = $true; what = "code first, then a literal secret: every match is looked at"; text = ("login(" + $six[5] + "=user_" + $six[5] + ")" + $nl + $six[4] + "=" + $made) },
    @{ found = $true; what = "KNOWN COST: code that names a password variable with nothing after it (self.password = password)"; text = ("self." + $six[5] + " = " + $six[5]) },
    # --- the review of PR 238 (2026-10-13): each line it measured firing, as written there ---
    @{ found = $false; what = "F: password: required"; text = ($six[5] + ": required") },
    @{ found = $false; what = "F: - api_key: optional"; text = ("- " + $six[4] + ": optional") },
    @{ found = $false; what = "F: password: process.env.DB_PASSWORD, with its comma"; text = ($six[5] + ": process.env.DB_PASS" + "WORD,") },
    @{ found = $false; what = "F: apiKey: config.apiKey"; text = ($ak + ": config." + $ak) },
    @{ found = $false; what = "F: api_key: SecretStr"; text = ($six[4] + ": SecretStr") },
    @{ found = $false; what = "F: password: Optional[str]"; text = ($six[5] + ": Optional[str]") },
    @{ found = $false; what = "F: clientSecret: SecretString; with its semicolon"; text = ($cs + ": SecretString;") },
    @{ found = $false; what = "F: password: see-the-vault"; text = ($six[5] + ": see-the-vault") },
    @{ found = $false; what = "F: login(password=user_password, timeout=5)"; text = ("login(" + $six[5] + "=user_" + $six[5] + ", timeout=5)") },
    @{ found = $false; what = "F: db.connect(host=h, password=db_password, port=5432)"; text = ("db.connect(host=h, " + $six[5] + "=db_" + $six[5] + ", port=5432)") },
    @{ found = $false; what = "F: password = config.db_password"; text = ($six[5] + " = config.db_" + $six[5]) },
    @{ found = $false; what = "F: password = os.environ['DB_PASSWORD'], quoted inside"; text = ($six[5] + " = os.environ['DB_PASS" + "WORD']") },
    # --- round 2 of that review (2026-10-14): six secrets ended by punctuation, each shared by the
    #     first reference rule though the rule before it refused them all. As written there, the
    #     made-up values assembled from pieces. ---
    @{ found = $true; what = "F2: a connection string's Password=...;"; text = ("Server=db1;Database=app;User Id=app;" + "Pass" + "word=MyS3" + "cretPass;") },
    @{ found = $true; what = "F2: export DB_PASSWORD=...;"; text = ("export DB_" + "PASS" + "WORD=Sup3r" + "S3cret;") },
    @{ found = $true; what = "F2: mysql --password=...,"; text = ("mysql --" + $six[5] + "=Sup3r" + "S3cret,") },
    @{ found = $true; what = "F2: password = ...,"; text = ($six[5] + " = Sup3r" + "S3cret,") },
    @{ found = $true; what = "F2: client_secret: ...; with an underscore in the value"; text = ($six[0] + ": Sup3r_" + "S3cret;") },
    @{ found = $true; what = "F2: password: ...,"; text = ($six[5] + ": Sup3r" + "S3cret,") },
    # --- and round them, from both sides ---
    @{ found = $false; what = "an identifier with a semicolon after it, as a statement ends"; text = ($ak + " = theKeyVariable;") },
    @{ found = $false; what = "an identifier with a closing parenthesis after it"; text = ("f(" + $six[4] + "=theKeyVariable)") },
    @{ found = $false; what = "an indexed lookup with a number"; text = ($six[5] + " = secrets[0]") },
    @{ found = $false; what = "a YAML value with a digit that is a call"; text = ($six[5] + ": lookup(vault2)") },
    @{ found = $false; what = "a YAML value with a digit that is a dotted lookup"; text = ($six[5] + ": settings.v2.password") },
    @{ found = $false; what = "KNOWN COST: a YAML value of letters only, bare, is taken for a word"; text = ($six[5] + ": lettersonlyvalue") },
    @{ found = $true; what = "a bare secret with a digit and a semicolon after it is a value (round 2 of the review of PR 238)"; text = ($six[4] + "=" + $made + ";") },
    @{ found = $false; what = "KNOWN COST: a bare secret of letters only with a semicolon after it reads as a statement's identifier"; text = ($six[4] + "=lettersonlyvalue;") },
    @{ found = $false; what = "KNOWN COST: and so with a comma, in a list"; text = ($six[5] + ": lettersonlyvalue,") },
    @{ found = $true; what = "KNOWN COST: an argument whose variable's name holds a digit is taken for a value (password=user_password2,)"; text = ("login(" + $six[5] + "=user_" + $six[5] + "2, timeout=5)") },
    @{ found = $true; what = "a bare letters-only value with nothing after it is still a value, as it was"; text = ($six[5] + " = lettersonlyvalue") },
    @{ found = $false; what = "KNOWN COST: a bare secret with a dot in it reads as a lookup"; text = ($six[4] + "=abc123.def456") },
    @{ found = $false; what = "KNOWN LIMIT: a value that ends in a parenthesis is code by the rule"; text = ($six[5] + "=Ab3dEf6hIj9k)") },
    @{ found = $false; what = "KNOWN COST: a bare value with an open parenthesis inside it is code by the rule"; text = ($six[5] + "=Ab3d(Ef6hIj9k") },
    @{ found = $true; what = "CONTROL: the same value quoted is a value again, parenthesis or not"; text = ($six[5] + "=""Ab3d(Ef6hIj9k""") },
    @{ found = $false; what = "KNOWN LIMIT: a YAML anchor before the value"; text = ($six[5] + ": &pw " + $made) },
    @{ found = $false; what = "KNOWN LIMIT: a PHP array arrow"; text = ("'" + $six[5] + "' => '" + $made + "'") },
    @{ found = $false; what = "KNOWN LIMIT: an XML element"; text = ("<" + $six[5] + ">" + $made + "</" + $six[5] + ">") },
    @{ found = $true; what = "a YAML value in quotes needs no digit"; text = ($six[4] + ": 'lettersonlyvalue'") },
    @{ found = $true; what = "a bare identifier-looking secret with nothing after it is still a value"; text = ($six[5] + " = hunter2xyz") },
    @{ found = $true; what = "a bare value with an ampersand after it, in an address, is no identifier"; text = ("https://example.org/cb?" + $six[3] + "=" + $made + "&state=1") },
    @{ found = $true; what = "a quoted value that looks like a lookup is still a value"; text = ($six[5] + ' = "config.db_password"') },
    # --- a markdown code span round a reference (round 3 of the review of PR 238, 2026-10-14) ---
    @{ found = $false; what = "F3: a lookup in a markdown code span (password = config.db_password)"; text = ('`' + $six[5] + " = config.db_" + $six[5] + '`') },
    @{ found = $false; what = "a YAML lookup with a digit in a code span (the digit keeps the YAML rule from hiding it)"; text = ('`' + $six[5] + ": settings.v2.db_" + $six[5] + '`') },
    @{ found = $false; what = "an identifier and its semicolon in a code span"; text = ('`' + $ak + " = theKeyVariable;" + '`') },
    @{ found = $false; what = "an indexed lookup in a code span, in a sentence"; text = ("set it with " + '`' + $six[5] + " = secrets[0]" + '`' + " and go on") },
    @{ found = $true; what = "a secret with a digit in a code span is still a secret"; text = ('`' + $six[5] + " = " + $made + '`') },
    @{ found = $true; what = "a secret with a digit and a semicolon in a code span"; text = ('`' + "export DB_" + "PASS" + "WORD=Sup3r" + "S3cret;" + '`') },
    @{ found = $true; what = "a letters-only value with only the backtick after it is still a value, as it is without one"; text = ('`' + $six[5] + " = lettersonlyvalue" + '`') },
    @{ found = $true; what = "two backticks after a lookup are not a code span's one"; text = ($six[5] + " = config.db_" + $six[5] + '``') },
    @{ found = $false; what = "F3: a code span with the sentence's full stop after it (os.environ['DB_PASSWORD'])"; text = ("set " + '`' + $six[5] + " = os.environ['DB_" + "PASS" + "WORD']" + '`' + ". Then go on") },
    @{ found = $false; what = "a code span with a comma after it (no parenthesis, which the older rule would skip on its own)"; text = ("as " + '`' + $six[5] + " = config.db_" + $six[5] + '`' + ", and more") },
    @{ found = $true; what = "a secret with a digit in a code span is still a secret with a full stop after it"; text = ("use " + '`' + $six[5] + " = " + $made + '`' + ". Then go on") },
    @{ found = $true; what = "a lookup with a word after its backtick is no code span's end"; text = ($six[5] + " = config.db_" + $six[5] + '`' + "x9") })
# FIVE GUARDS NO LINE ABOVE PINNED (the mutation net after PR 238 merged, 2026-10-14: secrets.psd1 69 of
# 74, each survivor a guard of this kind that could be removed with the suite still green). Each is
# pinned by a pair on its boundary: a quiet line the guard alone keeps quiet, and the same line just
# across it, which must be found. The mutant each pair turns red is named in its first line.
$attacks += @(
    # only-a-close-parenthesis-makes-code: every parenthesis line above holds a ')' after the equals
    # sign, so the open one was never looked at alone. A call whose arguments go on the next line has
    # only the '(' on its own.
    @{ found = $false; what = "a call whose arguments start on the next line: the OPEN parenthesis alone makes it code"; text = ($six[4] + " = load_key(" + $nl + '    "the-vault")') },
    @{ found = $true; what = "and the same identifier with no parenthesis after it is a value"; text = ($six[4] + " = load_key") },
    # named-secret-yaml-value-need-not-end-its-line: every YAML line above that is quiet is quiet for
    # another reason too (no digit, a placeholder, a short word). This value has a digit and its length.
    @{ found = $false; what = "a YAML value with a digit and more words after it on its line is prose, not a value"; text = ($six[5] + ": 12characters or more, with a digit") },
    @{ found = $true; what = "and the same value ending its line is a value"; text = ($six[5] + ": 12characters") },
    # named-secret-bare-yaml-value-of-any-length: 7 and 8 characters, both with digits, so only the
    # length decides (the 7-and-8 pairs above are a member and name=value, never bare YAML).
    @{ found = $false; what = "a bare YAML value of 7 characters with a digit"; text = ($six[5] + ": Ab3dEf6") },
    @{ found = $true; what = "a bare YAML value of exactly 8 characters with a digit"; text = ($six[5] + ": Ab3dEf6h") },
    # named-secret-quoted-yaml-value-of-any-length: the same boundary, in quotes.
    @{ found = $false; what = "a quoted YAML value of 7 characters"; text = ($six[5] + ": 'Ab3dEf6'") },
    @{ found = $true; what = "a quoted YAML value of exactly 8 characters"; text = ($six[5] + ": 'Ab3dEf6h'") },
    # named-secret-a-comparison-is-a-pair: the comparison line above ends in ')', so the parenthesis
    # rule kept it quiet with this guard gone. With nothing after the value, only this guard does.
    @{ found = $false; what = "a comparison with two equals signs and no parenthesis round it"; text = ("if " + $six[5] + "==" + $made + " then") },
    @{ found = $true; what = "and the pair it borders, one equals sign, is a value"; text = ("if " + $six[5] + "=" + $made + " then") })
foreach ($a in $attacks) { Check ((Test-Named $a.text) -eq $a.found) ($(if ($a.found) { "FOUND: " } else { "not found: " }) + $a.what) }
Check (@($attacks | Where-Object { $_.found }).Count -ge 35 -and @($attacks | Where-Object { -not $_.found }).Count -ge 50) ("the rule was attacked from both sides: " + @($attacks | Where-Object { $_.found }).Count + " texts that must be found and " + @($attacks | Where-Object { -not $_.found }).Count + " that must not")
# THE DEFAULT KINDS ARE UNCHANGED FOR EVERY CALLER: the folded and YAML forms above are found only
# when the named kind is asked for, never by a caller that names no kind or other kinds.
$newForms = @(($cs + "=" + $made), ($six[0] + ": " + $made), (("google_client_" + "secret") + ": " + $made), (Get-Member $cs $made))
$leaked = @($newForms | Where-Object { (Find-HordeSecretKind -Text $_) -cne "" -or (Find-HordeSecretKind -Text $_ -Kinds @("an access token", "a private key")) -cne "" -or (Protect-HordeSecretText -Text $_).count -ne 0 })
Check ($leaked.Count -eq 0) ("and none of the new forms is found by a caller that does not name the kind, nor hidden by the redact mode (" + $leaked.Count + " of " + $newForms.Count + " are)")
Complete-HordeSuite -Success "every secret shape is found and hidden whole, near misses stay, and decisions reads the one list"
