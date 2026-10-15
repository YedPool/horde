$HordeCommand = @{
    name    = "notify"
    group   = "relay"
    usage   = "notify -Text <one line>"
    summary = "tell the founder something on his phone, at once, as a notice in the app - run it only when he asked this session to tell him (""notify me when X is done""). The sender is this session's own label, worked out from the session the command runs inside and never taken from the command line, so no session can send as another; run outside a session it is refused. No switch on the phone mutes it. A text that looks like it holds a secret is not sent: the founder is told that this session sent a notice whose words stayed at the machine. One session may send the setting perHour notices (10) in one clock hour; the next one cuts it off until the hour ends, and the founder is told that once"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
        )
        # Loaded here, in the command's own scope (cli/commands/metrics.ps1 says why). This block only hands
        # the line on: who is asking is proven in notices/Sender.ps1, and what becomes a notice is decided in
        # notices/Decide.ps1, the one place that decides it.
        . (Join-Path (Get-HordeRoot) "notices\Sender.ps1")
        . (Join-Path (Get-HordeRoot) "notices\Decide.ps1")
        $who = Resolve-HordeNoticeSender
        if (-not $who.ok) { throw $who.reason }
        $r = Submit-HordeNotify -Sender $who -Text $Text
        switch -CaseSensitive ($r.outcome) {
            "sent" { Write-Output ("sent to the founder's phone as notice " + $r.notice.n + ", from " + $r.notice.from) }
            "sent-refused" { Write-Output ("notice " + $r.notice.n + " from " + $r.notice.from + " was sent without its words: " + $r.reason); throw "the text was not sent" }
            default { throw $r.reason }
        }
    }
}
