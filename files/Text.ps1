# files/Text.ps1 - is a file that is named as text really text?
#
# THE ONE JOB of this file: the check a shared .md, .txt, .json, .html or .htm file must pass. A
# picture or a PDF is known by its first bytes (files/Share.ps1); text has no signature, so until
# 2026-10-13 any bytes at all passed under a text name (review of the files store: "any binary
# renamed .txt passes"). It is given THE SAME BUFFER that is hashed and stored - the file is read
# once - and it changes no byte of it.
#
# WHAT IS REQUIRED, and what was decided where the rule had a choice:
#   - A REFUSAL SAYS WHERE AND NEVER WHAT: the position of the byte, never the byte.
#   - STRICT UTF-8. A sequence that is no character REFUSES; nothing is replaced by U+FFFD. The
#     decoder is .NET's with throwing on, measured 2026-10-13 against 23 byte strings: it refuses a
#     bad byte at the start, in the middle and at the end, a sequence cut short at the end, every
#     overlong form (C0 80, C1 BF, E0 80 AF, F0 80 80 AF), a lone surrogate and a surrogate pair
#     written as two three-byte sequences (ED A0 80 ...), and anything past U+10FFFF.
#   - NO NUL. A NUL is valid UTF-8 (the same measurement: the decoder passes it), so it is looked
#     for by itself. Text never holds one; a binary file almost always does, and so does text saved
#     as UTF-16 or UTF-32 without a mark, byte by byte.
#   - A UTF-8 BYTE ORDER MARK IS ACCEPTED, and is kept: the bytes stored are the bytes of the file.
#     Windows editors write one, and refusing it would refuse ordinary files.
#   - UTF-16 IS REFUSED. With its mark (FF FE or FE FF) it is named as UTF-16. Without one it is
#     refused by what it does to the bytes: a NUL beside every Latin letter, or sequences that are
#     not UTF-8. KNOWN LIMIT: UTF-16 text with no mark whose bytes happen to be valid UTF-8 with no
#     NUL (the two characters U+4141 U+4242 are the bytes of "AABB") IS a valid UTF-8 file; nothing
#     can tell the two apart, and it is shared as the UTF-8 text it also is.
#   - AN EMPTY FILE is text - no characters is valid UTF-8 - so an empty .md, .txt or .html is
#     shared. An empty .json is REFUSED: it holds no JSON value.
#   - A .json FILE MUST BE EXACTLY ONE JSON TEXT, by RFC 8259 and not by any of the platform's three
#     parsers: files/Json.cs has the measurement of what each wrongly takes and wrongly refuses. A
#     mark, if there is one, is stepped over; the grammar starts after it. Two things the grammar
#     allows are refused too, because the readers of a shared file do not take them: more than 512
#     objects and arrays open at once, and half of a surrogate pair written alone as an escape.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced.

function Get-HordeFilesJsonProblem {
    # Why -Bytes, from -Offset, is not exactly one JSON text, or "". The checker is compiled once a
    # process, on first use, from the neighbour file (relay/BackendCng.ps1 does the same for its own).
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes, [int]$Offset = 0)
    if (-not ([System.Management.Automation.PSTypeName]"HordeFilesJsonV2").Type) { Add-Type -Path (Join-Path $PSScriptRoot "Json.cs") }
    return [HordeFilesJsonV2]::Problem($Bytes, $Offset)
}

function Get-HordeFilesTextProblem {
    # Why -Bytes may not be shared as text of media type -Type, or "" when it may. The header has
    # every rule and every choice.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes, [Parameter(Mandatory = $true)][string]$Type)
    if ($Bytes.Length -ge 2 -and (($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) -or ($Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF))) { return "it is UTF-16 (it starts with that encoding's byte order mark), and text is shared as UTF-8: save it as UTF-8" }
    $nul = [Array]::IndexOf($Bytes, [byte]0)
    if ($nul -ge 0) { return ("it holds a NUL byte (the first is byte " + $nul + "), which text never does: it is not text, or it is text saved as UTF-16 or UTF-32; text is shared as UTF-8") }
    $strict = New-Object System.Text.UTF8Encoding($false, $true)
    try { $null = $strict.GetCharCount($Bytes) }
    catch {
        # WHERE, AND NEVER WHAT. Until 2026-10-13 the reason printed the bytes themselves, as
        # hex. A reason is printed and logged, and a refusal must not repeat what the file
        # holds: those bytes are part of whatever the file is, a key saved in another encoding
        # as well as a letter of a legacy code page. The position is enough to find them.
        # The exception's own Index is not that position: measured 2026-10-13 on Windows
        # PowerShell 5.1, a bad byte at 37 was said to be at 36, one at 300 at 298, one at 0 at
        # -1. So the file is asked instead how long a beginning of it is still UTF-8, by halves:
        # a decoder that is not told the bytes have ended takes a character cut short for a
        # character still coming, so it throws for a beginning only when a byte in it is wrong.
        $which = " (it ends in the middle of a character)"
        $readsToTheEnd = $true
        try { $null = $strict.GetDecoder().GetCharCount($Bytes, 0, $Bytes.Length, $false) } catch { $readsToTheEnd = $false }
        if (-not $readsToTheEnd) {
            $stillText = 0
            $notText = $Bytes.Length
            while (($notText - $stillText) -gt 1) {
                $half = $stillText + [int][System.Math]::Floor(($notText - $stillText) / 2)
                $reads = $true
                try { $null = $strict.GetDecoder().GetCharCount($Bytes, 0, $half, $false) } catch { $reads = $false }
                if ($reads) { $stillText = $half } else { $notText = $half }
            }
            $which = " (it stops being UTF-8 at byte " + ($notText - 1) + ")"
        }
        return ("it is not UTF-8: it holds a byte sequence that is no character in UTF-8" + $which + "; text is shared as UTF-8")
    }
    if ($Type -ceq "application/json") {
        $after = 0
        if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { $after = 3 }
        $problem = Get-HordeFilesJsonProblem -Bytes $Bytes -Offset $after
        if ($problem -ne "") { return ("its name says JSON, but it is not: " + $problem) }
    }
    return ""
}
