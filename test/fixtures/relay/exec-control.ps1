# Control file for the relay profile of tools/ExecScan.ps1 (test/test-exec-scan.ps1, section II). Every
# function is a way to compile code that the one admitted Add-Type form does not allow; each line names
# the finding it must get. Never run: it is parsed only.

function Get-FromVariable { $src = "public class X {}"; Add-Type -TypeDefinition $src }  # expect: only a literal neighbour C# file
function Get-FromMember { Add-Type -MemberDefinition 'public static void M() {}' -Name A -Namespace B }  # expect: only a literal neighbour C# file
function Get-FromPathVariable { $p = "Gcm.cs"; Add-Type -Path $p }  # expect: only a literal neighbour C# file
function Get-FromParentFolder { Add-Type -Path (Join-Path $PSScriptRoot "..\Evil.cs") }  # expect: only a literal neighbour C# file
function Get-FromOtherRoot { Add-Type -Path (Join-Path $HOME "Gcm.cs") }  # expect: only a literal neighbour C# file
function Get-ByAssemblyName { Add-Type -AssemblyName System.Web }  # expect: only a literal neighbour C# file
function Get-WithMoreParameters { Add-Type -Path (Join-Path $PSScriptRoot "Gcm.cs") -ReferencedAssemblies System.Diagnostics.Process }  # expect: only a literal neighbour C# file
function Get-NotCSharp { Add-Type -Path (Join-Path $PSScriptRoot "Gcm.dll") }  # expect: only a literal neighbour C# file
function Get-Positional { Add-Type (Join-Path $PSScriptRoot "Gcm.cs") }  # expect: only a literal neighbour C# file
function Get-Expandable { $n = "Gcm"; Add-Type -Path (Join-Path $PSScriptRoot "$n.cs") }  # expect: only a literal neighbour C# file
function Get-ColonBound { Add-Type -Path:(Join-Path $PSScriptRoot "Gcm.cs") }  # expect: only a literal neighbour C# file
function Get-LowerCase { add-type -TypeDefinition 'public class Y {}' }  # expect: only a literal neighbour C# file
