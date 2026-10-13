# The claude-code conversation adapter's fixture for test/test-conversation-conformance.ps1 (the contract
# is in that suite's header). Each state is a new fleet registry in the temp folder holding one Thrall
# record and its transcript, built from synthetic lines (ConversationLines.ps1): no real transcript is
# read or copied. Every turn is written with the harness's noise around it, which must never become one.
param([Parameter(Mandatory = $true)][string]$Root)
. (Join-Path $PSScriptRoot "ConversationLines.ps1")
return [pscustomobject]@{
    New = {
        $reg = New-ClaudeCodeRegistry
        $sid = [guid]::NewGuid().ToString()
        $path = Set-ClaudeCodeRecord -Registry $reg -Session $sid
        $st = [pscustomobject]@{ registry = $reg; session = $sid; path = $path; fleet = "conf"; options = @{ registryRoot = $reg.root }; tornRest = $null }
        # A retired Thrall of an earlier run beside it, as a real registry has: it must not be found.
        $null = Set-ClaudeCodeRecord -Registry $reg -Session ([guid]::NewGuid().ToString()) -Retired $true
        return $st
    }
    Add = {
        param($State, $Turns)
        $lines = New-Object System.Collections.ArrayList
        foreach ($t in @($Turns)) {
            foreach ($n in @(New-ClaudeCodeNoise -Session $State.session)) { [void]$lines.Add($n) }
            if ($t.role -ceq "user") { [void]$lines.Add((New-ClaudeCodeLine -Kind "human" -Session $State.session -Text $t.text)) }
            else {
                # A response's text block beside a tool call of the SAME response, as the harness writes it.
                $mid = "msg_synthetic" + [guid]::NewGuid().ToString("N").Substring(0, 16)
                [void]$lines.Add((New-ClaudeCodeLine -Kind "thinking" -Session $State.session -MessageId $mid))
                [void]$lines.Add((New-ClaudeCodeLine -Kind "assistant-text" -Session $State.session -Text $t.text -MessageId $mid))
                [void]$lines.Add((New-ClaudeCodeLine -Kind "tool-use" -Session $State.session -MessageId $mid))
            }
        }
        Add-ClaudeCodeLines -Path $State.path -Lines @($lines)
    }
    Tear = {
        param($State, $Turn)
        $line = New-ClaudeCodeLine -Kind "human" -Session $State.session -Text $Turn.text
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($line + "`n")
        $cut = [int]($bytes.Length / 2)
        $fs = [System.IO.File]::Open($State.path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        try { $fs.Write($bytes, 0, $cut) } finally { $fs.Dispose() }
        $State.tornRest = $bytes[$cut..($bytes.Length - 1)]
        return $true
    }
    Mend = {
        param($State)
        $rest = [byte[]]$State.tornRest
        $fs = [System.IO.File]::Open($State.path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        try { $fs.Write($rest, 0, $rest.Length) } finally { $fs.Dispose() }
        $State.tornRest = $null
    }
    Clear = {
        # /clear: the old record retired, a new session's record names the role and a new file (S4).
        param($State)
        $null = Set-ClaudeCodeRecord -Registry $State.registry -Session $State.session -Retired $true -TranscriptPath $State.path
        $State.session = [guid]::NewGuid().ToString()
        $State.path = Set-ClaudeCodeRecord -Registry $State.registry -Session $State.session
    }
    Rotate = {
        param($State, $Turns)
        [System.IO.File]::Delete($State.path)
        $lines = New-Object System.Collections.ArrayList
        [void]$lines.Add((New-ClaudeCodeLine -Kind "mode" -Session $State.session))
        foreach ($t in @($Turns)) {
            if ($t.role -ceq "user") { [void]$lines.Add((New-ClaudeCodeLine -Kind "human" -Session $State.session -Text $t.text)) }
            else { [void]$lines.Add((New-ClaudeCodeLine -Kind "assistant-text" -Session $State.session -Text $t.text)) }
        }
        Add-ClaudeCodeLines -Path $State.path -Lines @($lines)
    }
    Enlist = {
        # A session of the fleet beside the Thrall: its own record in the registry, as the fleet writes one.
        param($State, $Member)
        $sid = "" + $Member.session
        if ($sid -eq "") { $sid = [guid]::NewGuid().ToString() }
        $null = Set-ClaudeCodeRecord -Registry $State.registry -Session $sid -Role $Member.role -Label $Member.label -Parent $Member.parent
        return $sid
    }
    Remove = { param($State) Remove-ClaudeCodeRegistry -Registry $State.registry }
}
