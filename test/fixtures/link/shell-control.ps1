# A CONTROL for test/test-link-contracts.ps1's no-shell tripwire, never run: each line below is one way
# code could start a shell or a program, and the tripwire must find every one of them here. If it
# finds nothing in this file, its silence about remote/ proves nothing (CONTRIBUTING 7).
function Never-Run-1 { Invoke-Expression "hostname" }
function Never-Run-2 { iex "hostname" }
function Never-Run-3 { Start-Process "notepad" }
function Never-Run-4 { Invoke-Command -ScriptBlock { 1 } }
function Never-Run-5 { $p = "hostname"; & $p }
function Never-Run-6 { [scriptblock]::Create("hostname") }
function Never-Run-7 { $ExecutionContext.InvokeCommand.NewScriptBlock("hostname") }
function Never-Run-8 { [System.Diagnostics.Process]::Start("hostname") }
function Never-Run-9 { Invoke-Item "x" }
