# test/lib/PaneTool.ps1 - a small console program for tests that run something in a terminal pane.
#
# WHY A COMPILED PROGRAM. A pane runs an executable, and what a test needs to know is what that
# executable received: its exact arguments, its environment, and whether it ended when it was told to.
# A script would need an interpreter between the pane and the test, with quoting rules of its own; this
# is one .exe whose arguments arrive through the C runtime exactly as any harness's would. It is
# compiled from the source below with Add-Type into a folder under TEMP, once per process.
#
# MODES:
#   standin <out> <exit|never> <args...>  write its pid and each argument (base64 of UTF-8, one per
#                                         line) to <out>, print PANETOOL-READY, then read lines from
#                                         the terminal; with exit, the line /exit ends it with code 0;
#                                         with never, nothing does (a session that ignores a close).
#   env-dump <out>                        write every environment variable, NAME=base64(value).
#   cli --no-auto-start <mode> ...        run <mode>: the tool standing in for the terminal's command,
#                                         so a test sees what a terminal call's process received.
#
# A pane gets the environment of the process that runs `cli spawn` (measured 2026-10-05, issue #95),
# so env-dump in a pane shows exactly what a program spawned the same way would see.
#
# Test-only. Nothing that ships uses it.

$script:HordePaneToolSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

public static class HordePaneTool {
    static string B64(string s) { return Convert.ToBase64String(Encoding.UTF8.GetBytes(s)); }
    static string Un64(string s) { return Encoding.UTF8.GetString(Convert.FromBase64String(s)); }
    public static int Main(string[] args) {
        if (args.Length < 1) return 64;
        // Standing in for the terminal's command in a test: "cli --no-auto-start <mode> ..." runs <mode>,
        // so a test can see what a terminal call's process received, environment included.
        if (args.Length >= 3 && args[0] == "cli" && args[1] == "--no-auto-start") {
            var rest = new string[args.Length - 2];
            Array.Copy(args, 2, rest, 0, rest.Length);
            return Main(rest);
        }
        if (args[0] == "standin" && args.Length >= 3) {
            var lines = new List<string>();
            lines.Add("pid=" + Process.GetCurrentProcess().Id);
            for (int i = 3; i < args.Length; i++) lines.Add("arg=" + B64(args[i]));
            File.WriteAllLines(args[1], lines.ToArray(), Encoding.ASCII);
            Console.WriteLine("PANETOOL-READY");
            bool exitOn = args[2] == "exit";
            while (true) {
                string l = Console.ReadLine();
                if (l == null) { if (exitOn) return 0; System.Threading.Thread.Sleep(1000); continue; }
                if (exitOn && l.Trim() == "/exit") { Console.WriteLine("PANETOOL-EXIT"); return 0; }
            }
        }
        if (args[0] == "env-dump" && args.Length == 2) {
            var lines = new List<string>();
            foreach (System.Collections.DictionaryEntry e in Environment.GetEnvironmentVariables()) lines.Add(e.Key + "=" + B64("" + e.Value));
            File.WriteAllLines(args[1], lines.ToArray(), Encoding.ASCII);
            return 0;
        }
        return 64;
    }
}
'@

$script:HordePaneToolPath = ""

function Get-HordePaneTool {
    # The tool's path, compiling it into a fresh folder under TEMP on first use in this process.
    if ($script:HordePaneToolPath -ne "" -and (Test-Path -LiteralPath $script:HordePaneToolPath)) { return $script:HordePaneToolPath }
    $dir = Join-Path $env:TEMP ("horde-panetool-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $dir | Out-Null
    $exe = Join-Path $dir "horde-panetool.exe"
    Add-Type -TypeDefinition $script:HordePaneToolSource -OutputAssembly $exe -OutputType ConsoleApplication
    $script:HordePaneToolPath = $exe
    return $exe
}

function Remove-HordePaneTool {
    # Remove the compiled tool's folder, if this process made one.
    if ($script:HordePaneToolPath -eq "") { return }
    $dir = Split-Path -Parent $script:HordePaneToolPath
    if ((Split-Path -Leaf $dir) -match '^horde-panetool-[0-9a-f]{32}$') { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    $script:HordePaneToolPath = ""
}

function Read-HordePaneToolArgs {
    # A standin's record: { pid; args } from its out file, or $null when it has not written one.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $pidv = 0; $list = New-Object System.Collections.Generic.List[string]
    foreach ($l in @(Get-Content -LiteralPath $Path)) {
        if ($l -like "pid=*") { $pidv = [int]$l.Substring(4) }
        elseif ($l -like "arg=*") { $list.Add([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($l.Substring(4)))) }
    }
    return [pscustomobject]@{ pid = $pidv; args = $list.ToArray() }
}

function Read-HordePaneToolEnv {
    # An env-dump's record as a hashtable, or $null when it has not written one.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $h = @{}
    foreach ($l in @(Get-Content -LiteralPath $Path)) {
        $i = $l.IndexOf("=")
        if ($i -le 0) { continue }
        $h[$l.Substring(0, $i)] = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($l.Substring($i + 1)))
    }
    return $h
}
