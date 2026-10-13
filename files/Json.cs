// files/Json.cs - is this exactly one JSON text? The grammar of RFC 8259, and nothing more lenient.
//
// WHY THIS IS WRITTEN OUT. A shared .json file is read on a phone by a strict parser, so "it parses"
// must mean what that parser means. Measured 2026-10-13 on Windows PowerShell 5.1, 80 boundary texts
// against the three parsers the platform has; none is strict, and two refuse valid JSON:
//   ConvertFrom-Json        accepts an empty text, NaN, 01, 1., {'a':1}, {a:1}, a raw tab in a string;
//                           REFUSES {"a":1,"A":2}, {"":1}, 1e400 and anything nested 200 deep.
//   JavaScriptSerializer    accepts the same wrong texts; REFUSES 1e400 and {"__type":"x","a":1}.
//   JsonReaderWriterFactory accepts an empty text, NaN, 01, 1., 0x10, [1,], {"a":1,} {}{}, 1 2,
//                           {"a":1 with no closing brace, {}} and NULL.
// It is a neighbour C# file, loaded once a process by files/Text.ps1 (relay/Gcm.cs is the same
// arrangement): in script, a text of small values costs seconds a megabyte.
//
// IT READS BYTES, the same buffer that is hashed and stored, from -offset (past a byte order mark).
// The caller has already required the bytes to be strict UTF-8, so only ASCII has meaning here and
// every byte of 0x80 or more is legal exactly where a character may stand: inside a string.
// IT DOES NOT RECURSE: open objects and arrays are a list, so a text nested a million deep is
// answered, not a stack overflow. It keeps no value: a number is never converted, so 1e400 and a
// number of thirty digits are JSON here as they are in the grammar.
//
// TWO THINGS THE GRAMMAR ALLOWS ARE REFUSED ALL THE SAME, since the review of 2026-10-13, because the
// readers this text is for do not take them:
//   - MORE THAN 512 OBJECTS AND ARRAYS OPEN AT ONCE (MaxDepth). The phone's parsers cap how deep
//     they go; a text one deeper than a reader goes is a text that reader cannot read.
//   - HALF OF A SURROGATE PAIR, WRITTEN ALONE AS AN ESCAPE. The escape of a first half (D800 to
//     DBFF) must be followed at once by the escape of a second half (DC00 to DFFF), and a second
//     half with no first before it is refused: alone, either is no character, and a strict reader
//     refuses the string.
//
// The name ends in V2 because a loaded type cannot be replaced in a process: a changed grammar is
// the next number. V1 was the grammar alone; V2 is the grammar with the two refusals above.
public static class HordeFilesJsonV2
{
    // The most objects and arrays that may be open at one place in the text.
    public const int MaxDepth = 512;

    // "" when bytes[offset..] is exactly one JSON text; otherwise why it is not, in words.
    public static string Problem(byte[] bytes, int offset)
    {
        int n = bytes.Length;
        int i = offset;
        // What may come next. 0 a value; 1 a value or ] (just after [); 2 a key or } (just after {);
        // 3 a key (after a comma in an object); 4 a colon; 5 a comma or the close; 6 nothing more.
        int state = 0;
        System.Collections.Generic.List<byte> open = new System.Collections.Generic.List<byte>();
        string why = "";
        while (true)
        {
            // The four characters JSON calls white space, and no others.
            while (i < n && (bytes[i] == 0x20 || bytes[i] == 0x09 || bytes[i] == 0x0A || bytes[i] == 0x0D)) { i++; }
            if (i >= n) { break; }
            byte c = bytes[i];
            if (state == 6) { return At(i, "there is more after the end of the value"); }
            if (state == 4)
            {
                if (c != (byte)':') { return At(i, "a colon was expected after the key"); }
                i++; state = 0; continue;
            }
            if (state == 5)
            {
                byte top = open[open.Count - 1];
                if (c == (byte)',') { i++; state = (top == (byte)'{') ? 3 : 0; continue; }
                if ((c == (byte)'}' && top == (byte)'{') || (c == (byte)']' && top == (byte)'[')) { i++; open.RemoveAt(open.Count - 1); state = (open.Count == 0) ? 6 : 5; continue; }
                return At(i, "a comma or the closing bracket was expected");
            }
            if (state == 2 || state == 3)
            {
                if (state == 2 && c == (byte)'}') { i++; open.RemoveAt(open.Count - 1); state = (open.Count == 0) ? 6 : 5; continue; }
                if (c != (byte)'"') { return At(i, "a key in double quotes was expected"); }
                i = Text(bytes, i, ref why);
                if (i < 0) { return why; }
                state = 4; continue;
            }
            // A value (state 0 or 1).
            if (state == 1 && c == (byte)']') { i++; open.RemoveAt(open.Count - 1); state = (open.Count == 0) ? 6 : 5; continue; }
            if ((c == (byte)'{' || c == (byte)'[') && open.Count >= MaxDepth) { return At(i, "it is nested more than " + MaxDepth + " deep, which is deeper than the readers of a shared file go"); }
            if (c == (byte)'{') { i++; open.Add(c); state = 2; continue; }
            if (c == (byte)'[') { i++; open.Add(c); state = 1; continue; }
            if (c == (byte)'"') { i = Text(bytes, i, ref why); }
            else if (c == (byte)'-' || (c >= (byte)'0' && c <= (byte)'9')) { i = Number(bytes, i, ref why); }
            else if (c == (byte)'t') { i = Word(bytes, i, "true", ref why); }
            else if (c == (byte)'f') { i = Word(bytes, i, "false", ref why); }
            else if (c == (byte)'n') { i = Word(bytes, i, "null", ref why); }
            else { return At(i, "a value was expected"); }
            if (i < 0) { return why; }
            state = (open.Count == 0) ? 6 : 5;
        }
        if (state == 0 && open.Count == 0) { return "it holds no value: it is empty, or only white space"; }
        if (state != 6) { return "it ends before its value is complete"; }
        return "";
    }

    private static string At(int i, string what) { return "at byte " + i + ", " + what; }

    // A string starting at the quote at i: the index after its closing quote, or -1 with why.
    private static int Text(byte[] b, int i, ref string why)
    {
        int n = b.Length;
        int j = i + 1;
        while (true)
        {
            if (j >= n) { why = At(i, "a string is never closed"); return -1; }
            byte c = b[j];
            if (c == (byte)'"') { return j + 1; }
            if (c < 0x20) { why = At(j, "a control character stands inside a string, where it must be written as an escape"); return -1; }
            if (c != (byte)'\\') { j++; continue; }
            j++;
            if (j >= n) { why = At(i, "a string ends in the middle of an escape"); return -1; }
            byte e = b[j];
            if (e == (byte)'"' || e == (byte)'\\' || e == (byte)'/' || e == (byte)'b' || e == (byte)'f' || e == (byte)'n' || e == (byte)'r' || e == (byte)'t') { j++; continue; }
            if (e != (byte)'u') { why = At(j - 1, "an escape that JSON does not have"); return -1; }
            int unit = Unit(b, j);
            if (unit < 0) { why = At(j - 1, "a \\u escape without its four hex digits"); return -1; }
            if (unit >= 0xDC00 && unit <= 0xDFFF) { why = At(j - 1, "a \\u escape of the second half of a surrogate pair, with no first half before it"); return -1; }
            j += 5;
            if (unit >= 0xD800 && unit <= 0xDBFF)
            {
                // The second half must stand right here, and as an escape too.
                int next = (j + 1 < n && b[j] == (byte)'\\' && b[j + 1] == (byte)'u') ? Unit(b, j + 1) : -1;
                if (next < 0xDC00 || next > 0xDFFF) { why = At(j - 6, "a \\u escape of the first half of a surrogate pair, not followed by its second half"); return -1; }
                j += 6;
            }
        }
    }

    // The number the four hex digits after the u at j write, or -1 when they are not four hex digits.
    private static int Unit(byte[] b, int j)
    {
        int unit = 0;
        for (int k = 1; k <= 4; k++)
        {
            if (j + k >= b.Length || !Hex(b[j + k])) { return -1; }
            byte h = b[j + k];
            unit = unit * 16 + ((h <= (byte)'9') ? h - (byte)'0' : (h | 0x20) - (byte)'a' + 10);
        }
        return unit;
    }

    private static bool Hex(byte c) { return (c >= (byte)'0' && c <= (byte)'9') || (c >= (byte)'a' && c <= (byte)'f') || (c >= (byte)'A' && c <= (byte)'F'); }

    private static bool Digit(byte[] b, int j) { return j < b.Length && b[j] >= (byte)'0' && b[j] <= (byte)'9'; }

    // A number starting at i: the index after it, or -1 with why. What follows it is the caller's to
    // judge, so 01 is the number 0 with more after it, and that is refused there.
    private static int Number(byte[] b, int i, ref string why)
    {
        int j = i;
        if (b[j] == (byte)'-') { j++; }
        if (!Digit(b, j)) { why = At(i, "a minus sign with no digit after it"); return -1; }
        if (b[j] == (byte)'0') { j++; } else { while (Digit(b, j)) { j++; } }
        if (j < b.Length && b[j] == (byte)'.')
        {
            j++;
            if (!Digit(b, j)) { why = At(i, "a number with a point and no digit after it"); return -1; }
            while (Digit(b, j)) { j++; }
        }
        if (j < b.Length && (b[j] == (byte)'e' || b[j] == (byte)'E'))
        {
            j++;
            if (j < b.Length && (b[j] == (byte)'+' || b[j] == (byte)'-')) { j++; }
            if (!Digit(b, j)) { why = At(i, "a number with an exponent and no digit in it"); return -1; }
            while (Digit(b, j)) { j++; }
        }
        return j;
    }

    // One of true, false, null, exactly as written: the index after it, or -1 with why.
    private static int Word(byte[] b, int i, string word, ref string why)
    {
        for (int k = 0; k < word.Length; k++)
        {
            if (i + k >= b.Length || b[i + k] != (byte)word[k]) { why = At(i, "a value was expected (only true, false and null are written without quotes)"); return -1; }
        }
        return i + word.Length;
    }
}
