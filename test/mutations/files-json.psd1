# Mutations of files/Json.cs: is this exactly one JSON text. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-json.psd1
# Each makes the grammar take a text that is not JSON - most of them a leniency one of the platform's
# own parsers has - or refuse one that is; test\test-files-store.ps1, which compiles the file it finds
# beside files\Text.ps1, must fail for every one.
@{
    Target = "files\Json.cs"
    Suite  = "test\test-files-store.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- the whole text ---
        @{ Name = "more-after-the-value-allowed"
           Find = 'if (state == 6) { return At(i, "there is more after the end of the value"); }'
           Replace = 'if (state == 6) { return ""; }' }
        @{ Name = "empty-text-not-said-to-be-empty"
           Find = 'if (state == 0 && open.Count == 0) { return "it holds no value: it is empty, or only white space"; }'
           Replace = '' }
        @{ Name = "text-cut-short-allowed"
           Find = 'if (state != 6) { return "it ends before its value is complete"; }'
           Replace = '' }
        @{ Name = "any-control-character-is-white-space"
           Find = '(bytes[i] == 0x20 || bytes[i] == 0x09 || bytes[i] == 0x0A || bytes[i] == 0x0D)'
           Replace = '(bytes[i] <= 0x20)' }
        @{ Name = "a-tab-is-not-white-space"
           Find = '(bytes[i] == 0x20 || bytes[i] == 0x09 || bytes[i] == 0x0A || bytes[i] == 0x0D)'
           Replace = '(bytes[i] == 0x20 || bytes[i] == 0x0A || bytes[i] == 0x0D)' }
        # --- objects and arrays ---
        @{ Name = "anything-stands-for-the-colon"
           Find = 'if (c != (byte)'':'') { return At(i, "a colon was expected after the key"); }'
           Replace = '' }
        @{ Name = "comma-before-the-closing-brace-allowed"
           Find = 'state = (top == (byte)''{'') ? 3 : 0; continue; }'
           Replace = 'state = (top == (byte)''{'') ? 2 : 0; continue; }' }
        @{ Name = "comma-before-the-closing-bracket-allowed"
           Find = 'state = (top == (byte)''{'') ? 3 : 0; continue; }'
           Replace = 'state = (top == (byte)''{'') ? 3 : 1; continue; }' }
        @{ Name = "either-bracket-closes-either"
           Find = 'if ((c == (byte)''}'' && top == (byte)''{'') || (c == (byte)'']'' && top == (byte)''[''))'
           Replace = 'if (c == (byte)''}'' || c == (byte)'']'')' }
        @{ Name = "nothing-needed-between-two-values"
           Find = 'return At(i, "a comma or the closing bracket was expected");'
           Replace = 'state = 0; continue;' }
        @{ Name = "key-needs-no-opening-quote"
           Find = 'if (c != (byte)''"'') { return At(i, "a key in double quotes was expected"); }'
           Replace = '' }
        @{ Name = "empty-object-refused"
           Find = 'if (state == 2 && c == (byte)''}'')'
           Replace = 'if (false && c == (byte)''}'')' }
        @{ Name = "empty-array-refused"
           Find = 'if (state == 1 && c == (byte)'']'')'
           Replace = 'if (false && c == (byte)'']'')' }
        @{ Name = "unknown-value-skipped"
           Find = 'else { return At(i, "a value was expected"); }'
           Replace = 'else { i++; }' }
        # --- strings ---
        @{ Name = "string-never-closed-allowed"
           Find = 'if (j >= n) { why = At(i, "a string is never closed"); return -1; }'
           Replace = 'if (j >= n) { return j; }' }
        @{ Name = "string-ending-inside-an-escape-allowed"
           Find = 'if (j >= n) { why = At(i, "a string ends in the middle of an escape"); return -1; }'
           Replace = 'if (j >= n) { return j; }' }
        @{ Name = "control-character-allowed-inside-a-string"
           Find = 'if (c < 0x20) { why = At(j,'
           Replace = 'if (false) { why = At(j,' }
        @{ Name = "delete-character-refused-inside-a-string"
           Find = 'if (c < 0x20) { why = At(j,'
           Replace = 'if (c < 0x20 || c == 0x7F) { why = At(j,' }
        @{ Name = "any-escape-allowed"
           Find = 'if (e != (byte)''u'') { why = At(j - 1, "an escape that JSON does not have"); return -1; }'
           Replace = 'if (e != (byte)''u'') { j++; continue; }' }
        @{ Name = "slash-escape-refused"
           Find = 'e == (byte)''\\'' || e == (byte)''/'' || e == (byte)''b'''
           Replace = 'e == (byte)''\\'' || e == (byte)''b''' }
        @{ Name = "unicode-escape-needs-no-hex-digits"
           Find = 'if (j + k >= b.Length || !Hex(b[j + k])) { return -1; }'
           Replace = 'if (j + k >= b.Length) { return -1; }' }
        @{ Name = "unicode-escape-of-two-digits"
           Find = 'for (int k = 1; k <= 4; k++)'
           Replace = 'for (int k = 1; k <= 2; k++)' }
        @{ Name = "capital-hex-digits-refused"
           Find = ' || (c >= (byte)''A'' && c <= (byte)''F'');'
           Replace = ';' }
        # --- numbers and words ---
        @{ Name = "leading-zero-allowed"
           Find = 'if (b[j] == (byte)''0'') { j++; } else { while (Digit(b, j)) { j++; } }'
           Replace = 'while (Digit(b, j)) { j++; }' }
        @{ Name = "minus-needs-no-digit"
           Find = 'if (!Digit(b, j)) { why = At(i, "a minus sign with no digit after it"); return -1; }'
           Replace = '' }
        @{ Name = "point-needs-no-digit-after-it"
           Find = 'if (!Digit(b, j)) { why = At(i, "a number with a point and no digit after it"); return -1; }'
           Replace = '' }
        @{ Name = "exponent-needs-no-digit"
           Find = 'if (!Digit(b, j)) { why = At(i, "a number with an exponent and no digit in it"); return -1; }'
           Replace = '' }
        @{ Name = "exponent-may-not-be-signed"
           Find = 'if (j < b.Length && (b[j] == (byte)''+'' || b[j] == (byte)''-'')) { j++; }'
           Replace = '' }
        @{ Name = "capital-exponent-refused"
           Find = 'if (j < b.Length && (b[j] == (byte)''e'' || b[j] == (byte)''E''))'
           Replace = 'if (j < b.Length && (b[j] == (byte)''e''))' }
        @{ Name = "word-known-by-its-first-letter"
           Find = 'for (int k = 0; k < word.Length; k++)'
           Replace = 'for (int k = 0; k < 1; k++)' }
        # --- deeper than a reader goes: 512 open at once is the most (review of 2026-10-13) ---
        @{ Name = "depth-not-capped"
           Find = 'if ((c == (byte)''{'' || c == (byte)''['') && open.Count >= MaxDepth) { return'
           Replace = 'if (open.Count < 0) { return' }
        @{ Name = "cap-is-one-more"
           Find = 'public const int MaxDepth = 512;'
           Replace = 'public const int MaxDepth = 513;' }
        @{ Name = "cap-is-one-less"
           Find = '&& open.Count >= MaxDepth) { return'
           Replace = '&& open.Count >= MaxDepth - 1) { return' }
        @{ Name = "only-arrays-counted-against-the-cap"
           Find = 'if ((c == (byte)''{'' || c == (byte)''['') && open.Count >= MaxDepth) { return'
           Replace = 'if ((c == (byte)''['') && open.Count >= MaxDepth) { return' }
        @{ Name = "only-objects-counted-against-the-cap"
           Find = 'if ((c == (byte)''{'' || c == (byte)''['') && open.Count >= MaxDepth) { return'
           Replace = 'if ((c == (byte)''{'') && open.Count >= MaxDepth) { return' }
        # --- half of a surrogate pair, alone ---
        @{ Name = "lone-second-half-allowed"
           Find = 'if (unit >= 0xDC00 && unit <= 0xDFFF) { why'
           Replace = 'if (unit < 0) { why' }
        @{ Name = "first-second-half-not-one"
           Find = 'if (unit >= 0xDC00 && unit <= 0xDFFF) { why'
           Replace = 'if (unit > 0xDC00 && unit <= 0xDFFF) { why' }
        @{ Name = "last-second-half-not-one"
           Find = 'if (unit >= 0xDC00 && unit <= 0xDFFF) { why'
           Replace = 'if (unit >= 0xDC00 && unit < 0xDFFF) { why' }
        @{ Name = "lone-first-half-allowed"
           Find = 'if (next < 0xDC00 || next > 0xDFFF) { why'
           Replace = 'if (next < -1) { why' }
        @{ Name = "first-first-half-not-one"
           Find = 'if (unit >= 0xD800 && unit <= 0xDBFF)'
           Replace = 'if (unit > 0xD800 && unit <= 0xDBFF)' }
        @{ Name = "last-first-half-not-one"
           Find = 'if (unit >= 0xD800 && unit <= 0xDBFF)'
           Replace = 'if (unit >= 0xD800 && unit < 0xDBFF)' }
        @{ Name = "first-second-half-not-taken-after-a-first-half"
           Find = 'if (next < 0xDC00 || next > 0xDFFF) { why'
           Replace = 'if (next < 0xDC01 || next > 0xDFFF) { why' }
        @{ Name = "last-second-half-not-taken-after-a-first-half"
           Find = 'if (next < 0xDC00 || next > 0xDFFF) { why'
           Replace = 'if (next < 0xDC00 || next > 0xDFFE) { why' }
        @{ Name = "anything-past-the-first-halves-taken-as-a-second-half"
           Find = 'if (next < 0xDC00 || next > 0xDFFF) { why'
           Replace = 'if (next < 0xDC00) { why' }
        @{ Name = "anything-up-to-the-second-halves-taken-as-one"
           Find = 'if (next < 0xDC00 || next > 0xDFFF) { why'
           Replace = 'if (next < 0 || next > 0xDFFF) { why' }
        @{ Name = "second-half-need-not-start-with-a-backslash"
           Find = '(j + 1 < n && b[j] == (byte)''\\'' && b[j + 1] == (byte)''u'')'
           Replace = '(j + 1 < n && b[j + 1] == (byte)''u'')' }
        @{ Name = "second-half-may-be-any-escape"
           Find = '(j + 1 < n && b[j] == (byte)''\\'' && b[j + 1] == (byte)''u'')'
           Replace = '(j + 1 < n && b[j] == (byte)''\\'')' }
        @{ Name = "capital-hex-digits-given-another-value"
           Find = '(h | 0x20) - (byte)''a'' + 10'
           Replace = 'h - (byte)''a'' + 10' }
        @{ Name = "null-is-no-value"
           Find = 'else if (c == (byte)''n'') { i = Word(bytes, i, "null", ref why); }'
           Replace = '' }
    )
}
