# The local relay's fixture for test/test-relay-conformance.ps1 (the contract is in that suite's
# header). Each state is a new empty folder under the temp folder, the relay's root; Remove deletes it
# and nothing else.
param([Parameter(Mandatory = $true)][string]$Root)
return [pscustomobject]@{
    New = {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-relay-conf-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
        [void][System.IO.Directory]::CreateDirectory($dir)
        return [pscustomobject]@{ root = $dir; options = @{ root = $dir } }
    }
    Remove = {
        param($State)
        if ($State.root -like "*horde-relay-conf-*" -and [System.IO.Directory]::Exists($State.root)) { Remove-Item -LiteralPath $State.root -Recurse -Force }
    }
}
