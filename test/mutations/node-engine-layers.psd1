# Mutations of core/NodeEngineLayers.ps1, the one engine-layer reader. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\node-engine-layers.psd1
# test\test-node-engine-layers.ps1 must fail for every one. Each lets a file the owner cannot have meant
# be read, or dropped without a problem, or reported without its cause.
@{
    Target = "core\NodeEngineLayers.ps1"
    Suite  = "test\test-node-engine-layers.ps1"
    Mutations = @(
        @{ Name = "bytes-unchecked"
           Find = 'try { Assert-HordeAsciiBytes -Bytes $bytes -What $path }'
           Replace = 'try { }' }
        @{ Name = "not-ascii-dropped"
           Find = 'catch { [void]$problems.Add($path + ": not ASCII - " + $_.Exception.Message); continue }'
           Replace = 'catch { continue }' }
        @{ Name = "parse-reason-generic"
           Find = 'catch { [void]$problems.Add($path + ": not JSON - " + $_.Exception.Message) }'
           Replace = 'catch { [void]$problems.Add($path + ": not JSON") }' }
        @{ Name = "not-json-dropped"
           Find = 'catch { [void]$problems.Add($path + ": not JSON - " + $_.Exception.Message) }'
           Replace = 'catch { }' }
        @{ Name = "findings-dropped"
           Find = 'foreach ($f in $findings) { [void]$problems.Add($f.source + " " + $f.path + ": " + $f.code + " - " + $f.detail) }'
           Replace = '' }
        @{ Name = "live-layer-unread"
           Find = 'foreach ($pair in @(@("L1", "engine.json"), @("L4", "engine-live.json"))) {'
           Replace = 'foreach ($pair in @(,@("L1", "engine.json"))) {' }
        @{ Name = "policy-not-read"
           Find = '    $policy = Get-HordeNodePolicy -Path (Get-HordeNodePolicyPath -HordeHome $HordeHome)'
           Replace = '    $policy = New-HordeKnown -Value $null' }
    )
}
