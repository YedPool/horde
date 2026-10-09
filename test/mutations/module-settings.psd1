# Mutations of core/ModuleSettings.ps1, where a module's settings live. Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\module-settings.psd1
# Each breaks one rule of the declaration, of the pure reading of a file's text, or of the reading of the
# file; test\test-module-settings.ps1 must fail a check for every one of them. A reading that throws is
# turned into a failed check by the suite's own helpers, because "never a throw" is a rule here and
# tools\Mutate.ps1 counts a crashed suite as nothing caught. THE RULE MOST OF THE LATER ONES ATTACK: a
# file that fails a check is refused whole - state "refused", no values, every problem named with the
# file - and never falls back to a default.
#
# NOT HERE, because nothing could tell them apart from the code as it is: the order of the checks of a
# text (length, pieces, duplicates, parser, schema) where two of them refuse the same text in different
# words - each check's own mutant is here instead - and the branch of the absolute-path test for a
# system whose separator is not a backslash, which no suite on Windows reaches (the header of the
# target says only Windows is tested). And one that was here while a bad value was reported and its
# default used, "wrong-value-used" (the value put among the values although its check failed): a failed
# check now refuses and a refusal hands back no values, so where that value would have gone nobody can
# look. What stands in its place is refusal-hands-back-values and findings-do-not-refuse.
@{
    Target = "core\ModuleSettings.ps1"
    Suite  = "test\test-module-settings.ps1"
    Mutations = @(
        @{ Name = "folder-rooted-counts-as-absolute"
           Find = '{ return [bool]($Path -cmatch ''\A(?:[A-Za-z]:[\\/]|[\\/]{2}[^\\/])'') }'
           Replace = '{ return $true }' }
        @{ Name = "folder-on-a-share-refused"
           Find = '|[\\/]{2}[^\\/])'') }'
           Replace = ')'') }' }
        @{ Name = "folder-drive-without-slash-allowed"
           Find = '(?:[A-Za-z]:[\\/]|'
           Replace = '(?:[A-Za-z]:|' }
        @{ Name = "folder-bad-character-throws"
           Find = 'catch { return $false }'
           Replace = 'catch { throw }' }
        @{ Name = "whole-accepts-any-number"
           Find = 'if ($Value -isnot [int] -and $Value -isnot [long]) { return $no }'
           Replace = 'if (-not (Test-HordeSchemaIsNumber $Value)) { return $no }' }
        @{ Name = "whole-accepts-text"
           Find = 'if ($Value -isnot [int] -and $Value -isnot [long]) { return $no }'
           Replace = 'if ($Value -is [bool] -or $null -eq $Value -or $Value -is [System.Collections.IList] -or $Value -is [System.Management.Automation.PSCustomObject]) { return $no }' }
        # PowerShell 7's ConvertFrom-Json reads every whole number as an Int64: refusing one refuses
        # every whole number a file gives there, and handing one on gives the module a type it was not
        # promised (an Int32).
        @{ Name = "whole-refuses-int64"
           Find = 'if ($Value -isnot [int] -and $Value -isnot [long]) { return $no }'
           Replace = 'if ($Value -isnot [int]) { return $no }' }
        @{ Name = "whole-int64-handed-on-as-it-is"
           Find = 'return [pscustomobject]@{ ok = $true; value = [int]$Value }'
           Replace = 'return [pscustomobject]@{ ok = $true; value = $Value }' }
        @{ Name = "whole-below-smallest-allowed"
           Find = 'if ($Value -lt $Entry.min -or $Value -gt $Entry.max) { return $no }'
           Replace = 'if ($Value -gt $Entry.max) { return $no }' }
        @{ Name = "whole-above-largest-allowed"
           Find = 'if ($Value -lt $Entry.min -or $Value -gt $Entry.max) { return $no }'
           Replace = 'if ($Value -lt $Entry.min) { return $no }' }
        @{ Name = "whole-smallest-excluded"
           Find = 'if ($Value -lt $Entry.min -or $Value -gt $Entry.max) { return $no }'
           Replace = 'if ($Value -le $Entry.min -or $Value -gt $Entry.max) { return $no }' }
        @{ Name = "whole-largest-excluded"
           Find = 'if ($Value -lt $Entry.min -or $Value -gt $Entry.max) { return $no }'
           Replace = 'if ($Value -lt $Entry.min -or $Value -ge $Entry.max) { return $no }' }
        @{ Name = "fraction-accepts-text"
           Find = 'if (-not ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [double])) { return $no }'
           Replace = 'if ($Value -is [bool] -or $null -eq $Value -or $Value -is [System.Collections.IList]) { return $no }' }
        @{ Name = "fraction-refuses-whole-numbers"
           Find = 'if (-not ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [double])) { return $no }'
           Replace = 'if (-not ($Value -is [long] -or $Value -is [decimal] -or $Value -is [double])) { return $no }' }
        @{ Name = "fraction-refuses-int64"
           Find = 'if (-not ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [double])) { return $no }'
           Replace = 'if (-not ($Value -is [int] -or $Value -is [decimal] -or $Value -is [double])) { return $no }' }
        @{ Name = "fraction-refuses-decimals"
           Find = 'if (-not ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [double])) { return $no }'
           Replace = 'if (-not ($Value -is [int] -or $Value -is [long] -or $Value -is [double])) { return $no }' }
        @{ Name = "fraction-refuses-doubles"
           Find = 'if (-not ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [double])) { return $no }'
           Replace = 'if (-not ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal])) { return $no }' }
        @{ Name = "fraction-not-a-number-allowed"
           Find = 'if ([double]::IsNaN($asDouble)) { return $no }'
           Replace = '' }
        @{ Name = "fraction-below-smallest-allowed"
           Find = 'if ($asDouble -lt $Entry.min -or $asDouble -gt $Entry.max) { return $no }'
           Replace = 'if ($asDouble -gt $Entry.max) { return $no }' }
        @{ Name = "fraction-above-largest-allowed"
           Find = 'if ($asDouble -lt $Entry.min -or $asDouble -gt $Entry.max) { return $no }'
           Replace = 'if ($asDouble -lt $Entry.min) { return $no }' }
        @{ Name = "fraction-smallest-excluded"
           Find = 'if ($asDouble -lt $Entry.min -or $asDouble -gt $Entry.max) { return $no }'
           Replace = 'if ($asDouble -le $Entry.min -or $asDouble -gt $Entry.max) { return $no }' }
        @{ Name = "fraction-largest-excluded"
           Find = 'if ($asDouble -lt $Entry.min -or $asDouble -gt $Entry.max) { return $no }'
           Replace = 'if ($asDouble -lt $Entry.min -or $asDouble -ge $Entry.max) { return $no }' }
        @{ Name = "fraction-handed-over-unconverted"
           Find = 'return [pscustomobject]@{ ok = $true; value = $asDouble }'
           Replace = 'return [pscustomobject]@{ ok = $true; value = $Value }' }
        @{ Name = "truefalse-accepts-anything"
           Find = 'if ($Value -isnot [bool]) { return $no }'
           Replace = '' }
        @{ Name = "text-control-character-allowed"
           Find = 'if ($Value -isnot [string] -or $Value -cmatch ''\p{Cc}'') { return $no }'
           Replace = 'if ($Value -isnot [string]) { return $no }' }
        @{ Name = "text-accepts-what-is-not-text"
           Find = 'if ($Value -isnot [string] -or $Value -cmatch ''\p{Cc}'') { return $no }'
           Replace = 'if ($Value -is [string] -and $Value -cmatch ''\p{Cc}'') { return $no }' }
        @{ Name = "folder-any-length"
           Find = '$Value.Length -gt $script:HordeModuleSettingFolderCap -or '
           Replace = '' }
        @{ Name = "folder-relative-allowed"
           Find = ' -or -not (Test-HordeModuleSettingFolder -Path $Value)) { return $no }'
           Replace = ') { return $no }' }
        @{ Name = "closed-list-ignores-case"
           Find = 'if (@($Entry.values) -cnotcontains $Value) { return $no }'
           Replace = 'if (@($Entry.values) -notcontains $Value) { return $no }' }
        @{ Name = "closed-list-is-open"
           Find = 'if (@($Entry.values) -cnotcontains $Value) { return $no }'
           Replace = '' }
        @{ Name = "text-shorter-than-smallest-allowed"
           Find = 'elseif ($Value.Length -lt $Entry.min -or $Value.Length -gt $Entry.max) { return $no }'
           Replace = 'elseif ($Value.Length -gt $Entry.max) { return $no }' }
        @{ Name = "text-longer-than-largest-allowed"
           Find = 'elseif ($Value.Length -lt $Entry.min -or $Value.Length -gt $Entry.max) { return $no }'
           Replace = 'elseif ($Value.Length -lt $Entry.min) { return $no }' }
        @{ Name = "text-smallest-length-excluded"
           Find = 'elseif ($Value.Length -lt $Entry.min -or $Value.Length -gt $Entry.max) { return $no }'
           Replace = 'elseif ($Value.Length -le $Entry.min -or $Value.Length -gt $Entry.max) { return $no }' }
        @{ Name = "text-largest-length-excluded"
           Find = 'elseif ($Value.Length -lt $Entry.min -or $Value.Length -gt $Entry.max) { return $no }'
           Replace = 'elseif ($Value.Length -lt $Entry.min -or $Value.Length -ge $Entry.max) { return $no }' }
        @{ Name = "double-written-by-the-machine-culture"
           Find = 'return $Number.ToString("R", $invariant)'
           Replace = 'return $Number.ToString()' }
        @{ Name = "number-written-by-the-machine-culture"
           Find = 'return $Number.ToString($invariant)'
           Replace = 'return $Number.ToString()' }
        @{ Name = "given-text-is-quoted"
           Find = 'return ("text of " + $Value.Length + " characters")'
           Replace = 'return ("the text " + $Value)' }
        @{ Name = "given-control-character-not-said"
           Find = 'if ($Value -cmatch ''\p{Cc}'') { return "text holding a control character" }'
           Replace = '' }
        @{ Name = "given-null-not-said"
           Find = 'if ($null -eq $Value) { return "null" }'
           Replace = '' }
        @{ Name = "given-list-not-said"
           Find = 'if ($Value -is [System.Collections.IList]) { return "a list" }'
           Replace = '' }
        @{ Name = "given-true-false-not-said"
           Find = 'if ($Value -is [bool]) { if ($Value) { return "true" }; return "false" }'
           Replace = '' }
        @{ Name = "given-whole-number-not-told-apart"
           Find = 'if ($Value -is [int] -or $Value -is [long]) {'
           Replace = 'if ($false) {' }
        @{ Name = "given-int64-not-a-whole-number"
           Find = 'if ($Value -is [int] -or $Value -is [long]) {'
           Replace = 'if ($Value -is [int]) {' }
        @{ Name = "module-name-unchecked"
           Find = 'if ($Module -cnotmatch $script:HordeModuleNamePattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "module-name-any-length"
           Find = '$script:HordeModuleNamePattern = ''\A[a-z][a-z0-9-]{0,39}\z'''
           Replace = '$script:HordeModuleNamePattern = ''\A[a-z][a-z0-9-]*\z''' }
        @{ Name = "module-device-name-allowed"
           Find = 'if ($Module -cmatch $script:HordeModuleDeviceNamePattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "module-device-name-by-prefix"
           Find = '$script:HordeModuleDeviceNamePattern = ''\A(con|prn|aux|nul|com[0-9]|lpt[0-9])\z'''
           Replace = '$script:HordeModuleDeviceNamePattern = ''\A(con|prn|aux|nul|com[0-9]|lpt[0-9])''' }
        @{ Name = "empty-table-allowed"
           Find = 'if (@($Settings).Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "entry-that-is-no-table-read"
           Find = 'if ($raw -isnot [System.Collections.IDictionary]) {'
           Replace = 'if ($false) {' }
        @{ Name = "setting-name-unchecked"
           Find = 'if ($name -isnot [string] -or $name -cnotmatch $script:HordeModuleSettingNamePattern) {'
           Replace = 'if ($name -isnot [string]) {' }
        @{ Name = "setting-name-any-length"
           Find = '$script:HordeModuleSettingNamePattern = ''\A[a-z][a-zA-Z0-9]{0,39}\z'''
           Replace = '$script:HordeModuleSettingNamePattern = ''\A[a-z][a-zA-Z0-9]*\z''' }
        @{ Name = "setting-names-differ-by-case"
           Find = '$seen = New-Object ''System.Collections.Generic.HashSet[string]'' ([System.StringComparer]::OrdinalIgnoreCase)'
           Replace = '$seen = New-Object ''System.Collections.Generic.HashSet[string]'' ([System.StringComparer]::Ordinal)' }
        @{ Name = "unknown-field-ignored"
           Find = 'if ($script:HordeModuleSettingFields -cnotcontains $field) {'
           Replace = 'if ($false) {' }
        @{ Name = "field-names-ignore-case"
           Find = 'if ($script:HordeModuleSettingFields -cnotcontains $field) {'
           Replace = 'if ($script:HordeModuleSettingFields -notcontains $field) {' }
        @{ Name = "kind-unchecked"
           Find = ' -or $script:HordeModuleSettingKinds -cnotcontains $kind) {'
           Replace = ') {' }
        @{ Name = "what-it-is-unchecked"
           Find = 'if ($what -isnot [string] -or $what -cnotmatch $script:HordeModuleSettingWhatPattern -or $what.Trim() -ceq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "what-it-is-may-be-blank"
           Find = 'if ($what -isnot [string] -or $what -cnotmatch $script:HordeModuleSettingWhatPattern -or $what.Trim() -ceq "") {'
           Replace = 'if ($what -isnot [string] -or $what -cnotmatch $script:HordeModuleSettingWhatPattern) {' }
        @{ Name = "what-it-is-any-length"
           Find = '$script:HordeModuleSettingWhatPattern = ''\A[\x20-\x7E]{1,200}\z'''
           Replace = '$script:HordeModuleSettingWhatPattern = ''\A[\x20-\x7E]+\z''' }
        @{ Name = "what-it-is-any-character"
           Find = '$script:HordeModuleSettingWhatPattern = ''\A[\x20-\x7E]{1,200}\z'''
           Replace = '$script:HordeModuleSettingWhatPattern = ''\A.{1,200}\z''' }
        @{ Name = "text-length-and-list-together"
           Find = 'if ($kind -ceq "text" -and $hasValues -and ($hasMin -or $hasMax)) {'
           Replace = 'if ($false) {' }
        @{ Name = "text-with-no-range"
           Find = 'elseif ($kind -ceq "text" -and -not ($hasValues -or $hasMin -or $hasMax)) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "fraction-bound-not-a-number"
           Find = ' -or [double]::IsNaN([double]$bound)) {'
           Replace = ') {' }
        @{ Name = "fraction-bound-as-text"
           Find = '$isNumber = ($bound -is [int] -or $bound -is [double] -or $bound -is [decimal])'
           Replace = '$isNumber = ($bound -isnot [bool] -and $null -ne $bound)' }
        @{ Name = "fraction-bound-outside-the-unit"
           Find = 'elseif ([double]$bound -lt 0 -or [double]$bound -gt 1) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "fraction-bound-below-zero"
           Find = 'elseif ([double]$bound -lt 0 -or [double]$bound -gt 1) {'
           Replace = 'elseif ([double]$bound -gt 1) {' }
        @{ Name = "fraction-bound-above-one"
           Find = 'elseif ([double]$bound -lt 0 -or [double]$bound -gt 1) {'
           Replace = 'elseif ([double]$bound -lt 0) {' }
        @{ Name = "bound-written-as-a-fraction"
           Find = 'elseif (-not $given -or $bound -isnot [int]) {'
           Replace = 'elseif (-not $given -or -not (Test-HordeSchemaIsNumber $bound)) {' }
        @{ Name = "text-length-unbounded"
           Find = 'elseif ($kind -ceq "text" -and ($bound -lt 0 -or $bound -gt $script:HordeModuleSettingTextCap)) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "text-length-below-zero"
           Find = 'elseif ($kind -ceq "text" -and ($bound -lt 0 -or $bound -gt $script:HordeModuleSettingTextCap)) {'
           Replace = 'elseif ($kind -ceq "text" -and ($bound -gt $script:HordeModuleSettingTextCap)) {' }
        @{ Name = "text-length-above-the-cap"
           Find = 'elseif ($kind -ceq "text" -and ($bound -lt 0 -or $bound -gt $script:HordeModuleSettingTextCap)) {'
           Replace = 'elseif ($kind -ceq "text" -and ($bound -lt 0)) {' }
        @{ Name = "text-cap-one-less"
           Find = '$script:HordeModuleSettingTextCap = 4096'
           Replace = '$script:HordeModuleSettingTextCap = 4095' }
        @{ Name = "folder-cap-one-less"
           Find = '$script:HordeModuleSettingFolderCap = 1024'
           Replace = '$script:HordeModuleSettingFolderCap = 1023' }
        @{ Name = "smallest-above-largest"
           Find = 'if ($problems.Count -eq $before -and $min -gt $max) {'
           Replace = 'if ($false) {' }
        @{ Name = "fraction-bounds-kept-as-written"
           Find = '{ $min = [double]$min; $max = [double]$max }'
           Replace = '{ }' }
        @{ Name = "range-on-a-kind-without-one"
           Find = 'if ($fields.ContainsKey($end)) {'
           Replace = 'if ($false) {' }
        @{ Name = "closed-list-on-another-kind"
           Find = 'if ($hasValues -and $kind -cne "text") {'
           Replace = 'if ($false) {' }
        @{ Name = "closed-list-shape-unchecked"
           Find = '$bad = ($values -isnot [System.Collections.IList] -or @($values).Count -eq 0)'
           Replace = '$bad = $false' }
        @{ Name = "closed-list-may-be-one-text"
           Find = '$bad = ($values -isnot [System.Collections.IList] -or @($values).Count -eq 0)'
           Replace = '$bad = (@($values).Count -eq 0)' }
        @{ Name = "closed-list-may-be-empty"
           Find = '$bad = ($values -isnot [System.Collections.IList] -or @($values).Count -eq 0)'
           Replace = '$bad = ($values -isnot [System.Collections.IList])' }
        @{ Name = "closed-list-holds-what-is-not-text"
           Find = '$v -isnot [string] -or $v.Length -lt 1'
           Replace = '$v.Length -lt 1' }
        @{ Name = "closed-list-holds-empty-text"
           Find = '$v -isnot [string] -or $v.Length -lt 1 -or '
           Replace = '$v -isnot [string] -or ' }
        @{ Name = "closed-list-holds-text-past-the-cap"
           Find = ' -or $v.Length -gt $script:HordeModuleSettingTextCap'
           Replace = '' }
        @{ Name = "closed-list-holds-a-control-character"
           Find = ' -or $v -cmatch ''\p{Cc}'') { $bad = $true }'
           Replace = ') { $bad = $true }' }
        @{ Name = "closed-list-holds-a-value-twice"
           Find = 'if (-not $listed.Add($v)) {'
           Replace = 'if ($false) {' }
        @{ Name = "no-default-allowed"
           Find = 'if (-not $fields.ContainsKey("default")) {'
           Replace = 'if ($false) {' }
        @{ Name = "default-unchecked"
           Find = 'if (-not $checked.ok) {'
           Replace = 'if ($false) {' }
        @{ Name = "folder-default-may-not-be-empty"
           Find = 'if ($kind -ceq "folder" -and $default -is [string] -and $default -ceq "") { $entry.default = "" }'
           Replace = 'if ($false) { }' }
        @{ Name = "any-default-may-be-empty"
           Find = 'if ($kind -ceq "folder" -and $default -is [string] -and $default -ceq "") { $entry.default = "" }'
           Replace = 'if ($default -is [string] -and $default -ceq "") { $entry.default = "" }' }
        @{ Name = "one-problem-at-a-time"
           Find = 'if ($problems.Count -gt 0) { throw ("the settings of " + $Module + " are declared wrongly: " + ($problems -join "; ")) }'
           Replace = 'if ($problems.Count -gt 0) { throw ("the settings of " + $Module + " are declared wrongly: " + $problems[0]) }' }
        @{ Name = "part-never-cut"
           Find = 'if ($sb.Length -ge $Max) { [void]$sb.Append("..."); break }'
           Replace = '' }
        @{ Name = "part-cut-one-late"
           Find = 'if ($sb.Length -ge $Max) { [void]$sb.Append("..."); break }'
           Replace = 'if ($sb.Length -gt $Max) { [void]$sb.Append("..."); break }' }
        @{ Name = "part-cut-without-saying"
           Find = 'if ($sb.Length -ge $Max) { [void]$sb.Append("..."); break }'
           Replace = 'if ($sb.Length -ge $Max) { break }' }
        @{ Name = "part-kept-as-written"
           Find = 'if ($code -ge 0x20 -and $code -le 0x7E) {'
           Replace = 'if ($true) {' }
        @{ Name = "part-keeps-unit-separator"
           Find = 'if ($code -ge 0x20 -and $code -le 0x7E) {'
           Replace = 'if ($code -ge 0x1F -and $code -le 0x7E) {' }
        @{ Name = "part-escapes-space"
           Find = 'if ($code -ge 0x20 -and $code -le 0x7E) {'
           Replace = 'if ($code -gt 0x20 -and $code -le 0x7E) {' }
        @{ Name = "part-keeps-delete"
           Find = 'if ($code -ge 0x20 -and $code -le 0x7E) {'
           Replace = 'if ($code -ge 0x20 -and $code -le 0x7F) {' }
        @{ Name = "part-escapes-tilde"
           Find = 'if ($code -ge 0x20 -and $code -le 0x7E) {'
           Replace = 'if ($code -ge 0x20 -and $code -lt 0x7E) {' }
        @{ Name = "name-shown-longer"
           Find = '$script:HordeModuleSettingsNameShown = 60'
           Replace = '$script:HordeModuleSettingsNameShown = 61' }
        @{ Name = "part-shown-longer"
           Find = '$script:HordeModuleSettingsPartShown = 300'
           Replace = '$script:HordeModuleSettingsPartShown = 3000' }
        @{ Name = "file-problem-not-made-plain"
           Find = '(ConvertTo-HordeModuleSettingsPlain -Text $problem -Max $script:HordeModuleSettingsPartShown)'
           Replace = '$problem' }
        @{ Name = "file-problem-does-not-say-it"
           Find = '-Problem ("it " + (ConvertTo-HordeModuleSettingsPlain -Text $problem'
           Replace = '-Problem ("" + (ConvertTo-HordeModuleSettingsPlain -Text $problem' }
        @{ Name = "rule-not-made-plain"
           Find = '$rule = ConvertTo-HordeModuleSettingsPlain -Text (Get-HordeModuleSettingRule -Entry $entry) -Max $script:HordeModuleSettingsPartShown'
           Replace = '$rule = Get-HordeModuleSettingRule -Entry $entry' }
        @{ Name = "key-name-not-made-plain"
           Find = '$shown = ConvertTo-HordeModuleSettingsPlain -Text $key -Max $script:HordeModuleSettingsNameShown'
           Replace = '$shown = $key' }
        @{ Name = "refusal-does-not-say-refused"
           Find = '+ "'' of " + $Module + " is refused: " + $Problem)'
           Replace = '+ "'' of " + $Module + ": " + $Problem)' }
        @{ Name = "refusal-does-not-name-the-module"
           Find = '+ "'' of " + $Module + " is refused: " + $Problem)'
           Replace = '+ "'' is refused: " + $Problem)' }
        @{ Name = "refusal-does-not-name-the-file"
           Find = 'return ("the settings file ''" + (ConvertTo-HordeModuleSettingsPlain -Text $File -Max $script:HordeModuleSettingsPartShown) + "'' of "'
           Replace = 'return ("the settings file" + " of "' }
        @{ Name = "file-name-not-made-plain"
           Find = '(ConvertTo-HordeModuleSettingsPlain -Text $File -Max $script:HordeModuleSettingsPartShown)'
           Replace = '$File' }
        @{ Name = "file-name-cut-as-a-key-is"
           Find = '(ConvertTo-HordeModuleSettingsPlain -Text $File -Max $script:HordeModuleSettingsPartShown)'
           Replace = '(ConvertTo-HordeModuleSettingsPlain -Text $File -Max $script:HordeModuleSettingsNameShown)' }
        @{ Name = "refusal-hands-back-an-empty-object"
           Find = '    if ($null -ne $Values) {'
           Replace = '    if ($true) {' }
        @{ Name = "path-left-out-of-the-answer"
           Find = 'findings = [string[]]@($Findings); path = $Path }'
           Replace = 'findings = [string[]]@($Findings); path = "" }' }
        @{ Name = "state-left-out-of-the-answer"
           Find = '[pscustomobject]@{ state = $State; values = $object;'
           Replace = '[pscustomobject]@{ values = $object;' }
        @{ Name = "any-object-is-a-declaration"
           Find = 'if ($null -eq $Declaration -or $Declaration.PSObject.TypeNames -notcontains "Horde.ModuleSettings") {'
           Replace = 'if ($false) {' }
        @{ Name = "text-of-any-length-read"
           Find = 'if ($Text.Length -gt $script:HordeModuleSettingsMaxLength) {'
           Replace = 'if ($false) {' }
        @{ Name = "text-at-the-limit-refused"
           Find = 'if ($Text.Length -gt $script:HordeModuleSettingsMaxLength) {'
           Replace = 'if ($Text.Length -ge $script:HordeModuleSettingsMaxLength) {' }
        @{ Name = "pieces-not-checked"
           Find = 'if ($pieces.Length -ne $Text.Length) {'
           Replace = 'if ($false) {' }
        @{ Name = "line-counted-from-zero"
           Find = '$line = $Text.Substring(0, $pieces.Length).Split([char]10).Count'
           Replace = '$line = $Text.Substring(0, $pieces.Length).Split([char]10).Count - 1' }
        @{ Name = "pieces-leading-zero"
           Find = '-?(?:0|[1-9][0-9]*)'
           Replace = '-?(?:[0-9]+)' }
        @{ Name = "pieces-number-runs-into-the-next"
           Find = '(?![0-9A-Za-z.+-])'
           Replace = '' }
        @{ Name = "pieces-plus-sign"
           Find = '-?(?:0|[1-9][0-9]*)'
           Replace = '[+-]?(?:0|[1-9][0-9]*)' }
        @{ Name = "pieces-control-character-in-a-string"
           Find = '"(?:[^"\\\x00-\x1F]|'
           Replace = '"(?:[^"\\]|' }
        @{ Name = "pieces-any-escape"
           Find = '\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4})'
           Replace = '\\.' }
        @{ Name = "pieces-not-a-number"
           Find = '|true|false|null|'
           Replace = '|true|false|null|NaN|Infinity|' }
        @{ Name = "pieces-any-blank"
           Find = '(?:[ \t\r\n]+|'
           Replace = '(?:\s+|' }
        @{ Name = "pieces-single-quoted-strings"
           Find = '|true|false|null|'
           Replace = '|''''[^'''']*''''|true|false|null|' }
        @{ Name = "pieces-bare-words"
           Find = '|true|false|null|'
           Replace = '|[A-Za-z_]+|' }
        @{ Name = "duplicate-keys-not-refused"
           Find = 'if ($twice.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "parser-error-thrown"
           Find = 'catch { return [pscustomobject]@{ settings = $null; problems = @("is not JSON the parser can read") } }'
           Replace = 'catch { throw }' }
        @{ Name = "schema-not-checked"
           Find = 'if ($unfit.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "schema-findings-only-the-first"
           Find = '@($unfit | ForEach-Object { "does not fit schema/" + $script:HordeModuleSettingsSchemaName + ": " + $_ })'
           Replace = '@("does not fit schema/" + $script:HordeModuleSettingsSchemaName + ": " + $unfit[0])' }
        @{ Name = "duplicate-findings-only-the-first"
           Find = '@($twice | ForEach-Object { "says one thing twice: " + $_ })'
           Replace = '@("says one thing twice: " + $twice[0])' }
        @{ Name = "text-of-any-type-read"
           Find = 'if ($null -ne $Text -and $Text -isnot [string]) {'
           Replace = 'if ($false) {' }
        @{ Name = "no-file-and-any-file-alike"
           Find = 'if ($null -eq $Text) { return (New-HordeModuleSettingsAnswer -State "defaults"'
           Replace = 'if ($true) { return (New-HordeModuleSettingsAnswer -State "defaults"' }
        @{ Name = "no-file-read-as-a-file"
           Find = 'if ($null -eq $Text) { return (New-HordeModuleSettingsAnswer -State "defaults"'
           Replace = 'if ($false) { return (New-HordeModuleSettingsAnswer -State "defaults"' }
        @{ Name = "no-file-called-read"
           Find = 'New-HordeModuleSettingsAnswer -State "defaults" -Values $values'
           Replace = 'New-HordeModuleSettingsAnswer -State "read" -Values $values' }
        @{ Name = "no-file-is-a-refusal"
           Find = 'New-HordeModuleSettingsAnswer -State "defaults" -Values $values'
           Replace = 'New-HordeModuleSettingsAnswer -State "refused" -Values $null' }
        @{ Name = "good-file-called-defaults"
           Find = 'New-HordeModuleSettingsAnswer -State "read" -Values $values'
           Replace = 'New-HordeModuleSettingsAnswer -State "defaults" -Values $values' }
        @{ Name = "findings-do-not-refuse"
           Find = 'if ($sentences.Count -gt 0) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "one-finding-does-not-refuse"
           Find = 'if ($sentences.Count -gt 0) { return'
           Replace = 'if ($sentences.Count -gt 1) { return' }
        @{ Name = "refusal-called-read"
           Find = '-State "refused" -Values $null -Findings @($sentences.ToArray())'
           Replace = '-State "read" -Values $null -Findings @($sentences.ToArray())' }
        @{ Name = "refusal-hands-back-values"
           Find = '-State "refused" -Values $null -Findings @($sentences.ToArray())'
           Replace = '-State "refused" -Values $values -Findings @($sentences.ToArray())' }
        @{ Name = "refusal-names-only-the-first-problem"
           Find = '-State "refused" -Values $null -Findings @($sentences.ToArray())'
           Replace = '-State "refused" -Values $null -Findings @($sentences[0])' }
        @{ Name = "refusal-names-no-problem"
           Find = '-State "refused" -Values $null -Findings @($sentences.ToArray())'
           Replace = '-State "refused" -Values $null -Findings @()' }
        @{ Name = "file-called-by-the-module-alone"
           Find = '$called = [System.IO.Path]::Combine($script:HordeModuleSettingsFolder, ($module + ".json"))'
           Replace = '$called = $module' }
        @{ Name = "given-file-name-ignored"
           Find = 'if ($called -eq "") {'
           Replace = 'if ($true) {' }
        @{ Name = "answer-path-is-not-the-file-named"
           Find = '-Findings @($sentences.ToArray()) -Path $called)'
           Replace = '-Findings @($sentences.ToArray()) -Path "")' }
        @{ Name = "byte-order-mark-kept"
           Find = 'if ($body.Length -gt 0 -and [int]$body[0] -eq 0xFEFF) { $body = $body.Substring(1) }'
           Replace = '' }
        @{ Name = "every-byte-order-mark-skipped"
           Find = 'if ($body.Length -gt 0 -and [int]$body[0] -eq 0xFEFF) { $body = $body.Substring(1) }'
           Replace = 'while ($body.Length -gt 0 -and [int]$body[0] -eq 0xFEFF) { $body = $body.Substring(1) }' }
        @{ Name = "empty-text-indexed"
           Find = 'if ($body.Length -gt 0 -and [int]$body[0] -eq 0xFEFF) { $body = $body.Substring(1) }'
           Replace = 'if ([int]$body[0] -eq 0xFEFF) { $body = $body.Substring(1) }' }
        @{ Name = "setting-names-ignore-case"
           Find = '$byName = New-Object ''System.Collections.Generic.Dictionary[string,object]'' ([System.StringComparer]::Ordinal)'
           Replace = '$byName = New-Object ''System.Collections.Generic.Dictionary[string,object]'' ([System.StringComparer]::OrdinalIgnoreCase)' }
        @{ Name = "unknown-key-ignored-in-silence"
           Find = '[void]$sentences.Add((Get-HordeModuleSettingsFileSentence -Module $module -File $called -Problem ("it has the key ''" + $shown + "'', which is no setting of " + $module + $meant)))'
           Replace = '$null = $shown' }
        @{ Name = "unknown-key-finding-names-no-key"
           Find = '-Problem ("it has the key ''" + $shown + "'', which is no setting of " + $module + $meant)'
           Replace = '-Problem ("it has a key that is no setting of " + $module + $meant)' }
        @{ Name = "name-meant-not-said"
           Find = 'if ($byNameAnyCase.ContainsKey($key)) {'
           Replace = 'if ($false) {' }
        @{ Name = "name-meant-is-the-key-itself"
           Find = '$meant = " (names are case-sensitive: ''" + $byNameAnyCase[$key].name + "'' is one)"'
           Replace = '$meant = " (names are case-sensitive: ''" + $key + "'' is one)"' }
        @{ Name = "wrong-value-ignored-in-silence"
           Find = '[void]$sentences.Add((Get-HordeModuleSettingsFileSentence -Module $module -File $called -Problem ("its key ''" + $shown + "'' must be " + $rule + "; it gives " + (Get-HordeModuleSettingGiven -Value $given[$key]))))'
           Replace = '$null = $shown' }
        @{ Name = "wrong-value-finding-names-no-key"
           Find = '-Problem ("its key ''" + $shown + "'' must be " + $rule + "; it gives "'
           Replace = '-Problem ("one of its keys must be " + $rule + "; it gives "' }
        @{ Name = "wrong-value-finding-does-not-say-what-was-given"
           Find = ' + "; it gives " + (Get-HordeModuleSettingGiven -Value $given[$key]))))'
           Replace = ')))' }
        @{ Name = "first-wrong-value-ends-the-reading"
           Find = ' + "; it gives " + (Get-HordeModuleSettingGiven -Value $given[$key]))))'
           Replace = ' + "; it gives " + (Get-HordeModuleSettingGiven -Value $given[$key])))); break' }
        @{ Name = "first-unknown-key-ends-the-reading"
           Find = '                continue'
           Replace = '                break' }
        @{ Name = "good-value-not-used"
           Find = 'if ($checked.ok) { $values[$key] = $checked.value; continue }'
           Replace = 'if ($checked.ok) { continue }' }
        @{ Name = "value-handed-over-as-parsed"
           Find = 'if ($checked.ok) { $values[$key] = $checked.value; continue }'
           Replace = 'if ($checked.ok) { $values[$key] = $given[$key]; continue }' }
        @{ Name = "defaults-left-out-of-the-answer"
           Find = '$values[$entry.name] = $entry.default }'
           Replace = '}' }
        @{ Name = "home-may-be-relative"
           Find = 'elseif (-not (Test-HordeModuleSettingFolder -Path $base)) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "given-home-ignored"
           Find = 'if ($base -eq "") { $base = Get-HordeHome }'
           Replace = 'if ($true) { $base = Get-HordeHome }' }
        @{ Name = "settings-folder-renamed"
           Find = '$script:HordeModuleSettingsFolder = "settings"'
           Replace = '$script:HordeModuleSettingsFolder = "config"' }
        @{ Name = "file-not-named-json"
           Find = '($Declaration.module + ".json")'
           Replace = '($Declaration.module + ".txt")' }
        @{ Name = "one-file-for-every-module"
           Find = '($Declaration.module + ".json")'
           Replace = '("probe" + ".json")' }
        @{ Name = "file-of-any-size-read"
           Find = 'if ($stream.Length -gt $script:HordeModuleSettingsMaxLength) {'
           Replace = 'if ($false) {' }
        @{ Name = "file-at-the-limit-refused"
           Find = 'if ($stream.Length -gt $script:HordeModuleSettingsMaxLength) {'
           Replace = 'if ($stream.Length -ge $script:HordeModuleSettingsMaxLength) {' }
        @{ Name = "lenient-decoder"
           Find = '(New-Object System.Text.UTF8Encoding($false, $true))'
           Replace = '(New-Object System.Text.UTF8Encoding($false, $false))' }
        @{ Name = "missing-file-is-a-finding"
           Find = 'if (-not ($cause -is [System.IO.FileNotFoundException] -or $cause -is [System.IO.DirectoryNotFoundException])) {'
           Replace = 'if (-not ($cause -is [System.IO.DirectoryNotFoundException])) {' }
        @{ Name = "missing-folder-is-a-finding"
           Find = 'if (-not ($cause -is [System.IO.FileNotFoundException] -or $cause -is [System.IO.DirectoryNotFoundException])) {'
           Replace = 'if (-not ($cause -is [System.IO.FileNotFoundException])) {' }
        @{ Name = "unreadable-file-is-no-finding"
           Find = 'if (-not ($cause -is [System.IO.FileNotFoundException] -or $cause -is [System.IO.DirectoryNotFoundException])) {'
           Replace = 'if ($false) {' }
        @{ Name = "unreadable-file-throws"
           Find = '$trouble = "cannot be read (" + $cause.GetType().Name + ")" }'
           Replace = 'throw }' }
        @{ Name = "file-opened-without-sharing"
           Find = '$stream = Open-HordeSharedStream -Path $path'
           Replace = '$stream = [System.IO.File]::OpenRead($path)' }
        @{ Name = "file-kept-open"
           Find = 'finally { if ($null -ne $stream) { $stream.Dispose() } }'
           Replace = 'finally { }' }
        @{ Name = "file-trouble-not-reported"
           Find = 'if ($trouble -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "undecodable-file-not-reported"
           Find = 'catch { $trouble = "is not UTF-8 text; save it as UTF-8" }'
           Replace = 'catch { }' }
        @{ Name = "file-trouble-called-read"
           Find = '-State "refused" -Values $null -Findings @(Get-HordeModuleSettingsFileSentence'
           Replace = '-State "read" -Values $null -Findings @(Get-HordeModuleSettingsFileSentence' }
        @{ Name = "file-trouble-names-no-file"
           Find = '-File $path -Problem ("it " + $trouble)) -Path $path)'
           Replace = '-File "" -Problem ("it " + $trouble)) -Path $path)' }
        @{ Name = "file-trouble-answer-without-its-path"
           Find = '-File $path -Problem ("it " + $trouble)) -Path $path)'
           Replace = '-File $path -Problem ("it " + $trouble)) -Path "")' }
        @{ Name = "text-reading-not-given-the-path"
           Find = '-Text $text -File $path)'
           Replace = '-Text $text)' }
    )
}
