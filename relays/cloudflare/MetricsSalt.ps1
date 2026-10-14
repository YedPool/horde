# relays/cloudflare/MetricsSalt.ps1 - reading the relay's METRICS SALT, the Worker secret METRICS_SALT the
# deploy stores (Deploy.ps1), WITHOUT EVER SAYING WHAT IS IN IT.
#
# WHAT IT IS FOR (worker/metrics.js, PER ACCOUNT, PER HOUR): the relay counts each account's requests an
# hour under the first 16 hex of HMAC-SHA-256(salt, account id), never under the id itself. Account ids
# are not secret - a Google account's is in every id token it signs - so without a secret salt anyone
# could hash every id they know and read whose rows are whose. With it, they cannot. Rotating it only
# breaks the hashes' continuity across the change (yesterday's hash is not today's); it exposes nothing.
#
# WHERE IT LIVES: a file of its own, outside every repository, as the Google client file does
# (GoogleClient.ps1) - the setting metricsSaltFile, or by default .horde-secrets\relay-metrics-salt.txt in
# the user's profile (Settings.ps1). A deploy without it REFUSES, in plain words that say how to make one:
# a relay deployed without a salt would count no account at all, and nobody would notice.
#
# WHAT THE FILE MUST HOLD: the salt and nothing else - 32 to 256 printable ASCII characters, none of them
# a space, with no byte order mark and no line end or other whitespace before or after it. It is handed
# to wrangler's standard input byte for byte (Deploy.ps1), so a line end left in the file would become
# part of the secret, and a byte order mark three bytes of it: refused, not trimmed, so the file always
# says exactly what the Worker holds (the same rule the deploy holds every secret to).
#
# NO VALUE IS EVER IN A REFUSAL, and the file's length is not said either: every refusal names the file
# and says what is wrong in this file's own words.
#
# No Set-StrictMode here: dot-sourced.

. (Join-Path $PSScriptRoot "GoogleClient.ps1")

$script:HordeCloudflareRelayMetricsSaltBytes = 4096
$script:HordeCloudflareRelayMetricsSaltPattern = '\A[\x21-\x7E]{32,256}\z'
$script:HordeCloudflareRelayMetricsSaltHowTo = "put a new random salt there: 32 to 256 printable ASCII characters with no spaces, and nothing else in the file - no line end, no byte order mark (for example, in PowerShell: `$b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes(`$b); [IO.File]::WriteAllText('<that file>', (-join (`$b | ForEach-Object { `$_.ToString('x2') })))"

function Read-HordeCloudflareRelayMetricsSalt {
    # The salt: known, the text, or unknown with a reason that holds nothing of the file's contents.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path, [Parameter(Mandatory = $true)][string]$RepoRoot)
    if ($Path -eq "" -or -not (Test-HordeModuleSettingFolder -Path $Path)) { return (New-HordeUnknown -Reason ("the metrics salt file must be an absolute path (the setting metricsSaltFile), not '" + $Path + "'")) }
    if (Test-HordeCloudflareRelayUnder -Path $Path -Folder $RepoRoot) { return (New-HordeUnknown -Reason ("the metrics salt file " + $Path + " is inside the repository; a secret must live outside every working tree, so it was not read")) }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return (New-HordeUnknown -Reason ("there is no metrics salt file at " + $Path + ": the deploy stores it as the Worker secret METRICS_SALT, which the relay's request metrics need to count accounts without naming them; " + $script:HordeCloudflareRelayMetricsSaltHowTo)) }
    $info = New-Object System.IO.FileInfo($Path)
    if ($info.Length -gt $script:HordeCloudflareRelayMetricsSaltBytes) { return (New-HordeUnknown -Reason ("the metrics salt file " + $Path + " is larger than a salt is; " + $script:HordeCloudflareRelayMetricsSaltHowTo)) }
    $bytes = $null
    try { $bytes = [System.IO.File]::ReadAllBytes($Path) } catch { return (New-HordeUnknown -Reason ("the metrics salt file " + $Path + " could not be read")) }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return (New-HordeUnknown -Reason ("the metrics salt file " + $Path + " begins with a byte order mark, which would become part of the secret; " + $script:HordeCloudflareRelayMetricsSaltHowTo)) }
    foreach ($b in $bytes) { if ($b -gt 0x7E -or ($b -lt 0x20 -and $b -ne 0x09 -and $b -ne 0x0A -and $b -ne 0x0D)) { return (New-HordeUnknown -Reason ("the metrics salt file " + $Path + " holds a character that is not printable ASCII; " + $script:HordeCloudflareRelayMetricsSaltHowTo)) } }
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    if ($text -ne $text.Trim()) { return (New-HordeUnknown -Reason ("the metrics salt file " + $Path + " has whitespace or a line end before or after the salt, which would become part of the secret; " + $script:HordeCloudflareRelayMetricsSaltHowTo)) }
    if ($text -cnotmatch $script:HordeCloudflareRelayMetricsSaltPattern) { return (New-HordeUnknown -Reason ("the metrics salt file " + $Path + " does not hold one salt of 32 to 256 printable ASCII characters with no spaces; " + $script:HordeCloudflareRelayMetricsSaltHowTo)) }
    return (New-HordeKnown -Value $text)
}
