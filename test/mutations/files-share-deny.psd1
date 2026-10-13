# Mutations of files/Share.ps1, where a share asks the deny list and the drive-letter question. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-share-deny.psd1
# Each stops the share asking, asks of the path that was written instead of the open handle's own,
# or drops what the caller handed in; test\test-files-deny.ps1 must fail for every one. The rest of
# files/Share.ps1 is in test\mutations\files-share.psd1, against the store's suite.
@{
    Target = "files\Share.ps1"
    Suite  = "test\test-files-deny.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "deny-list-not-asked"
           Find = 'if ($denied -ne "") { return (& $refuse $denied) }'
           Replace = '' }
        # F's condition: every rule judges the final path of the open handle, never the typed path.
        @{ Name = "deny-list-asked-of-the-path-that-was-written"
           Find = '$denied = Get-HordeFilesDenyRefusal -FinalPath $real '
           Replace = '$denied = Get-HordeFilesDenyRefusal -FinalPath $full ' }
        @{ Name = "deny-list-asked-of-the-ambient-home"
           Find = '-FinalPath $real -HordeHome $HordeHome -RepoRoot $RepoRoot'
           Replace = '-FinalPath $real -RepoRoot $RepoRoot' }
        @{ Name = "deny-list-reads-the-real-harnesses-whatever-is-given"
           Find = '-FinalPath $real -HordeHome $HordeHome -RepoRoot $RepoRoot'
           Replace = '-FinalPath $real -HordeHome $HordeHome' }
        @{ Name = "force-not-handed-to-the-deny-list"
           Find = '-RepoRoot $RepoRoot -Force:$Force'
           Replace = '-RepoRoot $RepoRoot' }
        @{ Name = "force-handed-to-the-deny-list-whatever-was-said"
           Find = '-RepoRoot $RepoRoot -Force:$Force'
           Replace = '-RepoRoot $RepoRoot -Force' }
        # The letter that stands for a network drive: asked first, of the path as written and of
        # the path it resolves to. Without the first, the share is still refused, by the second -
        # but only after the network question asked the letter's type, which looks the host up.
        @{ Name = "written-path-not-asked-what-its-letter-stands-for"
           Find = '$unfit = Get-HordeFilesAliasRefusal -Path $Path'
           Replace = '$unfit = ""' }
        @{ Name = "resolved-path-not-asked-what-its-letter-stands-for"
           Find = '$network = Get-HordeFilesAliasRefusal -Path $full'
           Replace = '$network = ""' }
    )
}
