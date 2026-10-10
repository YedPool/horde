# Mutations of surfaces/pwa/Site.ps1, the phone app's site assembler. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-site.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\Site.ps1"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "relay-origin-not-written-into-the-policy"
           Find = '$connect = $script:'
           Replace = '$connect = "connect-src ''self''"; $unused = $script:' }
        @{ Name = "full-folder-written-into"
           Find = 'GetFileSystemEntries($outFull)).Count -gt 0)'
           Replace = 'GetFileSystemEntries($outFull)).Count -lt 0)' }
        @{ Name = "plain-http-origin-taken"
           Find = '\A(https://[a-z0-9]'
           Replace = '\A(https?://[a-z0-9]' }
        @{ Name = "worker-caches-itself"
           Find = 'Where-Object { $_ -cne "app/sw.js" -and $_ -cne "index.html" } | Sort-Object)'
           Replace = 'Where-Object { $_ -cne "index.html" } | Sort-Object)' }
        @{ Name = "version-not-from-the-files"
           Find = '$all.Write($bytes[$p], 0, $bytes[$p].Length)'
           Replace = '$null = $p' }
    )
}
