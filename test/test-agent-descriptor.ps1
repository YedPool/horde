# IS AN AGENT DESCRIPTOR REFUSED WHEN IT IS WRONG IN ANY WAY, AND ACCEPTED ONLY WHEN WHOLE?
#
# core/AgentDescriptor.ps1 (engines plan step E2) reads agents/<name>/agent.json: what one agent
# harness offers, each capability yes, no, declined or unverified with its evidence. Every later step
# that picks or launches a harness reads its answers, so a descriptor it cannot trust must never load.
#
# NEUTRAL NAMES ONLY (CONTRIBUTING 14). The golden descriptor is a fixture harness, harness-a, under
# test/fixtures/agent-descriptor/agents/. Each REJECTED SHAPE is one named edit of that golden text,
# so every rejection differs from an accepted descriptor in exactly the one way it names. The real
# descriptors are checked by the suites in their own agents/<name>/test/ folders.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\AgentDescriptor.ps1")

$fixtureRoot = Join-Path $root "test\fixtures\agent-descriptor"
$goldenPath = Join-Path $fixtureRoot "agents\harness-a\agent.json"
$goldenText = [System.IO.File]::ReadAllText($goldenPath)

function Read-Golden { return ($goldenText | ConvertFrom-Json) }
function ConvertTo-DescriptorText { param($Value) return ($Value | ConvertTo-Json -Depth 12) }
function Get-Refusal {
    # The refusal text for a descriptor text, or "" when it loads.
    param([string]$Text, [string]$Name = "harness-a")
    try { $null = Read-HordeAgentDescriptorText -Text $Text -ExpectedName $Name; return "" } catch { return "$($_.Exception.Message)" }
}
function Test-Rejected {
    # One rejected shape: the golden descriptor with one edit. The edit must change the text, and the
    # refusal must say what is wrong (Like), so a refusal for some other reason does not count.
    param([string]$What, [scriptblock]$Edit, [string]$Like)
    $d = Read-Golden
    & $Edit $d
    $text = ConvertTo-DescriptorText $d
    $why = Get-Refusal -Text $text
    Check ($why -ne "" -and $why -like ("*" + $Like + "*")) ("refused: " + $What + $(if ($why -eq "") { " (it loaded)" } elseif ($why -notlike ("*" + $Like + "*")) { " (refused for another reason: " + $why + ")" } else { "" }))
}
function Remove-Prop { param($Object, [string]$Name) $Object.PSObject.Properties.Remove($Name) }
function Add-Prop { param($Object, [string]$Name, $Value) $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }

Write-Host ""
Write-Host "--- the golden descriptor loads ---" -ForegroundColor Cyan
Check ((Get-Refusal -Text $goldenText) -eq "") "CONTROL: the golden fixture descriptor loads"
Check ((Get-Refusal -Text (ConvertTo-DescriptorText (Read-Golden))) -eq "") "CONTROL: the golden descriptor written back by ConvertTo-Json loads too, so every edit below is the only difference"
$golden = Read-HordeAgentDescriptorText -Text $goldenText -ExpectedName "harness-a"
Check ($golden.name -ceq "harness-a") "the loaded descriptor is the one in the file"

Write-Host ""
Write-Host "--- every capability carries evidence, in one of four states ---" -ForegroundColor Cyan
Test-Rejected "a capability whose evidence is blank" { param($d) $d.capabilities.resume.evidence = "   " } "evidence"
Test-Rejected "a capability with no evidence at all" { param($d) Remove-Prop $d.capabilities.resume "evidence" } "evidence"
Test-Rejected "a capability in a state outside the four" { param($d) $d.capabilities.resume.support = "maybe" } "support"
Test-Rejected "a capability state in another case" { param($d) $d.capabilities.resume.support = "Yes" } "support"
Test-Rejected "a capability of the vocabulary left out" { param($d) Remove-Prop $d.capabilities "session.remoteName" } "session.remoteName"
Test-Rejected "a capability the vocabulary does not have" { param($d) Add-Prop $d.capabilities "telepathy" ([pscustomobject]@{ support = "yes"; evidence = "x" }) } "telepathy"
Test-Rejected "a capability row with a field beyond support and evidence" { param($d) Add-Prop $d.capabilities.resume "since" "1.0" } "since"

Write-Host ""
Write-Host "--- every Horde event is mapped once, to a hook, with evidence ---" -ForegroundColor Cyan
Test-Rejected "an event whose evidence is blank" { param($d) $d.events."turn-ended".evidence = "" } "evidence"
Test-Rejected "an event the harness supports with no hook named" { param($d) Remove-Prop $d.events."turn-ended" "hook" } "hook"
Test-Rejected "an event the harness supports with a blank hook" { param($d) $d.events."turn-ended".hook = " " } "hook"
Test-Rejected "an event the harness lacks that still names a hook" { param($d) Add-Prop $d.events."session-ended" "hook" "End" } "hook"
Test-Rejected "a Horde event left out" { param($d) Remove-Prop $d.events "turn-ended" } "turn-ended"
Test-Rejected "an event Horde does not have" { param($d) Add-Prop $d.events "turn-paused" ([pscustomobject]@{ hook = "P"; support = "yes"; evidence = "x" }) } "turn-paused"
Test-Rejected "an event in a state outside the four" { param($d) $d.events."turn-ended".support = "sometimes" } "support"

Write-Host ""
Write-Host "--- protocols, provider, session ids and owned variables ---" -ForegroundColor Cyan
Test-Rejected "no protocol at all" { param($d) $d.protocols = @() } "protocol"
Test-Rejected "a protocol listed twice" { param($d) $d.protocols = @("anthropic-messages", "anthropic-messages") } "twice"
Test-Rejected "a protocol outside the wire-format list" { param($d) $d.protocols = @("carrier-pigeon") } "protocols"
Test-Rejected "no native provider" { param($d) Remove-Prop $d "nativeProvider" } "nativeProvider"
Test-Rejected "a native provider that is not a lower-case name" { param($d) $d.nativeProvider = "Provider A" } "nativeProvider"
Test-Rejected "a session-id pattern that is not anchored at both ends" { param($d) $d.sessionIdPattern = "[0-9a-f]{8}" } "anchored"
Test-Rejected "a session-id pattern anchored only at the start" { param($d) $d.sessionIdPattern = "^[0-9a-f]{8}" } "anchored"
Test-Rejected "a session-id pattern that does not compile" { param($d) $d.sessionIdPattern = "^([0-9$" } "compile"
Test-Rejected "an owned variable listed twice, in another case" { param($d) $d.ownedEnv = @($d.ownedEnv) + @([pscustomobject]@{ name = "provider_a_token"; evidence = "again" }) } "twice"
Test-Rejected "an owned variable whose name is not an environment-variable name" { param($d) $d.ownedEnv[0].name = "PROVIDER A" } "ownedEnv"
Test-Rejected "an owned variable with blank evidence" { param($d) $d.ownedEnv[0].evidence = " " } "evidence"

Write-Host ""
Write-Host "--- every permission level of core/permission-levels.json is mapped once (remote R0, R9) ---" -ForegroundColor Cyan
function Get-LevelRow { param($d, [string]$Level) return @($d.permissionLevels | Where-Object { $_.level -ceq $Level })[0] }
Test-Rejected "a permission level left out" { param($d) $d.permissionLevels = @($d.permissionLevels | Where-Object { $_.level -cne "edits" }) } "edits"
Test-Rejected "a permission level mapped twice" { param($d) $d.permissionLevels = @($d.permissionLevels) + @((Get-LevelRow $d "plan")) } "plan"
Test-Rejected "a permission level the vocabulary does not have" { param($d) $d.permissionLevels = @($d.permissionLevels) + @([pscustomobject]@{ level = "sandboxed"; inexpressible = "x" }) } "sandboxed"
Test-Rejected "a level in another case" { param($d) (Get-LevelRow $d "plan").level = "Plan" } "level"
Test-Rejected "a level given both a fragment, with its evidence, and a reason it cannot be expressed" { param($d) $r = Get-LevelRow $d "bypass"; Add-Prop $r "argv" @("--all"); Add-Prop $r "evidence" "--all in its help" } "both"
Test-Rejected "a level given neither" { param($d) Remove-Prop (Get-LevelRow $d "bypass") "inexpressible" } "bypass"
Test-Rejected "a fragment with no evidence that its flag was read off the help" { param($d) Remove-Prop (Get-LevelRow $d "edits") "evidence" } "evidence"
Test-Rejected "a fragment whose evidence is blank" { param($d) (Get-LevelRow $d "edits").evidence = " " } "evidence"
Test-Rejected "an empty fragment" { param($d) (Get-LevelRow $d "edits").argv = @() } "edits"
Test-Rejected "a fragment holding a blank word" { param($d) (Get-LevelRow $d "edits").argv = @("--mode", " ") } "argv"
Test-Rejected "an inexpressible level with a blank reason" { param($d) (Get-LevelRow $d "bypass").inexpressible = " " } "inexpressible"
Test-Rejected "an inexpressible level that also carries evidence, as if it had a flag" { param($d) Add-Prop (Get-LevelRow $d "bypass") "evidence" "read off the help" } "bypass"
$levels = @(Get-HordePermissionLevels)
$grown = @($levels) + @([pscustomobject]@{ name = "sandboxed"; rank = $levels.Count; meaning = "a level added later" })
$why = ""
try { $null = Read-HordeAgentDescriptorText -Text $goldenText -ExpectedName "harness-a" -Levels $grown } catch { $why = "$($_.Exception.Message)" }
Check ($why -like "*sandboxed*") "a vocabulary that gains a level fails a descriptor written against the old one, naming the level it lacks"

Write-Host ""
Write-Host "--- a level the harness cannot express is refused, never lowered ---" -ForegroundColor Cyan
$p = Get-HordePermissionArgs -Descriptor $golden -Level "edits"
Check ($p.state -eq "known" -and (@($p.value) -join " ") -ceq "--mode edit") "CONTROL: an expressible level gives that level's fragment"
$p = Get-HordePermissionArgs -Descriptor $golden -Level "bypass"
Check ($p.state -eq "unknown") "an inexpressible level is refused (unknown), not answered with some fragment"
Check ($p.state -eq "unknown" -and $p.reason -like "*no way to skip every prompt*") "and the refusal carries the descriptor's reason"
Check ($p.state -ne "known" -or (@($p.value) -join " ") -cne "--mode edit") "and never the fragment of the nearest level below it"
$p = Get-HordePermissionArgs -Descriptor $golden -Level "Bypass"
Check ($p.state -eq "unknown" -and $p.reason -like "*not a Horde permission level*") "a level name in another case is not a level, and is refused"
$p = Get-HordePermissionArgs -Descriptor $golden -Level "plan"
Check ($p.state -eq "known" -and (@($p.value) -join " ") -ceq "--mode look") "CONTROL: the lowest level is a level like any other"
$p1 = Get-HordePermissionArgs -Descriptor $golden -Level "plan"
$p1.value[0] = "--changed"
Check ((@((Get-HordePermissionArgs -Descriptor $golden -Level "plan").value) -join " ") -ceq "--mode look") "a caller that edits the fragment it was given does not change the descriptor"

Write-Host ""
Write-Host "--- the file as a whole ---" -ForegroundColor Cyan
Check ((Get-Refusal -Text $goldenText -Name "harness-b") -like "*harness-b*") "refused: a descriptor whose name is not its folder's"
Test-Rejected "a field the schema does not have" { param($d) Add-Prop $d "auth" "subscription" } "auth"
Test-Rejected "another schema version" { param($d) $d.schemaVersion = 2 } "schemaVersion"
Test-Rejected "a measurement date that is not a date" { param($d) $d.measured.on = "last week" } "measured"
Test-Rejected "no record of which version was measured" { param($d) Remove-Prop $d "measured" } "measured"
$dupText = $goldenText.Replace('"nativeProvider": "provider-a",', '"nativeProvider": "provider-a", "nativeProvider": "provider-b",')
Check ($dupText -ne $goldenText -and (Get-Refusal -Text $dupText) -like "*twice*") "refused: a key repeated in one object, where only the last would be read"
$why = Get-Refusal -Text "{ not json"
Check ($why -ne "") "refused: text that is not JSON"

# Bytes: read from a file, so the check sees what is on disk, not what a decoder made of it.
$work = Join-Path $env:TEMP ("horde-agent-descriptor-" + [guid]::NewGuid().ToString("N"))
try {
    $dir = Join-Path $work "agents\harness-a"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $file = Join-Path $dir "agent.json"
    [System.IO.File]::WriteAllBytes($file, [System.Text.Encoding]::ASCII.GetBytes($goldenText))
    Check ((Read-HordeAgentDescriptor -Path $file).name -ceq "harness-a") "CONTROL: the golden text written as plain ASCII loads from a file, its name taken from the folder"
    [System.IO.File]::WriteAllBytes($file, [byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::ASCII.GetBytes($goldenText)))
    Check (Throws { Read-HordeAgentDescriptor -Path $file } "byte-order mark") "refused: a descriptor saved with a byte-order mark"
    $accented = $goldenText.Replace("measured firing", ("measured fir" + [char]0x00EF + "ng"))
    [System.IO.File]::WriteAllBytes($file, [System.Text.Encoding]::UTF8.GetBytes($accented))
    Check ($accented -ne $goldenText -and (Throws { Read-HordeAgentDescriptor -Path $file } "not ASCII")) "refused: a descriptor holding a byte that is not ASCII (CONTRIBUTING 13)"

    Write-Host ""
    Write-Host "--- every agents/<name>/ folder has a descriptor ---" -ForegroundColor Cyan
    [System.IO.File]::WriteAllBytes($file, [System.Text.Encoding]::ASCII.GetBytes($goldenText))
    $all = Get-HordeAgentDescriptors -Root $work
    Check (@($all.Keys) -ccontains "harness-a" -and @($all.Keys).Count -eq 1) "CONTROL: a tree whose one folder has a descriptor loads it"
    New-Item -ItemType Directory -Path (Join-Path $work "agents\harness-b") -Force | Out-Null
    Check (Throws { Get-HordeAgentDescriptors -Root $work } "harness-b") "refused: a harness folder with no agent.json, named"
    $b = Join-Path $work "agents\harness-b\agent.json"
    [System.IO.File]::WriteAllBytes($b, [System.Text.Encoding]::ASCII.GetBytes($goldenText))
    Check (Throws { Get-HordeAgentDescriptors -Root $work } "harness-b") "refused: a folder whose descriptor names another harness"
    [System.IO.File]::WriteAllBytes($b, [System.Text.Encoding]::ASCII.GetBytes($goldenText.Replace('"name": "harness-a"', '"name": "harness-b"')))
    Check (@((Get-HordeAgentDescriptors -Root $work).Keys).Count -eq 2) "CONTROL: with its own descriptor, both folders load"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
$realWhy = ""
$real = [ordered]@{}
try { $real = Get-HordeAgentDescriptors -Root $root } catch { $realWhy = ": " + $_.Exception.Message }
$realFolders = @(Get-ChildItem -LiteralPath (Join-Path $root "agents") -Directory | ForEach-Object { $_.Name })
Check ($realWhy -eq "" -and $realFolders.Count -ge 1 -and @($realFolders | Where-Object { @($real.Keys) -cnotcontains $_ }).Count -eq 0) ("every harness folder in this repository has a descriptor that loads (" + $realFolders.Count + " folders)" + $realWhy)

Write-Host ""
Write-Host "--- a capability counts only when it is yes ---" -ForegroundColor Cyan
Check ((Test-HordeAgentCapability -Descriptor $golden -Name "resume") -eq $true) "CONTROL: yes satisfies a requirement"
Check ((Test-HordeAgentCapability -Descriptor $golden -Name "message-inject") -eq $false) "unverified never satisfies a requirement"
Check ((Test-HordeAgentCapability -Descriptor $golden -Name "provider-select") -eq $false) "declined does not either"
Check ((Test-HordeAgentCapability -Descriptor $golden -Name "name-at-spawn") -eq $false) "nor does no"
$a = Get-HordeAgentCapability -Descriptor $golden -Name "resume"
Check ($a.state -eq "known" -and $a.value -eq $true) "the answer for yes is known true"
$a = Get-HordeAgentCapability -Descriptor $golden -Name "name-at-spawn"
Check ($a.state -eq "known" -and $a.value -eq $false) "the answer for no is known false"
$a = Get-HordeAgentCapability -Descriptor $golden -Name "provider-select"
Check ($a.state -eq "known" -and $a.value -eq $false) "the answer for declined is known false"
$a = Get-HordeAgentCapability -Descriptor $golden -Name "message-inject"
Check ($a.state -eq "unknown" -and $a.reason -like "*unverified*delivery unmeasured*") "the answer for unverified is unknown, with the evidence as its reason - never yes and never a plain no"
Check (Throws { Get-HordeAgentCapability -Descriptor $golden -Name "telepathy" } "telepathy") "a capability outside the vocabulary is a mistake in the caller, and throws"

# The web-session-name gate (plan group I). A harness whose remote name is unverified gets no naming
# fragment at birth, and lifecycle step 34's horde names answers it unknown - never ok, never drifted.
# This step owns the answer those two read; the fragment is N1's, the verb lifecycle 34's.
$a = Get-HordeAgentCapability -Descriptor $golden -Name "session.remoteName"
Check ($a.state -eq "unknown") "a fixture harness with session.remoteName unverified is answered unknown"
$yes = Read-Golden
$yes.capabilities."session.remoteName".support = "yes"
$yesD = Read-HordeAgentDescriptorText -Text (ConvertTo-DescriptorText $yes) -ExpectedName "harness-a"
$a = Get-HordeAgentCapability -Descriptor $yesD -Name "session.remoteName"
Check ($a.state -eq "known" -and $a.value -eq $true) "CONTROL: set to yes, the same harness is answered known true"

Write-Host ""
Write-Host "--- the capability vocabulary (core/capabilities.json) ---" -ForegroundColor Cyan
$vocab = @(Get-HordeCapabilityVocabulary)
Check ($vocab.Count -ge 1) ("the vocabulary loads (" + $vocab.Count + " capabilities)")
$schemaNames = @((Get-HordeSchema -Name "agent-descriptor.v1").properties.capabilities.required)
$agentNames = @($vocab | Where-Object { $_.port -ne "host" } | ForEach-Object { $_.name })
Check ($schemaNames.Count -ge 1 -and @($schemaNames | Where-Object { $agentNames -cnotcontains $_ }).Count -eq 0 -and @($agentNames | Where-Object { $schemaNames -cnotcontains $_ }).Count -eq 0) "the schema's capabilities are exactly the ones the vocabulary says an agent can satisfy"
$either = @($vocab | Where-Object { $_.port -eq "either" })
Check ($either.Count -ge 1 -and @($either | Where-Object { $script:HordeHostCapabilityNames -cnotcontains $_.host }).Count -eq 0) "every capability a host can also satisfy names a capability of the host port's own vocabulary"
function Get-VocabRefusal {
    param([string]$Text)
    try { $null = Read-HordeCapabilityVocabularyText -Text $Text; return "" } catch { return "$($_.Exception.Message)" }
}
$vText = [System.IO.File]::ReadAllText((Join-Path $root "core\capabilities.json"))
Check ((Get-VocabRefusal $vText) -eq "") "CONTROL: the vocabulary's own text loads through the text reader"
$bad = $vText.Replace('"host": "text.send"', '"host": "text.sned"')
Check ($bad -ne $vText -and (Get-VocabRefusal $bad) -like "*text.sned*") "refused: a host capability the host port does not have"
$v = $vText | ConvertFrom-Json
$v.capabilities = @($v.capabilities) + @($v.capabilities[0])
Check ((Get-VocabRefusal ($v | ConvertTo-Json -Depth 6)) -like "*twice*") "refused: a capability listed twice"
$v = $vText | ConvertFrom-Json
$v.capabilities[0].port = "anyone"
Check ((Get-VocabRefusal ($v | ConvertTo-Json -Depth 6)) -like "*port*") "refused: a port other than agent, host or either"
$v = $vText | ConvertFrom-Json
$agentRow = @($v.capabilities | Where-Object { $_.port -eq "agent" })[0]
Add-Prop $agentRow "host" "text.send"
Check ((Get-VocabRefusal ($v | ConvertTo-Json -Depth 6)) -like "*host*") "refused: a capability only an agent satisfies that names a host capability"
$v = $vText | ConvertFrom-Json
$v.capabilities[0].meaning = "skip it with --no-ask"
Check ((Get-VocabRefusal ($v | ConvertTo-Json -Depth 6)) -like "*flag*") "refused: a meaning that spells a command-line flag, which belongs in a harness's folder"

Complete-HordeSuite -Success "an agent descriptor loads only when whole, and a capability counts only when yes"
