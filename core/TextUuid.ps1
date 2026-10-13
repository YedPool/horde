# core/TextUuid - one recipe for an id made from text: the same text, the same lowercase uuid.
#
# WHY ITS OWN FILE. A sender that must not post twice names its message by what the message is about, so
# a retry - after a crash, or on the next pass - is the same message and a messenger keeps it as one
# (messengers/Port.ps1, idempotent.post). The decisions doorbell made its notice's id this way first
# (decisions/Notify.ps1); the restore source needed the same (core/RestoreSource.ps1) and copied it,
# because core does not load decisions. The review of the wake watcher (PR #207, 2026-10-13) asked for
# one definition: two copies of a recipe drift, and an id that drifts is a message posted twice.
#
# THE RECIPE: the SHA-256 of the text's UTF-8 bytes, its first 32 hex digits, grouped 8-4-4-4-12. It is
# an id of that shape, not a version-numbered UUID; the link's schema asks only for the shape.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

function ConvertTo-HordeTextUuid {
    param([Parameter(Mandatory = $true)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hex = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString("x2") }) } finally { $sha.Dispose() }
    return ($hex.Substring(0, 8) + "-" + $hex.Substring(8, 4) + "-" + $hex.Substring(12, 4) + "-" + $hex.Substring(16, 4) + "-" + $hex.Substring(20, 12))
}
