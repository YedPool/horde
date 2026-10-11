# relay/Records.ps1 - the write-once records of a machine's relay identity, trust store and pairing
# offers: one canonical form, read by one anchored pattern, written once and never rewritten.
#
# WHERE: under <HORDE_HOME>\relay\ (Get-HordeRelayStateDir), beside the journal's folder. Each record is
# one file, named by what it is about, holding one line of JSON.
#
# ONE SPELLING, READ BY PATTERN, NOT BY A JSON PARSER. A record is written by
# ConvertTo-HordeRelayRecordText from a spec - an ordered list of { name; kind } - with members in the
# spec's order, no spacing, strings from alphabets that need no escaping, and integers as plain
# digits. Read-HordeRelayRecordText reads it back with ONE anchored pattern built from the same spec,
# so a record with a member missing, repeated, reordered or added, a value of the wrong kind, an escape
# or a space is refused as a whole, by its file name - the envelope's rule (relay/Envelope.ps1), kept
# without ConvertFrom-Json, which keeps the last of two repeated members silently and, under
# PowerShell 7, turns a string that looks like a date into a date (measured 2026-10-09).
#
# THE KINDS, and what each admits:
#   int      0 to 2^53-1 in digits, no leading zero (JavaScript reads it exactly)
#   bool     true or false
#   hex32    32 lower-case hex digits (a key id, a record id)
#   hex      0 to 128 lower-case hex digits, whole bytes (an aaguid)
#   b64u     canonical unpadded base64url, at most 8192 characters (relay/Bytes.ps1 refuses a second
#            spelling)
#   point    a b64u that is a 65-byte P-256 public point ON THE CURVE: checked on every read, so a key
#            damaged on disk is refused, not used
#   name     1 to 63 of a-z, 0-9 and -, starting with a letter or digit (a horde, a provider, a kind)
#   label    1 to 64 printable ASCII characters, no quote or backslash, no space at either end (what a
#            person called a device or machine)
#   text     0 to 512 printable ASCII characters, no quote or backslash (a reason)
#   rpid     a relying party id: lower-case host name characters, 1 to 253
#   origins  a list of 1 to 8 origins, each https://<host>[:port] or http://localhost[:port]
#   mailbox  <horde>/<reader>, each part a name (relays/Port.ps1's addressing)
#
# WRITE-ONCE, AS THE JOURNAL DOES IT (relay/Journal.ps1, decisions/Store.ps1): the text is written whole
# into a temporary file this writer holds open, flushed to disk, and given its name by
# core/FileAtomic.ps1's Move-HordeFileNewDurable, which never replaces. So a record is never seen half
# written and never overwritten; a second writer of one name is told "exists". Nothing here deletes a
# record: a trust entry ends with a revocation record beside it (relay/Trust.ps1), and a pairing offer
# is ended by a used marker (relay/Pairing.ps1). A writer killed before its move leaves a
# writing-<hex>.part file, which every reader here passes over: it never has a record's name.
#
# THE HONEST LIMIT: these files defend against crashes and damage, not against whoever can write to
# <HORDE_HOME>. Such a person can delete a revocation and so trust a device again, or add a device of
# their own; that access is already the machine owner's, and the journal says the same of itself.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\FileAtomic.ps1")
. (Join-Path $PSScriptRoot "Bytes.ps1")
. (Join-Path $PSScriptRoot "P256.ps1")

$script:HordeRelayRecordMaxBytes = 32768
$script:HordeRelayRecordOriginPattern = '(?:https://[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?|http://localhost)(?::[0-9]{1,5})?'
$script:HordeRelayRecordKinds = @{
    "int" = '(0|[1-9][0-9]{0,15})'
    "bool" = '(true|false)'
    "hex32" = '"([0-9a-f]{32})"'
    "hex" = '"((?:[0-9a-f]{2}){0,64})"'
    "b64u" = '"([A-Za-z0-9_-]{0,8192})"'
    "point" = '"([A-Za-z0-9_-]{87})"'
    "name" = '"([a-z0-9][a-z0-9-]{0,62})"'
    "label" = '"([\x21\x23-\x5B\x5D-\x7E](?:[\x20\x21\x23-\x5B\x5D-\x7E]{0,62}[\x21\x23-\x5B\x5D-\x7E])?)"'
    "text" = '"([\x20\x21\x23-\x5B\x5D-\x7E]{0,512})"'
    "rpid" = '"([a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?)"'
    "origins" = ('\[("' + $script:HordeRelayRecordOriginPattern + '"(?:,"' + $script:HordeRelayRecordOriginPattern + '"){0,7})\]')
    "mailbox" = '"([a-z0-9][a-z0-9-]{0,62}/[a-z0-9][a-z0-9-]{0,62})"'
}

function Get-HordeRelayStateDir {
    # <home>\relay\<Part>. -HordeHome, when given, must be absolute; without it the home is
    # core/Home.ps1's, whose refusal of a relative HORDE_HOME is thrown as it is.
    param([string]$HordeHome = "", [Parameter(Mandatory = $true)][string]$Part)
    $base = $HordeHome
    if ($base -ceq "") { $base = Get-HordeHome }
    elseif (-not [System.IO.Path]::IsPathRooted($base)) { throw ("-HordeHome must be an absolute path, not '" + $base + "'") }
    return [System.IO.Path]::Combine($base, "relay", $Part)
}

function ConvertTo-HordeRelayRecordMs {
    # Milliseconds since 1970 UTC: $null is now. In ticks, as relay/Journal.ps1 does it, so nothing
    # outside tools/ExecScan.ps1's relay profile is needed.
    param($Time = $null)
    $t = $Time
    if ($null -eq $t) { $t = [datetime]::UtcNow }
    $epoch = New-Object datetime -ArgumentList 1970, 1, 1, 0, 0, 0, ([System.DateTimeKind]::Utc)
    return [long][System.Math]::Floor(($t.ToUniversalTime().Ticks - $epoch.Ticks) / 10000)
}

function New-HordeRelayRecordSpec {
    # A spec from pairs: @("v", "int", "kind", "name", ...). Every record starts with v and kind.
    param([Parameter(Mandatory = $true)][string[]]$Pairs)
    $out = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $Pairs.Count; $i += 2) {
        if (-not $script:HordeRelayRecordKinds.ContainsKey($Pairs[$i + 1])) { throw ("no record kind '" + $Pairs[$i + 1] + "'") }
        [void]$out.Add([pscustomobject]@{ name = $Pairs[$i]; kind = $Pairs[$i + 1] })
    }
    return @($out.ToArray())
}

function Test-HordeRelayRecordValue {
    # "" when Value is a value of Kind as a record holds it, else why not. Values are strings, longs,
    # bools, or string arrays (origins).
    param([string]$Kind, $Value)
    if ($Kind -ceq "int") {
        if (($Value -isnot [long] -and $Value -isnot [int]) -or $Value -lt 0 -or $Value -gt [long]9007199254740991) { return "not a whole number from 0 to 2^53-1" }
        return ""
    }
    if ($Kind -ceq "bool") { if ($Value -isnot [bool]) { return "not true or false" }; return "" }
    if ($Kind -ceq "origins") {
        $list = @($Value)
        if ($list.Count -lt 1 -or $list.Count -gt 8) { return "not a list of 1 to 8 origins" }
        foreach ($o in $list) { if ($o -isnot [string] -or $o -cnotmatch ('\A' + $script:HordeRelayRecordOriginPattern + '\z')) { return ("'" + $o + "' is not an origin (https://<host>[:port] or http://localhost[:port])") } }
        return ""
    }
    if ($Value -isnot [string]) { return "not text" }
    # Every text kind's pattern is the quoted form, as the record holds it.
    if (('"' + $Value + '"') -cnotmatch ('\A' + $script:HordeRelayRecordKinds[$Kind] + '\z')) { return ("'" + $Value + "' is not a " + $Kind) }
    if ($Kind -ceq "b64u" -or $Kind -ceq "point") {
        try { $bytes = ConvertFrom-HordeRelayBase64Url -Text $Value } catch { return $_.Exception.Message }
        if ($Kind -ceq "point") {
            try { $k = ConvertFrom-HordeRelayP256Public -Bytes $bytes -Use "ecdsa"; $k.Dispose() } catch { return ("not a P-256 public key: " + $_.Exception.Message) }
        }
    }
    return ""
}

function ConvertTo-HordeRelayRecordText {
    # The canonical text of a record. Values is a hashtable by member name. Throws on a value that is
    # not of its kind: the caller checks what came from a person or the far end before it gets here.
    param([Parameter(Mandatory = $true)][object[]]$Spec, [Parameter(Mandatory = $true)][hashtable]$Values)
    $parts = New-Object System.Collections.ArrayList
    foreach ($f in $Spec) {
        if (-not $Values.ContainsKey($f.name)) { throw ("the record has no " + $f.name) }
        $v = $Values[$f.name]
        $why = Test-HordeRelayRecordValue -Kind $f.kind -Value $v
        if ($why -cne "") { throw ("the record's " + $f.name + " is refused: " + $why) }
        $t = ""
        if ($f.kind -ceq "int") { $t = ([long]$v).ToString([System.Globalization.CultureInfo]::InvariantCulture) }
        elseif ($f.kind -ceq "bool") { $t = $(if ($v) { "true" } else { "false" }) }
        elseif ($f.kind -ceq "origins") { $t = "[" + ((@($v) | ForEach-Object { '"' + $_ + '"' }) -join ",") + "]" }
        else { $t = '"' + $v + '"' }
        [void]$parts.Add('"' + $f.name + '":' + $t)
    }
    return ("{" + ($parts -join ",") + "}")
}

function Read-HordeRelayRecordText {
    # A record's values from its text, by the spec's one pattern: { ok; reason; value }, value a
    # pscustomobject with one property per member. Kind is the kind member the text must carry.
    param([AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][object[]]$Spec, [Parameter(Mandatory = $true)][string]$Kind, [string]$What = "the record")
    $fail = [pscustomobject]@{ ok = $false; reason = ""; value = $null }
    $pattern = "\A\{" + ((@($Spec) | ForEach-Object { '"' + $_.name + '":' + $script:HordeRelayRecordKinds[$_.kind] }) -join ",") + "\}\z"
    $m = [regex]::Match($Text, $pattern)
    if (-not $m.Success) { $fail.reason = ($What + " is not in its canonical form (a member missing, added, repeated or out of order, a value of the wrong kind, or spacing)"); return $fail }
    $vals = [ordered]@{}
    for ($i = 0; $i -lt $Spec.Count; $i++) {
        $f = $Spec[$i]
        $raw = $m.Groups[$i + 1].Value
        $v = $raw
        if ($f.kind -ceq "int") { $v = [long]$raw }
        elseif ($f.kind -ceq "bool") { $v = ($raw -ceq "true") }
        elseif ($f.kind -ceq "origins") { $v = @([regex]::Split($raw.Substring(1, $raw.Length - 2), '","')) }
        $why = Test-HordeRelayRecordValue -Kind $f.kind -Value $v
        if ($why -cne "") { $fail.reason = ($What + "'s " + $f.name + " is refused: " + $why); return $fail }
        $vals[$f.name] = $v
    }
    if ($vals.Contains("kind") -and $vals["kind"] -cne $Kind) { $fail.reason = ($What + " is a " + $vals["kind"] + ", not a " + $Kind); return $fail }
    if ($vals.Contains("v") -and $vals["v"] -ne 1) { $fail.reason = ($What + " is version " + $vals["v"] + "; only version 1 is read"); return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; value = [pscustomobject]$vals }
}

function Write-HordeRelayRecordFile {
    # Put -Text under -Name in -Dir, write-once (the header). "moved", "exists" or "unconfirmed"
    # (core/FileAtomic.ps1); throws otherwise, leaving no temporary file. The folder is made if missing.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Text)
    $bytes = Get-HordeRelayAsciiBytes -Text $Text
    [void][System.IO.Directory]::CreateDirectory($Dir)
    $tmp = [System.IO.Path]::Combine($Dir, ("writing-" + [guid]::NewGuid().ToString("N") + ".part"))
    $fs = New-Object System.IO.FileStream -ArgumentList $tmp, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::Delete), 4096, ([System.IO.FileOptions]::WriteThrough)
    $moved = ""
    try {
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush($true)
        $moved = Move-HordeFileNewDurable -From $tmp -To ([System.IO.Path]::Combine($Dir, $Name)) -Open $fs
    } finally {
        $fs.Dispose()
        if ($moved -cne "moved" -and $moved -cne "unconfirmed") { try { [System.IO.File]::Delete($tmp) } catch { } }
    }
    return $moved
}

function Read-HordeRelayRecordFile {
    # The text of one record file: { ok; found; reason; text }. found is $false, with ok $true, when
    # there is no such file; a file that is too large or not printable ASCII is refused.
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $fs = New-Object System.IO.FileStream -ArgumentList $Path, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), ([System.IO.FileShare]::Read)
    } catch [System.IO.FileNotFoundException] {
        return [pscustomobject]@{ ok = $true; found = $false; reason = ""; text = "" }
    } catch [System.IO.DirectoryNotFoundException] {
        return [pscustomobject]@{ ok = $true; found = $false; reason = ""; text = "" }
    } catch {
        return [pscustomobject]@{ ok = $false; found = $false; reason = ("'" + $Path + "' could not be read: " + $_.Exception.Message); text = "" }
    }
    try {
        if ($fs.Length -gt $script:HordeRelayRecordMaxBytes) { return [pscustomobject]@{ ok = $false; found = $true; reason = ("'" + $Path + "' is larger than a record can be"); text = "" } }
        $buf = New-Object byte[] ([int]$fs.Length)
        $at = 0
        while ($at -lt $buf.Length) {
            $n = $fs.Read($buf, $at, $buf.Length - $at)
            if ($n -le 0) { break }
            $at += $n
        }
    } finally { $fs.Dispose() }
    $text = [System.Text.Encoding]::ASCII.GetString($buf, 0, $at)
    if ($text -cnotmatch '\A[\x20-\x7E]*\z') { return [pscustomobject]@{ ok = $false; found = $true; reason = ("'" + $Path + "' is not one line of printable ASCII"); text = "" } }
    return [pscustomobject]@{ ok = $true; found = $true; reason = ""; text = $text }
}

function Get-HordeRelayRecordNames {
    # The record names in -Dir that match -Pattern: { ok; reason; names }. No folder is no records.
    # A writer's temporary file is passed over; any other name is damage, and refuses the whole folder.
    param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][string]$Pattern)
    $items = @()
    try { $items = @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction Stop) }
    catch {
        # A folder that is not there is PathNotFound (measured 2026-10-09 on both runtimes); asked by the
        # error's id because the exception's type is not one tools/ExecScan.ps1 lets relay/ name.
        if (("" + $_.FullyQualifiedErrorId).StartsWith("PathNotFound")) { return [pscustomobject]@{ ok = $true; reason = ""; names = @() } }
        return [pscustomobject]@{ ok = $false; reason = ("'" + $Dir + "' could not be listed: " + $_.Exception.Message); names = @() }
    }
    $names = New-Object System.Collections.ArrayList
    foreach ($it in $items) {
        $n = "" + $it.Name
        if ($n -cmatch '\Awriting-[0-9a-f]{32}\.part\z') { continue }
        if ($it.PSIsContainer -or $n -cnotmatch $Pattern) { return [pscustomobject]@{ ok = $false; reason = ("'" + $Dir + "' holds '" + $n + "', which is not a record this folder keeps; the folder is refused until a person removes it"); names = @() } }
        [void]$names.Add($n)
    }
    return [pscustomobject]@{ ok = $true; reason = ""; names = @($names.ToArray() | Sort-Object) }
}
