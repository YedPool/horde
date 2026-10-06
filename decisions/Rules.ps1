# decisions/Rules.ps1 - what the decisions records mean, and what may be written.
#
# THE ONE JOB of this file is to turn the records of the store into the current list of questions, and
# to say what a question must hold. Every function is pure: values in, values out. It opens no file,
# reads no clock, and knows nothing of who is calling or how a question is shown. decisions/Store.ps1
# reads the records; decisions/Definitions.ps1 reads the schemas and the kind table from disk and hands
# them in as -Definitions; decisions/Operations.ps1 is the only caller.
#
# ONE FUNCTION PER EVENT KIND DECIDES BOTH QUESTIONS. "May this be written?" and "what does this record
# do to the list?" are the same question asked at two moments, so each kind has one function that
# applies a record to the list or says why it cannot. Operations.ps1 runs it on the record it is about
# to write, against the list as it stands, and refuses the request if it says no; the fold runs it on
# every stored record. Two functions would be two statements of one rule, and would drift.
#
# ADDING AN EVENT KIND is one entry in $HordeDecisionEventKinds and its function below, plus its data
# definition in schema/decision-event.v1. Nothing else in this file changes.
#
# A QUESTION'S NUMBER IS DERIVED FROM THE ORDER, AND IS PERMANENT. The Nth question-added record is
# question N; there is no counter anywhere. Each question-added record also carries the number it was
# given, as a CHECK on that derivation, and here is why it must. A record can become unreadable after
# it was written (a damaged disk, a file deleted by hand), and the reader cannot tell what kind it
# was. Counting only the readable question-added records would then renumber every question added
# after it - the shifting numbers this module exists to end. So:
#   - reading: a question-added record's own number is believed when it is ABOVE every number already
#     given. The numbers it jumps over belonged to records that cannot be read; they have no question,
#     and they are never given again. A record claiming a number at or below one already given
#     contradicts the order and is reported as unreadable; it changes nothing.
#   - writing: the next number is one above the highest given, PLUS one for every unreadable record
#     since the last readable question-added. Any of those may have been a question, so its number is
#     left unused. The cost is a gap in the numbers, which is harmless; the alternative is a number
#     that means two questions.
# With every record readable both rules reduce to "the Nth question-added is question N", and
# test/test-decisions-rules.ps1 holds them to that.
#
# STORED RECORDS ARE FACTS, NOT REQUESTS. The fold checks a record's SHAPE (its schemas) and whether it
# applies, never the wording rules below: a title rule tightened next month must not make last month's
# question unreadable. The wording rules are for what is about to be written.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")

# THE EVENT KINDS. data: the definition of schema/decision-event.v1 its data must match. words: the
# member of its data, if any, that holds question fields (schema/decision-question.v1). apply: the
# function that applies it to the list, or returns why it cannot.
$script:HordeDecisionEventKinds = [ordered]@{
    "question-added"    = @{ data = "question-added";    words = "question"; apply = "Step-HordeDecisionAdded" }
    "question-updated"  = @{ data = "question-updated";  words = "changes";  apply = "Step-HordeDecisionUpdated" }
    "question-closed"   = @{ data = "question-closed";   words = "";         apply = "Step-HordeDecisionClosed" }
    "question-reopened" = @{ data = "question-reopened"; words = "";         apply = "Step-HordeDecisionReopened" }
}

# THE STATES a question can be in. A later slice adds to this list; nothing reads a state it does not
# find here except to show its name.
$script:HordeDecisionStates = @("open", "closed")

# THE FIELDS OF A QUESTION, in the order they are stored and shown. type: text, list (of texts) or
# flag. oneLine: a line break is refused. wording: a change to it is a new wording, because it is what
# a person reads before answering - an answer given to wording 2 must not be taken as given to
# wording 3. The same names are schema/decision-question.v1's properties; the rules suite compares them.
$script:HordeDecisionFields = [ordered]@{
    title          = @{ type = "text"; oneLine = $true;  wording = $true }
    kind           = @{ type = "text"; oneLine = $true;  wording = $false }
    options        = @{ type = "list"; oneLine = $true;  wording = $true }
    parts          = @{ type = "list"; oneLine = $false; wording = $true }
    whatItIs       = @{ type = "text"; oneLine = $false; wording = $true }
    yesMeans       = @{ type = "text"; oneLine = $false; wording = $true }
    recommendation = @{ type = "text"; oneLine = $false; wording = $false }
    group          = @{ type = "text"; oneLine = $true;  wording = $false }
    groupNote      = @{ type = "text"; oneLine = $false; wording = $false }
    askedBy        = @{ type = "text"; oneLine = $true;  wording = $false }
    waiting        = @{ type = "list"; oneLine = $true;  wording = $false }
    files          = @{ type = "list"; oneLine = $true;  wording = $false }
    references     = @{ type = "list"; oneLine = $true;  wording = $false }
    needsSecret    = @{ type = "flag"; oneLine = $true;  wording = $false }
}
# The fields a new question must fill. whatItIs and yesMeans are "one of the two", checked on its own.
$script:HordeDecisionRequiredFields = @("title", "kind", "group", "askedBy")

# LIMITS. A text longer than the first is refused whole, with the count, never cut: 500,000 characters
# is five times the 100,000-character text the decisions design (2026-10-06, section 6) requires to be stored whole, and keeps a record
# under the 2,097,152 characters Windows PowerShell 5.1's ConvertFrom-Json will read back.
$script:HordeDecisionMaxTextChars = 500000
$script:HordeDecisionMaxLineChars = 1000
$script:HordeDecisionMaxListItems = 100
# THE LARGEST NUMBER A QUESTION AND A RECORD CAN HAVE. core/Schema.ps1 has no "maximum", and "type":
# "integer" passes 99999999999 and 1e30, so these are held here, for a stored record and a request
# alike. Measured 2026-10-06, before they were: ONE record numbered 99999999999 made list, show and
# add throw "Cannot convert value to type System.Int32" - the whole list unloadable for one record -
# and one numbered 2147483647 made every later add throw. A question's number is nine digits, which
# is what the command line takes (decisions/Console.ps1) and is inside the Int32 the list keeps it
# in; a record's sequence number is ten, the length of its file name (decisions/Store.ps1).
$script:HordeDecisionMaxNumber = 999999999
$script:HordeDecisionMaxSequence = 9999999999
# A title must have this many words besides numbers and reference words. "Merge PR 1469?" has one.
$script:HordeDecisionMinTitleWords = 3

# WHAT LOOKS LIKE A SECRET. Names are what a finding says; the value is never repeated. Matched
# case-sensitively unless the pattern says (?i). A key header is matched by its fixed words, whatever
# kind of key it names.
$script:HordeDecisionSecretPatterns = [ordered]@{
    "a private key" = '-----BEGIN [A-Z0-9 ]*PRIVATE KEY'
    "an access token" = '(?<![A-Za-z0-9])(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{16,}|xox[abprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{20,}|A[KS]IA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,})'
    "a signed web token" = 'eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.'
    "a bearer token" = '(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{20,}'
    "a password or key written as name=value" = '(?i)\b(password|passwd|pwd|passphrase|secret|token|api[_-]?key|access[_-]?key)\s*=\s*\S'
    "a password written after a colon" = '(?i)\b(password|passwd|pwd|passphrase)\s*:\s*(?=\S*[0-9])(?=\S*[A-Za-z])\S{6,}'
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
$script:HordeDecisionSecretRunPattern = '[A-Za-z0-9+=_-]{32,}'
$script:HordeDecisionSecretRunBits = 4.0

function Get-HordeDecisionEventKinds { return @($script:HordeDecisionEventKinds.Keys) }
function Get-HordeDecisionStates { return @($script:HordeDecisionStates) }
function Get-HordeDecisionFieldNames { return @($script:HordeDecisionFields.Keys) }
function Get-HordeDecisionMaxNumber { return $script:HordeDecisionMaxNumber }

function Test-HordeDecisionCount {
    # Is a value a whole number from 1 to -Most? Compared as a Double and NEVER CAST FIRST: 1e30 is an
    # integer to the schema, and casting it to a 32- or 64-bit number is the throw this guards against.
    # Every limit here is far below 2^53, so the comparison is exact.
    param($Value, [Parameter(Mandatory = $true)][double]$Most)
    if (-not (Test-HordeSchemaType -Value $Value -Type "integer")) { return $false }
    $size = [double]$Value
    return ($size -ge 1 -and $size -le $Most)
}

function Test-HordeDecisionMember {
    # Does a parsed JSON object, or a table built here, have the member? Asked, never assumed: under
    # strict mode reading a property that is not there throws.
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return [bool]$Object.Contains($Name) }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

function Get-HordeDecisionMember {
    # The member's value, or $null when there is none. Returned with the unary comma so a list keeps
    # its shape - a list of one would otherwise arrive as its one item (core/Tristate.ps1, L-004).
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Name)) { return ,$Object[$Name] }; return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return ,$prop.Value
}

function ConvertTo-HordeDecisionCanonicalText {
    # One text for one value, whatever order its keys were given in, for hashing only: nothing parses
    # it. Keys are sorted by ordinal comparison; a whole number has one spelling whatever .NET type
    # holds it (Windows PowerShell 5.1's ConvertFrom-Json reads 1.0 as a Decimal). Anything that is
    # not JSON data is refused, never turned into its type name.
    # remote/Journal.ps1 has a fuller form of the same idea for the link's request ids. It is not
    # loaded here: the decisions rules would then depend on the link's code to hash a question.
    param($Value)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($null -eq $Value) { return "null" }
    if ($Value -is [bool]) { if ($Value) { return "true" } else { return "false" } }
    if ($Value -is [string]) { return ('"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"') }
    if (Test-HordeSchemaIsNumber $Value) {
        if (-not (Test-HordeSchemaType -Value $Value -Type "integer")) { throw ("the number " + $Value + " cannot be hashed: only whole numbers are decisions data") }
        return ([long]$Value).ToString($inv)
    }
    if ($Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject]) {
        $map = Get-HordeObjectByKey $Value
        $sorted = [string[]]@($map.Keys)
        [Array]::Sort($sorted, [System.StringComparer]::Ordinal)
        $pairs = foreach ($k in $sorted) { (ConvertTo-HordeDecisionCanonicalText -Value $k) + ":" + (ConvertTo-HordeDecisionCanonicalText -Value $map[$k]) }
        return ("{" + (@($pairs) -join ",") + "}")
    }
    if ($Value -is [System.Collections.IList]) {
        $items = foreach ($item in $Value) { ConvertTo-HordeDecisionCanonicalText -Value $item }
        return ("[" + (@($items) -join ",") + "]")
    }
    throw ("a value of type " + $Value.GetType().FullName + " cannot be hashed: only JSON data can")
}

function Get-HordeDecisionHash {
    # SHA-256, lowercase hex, of a value's canonical text in UTF-8.
    param($Value)
    $text = ConvertTo-HordeDecisionCanonicalText -Value $Value
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)) } finally { $sha.Dispose() }
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $digest) { [void]$sb.Append($b.ToString("x2")) }
    return $sb.ToString()
}

function Get-HordeDecisionTextBits {
    # Shannon entropy of a text, in bits a character.
    param([string]$Text)
    if ($Text.Length -eq 0) { return 0.0 }
    $counts = @{}
    foreach ($ch in $Text.ToCharArray()) { $key = [int]$ch; if ($counts.ContainsKey($key)) { $counts[$key]++ } else { $counts[$key] = 1 } }
    $bits = 0.0
    foreach ($n in $counts.Values) { $share = $n / $Text.Length; $bits -= $share * [Math]::Log($share, 2) }
    return $bits
}

function Find-HordeDecisionSecretKind {
    # What kind of secret a text looks like it holds, as words for a finding, or "" for none.
    param([string]$Text)
    foreach ($name in $script:HordeDecisionSecretPatterns.Keys) {
        if ([regex]::IsMatch($Text, $script:HordeDecisionSecretPatterns[$name])) { return $name }
    }
    foreach ($m in [regex]::Matches($Text, $script:HordeDecisionSecretRunPattern)) {
        $run = $m.Value
        if ($run -cmatch '[A-Z]' -and $run -cmatch '[a-z]' -and $run -cmatch '[0-9]' -and (Get-HordeDecisionTextBits -Text $run) -ge $script:HordeDecisionSecretRunBits) { return "a long random-looking string, as a key or token is" }
    }
    return ""
}

function Find-HordeDecisionSecrets {
    # A finding for every text anywhere in a value that looks like a secret. THE FINDING NAMES THE
    # FIELD AND THE KIND OF SECRET, AND NEVER THE VALUE: a refusal is printed, logged and may travel,
    # and repeating the secret in it would be the leak the check exists to stop. Every text is
    # looked at, in whatever member it sits, and so is every member's NAME, so a field or an event
    # kind added later is covered without being listed here.
    param($Value, [string]$Path = "the request")
    $out = New-Object System.Collections.ArrayList
    if ($Value -is [string]) {
        $kind = Find-HordeDecisionSecretKind -Text $Value
        if ($kind -ne "") { [void]$out.Add($Path + " holds what looks like " + $kind + ". A secret is never stored in the list: leave it out, and mark the question needsSecret if answering needs one") }
    }
    elseif ($Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject]) {
        $map = Get-HordeObjectByKey $Value
        foreach ($k in @($map.Keys)) {
            # A NAME IS TEXT TOO, and the schema's finding for a member it does not allow repeats the
            # name: a token pasted where a field's name goes came back in the refusal (measured
            # 2026-10-06). So a name is looked at like any text, and one that looks like a secret is
            # never used to say where anything is.
            $where = "'" + $k + "'"
            $nameKind = Find-HordeDecisionSecretKind -Text "$k"
            if ($nameKind -ne "") {
                $where = "a field whose name is not repeated here"
                [void]$out.Add("a field name in " + $Path + " holds what looks like " + $nameKind + ". A secret is never stored in the list: leave it out, and mark the question needsSecret if answering needs one")
            }
            foreach ($f in @(Find-HordeDecisionSecrets -Value $map[$k] -Path $where)) { [void]$out.Add($f) }
        }
    }
    elseif ($Value -is [System.Collections.IList]) {
        $i = 0
        foreach ($item in $Value) { $i++; foreach ($f in @(Find-HordeDecisionSecrets -Value $item -Path ($Path + " (item " + $i + ")"))) { [void]$out.Add($f) } }
    }
    return @($out)
}

function ConvertTo-HordeDecisionFields {
    # A question's fields from a value that has passed schema/decision-question.v1, as an ordered
    # table in the one field order, each value of its one .NET type. Without -Partial every field is
    # there, an absent one as its empty value ("", no items, false); with it, only the fields given,
    # which is what a change is. Texts are kept exactly: nothing is trimmed or re-encoded.
    param($Source, [switch]$Partial)
    $out = [ordered]@{}
    foreach ($name in $script:HordeDecisionFields.Keys) {
        $type = $script:HordeDecisionFields[$name].type
        $given = Test-HordeDecisionMember -Object $Source -Name $name
        if (-not $given -and $Partial) { continue }
        $raw = $null
        if ($given) { $raw = Get-HordeDecisionMember -Object $Source -Name $name }
        if ($type -eq "list") {
            $items = New-Object 'System.Collections.Generic.List[string]'
            if ($null -ne $raw) { foreach ($item in @($raw)) { $items.Add([string]$item) } }
            $out[$name] = $items.ToArray()
        }
        elseif ($type -eq "flag") { $out[$name] = ($raw -eq $true) }
        else { if ($null -eq $raw) { $out[$name] = "" } else { $out[$name] = [string]$raw } }
    }
    return $out
}

function Get-HordeDecisionTitleProblem {
    # Why a title does not explain itself, or "". The rule this builds in: a person reading only the
    # title, with no other context, must understand what is asked. A number or a pull-request or issue
    # reference names something the reader has to look up, so those, and the words that only introduce
    # them, do not count as saying anything.
    param([string]$Title)
    if ($Title -notmatch '\p{L}') { return "the title has no letters: write the question in plain words" }
    # A LINK IS A REFERENCE, whatever words its host and path are made of: before links were set
    # aside, a title that was only a pull request's address counted six words and was added (measured
    # 2026-10-06).
    $rest = [regex]::Replace($Title, '(?i)\b[a-z][a-z0-9+.-]*://\S+', ' ')
    # "Not followed by a letter", not \b: there is no word boundary between a letter and a digit, so
    # with \b "PR1469" kept its "PR" as a word, and "PR1469 PR1470 PR1471" was added as three (same
    # measurement). "press" and "bugfix" are still words: a letter follows.
    $rest = [regex]::Replace($rest, '(?i)\b(pull[\s-]*requests?|prs?|merge[\s-]*requests?|mrs?|issues?|tickets?|bugs?)(?!\p{L})', ' ')
    $rest = [regex]::Replace($rest, '#?[0-9]+', ' ')
    $words = [regex]::Matches($rest, '\p{L}[\p{L}\p{M}]*').Count
    if ($words -eq 0) { return "the title is only a pull-request or issue reference: write the question in plain words, and put the reference in 'references'" }
    if ($words -lt $script:HordeDecisionMinTitleWords) {
        return ("the title is too short to explain itself: besides numbers and references it has " + $words + " word(s), and it needs at least " + $script:HordeDecisionMinTitleWords + ". Write the question so that someone with no other context understands it")
    }
    return ""
}

function Test-HordeDecisionQuestion {
    # Findings for a whole question that is about to be written: -Question is every field
    # (ConvertTo-HordeDecisionFields, or a question of the list), -Kinds the question-kind table.
    # Empty means it may be written. Secrets are not looked for here: Find-HordeDecisionSecrets runs
    # over the whole request first, so that no later finding can repeat one.
    param($Question, $Kinds)
    $out = New-Object System.Collections.ArrayList
    foreach ($name in $script:HordeDecisionFields.Keys) {
        $spec = $script:HordeDecisionFields[$name]
        $value = Get-HordeDecisionMember -Object $Question -Name $name
        if ($spec.type -eq "flag") { continue }
        $texts = @($value)
        if ($spec.type -eq "list" -and $texts.Count -gt $script:HordeDecisionMaxListItems) { [void]$out.Add("'" + $name + "' has " + $texts.Count + " items; the most is " + $script:HordeDecisionMaxListItems) }
        $i = 0
        foreach ($text in $texts) {
            $i++
            $where = "'" + $name + "'"
            if ($spec.type -eq "list") {
                $where = $where + " (item " + $i + ")"
                if ("$text".Trim() -eq "") { [void]$out.Add($where + " is blank") }
            }
            $most = $script:HordeDecisionMaxTextChars
            if ($spec.oneLine) {
                $most = $script:HordeDecisionMaxLineChars
                if ("$text" -match "[\r\n]") { [void]$out.Add($where + " must be one line, and it has a line break") }
            }
            if ("$text".Length -gt $most) { [void]$out.Add($where + " is " + "$text".Length + " characters long; the most is " + $most + ". It is refused whole, never cut") }
        }
    }
    foreach ($name in $script:HordeDecisionRequiredFields) {
        if ("$(Get-HordeDecisionMember -Object $Question -Name $name)".Trim() -eq "") { [void]$out.Add("'" + $name + "' is missing or blank") }
    }
    $title = "$(Get-HordeDecisionMember -Object $Question -Name 'title')"
    if ($title.Trim() -ne "") { $why = Get-HordeDecisionTitleProblem -Title $title; if ($why -ne "") { [void]$out.Add($why) } }
    if ("$(Get-HordeDecisionMember -Object $Question -Name 'whatItIs')".Trim() -eq "" -and "$(Get-HordeDecisionMember -Object $Question -Name 'yesMeans')".Trim() -eq "") {
        [void]$out.Add("a question must explain itself: give 'whatItIs' (the background) or 'yesMeans' (what a yes would do), or both")
    }
    $kind = "$(Get-HordeDecisionMember -Object $Question -Name 'kind')"
    if ($kind.Trim() -ne "") {
        if (-not (Test-HordeDecisionMember -Object $Kinds -Name $kind)) {
            [void]$out.Add("'kind' is '" + $kind + "', which is not a kind of question; the kinds are: " + ((Get-HordeObjectByKey $Kinds).Keys -join ", "))
        } else {
            $needs = "$((Get-HordeDecisionMember -Object $Kinds -Name $kind).list)"
            foreach ($listName in @("options", "parts")) {
                # Assigned, then wrapped: the member comes back with the unary comma, so wrapping the
                # call itself would make a list of one holding the whole list (core/Tristate.ps1).
                $held = Get-HordeDecisionMember -Object $Question -Name $listName
                $items = @($held)
                if ($listName -eq $needs) {
                    if ($items.Count -lt 2) { [void]$out.Add("a question of kind " + $kind + " needs at least two " + $listName + ", and this has " + $items.Count) }
                    $distinct = @($items | Sort-Object -Unique)
                    if ($distinct.Count -ne $items.Count) { [void]$out.Add("'" + $listName + "' names one item twice") }
                }
                elseif ($items.Count -gt 0) { [void]$out.Add("'" + $listName + "' is given, but a question of kind " + $kind + " has none; it would be stored and never shown") }
            }
        }
    }
    return @($out)
}

function Test-HordeDecisionNote {
    # Findings for a text that goes with an act on a question - the outcome it is closed with, the
    # reason it is reopened for. -Name is how a finding names it. It must say something, and it is
    # held to the same lengths as a question's own texts.
    param([string]$Text, [Parameter(Mandatory = $true)][string]$Name, [switch]$OneLine)
    $out = New-Object System.Collections.ArrayList
    if ($Text.Trim() -eq "") { [void]$out.Add("'" + $Name + "' is blank: say it in plain words") }
    $most = $script:HordeDecisionMaxTextChars
    if ($OneLine) {
        $most = $script:HordeDecisionMaxLineChars
        if ($Text -match "[\r\n]") { [void]$out.Add("'" + $Name + "' must be one line, and it has a line break") }
    }
    if ($Text.Length -gt $most) { [void]$out.Add("'" + $Name + "' is " + $Text.Length + " characters long; the most is " + $most + ". It is refused whole, never cut") }
    return @($out)
}

function New-HordeDecisionState {
    # The list before any record: nothing asked. questions is keyed by number and kept in number order.
    return [pscustomobject]@{
        questions = (New-Object 'System.Collections.Generic.SortedDictionary[int,object]')
        lastNumber = 0
        pending = 0
        ids = (New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal))
        unreadable = (New-Object System.Collections.ArrayList)
        ignored = (New-Object System.Collections.ArrayList)
        lastSequence = [long]0
    }
}

function Get-HordeDecisionNextNumber {
    # The number a question added now would get: one above the highest given, plus one for every
    # unreadable record since the last readable question-added (see the header).
    param($State)
    return ([int]$State.lastNumber + [int]$State.pending + 1)
}

function Get-HordeDecisionNumberStatus {
    # What the list knows of one number: present (a question), unreadable (the number was given, or
    # may have been, to a record that cannot be read), or absent (never given).
    param($State, [int]$Number)
    if ($State.questions.ContainsKey($Number)) { return "present" }
    if ($Number -ge 1 -and $Number -le ([int]$State.lastNumber + [int]$State.pending)) { return "unreadable" }
    return "absent"
}

function Add-HordeDecisionHistory {
    param($Question, $Ev, [string]$Note)
    [void]$Question.history.Add([pscustomobject]@{ sequence = [long]$Ev.sequence; kind = "$($Ev.kind)"; at = "$($Ev.at)"; actor = "$($Ev.actor)"; note = $Note })
    $Question.updatedAt = "$($Ev.at)"
}

function Step-HordeDecisionAdded {
    param($State, $Ev)
    $number = [int]$Ev.data.number
    if ($number -le [int]$State.lastNumber) {
        # Counted as pending: it may be a real question whose number was damaged, and the next
        # question written must not take a number this one might have had.
        $State.pending = [int]$State.pending + 1
        return ("it says it is question " + $number + ", but numbers up to " + $State.lastNumber + " were already given by earlier records; a number is never given twice, so it is not shown")
    }
    # A number above the next one is believed: the numbers jumped over stay unused (see the header).
    $question = ConvertTo-HordeDecisionFields -Source $Ev.data.question
    $question["number"] = $number
    $question["state"] = "open"
    $question["wordingVersion"] = 1
    $question["outcome"] = ""
    $question["reopenReason"] = ""
    $question["addedAt"] = "$($Ev.at)"
    $question["updatedAt"] = "$($Ev.at)"
    $question["closedAt"] = ""
    $question["history"] = (New-Object System.Collections.ArrayList)
    Add-HordeDecisionHistory -Question $question -Ev $Ev -Note "added"
    $State.questions[$number] = $question
    $State.lastNumber = $number
    $State.pending = 0
    return ""
}

function Get-HordeDecisionTarget {
    # The question a record is about, as { question; why }: why says what is wrong when there is none.
    param($State, $Ev)
    $about = [int]$Ev.data.number
    if ($State.questions.ContainsKey($about)) { return [pscustomobject]@{ question = $State.questions[$about]; why = "" } }
    if ((Get-HordeDecisionNumberStatus -State $State -Number $about) -eq "unreadable") {
        return [pscustomobject]@{ question = $null; why = ("it is about question " + $about + ", whose own record cannot be read") }
    }
    return [pscustomobject]@{ question = $null; why = ("it is about question " + $about + ", and there is no question " + $about) }
}

function Step-HordeDecisionUpdated {
    param($State, $Ev)
    $target = Get-HordeDecisionTarget -State $State -Ev $Ev
    if ($null -eq $target.question) { return $target.why }
    $question = $target.question
    if ($question.state -cne "open") { return ("question " + $question.number + " is " + $question.state + ", and only an open question can be changed; reopen it first") }
    $changes = ConvertTo-HordeDecisionFields -Source $Ev.data.changes -Partial
    $changed = New-Object System.Collections.ArrayList
    $reworded = $false
    foreach ($name in @($changes.Keys)) {
        if ((ConvertTo-HordeDecisionCanonicalText -Value $question[$name]) -ceq (ConvertTo-HordeDecisionCanonicalText -Value $changes[$name])) { continue }
        $question[$name] = $changes[$name]
        [void]$changed.Add($name)
        if ($script:HordeDecisionFields[$name].wording) { $reworded = $true }
    }
    if ($changed.Count -eq 0) { return ("it changes nothing: every field it names already has that value in question " + $question.number) }
    $note = "changed " + ($changed -join ", ")
    if ($reworded) { $question.wordingVersion = [int]$question.wordingVersion + 1; $note = $note + " (now wording " + $question.wordingVersion + ")" }
    Add-HordeDecisionHistory -Question $question -Ev $Ev -Note $note
    return ""
}

function Step-HordeDecisionClosed {
    param($State, $Ev)
    $target = Get-HordeDecisionTarget -State $State -Ev $Ev
    if ($null -eq $target.question) { return $target.why }
    $question = $target.question
    if ($question.state -cne "open") { return ("question " + $question.number + " is already " + $question.state) }
    $question.state = "closed"
    $question.outcome = "$($Ev.data.outcome)"
    $question.closedAt = "$($Ev.at)"
    Add-HordeDecisionHistory -Question $question -Ev $Ev -Note "closed"
    return ""
}

function Step-HordeDecisionReopened {
    param($State, $Ev)
    $target = Get-HordeDecisionTarget -State $State -Ev $Ev
    if ($null -eq $target.question) { return $target.why }
    $question = $target.question
    if ($question.state -cne "closed") { return ("question " + $question.number + " is " + $question.state + ", and only a closed question can be reopened") }
    # The number, the wording version and the history stay: a reopened question is the same question.
    # The outcome it was closed with is in the history's record, not carried on an open question.
    $question.state = "open"
    $question.outcome = ""
    $question.closedAt = ""
    $question.reopenReason = "$($Ev.data.reason)"
    Add-HordeDecisionHistory -Question $question -Ev $Ev -Note "reopened"
    return ""
}

function Test-HordeDecisionEvent {
    # Findings for a parsed record's SHAPE: the envelope, its kind, and its kind's data, each against
    # its schema. Empty means the record can be applied. One function, used for a stored record and for
    # a record about to be written, so nothing is ever written that the reader would call unreadable.
    param($Ev, $Definitions)
    $found = @(Test-HordeSchema -Value $Ev -Schema $Definitions.eventSchema)
    if ($found.Count -gt 0) { return @("it is not a decision-event.v1 record: " + (@($found | Select-Object -First 3) -join "; ")) }
    if (-not (Test-HordeDecisionCount -Value $Ev.sequence -Most $script:HordeDecisionMaxSequence)) { return @("its sequence number is beyond " + $script:HordeDecisionMaxSequence + ", the largest a record can have") }
    $entry = $script:HordeDecisionEventKinds["$($Ev.kind)"]
    if ($null -eq $entry) { return @("its kind '" + $Ev.kind + "' is not one this version of Horde knows; a newer version may have written it") }
    $dataSchema = Get-HordeDecisionMember -Object $Definitions.eventSchema.definitions -Name $entry.data
    $found = @(Test-HordeSchema -Value $Ev.data -Schema $dataSchema -Path '$.data' -Root $Definitions.eventSchema)
    if ($found.Count -eq 0 -and $entry.words -ne "") {
        $found = @(Test-HordeSchema -Value (Get-HordeDecisionMember -Object $Ev.data -Name $entry.words) -Schema $Definitions.questionSchema -Path ('$.data.' + $entry.words))
    }
    if ($found.Count -gt 0) { return @("its data is not what a " + $Ev.kind + " record holds: " + (@($found | Select-Object -First 3) -join "; ")) }
    if (-not (Test-HordeDecisionCount -Value $Ev.data.number -Most $script:HordeDecisionMaxNumber)) { return @("its question number is beyond " + $script:HordeDecisionMaxNumber + ", the largest a question can have") }
    return @()
}

function Add-HordeDecisionRecordToState {
    # Apply one record of the store (decisions/Store.ps1: { sequence; file; kind; data; reason }) to the
    # list. Returns "" when it applied, or why it did not; either way the list says so itself, in
    # .unreadable or .ignored, so a caller that only shows the list still shows the problem.
    param($State, $Record, $Definitions)
    $State.lastSequence = [long]$Record.sequence
    $why = ""
    if ($Record.kind -cne "ok") { $why = "$($Record.reason)" }
    else {
        $shape = @(Test-HordeDecisionEvent -Ev $Record.data -Definitions $Definitions)
        if ($shape.Count -gt 0) { $why = $shape[0] }
        elseif ([long]$Record.data.sequence -ne [long]$Record.sequence) { $why = "it says it is record " + $Record.data.sequence + ", which is not its place in the store" }
    }
    if ($why -ne "") {
        # A long reason is cut, and says so: a damaged record can produce findings of any length.
        if ($why.Length -gt 400) { $why = $why.Substring(0, 400) + " (reason cut at 400 characters)" }
        [void]$State.unreadable.Add([pscustomobject]@{ sequence = [long]$Record.sequence; file = "$($Record.file)"; reason = $why })
        $State.pending = 1 + [int]$State.pending
        return $why
    }
    $Ev = $Record.data
    $entry = $script:HordeDecisionEventKinds["$($Ev.kind)"]
    $applied = & $entry.apply $State $Ev
    if ("$applied" -ne "") { [void]$State.ignored.Add([pscustomobject]@{ sequence = [long]$Record.sequence; file = "$($Record.file)"; reason = "$applied" }) }
    # The first record of an id is the one a repost is answered from.
    if (-not $State.ids.ContainsKey("$($Ev.id)")) {
        $State.ids["$($Ev.id)"] = [pscustomobject]@{ sequence = [long]$Record.sequence; kind = "$($Ev.kind)"; requestHash = "$($Ev.requestHash)"; number = [int]$Ev.data.number; applied = ("$applied" -eq "") }
    }
    return "$applied"
}

function ConvertTo-HordeDecisionState {
    # THE FOLD: the store's records, in order, become the current list. Nothing is cached and nothing
    # else is consulted, so the records are the single source of truth.
    param($Records, $Definitions)
    $state = New-HordeDecisionState
    foreach ($record in @($Records)) { $null = Add-HordeDecisionRecordToState -State $state -Record $record -Definitions $Definitions }
    return $state
}

function ConvertTo-HordeDecisionView {
    # One question of the list as plain data, schema/decision-result.v1's view: a copy, so nothing a
    # caller does to it reaches the list.
    param($Question)
    $view = [ordered]@{ number = [int]$Question.number; state = "$($Question.state)"; wordingVersion = [int]$Question.wordingVersion }
    foreach ($name in $script:HordeDecisionFields.Keys) {
        $type = $script:HordeDecisionFields[$name].type
        if ($type -eq "list") { $view[$name] = [string[]]@($Question[$name]) }
        elseif ($type -eq "flag") { $view[$name] = [bool]$Question[$name] }
        else { $view[$name] = "$($Question[$name])" }
    }
    foreach ($name in @("outcome", "reopenReason", "addedAt", "updatedAt", "closedAt")) { $view[$name] = "$($Question[$name])" }
    $view["history"] = @($Question.history | ForEach-Object { [pscustomobject]@{ sequence = $_.sequence; kind = $_.kind; at = $_.at; actor = $_.actor; note = $_.note } })
    return [pscustomobject]$view
}
