# A CONTROL for tools/ExecScan.ps1, never run: each function below is one way code could start a
# program, a shell or a script, and the scan must find every one of them here. If it finds nothing in
# this file, its silence about remote/ proves nothing (CONTRIBUTING 7). A line ending "# expect: X"
# must have a finding containing X, so each rule of the scan is proved by a form that only it catches.
#
# R01 to R27 are the 27 forms of the review of PR #40 (2026-10-01), verbatim; the first scan, a list of
# banned names, caught 3 of them. O1 to O9 are that first scan's own control. S01 onwards each isolate
# one rule.
. (Join-Path $PSScriptRoot $loaded)  # expect: dot-sourcing something other than a neighbour file
. (Join-Path $env:TEMP "Contract.ps1")  # expect: dot-sourcing something other than a neighbour file
. (Join-Path $PSScriptRoot "..\..\elsewhere.ps1")  # expect: dot-sourcing something other than a neighbour file
function R01 { $sb = { hostname }; $sb.Invoke() }  # expect: the method Invoke
function R02 { $sb = { hostname }; $sb.InvokeReturnAsIs() }  # expect: the method InvokeReturnAsIs
function R03 { . $args[0] }  # expect: dot-sourcing
function R04 { .("ie" + "x") "hostname" }  # expect: dot-sourcing
function R05 { (New-Object -ComObject WScript.Shell).Run("cmd /c hostname") }  # expect: the method Run
function R06 { (New-Object -ComObject Shell.Application).ShellExecute("cmd.exe", "/c hostname") }  # expect: the method ShellExecute
function R07 { $p = New-Object System.Diagnostics.Process; $p.StartInfo.FileName = "cmd.exe"; $null = $p.Start() }  # expect: New-Object System.Diagnostics.Process
function R08 { $t = [scriptblock]; $t::Create("hostname") }  # expect: the type [scriptblock]
function R09 { [powershell]::Create().AddScript("hostname").Invoke() }  # expect: the method AddScript
function R10 { $ExecutionContext.InvokeCommand.InvokeScript("hostname") }  # expect: the method InvokeScript
function R11 { Microsoft.PowerShell.Management\Start-Process "notepad" }  # expect: is module-qualified
function R12 { Microsoft.PowerShell.Utility\Invoke-Expression "hostname" }  # expect: is module-qualified
function R13 { Set-Alias zz Invoke-Expression; zz "hostname" }  # expect: Set-Alias is refused
function R14 { Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "cmd /c hostname" } }  # expect: Invoke-CimMethod is refused
function R15 { Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList "cmd /c hostname" }  # expect: Invoke-WmiMethod is refused
function R16 { Start-Job { hostname } }  # expect: Start-Job is refused
function R17 { Add-Type -TypeDefinition 'public static class Q { public static void R() { System.Diagnostics.Process.Start("cmd.exe"); } }' }  # expect: Add-Type is refused
function R18 { notepad.exe }  # expect: notepad.exe is not an allowlisted cmdlet
function R19 { git status }  # expect: git is not an allowlisted cmdlet
function R20 { ssh.exe somehost }  # expect: ssh.exe is not an allowlisted cmdlet
function R21 { [Activator]::CreateInstance([type]::GetTypeFromProgID("WScript.Shell")).Exec("cmd /c hostname") }  # expect: the method Exec
function R22 { $m = "Start"; [System.Diagnostics.Process]::$m("cmd.exe") }  # expect: a member named by an expression
function R23 { [Diagnostics.Process]::Start("cmd.exe") }  # expect: the method Start
function R24 { & $env:ComSpec /c hostname }  # expect: a call with &
function R25 { Register-ObjectEvent -InputObject (New-Object Timers.Timer) -EventName Elapsed -Action { hostname } }  # expect: Register-ObjectEvent is refused
function R26 { $ExecutionContext.SessionState.InvokeCommand.InvokeScript("hostname") }  # expect: $ExecutionContext
function R27 { Invoke-Command { hostname } }  # expect: Invoke-Command is refused
function O1 { Invoke-Expression "hostname" }  # expect: Invoke-Expression is refused
function O2 { iex "hostname" }  # expect: iex is refused
function O3 { Start-Process "notepad" }  # expect: Start-Process is refused
function O4 { Invoke-Command -ScriptBlock { 1 } }  # expect: Invoke-Command is refused
function O5 { $p = "hostname"; & $p }  # expect: a call with &
function O6 { [scriptblock]::Create("hostname") }  # expect: the method Create
function O7 { $ExecutionContext.InvokeCommand.NewScriptBlock("hostname") }  # expect: the method NewScriptBlock
function O8 { [System.Diagnostics.Process]::Start("hostname") }  # expect: the type [System.Diagnostics.Process]
function O9 { Invoke-Item "x" }  # expect: Invoke-Item is refused
function S01 { param($sb) $sb.Invoke() }  # expect: the method Invoke
function S02 { param($o, $m) $o.$m() }  # expect: a member named by an expression
function S03 { [Diagnostics.Process]::GetProcesses() }  # expect: the type [Diagnostics.Process]
function S04 { $null = New-Object -ComObject Scripting.FileSystemObject }  # expect: New-Object -ComObject
function S05 { $null = New-Object System.Diagnostics.ProcessStartInfo }  # expect: New-Object System.Diagnostics.ProcessStartInfo
function S06 { param($t) $null = New-Object $t }  # expect: New-Object of a type that is not a literal
function S07 { param($sb) $sb | ForEach-Object Invoke }  # expect: ForEach-Object given Invoke
function S08 { param($sb) $sb | ForEach-Object -MemberName Invoke }  # expect: ForEach-Object -MemberName
function S09 { $null = $ExecutionContext.SessionState }  # expect: $ExecutionContext
function S10 { . (Join-Path $PSScriptRoot "Contract.ps1") }  # expect: dot-sourcing
function S11 { & { 1 } }  # expect: a call with &
function S12 { Get-ChildItem }  # expect: Get-ChildItem is not an allowlisted cmdlet
function S13 { New-Alias zz Get-Date }  # expect: New-Alias is refused
function Start-Process { param($x) $x }  # expect: would shadow a cmdlet
function S14 { param([System.Diagnostics.ProcessStartInfo]$Info) $Info }  # expect: the type [System.Diagnostics.ProcessStartInfo]
