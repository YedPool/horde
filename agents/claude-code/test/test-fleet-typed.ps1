# DOES HIBERNATION READ WHAT A PERSON TYPED INTO A SESSION - AND ONLY THAT - FROM THE TRANSCRIPT'S TAIL?
#
# agents/claude-code/Fleet.ps1, Get-ClaudeCodeFleetTyped (the fleet port's LastTyped). Each transcript
# here is a real file this suite writes under TEMP, its lines in the shapes measured on 2026-10-16 from
# the 80 newest local transcripts (the adapter's comment lists them): a typed prompt, a queued one, the
# fleet's mail pointer (typed too, and returned - telling it apart is fleet/Hibernate.ps1's), a Stop hook
# mail block, a task notification, a tool result, a compaction summary, a side conversation, an Escape and
# a typed slash command. Nothing here reads a real transcript.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "agents\claude-code\Fleet.ps1")

function Section { param([string]$Title) Write-Host ""; Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan }

$work = Join-Path $env:TEMP ("horde-fleet-typed-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $work -Force)
$now = [datetime]::new(2026, 10, 16, 12, 0, 0, [System.DateTimeKind]::Utc)
function Stamp { param([double]$MinutesAgo) return $now.AddMinutes(-$MinutesAgo).ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture) }
function Line {
    # One transcript line, compact JSON as the harness writes it.
    param([hashtable]$Fields)
    return (ConvertTo-Json -InputObject $Fields -Compress -Depth 8)
}
function Human { param([double]$Ago, [string]$Text, [string]$Source = "typed") Line @{ type = "user"; timestamp = (Stamp $Ago); origin = @{ kind = "human" }; promptSource = $Source; message = @{ role = "user"; content = $Text } } }
function Write-Transcript { param([string]$Name, [string[]]$Lines) $p = Join-Path $work $Name; [System.IO.File]::WriteAllText($p, (($Lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false))); return $p }

Section "what counts as typed by a person"
$lines = @(
    (Human 50 "an old prompt, before the window")
    (Human 20 "please look at the failing test")
    (Human 15 "wezfleet: a message is waiting for you (id 0123456789) - run 'wezfleet mail read' to take it" "queued")
    (Line @{ type = "user"; timestamp = (Stamp 14); isMeta = $true; message = @{ role = "user"; content = "Stop hook feedback:`nMESSAGE FROM M (wezfleet mail 0123)`n`ngo on" } })
    (Line @{ type = "user"; timestamp = (Stamp 13); origin = @{ kind = "task-notification" }; promptSource = "system"; message = @{ role = "user"; content = "<task-notification>done</task-notification>" } })
    (Line @{ type = "user"; timestamp = (Stamp 12); message = @{ role = "user"; content = @(@{ type = "tool_result"; tool_use_id = "x"; content = "ok" }) } })
    (Line @{ type = "user"; timestamp = (Stamp 11); isCompactSummary = $true; message = @{ role = "user"; content = "This session is being continued from a previous conversation" } })
    (Line @{ type = "user"; timestamp = (Stamp 10); isSidechain = $true; origin = @{ kind = "human" }; message = @{ role = "user"; content = "a side conversation's prompt" } })
    (Line @{ type = "user"; timestamp = (Stamp 9); message = @{ role = "user"; content = @(@{ type = "text"; text = "[Request interrupted by user]" }) } })
    (Line @{ type = "user"; timestamp = (Stamp 8); message = @{ role = "user"; content = "<command-name>/model</command-name>" } })
    (Line @{ type = "user"; timestamp = (Stamp 7); message = @{ role = "user"; content = "<local-command-stdout>Set model</local-command-stdout>" } })
    (Line @{ type = "assistant"; timestamp = (Stamp 6); message = @{ role = "assistant"; content = @(@{ type = "text"; text = "origin human in my words" }) } })
    (Human 5 ("x" * 500))
    "not json at all, a torn line"
)
$p = Write-Transcript "a.jsonl" $lines
$a = Get-ClaudeCodeFleetTyped -Path $p -Since $now.AddMinutes(-30)
Check ($a.state -ceq "known") ("a readable transcript is read (" + $a.reason + ")")
$texts = @($a.value | ForEach-Object { $_.text })
Check ($texts.Count -eq 5) ("five typed turns in the window: the prompt, the pointer, the Escape, the slash command and the long one (" + $texts.Count + ")")
Check ($texts[0].Length -eq 200 -and $texts[0] -ceq ("x" * 200)) "newest first, and a long text is cut to 200 characters"
Check ($texts -ccontains "please look at the failing test") "a typed prompt is returned"
Check (@($texts | Where-Object { $_.StartsWith("wezfleet:") }).Count -eq 1) "the fleet's pointer is returned too: the harness marks it as typed, and the fleet's code tells it apart"
Check ($texts -ccontains "[Request interrupted by user]" -and $texts -ccontains "<command-name>/model</command-name>") "an Escape and a typed slash command, which carry no origin, are returned"
Check (-not ($texts -ccontains "an old prompt, before the window")) "a prompt older than the window is not"
Check (@($texts | Where-Object { $_ -like "*Stop hook*" -or $_ -like "*task-notification*" -or $_ -like "*being continued*" -or $_ -like "*side conversation*" -or $_ -like "*local-command-stdout*" -or $_ -like "*my words*" }).Count -eq 0) "a mail block, a notification, a tool result, a summary, a side conversation, a command's output and the model's words are never a person's"
Check ($a.value[0].at -eq $now.AddMinutes(-5) -and $a.value[0].at.Kind -eq [System.DateTimeKind]::Utc) "each time is the line's own timestamp, in UTC"

Section "the tail grows until it holds the whole window"
$many = New-Object System.Collections.ArrayList
[void]$many.Add((Human 40 "before the window"))
[void]$many.Add((Human 25 "inside the window, far back"))
for ($i = 0; $i -lt 400; $i++) { [void]$many.Add((Line @{ type = "assistant"; timestamp = (Stamp (24 - $i * 0.05)); message = @{ role = "assistant"; content = @(@{ type = "text"; text = ("filler " * 20) }) } })) }
$p2 = Write-Transcript "b.jsonl" @($many)
$b = Get-ClaudeCodeFleetTyped -Path $p2 -Since $now.AddMinutes(-30) -TailBytes 2048
Check ($b.state -ceq "known" -and @($b.value | Where-Object { $_.text -ceq "inside the window, far back" }).Count -eq 1) "a prompt beyond the first tail read, inside the window, is found"
$c = Get-ClaudeCodeFleetTyped -Path $p2 -Since $now.AddMinutes(-30) -TailBytes 2048 -MostBytes 4096
Check ($c.state -ceq "unknown") "a window longer than the most it may read is unknown, never answered from part of it"
$d = Get-ClaudeCodeFleetTyped -Path $p2 -Since $now.AddMinutes(-1) -TailBytes 2048 -MostBytes 4096
Check ($d.state -ceq "known" -and @($d.value).Count -eq 0) "CONTROL: a short window inside the tail is read from the tail alone, and holds nothing typed"

Section "an unreadable transcript is unknown"
Check ((Get-ClaudeCodeFleetTyped -Path "" -Since $now).state -ceq "unknown") "no path is unknown"
Check ((Get-ClaudeCodeFleetTyped -Path (Join-Path $work "missing.jsonl") -Since $now).state -ceq "unknown") "a missing file is unknown"
Check ((Get-ClaudeCodeFleetTyped -Path "relative.jsonl" -Since $now).state -ceq "unknown") "a relative path is unknown"
$a = Resolve-HordeFleetAdapter -Kind "agent"
Check ($a.state -ceq "known" -and $null -ne $a.value.lastTyped) "the adapter registers the reader as the port's LastTyped"
$viaPort = & $a.value.lastTyped $p $now.AddMinutes(-30)
Check ($viaPort.state -ceq "known" -and @($viaPort.value).Count -eq 5) "and the port's block answers as the function does"

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Complete-HordeSuite -Success "hibernation reads what a person typed from the transcript's tail, and nothing the harness or the fleet wrote in their place"
