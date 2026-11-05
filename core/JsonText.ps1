# core/JsonText - what Horde checks in JSON text before it parses it, and the parse itself.
#
# ONE SCANNER, SHARED. ConvertFrom-Json in Windows PowerShell 5.1 keeps one of two repeated keys and
# reports nothing, so text can show its reader one value and give Horde another. core/Ownership.ps1
# (the ownership table) and core/PermissionLevels.ps1 (the permission-level vocabulary) both refuse
# such text through Find-HordeJsonDuplicateKey, which lives here alone. Until 2026-10-02 each file had
# a scanner of its own under that one name, with different answers - a list of findings ignoring case,
# against the first repeat compared exactly - and PowerShell gives a name to whichever definition
# loads last, so a caller loading both would have run one while its author tested the other
# (test/test-function-names.ps1 now fails on any name defined twice). Moved here unchanged from
# core/Ownership.ps1, with one change: an unterminated string now ends the scan instead of throwing.
# test/test-json-text.ps1 holds it.
#
# No Set-StrictMode here: this file is dot-sourced, so a file-scope Set-StrictMode would set the
# caller's mode (see core/Tristate.ps1). The function runs under -Version Latest.

# THE BYTE CHECK lives here too (review of #109): every reader of a Horde data file runs it before it
# decodes, and every one of them already loads this file, so no reader can call it without loading it
# (core/NodePolicy.ps1 once called it from a file it never loaded; tools/CoreLoad.ps1 now guards that).

# THE ONE PARSE, the same under both PowerShells (issue #274; made one strict parser for T-0366, M's
# option A, 2026-10-28). ConvertFrom-HordeJson is the parse a Horde reader uses instead of ConvertFrom-Json.
# Each shell's own ConvertFrom-Json gave its own answer for the same text (measured 2026-10-28, 7.6.6 and 5.1):
#   - 7 read a date-shaped string as a [datetime] (5.1 never did), so `horde decisions add` refused its own
#     new record: "it is not a decision-event.v1 record: $.at should be string";
#   - 7 wrote a top-level array's items one at a time, so '[7]' came back as the number 7 and '[]' as nothing;
#   - a whole number was Int64 under 7 and Int32 under 5.1; 1.5 was a Double under 7 and a Decimal under 5.1;
#   - each read more than JSON, and not the same more: both took 01, .5, NaN, Infinity, a raw tab inside a
#     string and 'single quotes'; 7 alone took [1,] and 0x10, 5.1 alone took +1; 7 read 1e400 as Infinity.
# So the text is read here by ONE PARSER, compiled into whichever shell loads this file (C# 5, which 5.1's
# compiler is), and every answer below is that parser's, the same under both:
#   - JSON as RFC 8259 writes it and nothing else: anything else throws, as text that is not JSON;
#   - every string is a string, exactly as written;
#   - an object is a PSCustomObject, as ConvertFrom-Json gives it; a repeated key keeps the last value, as both
#     shells did; two keys differing only in case, an empty key, or a key a PSCustomObject keeps for itself
#     (PSObject) throw, as both shells did;
#   - an array is one object[], at the top level too, so @(ConvertFrom-HordeJson '[1,2]').Count is 1;
#   - a number takes 5.1's types, in 5.1's order: Int32, else Int64, else Decimal (a fraction, or a whole
#     number past Int64), else a Double (an exponent); one too large for a Double throws;
#   - nesting past 100 levels throws (5.1's limit, near enough: it took 101 arrays and refused 102 objects);
#   - text that is empty or only whitespace is $null, and lines given as a list are one text joined by
#     newlines, as ConvertFrom-Json took them from the pipeline.
$script:HordeJsonMakesDates = ("" + $PSVersionTable.PSEdition) -ceq "Core"
if (-not ("HordeJsonStrictReader" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text;
public static class HordeJsonStrictReader {
    private const int MaxDepth = 100;
    public static object Read(string text) {
        int i = 0;
        SkipSpace(text, ref i);
        if (i == text.Length) { return null; }
        object value = ReadValue(text, ref i, 0);
        SkipSpace(text, ref i);
        if (i != text.Length) { throw Bad(i, "text after the value"); }
        return value;
    }
    private static FormatException Bad(int at, string what) {
        return new FormatException("not JSON: " + what + " at character " + at.ToString(CultureInfo.InvariantCulture));
    }
    private static void SkipSpace(string text, ref int i) {
        while (i < text.Length && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n' || text[i] == '\r')) { i++; }
    }
    private static object ReadValue(string text, ref int i, int depth) {
        if (i >= text.Length) { throw Bad(i, "the end where a value should be"); }
        char c = text[i];
        if (c == '{') { return ReadObject(text, ref i, depth + 1); }
        if (c == '[') { return ReadArray(text, ref i, depth + 1); }
        if (c == '"') { return ReadString(text, ref i); }
        if (c == '-' || (c >= '0' && c <= '9')) { return ReadNumber(text, ref i); }
        if (Word(text, ref i, "true")) { return true; }
        if (Word(text, ref i, "false")) { return false; }
        if (Word(text, ref i, "null")) { return null; }
        throw Bad(i, "a character no value starts with");
    }
    private static bool Word(string text, ref int i, string word) {
        if (i + word.Length > text.Length || string.CompareOrdinal(text, i, word, 0, word.Length) != 0) { return false; }
        i += word.Length;
        return true;
    }
    private static PSObject ReadObject(string text, ref int i, int depth) {
        if (depth > MaxDepth) { throw Bad(i, "nesting past " + MaxDepth.ToString(CultureInfo.InvariantCulture) + " levels"); }
        PSObject o = new PSObject();
        i++;
        SkipSpace(text, ref i);
        if (i < text.Length && text[i] == '}') { i++; return o; }
        while (true) {
            SkipSpace(text, ref i);
            if (i >= text.Length || text[i] != '"') { throw Bad(i, "a key that is not a string"); }
            int keyAt = i;
            string key = ReadString(text, ref i);
            SkipSpace(text, ref i);
            if (i >= text.Length || text[i] != ':') { throw Bad(i, "a key with no colon after it"); }
            i++;
            SkipSpace(text, ref i);
            object value = ReadValue(text, ref i, depth);
            if (key.Length == 0) { throw new InvalidOperationException("not JSON a PowerShell object can hold: an empty key at character " + keyAt.ToString(CultureInfo.InvariantCulture)); }
            PSPropertyInfo have = o.Properties[key];
            if (have == null) { o.Properties.Add(new PSNoteProperty(key, value)); }
            else if (string.Equals(have.Name, key, StringComparison.Ordinal)) { have.Value = value; }
            else { throw new InvalidOperationException("not JSON a PowerShell object can hold: keys '" + have.Name + "' and '" + key + "' differ only in case"); }
            SkipSpace(text, ref i);
            if (i < text.Length && text[i] == ',') { i++; continue; }
            if (i < text.Length && text[i] == '}') { i++; return o; }
            throw Bad(i, "an object not closed");
        }
    }
    private static object[] ReadArray(string text, ref int i, int depth) {
        if (depth > MaxDepth) { throw Bad(i, "nesting past " + MaxDepth.ToString(CultureInfo.InvariantCulture) + " levels"); }
        List<object> list = new List<object>();
        i++;
        SkipSpace(text, ref i);
        if (i < text.Length && text[i] == ']') { i++; return list.ToArray(); }
        while (true) {
            SkipSpace(text, ref i);
            list.Add(ReadValue(text, ref i, depth));
            SkipSpace(text, ref i);
            if (i < text.Length && text[i] == ',') { i++; continue; }
            if (i < text.Length && text[i] == ']') { i++; return list.ToArray(); }
            throw Bad(i, "an array not closed");
        }
    }
    private static string ReadString(string text, ref int i) {
        StringBuilder sb = new StringBuilder();
        i++;
        while (true) {
            if (i >= text.Length) { throw Bad(i, "a string not closed"); }
            char c = text[i];
            if (c == '"') { i++; return sb.ToString(); }
            if (c < ' ') { throw Bad(i, "a control character inside a string"); }
            if (c != '\\') { sb.Append(c); i++; continue; }
            if (i + 1 >= text.Length) { throw Bad(i, "a string not closed"); }
            char e = text[i + 1];
            switch (e) {
                case '"': sb.Append('"'); break;
                case '\\': sb.Append('\\'); break;
                case '/': sb.Append('/'); break;
                case 'b': sb.Append('\b'); break;
                case 'f': sb.Append('\f'); break;
                case 'n': sb.Append('\n'); break;
                case 'r': sb.Append('\r'); break;
                case 't': sb.Append('\t'); break;
                case 'u':
                    int code;
                    if (i + 6 > text.Length || !int.TryParse(text.Substring(i + 2, 4), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out code)) { throw Bad(i, "a \\u escape without four hex digits"); }
                    sb.Append((char)code);
                    i += 4;
                    break;
                default: throw Bad(i, "an escape JSON does not have");
            }
            i += 2;
        }
    }
    private static object ReadNumber(string text, ref int i) {
        int start = i;
        if (text[i] == '-') { i++; }
        if (i < text.Length && text[i] == '0') { i++; }
        else if (i < text.Length && text[i] >= '1' && text[i] <= '9') { while (i < text.Length && text[i] >= '0' && text[i] <= '9') { i++; } }
        else { throw Bad(i, "a number with no digits"); }
        if (i < text.Length && text[i] == '.') {
            i++;
            if (i >= text.Length || text[i] < '0' || text[i] > '9') { throw Bad(i, "a number with no digits after its point"); }
            while (i < text.Length && text[i] >= '0' && text[i] <= '9') { i++; }
        }
        if (i < text.Length && (text[i] == 'e' || text[i] == 'E')) {
            i++;
            if (i < text.Length && (text[i] == '+' || text[i] == '-')) { i++; }
            if (i >= text.Length || text[i] < '0' || text[i] > '9') { throw Bad(i, "a number with no digits in its exponent"); }
            while (i < text.Length && text[i] >= '0' && text[i] <= '9') { i++; }
        }
        if (i < text.Length && ((text[i] >= '0' && text[i] <= '9') || text[i] == '.' || char.IsLetter(text[i]))) { throw Bad(i, "a number written as JSON does not write one"); }
        string s = text.Substring(start, i - start);
        int n; long l; decimal m; double d;
        if (int.TryParse(s, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out n)) { return n; }
        if (long.TryParse(s, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out l)) { return l; }
        if (decimal.TryParse(s, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out m)) { return m; }
        if (double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out d) && !double.IsInfinity(d)) { return d; }
        throw Bad(start, "a number too large to hold");
    }
}
'@
}

function ConvertFrom-HordeJson {
    # -Text parsed as JSON by the one strict parser above, the same under both shells. Throws on text that is
    # not JSON, as ConvertFrom-Json threw, so a caller's try/catch is unchanged.
    param($Text)
    if ($null -eq $Text) { throw (New-Object System.ArgumentNullException "Text", "there is no text to parse") }
    if ($Text -is [array]) { $Text = @($Text | ForEach-Object { "" + $_ }) -join "`n" }
    $parsed = [HordeJsonStrictReader]::Read(("" + $Text))
    # The comma keeps a top-level array one value on the way out.
    if ($parsed -is [array]) { return , $parsed }
    return $parsed
}

# THE DICTIONARY PARSE (T-0323): ConvertFrom-HordeJsonObject is the parse for a reader that wants plain .NET
# values and not PowerShell objects - a transcript line, a stores.json, a price table. It was
# System.Web.Script.Serialization.JavaScriptSerializer at every site (chosen 2026-10-01 for speed and
# dictionaries, see core/Transcript.ps1), and that class cannot run under PowerShell 7 on .NET 10: every call
# throws "Could not load type System.Web.UI.WebResourceAttribute", and the callers' catch-and-skip read each
# row as unparseable. The shape it returns is the shape JavaScriptSerializer gave, under both:
#   - an object is a Dictionary[string, object] (case-sensitive keys; a repeated key keeps the last);
#   - an array is an object[]; a string, bool or $null is itself;
#   - a whole number is Int32, or Int64 when it does not fit; any other number is a Decimal.
#   - text that is not JSON throws, as does nesting past 100 levels.
# 5.1 keeps JavaScriptSerializer unchanged; 7 reads with System.Text.Json through a small compiled type.
$script:HordeJsonObjectSerializer = $null
if ($script:HordeJsonMakesDates -and -not ("HordeJsonObjectReader" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text.Json;
public static class HordeJsonObjectReader {
    public static object Read(string text) {
        var options = new JsonDocumentOptions { MaxDepth = 100 };
        using (JsonDocument doc = JsonDocument.Parse(text, options)) { return Convert(doc.RootElement); }
    }
    private static object Convert(JsonElement e) {
        switch (e.ValueKind) {
            case JsonValueKind.Object:
                var d = new Dictionary<string, object>();
                foreach (JsonProperty p in e.EnumerateObject()) { d[p.Name] = Convert(p.Value); }
                return d;
            case JsonValueKind.Array:
                var list = new List<object>();
                foreach (JsonElement x in e.EnumerateArray()) { list.Add(Convert(x)); }
                return list.ToArray();
            case JsonValueKind.String: return e.GetString();
            case JsonValueKind.True: return true;
            case JsonValueKind.False: return false;
            case JsonValueKind.Number:
                int i; long l; decimal m;
                if (e.TryGetInt32(out i)) { return i; }
                if (e.TryGetInt64(out l)) { return l; }
                if (e.TryGetDecimal(out m)) { return m; }
                return e.GetDouble();
            default: return null;
        }
    }
}
'@
}

function ConvertFrom-HordeJsonObject {
    # -Text parsed as JSON into dictionaries, object[] and plain values (above). Throws on text that is not JSON.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    if ($script:HordeJsonMakesDates) { return , [HordeJsonObjectReader]::Read($Text) }
    if ($null -eq $script:HordeJsonObjectSerializer) {
        Add-Type -AssemblyName System.Web.Extensions
        $script:HordeJsonObjectSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $script:HordeJsonObjectSerializer.MaxJsonLength = [int]::MaxValue
    }
    return , $script:HordeJsonObjectSerializer.DeserializeObject($Text)
}

function Assert-HordeAsciiBytes {
    # Throw unless the bytes are plain ASCII with no byte-order mark and no control byte but tab, CR and
    # LF. Checked before decoding: a decoder turns a stray byte into a character, or a replacement mark,
    # and either reads as text. A NUL is how a file saved as UTF-16 without a mark looks byte by byte, so
    # it is named as that rather than left to fail later as not JSON (review of #109).
    param([byte[]]$Bytes, [string]$What)
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { throw ($What + " starts with a UTF-8 byte-order mark; save it as plain ASCII (CONTRIBUTING 13)") }
    foreach ($b in $Bytes) {
        if ($b -gt 0x7F) { throw ($What + " holds a byte that is not ASCII (CONTRIBUTING 13)") }
        if ($b -lt 0x20 -and $b -ne 0x09 -and $b -ne 0x0A -and $b -ne 0x0D) { throw ($What + " holds the control byte 0x" + ([int]$b).ToString("X2") + $(if ($b -eq 0) { ", as a file saved as UTF-16 does" } else { "" }) + "; save it as plain ASCII (CONTRIBUTING 13)") }
    }
}

function Find-HordeJsonDuplicateKey {
    # Every key that appears more than once in ONE object of a JSON text, as findings.
    #
    # WHY THE TEXT AND NOT THE PARSED TABLE: ConvertFrom-Json keeps one of two repeated keys and
    # reports nothing, so {"owner":"agent","owner":"engine"} parses to a field with one owner and
    # passes every check on the parsed object. A review found exactly that on 2026-09-29.
    #
    # PER OBJECT, NOT PER FILE: "store" legitimately appears in every read entry. Keys are
    # compared ignoring case, because PowerShell reads properties ignoring case and Windows
    # PowerShell 5.1's ConvertFrom-Json throws on two keys that differ only in case.
    # A key written with escapes is decoded before it is compared, so an escaped spelling of a
    # key is still the same key.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $out = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.ArrayList   # one frame per open object or array
    $i = 0; $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($c -eq '"') {
            $start = $i; $i++
            while ($i -lt $n -and $Text[$i] -ne '"') { if ($Text[$i] -eq '\') { $i++ }; $i++ }
            # AN UNTERMINATED STRING ENDS THE SCAN: nothing after it can be a key, and reading its
            # text ran Substring past the end ("{\"a\\" threw, review of this fix). ConvertFrom-Json
            # refuses the text with its own message.
            if ($i -ge $n) { break }
            $i++
            if ($stack.Count -eq 0) { continue }
            $top = $stack[$stack.Count - 1]
            if ($top.kind -ne "object" -or -not $top.expectKey) { continue }
            $key = $Text.Substring($start + 1, [Math]::Max(0, $i - $start - 2))
            if ($key.Contains('\')) { try { $key = [string]('"' + $key + '"' | ConvertFrom-Json) } catch { } }
            $low = $key.ToLowerInvariant()
            if ($top.keys.ContainsKey($low)) {
                [void]$out.Add("key '" + $key + "' appears more than once in one object (" + $top.path + ")")
            }
            $top.keys[$low] = $true
            $top.lastKey = $key
            $top.expectKey = $false
            continue
        }
        if ($c -eq '{' -or $c -eq '[') {
            $path = "top level"
            if ($stack.Count -gt 0) {
                $parent = $stack[$stack.Count - 1]
                if ($parent.kind -eq "object") { $path = $parent.path + "." + $parent.lastKey }
                else { $path = $parent.path + "[" + $parent.index + "]" }
                if ($path.StartsWith("top level.")) { $path = $path.Substring(10) }
            }
            $kind = if ($c -eq '{') { "object" } else { "array" }
            [void]$stack.Add(@{ kind = $kind; keys = @{}; expectKey = ($c -eq '{'); lastKey = ""; index = 0; path = $path })
        }
        elseif ($c -eq '}' -or $c -eq ']') { if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) } }
        elseif ($c -eq ',' -and $stack.Count -gt 0) {
            $top = $stack[$stack.Count - 1]
            if ($top.kind -eq "object") { $top.expectKey = $true } else { $top.index++ }
        }
        $i++
    }
    return @($out)
}
