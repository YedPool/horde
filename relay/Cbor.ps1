# relay/Cbor.ps1 - a strict reader for the CBOR a WebAuthn registration carries, and nothing more.
#
# WHY A READER OF OUR OWN. A passkey registration arrives as CBOR (RFC 8949): the attestationObject
# {fmt, attStmt, authData}, and inside authData the credential's COSE_Key and the extension outputs
# (WebAuthn Level 3, 6.1 and 6.5). Neither .NET runtime has a CBOR reader that both share (.NET has
# System.Formats.Cbor as a package, .NET Framework has nothing), and the bytes come from the phone over
# an untrusted relay, so the reader is small, written once for both runtimes, and refuses everything it
# does not need.
#
# WHAT IS READ: unsigned and negative integers that fit an Int64, byte strings, text strings (strict
# UTF-8), arrays, maps, true, false and null - with definite lengths, each in its SHORTEST form.
# WHAT IS REFUSED, each by name: indefinite lengths, a length or integer written longer than it needs
# (CTAP2's canonical encoding, which authenticators are held to, writes the shortest form; two
# spellings of one value would let two readers disagree), tags, floating-point numbers, undefined and
# the other simple values, a map key written twice (a reader that keeps the first and one that keeps
# the last would read two different keys), a length that runs past the end, nesting deeper than 8, and
# more than 64 items in one array or map. Map keys are not required to be in canonical ORDER: that
# changes no value, and authenticators have been seen to differ (relay design, spike list: a real
# phone's registration is still to be measured).
#
# A VALUE is { type; value }: type is uint, nint, bytes, text, array, map, bool or null; an integer's
# value is a [long], bytes a byte[], text a string, an array a list of values, a map a list of
# { key; value } pairs in the order written. Read-HordeRelayCbor answers { ok; reason; value; next },
# where next is the offset just past the item, and never throws for the input.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Bytes.ps1")

function Get-HordeRelayCborLimits {
    # depth: an attestationObject is a map holding a map (attStmt); authData's COSE key and extensions
    # are each read on their own, a map of scalars or of one level of maps. 8 is room, not a target.
    # items: a COSE EC2 key has 5 members, an attestationObject 3. 64 refuses a flood before it is read.
    return [pscustomobject]@{ depth = 8; items = 64 }
}

function New-HordeRelayCborAnswer {
    param([string]$Reason, $Value = $null, [int]$Next = 0)
    return [pscustomobject]@{ ok = ($Reason -ceq ""); reason = $Reason; value = $Value; next = $Next }
}

function Read-HordeRelayCborHead {
    # The initial byte at Offset and the number it carries: { ok; reason; major; info; number; next }.
    # number is a [decimal] so a 64-bit argument is read exactly before it is judged.
    param([byte[]]$Bytes, [int]$Offset)
    $fail = [pscustomobject]@{ ok = $false; reason = ""; major = -1; info = -1; number = [decimal]0; next = $Offset }
    if ($Offset -ge $Bytes.Length) { $fail.reason = "the CBOR ends where an item should begin"; return $fail }
    $ib = [int]$Bytes[$Offset]
    $major = $ib -shr 5
    $info = $ib -band 0x1f
    if ($info -lt 24) { return [pscustomobject]@{ ok = $true; reason = ""; major = $major; info = $info; number = [decimal]$info; next = ($Offset + 1) } }
    if ($info -eq 31) { $fail.reason = "the CBOR uses an indefinite length, which is not read here"; return $fail }
    if ($info -gt 27) { $fail.reason = ("the CBOR has a reserved additional-information value (" + $info + ")"); return $fail }
    $width = $(if ($info -eq 24) { 1 } elseif ($info -eq 25) { 2 } elseif ($info -eq 26) { 4 } else { 8 })
    if ($Offset + 1 + $width -gt $Bytes.Length) { $fail.reason = "the CBOR ends inside an item's length"; return $fail }
    $n = [decimal]0
    for ($i = 1; $i -le $width; $i++) { $n = $n * 256 + [decimal]$Bytes[$Offset + $i] }
    # Shortest form: each width is used only for a number the narrower one cannot hold.
    $floor = $(if ($width -eq 1) { [decimal]24 } elseif ($width -eq 2) { [decimal]256 } elseif ($width -eq 4) { [decimal]65536 } else { [decimal]4294967296 })
    if ($major -ne 7 -and $n -lt $floor) { $fail.reason = ("the CBOR writes " + $n + " in " + $width + " bytes: not its shortest form"); return $fail }
    return [pscustomobject]@{ ok = $true; reason = ""; major = $major; info = $info; number = $n; next = ($Offset + 1 + $width) }
}

function Read-HordeRelayCborItem {
    # One item at Offset, recursively, at nesting Depth.
    param([byte[]]$Bytes, [int]$Offset, [int]$Depth)
    $limits = Get-HordeRelayCborLimits
    if ($Depth -gt $limits.depth) { return (New-HordeRelayCborAnswer -Reason ("the CBOR nests deeper than " + $limits.depth)) }
    $h = Read-HordeRelayCborHead -Bytes $Bytes -Offset $Offset
    if (-not $h.ok) { return (New-HordeRelayCborAnswer -Reason $h.reason) }
    $maxLong = [decimal][long]::MaxValue
    if ($h.major -eq 0) {
        if ($h.number -gt $maxLong) { return (New-HordeRelayCborAnswer -Reason "the CBOR integer is larger than this reader holds") }
        return (New-HordeRelayCborAnswer -Reason "" -Value ([pscustomobject]@{ type = "uint"; value = [long]$h.number }) -Next $h.next)
    }
    if ($h.major -eq 1) {
        if ($h.number -gt $maxLong) { return (New-HordeRelayCborAnswer -Reason "the CBOR integer is more negative than this reader holds") }
        return (New-HordeRelayCborAnswer -Reason "" -Value ([pscustomobject]@{ type = "nint"; value = (-1 - [long]$h.number) }) -Next $h.next)
    }
    if ($h.major -eq 2 -or $h.major -eq 3) {
        if ($h.number -gt [decimal]($Bytes.Length - $h.next)) { return (New-HordeRelayCborAnswer -Reason "the CBOR string's length runs past the end") }
        $len = [int]$h.number
        $chunk = New-Object byte[] $len
        [System.Array]::Copy($Bytes, $h.next, $chunk, 0, $len)
        if ($h.major -eq 2) { return (New-HordeRelayCborAnswer -Reason "" -Value ([pscustomobject]@{ type = "bytes"; value = $chunk }) -Next ($h.next + $len)) }
        $strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
        try { $text = $strict.GetString($chunk) } catch { return (New-HordeRelayCborAnswer -Reason "the CBOR text string is not UTF-8") }
        return (New-HordeRelayCborAnswer -Reason "" -Value ([pscustomobject]@{ type = "text"; value = $text }) -Next ($h.next + $len))
    }
    if ($h.major -eq 4 -or $h.major -eq 5) {
        if ($h.number -gt [decimal]$limits.items) { return (New-HordeRelayCborAnswer -Reason ("the CBOR " + $(if ($h.major -eq 4) { "array" } else { "map" }) + " has more than " + $limits.items + " items")) }
        $count = [int]$h.number
        $at = $h.next
        $items = New-Object System.Collections.ArrayList
        $seen = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $count; $i++) {
            $k = Read-HordeRelayCborItem -Bytes $Bytes -Offset $at -Depth ($Depth + 1)
            if (-not $k.ok) { return $k }
            $at = $k.next
            if ($h.major -eq 4) { [void]$items.Add($k.value); continue }
            if (@("uint", "nint", "text") -cnotcontains $k.value.type) { return (New-HordeRelayCborAnswer -Reason ("the CBOR map has a key of type " + $k.value.type + "; only integers and text are read")) }
            $keyText = $k.value.type + ":" + $k.value.value
            if ($k.value.type -ceq "nint") { $keyText = "uint:" + $k.value.value }
            if ($seen -ccontains $keyText) { return (New-HordeRelayCborAnswer -Reason ("the CBOR map has the key " + $k.value.value + " more than once")) }
            [void]$seen.Add($keyText)
            $v = Read-HordeRelayCborItem -Bytes $Bytes -Offset $at -Depth ($Depth + 1)
            if (-not $v.ok) { return $v }
            $at = $v.next
            [void]$items.Add([pscustomobject]@{ key = $k.value; value = $v.value })
        }
        $type = $(if ($h.major -eq 4) { "array" } else { "map" })
        return (New-HordeRelayCborAnswer -Reason "" -Value ([pscustomobject]@{ type = $type; value = @($items.ToArray()) }) -Next $at)
    }
    if ($h.major -eq 6) { return (New-HordeRelayCborAnswer -Reason "the CBOR has a tag, which is not read here") }
    # Major type 7: only false (20), true (21) and null (22), in the initial byte.
    if ($h.info -eq 20) { return (New-HordeRelayCborAnswer -Reason "" -Value ([pscustomobject]@{ type = "bool"; value = $false }) -Next $h.next) }
    if ($h.info -eq 21) { return (New-HordeRelayCborAnswer -Reason "" -Value ([pscustomobject]@{ type = "bool"; value = $true }) -Next $h.next) }
    if ($h.info -eq 22) { return (New-HordeRelayCborAnswer -Reason "" -Value ([pscustomobject]@{ type = "null"; value = $null }) -Next $h.next) }
    if ($h.info -ge 25 -and $h.info -le 27) { return (New-HordeRelayCborAnswer -Reason "the CBOR has a floating-point number, which is not read here") }
    return (New-HordeRelayCborAnswer -Reason ("the CBOR has the simple value " + $h.number + ", which is not read here"))
}

function Read-HordeRelayCbor {
    # One CBOR item from Bytes at Offset. With -Whole, the item must end exactly at the end of Bytes.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes, [int]$Offset = 0, [switch]$Whole)
    if ($Offset -lt 0 -or $Offset -gt $Bytes.Length) { return (New-HordeRelayCborAnswer -Reason "the CBOR offset is outside its bytes") }
    $r = Read-HordeRelayCborItem -Bytes $Bytes -Offset $Offset -Depth 1
    if ($r.ok -and $Whole -and $r.next -ne $Bytes.Length) { return (New-HordeRelayCborAnswer -Reason ("there are " + ($Bytes.Length - $r.next) + " bytes after the CBOR item")) }
    return $r
}

function Get-HordeRelayCborMember {
    # The value under Key (an integer or a string) in a read map value, or $null when there is none.
    # The reader has already refused a key written twice, so there is at most one.
    param([Parameter(Mandatory = $true)]$Map, [Parameter(Mandatory = $true)]$Key)
    foreach ($pair in @($Map.value)) {
        if ($Key -is [string]) {
            if ($pair.key.type -ceq "text" -and $pair.key.value -ceq $Key) { return $pair.value }
        } elseif (($pair.key.type -ceq "uint" -or $pair.key.type -ceq "nint") -and $pair.key.value -eq [long]$Key) { return $pair.value }
    }
    return $null
}

function Get-HordeRelayCborKeyNames {
    # The keys of a read map value, as text: integers as their digits, strings as they are.
    param([Parameter(Mandatory = $true)]$Map)
    return @(@($Map.value) | ForEach-Object { "" + $_.key.value })
}
