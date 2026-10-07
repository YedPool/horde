# decisions/Window.ps1 - `horde decisions open`: the list of questions in a window Horde owns, standing
# beside the terminal window of the session that keeps the list.
#
# THIS FILE ONLY PUTS FOUR PARTS TOGETHER, and is the only place that knows all four (decisions design
# 2026-10-06, "how it is put together so it can grow"; attach design of the same day):
#   A. a surface shows a page        surfaces/Port.ps1 - asked for by what it can do, never by name
#   B. a window follows a window     platform/windows/WindowFollow.ps1 - two native handles
#   C. a session's terminal window   core/SessionSeat.ps1 (who holds the role, and where it sits) and
#                                    core/HostWindow.ps1 (the terminal's own adapter names the window)
#   D. the pages                     decisions/page (the list), fleet/panel (the fleet panel), and
#                                    decisions/window (the frame the two are put together in), with
#                                    fleet/StatusPanel.ps1 reading what the panel shows
# None of the four knows another. A later way of showing the list - a file for a phone, a view across
# a link - is another surface under the same bridge, and nothing here but the choice of surface moves.
#
# WHAT THE PAGE MAY ASK is the closed list below, five requests, and nothing else (surfaces/Port.ps1
# checks every message before a handler sees it): kinds, list, fleet, attachment, rendered. The first
# two are the decisions operations of the same names, called through decisions/Operations.ps1's one
# entry point and handed on as they came: THIS FILE READS NO RECORD OF THE STORE. READ-ONLY in this
# slice: nothing the page can ask changes the list.
#
# THE LIST REDRAWS WHEN THE STORE CHANGES. The store's folder is watched (it may not exist yet: it is
# made by the first question, and the watch starts when it appears). Changes are gathered for 400 ms,
# because one command writes one record and a burst of them should be one redraw; then the list is
# asked for again and pushed to the page ONLY IF it differs from what the page was last given.
#
# ATTACHED, OR SAYING WHY NOT. The window stands beside the terminal window of the session that holds
# the role of warchief, found from the fleet's records and that terminal's own listing. When no such
# window can be proven it stands free, as an ordinary window, and its page says "not attached:" and
# the reason. A window is never guessed. -Hidden is never attached: it stands where nobody sees it.
#
# ONE WINDOW PER HOME. A second `open` finds the first by a named mutex, asks it to come forward and
# returns. The name carries a fingerprint of HORDE_HOME, so a test's window on a home of its own
# never meets the real one.
#
# THE COMMAND STAYS UNTIL THE WINDOW IS CLOSED, and exits 0 then. A caller that wants its prompt back
# starts it in the background. (A start at sign-in, and a command that returns at once, are later.)
#
# WHAT IT WRITES: the web engine's own profile, under <HordeHome>\cache\decisions-window, and the
# files -Report and -Picture name. Nothing else, and never the store.
#
# -Picture SAVES A PICTURE OF THE PAGE AS IT IS DRAWN, once, when the page has reported what it drew
# and been quiet for a moment: so that what a person would see can be looked at by a session, or by a
# scenario, without that person. It is the surface's own capture; the page cannot ask for it.
#
# A CALLBACK TAKES WHAT IT NEEDS FROM ITS $State, never from a local of the function that wrote it
# (surfaces/Port.ps1): the file watcher's handlers, which no surface calls, read the same object from
# $script:HordeDecisionWindow.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Operations.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "surfaces\Port.ps1")
foreach ($surfaceFile in @(Get-HordeSurfaceFiles)) { . $surfaceFile }
. (Join-Path (Split-Path -Parent $PSScriptRoot) "platform\windows\WindowFollow.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\SessionSeat.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\HostWindow.ps1")
foreach ($finderFile in @(Get-HordeHostWindowFinderFiles)) { . $finderFile }
. (Join-Path (Split-Path -Parent $PSScriptRoot) "fleet\StatusPanel.ps1")

# What a surface must be able to do to show this window.
$script:HordeDecisionWindowNeeds = @("page.local", "page.locked", "requests.closed", "push", "window.native")
# How long the page must have said nothing new before its picture is taken: a picture of a page that
# is still being drawn shows half of it.
$script:HordeDecisionWindowSettleMs = 700
# The role whose session the window stands beside: the one that keeps the list.
$script:HordeDecisionWindowRole = "warchief"
# How long changes to the store are gathered before the list is asked for again.
$script:HordeDecisionWindowQuietMs = 400
# How often the Orcs' status files are read again. They are written when an Orc's work changes, not
# on a timer, and the panel shows each file's age, so a few seconds late is not wrong.
$script:HordeDecisionWindowFleetMs = 5000
# How often the window is placed again whatever Windows reported: a net under the reports, not the
# mechanism (platform/windows/WindowFollow.ps1 places on every report).
$script:HordeDecisionWindowFollowMs = 1000
$script:HordeDecisionWindow = $null

function Get-HordeDecisionWindowName {
    # The name the one window of -HordeHome is known by to a second `open`: fixed words and a
    # fingerprint of the home's path, compared as Windows compares paths.
    param([Parameter(Mandatory = $true)][string]$HordeHome)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([System.IO.Path]::GetFullPath($HordeHome).TrimEnd('\').ToLowerInvariant())) | ForEach-Object { $_.ToString("x2") }) }
    finally { $sha.Dispose() }
    return ("horde-decisions-window-" + $hash.Substring(0, 16))
}

function Get-HordeDecisionWindowTitle {
    # The window's title from a list answer's record: "Open decisions: 22, 16 waiting". When the list
    # could not be had, the title says that, never a count of nothing.
    param($Record)
    if ($null -eq $Record -or "$($Record.state)" -cne "known" -or "$($Record.value.outcome)" -cne "done") { return "Open decisions: the list could not be read" }
    $open = @($Record.value.questions | Where-Object { "$($_.state)" -ceq "open" })
    $waiting = @($open | Where-Object { @($_.waiting).Count -gt 0 }).Count
    return ("Open decisions: " + $open.Count + ", " + $waiting + " waiting")
}

function Get-HordeDecisionWindowRecord {
    # One decisions operation's answer as the plain record a page is handed: { state; value; reason },
    # core/Tristate.ps1's stored form without the time it was read, so that the same list read twice
    # is the same record.
    param([Parameter(Mandatory = $true)][string]$Operation, $Request = @{})
    $answer = Invoke-HordeDecision -Operation $Operation -Request $Request
    $record = ConvertTo-HordeAnswerRecord -Answer $answer
    return [pscustomobject]@{ state = "$($record.state)"; value = $record.value; reason = "$($record.reason)" }
}

function Get-HordeDecisionWindowList {
    # The whole list, every state: the page filters, and a closed question must not need a second request.
    return (Get-HordeDecisionWindowRecord -Operation "list" -Request @{ state = "all" })
}

function Get-HordeDecisionWindowFleet {
    # The fleet's status as the panel is handed it, and the text it is compared by. An Orc's file ages
    # every second without changing; compared with its age in whole minutes, the panel is redrawn when
    # something was written or a minute turned, not every time it is read.
    $status = Get-HordeFleetStatus
    $coarse = @($status.orcs | ForEach-Object { "" + $_.folder + "|" + $_.written + "|" + $_.orc + "|" + $_.lane + "|" + $_.doing + "|" + $_.finished + "|" + $_.blocked + "|" + $_.blockedBy + "|" + (@($_.problems) -join ";") + "|" + [Math]::Floor($_.ageSeconds / 60) })
    return [pscustomobject]@{ status = $status; signature = ($status.state + "|" + $status.reason + "|" + ($coarse -join "`n")) }
}

function Resolve-HordeDecisionWindowAttachment {
    # Which window to stand beside, as { attached; handle; reason }: attached only when the session
    # that holds the role has a seat and a terminal's adapter proves that seat's window (header,
    # ATTACHED, OR SAYING WHY NOT). Everything else is not attached, with the reason in words.
    param([switch]$Hidden)
    $free = { param([string]$Why) return [pscustomobject]@{ attached = $false; handle = [long]0; reason = $Why } }
    if ($Hidden) { return (& $free "it was opened hidden, and a hidden window stands beside nothing") }
    $seat = $null
    try { $seat = Get-HordeRoleSeat -Role $script:HordeDecisionWindowRole } catch { return (& $free ("the fleet's session records could not be read: " + $_.Exception.Message)) }
    if ($seat.state -ceq "absent") { return (& $free ("no session holds the role of " + $script:HordeDecisionWindowRole + ", so there is no terminal window to stand beside")) }
    if ($seat.state -cne "known") { return (& $free $seat.reason) }
    $window = Find-HordeSessionWindow -Seat $seat.value
    if ($window.state -cne "known") { return (& $free $window.reason) }
    return [pscustomobject]@{ attached = $true; handle = [long]$window.value.handle; reason = "" }
}

function New-HordeDecisionWindowBridge {
    # THE CLOSED LIST of what the page may ask, and of what it may be pushed (header). Each handler
    # reads the state it is handed; none takes anything from here.
    return (New-HordeSurfaceBridge -Events @("list-changed", "fleet-changed", "attachment-changed", "show") -Requests ([ordered]@{
        "kinds" = @{ run = { param($Arguments, $State, $Window) return (Get-HordeDecisionWindowRecord -Operation "kinds") } }
        "list" = @{ run = { param($Arguments, $State, $Window)
            $record = Get-HordeDecisionWindowList
            # What the page now has, so that the next change is compared with it and not pushed twice.
            $State.listJson = ConvertTo-HordeSurfaceJson -Value $record
            $State.title = Get-HordeDecisionWindowTitle -Record $record
            if ($null -ne $Window) { & $Window.setTitle $State.title }
            $State.reportDue = $true
            return $record } }
        "fleet" = @{ run = { param($Arguments, $State, $Window)
            $fleet = Get-HordeDecisionWindowFleet
            $State.fleetSignature = $fleet.signature
            return $fleet.status } }
        "attachment" = @{ run = { param($Arguments, $State, $Window) return [pscustomobject]@{ attached = [bool]$State.attachment.attached; reason = "$($State.attachment.reason)" } } }
        # What is on screen, in numbers: how a script checks the window without looking at it (-Report).
        "rendered" = @{
            args = @{
                rows = @{ type = "integer"; most = 100000 }; open = @{ type = "integer"; most = 100000 }; closed = @{ type = "integer"; most = 100000 }
                waiting = @{ type = "integer"; most = 100000 }; expanded = @{ type = "integer"; most = 100000 }
                entries = @{ type = "integer"; most = 1000 }; written = @{ type = "integer"; most = 1000 }
                filter = @{ type = "string"; most = 16 }; picked = @{ type = "string"; most = 80 }
            }
            run = { param($Arguments, $State, $Window)
                $State.rendered = [pscustomobject]@{ rows = $Arguments["rows"]; open = $Arguments["open"]; closed = $Arguments["closed"]; waiting = $Arguments["waiting"]; expanded = $Arguments["expanded"]
                                                    entries = $Arguments["entries"]; written = $Arguments["written"]; filter = $Arguments["filter"]; picked = $Arguments["picked"] }
                $State.reports = [int]$State.reports + 1
                $State.lastReportAt = [datetime]::UtcNow
                $State.reportDue = $true
                return $true }
        }
    }))
}

function New-HordeDecisionWindowState {
    # The one object every callback and handler of an open window reads and writes.
    param([string]$ReportPath = "", $Attachment = $null, [datetime]$Now = [datetime]::UtcNow, [string]$PicturePath = "")
    if ($null -eq $Attachment) { $Attachment = [pscustomobject]@{ attached = $false; handle = [long]0; reason = "" } }
    $storeRoot = ""
    try { $storeRoot = Get-HordeDecisionStoreRoot } catch { $storeRoot = "" }
    return [pscustomobject]@{
        bridge = (New-HordeDecisionWindowBridge); storeRoot = $storeRoot; watcher = $null; dirtyAt = $null
        listJson = ""; title = ""; fleetSignature = ""; fleetDueAt = $Now; followDueAt = $Now
        attachment = $Attachment; followed = $false; lost = $false
        reportPath = $ReportPath; reportDue = $true; rendered = $null; reports = 0; pushes = 0; changes = 0; errors = $null
        showEvent = $null; handle = [long]0; openedAt = $Now
        picturePath = $PicturePath; pictureAsked = $false; pictureSeen = $false; lastReportAt = $null
    }
}

function Set-HordeDecisionWindowDirty {
    # Called for every change in the store's folder, on the window's own thread: note when, and no more.
    $s = $script:HordeDecisionWindow
    if ($null -ne $s) { $s.dirtyAt = [datetime]::UtcNow; $s.changes = [int]$s.changes + 1 }
}

function Start-HordeDecisionWindowWatch {
    # Watch the store's folder, once it exists. Its events are marshalled through -Sync to the window's
    # thread, where the handlers below - one line each, reading the script's state - only note the time.
    #
    # NEVER WITHOUT -Sync. A watcher with nothing to marshal through calls its handler on a thread of
    # its own, where PowerShell has no way to run a script block, and the process ends at once with no
    # error to read (measured 2026-10-06: this file's suite stopped mid-run, exit 2, at the first record
    # written after a watch was started bare). So with no -Sync there is no watch.
    param([Parameter(Mandatory = $true)]$State, $Sync = $null)
    if ($null -eq $Sync) { return $false }
    if ($null -ne $State.watcher -or $State.storeRoot -eq "" -or -not (Test-Path -LiteralPath $State.storeRoot -PathType Container)) { return $false }
    $watcher = New-Object System.IO.FileSystemWatcher($State.storeRoot, "*.json")
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
    $watcher.SynchronizingObject = $Sync
    $noted = { Set-HordeDecisionWindowDirty }
    $watcher.add_Created($noted); $watcher.add_Changed($noted); $watcher.add_Deleted($noted); $watcher.add_Renamed($noted)
    $watcher.EnableRaisingEvents = $true
    $State.watcher = $watcher
    # Whatever was written between the page's first list and this moment is picked up by one refresh.
    $State.dirtyAt = [datetime]::UtcNow
    return $true
}

function Write-HordeDecisionWindowReport {
    # -Report's file: one JSON object saying what the window shows, replaced whole. Written beside
    # itself and moved into place, so a reader never finds half of it.
    param([Parameter(Mandatory = $true)]$State)
    if ($State.reportPath -eq "") { return }
    $follow = Get-HordeWindowFollow
    $placed = $null
    if ($null -ne $follow -and $null -ne $follow.placed) { $placed = [ordered]@{ left = $follow.placed.left; top = $follow.placed.top; width = $follow.placed.width; height = $follow.placed.height } }
    $report = [ordered]@{
        schemaVersion = 1; pid = $PID; handle = [long]$State.handle; title = $State.title
        attachment = [ordered]@{ attached = [bool]$State.attachment.attached; reason = "$($State.attachment.reason)"; target = [long]$State.attachment.handle; placed = $placed }
        rendered = $State.rendered; reports = [int]$State.reports; pushes = [int]$State.pushes
        picture = [ordered]@{ path = "$($State.picturePath)"; asked = [bool]$State.pictureAsked; saved = [bool]($State.picturePath -ne "" -and (Test-Path -LiteralPath $State.picturePath -PathType Leaf)) }
        refused = [int]$State.bridge.refused; watching = ($null -ne $State.watcher); changes = [int]$State.changes
        errors = @($State.errors | Where-Object { $null -ne $_ } | Select-Object -Last 5 | ForEach-Object { "" + $_ })
        secondsToFirstReport = $null
    }
    if ($State.reports -ge 1 -and $null -eq $State.PSObject.Properties["firstReportAt"]) { Add-Member -InputObject $State -NotePropertyName firstReportAt -NotePropertyValue ([datetime]::UtcNow) }
    if ($null -ne $State.PSObject.Properties["firstReportAt"]) { $report["secondsToFirstReport"] = [Math]::Round(($State.firstReportAt - $State.openedAt).TotalSeconds, 2) }
    $text = ConvertTo-HordeSurfaceJson -Value $report
    $temp = $State.reportPath + "." + $PID + ".tmp"
    [System.IO.File]::WriteAllText($temp, $text, (New-Object System.Text.UTF8Encoding($false)))
    # [NullString]::Value, not $null: PowerShell hands a .NET string parameter "" for $null, and Replace
    # read "" as the name of a backup file and threw "The path is not of a legal form" on every write
    # after the first (measured 2026-10-06: the report stayed at its first version while the window ran on).
    if (Test-Path -LiteralPath $State.reportPath -PathType Leaf) { [System.IO.File]::Replace($temp, $State.reportPath, [NullString]::Value) } else { [System.IO.File]::Move($temp, $State.reportPath) }
    $State.reportDue = $false
}

function Update-HordeDecisionWindowList {
    # Ask for the list again and push it to the page if it is not what the page has. Returns whether
    # it was pushed.
    param([Parameter(Mandatory = $true)]$State, $Window = $null)
    $record = Get-HordeDecisionWindowList
    $json = ConvertTo-HordeSurfaceJson -Value $record
    if ($json -ceq $State.listJson) { return $false }
    $State.listJson = $json
    $State.title = Get-HordeDecisionWindowTitle -Record $record
    $State.pushes = [int]$State.pushes + 1
    $State.reportDue = $true
    if ($null -ne $Window) {
        & $Window.setTitle $State.title
        & $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "list-changed" -Value $record)
    }
    return $true
}

function Invoke-HordeDecisionWindowOpened {
    # The surface's engine is up. Stand beside the terminal window if one was proven, and start watching.
    param($Window, $State)
    $State.handle = [long]$Window.handle
    $State.errors = $Window.errors
    if ($State.attachment.attached) {
        $follow = Start-HordeWindowFollow -Target $State.attachment.handle -Follower $Window.handle
        if ($follow.state -ceq "following") { $State.followed = $true }
        else { $State.attachment = [pscustomobject]@{ attached = $false; handle = [long]0; reason = $follow.reason } }
    }
    [void](Start-HordeDecisionWindowWatch -State $State -Sync $Window.sync)
    $State.reportDue = $true
}

function Invoke-HordeDecisionWindowTick {
    # Every quarter second, on the window's thread: a second `open` asking to be seen; the store's
    # folder appearing; a gathered change; the Orcs' files; the placement's safety net; the report.
    param($Window, $State)
    $now = [datetime]::UtcNow
    if ($null -ne $State.showEvent -and $State.showEvent.WaitOne(0)) { & $Window.show }
    if ($null -eq $State.watcher) { [void](Start-HordeDecisionWindowWatch -State $State -Sync $Window.sync) }
    if ($null -ne $State.dirtyAt -and ($now - $State.dirtyAt).TotalMilliseconds -ge $script:HordeDecisionWindowQuietMs) {
        $State.dirtyAt = $null
        [void](Update-HordeDecisionWindowList -State $State -Window $Window)
    }
    if ($now -ge $State.fleetDueAt) {
        $State.fleetDueAt = $now.AddMilliseconds($script:HordeDecisionWindowFleetMs)
        $fleet = Get-HordeDecisionWindowFleet
        if ($fleet.signature -cne $State.fleetSignature) {
            $State.fleetSignature = $fleet.signature
            & $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "fleet-changed" -Value $fleet.status)
        }
    }
    if ($State.followed -and -not $State.lost -and $now -ge $State.followDueAt) {
        $State.followDueAt = $now.AddMilliseconds($script:HordeDecisionWindowFollowMs)
        if ((Update-HordeWindowFollow) -ceq "lost") {
            # The window it stood beside is gone. It stops following and stands where it is, as a free
            # window that says so; finding the session's next window is a later slice's.
            Stop-HordeWindowFollow
            $State.followed = $false
            $State.lost = $true
            $State.attachment = [pscustomobject]@{ attached = $false; handle = [long]0; reason = "the terminal window it stood beside has been closed" }
            & $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "attachment-changed" -Value ([pscustomobject]@{ attached = $false; reason = $State.attachment.reason }))
        }
        $State.reportDue = $true
    }
    # -Picture: once, when the page has reported what it drew and has then been quiet for a moment.
    if ($State.picturePath -ne "" -and -not $State.pictureAsked -and $null -ne $State.lastReportAt -and ($now - $State.lastReportAt).TotalMilliseconds -ge $script:HordeDecisionWindowSettleMs) {
        $State.pictureAsked = [bool](& $Window.capture $State.picturePath)
        $State.reportDue = $true
    }
    if ($State.pictureAsked -and -not $State.pictureSeen -and (Test-Path -LiteralPath $State.picturePath -PathType Leaf)) { $State.pictureSeen = $true; $State.reportDue = $true }
    if ($State.reportDue) { Write-HordeDecisionWindowReport -State $State }
}

function Invoke-HordeDecisionWindowClosed {
    param($Window, $State)
    if ($null -ne $State.watcher) { try { $State.watcher.EnableRaisingEvents = $false; $State.watcher.Dispose() } catch { }; $State.watcher = $null }
    Stop-HordeWindowFollow
}

function Open-HordeDecisionWindow {
    # `horde decisions open`. Writes its lines as it goes and returns when the window has been closed;
    # throws, in words, when the window could not be shown. -Report is a file to keep a one-line account
    # of what the window shows in; -Picture a .png to save a picture of the page in; -Hidden opens it
    # where nobody sees it.
    param([switch]$Hidden, [string]$Report = "", [string]$Picture = "")
    $hordeHome = Get-HordeHome
    $picturePath = ""
    if ($Picture -ne "") {
        $picturePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Picture)
        if ([System.IO.Path]::GetExtension($picturePath) -ine ".png") { throw "-Picture names the file a picture of the window is saved in, and it must end .png" }
    }
    $reportPath = ""
    if ($Report -ne "") { $reportPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Report) }
    $name = Get-HordeDecisionWindowName -HordeHome $hordeHome
    $first = $false
    $mutex = New-Object System.Threading.Mutex($true, ("Local\" + $name), [ref]$first)
    $show = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, ("Local\" + $name + "-show"))
    if (-not $first) {
        [void]$show.Set()
        $show.Dispose(); $mutex.Dispose()
        Write-Output "The decisions window is already open; it was asked to come forward."
        return
    }
    try {
        $surface = Resolve-HordeSurface -Requires $script:HordeDecisionWindowNeeds
        if ($null -eq $surface) { throw "no way of showing a window is part of this Horde on this machine, so the decisions window cannot be opened; horde decisions list prints the same list" }
        $attachment = Resolve-HordeDecisionWindowAttachment -Hidden:$Hidden
        $state = New-HordeDecisionWindowState -ReportPath $reportPath -Attachment $attachment -PicturePath $picturePath
        if ($picturePath -ne "" -and -not (Test-HordeSurfaceCapability -Surface $surface -Capability "picture")) { throw "the way this Horde shows a window here cannot save a picture of it, so -Picture cannot be honoured" }
        $state.showEvent = $show
        $script:HordeDecisionWindow = $state
        $root = Split-Path -Parent $PSScriptRoot
        $specArgs = @{
            Title = "Open decisions"; Start = "window/index.html"; Bridge = $state.bridge; State = $state
            Mounts = ([ordered]@{ window = (Join-Path $PSScriptRoot "window"); list = (Join-Path $PSScriptRoot "page"); fleet = (Join-Path $root "fleet\panel") })
            DataFolder = (Join-Path (Join-Path $hordeHome "cache") "decisions-window")
            OnOpened = { param($Window, $State) Invoke-HordeDecisionWindowOpened -Window $Window -State $State }
            OnTick = { param($Window, $State) Invoke-HordeDecisionWindowTick -Window $Window -State $State }
            OnClosed = { param($Window, $State) Invoke-HordeDecisionWindowClosed -Window $Window -State $State }
        }
        if ($Hidden) { $specArgs["Hidden"] = $true }
        if ($attachment.attached) {
            # Where it will stand, worked out before it is shown, so that it does not first appear
            # mid-screen and then jump. Real pixels first, or the rectangle read is a scaled one.
            [void](Enable-HordeWindowRealPixels)
            $beside = Get-HordeWindowRectangle -Handle $attachment.handle
            if ($null -ne $beside) {
                $at = Get-HordeWindowFollowPlacement -Target $beside -Dpi $beside.dpi
                $specArgs["Companion"] = $true; $specArgs["Left"] = $at.left; $specArgs["Top"] = $at.top
                $specArgs["Width"] = [Math]::Max($at.width, 200); $specArgs["Height"] = [Math]::Max($at.height, 150)
            }
            Write-Output ("Opening the decisions window beside the " + $script:HordeDecisionWindowRole + "'s terminal window. This command returns when the window is closed.")
        }
        else { Write-Output ("Opening the decisions window, standing free (not attached: " + $attachment.reason + "). This command returns when the window is closed.") }
        $spec = New-HordeSurfaceSpec @specArgs
        $result = Open-HordeSurface -Surface $surface -Spec $spec
        if ($result.state -cne "closed") { throw ("the decisions window could not be shown: " + $result.reason) }
        if ($state.reportPath -ne "") { try { Write-HordeDecisionWindowReport -State $state } catch { } }
        Write-Output "The decisions window was closed."
    }
    finally {
        $script:HordeDecisionWindow = $null
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose(); $show.Dispose()
    }
}
