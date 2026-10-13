# Mutations of cli/commands/files.ps1, the `horde files` command. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-command.psd1
# Each makes the command take what it must refuse, or say or exit wrongly; test\test-files-cli.ps1,
# which runs the real command as its own process, must fail for every one. One run of that suite
# starts about 100 processes (measured 2026-10-13 on a throttled machine: about 100 s).
@{
    Target = "cli\commands\files.ps1"
    Suite  = "test\test-files-cli.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "list-takes-shares-flags-in-silence"
           Find = 'foreach ($flag in @("Path", "Title", "Editable", "Force")) { if ($PSBoundParameters.ContainsKey($flag)) {'
           Replace = 'foreach ($flag in @()) { if ($PSBoundParameters.ContainsKey($flag)) {' }
        @{ Name = "list-given-a-path-not-refused"
           Find = 'foreach ($flag in @("Path", "Title", "Editable", "Force")) {'
           Replace = 'foreach ($flag in @("Title", "Editable", "Force")) {' }
        @{ Name = "list-given-force-not-refused"
           Find = 'foreach ($flag in @("Path", "Title", "Editable", "Force")) {'
           Replace = 'foreach ($flag in @("Path", "Title", "Editable")) {' }
        @{ Name = "force-not-handed-on"
           Find = '-Editable:$Editable -Force:$Force'
           Replace = '-Editable:$Editable' }
        @{ Name = "force-given-whatever-was-typed"
           Find = '-Editable:$Editable -Force:$Force'
           Replace = '-Editable:$Editable -Force' }
        @{ Name = "share-with-no-path-not-named"
           Find = 'if ("$Path" -eq "") { throw "share needs the path of the file to share" }'
           Replace = '' }
        @{ Name = "share-with-no-title-not-named"
           Find = 'if (-not $PSBoundParameters.ContainsKey("Title")) { throw "share needs -Title, the one line the file is listed under" }'
           Replace = '' }
        @{ Name = "refused-share-exits-zero"
           Find = 'if ($done.outcome -cne "shared") { throw ("not shared: " + $done.reason) }'
           Replace = 'if ($done.outcome -cne "shared") { Write-Output ("not shared: " + $done.reason); return }' }
        @{ Name = "editable-not-handed-on"
           Find = '$done = Add-HordeFilesShare -Path $Path -Title $Title -Editable:$Editable'
           Replace = '$done = Add-HordeFilesShare -Path $Path -Title $Title' }
        @{ Name = "unreadable-list-exits-zero"
           Find = 'if ($list.state -ceq "unknown") { throw $list.reason }'
           Replace = '' }
        @{ Name = "share-does-not-print-its-version"
           Find = '"shared " + $r.fileId + " version " + $r.version + ": "'
           Replace = '"shared " + $r.fileId + ": "' }
    )
}
