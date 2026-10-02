# remote/Protocol.ps1 - the link's wire: frames to bytes and bytes to frames, the size caps, and the
# choice of protocol version.
#
# A FRAME ON THE WIRE is one line: the frame as JSON, printable ASCII only, ending in LF (design 6.1).
# Every character outside printable ASCII - control characters and everything above 0x7E - is written
# as \uXXXX, so a frame is the same bytes whatever code page either console uses. PowerShell 5.1's
# ConvertTo-Json cannot be used for this: it leaves non-ASCII characters raw and escapes ' < > & instead
# (CONTRIBUTING 12), writes a [datetime] as "\/Date(...)\/", and at its default -Depth of 2 writes
# anything deeper as a type name with no error (core/Tristate.ps1, measured 2026-09-29). So this file
# writes JSON itself: ConvertTo-HordeWireText, one definition of how every value is spelled.
#
# ONE SPELLING PER FRAME. A received line is parsed, then written again with ConvertTo-HordeWireText,
# and it is refused unless the two are the same bytes. Both ends are Horde, so a frame that is not in
# that form did not come from Horde's encoder: extra spaces, a different escape for the same
# character, an exponent for a whole number, unquoted keys that ConvertFrom-Json might accept - each is
# refused rather than guessed at. One spelling also means a request's arguments hash the same at both
# ends (the request journal, plan step R3).
#
# THE ONE SPELLING FIXES WHAT PARSING FORGETS. The first version wrote keys in the order they arrived
# and wrote a decimal with the scale it arrived with, so the re-encoded text always matched: swapped
# keys, 1.0, 1.00 and pid:1234.0 were each accepted as canonical (review of PR #45, 2026-10-01). So:
#   - keys are written in ORDINAL ORDER, code unit by code unit, at every depth, whatever order the
#     object was built or received in;
#   - a number is a WHOLE NUMBER, written as one: no v1 schema has a fractional field, and 1.0 would be
#     a second spelling of 1, so the encoder refuses a [decimal], [double] or [single] outright, and a
#     received 1.0, which parses as a decimal, cannot be written again and is refused.
#
# WHAT A RECEIVER REFUSES, AND IN WHAT ORDER - cheapest first, so a hostile line costs little:
#   1. a line longer than the frame cap, before anything is parsed (oversized);
#   2. a byte order mark anywhere but the start of the stream, UTF-16, and any byte outside printable
#      ASCII - a raw byte above 0x7F, a NUL, a CR other than one just before the LF (bad-frame);
#   3. text that is not one JSON object (bad-frame);
#   4. a frame whose v is not 1 (unknown-version), read before the spelling and the schema, so that a
#      later version - which may spell itself differently - is named as one and not reported as a
#      malformed v1 frame;
#   4b. a frame not in the one spelling (bad-frame);
#   5. anything remote/Contract.ps1 refuses (bad-frame), then any cap it names (oversized).
# Each refusal carries a reason. The link closes on any of them: a line that is not a frame is never
# skipped, because a profile banner or a stray Write-Host would otherwise be read past silently
# (design 6.1).
#
# LINE ENDINGS. The encoder writes LF only. The reader accepts LF and CRLF, because PowerShell 5.1
# ends Write-Output lines with CRLF when stdout is redirected (measured below), and strips exactly one
# CR before the LF. A CR anywhere else is refused: JSON escapes it inside a string, so a raw one can
# only be damage.
#
# BYTE ORDER MARKS AND LINE ENDINGS, MEASURED 2026-09-30 on Windows PowerShell 5.1.26100.9444, raw
# bytes read from a child powershell.exe -NoProfile -NonInteractive -NoLogo, writing "ab":
#   to its redirected stdout with Write-Output ................................ 61 62 0D 0A
#     the same after [Console]::OutputEncoding = [Text.Encoding]::UTF8,
#     which has a BOM preamble, set by -Command or first thing in a -File .... 61 62 0D 0A
#   to its redirected stdout with [Console]::Out.Write("ab`n") ................ 61 62 0A
#   "a" + [char]0xE9 with Write-Output, default encoding ....................... 61 82 0D 0A
#     the same with a BOM-less UTF-8 OutputEncoding ............................ 61 C3 A9 0D 0A
#   [Console]::OutputEncoding = [Text.Encoding]::Unicode, Out.Write("ab`n") .... 61 00 62 00 0A 00
#   PIPED INTO a native program ("ab" | child) with $OutputEncoding = UTF8 ..... EF BB BF 61 62 0D 0A
#     the same with a BOM-less UTF-8 or ASCII $OutputEncoding ................. 61 62 0D 0A
# So on stdout 5.1 wrote no BOM in any case measured, and Write-Output ends every line with CRLF.
# A BOM DOES reach a pipe when PowerShell feeds a native program's stdin under a UTF-8 $OutputEncoding
# - the way a hub would feed a transport program - once, before the first byte. And the same "e with
# an acute accent" left as byte 0x82 under one code page and C3 A9 under another, which is why every
# non-ASCII character is escaped. test/test-link-protocol.ps1 repeats the stdout and pipe cases live.
# The reader therefore strips one UTF-8 BOM at the very start of a stream and refuses one anywhere
# else, strips one CR before each LF, and refuses UTF-16, naming it, rather than reporting its NULs
# as unexplained damage.
#
# SIZES. schema/link-frame.v1's x-horde-limits holds every cap as data (ruling of the plan review,
# 2026-09-30: core/Schema.ps1 has no size keywords and is being changed by two other pull requests).
# Test-HordeProtocolLimits enforces the per-field caps; the frame cap is enforced here, at both ends:
# the sender refuses to send a frame over it and the receiver refuses to parse one. A string is
# measured as it is on the wire, escapes included and quotes excluded, so a character written as
# \u00e9 costs six bytes of its cap - the cap is on what crosses, not on what it means.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Contract.ps1")

$script:HordeWireMaxDepth = 64
$script:HordeLinkProtocols = @(1)

function ConvertTo-HordeWireString {
    # A string as a JSON string literal in printable ASCII: " and \ escaped with a backslash, and every
    # character below 0x20 or above 0x7E as \u and four lower-case hex digits. A character outside the
    # Basic Multilingual Plane is two UTF-16 units in .NET and is written as two escapes, which JSON
    # reads back as the one character.
    #
    # REFUSED, BY THROWING, AT THE SENDER: a NUL, and half a surrogate pair. Each has an escape, so the
    # first version wrote both: the receiver accepted the NUL, and the lone surrogate went out to be
    # refused only at the other end (review of PR #45). Neither is
    # text: a NUL ends a string in most of what a node hands text to, and a lone surrogate is not a
    # character in any encoding. A received one is refused too, because the receiver writes the frame
    # again with this function and requires the same bytes.
    param([string]$Text)
    if ([regex]::IsMatch($Text, '\A[\x20\x21\x23-\x5B\x5D-\x7E]*\z')) { return ('"' + $Text + '"') }
    $sb = New-Object System.Text.StringBuilder ($Text.Length + 16)
    [void]$sb.Append('"')
    $chars = $Text.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $c = $chars[$i]
        $code = [int]$c
        if ($code -eq 0) { throw ("a NUL at character " + $i + " cannot cross the link: it is not text") }
        if ([char]::IsHighSurrogate($c)) {
            if ($i + 1 -ge $chars.Length -or -not [char]::IsLowSurrogate($chars[$i + 1])) { throw ("half a surrogate pair at character " + $i + " cannot cross the link: it is not a character") }
        } elseif ([char]::IsLowSurrogate($c)) {
            if ($i -eq 0 -or -not [char]::IsHighSurrogate($chars[$i - 1])) { throw ("half a surrogate pair at character " + $i + " cannot cross the link: it is not a character") }
        }
        if ($c -ceq '"') { [void]$sb.Append('\"') }
        elseif ($c -ceq '\') { [void]$sb.Append('\\') }
        elseif ($code -lt 0x20 -or $code -gt 0x7E) { [void]$sb.Append('\u').Append($code.ToString("x4")) }
        else { [void]$sb.Append($c) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Measure-HordeWireString {
    # How many bytes a string takes on the wire, quotes excluded: what its cap is measured against.
    param([string]$Text)
    return ((ConvertTo-HordeWireString $Text).Length - 2)
}

function ConvertTo-HordeWireText {
    # A value as JSON text in the one spelling the link uses: keys in ordinal order, whole numbers only,
    # no whitespace. Refused, by throwing: a [datetime] (times cross as ISO text, schema/link-frame.v1),
    # a fractional type ([decimal], [double], [single]), a key that is not a string, anything nested
    # deeper than 64, and any other type.
    param($Value, [int]$Depth = 0)
    if ($Depth -gt $script:HordeWireMaxDepth) { throw ("a value nested more than " + $script:HordeWireMaxDepth + " deep cannot cross the link") }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($null -eq $Value) { return "null" }
    if ($Value -is [string]) { return (ConvertTo-HordeWireString $Value) }
    if ($Value -is [bool]) { if ($Value) { return "true" } else { return "false" } }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64]) {
        return $Value.ToString($inv)
    }
    if ($Value -is [decimal] -or $Value -is [double] -or $Value -is [single]) {
        throw ("a number on the link is a whole number, written as one; " + $Value.ToString($inv) + " (a " + $Value.PSObject.TypeNames[0] + ") is not, and 1.0 would be a second spelling of 1")
    }
    if ($Value -is [datetime]) { throw "a [datetime] does not cross the link; write it as ISO 8601 text in UTC" }
    $parts = New-Object System.Collections.ArrayList
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($k in @($Value.Keys)) { if ($k -isnot [string]) { throw ("an object key must be a string, not " + $k.PSObject.TypeNames[0]) } }
        $keys = [string[]]@($Value.Keys)
        [Array]::Sort($keys, [System.StringComparer]::Ordinal)
        foreach ($k in $keys) {
            [void]$parts.Add((ConvertTo-HordeWireString $k) + ":" + (ConvertTo-HordeWireText -Value $Value[$k] -Depth ($Depth + 1)))
        }
        return ("{" + ($parts -join ",") + "}")
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        # A loop, not the pipeline: this runs for every object of every frame, the fuzz section's
        # thousands included.
        $props = @{}
        $names = New-Object System.Collections.Generic.List[string]
        foreach ($p in @($Value.PSObject.Properties)) { $props[$p.Name] = $p.Value; $names.Add($p.Name) }
        $keys = $names.ToArray()
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        foreach ($k in $keys) {
            [void]$parts.Add((ConvertTo-HordeWireString $k) + ":" + (ConvertTo-HordeWireText -Value $props[$k] -Depth ($Depth + 1)))
        }
        return ("{" + ($parts -join ",") + "}")
    }
    if ($Value -is [System.Collections.IList]) {
        foreach ($item in $Value) { [void]$parts.Add((ConvertTo-HordeWireText -Value $item -Depth ($Depth + 1))) }
        return ("[" + ($parts -join ",") + "]")
    }
    throw ("a " + $Value.PSObject.TypeNames[0] + " cannot cross the link")
}

function Get-HordeFrameCap {
    # The frame cap in use: the contract's frameBytes, or a smaller or larger one a deployment chose,
    # never above the ceiling (design 6.1: "never above 4 MiB").
    param($Contract, $FrameBytes = $null)
    $cap = $Contract.limits["frameBytes"]
    if ($null -ne $FrameBytes) { $cap = $FrameBytes }
    if (-not ($cap -is [int] -or $cap -is [long]) -or $cap -lt 1) { throw ("a frame cap is a positive whole number of bytes, not '" + $cap + "'") }
    if ($cap -gt $Contract.limits["frameBytesCeiling"]) { throw ("a frame cap of " + $cap + " bytes is above the ceiling of " + $Contract.limits["frameBytesCeiling"]) }
    return $cap
}

function New-HordeWireResult {
    param([bool]$Ok, $Frame = $null, [byte[]]$Bytes = $null, [string]$Code = "", [string]$Reason = "", [bool]$Bom = $false)
    return [pscustomobject]@{ ok = $Ok; frame = $Frame; bytes = $Bytes; code = $Code; reason = $Reason; bom = $Bom }
}

function Test-HordeProtocolLimits {
    # Every per-field cap of x-horde-limits, on a frame that remote/Contract.ps1 has already passed:
    # each string against the cap its schema names, measured as it is on the wire, and each array
    # against listItems. The envelope, the verb's arguments and a known result's value are each walked
    # with their own schema. Returns findings; empty means every field is within its cap.
    param($Frame, $Contract = $null)
    if ($null -eq $Contract) { $Contract = Get-HordeLinkContract }
    $walks = New-Object System.Collections.ArrayList
    [void]$walks.Add(@($Frame, $Contract.frame, $Contract.frame, '$'))
    $verb = Get-HordeLinkProp $Frame "verb"
    $row = $null
    if ($null -ne $verb -and $Contract.rows.ContainsKey("$verb")) { $row = $Contract.rows["$verb"] }
    if ($null -ne $row -and (Test-HordeLinkHasProp $Frame "args")) {
        $t = Resolve-HordeLinkTarget -Doc $Contract.verbs -Target "$($row.args)"
        [void]$walks.Add(@((Get-HordeLinkProp $Frame "args"), $t.node, $t.root, '$.args'))
    }
    $result = Get-HordeLinkProp $Frame "result"
    if ($null -ne $row -and $null -ne $result -and "$(Get-HordeLinkProp $result 'state')" -ceq "known") {
        $t = Resolve-HordeLinkTarget -Doc $Contract.verbs -Target "$($row.result)"
        [void]$walks.Add(@((Get-HordeLinkProp $result "value"), $t.node, $t.root, '$.result.value'))
    }
    $out = New-Object System.Collections.ArrayList
    # A HELLO'S VERSION LISTS are bounded tighter than any list: at most versionItems entries, none above
    # versionMax (review of PR #45). listItems (256) let a hello offer 256 versions, whose bye named all
    # of them in a reason over its cap, and nothing bounded a version's size.
    $hello = Get-HordeLinkProp $Frame "hello"
    if ($null -ne $hello) {
        foreach ($k in @("versionMax", "versionItems")) { if (-not $Contract.limits.ContainsKey($k)) { [void]$out.Add("x-horde-limits has no " + $k + ", so a hello's versions cannot be bounded") } }
        if ($out.Count -gt 0) { return @($out) }
        foreach ($list in @("protocols", "verbsVersions")) {
            $items = @(Get-HordeLinkProp $hello $list)
            if ($items.Count -gt $Contract.limits["versionItems"]) { [void]$out.Add('$.hello.' + $list + " has " + $items.Count + " versions, over the versionItems cap of " + $Contract.limits["versionItems"]) }
            foreach ($x in $items) {
                if (($x -is [int] -or $x -is [long]) -and [long]$x -gt [long]$Contract.limits["versionMax"]) { [void]$out.Add('$.hello.' + $list + " offers version " + $x + ", over the versionMax cap of " + $Contract.limits["versionMax"]) }
            }
        }
    }
    foreach ($w in $walks) {
        foreach ($x in @(Get-HordeLinkNodes -Value $w[0] -Node $w[1] -Root $w[2] -Path $w[3])) {
            $cap = Get-HordeLinkProp $x.node "x-horde-cap"
            if ($x.value -is [string]) {
                if ($null -eq $cap) {
                    if ($null -eq (Get-HordeLinkProp $x.node "enum")) { [void]$out.Add($x.path + " is a string whose schema names no cap") }
                    continue
                }
                $limit = $Contract.limits["$cap"]
                $size = Measure-HordeWireString $x.value
                if ($size -gt $limit) { [void]$out.Add($x.path + " is " + $size + " bytes on the wire, over its " + $cap + " cap of " + $limit) }
            } elseif ($x.value -is [System.Collections.IList]) {
                $limit = $Contract.limits["listItems"]
                if ($x.value.Count -gt $limit) { [void]$out.Add($x.path + " has " + $x.value.Count + " items, over the listItems cap of " + $limit) }
            }
        }
    }
    return @($out)
}

function ConvertTo-HordeFrameBytes {
    # One frame, ready to send: the contract checked, every cap checked, then the bytes with their LF.
    # A frame that fails any of them is refused HERE, at the sender, with the reason - never sent for
    # the other end to refuse.
    param([Parameter(Mandatory = $true)]$Frame, $Contract = $null, $FrameBytes = $null)
    if ($null -eq $Contract) { $Contract = Get-HordeLinkContract }
    $cap = Get-HordeFrameCap -Contract $Contract -FrameBytes $FrameBytes
    $found = @(Test-HordeLinkFrame -Frame $Frame -Contract $Contract)
    if ($found.Count -gt 0) { return (New-HordeWireResult -Ok $false -Code "bad-frame" -Reason ("not sent: " + ($found -join "; "))) }
    # Written before the caps are measured: a NUL or half a surrogate pair cannot be written, and the
    # caps measure strings as written, so the refusal is a bad-frame answer here, never a throw.
    $text = $null
    try { $text = ConvertTo-HordeWireText $Frame }
    catch { return (New-HordeWireResult -Ok $false -Code "bad-frame" -Reason ("not sent: the frame holds a value the link cannot carry: " + $_.Exception.Message)) }
    $found = @(Test-HordeProtocolLimits -Frame $Frame -Contract $Contract)
    if ($found.Count -gt 0) { return (New-HordeWireResult -Ok $false -Code "oversized" -Reason ("not sent: " + ($found -join "; "))) }
    if ($text.Length -gt $cap) { return (New-HordeWireResult -Ok $false -Code "oversized" -Reason ("not sent: the frame is " + $text.Length + " bytes, over the frame cap of " + $cap)) }
    $bytes = New-Object byte[] ($text.Length + 1)
    [void][System.Text.Encoding]::ASCII.GetBytes($text, 0, $text.Length, $bytes, 0)
    $bytes[$text.Length] = 10
    return (New-HordeWireResult -Ok $true -Frame $Frame -Bytes $bytes)
}

function ConvertFrom-HordeFrameBytes {
    # One received line - its bytes without the LF - to a frame, or a refusal with its code and reason.
    # -StreamStart says the line is the first of its stream, the one place a UTF-8 byte order mark is
    # stripped. Never throws on anything the other end sent.
    param([byte[]]$Bytes, $Contract = $null, $FrameBytes = $null, [switch]$StreamStart)
    if ($null -eq $Contract) { $Contract = Get-HordeLinkContract }
    $cap = Get-HordeFrameCap -Contract $Contract -FrameBytes $FrameBytes
    if ($null -eq $Bytes) { $Bytes = New-Object byte[] 0 }
    $start = 0
    $end = $Bytes.Length
    $bom = $false
    if ($end -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        if (-not $StreamStart) { return (New-HordeWireResult -Ok $false -Code "bad-frame" -Reason "a UTF-8 byte order mark in the middle of the stream: only the stream's first bytes may be one") }
        $start = 3
        $bom = $true
    }
    if ($end -ge 2 -and (($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) -or ($Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF))) {
        return (New-HordeWireResult -Ok $false -Code "bad-frame" -Reason "the stream is UTF-16 (it starts with a UTF-16 byte order mark); the link speaks ASCII")
    }
    if ($end -gt $start -and $Bytes[$end - 1] -eq 13) { $end-- }
    $length = $end - $start
    if ($length -gt $cap) { return (New-HordeWireResult -Ok $false -Code "oversized" -Bom $bom -Reason ("the frame is " + $length + " bytes, over the frame cap of " + $cap)) }
    if ($length -eq 0) { return (New-HordeWireResult -Ok $false -Code "bad-frame" -Bom $bom -Reason "an empty line is not a frame") }
    # Read as Latin-1, one character per byte, so a regular expression finds the first byte outside
    # printable ASCII without a PowerShell loop over up to a MiB of bytes; a line that passes is ASCII,
    # and the same text is what is parsed.
    $text = [System.Text.Encoding]::GetEncoding(28591).GetString($Bytes, $start, $length)
    $badAt = [regex]::Match($text, '[^\x20-\x7E]')
    if ($badAt.Success) {
        $b = [int][char]$badAt.Value
        $what = "byte 0x" + $b.ToString("X2")
        if ($b -eq 0) { $what = "a NUL byte (is the stream UTF-16?)" } elseif ($b -eq 13) { $what = "a CR that does not end the line" } elseif ($b -gt 0x7F) { $what = "a raw byte 0x" + $b.ToString("X2") + " above 0x7F" }
        return (New-HordeWireResult -Ok $false -Code "bad-frame" -Bom $bom -Reason ($what + " at offset " + $badAt.Index + "; a frame is printable ASCII"))
    }
    $frame = $null
    try { $frame = ConvertFrom-Json -InputObject $text -ErrorAction Stop }
    catch { return (New-HordeWireResult -Ok $false -Code "bad-frame" -Bom $bom -Reason ("the line is not JSON: " + $_.Exception.Message)) }
    if ($frame -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeWireResult -Ok $false -Code "bad-frame" -Bom $bom -Reason "the line is JSON but not one object") }
    if (-not (Test-HordeLinkHasProp $frame "v")) { return (New-HordeWireResult -Ok $false -Code "bad-frame" -Bom $bom -Reason "the frame has no version (v)") }
    $v = Get-HordeLinkProp $frame "v"
    if (-not ($v -is [int] -and $v -eq 1)) { return (New-HordeWireResult -Ok $false -Code "unknown-version" -Bom $bom -Reason ("the frame is version '" + $v + "'; this end reads version 1 only")) }
    $again = $null
    try { $again = ConvertTo-HordeWireText $frame } catch { return (New-HordeWireResult -Ok $false -Code "bad-frame" -Bom $bom -Reason ("the frame holds a value the link cannot carry: " + $_.Exception.Message)) }
    if (-not [string]::Equals($again, $text, [System.StringComparison]::Ordinal)) {
        $at = 0
        while ($at -lt $again.Length -and $at -lt $text.Length -and $again[$at] -ceq $text[$at]) { $at++ }
        return (New-HordeWireResult -Ok $false -Code "bad-frame" -Bom $bom -Reason ("the frame is not in the link's one spelling: it differs from Horde's encoding of it at offset " + $at))
    }
    $found = @(Test-HordeLinkFrame -Frame $frame -Contract $Contract)
    if ($found.Count -gt 0) { return (New-HordeWireResult -Ok $false -Code "bad-frame" -Bom $bom -Reason ($found -join "; ")) }
    $found = @(Test-HordeProtocolLimits -Frame $frame -Contract $Contract)
    if ($found.Count -gt 0) { return (New-HordeWireResult -Ok $false -Code "oversized" -Bom $bom -Reason ($found -join "; ")) }
    return (New-HordeWireResult -Ok $true -Frame $frame -Bom $bom)
}

function New-HordeFrameReader {
    # A reader of lines from a byte stream, bounded: it never holds more than one frame cap (plus a
    # BOM and a CR) of a line that has not ended, so a peer that never sends LF cannot make it buffer
    # without limit.
    param([Parameter(Mandatory = $true)][System.IO.Stream]$Stream, $Contract = $null, $FrameBytes = $null)
    if ($null -eq $Contract) { $Contract = Get-HordeLinkContract }
    $cap = Get-HordeFrameCap -Contract $Contract -FrameBytes $FrameBytes
    return [pscustomobject]@{ stream = $Stream; contract = $Contract; cap = $cap; pending = (New-Object byte[] 0); first = $true; closed = $null; lineNo = 0 }
}

function Read-HordeFrameLine {
    # The next line's bytes, without its LF: { state = line | end | error; bytes; reason }. end means
    # the stream closed between frames; a stream that closes inside a line is an error.
    param([Parameter(Mandatory = $true)]$Reader)
    $limit = $Reader.cap + 4
    $scanFrom = 0
    $chunk = New-Object byte[] 65536
    while ($true) {
        $idx = -1
        if ($Reader.pending.Length -gt $scanFrom) { $idx = [Array]::IndexOf($Reader.pending, [byte]10, $scanFrom) }
        if ($idx -ge 0) {
            $line = New-Object byte[] $idx
            [Array]::Copy($Reader.pending, 0, $line, 0, $idx)
            $rest = New-Object byte[] ($Reader.pending.Length - $idx - 1)
            [Array]::Copy($Reader.pending, $idx + 1, $rest, 0, $rest.Length)
            $Reader.pending = $rest
            return [pscustomobject]@{ state = "line"; bytes = $line; reason = "" }
        }
        if ($Reader.pending.Length -gt $limit) {
            return [pscustomobject]@{ state = "error"; bytes = $null; reason = ("oversized: more than " + $Reader.cap + " bytes arrived with no end of line") }
        }
        $scanFrom = $Reader.pending.Length
        $n = $Reader.stream.Read($chunk, 0, $chunk.Length)
        if ($n -le 0) {
            if ($Reader.pending.Length -eq 0) { return [pscustomobject]@{ state = "end"; bytes = $null; reason = "" } }
            return [pscustomobject]@{ state = "error"; bytes = $null; reason = ("bad-frame: the stream ended inside a frame, after " + $Reader.pending.Length + " bytes with no end of line") }
        }
        $grown = New-Object byte[] ($Reader.pending.Length + $n)
        [Array]::Copy($Reader.pending, 0, $grown, 0, $Reader.pending.Length)
        [Array]::Copy($chunk, 0, $grown, $Reader.pending.Length, $n)
        $Reader.pending = $grown
    }
}

function Receive-HordeFrame {
    # The next frame from a reader: { state = frame | end | closed; frame; code; reason }. The first
    # refusal CLOSES the reader, and every later call returns the same closed answer: a line that is
    # not a frame ends the link, and nothing after it is read.
    param([Parameter(Mandatory = $true)]$Reader)
    if ($null -ne $Reader.closed) { return $Reader.closed }
    $got = Read-HordeFrameLine -Reader $Reader
    $Reader.lineNo++
    if ($got.state -ceq "end") { return [pscustomobject]@{ state = "end"; frame = $null; code = ""; reason = "" } }
    if ($got.state -ceq "error") {
        $code = "bad-frame"
        if ($got.reason.StartsWith("oversized")) { $code = "oversized" }
        $Reader.closed = [pscustomobject]@{ state = "closed"; frame = $null; code = $code; reason = ("line " + $Reader.lineNo + ": " + $got.reason) }
        return $Reader.closed
    }
    $d = ConvertFrom-HordeFrameBytes -Bytes $got.bytes -Contract $Reader.contract -FrameBytes $Reader.cap -StreamStart:($Reader.first)
    $Reader.first = $false
    if (-not $d.ok) {
        $Reader.closed = [pscustomobject]@{ state = "closed"; frame = $null; code = $d.code; reason = ("line " + $Reader.lineNo + ": " + $d.reason) }
        return $Reader.closed
    }
    return [pscustomobject]@{ state = "frame"; frame = $d.frame; code = ""; reason = "" }
}

function Select-HordeLinkProtocol {
    # The highest protocol version both ends list, or 0 when they share none. Compared as [long], never
    # cast to [int]: a version of 1099511627776 threw at the cast (review of PR #45). Only a version of
    # Ours can win, so the answer always fits an [int].
    param([int[]]$Ours, $Theirs)
    $best = 0
    foreach ($t in @($Theirs)) {
        if (-not ($t -is [int] -or $t -is [long])) { continue }
        foreach ($o in $Ours) { if ([long]$o -eq [long]$t -and $o -gt $best) { $best = $o } }
    }
    return [int]$best
}

function Limit-HordeWireString {
    # Text cut so that it takes at most Bytes on the wire, with " ..." at the end when it was cut. Never
    # splits a surrogate pair, whose lone half the encoder refuses.
    param([string]$Text, [int]$Bytes)
    if ((Measure-HordeWireString $Text) -le $Bytes) { return $Text }
    $n = [Math]::Min($Text.Length, $Bytes)
    while ($n -gt 0) {
        if ([char]::IsHighSurrogate($Text[$n - 1])) { $n--; continue }
        $cut = $Text.Substring(0, $n) + " ..."
        if ((Measure-HordeWireString $cut) -le $Bytes) { return $cut }
        $n--
    }
    return "..."
}

function New-HordeLinkFrameId { return [guid]::NewGuid().ToString("D") }
function Get-HordeLinkTime { param([datetime]$At = (Get-Date)) return $At.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [System.Globalization.CultureInfo]::InvariantCulture) }

function New-HordeLinkBye {
    # A bye frame, the one way a side ends a link on purpose. Its reason is cut to the reasonBytes cap,
    # so a bye can always be sent, whatever it has to say.
    param([Parameter(Mandatory = $true)][string]$Code, [Parameter(Mandatory = $true)][string]$Reason, [Parameter(Mandatory = $true)][long]$Seq, $Contract = $null)
    if ($null -eq $Contract) { $Contract = Get-HordeLinkContract }
    $said = Limit-HordeWireString -Text $Reason -Bytes $Contract.limits["reasonBytes"]
    return [pscustomobject][ordered]@{ v = 1; kind = "bye"; id = (New-HordeLinkFrameId); seq = $Seq; ts = (Get-HordeLinkTime); bye = [pscustomobject][ordered]@{ code = $Code; reason = $said } }
}

function Resolve-HordeLinkHello {
    # What to do with the other side's hello: { protocol; bye }. protocol is the highest version both
    # speak; when there is none, protocol is 0 and bye is the frame that ends the link, naming both
    # lists, so the refusal is readable at both ends.
    param([Parameter(Mandatory = $true)]$Hello, [int[]]$Ours = $script:HordeLinkProtocols, [long]$Seq = 1, $Contract = $null)
    if ($null -eq $Contract) { $Contract = Get-HordeLinkContract }
    $theirs = @(Get-HordeLinkProp (Get-HordeLinkProp $Hello "hello") "protocols")
    $p = Select-HordeLinkProtocol -Ours $Ours -Theirs $theirs
    if ($p -gt 0) { return [pscustomobject]@{ protocol = $p; bye = $null } }
    # Their list is named up to versionItems entries; New-HordeLinkBye cuts the rest to the reason cap.
    $named = @($theirs | Select-Object -First $Contract.limits["versionItems"])
    $more = ""
    if ($theirs.Count -gt $named.Count) { $more = " and " + ($theirs.Count - $named.Count) + " more" }
    $reason = "no common protocol: this end speaks " + ($Ours -join ", ") + " and the other speaks " + ($named -join ", ") + $more
    return [pscustomobject]@{ protocol = 0; bye = (New-HordeLinkBye -Code "no-common-protocol" -Reason $reason -Seq $Seq -Contract $Contract) }
}
