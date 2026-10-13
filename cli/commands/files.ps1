$HordeCommand = @{
    name    = "files"
    group   = "files"
    usage   = "files share <path> -Title <one line> [-Editable] [-Force] | files list"
    summary = "files a session shares for the founder to read. share: keep one file - Markdown, text, JSON, HTML, a PNG, JPEG, GIF or WebP picture, or a PDF, up to the size the setting maxFileBytes allows - under a title, and print its id and version; sharing the same file again from the same session, however its path is written, makes the next version of the same file (-Editable records that the founder may change it). A missing file, a link, a device, a stream inside a file, a file on a network share, a file over the size, a type that is not allowed or whose first bytes are not its format's, and text that is not UTF-8 or a .json file that is not JSON are each refused with the reason. So is a file where secrets are kept. One in Horde's own home, in a .horde or .horde-secrets folder, or in the user's SSH folder is refused whatever is said, and so is an agent harness's own file - the one it keeps beside its folder - with any file beside it whose name begins with that file's name. One in a folder an agent harness keeps its own files in, and one named as a file of secrets is - a name holding credential, secret, key, password, passwd, passphrase, mnemonic, kubeconfig or .env, or having as a whole word token, auth, oauth, cred, private, wallet, cookie, recovery, env, pem, pwd, totp, seed, jwt, vault, 2fa or the name of a key file - are refused unless -Force says the file holds no secret; inside a harness's folder -Force shares other files and never one named so. A text file is also looked into: one holding the first line of a private key is refused whatever is said, and one holding a token of a known shape, or a secret written under the name client_secret, private_key, refresh_token, access_token, api_key or password, unless -Force is given; a picture and a PDF are not looked into. BY DESIGN: with -Force no shape of a token is looked for at all, only the first line of a private key; and with -Force a file whose name holds no such word is shared even when where the harnesses keep their files cannot be told. KNOWN LIMIT: a hard link, a second name made on purpose for a file in one of those places, is not seen, and the file is shared by that name. KNOWN LIMIT: a credentials file that one of Horde's settings names, kept outside those places under a name that says nothing, is known only by what it holds: one whose secret is written under another name than those six is shared. list: every version shared - id, version, type, size, the session that shared it, when, and its title. A shared file is never changed and never removed"
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
