# Mutations of files/Share.ps1: what may be shared, what a record holds, and the list. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-share.psd1
# Each lets through something that must be refused, or records or lists something wrongly;
# test\test-files-store.ps1 must fail for every one, except the one declared Expect = "survives".
# What the path, the text check and the key each do is in files-path, files-text, files-json and
# files-key, and what the fold of A to Z and the network question do is in path-text (core's);
# here are the lines of the share that call them.
@{
    Target = "files\Share.ps1"
    Suite  = "test\test-files-store.ps1"
    Mutations = @(
        # --- the type: the extension, and the first bytes ---
        @{ Name = "svg-is-just-another-unknown-type"
           Find = 'if ($extension -ceq ".svg") {'
           Replace = 'if ($false) {' }
        @{ Name = "extension-compared-with-its-case"
           Find = '$extension = ConvertTo-HordeAsciiLower -Text ([System.IO.Path]::GetExtension($Path))'
           Replace = '$extension = [System.IO.Path]::GetExtension($Path)' }
        # An extension is one of the list's only code unit for code unit, A to Z folded by the code's
        # own hand (review of 2026-10-13): not by the runtime's case table, and not by the table's comparer.
        @{ Name = "extension-lowered-by-the-runtimes-case-table-again"
           Find = '$extension = ConvertTo-HordeAsciiLower -Text ([System.IO.Path]::GetExtension($Path))'
           Replace = '$extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()' }
        @{ Name = "extension-looked-up-by-the-tables-own-comparer"
           Find = 'foreach ($listed in @($types.Keys)) { if ([string]::Equals($listed, $extension, [System.StringComparison]::Ordinal)) { $known = $types[$listed] } }'
           Replace = 'if ($types.Contains($extension)) { $known = $types[$extension] }' }
        @{ Name = "extension-compared-by-the-runtimes-own-comparison"
           Find = 'if ([string]::Equals($listed, $extension, [System.StringComparison]::Ordinal)) { $known = $types[$listed] }'
           Replace = 'if ($listed -ceq $extension) { $known = $types[$listed] }' }
        @{ Name = "type-not-on-the-list-allowed"
           Find = 'if ($null -eq $known) {'
           Replace = 'if ($false) {' }
        @{ Name = "first-bytes-never-checked"
           Find = 'return [bool]($hex -cmatch $Magic)'
           Replace = 'return $true' }
        @{ Name = "only-four-first-bytes-read"
           Find = '$count = [System.Math]::Min(12, $Bytes.Length)'
           Replace = '$count = [System.Math]::Min(4, $Bytes.Length)' }
        @{ Name = "png-known-by-half-its-signature"
           Find = 'magic = ''\A89504E470D0A1A0A'' }'
           Replace = 'magic = ''\A89504E47'' }' }
        @{ Name = "png-signature-found-anywhere"
           Find = 'magic = ''\A89504E470D0A1A0A'' }'
           Replace = 'magic = ''89504E470D0A1A0A'' }' }
        @{ Name = "jpg-has-no-signature"
           Find = '".jpg" = @{ type = "image/jpeg"; magic = ''\AFFD8FF'' }'
           Replace = '".jpg" = @{ type = "image/jpeg"; magic = "" }' }
        @{ Name = "jpeg-has-no-signature"
           Find = '".jpeg" = @{ type = "image/jpeg"; magic = ''\AFFD8FF'' }'
           Replace = '".jpeg" = @{ type = "image/jpeg"; magic = "" }' }
        @{ Name = "any-gif-version-allowed"
           Find = 'magic = ''\A47494638(37|39)61'' }'
           Replace = 'magic = ''\A47494638[0-9A-F]{2}61'' }' }
        @{ Name = "any-riff-file-is-webp"
           Find = 'magic = ''\A52494646[0-9A-F]{8}57454250'' }'
           Replace = 'magic = ''\A52494646'' }' }
        @{ Name = "pdf-has-no-signature"
           Find = 'magic = ''\A255044462D'' }'
           Replace = 'magic = "" }' }
        @{ Name = "wrong-first-bytes-shared"
           Find = 'if (-not (Test-HordeFilesMagic -Magic $kind.magic -Bytes $source.bytes)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "refused-type-shared"
           Find = 'if (-not $kind.ok) { return (& $refuse $kind.reason) }'
           Replace = '' }
        # --- a link is never followed ---
        @{ Name = "only-the-file-itself-is-asked"
           Find = '        $at = [System.IO.Path]::GetDirectoryName($at)'
           Replace = '        $at = $null' }
        @{ Name = "nothing-on-the-way-is-a-link"
           Find = 'if (Test-HordeFilesStoreLink -Path $at) { return $at }'
           Replace = '' }
        @{ Name = "link-shared"
           Find = 'if ($link -ne "") { return'
           Replace = 'if ($false) { return' }
        # --- one open handle: the link test, the type and the id are its path's ---
        @{ Name = "link-on-the-written-path-not-looked-for"
           Find = '        $link = Find-HordeFilesLink -Path $full'
           Replace = '        $link = ""' }
        @{ Name = "link-on-the-handles-own-path-not-looked-for"
           Find = 'if ($link -eq "") { $link = Find-HordeFilesLink -Path ("\\?\" + $real) }'
           Replace = ''
           Expect = "survives"
           Reason = "The handle's own path has every symbolic link and junction already taken out of it, so this second look can only find a reparse point that is NOT one of those - a sync folder's placeholder - on a folder the written path did not show, which needs an alias (a subst drive) over such a folder. No test here can make a placeholder. The first look, of the written path, is held by link-on-the-written-path-not-looked-for." }
        @{ Name = "type-taken-from-the-written-path"
           Find = '$kind = Get-HordeFilesType -Path $real'
           Replace = '$kind = Get-HordeFilesType -Path $full' }
        @{ Name = "id-made-from-the-written-path"
           Find = '-FullPath $real -Key $keyed.key'
           Replace = '-FullPath $full -Key $keyed.key' }
        # A network path is refused before anything asks the disk or the network about it: of the
        # path as written, before it is resolved, and of the path it resolves to, before it is looked at.
        @{ Name = "written-path-not-asked-whether-it-is-a-network-path"
           Find = '$unfit = Get-HordeFilesPlaceRefusal -Path $Path'
           Replace = '$unfit = ""' }
        @{ Name = "resolved-path-not-asked-whether-it-is-a-network-path"
           Find = '$network = Get-HordeFilesPlaceRefusal -Path $full'
           Replace = '$network = ""' }
        @{ Name = "resolved-network-path-found-and-looked-at-all-the-same"
           Find = 'if ($network -ne "") { return (& $refuse $network) }'
           Replace = '' }
        @{ Name = "device-and-stream-not-asked-about"
           Find = 'if ($unfit -eq "") { $unfit = Get-HordeFilesPathRefusal -Path $Path }'
           Replace = '' }
        @{ Name = "path-as-written-not-checked"
           Find = 'if ($unfit -ne "") { return (& $refuse $unfit) }'
           Replace = '' }
        # --- text is text ---
        @{ Name = "text-not-checked"
           Find = 'if ($kind.magic -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "text-problem-found-and-ignored"
           Find = 'if ($notText -ne "") { return (& $refuse $notText) }'
           Replace = '' }
        @{ Name = "json-file-held-to-plain-text-only"
           Find = '$notText = Get-HordeFilesTextProblem -Bytes $source.bytes -Type $kind.type'
           Replace = '$notText = Get-HordeFilesTextProblem -Bytes $source.bytes -Type "text/plain"' }
        # --- the key ---
        @{ Name = "share-goes-on-without-a-key"
           Find = 'if (-not $keyed.ok) { return (& $refuse $keyed.reason) }'
           Replace = '' }
        @{ Name = "key-of-the-ambient-home-whatever-home-is-given"
           Find = '$keyed = Get-HordeFilesKey -HordeHome $HordeHome -HeldTries'
           Replace = '$keyed = Get-HordeFilesKey -HordeHome "" -HeldTries' }
        @{ Name = "held-key-tried-once-whatever-the-setting"
           Find = '-HordeHome $HordeHome -HeldTries $settings.heldReadTries -HeldWaitMs $settings.heldReadWaitMs'
           Replace = '-HordeHome $HordeHome -HeldTries 1 -HeldWaitMs $settings.heldReadWaitMs' }
        @{ Name = "held-key-wait-is-not-the-setting"
           Find = '-HordeHome $HordeHome -HeldTries $settings.heldReadTries -HeldWaitMs $settings.heldReadWaitMs'
           Replace = '-HordeHome $HordeHome -HeldTries $settings.heldReadTries -HeldWaitMs 50' }
        @{ Name = "id-is-a-plain-digest-again"
           Find = '$mac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (, $Key)'
           Replace = '$mac = [System.Security.Cryptography.SHA256]::Create()' }
        @{ Name = "id-keyed-with-a-key-everyone-has"
           Find = '$mac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (, $Key)'
           Replace = '$mac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (, ([byte[]](1..32)))' }
        @{ Name = "id-in-capitals"
           Find = 'return ((ConvertTo-HordeAsciiLower -Text ([System.BitConverter]::ToString($mac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))).Replace("-", ""))).Substring(0, 32))'
           Replace = 'return (([System.BitConverter]::ToString($mac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))).Replace("-", "")).Substring(0, 32))' }
        # --- a file whose versions are used up ---
        @{ Name = "used-up-file-keeps-its-bytes-before-it-is-refused"
           Find = 'if ((Get-HordeFilesStoreLastVersion -Root $store -FileId $fileId) -ge $lastVersion) { return (& $refuse $usedUp) }'
           Replace = '' }
        @{ Name = "used-up-file-seen-one-version-late"
           Find = '-ge $lastVersion) { return (& $refuse $usedUp) }'
           Replace = '-gt $lastVersion) { return (& $refuse $usedUp) }' }
        @{ Name = "last-version-taken-meanwhile-throws"
           Find = 'if ($version -gt $lastVersion) { return (& $refuse $usedUp) }'
           Replace = '' }
        # --- the path ---
        @{ Name = "empty-path-not-named"
           Find = 'if ($Path.Trim() -eq "") { return (& $refuse "no file was named") }'
           Replace = '' }
        @{ Name = "folder-not-named-a-folder"
           Find = 'if ([System.IO.Directory]::Exists($full)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "missing-file-not-named-missing"
           Find = 'if (-not [System.IO.File]::Exists($full)) { return'
           Replace = 'if ($false) { return' }
        # --- the cap, and a file that cannot be read ---
        @{ Name = "cap-itself-refused"
           Find = 'if ($Stream.Length -gt $MaxBytes) {'
           Replace = 'if ($Stream.Length -ge $MaxBytes) {' }
        @{ Name = "no-cap"
           Find = 'if ($Stream.Length -gt $MaxBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "cap-is-not-the-setting"
           Find = '$source = Read-HordeFilesSource -Stream $opened.stream -MaxBytes $settings.maxFileBytes'
           Replace = '$source = Read-HordeFilesSource -Stream $opened.stream -MaxBytes 1048576' }
        @{ Name = "file-that-could-not-be-opened-shared"
           Find = 'if (-not $opened.ok) { return (& $refuse $opened.reason) }'
           Replace = 'if (-not $opened.ok) { return (& $refuse "") }' }
        @{ Name = "unread-file-shared"
           Find = 'if (-not $source.ok) { return (& $refuse $source.reason) }'
           Replace = '' }
        # --- the title ---
        @{ Name = "blank-title-allowed"
           Find = 'if ($name -eq "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "title-of-several-lines-allowed"
           Find = 'if ($unclear -ne "") { return (& $refuse $unclear) }'
           Replace = '' }
        @{ Name = "control-character-in-a-title-allowed"
           Find = 'if ($Title -cmatch ''\p{Cc}'') { return'
           Replace = 'if ($false) { return' }
        # What breaks a line without being a control character, and what turns text round (review of 2026-10-13).
        @{ Name = "line-and-paragraph-separators-in-a-title-allowed"
           Find = 'if ($Title -cmatch ''[\u2028\u2029]'') { return'
           Replace = 'if ($false) { return' }
        @{ Name = "line-separator-in-a-title-allowed"
           Find = '''[\u2028\u2029]'''
           Replace = '''[\u2029]''' }
        @{ Name = "paragraph-separator-in-a-title-allowed"
           Find = '''[\u2028\u2029]'''
           Replace = '''[\u2028]''' }
        @{ Name = "characters-that-turn-text-round-allowed"
           Find = 'if ($Title -cmatch ''[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]'') { return'
           Replace = 'if ($false) { return' }
        @{ Name = "arabic-letter-mark-allowed"
           Find = '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]'
           Replace = '[\u200E\u200F\u202A-\u202E\u2066-\u2069]' }
        @{ Name = "left-to-right-mark-allowed"
           Find = '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]'
           Replace = '[\u061C\u200F\u202A-\u202E\u2066-\u2069]' }
        @{ Name = "right-to-left-mark-allowed"
           Find = '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]'
           Replace = '[\u061C\u200E\u202A-\u202E\u2066-\u2069]' }
        @{ Name = "first-embedding-allowed"
           Find = '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]'
           Replace = '[\u061C\u200E\u200F\u202B-\u202E\u2066-\u2069]' }
        @{ Name = "right-to-left-override-allowed"
           Find = '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]'
           Replace = '[\u061C\u200E\u200F\u202A-\u202D\u2066-\u2069]' }
        @{ Name = "first-isolate-allowed"
           Find = '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]'
           Replace = '[\u061C\u200E\u200F\u202A-\u202E\u2067-\u2069]' }
        @{ Name = "last-isolate-allowed"
           Find = '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]'
           Replace = '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2068]' }
        @{ Name = "refusal-does-not-name-the-character"
           Find = '(U+" + ([int][char]$Matches[0]).ToString("X4") + ")'
           Replace = '(U+" + "" + ")' }
        # --- the runtime, the alias, and the look at the resolved path ---
        @{ Name = "runtime-not-asked"
           Find = 'if ($runtime -ne "") { return (& $refuse $runtime) }'
           Replace = '' }
        @{ Name = "device-and-stream-not-asked-of-the-resolved-path"
           Find = 'if ($network -eq "") { $network = Get-HordeFilesPathRefusal -Path $full }'
           Replace = '' }
        @{ Name = "longest-title-refused"
           Find = 'if ($name.Length -gt $settings.maxTitleChars) {'
           Replace = 'if ($name.Length -ge $settings.maxTitleChars) {' }
        @{ Name = "title-of-any-length"
           Find = 'if ($name.Length -gt $settings.maxTitleChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "title-kept-with-its-blanks"
           Find = '$name = $Title.Trim()'
           Replace = '$name = $Title' }
        # --- the sharing session ---
        @{ Name = "no-session-recorded-as-known"
           Find = 'if ($answer.state -ceq "known") { return [ordered]@{ known = $true; id = ("" + $answer.value) } }'
           Replace = 'return [ordered]@{ known = $true; id = ("" + $answer.value) }' }
        @{ Name = "session-never-known"
           Find = 'if ($answer.state -ceq "known") { return [ordered]@{ known = $true; id = ("" + $answer.value) } }'
           Replace = '' }
        @{ Name = "no-session-gives-no-reason"
           Find = 'reason = ("no session is known: " + $answer.reason) }'
           Replace = 'reason = "no session is known" }' }
        @{ Name = "session-given-is-ignored"
           Find = 'if ($null -eq $answer) { $answer = Get-HordeSelfSessionId }'
           Replace = '$answer = Get-HordeSelfSessionId' }
        # --- digests and the file id ---
        @{ Name = "digest-in-capitals"
           Find = '.Replace("-", "").ToLowerInvariant()) } finally { $sha.Dispose() }'
           Replace = '.Replace("-", "")) } finally { $sha.Dispose() }' }
        @{ Name = "digest-is-not-sha256"
           Find = '$sha = [System.Security.Cryptography.SHA256]::Create()'
           Replace = '$sha = [System.Security.Cryptography.SHA384]::Create()' }
        @{ Name = "path-case-makes-another-file"
           Find = '+ "`n" + (ConvertTo-HordeAsciiLower -Text $FullPath)'
           Replace = '+ "`n" + $FullPath' }
        @{ Name = "every-path-is-one-file"
           Find = '+ "`n" + (ConvertTo-HordeAsciiLower -Text $FullPath)'
           Replace = '' }
        # The path is folded by the code's own hand, A to Z and nothing else: an id is permanent, and
        # a runtime's case table is not. This is the defect the review found. The mutants of the fold
        # itself are core's: test\mutations\path-text.psd1.
        @{ Name = "path-folded-by-the-runtimes-case-table-again"
           Find = '+ "`n" + (ConvertTo-HordeAsciiLower -Text $FullPath)'
           Replace = '+ "`n" + $FullPath.ToLowerInvariant()' }
        @{ Name = "every-session-is-one-sharer"
           Find = 'if ($Session.known) { $who = "session:" + $Session.id }'
           Replace = 'if ($Session.known) { $who = "session:" }' }
        @{ Name = "session-named-like-no-session-is-no-session"
           Find = 'if ($Session.known) { $who = "session:" + $Session.id }'
           Replace = 'if ($Session.known) { $who = $Session.id }' }
        # --- what a share writes ---
        @{ Name = "bytes-not-kept"
           Find = '$kept = Add-HordeFilesStoreEntry -Root $store -Name $bytesName -Bytes $source.bytes -LeftoverMinAgeSeconds $settings.leftoverMinAgeSeconds'
           Replace = '$kept = "created"' }
        @{ Name = "unconfirmed-bytes-built-on"
           Find = 'if ($kept -ceq "unconfirmed") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "damaged-bytes-built-on"
           Find = 'if ($kept -ceq "exists" -and (New-Object System.IO.FileInfo((Join-Path $store $bytesName))).Length -ne $source.bytes.Length) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "store-folder-given-is-ignored"
           Find = 'if ($store -eq "") { $store = Get-HordeFilesStoreRoot -HordeHome $HordeHome }'
           Replace = '$store = Get-HordeFilesStoreRoot -HordeHome $HordeHome' }
        @{ Name = "first-version-is-two"
           Find = '$version = (Get-HordeFilesStoreLastVersion -Root $store -FileId $fileId) + 1'
           Replace = '$version = (Get-HordeFilesStoreLastVersion -Root $store -FileId $fileId) + 2' }
        @{ Name = "lost-version-not-tried-again"
           Find = 'for ($attempt = 1; $attempt -le $settings.versionTries; $attempt++) {'
           Replace = 'for ($attempt = 1; $attempt -le 1; $attempt++) {' }
        @{ Name = "taken-version-told-shared"
           Find = 'if ($made -ceq "created") { return'
           Replace = 'if ($true) { return' }
        @{ Name = "unconfirmed-record-tried-again-as-if-taken"
           Find = 'if ($made -ceq "unconfirmed") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "editable-never-recorded"
           Find = 'editable = [bool]$Editable }'
           Replace = 'editable = $false }' }
        @{ Name = "size-not-recorded"
           Find = 'size = $source.bytes.Length; sha256 = $digest'
           Replace = 'size = 0; sha256 = $digest' }
        @{ Name = "time-to-the-second"
           Find = '"yyyy-MM-ddTHH:mm:ss.fffZ"'
           Replace = '"yyyy-MM-ddTHH:mm:ssZ"' }
        @{ Name = "another-schema-version-written"
           Find = '$record = [ordered]@{ schemaVersion = 1;'
           Replace = '$record = [ordered]@{ schemaVersion = 2;' }
        @{ Name = "path-recorded"
           Find = 'session = $session; editable = [bool]$Editable }'
           Replace = 'session = $session; path = $full; editable = [bool]$Editable }' }
        # --- a record that was read is checked, field by field ---
        @{ Name = "schema-version-unchecked"; Find = '{ return "its schemaVersion is not 1" }'; Replace = '{ }' }
        @{ Name = "file-id-in-the-words-unchecked"; Find = '{ return "its fileId is not the one in its name" }'; Replace = '{ }' }
        @{ Name = "version-in-the-words-unchecked"; Find = '{ return "its version is not the one in its name" }'; Replace = '{ }' }
        @{ Name = "title-unchecked"; Find = '{ return "its title is not one line of text" }'; Replace = '{ }' }
        @{ Name = "title-with-a-control-character-read"
           Find = '-or $title.Trim() -eq "" -or (Get-HordeFilesTitleProblem -Title $title) -ne "") {'
           Replace = '-or $title.Trim() -eq "") {' }
        @{ Name = "type-unchecked"; Find = '{ return "its type is not one that is shared" }'; Replace = '{ }' }
        @{ Name = "size-unchecked"; Find = '{ return "its size is not a count of bytes" }'; Replace = '{ }' }
        @{ Name = "negative-size-read"
           Find = 'if (-not (& $whole "size") -or (& $value "size") -lt 0) {'
           Replace = 'if (-not (& $whole "size")) {' }
        @{ Name = "sha256-unchecked"; Find = '{ return "its sha256 is not 64 hex digits" }'; Replace = '{ }' }
        @{ Name = "sha256-in-capitals-read"
           Find = '(& $value "sha256") -cnotmatch ''\A[0-9a-f]{64}\z'')'
           Replace = '(& $value "sha256") -notmatch ''\A[0-9a-f]{64}\z'')' }
        @{ Name = "time-unchecked"; Find = '{ return "its time is not a UTC time to the millisecond" }'; Replace = '{ }' }
        @{ Name = "editable-unchecked"; Find = '{ return "its editable is not true or false" }'; Replace = '{ }' }
        @{ Name = "session-shape-unchecked"; Find = '{ return "it does not say which session shared it, or that none did" }'; Replace = '{ }' }
        @{ Name = "session-known-unchecked"; Find = '{ return "its session does not say whether it is known" }'; Replace = '{ }' }
        @{ Name = "session-id-or-reason-unchecked"; Find = '{ return ("its session has no " + $said) }'; Replace = '{ }' }
        @{ Name = "unknown-session-needs-an-id"
           Find = '$said = "reason"; if ($known.Value) { $said = "id" }'
           Replace = '$said = "id"' }
        # --- the list ---
        @{ Name = "record-not-checked-before-it-is-listed"
           Find = 'if ($entry.kind -ceq "ok") { $why = Get-HordeFilesRecordProblem -Entry $entry }'
           Replace = '' }
        @{ Name = "list-reads-the-home-whatever-folder-is-given"
           Find = 'if ($folder -eq "") { $folder = Get-HordeFilesStoreRoot -HordeHome $HordeHome }'
           Replace = '$folder = Get-HordeFilesStoreRoot -HordeHome $HordeHome' }
        @{ Name = "no-session-listed-as-nothing"
           Find = '$who = "no session"; if ($d.session.known) { $who = $d.session.id }'
           Replace = '$who = ""; if ($d.session.known) { $who = $d.session.id }' }
        @{ Name = "listed-in-the-order-of-their-names"
           Find = 'Sort-Object -Property time, fileId, version'
           Replace = 'Sort-Object -Property fileId, version' }
        @{ Name = "nothing-shared-prints-nothing"
           Find = 'if (@($List.rows).Count -eq 0) { [void]$lines.Add("no files have been shared") }'
           Replace = '' }
        @{ Name = "unreadable-list-printed-as-empty"
           Find = 'if ($List.state -ceq "unknown") {'
           Replace = 'if ($false) {' }
        @{ Name = "line-without-its-size"
           Find = '+ "  " + $row.size + " bytes  "'
           Replace = '+ "  "' }
        @{ Name = "unreadable-records-not-printed"
           Find = 'foreach ($bad in @($List.unreadable)) { [void]$lines.Add("unreadable record " + $bad.file + ": " + $bad.reason) }'
           Replace = '' }
        @{ Name = "strays-not-printed"
           Find = 'foreach ($stray in @($List.strays)) { [void]$lines.Add("not a record: " + $stray.file + ": " + $stray.reason) }'
           Replace = '' }
    )
}
