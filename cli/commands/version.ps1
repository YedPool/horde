$HordeCommand = @{
    name    = "version"
    group   = "about"
    usage   = "version [-Json]"
    summary = "the version from the VERSION file, and the commit when this is a git checkout"
    run     = {
        [CmdletBinding()] param([switch]$Json)
        $root = Get-HordeRoot
        $version = "$(Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1)".Trim()
        # The commit is UNKNOWN outside a git checkout - an installed copy, or no git on PATH - and says
        # so, rather than printing nothing that could be read as "no commit".
        $commit = $null
        if ((Test-Path -LiteralPath (Join-Path $root ".git")) -and (Get-Command git -ErrorAction SilentlyContinue)) {
            $out = & git -C $root rev-parse --short HEAD
            if ($LASTEXITCODE -eq 0 -and "$out" -match '^[0-9a-f]{7,40}$') { $commit = "$out" }
        }
        if ($Json) {
            [pscustomobject]@{ version = $version; commit = $commit } | ConvertTo-Json -Compress
            return
        }
        Write-Output ("horde " + $version)
        if ($commit) { Write-Output ("commit " + $commit) } else { Write-Output "commit unknown (not a git checkout)" }
    }
}
