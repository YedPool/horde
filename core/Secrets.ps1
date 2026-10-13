# core/Secrets.ps1 - the one statement, for all of Horde, of what text looks like a credential.
#
# TWO MODES, ONE LIST. Lifted from decisions/Rules.ps1 (relay design 2026-10-09, PR plan item 9), where
# it refused a question holding a secret. The conversation port (conversations/Port.ps1) needs the same
# judgement for the opposite purpose: a Thrall's turn is not refused - the founder must see it - but
# every secret in it is replaced by a marker before it leaves the machine. Two lists would drift, and a
# shape refused on the decisions page but shown in a chat is exactly the leak the check exists to stop.
# So:
#   Find-HordeSecretKind     - what kind of secret a text holds, as words, or "" (REFUSE mode; decisions
#                              calls it through its own Find-HordeDecisionSecretKind, unchanged)
#   Protect-HordeSecretText  - the text with every secret hidden, and how many (REDACT mode)
#
# REDACTING IS MORE THAN MATCHING. Several patterns below match only the START of a secret, which is
# enough to refuse and not enough to hide: the name=value pattern stops at the value's first character,
# the key header stops at the header, and the signed web token stops before its signature. So a match
# is widened before it is replaced: a key header to its END line (or to the end of the text, when there
# is none), and every other match over the rest of its word - every character up to the next white
# space. Hiding a little too much costs a word of the founder's reading; hiding too little cannot be
# taken back once it is on a phone. test/test-secrets.ps1 plants every kind and requires every 8
# characters of each one's secret part to be gone.
#
# Not to be confused with core/EngineConfig.ps1's Protect-HordeText, a narrower list kept for the
# engine configuration's own findings. Folding that one in here would change what an engine file
# refuses; it is left for its own pull request.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It loads nothing.

# WHAT LOOKS LIKE A SECRET. Names are what a finding says; the value is never repeated. Matched
# case-sensitively unless the pattern says (?i). A key header is matched by its fixed words, whatever
# kind of key it names.
# THIS IS BEST EFFORT, AND SAYS SO. It refuses the shapes a secret is usually written in; it cannot
# know a secret that looks like a word. Measured 2026-10-06, the first set of patterns let all of these
# be ADDED to a store: a cloud secret key with slashes in it, an address with user:password@ in it, a
# chat webhook address, an Authorization header, and "the password is ..." in a sentence. Each now
# has its pattern. WHAT IS STILL LET THROUGH, on purpose, because refusing it would refuse ordinary
# text: a password of plain words with no quotes round it ("password: ask the owner" must pass); a
# long string in one case only (a commit id, a UUID and a hash are those); a mixed string shorter
# than 32 characters. The list is never the place for a secret: the needsSecret flag is.
$script:HordeSecretKinds = [ordered]@{
    "a private key" = '-----BEGIN [A-Z0-9 ]*PRIVATE KEY'
    "an access token" = '(?<![A-Za-z0-9])(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{16,}|xox[abprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{20,}|A[KS]IA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,})'
    "a signed web token" = 'eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.'
    "a bearer token" = '(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{20,}'
    "a password or key written as name=value" = '(?i)\b(password|passwd|pwd|passphrase|secret|token|api[_-]?key|access[_-]?key)\s*=\s*\S'
    # After the colon, or after "is" or "was": anything in quotes, or a word of six or more characters
    # with a digit in it. "password: ask the owner" and "a password is needed" have neither.
    "a password written after a colon" = '(?i)\b(password|passwd|pwd|passphrase)\s*:\s*(?:["''][^"''\s][^"'']*["'']|(?=\S*[0-9])\S{6,})'
    "a password written in a sentence" = '(?i)\b(password|passwd|pwd|passphrase)\s+(is|was)\s+(?:["''][^"''\s][^"'']*["'']|(?=\S*[0-9])\S{6,})'
    # scheme://user:password@host. A colon in a link's path, or an @ outside the link, is not this.
    "a password inside an address" = '(?i)\b[a-z][a-z0-9+.-]*://[^\s/:@]+:[^\s/@]+@'
    # An address that is itself the credential: whoever holds it can post.
    "a webhook address" = '(?i)\b(hooks\.slack\.com/services/|discord(app)?\.com/api/webhooks/)[A-Za-z0-9/_-]{8,}'
    # The header by its name and scheme, or the scheme word before a value with both cases and a
    # digit in it: "the basic understanding" and "the bearer of the news" are not values.
    "an authorization value" = '(?i:\bauthorization\s*:\s*(basic|bearer|digest|token|apikey)\s+\S{4,})|(?i:\b(basic|bearer))\s+(?=[A-Za-z0-9._~+/-]*[0-9])(?=[A-Za-z0-9._~+/-]*[a-z])(?=[A-Za-z0-9._~+/-]*[A-Z])[A-Za-z0-9._~+/-]{12,}'
}
# A LONG RANDOM-LOOKING STRING: 32 or more characters of the letters, digits and + = _ - that keys are
# written in, holding an upper-case letter, a lower-case letter and a digit, with at least 4 bits of
# entropy a character. Left out on purpose, because they are ordinary content: a path (it is cut at
# every slash, backslash and dot), a commit id or other hex (one case only), a UUID (one case only).
# THE THRESHOLD FAVOURS REFUSING. Measured 2026-10-06: of 300 random 32-character keys of letters and
# digits the lowest had 4.16 bits a character (of 40-character ones, 4.45), while a 44-character
# identifier made of English words with a digit in it had 4.21 to 4.34. No threshold separates the
# two, so 4.0 is under every key measured, and a long mixed-case identifier with a digit is sometimes
# refused too. That costs a reworded sentence; a key stored in the list cannot be taken back.
$script:HordeSecretRunPattern = '[A-Za-z0-9+=_-]{32,}'
$script:HordeSecretRunBits = 4.0
# THE SAME, FOR A KEY WITH SLASHES IN IT. Cutting at every slash keeps paths out, and let the most
# common cloud secret in: 40 characters of base64, slashes among them. So a second look: 40 or more
# characters of letters, digits, + and /, standing alone (no dot, dash or underscore beside them, so
# a piece of a longer path is not a candidate), holding a slash, both cases and a digit. The bar is
# higher than above because a path is made of words. Measured 2026-10-06: of 300 random 40-character
# base64 strings the lowest had 4.40 bits a character and the documented example key has 4.66; of
# five mixed-case paths with a digit in them the highest had 4.32. 4.35 sits between, narrowly: a
# mixed-case path of unusual variety may be refused, and a key of unusual sameness may pass.
$script:HordeSecretSlashRunPattern = '(?<![A-Za-z0-9+/=_.-])[A-Za-z0-9+/]{40,}(?![A-Za-z0-9+/_.-])'
$script:HordeSecretSlashRunBits = 4.35
$script:HordeSecretRunKind = "a long random-looking string, as a key or token is"
# A SECRET UNDER ITS OWN NAME, LOOKED FOR ONLY WHEN A CALLER NAMES THIS KIND (review of the files deny
# list, 2026-10-13). It is not in the list above, so no caller that names no kind looks for it, and
# the redact mode does not know it: test/test-secrets.ps1 pins both. Why it exists: measured that
# day, a client file as an identity provider issues it ({"client_secret":"..."}) fired no kind a
# share asks for, and client_secret=VALUE fired none at all, because the word boundary of the
# name=value kind above does not break at an underscore. That kind is left as it is: other callers
# rely on it.
#   THE NAME is one of six, in any case of A to Z, and is the WHOLE name: a letter, a digit or an
#   underscore on either side makes it another name (my_api_key_name, DB_PASSWORD are not found).
#   TWO SPELLINGS. As a member: the name in quotes of either kind, a colon with any white space
#   round it, line breaks too, and the value in quotes. As name=value: an equals sign with blanks or
#   tabs round it and never a line break - an empty value must not take the next line's first word
#   for its own - and the value bare or in quotes. A name with no quotes before a colon is NOT
#   looked for: "password: required" is what a page that explains a setting says.
#   THE VALUE is 8 or more characters with no white space in it. A number, null, true or an object
#   is no value here: a schema that describes the member is not the secret.
#   A PLACEHOLDER IS NOT A VALUE: one holding an angle bracket, a dollar sign, an open brace or
#   three dots, or one of the words your, xxx, example, changeme, redacted in any case, anywhere in
#   it. So a shell line that reads the value from a variable is not found, and neither is a real
#   secret that happens to hold one of those: the cost of not refusing every page of documentation.
$script:HordeSecretNamedKind = "a secret written under a name such as client_secret or password"
$script:HordeSecretNamedNames = 'client_secret|private_key|refresh_token|access_token|api_key|password'
$script:HordeSecretNamedPattern = '(?<q>["''])(?<name>(?i:' + $script:HordeSecretNamedNames + '))\k<q>\s*:\s*(?<v>["''])(?<value>(?:\\.|(?!\k<v>)[^\\\s]){8,})\k<v>|(?<![A-Za-z0-9_])(?<name>(?i:' + $script:HordeSecretNamedNames + '))[ \t]*=[ \t]*(?:(?<w>["''])(?<value>(?:(?!\k<w>)\S){8,})\k<w>|(?<value>[^\s"''=]\S{7,}))'
$script:HordeSecretNamedPlaceholder = '[<>${]|\.\.\.|(?i:your|xxx|example|changeme|redacted)'
# THE MARKER a hidden secret leaves. Its own characters match no pattern above (test/test-secrets.ps1
# redacts a redacted text and requires no change), so redacting twice is redacting once.
$script:HordeSecretMark = "<redacted>"
# A KEY HEADER IS WIDENED TO ITS END LINE, or to the end of the text when the end line is not in it: a
# key's body is many lines of base64 with no fixed shape of its own to match.
$script:HordeSecretBlockEnd = '-----END [A-Z0-9 ]*PRIVATE KEY-----'

function Get-HordeSecretMark { return $script:HordeSecretMark }

function Get-HordeTextBits {
    # Shannon entropy of a text, in bits a character.
    param([string]$Text)
    if ($Text.Length -eq 0) { return 0.0 }
    $counts = @{}
    foreach ($ch in $Text.ToCharArray()) { $key = [int]$ch; if ($counts.ContainsKey($key)) { $counts[$key]++ } else { $counts[$key] = 1 } }
    $bits = 0.0
    foreach ($n in $counts.Values) { $share = $n / $Text.Length; $bits -= $share * [Math]::Log($share, 2) }
    return $bits
}

function Test-HordeSecretRun {
    # Is this match of the long-run pattern random-looking enough to be a key?
    param([string]$Run)
    return ($Run -cmatch '[A-Z]' -and $Run -cmatch '[a-z]' -and $Run -cmatch '[0-9]' -and (Get-HordeTextBits -Text $Run) -ge $script:HordeSecretRunBits)
}

function Test-HordeSecretSlashRun {
    # Is this match of the slash-run pattern random-looking enough to be a key?
    param([string]$Piece)
    return ($Piece.Contains("/") -and $Piece -cmatch '[A-Z]' -and $Piece -cmatch '[a-z]' -and $Piece -cmatch '[0-9]' -and (Get-HordeTextBits -Text $Piece) -ge $script:HordeSecretSlashRunBits)
}

function Test-HordeSecretNamed {
    # Does this text hold a secret under one of the six names (the header of that kind has the
    # rule)? Every match is looked at until one has a value that is no placeholder. The fold is
    # the invariant one, so a machine's language does not change which names are found.
    param([string]$Text)
    $invariant = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    foreach ($m in [regex]::Matches($Text, $script:HordeSecretNamedPattern, $invariant)) {
        if (-not [regex]::IsMatch($m.Groups["value"].Value, $script:HordeSecretNamedPlaceholder, $invariant)) { return $true }
    }
    return $false
}

function Find-HordeSecretKind {
    # What kind of secret a text looks like it holds, as words for a finding, or "" for none.
    # -Kinds NAMES WHICH KINDS ARE LOOKED FOR, by the words this function answers with; left out,
    # or empty, every kind is, as for every caller before it was added (review of the files deny
    # list, 2026-10-13). A caller that judges whole FILES asks only for the kinds that know a
    # credential by its shape: the two long-run looks below fire on ordinary reports. A name that
    # is no kind THROWS: misspelt, it would look for nothing and answer "no secret".
    # ONE KIND IS LOOKED FOR ONLY WHEN IT IS NAMED, and so never by "every kind": a secret under
    # its own name ($script:HordeSecretNamedKind says why).
    param([string]$Text, [string[]]$Kinds = @())
    $asked = @($Kinds)
    foreach ($kindName in $asked) {
        if (@($script:HordeSecretKinds.Keys) -cnotcontains $kindName -and $kindName -cne $script:HordeSecretRunKind -and $kindName -cne $script:HordeSecretNamedKind) { throw ("'" + $kindName + "' is not a kind of secret core/Secrets.ps1 looks for") }
    }
    foreach ($name in $script:HordeSecretKinds.Keys) {
        if ($asked.Count -gt 0 -and $asked -cnotcontains $name) { continue }
        if ([regex]::IsMatch($Text, $script:HordeSecretKinds[$name])) { return $name }
    }
    if ($asked -ccontains $script:HordeSecretNamedKind -and (Test-HordeSecretNamed -Text $Text)) { return $script:HordeSecretNamedKind }
    if ($asked.Count -gt 0 -and $asked -cnotcontains $script:HordeSecretRunKind) { return "" }
    foreach ($m in [regex]::Matches($Text, $script:HordeSecretRunPattern)) {
        if (Test-HordeSecretRun -Run $m.Value) { return $script:HordeSecretRunKind }
    }
    foreach ($m in [regex]::Matches($Text, $script:HordeSecretSlashRunPattern)) {
        if (Test-HordeSecretSlashRun -Piece $m.Value) { return $script:HordeSecretRunKind }
    }
    return ""
}

function Get-HordeSecretSpans {
    # Every stretch of a text to hide, as { start; end } (end exclusive), widened (header) and merged
    # where they touch or overlap, in order.
    param([string]$Text)
    $raw = New-Object System.Collections.ArrayList
    foreach ($name in $script:HordeSecretKinds.Keys) {
        foreach ($m in [regex]::Matches($Text, $script:HordeSecretKinds[$name])) {
            $end = $m.Index + $m.Length
            if ($name -ceq "a private key") {
                $close = [regex]::Match($Text.Substring($end), $script:HordeSecretBlockEnd)
                if ($close.Success) { $end = $end + $close.Index + $close.Length } else { $end = $Text.Length }
            } else {
                while ($end -lt $Text.Length -and -not [char]::IsWhiteSpace($Text[$end])) { $end++ }
            }
            [void]$raw.Add([pscustomobject]@{ start = $m.Index; end = $end })
        }
    }
    foreach ($m in [regex]::Matches($Text, $script:HordeSecretRunPattern)) {
        if (Test-HordeSecretRun -Run $m.Value) { [void]$raw.Add([pscustomobject]@{ start = $m.Index; end = $m.Index + $m.Length }) }
    }
    foreach ($m in [regex]::Matches($Text, $script:HordeSecretSlashRunPattern)) {
        if (Test-HordeSecretSlashRun -Piece $m.Value) { [void]$raw.Add([pscustomobject]@{ start = $m.Index; end = $m.Index + $m.Length }) }
    }
    # Most texts hold no secret: the sort's pipeline is not started for nothing (it was a third of the
    # cost of redacting an ordinary turn, 2026-10-10).
    if ($raw.Count -eq 0) { return @() }
    $merged = New-Object System.Collections.ArrayList
    foreach ($s in @($raw | Sort-Object start, end)) {
        if ($merged.Count -gt 0 -and $s.start -le $merged[$merged.Count - 1].end) {
            if ($s.end -gt $merged[$merged.Count - 1].end) { $merged[$merged.Count - 1].end = $s.end }
        } else { [void]$merged.Add([pscustomobject]@{ start = $s.start; end = $s.end }) }
    }
    return @($merged)
}

function Protect-HordeSecretText {
    # The text with every secret in it replaced by the marker, as { text; count }: count is how many
    # stretches were hidden. Nothing else of the text changes.
    param([AllowEmptyString()][string]$Text)
    if ($Text.Length -eq 0) { return [pscustomobject]@{ text = ""; count = 0 } }
    $spans = @(Get-HordeSecretSpans -Text $Text)
    if ($spans.Count -eq 0) { return [pscustomobject]@{ text = $Text; count = 0 } }
    $sb = New-Object System.Text.StringBuilder
    $at = 0
    foreach ($s in $spans) {
        [void]$sb.Append($Text, $at, $s.start - $at)
        [void]$sb.Append($script:HordeSecretMark)
        $at = $s.end
    }
    [void]$sb.Append($Text, $at, $Text.Length - $at)
    return [pscustomobject]@{ text = $sb.ToString(); count = $spans.Count }
}
