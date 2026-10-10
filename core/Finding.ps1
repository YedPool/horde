# core/Finding - is a text one generalisable finding that may be kept? schema/finding.v1, and the rules
# that schema cannot say.
#
# THE ONE JOB of this file is to answer, for a finding's text, "read" with the finding or "refused" with
# every reason. Every function is PURE: text in, answer out. It opens no file but Horde's own schema,
# reads no clock and no environment. core/FindingStore.ps1 is the only writer, and it writes only what
# this file has read. NOTHING HERE OR THERE SENDS A FINDING ANYWHERE: no network, no transport, no
# remote call. Carrying findings off the machine is a later piece, over the remote link, and will read
# the files this pair writes.
#
# WHY A FINDING IS ITS OWN RECORD. A fleet analyst sorts what it measures into fleet-specific and
# generalisable findings, and the generalisable ones are meant to leave the machine one day. What may
# leave must be checked where it is written, not where it is sent: a finding that holds a credential,
# a person's address or a piece of conversation is refused here, before it is a file.
#
# THE ANSWER: { state; finding; findings }, as the module-settings reader answers (core/ModuleSettings.ps1):
#   state     "read" or "refused";
#   finding   the parsed finding when read, $null when refused - never a part of it;
#   findings  every reason it was refused, each naming WHERE (a field's path), never repeating the value.
#
# THE CHECKS, IN THIS ORDER, and why the order:
#   1. size: more than $script:HordeFindingMaxLength characters is refused before anything walks it;
#   2. ASCII: a finding is stored as ASCII (CONTRIBUTING 13); any other character is written as a \u
#      escape, so text in any language can still be kept;
#   3. JSON the parser can read. Its own message is not passed on: it quotes the text;
#   4. CONTENT, over every text AND every member name of the parsed value: what is not text, a
#      credential, customer data, conversation. These run BEFORE the duplicate-key scan and the schema,
#      because both of those repeat what they found - a key's name, a value outside a closed list - and
#      a refusal that repeats a secret is the leak it exists to stop. When content is refused, nothing
#      else is looked at;
#   5. a key repeated in one object (core/JsonText.ps1): the parser keeps one of the two and says nothing;
#   6. schema/finding.v1: the shape, the closed confidence list and every text's bound;
#   7. what the schema cannot say: how many items each list holds, and a window that ends before it starts.
#
# REUSED, NOT WRITTEN AGAIN. The credential check is core/Secrets.ps1's Find-HordeSecretKind (moved there
# from decisions/Rules.ps1, relay design 2026-10-09, PR plan item 9), and the check for what is not text
# is decisions/Rules.ps1's Get-HordeDecisionCharProblem: one statement of each rule in the repository.
# Their headers say what they catch and what they let through on purpose; that holds here unchanged.
# Loading decisions/Rules.ps1 from core is the cost of reusing the second; moving it into core is a
# change of its own.
#
# CUSTOMER DATA. Nothing in the repository looked for it before this file, so this is a MINIMAL check,
# and says so: an e-mail address, a phone number written with a leading + and 8 to 15 digits, a
# ten-digit number grouped 3-3-4, and a path into a person's home folder. IT CANNOT SEE a person's or a
# company's name, a postal address, a device serial or an account number, or a phone number written as
# one bare run of digits (a count or a timestamp looks the same).
#
# CONVERSATION. Refused when a text has any of:
#   - a line that opens with a speaker's label from a closed list ("User:", "Assistant:", "Human:",
#     "AI:", "You:", "Me:", "Bot:", "Customer:", "Caller:", "Q:", "A:"), after any quote marks (">")
#     or a bracketed time stamp;
#   - two or more of those labels anywhere in it, as a chat pasted onto one line has;
#   - two or more lines that each open with a name of up to four words and a colon - dialogue with
#     any speaker's name;
#   - two or more lines that open with ">", as a quoted reply has;
#   - a transcript record's role field ("role": "user").
# IT CANNOT SEE paraphrase ("the person asked whether..."), a single quoted sentence, one dialogue line
# under a name not on the list, labels in another language, or a conversation pasted with no labels.
# And it refuses, on purpose, ordinary text shaped like dialogue: two lines "Note: ..." and "Limit: ..."
# in one field. That costs a reworded field; conversation kept in a finding cannot be taken back.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Schema.ps1")
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "Secrets.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "decisions\Rules.ps1")

$script:HordeFindingSchemaName = "finding.v1"
# The largest finding text read. Every field at its bound with 24 numbers of 16 values comes to about
# 9000 characters of indented JSON; this leaves room for indentation and escapes and no more.
$script:HordeFindingMaxLength = 16384
# How many items each list may hold. The subset of draft-07 that core/Schema.ps1 implements has no
# minItems or maxItems, so they are here, and the schema's descriptions repeat them for a reader.
$script:HordeFindingListBounds = [ordered]@{
    "metric.numbers"                  = @{ min = 1; max = 24 }
    "metric.countedFrom.recordKinds"  = @{ min = 1; max = 10 }
    "metric.countedFrom.versions"     = @{ min = 1; max = 10 }
}
$script:HordeFindingValuesBounds = @{ min = 1; max = 16 }

# What customer data looks like. Names are what a finding says; the value is never repeated.
$script:HordeFindingCustomerPatterns = [ordered]@{
    "an e-mail address" = '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'
    "a phone number" = '(?<![A-Za-z0-9+])\+[0-9](?:[ .()-]{0,2}[0-9]){7,14}(?![0-9])|(?<![0-9])\(?[0-9]{3}\)?[ .-][0-9]{3}[ .-][0-9]{4}(?![0-9])'
    "a path into a person's home folder" = '(?i)(?:\b[a-z]:[\\/]+(?:users|documents and settings)[\\/]+[^\\/\s]+|(?<![A-Za-z0-9])/(?:home|Users)/[^/\s]+)'
}
# What conversation looks like: the rules of the header, each with the count of matches that refuses.
$script:HordeFindingSpeakerLabel = '(?:user|assistant|human|ai|you|me|bot|customer|caller|q|a)[ \t]*:'
$script:HordeFindingConversationRules = @(
    @{ what = "a line that opens with a speaker's label"; least = 1
       pattern = '(?im)^[ \t>]*(?:\[[^\]\r\n]{1,40}\][ \t]*)?' + $script:HordeFindingSpeakerLabel }
    @{ what = "two or more speakers' labels, as a pasted chat has"; least = 2
       pattern = '(?i)(?<![A-Za-z0-9])' + $script:HordeFindingSpeakerLabel + '(?![/\\])' }
    @{ what = "two or more dialogue lines, each a name and a colon"; least = 2
       pattern = '(?m)^[ \t>]*(?:\[[^\]\r\n]{1,40}\][ \t]*)?[A-Za-z][A-Za-z0-9._-]*(?: [A-Za-z0-9._-]+){0,3}[ \t]*:[ \t]+\S' }
    @{ what = "two or more quoted reply lines"; least = 2
       pattern = '(?m)^[ \t]*>' }
    @{ what = "a transcript record's role field"; least = 1
       pattern = '(?i)"role"\s*:\s*"(?:user|assistant|system|tool|human)"' }
)

function Find-HordeFindingTextKind {
    # What a text looks like it holds that a finding must not, as words, or "" for none. The first of:
    # a credential (decisions/Rules.ps1), customer data, conversation.
    param([AllowEmptyString()][string]$Text)
    $secret = Find-HordeSecretKind -Text $Text
    if ($secret -ne "") { return ("what looks like " + $secret + ", a credential") }
    foreach ($name in $script:HordeFindingCustomerPatterns.Keys) {
        if ([regex]::IsMatch($Text, $script:HordeFindingCustomerPatterns[$name])) { return ("what looks like " + $name + ", customer data") }
    }
    foreach ($rule in $script:HordeFindingConversationRules) {
        if ([regex]::Matches($Text, $rule.pattern).Count -ge $rule.least) { return ("what looks like conversation: " + $rule.what) }
    }
    return ""
}

function Find-HordeFindingContentProblems {
    # A finding for every text, and every member NAME, anywhere in a parsed value that is not text or
    # holds what a finding must not. Each names the place and the kind, and NEVER the value: a refusal is
    # printed and may be kept, and repeating what it found would keep it after all. A name that is
    # itself refused is never used to say where anything else is.
    param($Value, [string]$Path = "the finding")
    $out = New-Object System.Collections.ArrayList
    if ($Value -is [string]) {
        $notText = Get-HordeDecisionCharProblem -Text $Value
        if ($notText -ne "") { [void]$out.Add($Path + " " + $notText) }
        $kind = Find-HordeFindingTextKind -Text $Value
        if ($kind -ne "") { [void]$out.Add($Path + " holds " + $kind + ". It is refused, and not repeated here") }
    }
    elseif ($Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject]) {
        $members = Get-HordeObjectByKey $Value
        foreach ($k in @($members.Keys)) {
            $where = $Path + "." + $k
            if ($Path -ceq "the finding") { $where = "" + $k }
            $nameKind = Find-HordeFindingTextKind -Text ("" + $k)
            $nameNotText = Get-HordeDecisionCharProblem -Text ("" + $k) -OneLine
            if ($nameKind -ne "" -or $nameNotText -ne "") {
                $where = "a field in " + $Path + " whose name is not repeated here"
                if ($nameKind -ne "") { [void]$out.Add("a field name in " + $Path + " holds " + $nameKind + ". It is refused, and not repeated here") }
                if ($nameNotText -ne "") { [void]$out.Add("a field name in " + $Path + " " + $nameNotText) }
            }
            foreach ($f in @(Find-HordeFindingContentProblems -Value $members[$k] -Path $where)) { [void]$out.Add($f) }
        }
    }
    elseif ($Value -is [System.Collections.IList]) {
        $i = 0
        foreach ($item in $Value) { $i++; foreach ($f in @(Find-HordeFindingContentProblems -Value $item -Path ($Path + " (item " + $i + ")"))) { [void]$out.Add($f) } }
    }
    return @($out)
}

function Get-HordeFindingCountProblem {
    # Why a list holds too few or too many items, or "".
    param($List, [string]$Path, [int]$Least, [int]$Most)
    $n = @($List).Count
    if ($null -eq $List) { $n = 0 }
    if ($n -lt $Least) { return ($Path + " holds " + $n + " item(s); it needs at least " + $Least) }
    if ($n -gt $Most) { return ($Path + " holds " + $n + " items; it may hold at most " + $Most) }
    return ""
}

function ConvertFrom-HordeFindingTime {
    # A window end as a UTC DateTime. The schema's pattern has already passed it; a date that does not
    # exist (February 30th) is $null.
    param([string]$Stamp)
    $parsedTime = [DateTime]::MinValue
    $forms = [string[]]@("yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'")
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([DateTime]::TryParseExact($Stamp, $forms, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsedTime)) { return $parsedTime }
    return $null
}

function Test-HordeFindingRules {
    # Findings for what schema/finding.v1 cannot say, on a value that has passed it. Empty means none.
    param([Parameter(Mandatory = $true)]$Finding)
    $out = New-Object System.Collections.ArrayList
    $metric = (Get-HordeObjectByKey $Finding)["metric"]
    $counted = (Get-HordeObjectByKey $metric)["countedFrom"]
    $lists = @{
        "metric.numbers" = (Get-HordeObjectByKey $metric)["numbers"]
        "metric.countedFrom.recordKinds" = (Get-HordeObjectByKey $counted)["recordKinds"]
        "metric.countedFrom.versions" = (Get-HordeObjectByKey $counted)["versions"]
    }
    foreach ($place in $script:HordeFindingListBounds.Keys) {
        $bound = $script:HordeFindingListBounds[$place]
        $p = Get-HordeFindingCountProblem -List $lists[$place] -Path $place -Least $bound.min -Most $bound.max
        if ($p -ne "") { [void]$out.Add($p) }
    }
    $i = 0
    foreach ($entry in @($lists["metric.numbers"])) {
        $i++
        $p = Get-HordeFindingCountProblem -List (Get-HordeObjectByKey $entry)["values"] -Path ("metric.numbers (item " + $i + ").values") -Least $script:HordeFindingValuesBounds.min -Most $script:HordeFindingValuesBounds.max
        if ($p -ne "") { [void]$out.Add($p) }
    }
    $window = Get-HordeObjectByKey (Get-HordeObjectByKey $counted)["window"]
    $starts = ConvertFrom-HordeFindingTime -Stamp ("" + $window["from"])
    $ends = ConvertFrom-HordeFindingTime -Stamp ("" + $window["to"])
    if ($null -eq $starts) { [void]$out.Add("metric.countedFrom.window.from is not a date and time that exists") }
    if ($null -eq $ends) { [void]$out.Add("metric.countedFrom.window.to is not a date and time that exists") }
    if ($null -ne $starts -and $null -ne $ends -and $ends -lt $starts) { [void]$out.Add("metric.countedFrom.window ends before it starts") }
    return @($out)
}

function New-HordeFindingAnswer {
    param([string]$State, $Finding, [string[]]$Problems)
    return [pscustomobject]@{ state = $State; finding = $Finding; findings = [string[]]@($Problems) }
}

function Read-HordeFindingText {
    # One finding from its TEXT: { state; finding; findings }. PURE: the same text gives the same answer
    # on any machine. ANY problem refuses, and a refusal carries no finding. The checks and their order
    # are in the header.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    if ($Text.Length -gt $script:HordeFindingMaxLength) { return (New-HordeFindingAnswer -State "refused" -Finding $null -Problems @("the finding is longer than " + $script:HordeFindingMaxLength + " characters")) }
    $wide = [regex]::Match($Text, '[^\x00-\x7F]')
    if ($wide.Success) {
        return (New-HordeFindingAnswer -State "refused" -Finding $null -Problems @("the finding holds the character U+" + ([int][char]$wide.Value).ToString("X4") + ", which is not ASCII. A finding is kept as ASCII: write the character as a \u escape"))
    }
    $parsedValue = $null
    try { $parsedValue = $Text | ConvertFrom-Json } catch { $parsedValue = $null }
    if ($null -eq $parsedValue -or $parsedValue -isnot [System.Management.Automation.PSCustomObject]) {
        return (New-HordeFindingAnswer -State "refused" -Finding $null -Problems @("the finding is not a JSON object the parser can read"))
    }
    $content = @(Find-HordeFindingContentProblems -Value $parsedValue)
    if ($content.Count -gt 0) { return (New-HordeFindingAnswer -State "refused" -Finding $null -Problems $content) }
    $twice = @(Find-HordeJsonDuplicateKey -Text $Text)
    if ($twice.Count -gt 0) { return (New-HordeFindingAnswer -State "refused" -Finding $null -Problems @($twice | ForEach-Object { "the finding says one thing twice: " + $_ })) }
    $unfit = @(Test-HordeSchema -Value $parsedValue -Schema (Get-HordeSchema -Name $script:HordeFindingSchemaName))
    if ($unfit.Count -gt 0) { return (New-HordeFindingAnswer -State "refused" -Finding $null -Problems @($unfit | ForEach-Object { "the finding does not fit schema/" + $script:HordeFindingSchemaName + ": " + $_ })) }
    $broken = @(Test-HordeFindingRules -Finding $parsedValue)
    if ($broken.Count -gt 0) { return (New-HordeFindingAnswer -State "refused" -Finding $null -Problems $broken) }
    return (New-HordeFindingAnswer -State "read" -Finding $parsedValue -Problems @())
}
