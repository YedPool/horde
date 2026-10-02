# A CONTROL for tools/ExecScan.ps1, never run: each function below is one way code could start a
# program, a shell or a script, and the scan must find every one of them here. If it finds nothing in
# this file, its silence about remote/ proves nothing (CONTRIBUTING 7). A line ending "# expect: X"
# must have a finding containing X, so each rule of the scan is proved by a form that only it catches.
#
# R01 to R27 are the 27 forms of the review of PR #40 (2026-10-01), verbatim; the first scan, a list of
# banned names, caught 3 of them. O1 to O9 are that first scan's own control. N01 to N15 are the forms
# of the verification of the same day, verbatim; the second scan, an allowlist of commands with lists
# of banned methods and types, let seven through. S and C forms each isolate one rule.
using namespace System.Diagnostics  # expect: a class or a using statement
. (Join-Path $PSScriptRoot $loaded)  # expect: dot-sourcing something other than a neighbour file
. (Join-Path $env:TEMP "Contract.ps1")  # expect: dot-sourcing something other than a neighbour file
. (Join-Path $PSScriptRoot "..\..\elsewhere.ps1")  # expect: dot-sourcing something other than a neighbour file
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Identity.ps1")  # expect: dot-sourcing something other than a neighbour file
class HordeControlQ { [string] R() { return "x" } }  # expect: a class or a using statement
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
function R13 { Set-Alias zz Invoke-Expression; zz "hostname" }  # expect: Set-Alias is not an allowlisted cmdlet
function R14 { Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "cmd /c hostname" } }  # expect: Invoke-CimMethod is not an allowlisted cmdlet
function R15 { Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList "cmd /c hostname" }  # expect: Invoke-WmiMethod is not an allowlisted cmdlet
function R16 { Start-Job { hostname } }  # expect: Start-Job is not an allowlisted cmdlet
function R17 { Add-Type -TypeDefinition 'public static class Q { public static void R() { System.Diagnostics.Process.Start("cmd.exe"); } }' }  # expect: Add-Type is not an allowlisted cmdlet
function R18 { notepad.exe }  # expect: notepad.exe is not an allowlisted cmdlet
function R19 { git status }  # expect: git is not an allowlisted cmdlet
function R20 { ssh.exe somehost }  # expect: ssh.exe is not an allowlisted cmdlet
function R21 { [Activator]::CreateInstance([type]::GetTypeFromProgID("WScript.Shell")).Exec("cmd /c hostname") }  # expect: the method Exec
function R22 { $m = "Start"; [System.Diagnostics.Process]::$m("cmd.exe") }  # expect: a member named by an expression
function R23 { [Diagnostics.Process]::Start("cmd.exe") }  # expect: the type [Diagnostics.Process]
function R24 { & $env:ComSpec /c hostname }  # expect: a call with &
function R25 { Register-ObjectEvent -InputObject (New-Object Timers.Timer) -EventName Elapsed -Action { hostname } }  # expect: Register-ObjectEvent is not an allowlisted cmdlet
function R26 { $ExecutionContext.SessionState.InvokeCommand.InvokeScript("hostname") }  # expect: $ExecutionContext, which reaches the engine
function R27 { Invoke-Command { hostname } }  # expect: Invoke-Command is not an allowlisted cmdlet
function O1 { Invoke-Expression "hostname" }  # expect: Invoke-Expression is not an allowlisted cmdlet
function O2 { iex "hostname" }  # expect: iex is not an allowlisted cmdlet
function O3 { Start-Process "notepad" }  # expect: Start-Process is not an allowlisted cmdlet
function O4 { Invoke-Command -ScriptBlock { 1 } }  # expect: Invoke-Command is not an allowlisted cmdlet
function O5 { $p = "hostname"; & $p }  # expect: a call with &
function O6 { [scriptblock]::Create("hostname") }  # expect: [scriptblock]::Create is not a static member
function O7 { $ExecutionContext.InvokeCommand.NewScriptBlock("hostname") }  # expect: the method NewScriptBlock
function O8 { [System.Diagnostics.Process]::Start("hostname") }  # expect: the type [System.Diagnostics.Process]
function O9 { Invoke-Item "x" }  # expect: Invoke-Item is not an allowlisted cmdlet
function N01 { $null = [Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic"); $null = [Microsoft.VisualBasic.Interaction]::Shell("cmd.exe /c echo N01> %MARKDIR%\N01.txt", 0) }  # expect: the type [Microsoft.VisualBasic.Interaction]
function N02 { $null = ([wmiclass]"Win32_Process").InvokeMethod("Create", @("cmd.exe /c echo N02> %MARKDIR%\N02.txt")) }  # expect: the type [wmiclass]
function N03 { $null = $global:ExecutionContext.InvokeCommand.ExpandString('$(cmd.exe /c "echo N03> %MARKDIR%\N03.txt")') }  # expect: $global:ExecutionContext, which reaches the engine
function N04 { $t = [psobject].Assembly.GetType("System.Management.Automation.ScriptBlock"); $d = [Delegate]::CreateDelegate([Func[string, object]], $t.GetMethod("Create")); $sb = $d.DynamicInvoke('cmd.exe /c "echo N04> %MARKDIR%\N04.txt"'); 1 | ForEach-Object -Process:$sb }  # expect: ForEach-Object -Process:$sb
function N05 { $t = [psobject].Assembly.GetType("System.Management.Automation.ScriptBlock"); $d = [Delegate]::CreateDelegate([Func[string, object]], $t.GetMethod("Create")); $sb = $d.DynamicInvoke('cmd.exe /c "echo N05> %MARKDIR%\N05.txt"'); $null = 1 | Select-Object @{ Name = "x"; Expression = $sb } }  # expect: Select-Object given a script block or a calculated property
function N06 { $t = [psobject].Assembly.GetType("System.Management.Automation.ScriptBlock"); $d = [Delegate]::CreateDelegate([Func[string, object]], $t.GetMethod("Create")); $sb = $d.DynamicInvoke('cmd.exe /c "echo N06> %MARKDIR%\N06.txt"'); $o = New-Object PSObject; $o | Add-Member -MemberType ScriptMethod -Name Go -Value $sb; $null = $o.Go() }  # expect: Add-Member -MemberType
function N08 { $t = [psobject].Assembly.GetType("System.Management.Automation.ScriptBlock"); $d = [Delegate]::CreateDelegate([Func[string, object]], $t.GetMethod("Create")); $sb = $d.DynamicInvoke('cmd.exe /c "echo N08> %MARKDIR%\N08.txt"'); $null = 1 | Sort-Object $sb }  # expect: Sort-Object given $sb
function N09 { $null = $host.Runspace.CreateNestedPipeline('cmd.exe /c "echo N09> %MARKDIR%\N09.txt"', $false).InvokeAsync() }  # expect: $host, which reaches the engine
function N11 { $t = [psobject].Assembly.GetType("System.Management.Automation.ScriptBlock"); $d = [Delegate]::CreateDelegate([Func[string, object]], $t.GetMethod("Create")); $sb = $d.DynamicInvoke('cmd.exe /c "echo N11> %MARKDIR%\N11.txt"'); $null = Invoke-HordeRead -What "x" -Read $sb }  # expect: Invoke-HordeRead is not an allowlisted cmdlet
function N12 { $null = "$(Get-Date; cmd.exe /c echo N12)" }  # expect: cmd.exe is not an allowlisted cmdlet
function N13 { $sb = { 1 }; $c = $sb.GetNewClosure(); 1 | ForEach-Object -Process:$c }  # expect: the method GetNewClosure
function N14 { 1 | ForEach-Object -MemberName ToString }  # expect: ForEach-Object -MemberName
function N15 { $n = "cmd" + ".exe"; & $n /c echo x }  # expect: a call with &
function S01 { param($sb) $sb.Invoke() }  # expect: the method Invoke
function S02 { param($o, $m) $o.$m() }  # expect: a member named by an expression
function S03 { [Diagnostics.Process]::GetProcesses() }  # expect: the type [Diagnostics.Process]
function S04 { $null = New-Object -ComObject Scripting.FileSystemObject }  # expect: New-Object -ComObject
function S05 { $null = New-Object System.Diagnostics.ProcessStartInfo }  # expect: New-Object System.Diagnostics.ProcessStartInfo is not a type
function S06 { param($t) $null = New-Object $t }  # expect: New-Object of a type that is not a literal
function S07 { param($sb) $sb | ForEach-Object Invoke }  # expect: ForEach-Object given Invoke
function S08 { param($sb) $sb | ForEach-Object -MemberName Invoke }  # expect: ForEach-Object -MemberName
function S09 { $null = $ExecutionContext }  # expect: $ExecutionContext, which reaches the engine
function S10 { . (Join-Path $PSScriptRoot "Contract.ps1") }  # expect: dot-sourcing
function S11 { & { 1 } }  # expect: a call with &
function S12 { Remove-Item "x" }  # expect: Remove-Item is not an allowlisted cmdlet
function S13 { New-Alias zz Get-Date }  # expect: New-Alias is not an allowlisted cmdlet
function S14 { param([System.Diagnostics.ProcessStartInfo]$Info) $Info }  # expect: the type [System.Diagnostics.ProcessStartInfo]
function Join-Path { param($x) $x }  # expect: would shadow a command
function Get-HordeSchema { param($x) $x }  # expect: would shadow a command
function C01 { $null = [wmiclass]"Win32_Process" }  # expect: the type [wmiclass]
function C02 { $null = [regex]::CacheSize }  # expect: [regex]::CacheSize is not a static member
function C03 { param($o) $null = $o.InvokeMethod("Create") }  # expect: the method InvokeMethod
function C04 { param($o) $null = $o.GetType() }  # expect: the method GetType
function C05 { $null = $global:ExecutionContext }  # expect: $global:ExecutionContext, which reaches the engine
function C06 { $null = $Host.Name }  # expect: $Host, which reaches the engine
function C07 { $null = $global:anything }  # expect: only plain variables and the script: scope
function C08 { $null = ${function:Get-HordeSchema} }  # expect: only plain variables and the script: scope
function C09 { param($o) $null = $o.InvokeCommand }  # expect: the property InvokeCommand
function C10 { param($sb) 1 | ForEach-Object -Process:$sb }  # expect: ForEach-Object -Process:$sb
function C11 { param($sb) $null = 1 | Select-Object @{ N = "x"; E = $sb } }  # expect: Select-Object given a script block or a calculated property
function C12 { param($sb) $null = 1 | Sort-Object $sb }  # expect: Sort-Object given $sb
function C13 { param($o, $sb) $o | Add-Member -MemberType ScriptMethod -Name Go -Value $sb }  # expect: Add-Member -MemberType
function C14 { param($sb) $null = Invoke-HordeRead -What "x" -Read $sb }  # expect: Invoke-HordeRead is not an allowlisted cmdlet
function C15 { $sb = { 1 }; $null = $sb }  # expect: a script block that is not the body of ForEach-Object or Where-Object
function C16 { param([ValidateScript({ $true })]$x) $x }  # expect: the attribute [ValidateScript()]
function C17 { $null = New-Object System.Net.WebClient }  # expect: New-Object System.Net.WebClient is not a type
function C18 { param($t) $null = $t::Start() }  # expect: a static member ::Start of something that is not a type literal
function C19 { param($x) $null = $x | Where-Object Name -eq 1 }  # expect: Where-Object given Name
function C20 { $null = 1 | ForEach-Object -Begin { 1 } -Process { 2 } }  # expect: ForEach-Object -Begin
function C21 { $null = Join-Path -Path { 1 } -ChildPath "x" }  # expect: a script block that is not the body of ForEach-Object or Where-Object
function C22 { param($p) $null = 1 | Select-Object $p }  # expect: Select-Object given $p
function C23 { param($o) $null = $o | Add-Member "x" "y" }  # expect: Add-Member given "x" by position
function C24 { $null = New-Object -TypeName System.Collections.ArrayList -Property @{ Capacity = 1 } }  # expect: New-Object -Property
function C25 { param($o) $null = $o.Where({ $true }) }  # expect: the method Where
function C26 { param($sb) $null = 1 | Select-Object -Property:@{ N = "x"; E = $sb } }  # expect: Select-Object -Property given a script block or a calculated property
function C27 { $null = [System.IO.File]::Copy("a", "b") }  # expect: [System.IO.File]::Copy is not a static member
function C28 { $null = New-Object System.IO.FileInfo "x" }  # expect: New-Object System.IO.FileInfo is not a type
