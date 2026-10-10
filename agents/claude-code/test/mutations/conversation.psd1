# Mutations of agents/claude-code/Conversation.ps1, the Claude Code conversation adapter. Run:
#   powershell -File tools\Mutate.ps1 -Spec agents\claude-code\test\mutations\conversation.psd1
# Each finds the wrong Thrall, keeps a line that is not a turn, or loses its place in the file;
# agents\claude-code\test\test-conversation.ps1 must fail for every one.
@{
    Target = "agents\claude-code\Conversation.ps1"
    Suite  = "agents\claude-code\test\test-conversation.ps1"
    Mutations = @(
        @{ Name = "retired-thrall-found"
           Find = 'if ($retired.state -ceq "known" -and [bool]$retired.value) { continue }'
           Replace = '$null = $retired' }
        @{ Name = "one-of-two-thralls-chosen"
           Find = 'if ($holders.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "other-sessions-transcript-read"
           Find = 'if ([System.IO.Path]::GetFileNameWithoutExtension($tp.value) -ine $one.id -or [System.IO.Path]::GetExtension($tp.value) -ine ".jsonl") {'
           Replace = 'if ($false) {' }
        @{ Name = "unreadable-registry-ignored"
           Find = 'if ($registry.complete.state -cne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "side-conversation-read"
           Find = 'if ((Get-ClaudeCodeMember $j "isSidechain") -eq $true) { return @() }'
           Replace = '$null = $j' }
        @{ Name = "harness-flags-ignored"
           Find = 'if ((Get-ClaudeCodeMember $j "isMeta") -eq $true -or (Get-ClaudeCodeMember $j "isCompactSummary") -eq $true) { return @() }'
           Replace = '$null = $j' }
        @{ Name = "origin-not-checked"
           Find = 'if ((Get-ClaudeCodeMember (Get-ClaudeCodeMember $j "origin") "kind") -cne "human") { return @() }'
           Replace = '$null = $j' }
        @{ Name = "api-error-shown-as-the-model"
           Find = '$role = "system"'
           Replace = '$role = "assistant"' }
        @{ Name = "no-group-id"
           Find = 'if ($group -is [string] -and $group -ne "") { $t["groupId"] = $group }'
           Replace = '$null = $group' }
        @{ Name = "one-id-for-every-block"
           Find = 'turnId = $(if ($k -eq 0) { $uuid } else { $uuid + "#" + $k })'
           Replace = 'turnId = $uuid' }
        @{ Name = "torn-line-read"
           Find = '$lastLf = [Array]::LastIndexOf($buf, [byte]10, $got - 1)'
           Replace = '$lastLf = $got - 1' }
        @{ Name = "long-line-skipped-before-it-is-whole"
           Find = 'if ($end -lt 0) { break }'
           Replace = 'if ($end -lt 0) { $end = $length - 1 }' }
        @{ Name = "head-change-not-seen"
           Find = 'elseif ($headLen -gt 0 -and (Get-ClaudeCodeHeadHash -Stream $stream -Count $headLen) -cne $headHash) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "moved-line-end-not-seen"
           Find = 'if ($stream.ReadByte() -ne 10) {'
           Replace = 'if ($false) {' }
        @{ Name = "shrink-not-named"
           Find = 'if ($length -lt $offset) {'
           Replace = 'if ($false) {' }
        @{ Name = "split-line-resumed-wrong"
           Find = '$skipTurns = $skipTurns + $room'
           Replace = '$skipTurns = $room' }
        @{ Name = "byte-limit-ignored"
           Find = '$window = [long][Math]::Min([long]($length - $consumed), $MaxBytes)'
           Replace = '$window = [long]($length - $consumed)' }
        @{ Name = "unparsed-lines-not-counted"
           Find = 'if ($unreadable -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "thrall-without-a-file-unknown"
           Find = 'if ($offset -eq 0) { return (New-HordeKnown'
           Replace = 'if ($false) { return (New-HordeKnown' }
    )
}
