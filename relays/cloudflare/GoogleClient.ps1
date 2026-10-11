# relays/cloudflare/GoogleClient.ps1 - reading the Google OAuth client JSON the deploy stores as Worker
# secrets, WITHOUT EVER SAYING WHAT IS IN IT.
#
# WHAT IS TAKEN. Google issues a web client's file as { "web": { client_id, client_secret,
# redirect_uris, javascript_origins, ... } }. Sign-in (relay PR 8b) needs the id and the secret, so
# those two are what the deploy stores; the redirect addresses are read only to warn when the relay's own
# is not among them. A file of another kind ("installed", a desktop client) is refused: a phone signs in
# from a web page, which only a web client may serve.
#
# NO VALUE IS EVER IN A REFUSAL. Every refusal names the file and the field and says what is wrong in
# this file's own words; nothing read from the file is repeated, quoted or measured aloud, so a refusal
# can be printed, logged or pasted into an issue. The parser's own message is not passed on either: it
# can quote the text it choked on.
#
# THE FILE MUST LIVE OUTSIDE THE REPOSITORY: a secret file inside a working tree is one `git add` from
# being published, so one found there is refused, before it is read.
#
# No Set-StrictMode here: dot-sourced. Test-HordeModuleSettingFolder is the one test of an absolute path.

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\ModuleSettings.ps1")

# The largest client file read: Google's are under 1 KiB.
$script:HordeCloudflareRelayClientFileBytes = 65536
$script:HordeCloudflareRelayClientIdPattern = '\A[0-9]{1,32}-[a-z0-9]{1,64}\.apps\.googleusercontent\.com\z'
# A secret: printable, no space, 8 to 256 characters (Google's are 35, "GOCSPX-" and 28 more).
$script:HordeCloudflareRelayClientSecretPattern = '\A[\x21-\x7E]{8,256}\z'

function Test-HordeCloudflareRelayUnder {
    # Is -Path inside -Folder (or the folder itself)? Compared whole, case-insensitively, as Windows does.
    param([string]$Path, [string]$Folder)
    $p = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/') + "\"
    $f = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\', '/') + "\"
    return $p.StartsWith($f, [System.StringComparison]::OrdinalIgnoreCase)
}

function Read-HordeCloudflareRelayGoogleClient {
    # The client's id, secret and redirect addresses: known { clientId; clientSecret; redirectUris }, or
    # unknown with a reason that holds nothing of the file's contents.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path, [Parameter(Mandatory = $true)][string]$RepoRoot)
    if ($Path -eq "" -or -not (Test-HordeModuleSettingFolder -Path $Path)) { return (New-HordeUnknown -Reason ("the Google client file must be an absolute path (the setting googleClientFile), not '" + $Path + "'")) }
    if (Test-HordeCloudflareRelayUnder -Path $Path -Folder $RepoRoot) { return (New-HordeUnknown -Reason ("the Google client file " + $Path + " is inside the repository; a secret must live outside every working tree, so it was not read")) }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return (New-HordeUnknown -Reason ("there is no Google client file at " + $Path + ": download the web client's JSON from the Google Cloud console there, or name it in the setting googleClientFile")) }
    $info = New-Object System.IO.FileInfo($Path)
    if ($info.Length -gt $script:HordeCloudflareRelayClientFileBytes) { return (New-HordeUnknown -Reason ("the Google client file " + $Path + " is larger than a client file is (" + $script:HordeCloudflareRelayClientFileBytes + " bytes at most)")) }
    $parsed = $null
    try { $parsed = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $parsed = $null }
    if ($null -eq $parsed -or $parsed -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ("the Google client file " + $Path + " is not a JSON object")) }
    $web = $parsed.PSObject.Properties["web"]
    if ($null -eq $web -or $web.Value -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ("the Google client file " + $Path + " is not a web application's client (it has no ""web"" section); a phone signs in from a web page")) }
    $w = $web.Value
    $id = $w.PSObject.Properties["client_id"]
    if ($null -eq $id -or $id.Value -isnot [string] -or $id.Value -cnotmatch $script:HordeCloudflareRelayClientIdPattern) { return (New-HordeUnknown -Reason ("the Google client file " + $Path + " has no web.client_id of the form <digits>-<letters and digits>.apps.googleusercontent.com")) }
    $secret = $w.PSObject.Properties["client_secret"]
    if ($null -eq $secret -or $secret.Value -isnot [string] -or $secret.Value -cnotmatch $script:HordeCloudflareRelayClientSecretPattern) { return (New-HordeUnknown -Reason ("the Google client file " + $Path + " has no web.client_secret of 8 to 256 printable characters with no space")) }
    $uris = @()
    $r = $w.PSObject.Properties["redirect_uris"]
    if ($null -ne $r -and $null -ne $r.Value) { $uris = @(@($r.Value) | Where-Object { $_ -is [string] }) }
    return (New-HordeKnown -Value ([pscustomobject]@{ clientId = $id.Value; clientSecret = $secret.Value; redirectUris = $uris }))
}
