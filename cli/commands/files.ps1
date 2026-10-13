$HordeCommand = @{
    name    = "files"
    group   = "files"
    usage   = "files share <path> -Title <one line> [-Editable] [-Force] | files list"
    summary = "files a session shares for the founder to read. share: keep one file - Markdown, text, JSON, HTML, a PNG, JPEG, GIF or WebP picture, or a PDF, up to the size the setting maxFileBytes allows - under a title, and print its id and version; sharing the same file again from the same session, however its path is written, makes the next version of the same file (-Editable records that the founder may change it). A missing file, a link, a device, a stream inside a file, a file on a network share, a file over the size, a type that is not allowed or whose first bytes are not its format's, and text that is not UTF-8 or a .json file that is not JSON are each refused with the reason. So is a file where secrets are kept: one in the user's SSH folder or in a folder an agent harness keeps its own files in, and one whose name holds credential, secret, token, key, password or .env, are refused unless -Force says the file holds no secret; one in Horde's own home or in a .horde-secrets folder is refused whatever is said. list: every version shared - id, version, type, size, the session that shared it, when, and its title. A shared file is never changed and never removed"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("share", "list")][string]$Verb,
            [Parameter(Position = 1)][string]$Path,
            [string]$Title,
            [switch]$Editable,
            [switch]$Force
        )
        # A flag meant for the other verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        if ($Verb -eq "list") {
            foreach ($flag in @("Path", "Title", "Editable", "Force")) { if ($PSBoundParameters.ContainsKey($flag)) { throw ("list takes nothing more; " + $(if ($flag -eq "Path") { "'" + $Path + "'" } else { "-" + $flag }) + " belongs to files share") } }
        }
        # Loaded here, in the command's own scope (cli/commands/metrics.ps1 says why). This block only
        # hands the arguments on: what is refused, and what a record holds, is decided in files/.
        . (Join-Path (Get-HordeRoot) "files\Share.ps1")
        if ($Verb -eq "list") {
            $list = Get-HordeFilesList
            Format-HordeFilesList -List $list | ForEach-Object { Write-Output $_ }
            # Printed first, then failed: a list that could not be read is a non-zero exit for a script.
            if ($list.state -ceq "unknown") { throw $list.reason }
            return
        }
        if ("$Path" -eq "") { throw "share needs the path of the file to share" }
        if (-not $PSBoundParameters.ContainsKey("Title")) { throw "share needs -Title, the one line the file is listed under" }
        $done = Add-HordeFilesShare -Path $Path -Title $Title -Editable:$Editable -Force:$Force
        if ($done.outcome -cne "shared") { throw ("not shared: " + $done.reason) }
        $r = $done.record
        Write-Output ("shared " + $r.fileId + " version " + $r.version + ": " + $r.title + " (" + $r.type + ", " + $r.size + " bytes)")
    }
}
