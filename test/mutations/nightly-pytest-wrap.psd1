# Mutations of tools/nightly/pytest-wrap.ps1, the nightly net's pytest wrapper: its own --basetemp (T-0331, 2026-10-27).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-pytest-wrap.psd1
@{
    Target = "tools\nightly\pytest-wrap.ps1"
    Suite  = "test\test-nightly-net.ps1"
    Mutations = @(
        @{ Name = "nodes-mode-uses-the-shared-temp"
           Find = '& python -m pytest -q -p no:cacheprovider $baseTempArg @nodes'
           Replace = '& python -m pytest -q -p no:cacheprovider @nodes' }
        @{ Name = "all-mode-uses-the-shared-temp"
           Find = '$lines = @(& python -m pytest -q -p no:cacheprovider $baseTempArg --ignore=$Ignore'
           Replace = '$lines = @(& python -m pytest -q -p no:cacheprovider --ignore=$Ignore' }
        @{ Name = "basetemp-is-not-unique"
           Find = '("pytest-tmp-" + $PID + "-" + [guid]::NewGuid().ToString("N").Substring(0, 8))'
           Replace = '"pytest-tmp"' }
        @{ Name = "basetemp-in-the-shared-pytest-of-folder"
           Find = '$tmpParent = Split-Path -Parent ([System.IO.Path]::GetFullPath($NodesFile))'
           Replace = '$tmpParent = Join-Path ([System.IO.Path]::GetTempPath()) ("pytest-of-" + $env:USERNAME)' }
    )
}
